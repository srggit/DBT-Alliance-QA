/**
 * @description REST API to fetch Institution Dashboard data (Header Info, Total Applications,
 *              Active Grants, Institution Work Queue) for a given Contact's Account,
 *              resolved via Contact.AccountId -> Applicant_Host_Association__c.Host__c.
 */
@RestResource(urlMapping='/InstitutionDashboardAPI/*')
global without sharing class InstitutionDashboardAPI {

    @HttpGet
    global static ResponseWrapper getDashboardData() {
        ResponseWrapper response = new ResponseWrapper();
        try {
            RestRequest req = RestContext.request;
            String contactId = req.params.get('contactId');

            if (String.isBlank(contactId)) {
                response.success = false;
                response.message = 'contactId is required.';
                return response;
            }

            Id conId;
            try {
                conId = (Id) contactId;
                if (conId.getSObjectType() != Contact.SObjectType) {
                    response.success = false;
                    response.message = 'Invalid contactId: not a Contact Id.';
                    return response;
                }
            } catch (Exception e) {
                response.success = false;
                response.message = 'Invalid contactId format.';
                return response;
            }

            // Step 1: resolve the Account off the Contact's standard AccountId field.
            List<Contact> conList = [
                SELECT Id, AccountId,
                       Account.Name, Account.BillingStreet, Account.BillingCity,
                       Account.BillingState, Account.BillingPostalCode, Account.BillingCountry
                FROM Contact
                WHERE Id = :conId
                LIMIT 1
            ];

            if (conList.isEmpty()) {
                response.success = false;
                response.message = 'Contact not found.';
                return response;
            }

            Contact con = conList[0];

            if (con.AccountId == null) {
                response.success = false;
                response.message = 'Contact is not associated with an Account.';
                return response;
            }

            // Step 2: header info comes straight off the Contact's Account.
            HeaderInfo header = new HeaderInfo();
            header.institutionName   = con.Account.Name;
            header.billingStreet     = con.Account.BillingStreet;
            header.billingCity       = con.Account.BillingCity;
            header.billingState      = con.Account.BillingState;
            header.billingPostalCode = con.Account.BillingPostalCode;
            header.billingCountry    = con.Account.BillingCountry;
            header.displayLocation   = buildDisplayLocation(con.Account.BillingCity, con.Account.BillingCountry);
            header.lastSyncedDate    = System.now();

            // Step 3: query AHA by Host__c = the Contact's AccountId. This surfaces
            // all proposals tagged to this institution, not just ones where this
            // specific contact is the Applicant__c on the AHA row.
            List<Applicant_Host_Association__c> ahaList = [
                SELECT Id, Applicant__c, Applicant__r.Name,
                       Host__c,CreatedDate,
                       Proposal__c,
                       Proposal__r.Proposal_Id__c,Proposal__r.Peer_Application_Stage__c,
                       Proposal__r.Proposal_Status__c,Proposal__r.Application_Stages__c,
                       Proposal__r.Yearly_Scheme__c,
                       Proposal__r.Yearly_Scheme__r.Name,Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name
                FROM Applicant_Host_Association__c
                WHERE Host__c = :con.AccountId
                AND Proposal__c != null
            ];

            // Dedupe by Proposal so a proposal is only counted/listed once,
            // even if multiple AHA rows point to the same Proposal.
            Map<Id, Applicant_Host_Association__c> proposalToAha = new Map<Id, Applicant_Host_Association__c>();
            for (Applicant_Host_Association__c aha : ahaList) {
                if (!proposalToAha.containsKey(aha.Proposal__c)) {
                    proposalToAha.put(aha.Proposal__c, aha);
                }
            }

            // Step 4: resolve the APA (Applicant_Proposal_Association__c) junction Id
            // for each Proposal/Applicant pair, since AHA doesn't carry it directly.
            Set<Id> proposalIds  = proposalToAha.keySet();
            Set<Id> applicantIds = new Set<Id>();
            for (Applicant_Host_Association__c aha : proposalToAha.values()) {
                if (aha.Applicant__c != null) {
                    applicantIds.add(aha.Applicant__c);
                }
            }

            Map<String, Id> proposalApplicantToApaId = new Map<String, Id>();
            if (!proposalIds.isEmpty() && !applicantIds.isEmpty()) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Proposal__c, Contact__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c IN :proposalIds
                    AND Contact__c IN :applicantIds
                ];
                for (Applicant_Proposal_Association__c apa : apaList) {
                    String key = apa.Proposal__c + '_' + apa.Contact__c;
                    // First match wins; a proposal/applicant pair is expected to be unique.
                    if (!proposalApplicantToApaId.containsKey(key)) {
                        proposalApplicantToApaId.put(key, apa.Id);
                    }
                }
            }

            Integer totalApplications = proposalToAha.size();
            Integer activeGrants = 0;
            List<WorkQueueItem> workQueue = new List<WorkQueueItem>();
            List<ApplicantPortfolioItem> applicantPortfolio = new List<ApplicantPortfolioItem>();

            for (Applicant_Host_Association__c aha : proposalToAha.values()) {
                String status = aha.Proposal__r.Proposal_Status__c;
                if (status == 'Award') {
                    activeGrants++;
                }

                String applicantName = aha.Applicant__r != null ? aha.Applicant__r.Name : null;
                String applicantId   = aha.Applicant__c;
                String proposalId    = aha.Proposal__r.Proposal_Id__c;
                String proposalrecordId = aha.Proposal__c;
                String proposalPeerApplicationStage = aha.Proposal__r.Peer_Application_Stage__c;
                String applicationStage = aha.Proposal__r.Application_Stages__c;
                String scheme        = aha.Proposal__r.Yearly_Scheme__r.Scheme_Items__r != null ? aha.Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name : null;
                String stage         = status;
                String createdDate = aha.CreatedDate != null ? aha.CreatedDate.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'', 'UTC') : null;
                String apaKey        = proposalrecordId + '_' + applicantId;
                Id apaId             = proposalApplicantToApaId.get(apaKey);

                WorkQueueItem item = new WorkQueueItem();
                item.applicantName = applicantName;
                item.applicantId   = applicantId;
                item.apaId         = apaId;
                item.proposalId    = proposalId;
				item.proposalrecordId = proposalrecordId;
                item.proposalPeerApplicationStage = proposalPeerApplicationStage;
                item.applicationStage = applicationStage;
                item.scheme        = scheme;
                item.stage         = stage;
                item.createdDate   = createdDate;
                workQueue.add(item);

                ApplicantPortfolioItem portfolioItem = new ApplicantPortfolioItem();
                portfolioItem.applicantName    = applicantName;
                portfolioItem.applicantId      = applicantId;
                portfolioItem.apaId            = apaId;
                portfolioItem.proposalId       = proposalId;
                portfolioItem.proposalrecordId = proposalrecordId;
                portfolioItem.proposalPeerApplicationStage = proposalPeerApplicationStage;
                portfolioItem.applicationStage = applicationStage;
                portfolioItem.scheme           = scheme;
                portfolioItem.stage            = stage;
                portfolioItem.createdDate   = createdDate;
                applicantPortfolio.add(portfolioItem);
            }

            DashboardData data = new DashboardData();
            data.header             = header;
            data.totalApplications  = totalApplications;
            data.activeGrants       = activeGrants;
            data.workQueue          = workQueue;
            data.applicantPortfolio = applicantPortfolio;

            response.success = true;
            response.message = 'Dashboard data retrieved successfully.';
            response.data    = data;
            return response;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
            return response;
        }
    }

    // Builds a "City, Country" style string, skipping blanks gracefully.
    private static String buildDisplayLocation(String city, String country) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) {
            parts.add(city);
        }
        if (String.isNotBlank(country)) {
            parts.add(country);
        }
        return String.join(parts, ', ');
    }

    global class ResponseWrapper {
        global Boolean success;
        global String message;
        global DashboardData data;
    }

    global class DashboardData {
        global HeaderInfo header;
        global Integer totalApplications;
        global Integer activeGrants;
        global List<WorkQueueItem> workQueue;
        global List<ApplicantPortfolioItem> applicantPortfolio;
    }

    global class HeaderInfo {
        global String institutionName;
        global String billingStreet;
        global String billingCity;
        global String billingState;
        global String billingPostalCode;
        global String billingCountry;
        global String displayLocation;
        global Datetime lastSyncedDate;
    }

    global class WorkQueueItem {
        global String applicantName;
        global String applicantId;
        global String apaId;
        global String proposalId;
		global String proposalrecordId;
        global String proposalPeerApplicationStage;
        global String applicationStage;
        global String scheme;
        global String stage;
        global String createdDate;
    }

    // Lean wrapper for the "Unified Applicant Portfolio" table.
    // Intentionally omits Pending Action, Last Updated, and Action -
    // those are UI-only concerns not sourced from this API.
    global class ApplicantPortfolioItem {
        global String applicantName;
        global String applicantId;
        global String apaId;
        global String proposalId;
        global String proposalrecordId;
        global String proposalPeerApplicationStage;
        global String applicationStage;
        global String scheme;
        global String stage;
        global String createdDate;
    }
}