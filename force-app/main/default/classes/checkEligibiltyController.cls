public with sharing class checkEligibiltyController {

    @AuraEnabled
    public static List<Proposal_Eligibility_Check_List__c> getEligibilityChecklist(Id proposalId) {
        try {
            System.debug('proposalId : ' + proposalId);
            System.debug('------------ checkEligibiltyController.getEligibilityChecklist ------------');

            if (proposalId == null) {
                throw new AuraHandledException('Proposal Id is required.');
            }

            List<Proposal__c> proposals = [
                SELECT Id, Application_Stages__c
                FROM Proposal__c
                WHERE Id = :proposalId
                LIMIT 1
            ];

            if (proposals.isEmpty()) {
                throw new AuraHandledException('Proposal not found or access denied.');
            }

            String stage = proposals[0].Application_Stages__c;
            System.debug('stage : ' + stage);

            List<Proposal_Eligibility_Check_List__c> eligibilityChecklist = [
                SELECT Id, Display_Question__c, Stage__c, Type__c, Answer__c
                FROM Proposal_Eligibility_Check_List__c
                WHERE Proposal__c = :proposalId
                AND Stage__c = :stage
                ORDER BY Name
            ];
            System.debug('eligibilityChecklist : ' + eligibilityChecklist);

            return eligibilityChecklist;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching eligibility checklist: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveEligibilityChecklist(List<Proposal_Eligibility_Check_List__c> records, Id proposalId) {
        try {
            System.debug('------------ checkEligibiltyController.saveEligibilityChecklist ------------');

            if (records == null || records.isEmpty()) {
                throw new AuraHandledException('No records to save.');
            }
            update records;

            // updateProposal(proposalId);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error saving eligibility checklist: ' + e.getMessage());
        }
    }

    // @AuraEnabled
    // public static void updateProposal(String proposalId) {
    //     try {
    //         System.debug('------------ checkEligibiltyController.updateProposal ------------');

    //         if (proposalId == null) {
    //             throw new AuraHandledException('Proposal Id is required.');
    //         }
    //         Proposal__c proposal = new Proposal__c(Id = proposalId, Eligible__c = true);
    //         update proposal;
    //     } catch (Exception e) {
    //         throw new AuraHandledException('Error updating proposal: ' + e.getMessage());
    //     }
    // }
}