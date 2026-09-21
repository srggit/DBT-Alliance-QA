public without sharing class ContactRegistrationEmailHandler {
	public static void sendWelcomeEmails(List<Contact> newRecords) {
        System.debug('========== ContactRegistrationEmailHandler START ==========');
        System.debug('Number of Contacts: ' + newRecords.size());

        List<Id> contactIds = new List<Id>();

        for (Contact con : newRecords) {

            if (String.isBlank(con.Email)) {
                continue;
            }

            contactIds.add(con.Id);
        }
        System.debug('Contact IDs for Queueable: ' + contactIds);
        if (contactIds.isEmpty()) {
            System.debug('No Contacts with Email. Queueable will NOT run.'); return; 
        }

        if (contactIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'CONTACT_WELCOME',
                contactIds,
                'X6_WelcomeEmail'
            )
        );

    }
}