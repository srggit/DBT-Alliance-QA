@RestResource(urlMapping='/InstitutionApplicationsAPI/*')
global without sharing class InstitutionApplicationsAPI {

    // Scheme name -> role that is allowed to submit for that scheme.
    // ECF/CPHE require Supervisor; IF/CPHI require Sponsor.
    private static final Map<String, String> SCHEME_TO_REQUIRED_ROLE = new Map<String, String>{
        'Early Career Fellowship - Basic [ECF]' => 'Supervisor',
        'Clinical and Public Health Early Career Research Fellowship – [CPHE]' => 'Supervisor',
        'Intermediate Fellowship - Basic[IF]' => 'Sponsor',
        'Clinical and Public Health Intermediate Research Fellowship - [CPHI]' => 'Sponsor'
    };

    @HttpGet
    global static ResponseWrapper getApplications() {
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

            // Step 1: query PPA (Proposal_Participant_Association__c) by
            // Participant__c = the passed-in contactId. This contact is the
            // participant/endorser sitting directly on the proposal
            // (e.g. Supervisor/Sponsor), not resolved via any Account/host.
            List<Proposal_Participant_Association__c> ppaList = [
                SELECT Id, Participant__c,Participant__r.Name,Document_Status__c, Document_Uploaded__c, Document_URL__c,Roles__c,Proposal__r.Peer_Application_Stage__c,
					   Proposal__c,Proposal__r.Name,Proposal__r.Proposal_Id__c,Proposal__r.Proposal_Status__c,Proposal__r.Application_Stages__c,
                       Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name
                FROM Proposal_Participant_Association__c
                WHERE Participant__c = :conId
                AND Proposal__c != null
            ];

            if (ppaList.isEmpty()) {
                response.success = true;
                response.message = 'No applications found for this contact.';
                response.data    = new List<ApplicationItem>();
                return response;
            }

            Set<Id> proposalIds = new Set<Id>();
            for (Proposal_Participant_Association__c ppa : ppaList) {
                proposalIds.add(ppa.Proposal__c);
            }

            // Step 2: resolve the coordinating applicant per proposal via APA
            // (Applicant_Proposal_Association__c) where Is_Coordinator__c = true.
            Map<Id, Applicant_Proposal_Association__c> proposalToCoordinatorApa = new Map<Id, Applicant_Proposal_Association__c>();
            List<Applicant_Proposal_Association__c> coordinatorApaList = [
                SELECT Id, Proposal__c, Contact__c, Contact__r.Name
                FROM Applicant_Proposal_Association__c
                WHERE Proposal__c IN :proposalIds
                AND Is_Coordinator__c = true
            ];
            for (Applicant_Proposal_Association__c apa : coordinatorApaList) {
                // First match wins; expected to be unique per proposal.
                if (!proposalToCoordinatorApa.containsKey(apa.Proposal__c)) {
                    proposalToCoordinatorApa.put(apa.Proposal__c, apa);
                }
            }

            List<ApplicationItem> applications = new List<ApplicationItem>();

            for (Proposal_Participant_Association__c ppa : ppaList) {
                Applicant_Proposal_Association__c coordinatorApa = proposalToCoordinatorApa.get(ppa.Proposal__c);

                ApplicationItem item = new ApplicationItem();
                item.applicantName    = coordinatorApa != null ? coordinatorApa.Contact__r.Name : null;
                item.applicantId      = coordinatorApa != null ? coordinatorApa.Contact__c : null;
                item.apaId            = coordinatorApa != null ? coordinatorApa.Id : null; // Is_Coordinator__c = true APA record
                item.ppaId            = ppa.Id;
				item.participantId    = ppa.Participant__c;
				item.participantName  = ppa.Participant__r.Name;
                item.participantRole  = ppa.Roles__c;
                item.applicationName  = ppa.Proposal__r.Name;
                item.proposalId       = ppa.Proposal__r.Proposal_Id__c;
                item.proposalRecordId = ppa.Proposal__c;
                item.proposalPeerApplicationStage = ppa.Proposal__r.Peer_Application_Stage__c;
                item.scheme           = ppa.Proposal__r.Yearly_Scheme__r.Scheme_Items__r != null ? ppa.Proposal__r.Yearly_Scheme__r.Scheme_Items__r.Name : null;
                item.stage             = ppa.Proposal__r.Application_Stages__c;
                item.status            = ppa.Proposal__r.Proposal_Status__c;
                item.documentStatus    = ppa.Document_Status__c;
                item.documentUrl       = ppa.Document_URL__c;
                item.participantCanSubmit = computeCanSubmit(item.scheme, item.participantRole);
                applications.add(item);
            }

            response.success = true;
            response.message = 'Applications retrieved successfully.';
            response.data    = applications;
            return response;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
            return response;
        }
    }

    // Determines whether this participant's role is the one allowed to
    // submit for the given scheme (ECF/CPHE -> Supervisor, IF/CPHI -> Sponsor).
    // Role comparison is case-insensitive and matches on "contains" since
    // Roles__c may be a multi-select / semicolon-delimited value.
    private static Boolean computeCanSubmit(String schemeName, String participantRole) {
        if (String.isBlank(schemeName) || String.isBlank(participantRole)) {
            return false;
        }
        String requiredRole = SCHEME_TO_REQUIRED_ROLE.get(schemeName);
        if (String.isBlank(requiredRole)) {
            return false;
        }
        return participantRole.toLowerCase().contains(requiredRole.toLowerCase());
    }

    global class ResponseWrapper {
        global Boolean success;
        global String message;
        global List<ApplicationItem> data;
    }

    // Single wrapper combining the PPA (participant/document) row with the
    // resolved coordinating applicant identity and the proposal's
    // scheme/stage/status, for a table sourced entirely by contactId
    // (PPA.Participant__c = contactId).
    global class ApplicationItem {
        global String applicantName;
        global String applicantId;
        global Id apaId; // Is_Coordinator__c = true APA record for this proposal
        global Id ppaId; // this PPA record's own Id
		global String participantId;
		global String participantName;
        global String participantRole; // PPA.Roles__c - this participant's role (e.g. Supervisor/Sponsor)
        global String applicationName;
        global String proposalId;
        global String proposalRecordId;
        global String proposalPeerApplicationStage;
        global String scheme;
        global String stage;
        global String status;
        global String documentStatus;
        global String documentUrl;
        global Boolean participantCanSubmit; // true if this participant's role matches the scheme's required submitter role
    }
}