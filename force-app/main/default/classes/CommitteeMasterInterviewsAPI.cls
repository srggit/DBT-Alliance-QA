/**
 * Portal endpoint: given a Committee Master Id (the logged-in committee member),
 * return every Interview evaluation row assigned to that person, plus a single
 * applicant name for each interview's Proposal.
 *
 * GET /services/apexrest/getCommitteeMasterInterviews?committeeMasterId=<Id>
 */
@RestResource(urlMapping='/getCommitteeMasterInterviews')
global without sharing class CommitteeMasterInterviewsAPI {

    private static final String INTERVIEW_MEMBER_TYPE = 'DCM';

    @HttpGet
    global static ResponseWrapper getInterviews() {
        ResponseWrapper response = new ResponseWrapper();

        String committeeMasterId = RestContext.request != null
            ? RestContext.request.params.get('committeeMasterId')
            : null;

        if (String.isBlank(committeeMasterId)) {
            response.success = false;
            response.message = 'Missing required parameter: committeeMasterId';
            return response;
        }

        Id masterId;
        try {
            masterId = Id.valueOf(committeeMasterId);
        } catch (Exception e) {
            response.success = false;
            response.message = 'Invalid committeeMasterId.';
            return response;
        }

        try {
            List<Proposal_Committee_Interview_Evaluation__c> evaluations = [
                SELECT Id, Name, Interview_Evaluation_Status__c,
                       Interview__c, Interview__r.Name, Interview__r.Status__c,
                       Interview__r.Start_Date_Time__c, Interview__r.End_Date_Time__c,
                       Interview__r.Proposal__c, Interview__r.Proposal__r.Proposal_Id__c,
                       Interview__r.Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name,
                       Proposal_Committee__c, Proposal_Committee__r.Name, Proposal_Committee__r.Type__c,
                       Proposal_Committee__r.Committee_Member__r.Committee_Master__r.First_Name__c,
                       Proposal_Committee__r.Committee_Member__r.Committee_Master__r.Last_Name__c
                FROM Proposal_Committee_Interview_Evaluation__c
                WHERE Proposal_Committee__r.Committee_Member__r.Committee_Master__c = :masterId
                AND Proposal_Committee__r.Type__c = :INTERVIEW_MEMBER_TYPE
                ORDER BY Interview__r.Start_Date_Time__c NULLS LAST, Name
            ];

            // Collect the proposals we need an applicant name for.
            Set<Id> proposalIds = new Set<Id>();
            for (Proposal_Committee_Interview_Evaluation__c eval : evaluations) {
                if (eval.Interview__r != null && eval.Interview__r.Proposal__c != null) {
                    proposalIds.add(eval.Interview__r.Proposal__c);
                }
            }

            // One applicant name per proposal. Coordinator wins; otherwise the
            // earliest-created applicant. First row seen per proposal is kept.
            Map<Id, String> applicantNameByProposal = new Map<Id, String>();
            if (!proposalIds.isEmpty()) {
                for (Applicant_Proposal_Association__c apa : [
                    SELECT Proposal__c, Contact__r.Name, Is_Coordinator__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c IN :proposalIds
                    AND Contact__c != null
                    ORDER BY Is_Coordinator__c DESC NULLS LAST, CreatedDate ASC
                ]) {
                    if (!applicantNameByProposal.containsKey(apa.Proposal__c)) {
                        applicantNameByProposal.put(apa.Proposal__c, apa.Contact__r.Name);
                    }
                }
            }

            List<InterviewRow> rows = new List<InterviewRow>();
            for (Proposal_Committee_Interview_Evaluation__c eval : evaluations) {
                InterviewRow row = new InterviewRow();
                row.evaluationId = eval.Id;
                row.evaluationName = eval.Name;
                row.evaluationStatus = eval.Interview_Evaluation_Status__c;

                row.interviewId = eval.Interview__c;
                if (eval.Interview__r != null) {
                    row.interviewName = eval.Interview__r.Name;
                    row.interviewStatus = eval.Interview__r.Status__c;
                    row.startDateTime = eval.Interview__r.Start_Date_Time__c;
                    row.endDateTime = eval.Interview__r.End_Date_Time__c;
                    row.proposalId = eval.Interview__r.Proposal__c;
                    row.proposalNumber = eval.Interview__r.Proposal__r.Proposal_Id__c;
                    row.applicantName = applicantNameByProposal.get(eval.Interview__r.Proposal__c);
                    row.schemeName = eval.Interview__r.Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name;
                }

                row.proposalCommitteeId = eval.Proposal_Committee__c;
                row.proposalCommitteeName = eval.Proposal_Committee__r != null ? eval.Proposal_Committee__r.Name : null;
                if (eval.Proposal_Committee__r != null
                        && eval.Proposal_Committee__r.Committee_Member__r != null
                        && eval.Proposal_Committee__r.Committee_Member__r.Committee_Master__r != null) {
                    row.committeeMemberFirstName = eval.Proposal_Committee__r.Committee_Member__r.Committee_Master__r.First_Name__c;
                    row.committeeMemberLastName = eval.Proposal_Committee__r.Committee_Member__r.Committee_Master__r.Last_Name__c;
                }

                rows.add(row);
            }

            response.success = true;
            response.message = rows.isEmpty() ? 'No interviews found.' : 'Interviews found.';
            response.totalSize = rows.size();
            response.interviews = rows;

        } catch (Exception e) {
            response.success = false;
            response.message = 'An error occurred: ' + e.getMessage();
        }

        return response;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public Integer totalSize = 0;
        public List<InterviewRow> interviews = new List<InterviewRow>();
    }

    global class InterviewRow {
        public String evaluationId;
        public String evaluationName;
        public String evaluationStatus;

        public String interviewId;
        public String interviewName;
        public String interviewStatus;
        public Datetime startDateTime;
        public Datetime endDateTime;

        public String proposalId;
        public String proposalNumber;
        public String schemeName;
        public String applicantName;

        public String proposalCommitteeId;
        public String proposalCommitteeName;
        public String committeeMemberFirstName;
        public String committeeMemberLastName;
    }
}