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

    // Set by the round robin while it flags reviewers - the Committee Review assignment email
    // (sent right after) already covers them, so no separate reviewer email in that pass.
    public static Boolean suppressReviewerEmail = false;

    /*
     Committee_Reviewer__c false -> true on an existing Proposal_Committee__c (ticked on the
     Proposal Committee screen, edited on the record, ...) emails that member the committee
     assignment template with the "assigned as the Reviewer" wording. Only once the proposal is
     at a committee stage - before that, the member is emailed with everyone else when the
     Proposal reaches Committee Review.
    */
    public static void sendReviewerAssignmentEmails(List<Proposal_Committee__c> newList, Map<Id, Proposal_Committee__c> oldMap) {
        if (suppressReviewerEmail || oldMap == null) {
            return;
        }
        Set<Id> committeeIds = new Set<Id>();
        for (Proposal_Committee__c pc : newList) {
            Proposal_Committee__c oldRec = oldMap.get(pc.Id);
            if (pc.Committee_Reviewer__c == true && oldRec != null && oldRec.Committee_Reviewer__c != true) {
                committeeIds.add(pc.Id);
            }
        }
        if (committeeIds.isEmpty()) {
            return;
        }

        Set<Id> proposalIds = new Set<Id>();
        Set<Id> eligibleCommitteeIds = new Set<Id>();
        for (Proposal_Committee__c pc : [
            SELECT Id, Proposal__c, Proposal__r.Proposal_Status__c
            FROM Proposal_Committee__c
            WHERE Id IN :committeeIds
        ]) {
            if (pc.Proposal__c != null && ReviewerController.COMMITTEE_STAGE_STATUSES.contains(pc.Proposal__r.Proposal_Status__c)) {
                proposalIds.add(pc.Proposal__c);
                eligibleCommitteeIds.add(pc.Id);
            }
        }
        if (!eligibleCommitteeIds.isEmpty()) {
            ReviewerController.sendCommitteeEmails(proposalIds, eligibleCommitteeIds);
        }
    }

    // NOTE: no longer called (see ProposalCommiteeTrigger) - the move to 'Chair/Co-Chair' (or
    // 'Rejected') is now a manual decision on the Committee Evaluation Responses screen.

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

    /*
     Keeps Proposal__c.All_Committee_Response_Submitted__c in sync with the LIVE state of
     every Proposal_Committee__c record on the proposal - true only while every single
     member (not just a threshold count, unlike Committee_Review_Submitted__c above) has
     Status__c = 'Submitted'. Unlike the one-way flag above, this recomputes both directions:
     adding a new not-yet-submitted member (or any status changing away from Submitted)
     un-sets it again, since "ALL submitted" is only true of the current member set.
     Runs on both insert (a newly added member can flip an already-true proposal back to
     false) and update (a status change can flip it either way).
    */
    public static void updateAllCommitteeResponseSubmitted(List<Proposal_Committee__c> newList, Map<Id, Proposal_Committee__c> oldMap) {
        Set<Id> proposalIds = new Set<Id>();
        for (Proposal_Committee__c pc : newList) {
            if (pc.Proposal__c == null) {
                continue;
            }
            if (oldMap == null) {
                proposalIds.add(pc.Proposal__c);
            } else {
                Proposal_Committee__c oldRec = oldMap.get(pc.Id);
                if (oldRec != null && oldRec.Status__c != pc.Status__c) {
                    proposalIds.add(pc.Proposal__c);
                }
            }
        }
        if (proposalIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> totalByProposal = new Map<Id, Integer>();
        Map<Id, Integer> submittedByProposal = new Map<Id, Integer>();
        for (Proposal_Committee__c pc : [
            SELECT Proposal__c, Status__c
            FROM Proposal_Committee__c
            WHERE Proposal__c IN :proposalIds
        ]) {
            totalByProposal.put(pc.Proposal__c, (totalByProposal.containsKey(pc.Proposal__c) ? totalByProposal.get(pc.Proposal__c) : 0) + 1);
            if (pc.Status__c == 'Submitted') {
                submittedByProposal.put(pc.Proposal__c, (submittedByProposal.containsKey(pc.Proposal__c) ? submittedByProposal.get(pc.Proposal__c) : 0) + 1);
            }
        }

        Map<Id, Proposal__c> proposalsById = new Map<Id, Proposal__c>([
            SELECT Id, All_Committee_Response_Submitted__c
            FROM Proposal__c
            WHERE Id IN :proposalIds
        ]);

        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();
        for (Id proposalId : proposalIds) {
            Proposal__c existing = proposalsById.get(proposalId);
            if (existing == null) {
                continue;
            }
            Integer total = totalByProposal.containsKey(proposalId) ? totalByProposal.get(proposalId) : 0;
            Integer submitted = submittedByProposal.containsKey(proposalId) ? submittedByProposal.get(proposalId) : 0;
            Boolean allSubmitted = total > 0 && submitted == total;

            if (existing.All_Committee_Response_Submitted__c != allSubmitted) {
                proposalsToUpdate.add(new Proposal__c(
                    Id = proposalId,
                    All_Committee_Response_Submitted__c = allSubmitted
                ));
            }
        }

        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }
}