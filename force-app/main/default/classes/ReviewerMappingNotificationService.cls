public class ReviewerMappingNotificationService {

    public static void process(List<Reviewer_Mapping__c> reviewerMappings) {
        // Get Admin users
        List<User> adminUsers = [ SELECT Id, Name FROM User WHERE Profile.Name = 'Admin' AND IsActive = true];
        if (adminUsers.isEmpty()) {
            return;
        }

        Set<String> adminIds = new Set<String>();
        List<Task> tasks = new List<Task>();
        for (User admin : adminUsers) {
            adminIds.add(String.valueOf(admin.Id));
            for (Reviewer_Mapping__c rm : reviewerMappings) {
                tasks.add(new Task(
                    OwnerId = admin.Id,
                    Subject = 'Reviewer Submitted',
                    Status = 'Not Started',
                    Priority = 'Normal',
                    WhatId = rm.Reviewer__c,
                    Description = 'Reviewer has been submitted and requires your attention.'
                ));
            }
        }
        if (!tasks.isEmpty()) {
            insert tasks;
        }
        sendNotification(adminIds, reviewerMappings);
    }

    private static void sendNotification(Set<String> userIds,List<Reviewer_Mapping__c> reviewerMappings) {
        CustomNotificationType cnt = [SELECT Id FROM CustomNotificationType
										WHERE DeveloperName = 'Reviewer_Mapping_Notification' LIMIT 1];

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(cnt.Id);
        notification.setTitle('Reviewer Mapping Submitted');
        notification.setBody('A Reviewer Mapping has been submitted for review.');
        notification.setTargetId(reviewerMappings[0].Id);

        notification.send(userIds);
    }

    // Fired from ReviewerMappingTriggerHandler.updateReviewerEligibilityStatus when a
    // Proposal's Prelim_Reviewer_Eligibility_Status__c or Peer_Reviewer_Eligibility_Status__c
    // just transitioned to 'Submitted'. Audience is the Grants Team Members who actually have
    // a Grants_Team_Response__c against this specific proposal - not everyone assigned to the
    // proposal's Yearly Scheme in general. Same Custom Notification Type as the per-reviewer
    // "Reviewer Submitted" notification above, but no Task (notification only, per instruction).
    public static void sendEligibilitySubmittedNotification(Id proposalId, String title, String body) {
        if (proposalId == null) {
            return;
        }

        Set<String> memberUserIds = new Set<String>();
        for (Grants_Team_Response__c response : [
            SELECT Grants_Team_Members__r.User__c
            FROM Grants_Team_Response__c
            WHERE Proposal__c = :proposalId
            AND Grants_Team_Members__c != null
        ]) {
            if (response.Grants_Team_Members__r != null && response.Grants_Team_Members__r.User__c != null) {
                memberUserIds.add(String.valueOf(response.Grants_Team_Members__r.User__c));
            }
        }
        if (memberUserIds.isEmpty()) {
            return;
        }

        CustomNotificationType cnt = [SELECT Id FROM CustomNotificationType
                                        WHERE DeveloperName = 'Reviewer_Mapping_Notification' LIMIT 1];

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(cnt.Id);
        notification.setTitle(title);
        notification.setBody(body);
        notification.setTargetId(proposalId);

        notification.send(memberUserIds);
    }
}