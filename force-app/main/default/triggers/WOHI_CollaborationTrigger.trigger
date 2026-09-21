trigger WOHI_CollaborationTrigger on WOHI_Collaboration__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            WOHI_CollaborationTriggerHandler.sendInvitationEmails(Trigger.new, null);
        } else if (Trigger.isUpdate) {
            WOHI_CollaborationTriggerHandler.sendInvitationEmails(Trigger.new, Trigger.oldMap);
        }
    }
}








/*trigger WOHI_CollaborationTrigger on WOHI_Collaboration__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        WOHI_CollaborationTriggerHandler.sendInvitationEmails(Trigger.new);
    }
}*/