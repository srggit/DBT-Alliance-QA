/**
 * ReviewerInvitationReminderBatch
 * ---------------------------------
 * Daily job: finds Reviewer_Mapping__c records where exactly 3 days have
 * passed since the invitation was sent (Invitation_Sent_Date__c, a formula
 * field = DATE(CreatedDate)) and the reviewer has not yet responded
 * (Invitation_Responded__c = false).
 *
 * For each such record (only ever once, via Invitation_Reminder_Sent__c):
 *   - Sends a reminder email using the Classic Email Template
 *     "Reviewer_Invitation_Reminder" (DeveloperName), merged against the
 *     Reviewer_Mapping__c record via WhatId. No HTML is hardcoded in Apex -
 *     edit the template in Setup to change wording/styling.
 *   - Creates a Notification__c record as a "reminder" tied to the Reviewer.
 *
 * IMPORTANT - single WhatId tradeoff: Reviewer__c is a custom object, not a
 * Contact/Lead/User, so {!Contact.*} merges can't resolve to the actual
 * reviewer - the template uses {!Reviewer_Mapping__c.Reviewer_Name__c}
 * instead. setTargetObjectId() is set to the running user purely to satisfy
 * the API's requirement for a target object; it has no bearing on who
 * receives the email (setToAddresses() controls that). WhatId can only
 * reference ONE related record, so it points at Reviewer_Mapping__c (richer
 * field set: Deadline_Date__c, Scheme_Name__c, Reviewer_Type__c,
 * Application_Stages__c, Status__c) - this means Proposal__c.Project_Title__c
 * can NOT merge into this email, since that field only lives on Proposal.
 * setSaveAsActivity(false) is required since there's no valid Contact/Lead
 * WhoId to log the email against.
 *
 * Kicked off daily by ReviewerInvitationReminderScheduler.
 */
public class ReviewerInvitationReminderBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer REMINDER_DAYS_AFTER_INVITE = 0;
    private static final String EMAIL_TEMPLATE_DEV_NAME = 'Reviewer_Invitation_Reminder';
    // ASSUMPTION: Notification__c.Expiry_Date__c - how long the reminder
    // notification stays "active"/visible. Adjust if your UI treats this
    // differently.
    private static final Integer NOTIFICATION_EXPIRY_DAYS = 7;

    public Integer remindedCount = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date reminderThresholdDate = Date.today().addDays(-REMINDER_DAYS_AFTER_INVITE);

        return Database.getQueryLocator([
            SELECT Id, Reviewer__c, Reviewer__r.Email_Address__c, Reviewer_Name__c,
                   Proposal__c, Proposal_Id__c, Proposal__r.Project_Title__c,
                   Invitation_Sent_Date__c, Invitation_Responded__c,
                   Application_Stages__c, Status__c, Deadline_Date__c,
                   Scheme_Name__c, Reviewer_Type__c
            FROM Reviewer_Mapping__c
            WHERE Invitation_Responded__c = false
            AND Invitation_Reminder_Sent__c = false
            AND Invitation_Sent_Date__c = :reminderThresholdDate
            AND Reviewer__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Reviewer_Mapping__c> scope) {

        EmailTemplate template;
        try {
            template = [
                SELECT Id
                FROM EmailTemplate
                WHERE DeveloperName = :EMAIL_TEMPLATE_DEV_NAME
                LIMIT 1
            ];
        } catch (QueryException qe) {
            System.debug('Email Template "' + EMAIL_TEMPLATE_DEV_NAME + '" not found - no reminder emails will be sent this run: ' + qe.getMessage());
            template = null;
        }

        Id runningUserId = UserInfo.getUserId(); // satisfies setTargetObjectId() requirement only - not the actual recipient

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        List<Notification__c> notificationsToInsert = new List<Notification__c>();
        List<Reviewer_Mapping__c> mappingsToUpdate = new List<Reviewer_Mapping__c>();

        for (Reviewer_Mapping__c rm : scope) {

            String reviewerEmail = (rm.Reviewer__r != null) ? rm.Reviewer__r.Email_Address__c : null;
            String proposalId = String.isNotBlank(rm.Proposal_Id__c) ? rm.Proposal_Id__c : String.valueOf(rm.Proposal__c);
            String projectTitle = (rm.Proposal__r != null) ? rm.Proposal__r.Project_Title__c : '';
            String sentDateStr = (rm.Invitation_Sent_Date__c != null) ? rm.Invitation_Sent_Date__c.format() : '';
            String deadlineDateStr = (rm.Deadline_Date__c != null) ? rm.Deadline_Date__c.format() : 'Not set';

            if (template != null && String.isNotBlank(reviewerEmail)) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(template.Id);
                mail.setTargetObjectId(runningUserId);
                mail.setWhatId(rm.Id); // drives {!Reviewer_Mapping__c.*} merge fields in the template
                mail.setToAddresses(new String[]{ reviewerEmail });
                mail.setSaveAsActivity(false); // required - Reviewer__c is not a Contact/Lead
                emailsToSend.add(mail);
            } else if (template == null) {
                System.debug('Skipping email for Reviewer Mapping ' + rm.Id + ' - Email Template not found.');
            } else {
                System.debug('Skipping email for Reviewer Mapping ' + rm.Id + ' - Reviewer has no Email_Address__c.');
            }

            Notification__c notif = new Notification__c();
            notif.Reviewer__c = rm.Reviewer__c;
            notif.Title__c = 'Reviewer Invitation Reminder - ' + proposalId;
            notif.Description__c = 'You were invited to review Proposal ' + proposalId +
                (String.isNotBlank(projectTitle) ? ' ("' + projectTitle + '")' : '') +
                ' on ' + sentDateStr + ' and have not yet responded.' +
                (rm.Deadline_Date__c != null ? ' Review deadline: ' + deadlineDateStr + '.' : '') +
                ' Please log in to accept or decline this review invitation.';
            notif.Expiry_Date__c = Date.today().addDays(NOTIFICATION_EXPIRY_DAYS);
            notif.For_All__c = false;
            notificationsToInsert.add(notif);

            rm.Invitation_Reminder_Sent__c = true;
            mappingsToUpdate.add(rm);
        }

        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend, false);
        }
        if (!notificationsToInsert.isEmpty()) {
            insert notificationsToInsert;
        }
        if (!mappingsToUpdate.isEmpty()) {
            update mappingsToUpdate;
        }

        remindedCount += mappingsToUpdate.size();
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Reviewer Invitation Reminder Batch complete. Reminders sent: ' + remindedCount);
    }
}





/**
 * ReviewerInvitationReminderBatch
 * ---------------------------------
 * Daily job: finds Reviewer_Mapping__c records where exactly 3 days have
 * passed since the invitation was sent (Invitation_Sent_Date__c, a formula
 * field = DATE(CreatedDate)) and the reviewer has not yet responded
 * (Invitation_Responded__c = false).
 *
 * For each such record (only ever once, via Invitation_Reminder_Sent__c):
 *   - Sends a reminder email using the Classic Email Template
 *     "Reviewer_Invitation_Reminder" (DeveloperName), merged against the
 *     Reviewer_Mapping__c record via WhatId. No HTML is hardcoded in Apex -
 *     edit the template in Setup to change wording/styling.
 *   - Creates a Notification__c record as a "reminder" tied to the Reviewer.
 *
 * IMPORTANT - single WhatId tradeoff: Reviewer__c is a custom object, not a
 * Contact/Lead/User, so {!Contact.*} merges can't resolve to the actual
 * reviewer - the template uses {!Reviewer_Mapping__c.Reviewer_Name__c}
 * instead. setTargetObjectId() MUST point at a Contact or Lead (Salesforce
 * rejects setWhatId() combined with a User target with error
 * INVALID_ID_FIELD - "WhatId is not available for sending emails to
 * UserIds"), so this class queries a dedicated placeholder Contact
 * (LastName = 'EmailMergeContext') purely to satisfy that requirement - it
 * has no bearing on who actually receives the email (setToAddresses() does).
 * WhatId can only reference ONE related record, so it points at
 * Reviewer_Mapping__c (richer field set: Deadline_Date__c, Scheme_Name__c,
 * Reviewer_Type__c, Application_Stages__c, Status__c) - this means
 * Proposal__c.Project_Title__c can NOT merge into this email, since that
 * field only lives on Proposal.
 * setSaveAsActivity(false) is required since there's no valid Contact/Lead
 * WhoId to log the email against.
 *
 * Kicked off daily by ReviewerInvitationReminderScheduler.
 */
// public class ReviewerInvitationReminderBatch implements Database.Batchable<SObject>, Database.Stateful {

//     private static final Integer REMINDER_DAYS_AFTER_INVITE = 0;
//     private static final String EMAIL_TEMPLATE_DEV_NAME = 'Reviewer_Invitation_Reminder';
//     // ASSUMPTION: Notification__c.Expiry_Date__c - how long the reminder
//     // notification stays "active"/visible. Adjust if your UI treats this
//     // differently.
//     private static final Integer NOTIFICATION_EXPIRY_DAYS = 7;

//     public Integer remindedCount = 0;

//     public Database.QueryLocator start(Database.BatchableContext bc) {
//         Date reminderThresholdDate = Date.today().addDays(-REMINDER_DAYS_AFTER_INVITE);

//         return Database.getQueryLocator([
//             SELECT Id, Reviewer__c, Reviewer__r.Email_Address__c, Reviewer_Name__c,
//                    Proposal__c, Proposal_Id__c, Proposal__r.Project_Title__c,
//                    Invitation_Sent_Date__c, Invitation_Responded__c,
//                    Application_Stages__c, Status__c, Deadline_Date__c,
//                    Scheme_Name__c, Reviewer_Type__c
//             FROM Reviewer_Mapping__c
//             WHERE Invitation_Responded__c = false
//             AND Invitation_Reminder_Sent__c = false
//             AND Invitation_Sent_Date__c = :reminderThresholdDate
//             AND Reviewer__c != null
//         ]);
//     }

//     public void execute(Database.BatchableContext bc, List<Reviewer_Mapping__c> scope) {

//         EmailTemplate template;
//         try {
//             template = [
//                 SELECT Id
//                 FROM EmailTemplate
//                 WHERE DeveloperName = :EMAIL_TEMPLATE_DEV_NAME
//                 LIMIT 1
//             ];
//         } catch (QueryException qe) {
//             System.debug('Email Template "' + EMAIL_TEMPLATE_DEV_NAME + '" not found - no reminder emails will be sent this run: ' + qe.getMessage());
//             template = null;
//         }

//         // targetObjectId MUST be a Contact or Lead for setWhatId() merges to be
//         // allowed - Salesforce rejects the combination outright when the target
//         // is a User ("WhatId is not available for sending emails to UserIds").
//         // Reviewer__c has no Contact of its own, so this placeholder Contact
//         // exists purely to satisfy that requirement - it has no bearing on who
//         // actually receives the email (setToAddresses() controls that).
//         // SETUP REQUIRED: create one Contact with LastName = 'EmailMergeContext'
//         // (any Account/other fields your org requires) and leave it alone.
//         Id placeholderContactId;
//         try {
//             placeholderContactId = [
//                 SELECT Id FROM Contact WHERE LastName = 'EmailMergeContext' LIMIT 1
//             ].Id;
//         } catch (QueryException qe) {
//             placeholderContactId = null;
//             System.debug('Placeholder Contact "EmailMergeContext" not found - no reminder emails will be sent this run: ' + qe.getMessage());
//         }

//         List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
//         List<Notification__c> notificationsToInsert = new List<Notification__c>();
//         List<Reviewer_Mapping__c> mappingsToUpdate = new List<Reviewer_Mapping__c>();

//         for (Reviewer_Mapping__c rm : scope) {

//             String reviewerEmail = (rm.Reviewer__r != null) ? rm.Reviewer__r.Email_Address__c : null;
//             String proposalId = String.isNotBlank(rm.Proposal_Id__c) ? rm.Proposal_Id__c : String.valueOf(rm.Proposal__c);
//             String projectTitle = (rm.Proposal__r != null) ? rm.Proposal__r.Project_Title__c : '';
//             String sentDateStr = (rm.Invitation_Sent_Date__c != null) ? rm.Invitation_Sent_Date__c.format() : '';
//             String deadlineDateStr = (rm.Deadline_Date__c != null) ? rm.Deadline_Date__c.format() : 'Not set';

//             if (template != null && placeholderContactId != null && String.isNotBlank(reviewerEmail)) {
//                 Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
//                 mail.setTemplateId(template.Id);
//                 mail.setTargetObjectId(placeholderContactId);
//                 mail.setWhatId(rm.Id); // drives {!Reviewer_Mapping__c.*} merge fields in the template
//                 mail.setToAddresses(new String[]{ reviewerEmail });
//                 mail.setSaveAsActivity(false); // required - Reviewer__c is not a Contact/Lead
//                 emailsToSend.add(mail);
//             } else if (template == null) {
//                 System.debug('Skipping email for Reviewer Mapping ' + rm.Id + ' - Email Template not found.');
//             } else if (placeholderContactId == null) {
//                 System.debug('Skipping email for Reviewer Mapping ' + rm.Id + ' - placeholder Contact not found.');
//             } else {
//                 System.debug('Skipping email for Reviewer Mapping ' + rm.Id + ' - Reviewer has no Email_Address__c.');
//             }

//             Notification__c notif = new Notification__c();
//             notif.Reviewer__c = rm.Reviewer__c;
//             notif.Title__c = 'Reviewer Invitation Reminder - ' + proposalId;
//             notif.Description__c = 'You were invited to review Proposal ' + proposalId +
//                 (String.isNotBlank(projectTitle) ? ' ("' + projectTitle + '")' : '') +
//                 ' on ' + sentDateStr + ' and have not yet responded.' +
//                 (rm.Deadline_Date__c != null ? ' Review deadline: ' + deadlineDateStr + '.' : '') +
//                 ' Please log in to accept or decline this review invitation.';
//             notif.Expiry_Date__c = Date.today().addDays(NOTIFICATION_EXPIRY_DAYS);
//             notif.For_All__c = false;
//             notificationsToInsert.add(notif);

//             rm.Invitation_Reminder_Sent__c = true;
//             mappingsToUpdate.add(rm);
//         }

//         if (!emailsToSend.isEmpty()) {
//             List<Messaging.SendEmailResult> results = Messaging.sendEmail(emailsToSend, false);
//             for (Messaging.SendEmailResult result : results) {
//                 if (!result.isSuccess()) {
//                     for (Messaging.SendEmailError err : result.getErrors()) {
//                         System.debug('Reminder email failed: ' + err.getStatusCode() + ' - ' + err.getMessage());
//                     }
//                 }
//             }
//         }
//         if (!notificationsToInsert.isEmpty()) {
//             insert notificationsToInsert;
//         }
//         if (!mappingsToUpdate.isEmpty()) {
//             update mappingsToUpdate;
//         }

//         remindedCount += mappingsToUpdate.size();
//     }

//     public void finish(Database.BatchableContext bc) {
//         System.debug('Reviewer Invitation Reminder Batch complete. Reminders sent: ' + remindedCount);
//     }
// }