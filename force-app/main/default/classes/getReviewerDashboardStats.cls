@RestResource(urlMapping='/getReviewerDashboardStats')
global with sharing class getReviewerDashboardStats {

    @HttpGet
    global static ResponseWrapper doGet() {

        ResponseWrapper response = new ResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String reviewerId = req.params.get('Reviewer__c');

            System.debug('req ====> ' + req);
            System.debug('reviewerId ====> ' + reviewerId);

            if (String.isBlank(reviewerId)) {
                response.success = false;
                response.message = 'Reviewer Id is required';
                return response;
            }

            // ---- assignedApplication: total Reviewer_Mapping__c records for this reviewer ----
            Integer assignedApplication = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId AND Reviewer__r.Reviewer_Type__c !='Peer'
            ];
            System.debug('assignedApplication ==> ' + assignedApplication);

            // ---- pendingInvitations: Status__c is null OR 'In-Progress' ----
            Integer pendingInvitations = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId
                AND (Status__c = 'Assigned' OR Status__c = 'In-Progress') AND Reviewer__r.Reviewer_Type__c !='Peer'
            ];

            // ---- completedReviews: Status__c = 'Accepted' ----
            Integer completedReviews = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId
                AND Status__c = 'Accepted' AND Reviewer__r.Reviewer_Type__c !='Peer'
            ];

            // ---- Full mapping details list (non-Tentative) for this reviewer ----
            List<Reviewer_Mapping__c> mappings = [
                SELECT Id, Status__c, Proposal__c, Reviewer__c, Deadline_Date__c,
                       Proposal__r.Proposal_Id__c,
                       Proposal__r.Application_Stages__c,
                       Proposal__r.Yearly_Scheme__r.Scheme__c,
                       Proposal__r.Yearly_Scheme__r.Prelim_Deadline_Date__c,
                       Proposal__r.Yearly_Scheme__r.Peer_Deadline_Date__c,
                       Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name 
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId AND Status__c Not IN ('Tentative','Pending') AND Reviewer__r.Reviewer_Type__c !='Peer'
            ];

            // ---- Tentative mapping details list for this reviewer ----
            List<Reviewer_Mapping__c> tentativemappings = [
                SELECT Id, Status__c, Proposal__c, Reviewer__c, Deadline_Date__c,
                       Proposal__r.Proposal_Id__c,
                       Proposal__r.Application_Stages__c,
                       Proposal__r.Yearly_Scheme__r.Scheme__c,
                       Proposal__r.Yearly_Scheme__r.Prelim_Deadline_Date__c,
                       Proposal__r.Yearly_Scheme__r.Peer_Deadline_Date__c,
                       Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name
                FROM Reviewer_Mapping__c
                WHERE Reviewer__c = :reviewerId AND Status__c = 'Tentative' AND Reviewer__r.Reviewer_Type__c !='Peer'
            ];

            // ---- upcomingDeadline: computed from yearly scheme deadlines based on proposal stage ----
            Date todayDate = Date.today();
            Date fourDaysOut = todayDate.addDays(4);
            Integer upcomingDeadline = 0;
            for (Reviewer_Mapping__c rm : mappings) {
                if (rm.Status__c != 'Accepted') {
                    Date resolvedDeadline = resolveDeadline(rm);
                    if (resolvedDeadline != null && resolvedDeadline >= todayDate && resolvedDeadline <= fourDaysOut) {
                        upcomingDeadline++;
                    }
                }
            }
            for (Reviewer_Mapping__c rm : tentativemappings) {
                if (rm.Status__c != 'Accepted') {
                    Date resolvedDeadline = resolveDeadline(rm);
                    if (resolvedDeadline != null && resolvedDeadline >= todayDate && resolvedDeadline <= fourDaysOut) {
                        upcomingDeadline++;
                    }
                }
            }

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
                rmw.schemeItemName = rm.Proposal__r?.Yearly_Scheme__r?.Scheme_Items__r.Name;
                // rmw.deadlineDate = rm.Deadline_Date__c;
                rmw.deadlineDate = resolveDeadline(rm);
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
                trmw.schemeItemName = rm.Proposal__r?.Yearly_Scheme__r?.Scheme_Items__r.Name;
                // trmw.deadlineDate = rm.Deadline_Date__c;
                trmw.deadlineDate = resolveDeadline(rm);
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
        global String schemeItemName;
        global String proposalId;
        global String proposalNumber;
        global String status;
        global List<String> applicantNames;
    }

    global class TentativeReviewerMappingWrapper {
        global String reviewerMappingId;
        global Date deadlineDate;
        global String schemeName;
        global String schemeItemName;
        global String proposalId;
        global String proposalNumber;
        global String status;
        global List<String> applicantNames;
    }

    // ---- Resolve deadline from Yearly Scheme based on Proposal's Application Stage ----
    // Prelims  -> Prelim_Deadline_Date__c
    // Full     -> Peer_Deadline_Date__c
    private static Date resolveDeadline(Reviewer_Mapping__c rm) {
        System.debug('resolveDeadline called for Reviewer_Mapping: ' + rm.Id);
        System.debug('  Proposal__r: ' + rm.Proposal__r);
        if (rm.Proposal__r != null) {
            System.debug('  Proposal__r.Yearly_Scheme__r: ' + rm.Proposal__r.Yearly_Scheme__r);
            System.debug('  Proposal__r.Application_Stages__c: ' + rm.Proposal__r.Application_Stages__c);
            if (rm.Proposal__r.Yearly_Scheme__r != null) {
                System.debug('  Prelim_Deadline_Date__c: ' + rm.Proposal__r.Yearly_Scheme__r.Prelim_Deadline_Date__c);
                System.debug('  Peer_Deadline_Date__c: ' + rm.Proposal__r.Yearly_Scheme__r.Peer_Deadline_Date__c);
            }
        }
        if (rm.Proposal__r == null || rm.Proposal__r.Yearly_Scheme__r == null) {
            System.debug('  -> returning null: Proposal__r or Yearly_Scheme__r is null');
            return null;
        }
        String appStage = rm.Proposal__r.Application_Stages__c;
        if (appStage == 'Prelims') {
            System.debug('  -> returning Prelim_Deadline_Date__c: ' + rm.Proposal__r.Yearly_Scheme__r.Prelim_Deadline_Date__c);
            return rm.Proposal__r.Yearly_Scheme__r.Prelim_Deadline_Date__c;
        } else if (appStage == 'Full') {
            System.debug('  -> returning Peer_Deadline_Date__c: ' + rm.Proposal__r.Yearly_Scheme__r.Peer_Deadline_Date__c);
            return rm.Proposal__r.Yearly_Scheme__r.Peer_Deadline_Date__c;
        }
        System.debug('  -> returning null: appStage does not match Prelims or Full. appStage = ' + appStage);
        return null;
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