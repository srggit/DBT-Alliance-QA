trigger Proposal_Participant_AssociationTrigger on Proposal_Participant_Association__c (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ProposalParticipantTriggerHandler.sendInvitationEmails(Trigger.new);
        ProposalParticipantTriggerHandler.sendFullInvitationEmails(Trigger.new);
        ProposalParticipantTriggerHandler.createDocumentUploadedNotifications(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        ProposalParticipantTriggerHandler.sendInvitationEmails(Trigger.new, Trigger.oldMap);
        ProposalParticipantTriggerHandler.sendFullInvitationEmails(Trigger.new, Trigger.oldMap);
        ProposalParticipantTriggerHandler.createDocumentUploadedNotifications(Trigger.new, Trigger.oldMap);
    }
}











/*
trigger Proposal_Participant_AssociationTrigger on Proposal_Participant_Association__c (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ProposalParticipantTriggerHandler.sendInvitationEmails(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        ProposalParticipantTriggerHandler.sendInvitationEmails(Trigger.new, Trigger.oldMap);
    }
}*/