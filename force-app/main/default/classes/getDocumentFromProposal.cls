@RestResource(urlMapping='/getDocumentFromProposal')
global with sharing class getDocumentFromProposal {

    @HttpGet
    global static ResponseWrapper doGet() {

        ResponseWrapper response = new ResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String proposalRecordId = req.params.get('proposalid');     // Proposal record Id

            if (String.isBlank(proposalRecordId)) {
                response.success = false;
                response.message = 'Proposal Id is required.';
                return response;
            }

            // ---- Step 1: Find the Applicant Proposal Association matching both Ids ----
            List<Applicant_Proposal_Association__c> apaList = [
                SELECT Id, Name, Proposal__c, Proposal__r.Proposal_Id__c
                FROM Applicant_Proposal_Association__c
                WHERE Proposal__c = :proposalRecordId
                LIMIT 1
            ];

            if (apaList.isEmpty()) {
                response.success = false;
                response.message = 'No Applicant Proposal Association found for the given Proposal Id combination.';
                return response;
            }

            Id apaId = apaList[0].Id;

            // ---- Step 2: Query documents linked to that Applicant Proposal Association ----
            List<User_Documents__c> documents = [
                SELECT Id, Name, User_Document_Name__c, Document_Link__c, Roles__c,
                       Stages__c, Upload_Status__c, Is_Required__c, Contact__c,
                       Applicant_Proposal_Association__c
                FROM User_Documents__c
                WHERE Applicant_Proposal_Association__c = :apaId
            ];

            response.success = true;
            response.message = 'Documents retrieved successfully.';
            response.applicantProposalAssociationId = apaId;
            response.totalDocuments = documents.size();
            response.documentDetails = wrapDocumentDetails(documents);

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
        }

        return response;
    }

    // ---- Helper: map User_Documents__c list to typed wrapper list ----
    private static List<DocumentDetailsWrapper> wrapDocumentDetails(List<User_Documents__c> records) {
        List<DocumentDetailsWrapper> wrappedList = new List<DocumentDetailsWrapper>();

        for (User_Documents__c doc : records) {
            DocumentDetailsWrapper dw = new DocumentDetailsWrapper();
            dw.documentId = doc.Id;
            dw.documentName = doc.User_Document_Name__c;
            dw.documentLink = doc.Document_Link__c;
            dw.roles = doc.Roles__c;
            dw.stage = doc.Stages__c;
            dw.uploadStatus = doc.Upload_Status__c;
            dw.isRequired = doc.Is_Required__c;
            dw.contactId = doc.Contact__c;
            dw.applicantProposalAssociationId = doc.Applicant_Proposal_Association__c;
            wrappedList.add(dw);
        }

        return wrappedList;
    }

    // ---- Wrapper classes ----
    global class ResponseWrapper {
        global Boolean success;
        global String message;
        global Id applicantProposalAssociationId;
        global Integer totalDocuments;
        global List<DocumentDetailsWrapper> documentDetails;
    }

    global class DocumentDetailsWrapper {
        global String documentId;
        global String documentName;
        global String documentLink;
        global String roles;
        global String stage;
        global String uploadStatus;
        global Boolean isRequired;
        global String contactId;
        global String applicantProposalAssociationId;
    }
}