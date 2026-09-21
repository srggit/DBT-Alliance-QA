trigger ProposalTrigger on Proposal__c(before insert, before update, after insert, after update) {
	if (Trigger.isBefore && Trigger.isUpdate) {
        // Resets Peer_Application_Stage__c to 'Draft' as soon as Proposal_Status__c
        // transitions to 'Full Application' - see method doc for details.
        ProposalTriggerHandler.resetPeerApplicationStageOnFullApplication(Trigger.new, Trigger.oldMap);

        // Advances Proposal_Status__c to 'Peer Review' as soon as Eligible_For_Full__c
        // changes to 'Eligible' - whether that came from GrantsTeamResponseHandler's
        // consensus decision or a direct/manual edit to the field on the Proposal.
        ProposalTriggerHandler.advanceToPeerReviewOnFullEligible(Trigger.new, Trigger.oldMap);

        // Same reasoning, for the rejection side: advances Proposal_Status__c to 'Rejected'
        // as soon as Eligible_For_Prelim__c changes to 'Not Eligible'.
        ProposalTriggerHandler.advanceToRejectedOnPrelimNotEligible(Trigger.new, Trigger.oldMap);
    }
	if (Trigger.isAfter) {
        if (Trigger.isUpdate) {
            FieldHistoryTrackerUtil.trackChanges(Trigger.new, Trigger.oldMap);
            NotificationHandler.createNotifications('Proposal__c', Trigger.new);
            ProposalTriggerHandler.sendSubmissionConfirmation(Trigger.new, Trigger.oldMap);
            ProposalTriggerHandler.cloneCommitteeMember( Trigger.new,Trigger.oldMap);

            // Round-robin: for Proposals that just entered 'Committee Review', pick the
            // next Threshold__c committee members from the Yearly Scheme's ring and mark
            // them on the Proposal_Committee__c records cloneCommitteeMember just created.
            ProposalTriggerHandler.assignRoundRobinReviewers(Trigger.new, Trigger.oldMap);

            // Emails every committee member on this proposal (every Proposal_Committee__c
            // junction cloneCommitteeMember just created, not just the round-robin-selected
            // Committee_Reviewer__c = true subset assignRoundRobinReviewers picks).
            ReviewerController.sendCommitteeAssignmentEmails(
                Trigger.new,
                Trigger.oldMap
            );

            // Grants_Team_Response__c records are now created at Proposal insert (see the
            // after-insert block below) - this only advances Proposal_Status__c to
            // 'Eligibility Check' once the applicant actually submits.
            ProposalTriggerHandler.advanceToEligibilityCheckOnSubmit(Trigger.new, Trigger.oldMap);

            // Description: This method is used to autoassign the Reviewers as soon as:
            /* 
            Runs only when Eligible_For_Prelim__c or Eligible_For_Full__c changes to 'Eligible'.
            Uses the same keyword matching logic as the Assign Reviewers component (reviewer keyword substring-matched against proposal keywords).
            If a proposal has no keywords, it skips that proposal entirely (no mappings, no emails).
            Skips reviewers that are already mapped to the proposal.
            Enforces the minimum reviewer count: 2 for Prelims / 3 for Full.
            Creates Reviewer_Mapping__c records and updates Proposal_Status__c to 'Prelim Review' or 'Peer Review'. Assignment emails no longer fire here - see ReviewerMappingTriggerHandler.handleAfterUpdate, which sends them once the Grants Team approves each reviewer.
            */
            ProposalTriggerHandler.autoAssignReviewers(Trigger.new, Trigger.oldMap);

            // Advances Proposal_Status__c from 'Prelim Review' to 'Shortlisting' as soon as
            // Prelim_Reviewer_Eligibility_Status__c changes to 'Submitted' - whether that
            // came from ReviewerMappingTriggerHandler's reviewer-count automation or a
            // manual edit directly on the Proposal.
            ProposalTriggerHandler.updateShortlistingStatus(Trigger.new, Trigger.oldMap);

            // Same reasoning, for the Peer/Full side: advances Proposal_Status__c from
            // 'Peer Review' to 'Peer Shortlisting' as soon as
            // Peer_Reviewer_Eligibility_Status__c changes to 'Submitted'.
            ProposalTriggerHandler.updatePeerShortlistingStatus(Trigger.new, Trigger.oldMap);

            // Notifies the Grants Team (via Grants_Team_Response__c on this proposal) when
            // Prelim_Reviewer_Eligibility_Status__c or Peer_Reviewer_Eligibility_Status__c
            // changes to 'Submitted' - same "react to the field itself" reasoning as
            // updateShortlistingStatus just above, so a direct/manual edit notifies too.
            ProposalTriggerHandler.sendReviewerEligibilityNotifications(Trigger.new, Trigger.oldMap);

            // Same reasoning again: notifies the Grants Team as soon as Proposal_Status__c
            // itself becomes 'Full Application', regardless of which path set it.
            ProposalTriggerHandler.sendFullApplicationNotifications(Trigger.new, Trigger.oldMap);

            // Notifies the Applicant (in-app Notification__c + email) as soon as
            // Proposal_Status__c itself becomes 'Full Application', regardless of which path
            // set it - same reasoning as sendFullApplicationNotifications just above, but for
            // the Applicant audience instead of the Grants Team.
            ProposalTriggerHandler.notifyApplicantOnFullApplicationEligibility(Trigger.new, Trigger.oldMap);
        }
    }
     if (Trigger.isAfter && Trigger.isInsert) {
      //  ProposalTriggerHandler.generateProposalId(Trigger.newMap.keySet());
      ProposalTriggerHandler.cloneEligibilityChecklist(Trigger.new);

      // Creates the Grants_Team_Response__c records (and their child
      // Grants_Team_Response_Item__c questions, both stages) for every Grants Team Member
      // on the Proposal's Yearly Scheme, as soon as the Proposal record itself is created -
      // no longer gated on the Proposal being Submitted.
      ProposalTriggerHandler.createGrantsTeamResponses(Trigger.new);
    }
}