public class SchemeSectionTriggerHandler {

    private static final String EMAIL_TEMPLATE_DEVELOPER_NAME =
        'Reopen_Section_Detail';
    
        public static void handleAfterUpdateofReopen(
            List<Scheme_Section__c> newRecords,
            Map<Id, Scheme_Section__c> oldMap
        ) {
    
            Set<Id> reopenedSectionIds =
                new Set<Id>();
    
            for (Scheme_Section__c section : newRecords) {
    
                Scheme_Section__c oldSection =
                    oldMap.get(section.Id);
    
                if (
                    section.Reopen_Status__c == 'Reopen' &&
                    oldSection != null &&
                    oldSection.Reopen_Status__c != 'Reopen' &&
                    section.Applicant_Proposal_Association__c != null
                ) {
    
                    reopenedSectionIds.add(section.Id);
                }
            }
    
            if (reopenedSectionIds.isEmpty()) {
                return;
            }
            system.debug('Line 33-===>');
    
            sendReopenNotificationEmails(
                reopenedSectionIds
            );
        }
    
    
        private static void sendReopenNotificationEmails(
            Set<Id> sectionIds
        ) {
    
            System.enqueueJob(
                new EmailNotificationQueueable(
                    'SCHEME_SECTION_REOPEN',
                    new List<Id>(sectionIds),
                    'Reopen_Section_Detail'
                )
            );
        }
}