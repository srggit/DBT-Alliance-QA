/*
    1. This trigger is used to copy the Question Line Items from Yearly Scheme to Request Reviewer Response Line Items.
    2. For Ex-Grantee reviewers, all questions are copied.
    3. For Peer reviewers (International), only questions marked as visible to peer reviewers are copied.
*/

trigger ReviewerMappingTrigger on Reviewer_Mapping__c (after insert,after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ReviewerMappingTriggerHandler.createReviewerResponseLineItems(Trigger.new);
         NotificationHandler.createNotifications('Reviewer_Mapping__c', Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
         ReviewerMappingTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    
}