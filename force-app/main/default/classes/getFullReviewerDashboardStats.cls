@RestResource(urlMapping='/getFullReviewerDashboardStats')
global with sharing class getFullReviewerDashboardStats {

    @HttpGet
    global static ResponseWrapper doGet() {

        ResponseWrapper response = new ResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String reviewerId = req.params.get('Reviewer__c');

            if (String.isBlank(reviewerId)) {
                response.success = false;
                response.message = 'Reviewer Id is required';
                return response;
            }

            // ---- assignedApplication: total Reviewer_Mapping__c records for this reviewer ----
            Integer assignedApplication = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId AND Reviewer__r.Reviewer_Type__c ='Peer'
            ];

            // ---- pendingInvitations: Status__c is null OR 'In-Progress' ----
            Integer pendingInvitations = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId
                AND (Status__c = 'Assigned' OR Status__c = 'In-Progress') AND  Reviewer__r.Reviewer_Type__c ='Peer'
            ];

            // ---- completedReviews: Status__c = 'Accepted' ----
            Integer completedReviews = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId
                AND Status__c = 'Accepted' AND Reviewer_Type__c ='Peer' AND  Reviewer__r.Reviewer_Type__c ='Peer'
            ];

            // ---- upcomingDeadline: Status__c != 'Accepted' AND Deadline_Date__c within next 4 days ----
            Date todayDate = Date.today();
            Date fourDaysOut = todayDate.addDays(4);

            Integer upcomingDeadline = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId
                AND Status__c != 'Accepted'
                AND Deadline_Date__c != null
                AND Deadline_Date__c >= :todayDate
                AND Deadline_Date__c <= :fourDaysOut AND Reviewer__r.Reviewer_Type__c ='Peer'
            ];

            // ---- Full mapping details list (non-Tentative) for this reviewer ----
            List<Reviewer_Mapping__c> mappings = [
                SELECT Id, Status__c, Proposal__c, Reviewer__c, Deadline_Date__c,
                       Proposal__r.Proposal_Id__c,
                       Proposal__r.Yearly_Scheme__r.Scheme__c
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId AND Status__c != 'Tentative' AND Reviewer__r.Reviewer_Type__c ='Peer'
            ];

            // ---- Tentative mapping details list for this reviewer ----
            List<Reviewer_Mapping__c> tentativemappings = [
                SELECT Id, Status__c, Proposal__c, Reviewer__c, Deadline_Date__c,
                       Proposal__r.Proposal_Id__c,
                       Proposal__r.Yearly_Scheme__r.Scheme__c
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId AND Status__c = 'Tentative' AND Reviewer__r.Reviewer_Type__c ='Peer'
            ];

            // ---- Collect proposal Ids from BOTH lists so applicant names cover both ----
            Set<Id> proposalIds = new Set<Id>();
            for (Reviewer_Mapping__c rm : mappings) {
                if (rm.Proposal__c != null) {
                    proposalIds.add(rm.Proposal__c);
                }
            }
            for (Reviewer_Mapping__c rm : tentativemappings) {
                if (rm.Proposal__c != null) {
                    proposalIds.add(rm.Proposal__c);
                }
            }

            Map<Id, List<String>> proposalIdToApplicantNames = new Map<Id, List<String>>();
            List<Applicant_Proposal_Association__c> associations = [
                SELECT Id, Proposal__c, Contact__c, Contact__r.Name, Contact__r.Title__c
                FROM Applicant_Proposal_Association__c
                WHERE Proposal__c IN :proposalIds 
                AND Contact__c != null
            ];

            for (Applicant_Proposal_Association__c apa : associations) {
                if (apa.Proposal__c == null) continue;

                if (!proposalIdToApplicantNames.containsKey(apa.Proposal__c)) {
                    proposalIdToApplicantNames.put(apa.Proposal__c, new List<String>());
                }
                if (apa.Contact__r != null) {
                    String applicantName = apa.Contact__r.Name;

                    // ---- Prefix title only if it's not blank ----
                    if (String.isNotBlank(apa.Contact__r.Title__c)) {
                        applicantName = apa.Contact__r.Title__c + ' ' + applicantName;
                    }

                    proposalIdToApplicantNames.get(apa.Proposal__c).add(applicantName);
                }
            }

            List<ReviewerMappingWrapper> resultList = new List<ReviewerMappingWrapper>();
            List<TentativeReviewerMappingWrapper> tentativeresultList = new List<TentativeReviewerMappingWrapper>();

            for (Reviewer_Mapping__c rm : mappings) {
                ReviewerMappingWrapper rmw = new ReviewerMappingWrapper();
                rmw.reviewerMappingId = rm.Id;
                rmw.status = rm.Status__c;
                rmw.proposalId = rm.Proposal__c;
                rmw.proposalNumber = rm.Proposal__r?.Proposal_Id__c;
                rmw.schemeName = rm.Proposal__r?.Yearly_Scheme__r?.Scheme__c;
                rmw.deadlineDate = rm.Deadline_Date__c;
                rmw.applicantNames = proposalIdToApplicantNames.containsKey(rm.Proposal__c)
                                    ? proposalIdToApplicantNames.get(rm.Proposal__c)
                                    : new List<String>();
                resultList.add(rmw);
            }

            for (Reviewer_Mapping__c rm : tentativemappings) {
                TentativeReviewerMappingWrapper trmw = new TentativeReviewerMappingWrapper();
                trmw.reviewerMappingId = rm.Id;
                trmw.status = rm.Status__c;
                trmw.proposalId = rm.Proposal__c;
                trmw.proposalNumber = rm.Proposal__r?.Proposal_Id__c;
                trmw.schemeName = rm.Proposal__r?.Yearly_Scheme__r?.Scheme__c;
                trmw.deadlineDate = rm.Deadline_Date__c;
                trmw.applicantNames = proposalIdToApplicantNames.containsKey(rm.Proposal__c)
                                    ? proposalIdToApplicantNames.get(rm.Proposal__c)
                                    : new List<String>();
                tentativeresultList.add(trmw);
            }

            response.success = true;
            response.message = 'Success';
            response.assignedApplication = assignedApplication;
            response.pendingInvitations = pendingInvitations;
            response.completedReviews = completedReviews;
            response.upcomingDeadline = upcomingDeadline;
            response.reviewerMappingDetails = resultList;
            response.tentativereviewerMappingDetails = tentativeresultList;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
        }

        return response;
    }

    global class ReviewerMappingWrapper {
        global String reviewerMappingId;
        global Date deadlineDate;
        global String schemeName;
        global String proposalId;
        global String proposalNumber;
        global String status;
        global List<String> applicantNames;
    }

    global class TentativeReviewerMappingWrapper {
        global String reviewerMappingId;
        global Date deadlineDate;
        global String schemeName;
        global String proposalId;
        global String proposalNumber;
        global String status;
        global List<String> applicantNames;
    }

    // ---- Wrapper class ----
    global class ResponseWrapper {
        global Boolean success;
        global String message;
        global Integer assignedApplication;
        global Integer pendingInvitations;
        global Integer completedReviews;
        global Integer upcomingDeadline;
        global List<ReviewerMappingWrapper> reviewerMappingDetails;
        global List<TentativeReviewerMappingWrapper> tentativereviewerMappingDetails;
    }
}