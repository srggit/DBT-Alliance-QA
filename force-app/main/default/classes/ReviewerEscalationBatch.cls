/**
 * ReviewerEscalationBatch
 * ------------------------
 * Daily job: finds Reviewer_Mapping__c records where the reviewer has not
 * submitted their review (Status__c != 'Submitted') and the applicable
 * Yearly Scheme deadline (based on Application_Stages__c) has passed.
 *
 * For each overdue Reviewer Mapping (only escalated ONCE, ever):
 *   - Creates one standard Task per Active user with Profile Name = 'Admin',
 *     WhatId = the Proposal (so it shows on the Proposal record page).
 *   - Sends ONE Custom Notification (targeted at the Proposal record) to all
 *     Admin users at once.
 *
 * DUPLICATE-CHECK APPROACH: Relies solely on Escalation_Task_Created__c on
 * Reviewer_Mapping__c (set true after a successful escalation). The start()
 * query already excludes records where this flag is true, so a Reviewer
 * Mapping is only ever escalated once. No Task-side lookup or tag is used.
 *
 * Kicked off daily by ReviewerEscalationScheduler.
 */
public class ReviewerEscalationBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Maps Application_Stages__c value on Reviewer_Mapping__c to the
    // corresponding deadline field API name on Yearly_Schemes__c.
    // ASSUMPTION: 'Full' maps to Peer_Deadline_Date__c (only two deadline
    // fields exist for two stages). Confirm / adjust if incorrect.
    private static final Map<String, String> STAGE_TO_DEADLINE_FIELD = new Map<String, String>{
        'Prelims' => 'Prelim_Deadline_Date__c',
        'Full'    => 'Peer_Deadline_Date__c'
    };

    private static final String SUBMITTED_STATUS = 'Submitted';
    private static final String ADMIN_PROFILE_NAME = 'System Administrator';
    private static final String NOTIFICATION_TYPE_DEV_NAME = 'Reviewer_Escalation_Alert';

    public Integer escalatedCount = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Application_Stages__c, Status__c, Reviewer__c, Reviewer__r.Name, Reviewer_Name__c,
                   Proposal__c, Proposal__r.Name, Proposal_Id__c, Proposal__r.Yearly_Scheme__c,
                   Proposal__r.Yearly_Scheme__r.Prelim_Deadline_Date__c,
                   Proposal__r.Yearly_Scheme__r.Peer_Deadline_Date__c
            FROM Reviewer_Mapping__c
            WHERE Status__c != :SUBMITTED_STATUS
            AND Escalation_Task_Created__c = false
            AND Proposal__c != null
            AND Proposal__r.Yearly_Scheme__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Reviewer_Mapping__c> scope) {

        List<User> admins = [SELECT Id FROM User WHERE Profile.Name = :ADMIN_PROFILE_NAME AND IsActive = true];
        if (admins.isEmpty()) {
            System.debug('No active Admin-profile users found - skipping escalation for this batch.');
            return;
        }

        Set<Id> adminIds = new Set<Id>();
        Set<String> adminIdStrings = new Set<String>();
        for (User u : admins) {
            adminIds.add(u.Id);
            adminIdStrings.add(u.Id); // Messaging.CustomNotification.send() requires Set<String>, not Set<Id>
        }

        CustomNotificationType notifType;
        try {
            notifType = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE_DEV_NAME LIMIT 1];
        } catch (QueryException qe) {
            notifType = null; // Custom Notification Type not deployed yet - Tasks still get created
            System.debug('Custom Notification Type "' + NOTIFICATION_TYPE_DEV_NAME + '" not found: ' + qe.getMessage());
        }

        // First pass: figure out which Reviewer Mappings in this scope are
        // actually overdue right now (deadline passed, still unsubmitted).
        List<Reviewer_Mapping__c> overdueMappings = new List<Reviewer_Mapping__c>();
        Map<Id, Date> deadlineByMappingId = new Map<Id, Date>();
        Set<Id> proposalIds = new Set<Id>();

        for (Reviewer_Mapping__c rm : scope) {
            String deadlineField = STAGE_TO_DEADLINE_FIELD.get(rm.Application_Stages__c);
            if (deadlineField == null) {
                continue; // unrecognized stage value - skip
            }
            Date deadline = (Date) rm.Proposal__r.Yearly_Scheme__r.get(deadlineField);
            if (deadline == null || deadline >= Date.today()) {
                continue; // no deadline set, or not yet overdue
            }
            overdueMappings.add(rm);
            deadlineByMappingId.put(rm.Id, deadline);
            proposalIds.add(rm.Proposal__c);
        }

        if (overdueMappings.isEmpty()) {
            return;
        }

        List<Task> tasksToInsert = new List<Task>();
        List<Reviewer_Mapping__c> mappingsToUpdate = new List<Reviewer_Mapping__c>();

        for (Reviewer_Mapping__c rm : overdueMappings) {
            Date deadline = deadlineByMappingId.get(rm.Id);
            String reviewerName = (rm.Reviewer__c != null) ? rm.Reviewer_Name__c : 'Unknown Reviewer';
            String proposalName = (rm.Proposal__c != null) ? rm.Proposal_Id__c : String.valueOf(rm.Proposal__c);

            for (Id adminId : adminIds) {
                Task t = new Task();
                t.OwnerId      = adminId;
                t.WhatId       = rm.Proposal__c;
                t.Subject      = 'Escalation: Reviewer has not submitted review - ' + proposalName;
                t.Description  = 'Reviewer "' + reviewerName + '" has not submitted their ' +
                                  rm.Application_Stages__c + ' review for Proposal ' + proposalName +
                                  '. Deadline (' + deadline.format() + ') has passed.';
                t.ActivityDate = Date.today();
                t.Priority     = 'High';
                t.Status       = 'Not Started';
                tasksToInsert.add(t);
            }

            if (notifType != null) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('Reviewer Escalation: ' + proposalName);
                notification.setBody(reviewerName + ' has not submitted their ' +
                                      rm.Application_Stages__c + ' review. Deadline passed on ' +
                                      deadline.format() + '.');
                notification.setNotificationTypeId(notifType.Id);
                notification.setTargetId(rm.Proposal__c);
                try {
                    notification.send(adminIdStrings);
                } catch (Exception e) {
                    System.debug('Custom notification send failed for Proposal ' + proposalName + ': ' + e.getMessage());
                }
            }

            rm.Escalation_Task_Created__c = true;
            mappingsToUpdate.add(rm);
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
        if (!mappingsToUpdate.isEmpty()) {
            update mappingsToUpdate;
        }

        escalatedCount += mappingsToUpdate.size();
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Reviewer Escalation Batch complete. Escalated Reviewer Mapping records: ' + escalatedCount);
    }
}