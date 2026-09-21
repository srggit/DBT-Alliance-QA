public with sharing class ReviewerMappingController {

    @AuraEnabled
    public static List<Reviewer_Mapping__c> getReviewerMappingsForProposal(Id proposalId, String applicationStage) {
        if (String.isBlank(proposalId)) {
            return new List<Reviewer_Mapping__c>();
        }
        if (String.isNotBlank(applicationStage)) {
            return [
                SELECT Id, Name, Reviewer__c, Reviewer__r.Name, Reviewer_Name__c, Reviewer_Type__c,
                       Application_Stages__c, Status__c, Evaluation_Submission_Date__c,
                       Escalation_Task_Created__c, Invitation_Responded__c, Invitation_Responded_Date__c,
                       Invitation_Sent_Date__c, Invitation_Reminder_Sent__c, Overall_Score__c
                FROM Reviewer_Mapping__c
                WHERE Proposal__c = :proposalId
                AND Application_Stages__c = :applicationStage
                ORDER BY Name
            ];
        }
        return [
            SELECT Id, Name, Reviewer__c, Reviewer__r.Name, Reviewer_Name__c, Reviewer_Type__c,
                   Application_Stages__c, Status__c, Evaluation_Submission_Date__c,
                   Escalation_Task_Created__c, Invitation_Responded__c, Invitation_Responded_Date__c,
                   Invitation_Sent_Date__c, Invitation_Reminder_Sent__c, Overall_Score__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c = :proposalId
            ORDER BY Name
        ];
    }
}