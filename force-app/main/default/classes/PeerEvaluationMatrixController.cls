public with sharing class PeerEvaluationMatrixController {

    // Reject: Proposal_Status__c = 'Rejected', Recommended_for_Committee_Review__c = 'No',
    // Reason_for_Rejection_before_Committee__c = the typed reason (mandatory). Also sets the
    // original Reason_for_Rejection__c to the same text, since Reason_is_mandatory_when_
    // stage_is_reject on Proposal__c requires THAT field (not the new one) whenever
    // Proposal_Status__c = 'Rejected' - without this the save would fail validation.
    // Process to Committee: Recommended_for_Committee_Review__c = 'Yes', Proposal_Status__c =
    // 'Committee Review', Reviewer_Feedback_Summary__c = the Grant Member's typed summary of
    // the Peer Evaluation responses above (mandatory, same reveal-then-confirm UX as Reject).
    @AuraEnabled
    public static void saveCommitteeDecision(Id proposalId, String decision, String rejectionReason, String reviewerFeedbackSummary) {
        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }
        if (decision != 'Reject' && decision != 'ProcessToCommittee') {
            throw new AuraHandledException('Decision must be Reject or ProcessToCommittee.');
        }
        if (decision == 'Reject' && String.isBlank(rejectionReason)) {
            throw new AuraHandledException('Reason for Rejection is required.');
        }
        if (decision == 'ProcessToCommittee' && String.isBlank(reviewerFeedbackSummary)) {
            throw new AuraHandledException('Reviewer Feedback Summary is required.');
        }

        Proposal__c toUpdate = new Proposal__c(Id = proposalId);
        if (decision == 'Reject') {
            toUpdate.Proposal_Status__c = 'Rejected';
            toUpdate.Recommended_for_Committee_Review__c = 'No';
            toUpdate.Reason_for_Rejection_before_Committee__c = rejectionReason;
            toUpdate.Reason_for_Rejection__c = rejectionReason;
        } else {
            toUpdate.Recommended_for_Committee_Review__c = 'Yes';
            toUpdate.Proposal_Status__c = 'Committee Review';
            toUpdate.Reviewer_Feedback_Summary__c = reviewerFeedbackSummary;
        }

        try {
            update toUpdate;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to save decision: ' + e.getDmlMessage(0));
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ReviewerPeerEvaluationWrapper> getPeerEvaluations(Id proposalId) {
        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }

        List<Reviewer_Mapping__c> mappings = [
            SELECT Id, Reviewer_Name__c, Reviewer_Type__c, Status__c,
                   Reviewer__r.Title__c, Reviewer__r.First_Name__c, Reviewer__r.Last_Name__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c = :proposalId
            AND Status__c = 'Submitted'
            AND Application_Stages__c = 'Full'
            ORDER BY CreatedDate ASC
        ];

        if (mappings.isEmpty()) {
            return new List<ReviewerPeerEvaluationWrapper>();
        }

        Set<Id> mappingIds = new Set<Id>();
        for (Reviewer_Mapping__c mapping : mappings) {
            mappingIds.add(mapping.Id);
        }

        Map<Id, List<Peer_Evaluation__c>> evaluationsByMapping = new Map<Id, List<Peer_Evaluation__c>>();
        for (Peer_Evaluation__c pe : [
            SELECT Id, Question__c, Description__c, Answer__c, Reviewer_Mapping__c
            FROM Peer_Evaluation__c
            WHERE Reviewer_Mapping__c IN :mappingIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!evaluationsByMapping.containsKey(pe.Reviewer_Mapping__c)) {
                evaluationsByMapping.put(pe.Reviewer_Mapping__c, new List<Peer_Evaluation__c>());
            }
            evaluationsByMapping.get(pe.Reviewer_Mapping__c).add(pe);
        }

        List<ReviewerPeerEvaluationWrapper> result = new List<ReviewerPeerEvaluationWrapper>();
        for (Reviewer_Mapping__c mapping : mappings) {
            List<QuestionAnswerWrapper> answers = new List<QuestionAnswerWrapper>();
            List<Peer_Evaluation__c> evaluations = evaluationsByMapping.get(mapping.Id);
            if (evaluations != null) {
                for (Peer_Evaluation__c pe : evaluations) {
                    answers.add(new QuestionAnswerWrapper(pe.Question__c, pe.Description__c, pe.Answer__c));
                }
            }
            result.add(new ReviewerPeerEvaluationWrapper(mapping.Id, resolveReviewerName(mapping), mapping.Reviewer_Type__c, mapping.Status__c, answers));
        }
        return result;
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

    public class ReviewerPeerEvaluationWrapper {
        @AuraEnabled public Id mappingId;
        @AuraEnabled public String reviewerName;
        @AuraEnabled public String reviewerType;
        @AuraEnabled public String status;
        @AuraEnabled public List<QuestionAnswerWrapper> answers;

        public ReviewerPeerEvaluationWrapper(Id mappingId, String reviewerName, String reviewerType, String status, List<QuestionAnswerWrapper> answers) {
            this.mappingId = mappingId;
            this.reviewerName = reviewerName;
            this.reviewerType = reviewerType;
            this.status = status;
            this.answers = answers;
        }
    }

    public class QuestionAnswerWrapper {
        @AuraEnabled public String question;
        @AuraEnabled public String description;
        @AuraEnabled public String answer;

        public QuestionAnswerWrapper(String question, String description, String answer) {
            this.question = question;
            this.description = description;
            this.answer = answer;
        }
    }
}