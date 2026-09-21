trigger ContactRegistrationTrigger on Contact (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ContactRegistrationEmailHandler.sendWelcomeEmails(Trigger.new);
    }
}