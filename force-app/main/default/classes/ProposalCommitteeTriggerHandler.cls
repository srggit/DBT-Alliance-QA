public with sharing class ProposalCommitteeTriggerHandler {

    /*
     Once at least this many Proposal_Committee__c records for a Proposal have
     Status__c = 'Submitted', Proposal__c.Committee_Review_Submitted__c is set to true -
     mirrors the same "recount every Submitted child, then flip a Proposal field" pattern
     already used for Prelim_Reviewer_Eligibility_Status__c / Peer_Reviewer_Eligibility_Status__c
     in ReviewerMappingTriggerHandler.updateReviewerEligibilityStatus. Recounts every Submitted
     record per proposal (not just this batch) so the threshold reflects the true current
     total, and only proposals not already flagged true are considered, so the field is a
     one-way flip that never gets reset.
    */
    private static final Integer COMMITTEE_REQUIRED_SUBMISSIONS = 2;

    public static void updateCommitteeReviewSubmittedStatus(List<Proposal_Committee__c> newList, Map<Id, Proposal_Committee__c> oldMap) {
        Set<Id> proposalIds = new Set<Id>();
        for (Proposal_Committee__c pc : newList) {
            Proposal_Committee__c oldRec = oldMap.get(pc.Id);
            if (pc.Proposal__c != null && pc.Status__c == 'Submitted' && oldRec.Status__c != 'Submitted') {
                proposalIds.add(pc.Proposal__c);
            }
        }
        if (proposalIds.isEmpty()) {
            return;
        }

        Map<Id, Proposal__c> proposalsById = new Map<Id, Proposal__c>([
            SELECT Id, Committee_Review_Submitted__c
            FROM Proposal__c
            WHERE Id IN :proposalIds
            AND Committee_Review_Submitted__c = false
        ]);
        if (proposalsById.isEmpty()) {
            return;
        }

        Map<Id, Integer> submittedCountByProposal = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Proposal__c prop, COUNT(Id) cnt
            FROM Proposal_Committee__c
            WHERE Proposal__c IN :proposalsById.keySet()
            AND Status__c = 'Submitted'
            GROUP BY Proposal__c
        ]) {
            submittedCountByProposal.put((Id) ar.get('prop'), (Integer) ar.get('cnt'));
        }

        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();
        for (Id proposalId : proposalsById.keySet()) {
            Integer submittedCount = submittedCountByProposal.containsKey(proposalId) ? submittedCountByProposal.get(proposalId) : 0;
            if (submittedCount >= COMMITTEE_REQUIRED_SUBMISSIONS) {
                proposalsToUpdate.add(new Proposal__c(
                    Id = proposalId,
                    Committee_Review_Submitted__c = true,
                    Proposal_Status__c = 'Chair/Co-Chair'
                ));
            }
        }

        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }
}