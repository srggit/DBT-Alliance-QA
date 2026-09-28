public with sharing class GrantsTeamResponseHandler {

    /*
     * Eligibility is decided as soon as this many Grants_Team_Members__c
     * responses have been Submitted for the stage - it does not wait for
     * every member assigned to the scheme to respond.
     */
    private static final Integer PRELIMS_REQUIRED_RESPONSES = 2;
    private static final Integer FULL_REQUIRED_RESPONSES = 2;

    // The required counts above are only the defaults - each Yearly Scheme can override them via
    // Prelim_Grants_Responses_Required__c / Full_Grants_Responses_Required__c (blank = default).
    private static Integer requiredResponses(Proposal__c proposal, Boolean prelims) {
        Decimal configured = null;
        if (proposal != null && proposal.Yearly_Scheme__r != null) {
            configured = prelims
                ? proposal.Yearly_Scheme__r.Prelim_Grants_Responses_Required__c
                : proposal.Yearly_Scheme__r.Full_Grants_Responses_Required__c;
        }
        if (configured != null) {
            return Integer.valueOf(configured);
        }
        return prelims ? PRELIMS_REQUIRED_RESPONSES : FULL_REQUIRED_RESPONSES;
    }

    public static void updateProposalStatus(List<Grants_Team_Response__c> newResponses, Map<Id, Grants_Team_Response__c> oldMap) {
        Set<Id> prelimProposalIds = new Set<Id>();
        Set<Id> fullProposalIds = new Set<Id>();

        // Grants Team Members are no longer split by stage, so a response's own Stage__c can
        // no longer be used to bucket it - instead react to whichever of the response's own
        // Eligible_For_Prelim__c/Eligible_For_Full__c fields (set independently, per stage, by
        // GrantTeamResponseItemsController as that stage's items are answered) just became decided.
        for (Grants_Team_Response__c resp : newResponses) {
            Grants_Team_Response__c oldResp = oldMap.get(resp.Id);
            if (oldResp == null) {
                continue;
            }
            Boolean prelimJustDecided = resp.Eligible_For_Prelim__c != oldResp.Eligible_For_Prelim__c &&
                (resp.Eligible_For_Prelim__c == 'Eligible' || resp.Eligible_For_Prelim__c == 'Not Eligible');
            if (prelimJustDecided) {
                prelimProposalIds.add(resp.Proposal__c);
            }
            Boolean fullJustDecided = resp.Eligible_For_Full__c != oldResp.Eligible_For_Full__c &&
                (resp.Eligible_For_Full__c == 'Eligible' || resp.Eligible_For_Full__c == 'Not Eligible');
            if (fullJustDecided) {
                fullProposalIds.add(resp.Proposal__c);
            }
        }

        if (prelimProposalIds.isEmpty() && fullProposalIds.isEmpty()) {
            return;
        }

        Set<Id> allProposalIds = new Set<Id>();
        allProposalIds.addAll(prelimProposalIds);
        allProposalIds.addAll(fullProposalIds);

        // Eligibility is locked once decided, so skip stages that already have an outcome.
        Map<Id, Proposal__c> proposalsById = new Map<Id, Proposal__c>([
            SELECT Id, Eligible_For_Prelim__c, Eligible_For_Full__c, Proposal_Status__c,
                   Yearly_Scheme__r.Prelim_Grants_Responses_Required__c,
                   Yearly_Scheme__r.Full_Grants_Responses_Required__c
            FROM Proposal__c
            WHERE Id IN :allProposalIds
        ]);

        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();

        // --- Prelims: unchanged - wait for PRELIMS_REQUIRED_RESPONSES submissions, take the
        // first N (earliest submitted) and all N must say Eligible. ---
        if (!prelimProposalIds.isEmpty()) {
            Map<Id, List<Grants_Team_Response__c>> prelimResponsesByProposal = new Map<Id, List<Grants_Team_Response__c>>();
            for (Grants_Team_Response__c resp : [
                SELECT Id, Proposal__c, Eligible_For_Prelim__c
                FROM Grants_Team_Response__c
                WHERE Proposal__c IN :prelimProposalIds
                AND Eligible_For_Prelim__c IN ('Eligible', 'Not Eligible')
                ORDER BY LastModifiedDate ASC
            ]) {
                if (!prelimResponsesByProposal.containsKey(resp.Proposal__c)) {
                    prelimResponsesByProposal.put(resp.Proposal__c, new List<Grants_Team_Response__c>());
                }
                prelimResponsesByProposal.get(resp.Proposal__c).add(resp);
            }

            for (Id proposalId : prelimResponsesByProposal.keySet()) {
                String currentValue = proposalsById.get(proposalId).Eligible_For_Prelim__c;
                Boolean alreadyDecided = currentValue == 'Eligible' || currentValue == 'Not Eligible';
                if (alreadyDecided) {
                    continue;
                }

                List<Grants_Team_Response__c> submitted = prelimResponsesByProposal.get(proposalId);
                Integer requiredPrelims = requiredResponses(proposalsById.get(proposalId), true);
                if (submitted.size() < requiredPrelims) {
                    // Threshold not reached yet - wait for more submissions.
                    continue;
                }

                String eligibility = 'Eligible';
                for (Integer i = 0; i < requiredPrelims; i++) {
                    if (submitted[i].Eligible_For_Prelim__c != 'Eligible') {
                        eligibility = 'Not Eligible';
                        break;
                    }
                }

                proposalsToUpdate.add(new Proposal__c(Id = proposalId, Eligible_For_Prelim__c = eligibility));
            }
        }

        // --- Full: same "first N chronological responses decide" shape as Prelims above -
        // wait for FULL_REQUIRED_RESPONSES submissions, take the first N (earliest submitted
        // by LastModifiedDate) and all N must say Eligible. Only sets Eligible_For_Full__c here -
        // ProposalTriggerHandler.advanceToPeerReviewOnFullEligible reacts to that field itself
        // to advance Proposal_Status__c to 'Peer Review', so it also catches a direct/manual
        // edit to the field, not just this automation. Locked once decided either way. ---
        if (!fullProposalIds.isEmpty()) {
            Map<Id, List<Grants_Team_Response__c>> fullResponsesByProposal = new Map<Id, List<Grants_Team_Response__c>>();
            for (Grants_Team_Response__c resp : [
                SELECT Id, Proposal__c, Eligible_For_Full__c
                FROM Grants_Team_Response__c
                WHERE Proposal__c IN :fullProposalIds
                AND Eligible_For_Full__c IN ('Eligible', 'Not Eligible')
                ORDER BY LastModifiedDate ASC
            ]) {
                if (!fullResponsesByProposal.containsKey(resp.Proposal__c)) {
                    fullResponsesByProposal.put(resp.Proposal__c, new List<Grants_Team_Response__c>());
                }
                fullResponsesByProposal.get(resp.Proposal__c).add(resp);
            }

            for (Id proposalId : fullResponsesByProposal.keySet()) {
                String currentValue = proposalsById.get(proposalId).Eligible_For_Full__c;
                Boolean alreadyDecided = currentValue == 'Eligible' || currentValue == 'Not Eligible';
                if (alreadyDecided) {
                    continue;
                }

                List<Grants_Team_Response__c> submitted = fullResponsesByProposal.get(proposalId);
                Integer requiredFull = requiredResponses(proposalsById.get(proposalId), false);
                if (submitted.size() < requiredFull) {
                    // Threshold not reached yet - wait for more submissions.
                    continue;
                }

                String eligibility = 'Eligible';
                for (Integer i = 0; i < requiredFull; i++) {
                    if (submitted[i].Eligible_For_Full__c != 'Eligible') {
                        eligibility = 'Not Eligible';
                        break;
                    }
                }

                proposalsToUpdate.add(new Proposal__c(Id = proposalId, Eligible_For_Full__c = eligibility));
            }
        }

        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }
    public static void grantTeamMemberChange(List<Grants_Team_Response__c> newList, Map<Id, Grants_Team_Response__c> oldMap, Boolean isBefore) {
        System.debug('grantTeamMemberChange: START - isBefore=' + isBefore + ', recordCount=' + newList.size());
    
        List<Id> proposalIdsToNotify = new List<Id>();
        
        for (Grants_Team_Response__c gtr : newList) {
            Grants_Team_Response__c oldGtr = oldMap.get(gtr.Id);
            
            // Check if the Grants Team Member field was changed
            if (gtr.Grants_Team_Members__c != oldGtr.Grants_Team_Members__c) {
                System.debug('grantTeamMemberChange: Grants_Team_Members__c changed on Id=' + gtr.Id
                    + ' oldValue=' + oldGtr.Grants_Team_Members__c
                    + ' newValue=' + gtr.Grants_Team_Members__c);
    
                if (isBefore) {
                    // BEFORE UPDATE LOGIC: Validation Error
                    if (gtr.Status__c == 'Submitted' || oldGtr.Status__c == 'Submitted') {
                        System.debug('grantTeamMemberChange: BLOCKED - Id=' + gtr.Id
                            + ' currentStatus=' + gtr.Status__c
                            + ' oldStatus=' + oldGtr.Status__c);
                        gtr.addError('You cannot change Grant Team Member. Grant Team Response already submitted.');
                    }
                } else {
                    // AFTER UPDATE LOGIC: Collect proposals for notification
                    if (gtr.Status__c != 'Submitted' && gtr.Proposal__c != null) {
                        System.debug('grantTeamMemberChange: Queuing Proposal__c=' + gtr.Proposal__c + ' for notification');
                        proposalIdsToNotify.add(gtr.Proposal__c);
                    }
                }
            }
        }
        
        System.debug('grantTeamMemberChange: proposalIdsToNotify=' + proposalIdsToNotify);
    
        // If we are in the After Update context and have valid proposals, send the notification
        if (!isBefore && !proposalIdsToNotify.isEmpty()) {
            System.debug('grantTeamMemberChange: Calling sendNotifications with ' + proposalIdsToNotify.size() + ' proposal(s)');
            GrantsTeamResponseHandler.sendNotifications(proposalIdsToNotify); 
        }
    
        System.debug('grantTeamMemberChange: END');
    }
    
    private static final String NOTIFICATION_TYPE_DEVELOPER_NAME = 'Bulk_Eligibility_Check_Alert';
    private static final String EMAIL_TEMPLATE_DEVELOPER_NAME = 'Bulk_Eligibility_Check_Notification'; 

    
    public static void sendNotifications(List<Id> proposalIds) {
        System.debug('sendNotifications: START - proposalIds=' + proposalIds);
    
        if (proposalIds == null || proposalIds.isEmpty()) {
            System.debug('sendNotifications: ERROR - proposalIds is null or empty');
            throw new AuraHandledException('Select at least one Proposal.');
        }
    
        List<CustomNotificationType> notifTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_DEVELOPER_NAME
            LIMIT 1
        ];
        System.debug('sendNotifications: notifTypes found=' + notifTypes.size());
        if (notifTypes.isEmpty()) {
            System.debug('sendNotifications: ERROR - notification type not configured: ' + NOTIFICATION_TYPE_DEVELOPER_NAME);
            throw new AuraHandledException('Bulk Eligibility Check notification type is not configured.');
        }
        Id notificationTypeId = notifTypes[0].Id;
        System.debug('sendNotifications: notificationTypeId=' + notificationTypeId);
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate WHERE DeveloperName = :EMAIL_TEMPLATE_DEVELOPER_NAME LIMIT 1
        ];
    	Id templateId = templates.isEmpty() ? null : templates[0].Id;
        if (templateId == null) {
            System.debug('sendNotifications: WARNING - Email Template not found: ' + EMAIL_TEMPLATE_DEVELOPER_NAME);
        }
        Map<Id, Proposal__c> proposals = new Map<Id, Proposal__c>([
            SELECT Id, Yearly_Scheme__c, Yearly_Scheme__r.Name
            FROM Proposal__c
            WHERE Id IN :proposalIds
            AND Yearly_Scheme__c != NULL
        ]);
        System.debug('sendNotifications: proposals found=' + proposals.size());
        if (proposals.isEmpty()) {
            System.debug('sendNotifications: ERROR - no Proposals with Yearly Scheme found for given Ids');
            throw new AuraHandledException('No Proposals with Yearly Scheme found.');
        }
    
        Set<Id> schemeIds = new Set<Id>();
        Map<Id, String> schemeNumberById = new Map<Id, String>();
        Map<Id, Id> schemeToProposalId = new Map<Id, Id>();
        for (Proposal__c p : proposals.values()) {
            schemeIds.add(p.Yearly_Scheme__c);
            schemeNumberById.put(p.Yearly_Scheme__c, p.Yearly_Scheme__r.Name);
            if (!schemeToProposalId.containsKey(p.Yearly_Scheme__c)) {
                schemeToProposalId.put(p.Yearly_Scheme__c, p.Id);
            }
        }
        System.debug('sendNotifications: schemeIds=' + schemeIds);
        System.debug('sendNotifications: schemeToProposalId=' + schemeToProposalId);
    
        Map<Id, Set<String>> schemeToUserIds = new Map<Id, Set<String>>();
        for (Grants_Team_Members__c member : [
            SELECT User__c, Yearly_Scheme__c
            FROM Grants_Team_Members__c
            WHERE Yearly_Scheme__c IN :schemeIds
            AND User__c != NULL
        ]) {
            if (!schemeToUserIds.containsKey(member.Yearly_Scheme__c)) {
                schemeToUserIds.put(member.Yearly_Scheme__c, new Set<String>());
            }
            schemeToUserIds.get(member.Yearly_Scheme__c).add(member.User__c);
        }
        System.debug('sendNotifications: schemeToUserIds=' + schemeToUserIds);
    
        Integer notifiedCount = 0;
         List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>(); // List to hold emails
        for (Id schemeId : schemeToUserIds.keySet()) {
            Set<String> recipientIds = schemeToUserIds.get(schemeId);
            if (recipientIds.isEmpty()) {
                System.debug('sendNotifications: schemeId=' + schemeId + ' has no recipientIds, skipping');
                continue;
            }
            
    
            String body = 'Bulk eligibility check requested for proposals under ' + schemeNumberById.get(schemeId) + '.';
            Id targetId = schemeToProposalId.containsKey(schemeId) ? schemeToProposalId.get(schemeId) : schemeId;
    
            System.debug('sendNotifications: Sending notification for schemeId=' + schemeId
                + ' targetId=' + targetId
                + ' recipientCount=' + recipientIds.size());
    
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Eligibility Check Assigned.');
            notification.setBody(body);
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(targetId);
    
            try {
                notification.send(recipientIds);
                notifiedCount++;
                System.debug('sendNotifications: SUCCESS for schemeId=' + schemeId + ' - notifiedCount now=' + notifiedCount);
            } catch (Exception ex) {
                System.debug('sendNotifications: ERROR sending notification for schemeId=' + schemeId + ' - ' + ex.getMessage());
                throw new AuraHandledException('Unable to send notification: ' + ex.getMessage());
            }
            if (templateId != null) {
                for (String userId : recipientIds) {
                    try {
                        // Workaround: We render the template in memory first to bypass the WhatId/User limit in Salesforce
                        Messaging.SingleEmailMessage renderedEmail = Messaging.renderStoredEmailTemplate(templateId, userId, schemeId);
                        
                        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                        mail.setTargetObjectId(userId);
                        mail.setSubject(renderedEmail.getSubject());
                        mail.setHtmlBody(renderedEmail.getHtmlBody());
                        mail.setPlainTextBody(renderedEmail.getPlainTextBody());
                        mail.setSaveAsActivity(false); // Must be false when sending to Users
                        
                        emailsToSend.add(mail);
                    } catch (Exception e) {
                        System.debug('sendNotifications: ERROR generating email for user ' + userId + ' - ' + e.getMessage());
                    }
                }
            }
        }
        if (!emailsToSend.isEmpty()) {
            try {
                // The false parameter ensures one failed email doesn't roll back the whole list
                Messaging.sendEmail(emailsToSend, false); 
                System.debug('sendNotifications: Emails sent successfully. Count: ' + emailsToSend.size());
            } catch (Exception ex) {
                System.debug('sendNotifications: ERROR sending emails - ' + ex.getMessage());
            }
        }
    
        System.debug('sendNotifications: END - notifiedCount=' + notifiedCount);
        if (notifiedCount == 0 && emailsToSend.isEmpty()) {
            System.debug('sendNotifications: ERROR - no notifications were sent');
            throw new AuraHandledException('No Grant Team Members found for the selected Proposals.');
        }
    }
    
}