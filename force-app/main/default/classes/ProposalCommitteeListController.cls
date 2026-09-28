public with sharing class ProposalCommitteeListController {

    @AuraEnabled(cacheable=true)
    public static List<CommitteeRowWrapper> getProposalCommitteeRecords(Id proposalId) {
        List<CommitteeRowWrapper> results = new List<CommitteeRowWrapper>();
        if (proposalId == null) {
            return results;
        }

        for (Proposal_Committee__c pc : [
            SELECT Id, Commitee_Member_Name__c, Type__c, Status__c, Committee_Reviewer__c,
                   Reviewer_Response__c, Conflict_Status__c, Overall_Score__c
            FROM Proposal_Committee__c
            WHERE Proposal__c = :proposalId
            ORDER BY Type__c ASC, Commitee_Member_Name__c ASC
        ]) {
            results.add(new CommitteeRowWrapper(pc));
        }

        return results;
    }

    @AuraEnabled
    public static void updateCommitteeTypes(List<CommitteeTypeUpdate> updates) {
        if (updates == null || updates.isEmpty()) {
            throw new AuraHandledException('No changes to save.');
        }
        List<Proposal_Committee__c> recordsToUpdate = new List<Proposal_Committee__c>();
        for (CommitteeTypeUpdate u : updates) {
            recordsToUpdate.add(new Proposal_Committee__c(Id = u.id, Type__c = u.type));
        }
        update recordsToUpdate;
    }

    public class CommitteeTypeUpdate {
        @AuraEnabled public Id id;
        @AuraEnabled public String type;
    }

    public class CommitteeRowWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String memberName;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean committeeReviewer;
        @AuraEnabled public String reviewerResponse;
        @AuraEnabled public String conflictStatus;
        @AuraEnabled public Decimal overallScore;

        public CommitteeRowWrapper(Proposal_Committee__c pc) {
            this.id = pc.Id;
            this.memberName = pc.Commitee_Member_Name__c;
            this.type = pc.Type__c;
            this.status = pc.Status__c;
            this.committeeReviewer = pc.Committee_Reviewer__c;
            this.reviewerResponse = pc.Reviewer_Response__c;
            this.conflictStatus = pc.Conflict_Status__c;
            this.overallScore = pc.Overall_Score__c;
        }
    }
}