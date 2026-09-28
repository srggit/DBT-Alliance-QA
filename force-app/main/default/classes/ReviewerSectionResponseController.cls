public with sharing class ReviewerSectionResponseController {

    @AuraEnabled(cacheable=true)
    public static List<ReviewerMappingWrapper> getReviewerSectionResponses(Id proposalId) {
        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }

        List<Proposal__c> proposals = [
            SELECT Application_Stages__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];
        String proposalStage = proposals.isEmpty() ? null : proposals[0].Application_Stages__c;

        // Reviewer responses are scoped strictly to the proposal's current stage:
        // Prelims proposals show only Prelims reviewers, Full proposals show only
        // Full reviewers. The child Scheme_Section__c filter mirrors the same stage,
        // since a single reviewer mapping's sections can otherwise include
        // stage-irrelevant sections (Ex-Grantee reviewers get every question-template
        // section regardless of which stage it belongs to). If the proposal has no
        // stage set, the equality filter naturally returns zero rows - a proposal
        // without a stage shouldn't have reviewer responses to show anyway.
        List<Reviewer_Mapping__c> mappings = [
            SELECT Id, Reviewer_Name__c, Reviewer_Type__c, Status__c,
                   Overall_Assessment_Comments__c, Overall_Score__c, Application_Stages__c,
                   Reviewer__r.Title__c, Reviewer__r.First_Name__c, Reviewer__r.Last_Name__c,
                   (SELECT Id, Section_Name__c, Rating__c, Overall_Comments__c
                    FROM Scheme_Sections__r
                    WHERE Application_Stages__c = :proposalStage
                    ORDER BY CreatedDate ASC)
            FROM Reviewer_Mapping__c
            WHERE Proposal__c = :proposalId
            AND Status__c = 'Submitted'
            AND Application_Stages__c = :proposalStage
            ORDER BY CreatedDate ASC
        ];

        // Group Prelims reviewers before Full reviewers (SOQL can't order by a custom
        // picklist sequence), preserving CreatedDate order within each group.
        List<Reviewer_Mapping__c> orderedMappings = new List<Reviewer_Mapping__c>();
        for (Reviewer_Mapping__c mapping : mappings) {
            if (mapping.Application_Stages__c == 'Prelims') {
                orderedMappings.add(mapping);
            }
        }
        for (Reviewer_Mapping__c mapping : mappings) {
            if (mapping.Application_Stages__c != 'Prelims') {
                orderedMappings.add(mapping);
            }
        }

        List<ReviewerMappingWrapper> result = new List<ReviewerMappingWrapper>();
        for (Reviewer_Mapping__c mapping : orderedMappings) {
            List<SectionWrapper> sections = new List<SectionWrapper>();
            for (Scheme_Section__c section : mapping.Scheme_Sections__r) {
                sections.add(new SectionWrapper(
                    section.Id,
                    section.Section_Name__c,
                    section.Rating__c,
                    section.Overall_Comments__c
                ));
            }
            result.add(new ReviewerMappingWrapper(
                mapping.Id,
                resolveReviewerName(mapping),
                mapping.Reviewer_Type__c,
                mapping.Overall_Assessment_Comments__c,
                mapping.Overall_Score__c,
                mapping.Application_Stages__c,
                sections
            ));
        }
        return result;
    }

    // Gates the Reject/Eligible for Full buttons in reviewerRatingMatrix.js - those
    // decisions should only be takeable once Prelim_Reviewer_Eligibility_Status__c is
    // 'Submitted' (the same condition the Shortlisting tab itself is already filtered on).
    @AuraEnabled(cacheable=true)
    public static String getPrelimReviewerEligibilityStatus(Id proposalId) {
        if (proposalId == null) {
            return null;
        }
        List<Proposal__c> proposals = [
            SELECT Prelim_Reviewer_Eligibility_Status__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];
        return proposals.isEmpty() ? null : proposals[0].Prelim_Reviewer_Eligibility_Status__c;
    }

    // Records the Grants team's Eligible for Full / Rejected decision (and accompanying
    // feedback) from the reviewerRatingMatrix component. decision must be exactly
    // 'Eligible' or 'Not Eligible' - anything else is rejected before it reaches the DML.
    // reasonForRejection is required (and only ever stored) when decision = 'Not Eligible'.
    @AuraEnabled
    public static void saveFullEligibilityDecision(Id proposalId, String decision, String feedbackSummary, String reasonForRejection) {
        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }
        if (decision != 'Eligible' && decision != 'Not Eligible') {
            throw new AuraHandledException('Decision must be Eligible or Not Eligible.');
        }
        if (decision == 'Not Eligible' && String.isBlank(reasonForRejection)) {
            throw new AuraHandledException('Reason for Rejection is required.');
        }
        if (decision == 'Eligible' && String.isBlank(feedbackSummary)) {
            throw new AuraHandledException('Grants Feedback Summary is required.');
        }
        Proposal__c toUpdate = new Proposal__c(
            Id = proposalId,
            Grants_Feedback_Summary__c = feedbackSummary
        );
        if (decision == 'Not Eligible') {
            toUpdate.Eligible_For_Full__c = decision;
            toUpdate.Reason_for_Rejection__c = reasonForRejection;
            toUpdate.Proposal_Status__c = 'Rejected';
        } else {
            // Eligible_For_Full__c is intentionally left untouched here - Moved_to_Full_Stage_By_Grant_Team_Member__c
            // is now the signal that a Grants Team Member has moved this proposal to Full stage.
            toUpdate.Moved_to_Full_Stage_By_Grant_Team_Member__c = true;
            toUpdate.Proposal_Status__c = 'Full Application';
        }
        try {
            update toUpdate;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to save decision: ' + e.getDmlMessage(0));
        }

        if (decision == 'Eligible') {
            markMovedToFullStageOnGrantTeamResponse(proposalId);
        }
    }

    // The Grants Team Member clicking "Eligible for Full" is acting through their own
    // Grants_Team_Response__c for this proposal - Grants Team Members are no longer split by
    // Application_Stages__c, so there is a single member record (and a single response) per
    // user per scheme to flag here, not a Prelims-specific one.
    private static void markMovedToFullStageOnGrantTeamResponse(Id proposalId) {
        Proposal__c proposal = [SELECT Yearly_Scheme__c FROM Proposal__c WHERE Id = :proposalId LIMIT 1];
        if (proposal.Yearly_Scheme__c == null) {
            return;
        }

        List<Grants_Team_Members__c> members = [
            SELECT Id
            FROM Grants_Team_Members__c
            WHERE User__c = :UserInfo.getUserId()
            AND Yearly_Scheme__c = :proposal.Yearly_Scheme__c
            LIMIT 1
        ];
        if (members.isEmpty()) {
            return;
        }

        List<Grants_Team_Response__c> responses = [
            SELECT Id
            FROM Grants_Team_Response__c
            WHERE Proposal__c = :proposalId
            AND Grants_Team_Members__c = :members[0].Id
            LIMIT 1
        ];
        if (responses.isEmpty()) {
            return;
        }

        update new Grants_Team_Response__c(
            Id = responses[0].Id,
            Moved_to_Full_Stage_By_Grant_Team_Member__c = true
        );
    }

    private static String resolveReviewerName(Reviewer_Mapping__c mapping) {
        if (mapping.Reviewer__r == null) {
            return mapping.Reviewer_Name__c;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(mapping.Reviewer__r.Title__c)) {
            parts.add(mapping.Reviewer__r.Title__c);
        }
        if (String.isNotBlank(mapping.Reviewer__r.First_Name__c)) {
            parts.add(mapping.Reviewer__r.First_Name__c);
        }
        if (String.isNotBlank(mapping.Reviewer__r.Last_Name__c)) {
            parts.add(mapping.Reviewer__r.Last_Name__c);
        }
        String fullName = String.join(parts, ' ');
        return String.isBlank(fullName) ? mapping.Reviewer_Name__c : fullName;
    }

    public class ReviewerMappingWrapper {
        @AuraEnabled public Id mappingId;
        @AuraEnabled public String reviewerName;
        @AuraEnabled public String reviewerType;
        @AuraEnabled public String overallComments;
        @AuraEnabled public Decimal overallScore;
        @AuraEnabled public String applicationStage;
        @AuraEnabled public List<SectionWrapper> sections;

        public ReviewerMappingWrapper(
            Id mappingId,
            String reviewerName,
            String reviewerType,
            String overallComments,
            Decimal overallScore,
            String applicationStage,
            List<SectionWrapper> sections
        ) {
            this.mappingId = mappingId;
            this.reviewerName = String.isBlank(reviewerName) ? 'Unnamed Reviewer' : reviewerName;
            this.reviewerType = reviewerType;
            this.overallComments = overallComments;
            this.overallScore = overallScore;
            this.applicationStage = applicationStage;
            this.sections = sections;
        }
    }

    public class SectionWrapper {
        @AuraEnabled public Id sectionId;
        @AuraEnabled public String sectionName;
        @AuraEnabled public String rating;
        @AuraEnabled public String overallComments;

        public SectionWrapper(Id sectionId, String sectionName, String rating, String overallComments) {
            this.sectionId = sectionId;
            this.sectionName = String.isBlank(sectionName) ? 'Unnamed Section' : sectionName;
            this.rating = rating;
            this.overallComments = overallComments;
        }
    }
}