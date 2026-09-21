public with sharing class ScheduleInterviewController {

    // Only Proposal Committee members of this Type get an interview evaluation row.
    private static final String INTERVIEW_MEMBER_TYPE = 'DCM';

    // Fallback status when the caller doesn't send one.
    private static final String DEFAULT_INTERVIEW_STATUS = 'Upcoming';

    @AuraEnabled
    public static Result scheduleInterview(Id proposalId, Datetime startDateTime, Datetime endDateTime, String status) {

        if (proposalId == null) {
            throw new AuraHandledException('Please select a Proposal.');
        }
        if (startDateTime == null) {
            throw new AuraHandledException('Start Date & Time is required.');
        }
        if (endDateTime != null && endDateTime < startDateTime) {
            throw new AuraHandledException('End Date & Time cannot be before Start Date & Time.');
        }

        // The DCM committee members tied to this proposal - one evaluation row per member.
        List<Proposal_Committee__c> dcmMembers = [
            SELECT Id
            FROM Proposal_Committee__c
            WHERE Proposal__c = :proposalId
            AND Type__c = :INTERVIEW_MEMBER_TYPE
        ];

        if (dcmMembers.isEmpty()) {
            throw new AuraHandledException('No DCM committee members found');
        }

        Interview__c interview = new Interview__c(
            Proposal__c = proposalId,
            Start_Date_Time__c = startDateTime,
            End_Date_Time__c = endDateTime,
            Status__c = String.isBlank(status) ? DEFAULT_INTERVIEW_STATUS : status
        );
        insert interview;

        List<Proposal_Committee_Interview_Evaluation__c> evaluations =
            new List<Proposal_Committee_Interview_Evaluation__c>();
        for (Proposal_Committee__c member : dcmMembers) {
            evaluations.add(new Proposal_Committee_Interview_Evaluation__c(
                Interview__c = interview.Id,
                Proposal_Committee__c = member.Id
            ));
        }
        insert evaluations;

        return new Result(interview.Id, evaluations.size());
    }

    public class Result {
        @AuraEnabled public Id interviewId;
        @AuraEnabled public Integer evaluationCount;

        public Result(Id interviewId, Integer evaluationCount) {
            this.interviewId = interviewId;
            this.evaluationCount = evaluationCount;
        }
    }
}