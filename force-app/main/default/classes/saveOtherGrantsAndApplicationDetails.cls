/*@RestResource(urlMapping='/saveOtherGrantsAndApplicationDetails')
global without sharing class saveOtherGrantsAndApplicationDetails {

    @HttpPost
    global static ResponseWrapper saveOtherGrantsAndApplicationDetails() {
        ResponseWrapper response = new ResponseWrapper();

        try {   
            String requestBody = RestContext.request.requestBody.toString();
            RequestWrapper req = (RequestWrapper) JSON.deserialize(requestBody, RequestWrapper.class);

            Id apaRecordId;

            if (!String.isBlank(req.apaId)) {
                apaRecordId = req.apaId;
            } 
            else if (!String.isBlank(req.proposalId)) {
                List<Applicant_Proposal_Association__c> associations = [
                    SELECT Id, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :req.proposalId
                    AND Contact__c = :req.contactId
                    LIMIT 1
                ];

                if (associations.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the provided proposalId';
                    return response;
                }

                apaRecordId = associations[0].Id;
            } else {
                response.success = false;
                response.message = 'Missing required field: provide either apaId or proposalId';
                return response;
            }

            Applicant_Proposal_Association__c updatedAPA = new Applicant_Proposal_Association__c(
                Id = apaRecordId,
                Have_you_applied_to_Alliance_before__c = req.firstApplicationWithAlliance,
                Previous_Application_Reference_Number__c = req.previousApplReferenceNumber,
                Previous_Application_Project_Title__c = req.previousApplProjectTitle_Alliance,
                Decision_on_previous_application__c = req.prevoiusApplDecision,
                Key_difference_from_previous_application__c = req.keyDifferencesFromPreviousApplication,
                Other_Ongoing_Scheme__c = req.otherOngoingSchemaName,
                Other_Ongoing_Applications__c = req.otherOngoingApplications,
                Name_of_the_Ongoing_funding_agency__c = req.nameOfFundingAgencyAndScheme,
                Ongoing_Project_Title__c = req.projectTitle_Ongoing,
                Abstract_Ongoing__c = req.abstract_Ongoing,
                Overlap_with_current_IA_application__c = req.degreeOfOverlapWithCurrentAllianceApplication,
                Type_of_funding__c = req.typeOfFunding_Ongoing,
                Your_Role_on_the_Application__c = req.yourRoleOnApplication_Ongoing,
                Expected_date_of_decision__c = req.expectedDateOfDecision_Ongoing
            );
            update updatedAPA;

            response.success = true;
            response.message = 'Other grants and application details saved successfully';
            response.apaId = updatedAPA.Id;
        }
        catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();
        }
        return response;
    }

    global class RequestWrapper {
        public String proposalId;
        public String apaId;
        public String contactId;
        public String firstApplicationWithAlliance;
        public String previousApplReferenceNumber;
        public String previousApplProjectTitle_Alliance;
        public String prevoiusApplDecision;
        public String keyDifferencesFromPreviousApplication;
        public String otherOngoingApplications;
        public String otherOngoingSchemaName;
        public String nameOfFundingAgencyAndScheme;
        public String projectTitle_Ongoing;
        public String abstract_Ongoing;
        public String degreeOfOverlapWithCurrentAllianceApplication;
        public String typeOfFunding_Ongoing;
        public String yourRoleOnApplication_Ongoing;
        public Date expectedDateOfDecision_Ongoing;
    }   

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public Id apaId;
    }
}*/




/*
@RestResource(urlMapping='/saveOtherGrantsAndApplicationDetails')
global without sharing class saveOtherGrantsAndApplicationDetails {

    @HttpPost
    global static ResponseWrapper saveOtherGrantsAndApplicationDetails() {
        ResponseWrapper response = new ResponseWrapper();

        try {   
            String requestBody = RestContext.request.requestBody.toString();
            RequestWrapper req = (RequestWrapper) JSON.deserialize(requestBody, RequestWrapper.class);

            Id apaRecordId;
            Id contactRecordId = String.isBlank(req.contactId) ? null : (Id) req.contactId;

            if (!String.isBlank(req.apaId)) {
                apaRecordId = req.apaId;
            } 
            else if (!String.isBlank(req.proposalId)) {
                List<Applicant_Proposal_Association__c> associations = [
                    SELECT Id, Proposal__c, Contact__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :req.proposalId
                    AND Contact__c = :req.contactId
                    LIMIT 1
                ];

                if (associations.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the provided proposalId';
                    return response;
                }

                apaRecordId = associations[0].Id;
            } else {
                response.success = false;
                response.message = 'Missing required field: provide either apaId or proposalId';
                return response;
            }

            Applicant_Proposal_Association__c updatedAPA = new Applicant_Proposal_Association__c(
                Id = apaRecordId,
                Have_you_applied_to_Alliance_before__c = req.firstApplicationWithAlliance,
                Previous_Application_Reference_Number__c = req.previousApplReferenceNumber,
                Previous_Scheme__c = req.previousScheme,
                Previous_Application_Project_Title__c = req.previousApplProjectTitle_Alliance,
                Decision_on_previous_application__c = req.prevoiusApplDecision,
                Key_difference_from_previous_application__c = req.keyDifferencesFromPreviousApplication,
               // Other_Ongoing_Scheme__c = req.otherOngoingSchemaName,
                Other_Ongoing_Applications__c = req.otherOngoingApplications,
                Name_of_the_Ongoing_funding_agency__c = req.nameOfFundingAgencyAndScheme,
                Ongoing_Project_Title__c = req.projectTitle_Ongoing,
                Abstract_Ongoing__c = req.abstract_Ongoing,
                Overlap_with_current_IA_application__c = req.degreeOfOverlapWithCurrentAllianceApplication,
                Type_of_funding__c = req.typeOfFunding_Ongoing,
                Your_Role_on_the_Application__c = req.yourRoleOnApplication_Ongoing,
                Expected_date_of_decision__c = req.expectedDateOfDecision_Ongoing
            );
            update updatedAPA;
            System.debug('apaId: ' + req.apaId);
            String sectionName = req.sectionName;
            if (String.isNotBlank(req.sectionName) && String.isNotBlank(req.apaId)) { 
                List<Scheme_Section__c> schemeSectionList = [
                    SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :req.apaId
                    AND Section_Name__c = :req.sectionName
                ];
                 System.debug('Line 166 schemeSectionList: ' + schemeSectionList);

                if (!schemeSectionList.isEmpty()) {
                    schemeSectionList[0].Data_Filled_Successfully__c = true;
                    update schemeSectionList;
                    response.sectionUpdateResult = true;
                } 
                else {
                    response.sectionUpdateResult = false;
                }
            }


            Integer existingGrantsInsertedCount = 0;
            Integer existingGrantsUpdatedCount = 0;

            if (req.existingGrants != null && !req.existingGrants.isEmpty()) {
                List<Existing_Grants__c> grantsToInsertApa = new List<Existing_Grants__c>();
                List<Existing_Grants__c> grantsToInsertContact = new List<Existing_Grants__c>();
                List<Existing_Grants__c> grantsToUpdate = new List<Existing_Grants__c>();

                for (ExistingGrantWrapper grant : req.existingGrants) {

                    if (String.isNotBlank(grant.id)) {

                        // Existing APA record -> UPDATE
                        if (String.isNotBlank(grant.applicantProposalAssociationId)) {

                            Existing_Grants__c existingGrant = buildExistingGrantRecord(grant);
                            existingGrant.Id = grant.id;
                            existingGrant.Applicant_Proposal_Association__c = grant.applicantProposalAssociationId;
                            grantsToUpdate.add(existingGrant);

                        }
                        // Existing Contact record -> DON'T UPDATE, CREATE APA RECORD
                        else if (String.isNotBlank(grant.contactId)) {

                            Existing_Grants__c apaGrant = buildExistingGrantRecord(grant);
                            apaGrant.Applicant_Proposal_Association__c = apaRecordId;
                            grantsToInsertApa.add(apaGrant);

                        }
                        // DEFENSIVE FALLBACK: Id present but neither association Id came through
                        else {
                            Existing_Grants__c existingGrant = buildExistingGrantRecord(grant);
                            existingGrant.Id = grant.id;
                            existingGrant.Applicant_Proposal_Association__c = apaRecordId;
                            grantsToUpdate.add(existingGrant);
                        }

                    } else {

                        // New record — create both an APA-tagged copy (this proposal only)
                        // and a Contact-tagged copy (the applicant's reusable master record)
                        Existing_Grants__c apaGrant = buildExistingGrantRecord(grant);
                        apaGrant.Applicant_Proposal_Association__c = apaRecordId;
                        grantsToInsertApa.add(apaGrant);

                        Existing_Grants__c contactGrant = buildExistingGrantRecord(grant);
                        contactGrant.Contact__c = req.contactId;
                        grantsToInsertContact.add(contactGrant);
                    }
                }

                // Bypass trigger sync so the Contact insert does not clone a second APA record
                if (!grantsToInsertApa.isEmpty() || !grantsToInsertContact.isEmpty()) {
                    GenericApplicantAssociationHandler.bypassAssociationSync = true;
                    try {
                        if (!grantsToInsertApa.isEmpty()) {
                            insert grantsToInsertApa;
                            existingGrantsInsertedCount += grantsToInsertApa.size();
                        }
                        if (!grantsToInsertContact.isEmpty()) {
                            insert grantsToInsertContact;
                            existingGrantsInsertedCount += grantsToInsertContact.size();
                        }
                    } finally {
                        GenericApplicantAssociationHandler.bypassAssociationSync = false;
                    }
                }
                if (!grantsToUpdate.isEmpty()) {
                    update grantsToUpdate;
                    existingGrantsUpdatedCount = grantsToUpdate.size();
                }
            }

            response.success = true;
            List<String> messages = new List<String>{ 'Other grants and application details saved successfully' };
            if (existingGrantsInsertedCount > 0) {
                messages.add(existingGrantsInsertedCount + ' existing grant record(s) inserted');
            }
            if (existingGrantsUpdatedCount > 0) {
                messages.add(existingGrantsUpdatedCount + ' existing grant record(s) updated');
            }
            response.message = String.join(messages, '. ');
            response.apaId = updatedAPA.Id;
        }
        catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();
        }
        return response;
    }

    private static Existing_Grants__c buildExistingGrantRecord(ExistingGrantWrapper grant) {
        return new Existing_Grants__c(
            Title__c = grant.title,
            Funding_Agency__c = grant.fundingAgency,
            Type__c = grant.type,
            Role_of_Applicant__c = grant.roleOfApplicant,
            Start_Date__c = grant.startDate,
            End_Date__c = grant.endDate,
            Duration_In_Months__c = grant.durationInMonths,
            Total_Award_Amount__c = grant.totalAwardAmount,
            Currency__c = grant.currencyPicklist,
            Other_Currency__c = grant.otherCurrency,
            Abstracts_of_ongoing_grants_fellowship__c = grant.abstractOfOngoingGrant
        );
    }

    global class RequestWrapper {
        public String proposalId;
        public String apaId;
        public String sectionName;
        public String contactId;
        public String firstApplicationWithAlliance;
        public String previousApplReferenceNumber;
        public String previousScheme;
        public String previousApplProjectTitle_Alliance;
        public String prevoiusApplDecision;
        public String keyDifferencesFromPreviousApplication;
        public String otherOngoingApplications;
       // public String otherOngoingSchemaName;
        public String nameOfFundingAgencyAndScheme;
        public String projectTitle_Ongoing;
        public String abstract_Ongoing;
        public String degreeOfOverlapWithCurrentAllianceApplication;
        public String typeOfFunding_Ongoing;
        public String yourRoleOnApplication_Ongoing;
        public Date expectedDateOfDecision_Ongoing;
        public List<ExistingGrantWrapper> existingGrants;
    }   

    global class ExistingGrantWrapper {
        public String id;
        public String applicantProposalAssociationId;
        public String contactId;
        public String title;
        public String fundingAgency;
        public String type;
        public String roleOfApplicant;
        public Date startDate;
        public Date endDate;
        public Decimal durationInMonths;
        public Decimal totalAwardAmount;
        public String currencyPicklist;
        public String otherCurrency;
        public String abstractOfOngoingGrant;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public Id apaId;
        public Boolean sectionUpdateResult;
    }
}*/





/*
@RestResource(urlMapping='/saveOtherGrantsAndApplicationDetails')
global without sharing class saveOtherGrantsAndApplicationDetails {

    @HttpPost
    global static ResponseWrapper saveOtherGrantsAndApplicationDetails() {
        ResponseWrapper response = new ResponseWrapper();

        try {   
            String requestBody = RestContext.request.requestBody.toString();
            RequestWrapper req = (RequestWrapper) JSON.deserialize(requestBody, RequestWrapper.class);

            Id apaRecordId;
            Id contactRecordId = String.isBlank(req.contactId) ? null : (Id) req.contactId;

            if (!String.isBlank(req.apaId)) {
                apaRecordId = req.apaId;
            } 
            else if (!String.isBlank(req.proposalId)) {
                List<Applicant_Proposal_Association__c> associations = [
                    SELECT Id, Proposal__c, Contact__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :req.proposalId
                    AND Contact__c = :req.contactId
                    LIMIT 1
                ];

                if (associations.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the provided proposalId';
                    return response;
                }

                apaRecordId = associations[0].Id;
            } else {
                response.success = false;
                response.message = 'Missing required field: provide either apaId or proposalId';
                return response;
            }

            Savepoint sp = Database.setSavepoint();

            try {
                // ---- Update APA-level fields (Is this your first Application / Other Ongoing Applications) ----
                Applicant_Proposal_Association__c updatedAPA = new Applicant_Proposal_Association__c(
                    Id = apaRecordId,
                    Is_this_your_first_Application__c = req.isThisYourFirstApplication,
                    Other_Ongoing_Applications__c = req.otherOngoingApplications
                );
                update updatedAPA;

                // ---- Scheme Section status update ----
                if (String.isNotBlank(req.sectionName) && String.isNotBlank(req.apaId)) {
                    List<Scheme_Section__c> schemeSectionList = [
                        SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c
                        FROM Scheme_Section__c
                        WHERE Applicant_Proposal_Association__c = :req.apaId
                        AND Section_Name__c = :req.sectionName
                    ];
                    System.debug('Line schemeSectionList: ' + schemeSectionList);

                    if (!schemeSectionList.isEmpty()) {
                        schemeSectionList[0].Data_Filled_Successfully__c = true;
                        update schemeSectionList;
                        response.sectionUpdateResult = true;
                    } else {
                        response.sectionUpdateResult = false;
                    }
                }

                // ---- Other Grants & Application (Previous DBT Grants / Other Grants) ----
                Integer otherGrantsInsertedCount = 0;
                Integer otherGrantsUpdatedCount = 0;

                if (req.otherGrantsAndApplications != null && !req.otherGrantsAndApplications.isEmpty()) {
                    List<Other_Grants__c> otherGrantsToInsert = new List<Other_Grants__c>();
                    List<Other_Grants__c> otherGrantsToUpdate = new List<Other_Grants__c>();

                    for (OtherGrantAndApplicationWrapper og : req.otherGrantsAndApplications) {
                        Other_Grants__c rec = buildOtherGrantRecord(og);

                        if (String.isNotBlank(og.id)) {
                            rec.Id = og.id;
                            rec.Applicant_Proposal_Association__c = apaRecordId;
                            otherGrantsToUpdate.add(rec);
                        } else {
                            rec.Applicant_Proposal_Association__c = apaRecordId;
                            otherGrantsToInsert.add(rec);
                        }
                    }

                    if (!otherGrantsToInsert.isEmpty()) {
                        insert otherGrantsToInsert;
                        otherGrantsInsertedCount = otherGrantsToInsert.size();
                    }
                    if (!otherGrantsToUpdate.isEmpty()) {
                        update otherGrantsToUpdate;
                        otherGrantsUpdatedCount = otherGrantsToUpdate.size();
                    }
                }

                // ---- Existing Grants ----
                // Existing_Grants__c is mirrored across two scopes that must never bleed
                // into each other: Contact__c (the applicant's current/latest list) and
                // Applicant_Proposal_Association__c (a frozen snapshot for this proposal
                // only). Each save wipes both scopes for this contact/APA and recreates
                // them fresh from the payload, so the two scopes always match exactly.
                Integer existingGrantsInsertedCount = 0;

                if (req.existingGrants != null && !req.existingGrants.isEmpty()) {
                    delete [SELECT Id FROM Existing_Grants__c WHERE Contact__c = :contactRecordId];
                    delete [SELECT Id FROM Existing_Grants__c WHERE Applicant_Proposal_Association__c = :apaRecordId];

                    List<Existing_Grants__c> grantsToInsertApa = new List<Existing_Grants__c>();
                    List<Existing_Grants__c> grantsToInsertContact = new List<Existing_Grants__c>();

                    for (ExistingGrantWrapper grant : req.existingGrants) {
                        Existing_Grants__c apaGrant = buildExistingGrantRecord(grant);
                        apaGrant.Applicant_Proposal_Association__c = apaRecordId;
                        grantsToInsertApa.add(apaGrant);

                        Existing_Grants__c contactGrant = buildExistingGrantRecord(grant);
                        contactGrant.Contact__c = req.contactId;
                        grantsToInsertContact.add(contactGrant);
                    }

                    // Bypass trigger sync so the Contact insert does not clone a second APA record
                    GenericApplicantAssociationHandler.bypassAssociationSync = true;
                    try {
                        insert grantsToInsertApa;
                        existingGrantsInsertedCount += grantsToInsertApa.size();
                        insert grantsToInsertContact;
                        existingGrantsInsertedCount += grantsToInsertContact.size();
                    } finally {
                        GenericApplicantAssociationHandler.bypassAssociationSync = false;
                    }
                }

                response.success = true;
                List<String> messages = new List<String>{ 'Other grants and application details saved successfully' };
                if (otherGrantsInsertedCount > 0) {
                    messages.add(otherGrantsInsertedCount + ' other grant/application record(s) inserted');
                }
                if (otherGrantsUpdatedCount > 0) {
                    messages.add(otherGrantsUpdatedCount + ' other grant/application record(s) updated');
                }
                if (existingGrantsInsertedCount > 0) {
                    messages.add(existingGrantsInsertedCount + ' existing grant record(s) inserted');
                }
                response.message = String.join(messages, '. ');
                response.apaId = apaRecordId;
            }
            catch (Exception innerEx) {
                Database.rollback(sp);
                throw innerEx;
            }
        }
        catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();
        }
        return response;
    }

    private static Other_Grants__c buildOtherGrantRecord(OtherGrantAndApplicationWrapper og) {
        return new Other_Grants__c(
            Grants_Type__c = og.grantsType,
            CurrencyIsoCode = og.currencyIsoCode,

            // Applicable when grantsType = 'Previous DBT Grants'
            Previous_Application_Reference_Number__c = og.previousApplReferenceNumber,
            Previous_Scheme__c = og.previousScheme,
            Previous_Application_Project_Title__c = og.previousApplProjectTitle_Alliance,
            Decision_on_previous_application__c = og.prevoiusApplDecision,
            Key_difference_from_previous_application__c = og.keyDifferencesFromPreviousApplication,

            // Applicable when grantsType = 'Other Grants'
            Name_of_Ongoing_funding_agency_Scheme__c = og.nameOfFundingAgencyAndScheme,
            Ongoing_Project_Title__c = og.projectTitle_Ongoing,
            Abstract_Ongoing__c = og.abstract_Ongoing,
            Overlap_with_current_IA_application__c = og.degreeOfOverlapWithCurrentAllianceApplication,
            Type_of_funding__c = og.typeOfFunding_Ongoing,
            Your_Role_on_the_Application__c = og.yourRoleOnApplication_Ongoing,
            Expected_date_of_decision__c = og.expectedDateOfDecision_Ongoing
        );
    }

    private static Existing_Grants__c buildExistingGrantRecord(ExistingGrantWrapper grant) {
        return new Existing_Grants__c(
            Title__c = grant.title,
            Funding_Agency__c = grant.fundingAgency,
            Type__c = grant.type,
            Role_of_Applicant__c = grant.roleOfApplicant,
            Start_Date__c = grant.startDate,
            End_Date__c = grant.endDate,
            Duration_In_Months__c = grant.durationInMonths,
            Total_Award_Amount__c = grant.totalAwardAmount,
            Currency__c = grant.currencyPicklist,
            Other_Currency__c = grant.otherCurrency,
            Abstracts_of_ongoing_grants_fellowship__c = grant.abstractOfOngoingGrant
        );
    }

    global class RequestWrapper {
        public String proposalId;
        public String apaId;
        public String sectionName;
        public String contactId;

        // APA-level fields
        public String isThisYourFirstApplication;
        public String otherOngoingApplications;

        public List<OtherGrantAndApplicationWrapper> otherGrantsAndApplications;
        public List<ExistingGrantWrapper> existingGrants;
    }

    global class OtherGrantAndApplicationWrapper {
        public String id;
        public String grantsType; // 'Previous DBT Grants' or 'Other Grants'
        public String currencyIsoCode;

        // Applicable when grantsType = 'Previous DBT Grants'
        public String previousApplReferenceNumber;
        public String previousScheme;
        public String previousApplProjectTitle_Alliance;
        public String prevoiusApplDecision;
        public String keyDifferencesFromPreviousApplication;

        // Applicable when grantsType = 'Other Grants'
        public String nameOfFundingAgencyAndScheme;
        public String projectTitle_Ongoing;
        public String abstract_Ongoing;
        public String degreeOfOverlapWithCurrentAllianceApplication;
        public String typeOfFunding_Ongoing;
        public String yourRoleOnApplication_Ongoing;
        public Date expectedDateOfDecision_Ongoing;
    }

    global class ExistingGrantWrapper {
        public String id;
        public String applicantProposalAssociationId;
        public String contactId;
        public String title;
        public String fundingAgency;
        public String type;
        public String roleOfApplicant;
        public Date startDate;
        public Date endDate;
        public Decimal durationInMonths;
        public Decimal totalAwardAmount;
        public String currencyPicklist;
        public String otherCurrency;
        public String abstractOfOngoingGrant;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public Id apaId;
        public Boolean sectionUpdateResult;
    }
}
*/







@RestResource(urlMapping='/saveOtherGrantsAndApplicationDetails')
global without sharing class saveOtherGrantsAndApplicationDetails {

    private static final String PROPOSAL_STATUS_DRAFT = 'Draft';
    private static final String REOPEN_STATUS_CLOSED = 'Closed';

    @HttpPost
    global static ResponseWrapper saveOtherGrantsAndApplicationDetails() {
        ResponseWrapper response = new ResponseWrapper();

        try {   
            String requestBody = RestContext.request.requestBody.toString();
            RequestWrapper req = (RequestWrapper) JSON.deserialize(requestBody, RequestWrapper.class);

            Id apaRecordId;
            Id contactRecordId = String.isBlank(req.contactId) ? null : (Id) req.contactId;

            if (!String.isBlank(req.apaId)) {
                apaRecordId = req.apaId;
            } 
            else if (!String.isBlank(req.proposalId)) {
                List<Applicant_Proposal_Association__c> associations = [
                    SELECT Id, Proposal__c, Contact__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :req.proposalId
                    AND Contact__c = :req.contactId
                    LIMIT 1
                ];

                if (associations.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the provided proposalId';
                    return response;
                }

                apaRecordId = associations[0].Id;
            } else {
                response.success = false;
                response.message = 'Missing required field: provide either apaId or proposalId';
                return response;
            }

            Savepoint sp = Database.setSavepoint();

            try {
                // ---- Update APA-level fields (Is this your first Application / Other Ongoing Applications) ----
                Applicant_Proposal_Association__c updatedAPA = new Applicant_Proposal_Association__c(
                    Id = apaRecordId,
                    Is_this_your_first_Application__c = req.isThisYourFirstApplication,
                    Other_Ongoing_Applications__c = req.otherOngoingApplications
                );
                update updatedAPA;

                // ---- Scheme Section status update ----
                if (String.isNotBlank(req.sectionName) && String.isNotBlank(req.apaId)) {
                    List<Scheme_Section__c> schemeSectionList = [
                        SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c,Application_Stages__c
                        FROM Scheme_Section__c
                        WHERE Applicant_Proposal_Association__c = :req.apaId
                        AND Section_Name__c = :req.sectionName
                        AND Application_Stages__c ='Prelims'
                    ];
                    System.debug('Line schemeSectionList: ' + schemeSectionList);

                    if (!schemeSectionList.isEmpty()) {
                        schemeSectionList[0].Data_Filled_Successfully__c = true;
                        update schemeSectionList;
                        response.sectionUpdateResult = true;
                    } else {
                        response.sectionUpdateResult = false;
                    }
                }

                // ---- Other Grants & Application (Previous DBT Grants / Other Grants) ----
                Integer otherGrantsInsertedCount = 0;
                Integer otherGrantsUpdatedCount = 0;

                if (req.otherGrantsAndApplications != null && !req.otherGrantsAndApplications.isEmpty()) {
                    List<Other_Grants__c> otherGrantsToInsert = new List<Other_Grants__c>();
                    List<Other_Grants__c> otherGrantsToUpdate = new List<Other_Grants__c>();

                    for (OtherGrantAndApplicationWrapper og : req.otherGrantsAndApplications) {
                        Other_Grants__c rec = buildOtherGrantRecord(og);

                        if (String.isNotBlank(og.id)) {
                            rec.Id = og.id;
                            rec.Applicant_Proposal_Association__c = apaRecordId;
                            otherGrantsToUpdate.add(rec);
                        } else {
                            rec.Applicant_Proposal_Association__c = apaRecordId;
                            otherGrantsToInsert.add(rec);
                        }
                    }

                    if (!otherGrantsToInsert.isEmpty()) {
                        insert otherGrantsToInsert;
                        otherGrantsInsertedCount = otherGrantsToInsert.size();
                    }
                    if (!otherGrantsToUpdate.isEmpty()) {
                        update otherGrantsToUpdate;
                        otherGrantsUpdatedCount = otherGrantsToUpdate.size();
                    }
                }

                // ---- Existing Grants ----
                // Existing_Grants__c is mirrored across two scopes that must never bleed
                // into each other: Contact__c (the applicant's current/latest list) and
                // Applicant_Proposal_Association__c (a frozen snapshot for this proposal
                // only). Each save wipes both scopes for this contact/APA and recreates
                // them fresh from the payload, so the two scopes always match exactly.
                Integer existingGrantsInsertedCount = 0;

                if (req.existingGrants != null && !req.existingGrants.isEmpty()) {
                    delete [SELECT Id FROM Existing_Grants__c WHERE Contact__c = :contactRecordId];
                    delete [SELECT Id FROM Existing_Grants__c WHERE Applicant_Proposal_Association__c = :apaRecordId];

                    List<Existing_Grants__c> grantsToInsertApa = new List<Existing_Grants__c>();
                    List<Existing_Grants__c> grantsToInsertContact = new List<Existing_Grants__c>();

                    for (ExistingGrantWrapper grant : req.existingGrants) {
                        Existing_Grants__c apaGrant = buildExistingGrantRecord(grant);
                        apaGrant.Applicant_Proposal_Association__c = apaRecordId;
                        grantsToInsertApa.add(apaGrant);

                        Existing_Grants__c contactGrant = buildExistingGrantRecord(grant);
                        contactGrant.Contact__c = req.contactId;
                        grantsToInsertContact.add(contactGrant);
                    }

                    // Bypass trigger sync so the Contact insert does not clone a second APA record
                    GenericApplicantAssociationHandler.bypassAssociationSync = true;
                    try {
                        insert grantsToInsertApa;
                        existingGrantsInsertedCount += grantsToInsertApa.size();
                        insert grantsToInsertContact;
                        existingGrantsInsertedCount += grantsToInsertContact.size();
                    } finally {
                        GenericApplicantAssociationHandler.bypassAssociationSync = false;
                    }
                }

                response.success = true;
                List<String> messages = new List<String>{ 'Other grants and application details saved successfully' };
                if (otherGrantsInsertedCount > 0) {
                    messages.add(otherGrantsInsertedCount + ' other grant/application record(s) inserted');
                }
                if (otherGrantsUpdatedCount > 0) {
                    messages.add(otherGrantsUpdatedCount + ' other grant/application record(s) updated');
                }
                if (existingGrantsInsertedCount > 0) {
                    messages.add(existingGrantsInsertedCount + ' existing grant record(s) inserted');
                }
                response.message = String.join(messages, '. ');
                response.apaId = apaRecordId;

                // ---- Submitted Proposal -> close out Scheme_Section__c records ----
                // Proposal_Status__c may not be resolvable directly from the
                // payload (proposalId is optional when apaId is supplied), so
                // it is fetched here via the APA's Proposal__r relationship.
                // If Submitted, all Scheme_Section__c records under
                // apaRecordId are bulk-closed (Reopen_Status__c = 'Closed'),
                // skipping ones already closed.
                Integer sectionsClosedCount = 0;
                List<Applicant_Proposal_Association__c> apaStatusCheck = [
                    SELECT Id, Proposal__c, Proposal__r.Proposal_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaRecordId
                    LIMIT 1
                ];

                if (!apaStatusCheck.isEmpty()
                    && apaStatusCheck[0].Proposal__r.Proposal_Status__c != PROPOSAL_STATUS_DRAFT) {

                    List<Scheme_Section__c> sectionsToClose = [
                        SELECT Id, Reopen_Status__c,Application_Stages__c
                        FROM Scheme_Section__c
                        WHERE Applicant_Proposal_Association__c = :apaRecordId
                        AND Reopen_Status__c != :REOPEN_STATUS_CLOSED AND Section_Name__c = :req.sectionName AND Application_Stages__c ='Prelims'
                    ];

                    if (!sectionsToClose.isEmpty()) {
                        for (Scheme_Section__c sec : sectionsToClose) {
                            sec.Reopen_Status__c = REOPEN_STATUS_CLOSED;
                        }
                        update sectionsToClose;
                        sectionsClosedCount = sectionsToClose.size();
                    }
                }
                response.sectionsClosedCount = sectionsClosedCount;
            }
            catch (Exception innerEx) {
                Database.rollback(sp);
                throw innerEx;
            }
        }
        catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();
        }
        return response;
    }

    private static Other_Grants__c buildOtherGrantRecord(OtherGrantAndApplicationWrapper og) {
        return new Other_Grants__c(
            Grants_Type__c = og.grantsType,
            CurrencyIsoCode = og.currencyIsoCode,

            // Applicable when grantsType = 'Previous DBT Grants'
            Previous_Application_Reference_Number__c = og.previousApplReferenceNumber,
            Previous_Scheme__c = og.previousScheme,
            Previous_Application_Project_Title__c = og.previousApplProjectTitle_Alliance,
            Decision_on_previous_application__c = og.prevoiusApplDecision,
            Key_difference_from_previous_application__c = og.keyDifferencesFromPreviousApplication,

            // Applicable when grantsType = 'Other Grants'
            Name_of_Ongoing_funding_agency_Scheme__c = og.nameOfFundingAgencyAndScheme,
            Ongoing_Project_Title__c = og.projectTitle_Ongoing,
            Abstract_Ongoing__c = og.abstract_Ongoing,
            Overlap_with_current_IA_application__c = og.degreeOfOverlapWithCurrentAllianceApplication,
            Type_of_funding__c = og.typeOfFunding_Ongoing,
            Your_Role_on_the_Application__c = og.yourRoleOnApplication_Ongoing,
            Expected_date_of_decision__c = og.expectedDateOfDecision_Ongoing
        );
    }

    private static Existing_Grants__c buildExistingGrantRecord(ExistingGrantWrapper grant) {
        return new Existing_Grants__c(
            Title__c = grant.title,
            Funding_Agency__c = grant.fundingAgency,
            Type__c = grant.type,
            Role_of_Applicant__c = grant.roleOfApplicant,
            Start_Date__c = grant.startDate,
            End_Date__c = grant.endDate,
            Duration_In_Months__c = grant.durationInMonths,
            Total_Award_Amount__c = grant.totalAwardAmount,
            Currency__c = grant.currencyPicklist,
            Other_Currency__c = grant.otherCurrency,
            Abstracts_of_ongoing_grants_fellowship__c = grant.abstractOfOngoingGrant
        );
    }

    global class RequestWrapper {
        public String proposalId;
        public String apaId;
        public String sectionName;
        public String contactId;

        // APA-level fields
        public String isThisYourFirstApplication;
        public String otherOngoingApplications;

        public List<OtherGrantAndApplicationWrapper> otherGrantsAndApplications;
        public List<ExistingGrantWrapper> existingGrants;
    }

    global class OtherGrantAndApplicationWrapper {
        public String id;
        public String grantsType; // 'Previous DBT Grants' or 'Other Grants'
        public String currencyIsoCode;

        // Applicable when grantsType = 'Previous DBT Grants'
        public String previousApplReferenceNumber;
        public String previousScheme;
        public String previousApplProjectTitle_Alliance;
        public String prevoiusApplDecision;
        public String keyDifferencesFromPreviousApplication;

        // Applicable when grantsType = 'Other Grants'
        public String nameOfFundingAgencyAndScheme;
        public String projectTitle_Ongoing;
        public String abstract_Ongoing;
        public String degreeOfOverlapWithCurrentAllianceApplication;
        public String typeOfFunding_Ongoing;
        public String yourRoleOnApplication_Ongoing;
        public Date expectedDateOfDecision_Ongoing;
    }

    global class ExistingGrantWrapper {
        public String id;
        public String applicantProposalAssociationId;
        public String contactId;
        public String title;
        public String fundingAgency;
        public String type;
        public String roleOfApplicant;
        public Date startDate;
        public Date endDate;
        public Decimal durationInMonths;
        public Decimal totalAwardAmount;
        public String currencyPicklist;
        public String otherCurrency;
        public String abstractOfOngoingGrant;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public Id apaId;
        public Boolean sectionUpdateResult;
        public Integer sectionsClosedCount;
    }
}