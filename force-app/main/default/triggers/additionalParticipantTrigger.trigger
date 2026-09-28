trigger additionalParticipantTrigger on Additional_Partcipant__c(after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        additionalParticipantTriggerHandler.sendInvitationEmails(Trigger.new);
        additionalParticipantTriggerHandler.sendInvitationContactEmails(Trigger.new);
        additionalParticipantTriggerHandler.sendFullInvitationEmails(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        additionalParticipantTriggerHandler.sendInvitationEmails(Trigger.new, Trigger.oldMap);
        additionalParticipantTriggerHandler.sendInvitationContactEmails(Trigger.new, Trigger.oldMap);
        additionalParticipantTriggerHandler.sendFullInvitationEmails(Trigger.new, Trigger.oldMap);
    }
}






/*
trigger additionalParticipantTrigger on Additional_Partcipant__c(after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        additionalParticipantTriggerHandler.sendInvitationEmails(Trigger.new);
        additionalParticipantTriggerHandler.sendInvitationContactEmails(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        additionalParticipantTriggerHandler.sendInvitationEmails(Trigger.new, Trigger.oldMap);
        additionalParticipantTriggerHandler.sendInvitationContactEmails(Trigger.new, Trigger.oldMap);
    }
}*/









/*
trigger additionalParticipantTrigger on Additional_Partcipant__c(after insert) {
	 if (Trigger.isAfter && Trigger.isInsert) {
        additionalParticipantTriggerHandler.sendInvitationEmails(Trigger.new);
    }
}*/