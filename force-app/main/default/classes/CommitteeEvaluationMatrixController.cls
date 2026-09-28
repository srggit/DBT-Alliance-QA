public with sharing class CommitteeEvaluationMatrixController {

    // Only Proposal_Committee__c records whose own Status__c is 'Submitted' are included -
    // mirrors PeerEvaluationMatrixController's "Status__c = 'Submitted'" filter on
    // Reviewer_Mapping__c, applied here to the committee member's own submission status
    // instead.
    @AuraEnabled(cacheable=true)
    public static List<MemberEvaluationWrapper> getCommitteeEvaluations(Id proposalId) {
        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }

        List<Proposal_Committee__c> committeeMembers = [
            SELECT Id, Commitee_Member_Name__c
            FROM Proposal_Committee__c
            WHERE Proposal__c = :proposalId
            AND Status__c = 'Submitted'
            ORDER BY CreatedDate ASC
        ];

        if (committeeMembers.isEmpty()) {
            return new List<MemberEvaluationWrapper>();
        }

        Set<Id> committeeIds = new Set<Id>();
        for (Proposal_Committee__c pc : committeeMembers) {
            committeeIds.add(pc.Id);
        }

        Map<Id, List<Committee_Member_Evaluation__c>> evaluationsByCommittee = new Map<Id, List<Committee_Member_Evaluation__c>>();
        for (Committee_Member_Evaluation__c cme : [
            SELECT Id, Section_Detail__c, Question__c, Answer__c, Proposal_Committee__c
            FROM Committee_Member_Evaluation__c
            WHERE Proposal_Committee__c IN :committeeIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!evaluationsByCommittee.containsKey(cme.Proposal_Committee__c)) {
                evaluationsByCommittee.put(cme.Proposal_Committee__c, new List<Committee_Member_Evaluation__c>());
            }
            evaluationsByCommittee.get(cme.Proposal_Committee__c).add(cme);
        }

        List<MemberEvaluationWrapper> result = new List<MemberEvaluationWrapper>();
        for (Proposal_Committee__c pc : committeeMembers) {
            List<QuestionAnswerWrapper> answers = new List<QuestionAnswerWrapper>();
            List<Committee_Member_Evaluation__c> evaluations = evaluationsByCommittee.get(pc.Id);
            if (evaluations != null) {
                for (Committee_Member_Evaluation__c cme : evaluations) {
                    answers.add(new QuestionAnswerWrapper(cme.Section_Detail__c, cme.Question__c, cme.Answer__c));
                }
            }
            result.add(new MemberEvaluationWrapper(pc.Id, pc.Commitee_Member_Name__c, answers));
        }
        return result;
    }

    public class MemberEvaluationWrapper {
        @AuraEnabled public Id committeeId;
        @AuraEnabled public String memberName;
        @AuraEnabled public List<QuestionAnswerWrapper> answers;

        public MemberEvaluationWrapper(Id committeeId, String memberName, List<QuestionAnswerWrapper> answers) {
            this.committeeId = committeeId;
            this.memberName = memberName;
            this.answers = answers;
        }
    }

    public class QuestionAnswerWrapper {
        @AuraEnabled public String section;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;

        public QuestionAnswerWrapper(String section, String question, String answer) {
            this.section = section;
            this.question = question;
            this.answer = answer;
        }
    }
}