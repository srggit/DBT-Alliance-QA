trigger ProposalCommiteeTrigger on Proposal_Committee__c (after insert,after update) {
     if (Trigger.isAfter && Trigger.isInsert) {
         NotificationHandler.createNotifications('Proposal_Committee__c', Trigger.new);
         ProposalCommitteeTriggerHandler.updateAllCommitteeResponseSubmitted(Trigger.new, null);
     }
    if (Trigger.isAfter && Trigger.isUpdate) {
        NotificationHandler.createNotifications('Proposal_Committee__c', Trigger.new);
        // Automation stopped: Chair/Co-Chair is now a manual decision taken from the Committee
        // Evaluation Responses screen (CommitteeEvaluationMatrixController.saveCommitteeDecision).
        // ProposalCommitteeTriggerHandler.updateCommitteeReviewSubmittedStatus(Trigger.new, Trigger.oldMap);
        ProposalCommitteeTriggerHandler.updateAllCommitteeResponseSubmitted(Trigger.new, Trigger.oldMap);
        ProposalCommitteeTriggerHandler.sendReviewerAssignmentEmails(Trigger.new, Trigger.oldMap);
 }
}