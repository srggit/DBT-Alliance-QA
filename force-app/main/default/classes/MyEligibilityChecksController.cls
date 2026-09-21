public with sharing class MyEligibilityChecksController {

    @AuraEnabled
    public static void markEligibleForFull(List<Id> proposalIds) {
        if (proposalIds == null || proposalIds.isEmpty()) {
            throw new AuraHandledException('Select at least one proposal.');
        }
        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();
        for (Id proposalId : proposalIds) {
            proposalsToUpdate.add(new Proposal__c(
                Id = proposalId,
                Eligible_For_Full__c = 'Eligible',
                Peer_Application_Stage__c = 'Draft'
            ));
        }
        update proposalsToUpdate;
    }

    @AuraEnabled(cacheable=true)
    public static List<EligibilityCheckWrapper> getMyEligibilityChecks() {
        Id currentUserId = UserInfo.getUserId();

        List<Grants_Team_Members__c> memberRecords = [
            SELECT Id
            FROM Grants_Team_Members__c
            WHERE User__c = :currentUserId
        ];
        if (memberRecords.isEmpty()) {
            return new List<EligibilityCheckWrapper>();
        }

        Set<Id> memberIds = new Set<Id>();
        for (Grants_Team_Members__c member : memberRecords) {
            memberIds.add(member.Id);
        }

        List<Grants_Team_Response__c> responses = [
            SELECT Id,
                   CreatedDate,
                   Status__c,
                   Stage__c,
                   Eligible_For_Prelim__c,
                   Eligible_For_Full__c,
                   Proposal__c,
                   Proposal__r.Name,
                   Proposal__r.Proposal_Id__c,
                   Proposal__r.Proposal_Status__c,
                   Proposal__r.Application_Stages__c,
                   Proposal__r.Peer_Application_Stage__c,
                   Proposal__r.Eligible_For_Prelim__c,
                   Proposal__r.Eligible_For_Full__c,
                   Proposal__r.Moved_to_Full_Stage_By_Grant_Team_Member__c,
                   Proposal__r.Prelim_Reviewer_Eligibility_Status__c,
                   Proposal__r.Peer_Reviewer_Eligibility_Status__c,
                   Proposal__r.Recommended_for_Committee_Review__c,
                   Proposal__r.Yearly_Scheme__r.Name,
                   Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Grants_Team_Response__c
            WHERE Grants_Team_Members__c IN :memberIds
            AND Proposal__c != NULL
            // AND Proposal__r.Proposal_Status__c = 'Eligibility Check'
            // AND Proposal__r.Proposal_Status__c != 'Rejected'
            ORDER BY CreatedDate DESC
        ];

        Set<Id> proposalIds = new Set<Id>();
        for (Grants_Team_Response__c resp : responses) {
            if (resp.Proposal__c != null) {
                proposalIds.add(resp.Proposal__c);
            }
        }

        Map<Id, String> applicantNameByProposal = new Map<Id, String>();
        if (!proposalIds.isEmpty()) {
            for (Applicant_Proposal_Association__c apa : [
                SELECT Proposal__c, Contact__r.Name
                FROM Applicant_Proposal_Association__c
                WHERE Proposal__c IN :proposalIds
                AND Contact__c != null
                ORDER BY CreatedDate ASC
            ]) {
                if (!applicantNameByProposal.containsKey(apa.Proposal__c)) {
                    applicantNameByProposal.put(apa.Proposal__c, apa.Contact__r.Name);
                }
            }
        }

        List<EligibilityCheckWrapper> results = new List<EligibilityCheckWrapper>();
        for (Grants_Team_Response__c resp : responses) {
            String stage = resp.Proposal__r.Application_Stages__c;
            // "My Verdict" - this individual member's own submitted response for this stage.
            String eligibility;
            if (stage == 'Prelims') {
                eligibility = resp.Eligible_For_Prelim__c;
            } else if (stage == 'Full') {
                eligibility = resp.Eligible_For_Full__c;
            }

            // Proposal-level aggregate outcome (set by GrantsTeamResponseHandler once the
            // required number of members have submitted and agreed) - not any one person's vote.
            String proposalEligibility;
            if (stage == 'Prelims') {
                proposalEligibility = resp.Proposal__r.Eligible_For_Prelim__c;
            } else if (stage == 'Full') {
                proposalEligibility = resp.Proposal__r.Eligible_For_Full__c;
            }

            results.add(new EligibilityCheckWrapper(
                resp.Id,
                resp.Proposal__c,
                resp.Proposal__r.Name,
                resp.Proposal__r.Proposal_Id__c,
                resp.Proposal__r.Yearly_Scheme__r != null ? resp.Proposal__r.Yearly_Scheme__r.Name : null,
                resp.Proposal__r.Yearly_Scheme__r != null && resp.Proposal__r.Yearly_Scheme__r.Scheme_Items__r != null && resp.Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name != null ? resp.Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name : null,
                resp.Proposal__r.Proposal_Status__c,
                resp.Proposal__r.Application_Stages__c,
                resp.Status__c,
                eligibility,
                resp.Proposal__r.Eligible_For_Prelim__c,
                resp.Proposal__r.Eligible_For_Full__c,
                proposalEligibility,
                resp.Proposal__r.Prelim_Reviewer_Eligibility_Status__c,
                applicantNameByProposal.get(resp.Proposal__c),
                resp.CreatedDate,
                resp.Stage__c,
                resp.Proposal__r.Peer_Application_Stage__c,
                resp.Proposal__r.Moved_to_Full_Stage_By_Grant_Team_Member__c,
                resp.Proposal__r.Peer_Reviewer_Eligibility_Status__c,
                resp.Proposal__r.Recommended_for_Committee_Review__c
            ));
        }
        return results;
    }

    public class EligibilityCheckWrapper {
        @AuraEnabled public Id responseId;
        @AuraEnabled public Id proposalId;
        @AuraEnabled public String proposalName;
        @AuraEnabled public String proposalIdDisplay;
        @AuraEnabled public String yearlyScheme;
        @AuraEnabled public String schemeItemName;
        @AuraEnabled public String proposalStatus;
        @AuraEnabled public String applicationStage;
        @AuraEnabled public String status;
        @AuraEnabled public String eligibility;
        @AuraEnabled public String eligibleForPrelim;
        @AuraEnabled public String eligibleForFull;
        @AuraEnabled public String proposalEligibility;
        @AuraEnabled public String prelimReviewerEligibilityStatus;
        @AuraEnabled public String applicantName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String dueDate;
        // The response record's own Stage__c ('Prelims'/'Full') - not to be confused with
        // applicationStage (Proposal__r.Application_Stages__c), which reflects the Proposal's
        // current stage and can be out of sync with which stage this particular response
        // record belongs to (e.g. a member's old Prelims response once the Proposal has moved
        // on to Full). Used to correctly scope the Full Application tab to Full-stage responses.
        @AuraEnabled public String responseStage;
        @AuraEnabled public String peerApplicationStage;
        @AuraEnabled public Boolean movedToFullStageByGrantTeamMember;
        @AuraEnabled public String peerReviewerEligibilityStatus;
        @AuraEnabled public String recommendedForCommitteeReview;

        public EligibilityCheckWrapper(
            Id responseId,
            Id proposalId,
            String proposalName,
            String proposalIdDisplay,
            String yearlyScheme,
            String schemeItemName,
            String proposalStatus,
            String applicationStage,
            String status,
            String eligibility,
            String eligibleForPrelim,
            String eligibleForFull,
            String proposalEligibility,
            String prelimReviewerEligibilityStatus,
            String applicantName,
            Datetime createdDate,
            String responseStage,
            String peerApplicationStage,
            Boolean movedToFullStageByGrantTeamMember,
            String peerReviewerEligibilityStatus,
            String recommendedForCommitteeReview
        ) {
            this.responseId = responseId;
            this.proposalId = proposalId;
            this.proposalName = proposalName;
            this.proposalIdDisplay = proposalIdDisplay;
            this.yearlyScheme = yearlyScheme;
            this.schemeItemName = schemeItemName;
            this.proposalStatus = proposalStatus;
            this.applicationStage = applicationStage;
            this.status = status;
            this.eligibility = eligibility;
            this.eligibleForPrelim = eligibleForPrelim;
            this.eligibleForFull = eligibleForFull;
            this.proposalEligibility = proposalEligibility;
            this.prelimReviewerEligibilityStatus = prelimReviewerEligibilityStatus;
            this.applicantName = applicantName;
            this.createdDate = createdDate;
            this.responseStage = responseStage;
            this.peerApplicationStage = peerApplicationStage;
            this.movedToFullStageByGrantTeamMember = movedToFullStageByGrantTeamMember;
            this.peerReviewerEligibilityStatus = peerReviewerEligibilityStatus;
            this.recommendedForCommitteeReview = recommendedForCommitteeReview;
            this.dueDate = '—';
        }
    }
}