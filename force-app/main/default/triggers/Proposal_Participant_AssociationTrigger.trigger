trigger Proposal_Participant_AssociationTrigger on Proposal_Participant_Association__c (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ProposalParticipantTriggerHandler.sendInvitationEmails(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        ProposalParticipantTriggerHandler.sendInvitationEmails(Trigger.new, Trigger.oldMap);
    }
}