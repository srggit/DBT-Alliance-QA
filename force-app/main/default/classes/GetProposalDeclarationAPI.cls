@RestResource(urlMapping='/ProposalDeclaration/get/*')
global without sharing class GetProposalDeclarationAPI {

    @HttpGet
    global static GetDeclarationResponseWrapper getDeclaration() {
        GetDeclarationResponseWrapper response = new GetDeclarationResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String apaId = req.params.get('apaId');
            String proposalId = req.params.get('proposalId');
            String contactId = req.params.get('contactId');

            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(proposalId) && String.isNotBlank(contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :proposalId
                    AND Contact__c = :contactId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given proposalId/contactId combination.';
                    return response;
                }
                apaRecord = apaList[0];

            } else {
                response.success = false;
                response.message = 'Either apaId, or both proposalId and contactId, must be provided.';
                return response;
            }

            response.declaration1 = apaRecord.Declaration_1__c;
            response.declaration2 = apaRecord.Declaration_2__c;
            response.apaId = apaRecord.Id;

            Id resolvedProposalId = apaRecord.Proposal__c;

            if (resolvedProposalId != null) {
                List<Proposal__c> proposalList = [
                    SELECT Id, Proposal_Status__c, Application_Date__c
                    FROM Proposal__c
                    WHERE Id = :resolvedProposalId
                    LIMIT 1
                ];
                if (!proposalList.isEmpty()) {
                    response.proposalId = proposalList[0].Id;
                    response.proposalStatus = proposalList[0].Proposal_Status__c;
                    response.applicationDate = proposalList[0].Application_Date__c;
                }
            }

            // ---- Resolve Host Account (via Applicant_Host_Association__c) ----
            Id hostAccountId;
            String hostAccountName;

            if (resolvedProposalId != null) {
                List<Applicant_Host_Association__c> ahaList = [
                    SELECT Id, Host__c, Host__r.Name
                    FROM Applicant_Host_Association__c
                    WHERE Proposal__c = :resolvedProposalId
                    AND Host__c != null
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ];
                if (!ahaList.isEmpty()) {
                    hostAccountId = ahaList[0].Host__c;
                    hostAccountName = ahaList[0].Host__r.Name;
                }
            }
            response.hostAccountId = hostAccountId;
            response.hostAccountName = hostAccountName;

            // =========================================================
            // WRAPPER 1: Proposal_Participant_Association__c (Stage = Prelims)
            //            -> resolve linked Contacts (Supervisor / Sponsor)
            //            -> now also carries the PPA record's own Id
            //               (ppaId) so the frontend can round-trip it and
            //               the Save API's contactId+proposal+stage lookup
            //               can be cross-checked / replaced by it if needed.
            // =========================================================
            List<ParticipantWrapper> participantDetails = new List<ParticipantWrapper>();

            if (resolvedProposalId != null) {
                List<Proposal_Participant_Association__c> ppaList = [
                    SELECT Id, Participant__c, Roles__c, Document_Uploaded__c, Notify_through_Email__c
                    FROM Proposal_Participant_Association__c
                    WHERE Proposal__c = :resolvedProposalId
                    AND Participant__c != null AND Stage__c = 'Prelims'
                ];

                // Store the full PPA record (not just the role string) keyed
                // by Contact Id, so we can pull both ppaId and role from the
                // same map when building each ParticipantWrapper below.
                Map<Id, Proposal_Participant_Association__c> contactIdToPpa =
                    new Map<Id, Proposal_Participant_Association__c>();
                for (Proposal_Participant_Association__c ppa : ppaList) {
                    contactIdToPpa.put(ppa.Participant__c, ppa);
                }

                if (!contactIdToPpa.isEmpty()) {
                    List<Contact> contacts = [
                        SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                               AccountId, Email, Birthdate, Department, Gender__c, Nationality__c, Position__c, Phone,
                               Research_Experience_After_Viva_Date_Yrs__c, Research_Experience_After_Viva_Date_Mont__c,
                               MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                        FROM Contact
                        WHERE Id IN :contactIdToPpa.keySet()
                    ];

                    for (Contact con : contacts) {
                        Proposal_Participant_Association__c matchedPpa = contactIdToPpa.get(con.Id);

                        ParticipantWrapper pw = new ParticipantWrapper();
                        pw.ppaId = matchedPpa != null ? matchedPpa.Id : null;
                        pw.contactId = con.Id;
                        pw.name = con.Name;
                        pw.salutation = con.Salutation;
                        pw.firstName = con.FirstName;
                        pw.middleName = con.MiddleName;
                        pw.lastName = con.LastName;
                        pw.suffix = con.Suffix;
                        pw.accountId = con.AccountId;
                        pw.organisation = con.Account.Name;
                        pw.email = con.Email;
                        pw.birthdate = con.Birthdate;
                        pw.department = con.Department;
                        pw.gender = con.Gender__c;
                        pw.nationality = con.Nationality__c;
                        pw.currentPosition = con.Position__c;
                        pw.telePhone = con.Phone;
                        pw.experienceinMonths = con.Research_Experience_After_Viva_Date_Mont__c;
                        pw.experienceinYears = con.Research_Experience_After_Viva_Date_Yrs__c;
                        pw.mailingStreet = con.MailingStreet;
                        pw.mailingCity = con.MailingCity;
                        pw.mailingState = con.MailingState;
                        pw.mailingPostalCode = con.MailingPostalCode;
                        pw.mailingCountry = con.MailingCountry;
                        pw.role = matchedPpa != null ? matchedPpa.Roles__c : null;
                        pw.documentUploadStatus = matchedPpa.Document_Uploaded__c != null ? matchedPpa.Document_Uploaded__c : false;
                        pw.notifyThroughEmailForPPA = matchedPpa.Notify_through_Email__c != null ? matchedPpa.Notify_through_Email__c : false;
                        pw.documentUploaded = matchedPpa.Document_Uploaded__c;                  // Picklist
                        participantDetails.add(pw);
                    }
                }
            }
            response.participants = participantDetails;

            // =========================================================
            // WRAPPER 2: Additional_Partcipant__c (Stage = Prelims)
            // =========================================================
            List<AdditionalParticipantWrapper> additionalParticipants = new List<AdditionalParticipantWrapper>();

            if (resolvedProposalId != null) {
                List<Additional_Partcipant__c> additionalList = [
                    SELECT Id, Roles__c, First_Name__c, Last_Name__c, Email__c, Department__c,DocumentUploaded__c,
                           Designation__c, Gender__c, Nationality__c, Organisation__c, Telephone__c, Title__c, Stage__c,
                           Notify_through_Email__c
                    FROM Additional_Partcipant__c
                    WHERE Proposal__c = :resolvedProposalId AND Stage__c = 'Prelims'
                ];

                for (Additional_Partcipant__c ap : additionalList) {
                    AdditionalParticipantWrapper aw = new AdditionalParticipantWrapper();
                    aw.id = ap.Id;
                    aw.role = ap.Roles__c;
                    aw.firstName = ap.First_Name__c;
                    aw.lastName = ap.Last_Name__c;
                    aw.email = ap.Email__c;
                    aw.department = ap.Department__c;
                    aw.designation = ap.Designation__c;
                    aw.gender = ap.Gender__c;
                    aw.nationality = ap.Nationality__c;
                    aw.organisation = ap.Organisation__c;
                    aw.telephone = ap.Telephone__c;
                    aw.title = ap.Title__c;
                    aw.notifyThroughEmail = ap.Notify_through_Email__c;
                    aw.documentUploaded = ap.DocumentUploaded__c;
                    aw.documentUploadStatus = ap.DocumentUploaded__c;
                    additionalParticipants.add(aw);
                }

                // ---- WOHI_Collaboration__c records with Application_Stage__c = Prelims
                List<WOHI_Collaboration__c> wohiList = [
                    SELECT Id, Title__c, FirstName__c, Last_Name__c, Email__c, Department__c, Type__c,
                           Current_Position__c, Gender__c, Nationality__c, Organisation__c,Experience_in_Years__c,Experience_in_Months__c,
                           TelephoneNo__c, Roles__c, Application_Stage__c, Wohi_User_Document_Status__c
                    FROM WOHI_Collaboration__c
                    WHERE Applicant_Proposal_Association__c = :apaRecord.Id
                    AND Application_Stage__c = 'Prelims' AND Type__c = 'WOHI'
                ];

                for (WOHI_Collaboration__c wc : wohiList) {
                    AdditionalParticipantWrapper aw = new AdditionalParticipantWrapper();
                    aw.id = wc.Id;
                    aw.role = String.isNotBlank(wc.Roles__c) ? wc.Roles__c : 'External Sponsor';
                    aw.firstName = wc.FirstName__c;
                    aw.lastName = wc.Last_Name__c;
                    aw.email = wc.Email__c;
                    aw.department = wc.Department__c;
                    aw.designation = wc.Current_Position__c;
                    aw.gender = wc.Gender__c;
                    aw.nationality = wc.Nationality__c;
                    aw.organisation = wc.Organisation__c;
                    aw.telephone = wc.TelephoneNo__c;
                    aw.title = wc.Title__c;
                    aw.type = wc.Type__c;
                    aw.experienceinMonths = wc.Experience_in_Months__c;
                    aw.experienceinYears = wc.Experience_in_Years__c;
                    aw.documentUploaded = wc.Wohi_User_Document_Status__c;
                    additionalParticipants.add(aw);
                }
            }
            response.additionalParticipants = additionalParticipants;

            // =========================================================
            // WRAPPER 3: Host Account Contacts (via AHA -> Host Account)
            //            -> always fetched independently, no fallback gate
            // =========================================================
            List<HostContactWrapper> hostAccountContacts = new List<HostContactWrapper>();

            if (hostAccountId != null) {
                List<Contact> hostAccountContactList = [
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                           AccountId, Email, Birthdate, Department, Gender__c, Nationality__c, Position__c, Phone,
                           Research_Experience_After_Viva_Date_Yrs__c, Research_Experience_After_Viva_Date_Mont__c,
                           MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                    FROM Contact
                    WHERE AccountId = :hostAccountId
                ];

                for (Contact con : hostAccountContactList) {
                    HostContactWrapper hw = new HostContactWrapper();
                    hw.contactId = con.Id;
                    hw.name = con.Name;
                    hw.salutation = con.Salutation;
                    hw.firstName = con.FirstName;
                    hw.middleName = con.MiddleName;
                    hw.lastName = con.LastName;
                    hw.suffix = con.Suffix;
                    hw.accountId = con.AccountId;
                    hw.organisation = con.Account.Name;
                    hw.email = con.Email;
                    hw.birthdate = con.Birthdate;
                    hw.department = con.Department;
                    hw.gender = con.Gender__c;
                    hw.nationality = con.Nationality__c;
                    hw.currentPosition = con.Position__c;
                    hw.telePhone = con.Phone;
                    hw.experienceinMonths = con.Research_Experience_After_Viva_Date_Mont__c;
                    hw.experienceinYears = con.Research_Experience_After_Viva_Date_Yrs__c;
                    hw.mailingStreet = con.MailingStreet;
                    hw.mailingCity = con.MailingCity;
                    hw.mailingState = con.MailingState;
                    hw.mailingPostalCode = con.MailingPostalCode;
                    hw.mailingCountry = con.MailingCountry;
                    hostAccountContacts.add(hw);
                }
            }
            response.hostContactDetails = hostAccountContacts;

            List<Scheme_Section__c> schemeSectionList = [
                SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c,Reopen_Status__c,Application_Stages__c,Page_Name_URL__c,Is_Mandatory__c
                FROM Scheme_Section__c
                WHERE Applicant_Proposal_Association__c = :apaId AND Application_Stages__c ='Prelims'
            ];
            System.debug('schemeSectionList: ' + schemeSectionList);
            List<SectionWrapper> sectionWrappers = new List<SectionWrapper>();
            for (Scheme_Section__c section : schemeSectionList) {
                SectionWrapper sw = new SectionWrapper();
                sw.sectionId = section.Id;
                sw.sectionName = section.Section_Name__c;
                sw.sectionStatus = section.Data_Filled_Successfully__c;
                sw.sectionReopenStatus = section.Reopen_Status__c;
                sw.sectionPageNameURL = section.Page_Name_URL__c;
                sw.sectionMandatory = section.Is_Mandatory__c;
                sectionWrappers.add(sw);
            }
            response.sections = sectionWrappers;

            response.success = true;
            response.message = 'Declaration and proposal details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class GetDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global Boolean declaration1;
        global Boolean declaration2;
        global String proposalStatus;
        global Date applicationDate;
        global Id hostAccountId;
        global String hostAccountName;
        global List<ParticipantWrapper> participants;
        global List<AdditionalParticipantWrapper> additionalParticipants;
        global List<HostContactWrapper> hostContactDetails;
        global List<SectionWrapper> sections;
    }

    global class ParticipantWrapper {
        global Id ppaId;               // Proposal_Participant_Association__c record Id
        global Id contactId;
        global String name;
        global String salutation;
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global Id accountId;
        global String organisation;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition;
        global String telePhone;
        global Decimal experienceinMonths;
        global Decimal experienceinYears;
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
        global String role;
        global Boolean documentUploadStatus;
        global Boolean notifyThroughEmailForPPA;
        global Boolean documentUploaded;

    }

    global class AdditionalParticipantWrapper {
        global Id id;                  // Additional_Partcipant__c record Id
        global String role;
        global String firstName;
        global String lastName;
        global String email;
        global String department;
        global String designation;
        global String gender;
        global String nationality;
        global String organisation;
        global String telephone;
        global String title;
        global String type;
        global Decimal experienceinMonths;
        global Decimal experienceinYears;
        global Boolean notifyThroughEmail;
        global Boolean documentUploadStatus;
        global Boolean documentUploaded;
    }

    global class HostContactWrapper {
        global Id contactId;
        global String name;
        global String salutation;
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global Id accountId;
        global String organisation;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition;
        global String telePhone;
        global Decimal experienceinMonths;
        global Decimal experienceinYears;
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
    }

    global class SectionWrapper {
        global String sectionId;
        global String sectionName;
        global Boolean sectionStatus;
        global String sectionReopenStatus;
        global String sectionPageNameURL;
        global Boolean sectionMandatory;
    }
}








/*latest one 
@RestResource(urlMapping='/ProposalDeclaration/get/*')
global without sharing class GetProposalDeclarationAPI {

    @HttpGet
    global static GetDeclarationResponseWrapper getDeclaration() {
        GetDeclarationResponseWrapper response = new GetDeclarationResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String apaId = req.params.get('apaId');
            String proposalId = req.params.get('proposalId');
            String contactId = req.params.get('contactId');

            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(proposalId) && String.isNotBlank(contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :proposalId
                    AND Contact__c = :contactId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given proposalId/contactId combination.';
                    return response;
                }
                apaRecord = apaList[0];

            } else {
                response.success = false;
                response.message = 'Either apaId, or both proposalId and contactId, must be provided.';
                return response;
            }

            response.declaration1 = apaRecord.Declaration_1__c;
            response.declaration2 = apaRecord.Declaration_2__c;
            response.apaId = apaRecord.Id;

            if (apaRecord.Proposal__c != null) {
                List<Proposal__c> proposalList = [
                    SELECT Id, Proposal_Status__c, Application_Date__c
                    FROM Proposal__c
                    WHERE Id = :apaRecord.Proposal__c
                    LIMIT 1
                ];
                if (!proposalList.isEmpty()) {
                    response.proposalId = proposalList[0].Id;
                    response.proposalStatus = proposalList[0].Proposal_Status__c;
                    response.applicationDate = proposalList[0].Application_Date__c;
                }
            }

            // ---- Host Contact details ----
            // Priority 1: contacts already saved as Proposal_Participant_Association__c for this proposal
            // Priority 2 (fallback): all contacts under the Host Account(s) linked via Applicant_Host_Association__c
            List<HostContactWrapper> hostContactDetails = new List<HostContactWrapper>();
            Boolean hostContactsSourcedFromParticipants = false;

            // ---- Resolved Host Account (the one new participants get auto-tagged to) ----
            // Mirrors the "first AHA found, ordered by CreatedDate" resolution used in
            // SaveProposalDeclarationAPI, so the UI can show/confirm the same Host.
            Id hostAccountId;
            String hostAccountName;

            if (apaRecord.Proposal__c != null) {

                List<Applicant_Host_Association__c> ahaList = [
                    SELECT Id, Host__c, Host__r.Name
                    FROM Applicant_Host_Association__c
                    WHERE Proposal__c = :apaRecord.Proposal__c
                    AND Host__c != null
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ];
                if (!ahaList.isEmpty()) {
                    hostAccountId = ahaList[0].Host__c;
                    hostAccountName = ahaList[0].Host__r.Name;
                }

                List<Proposal_Participant_Association__c> ppaList = [
                    SELECT Id, Participant__c, Roles__c
                    FROM Proposal_Participant_Association__c
                    WHERE Proposal__c = :apaRecord.Proposal__c
                    AND Participant__c != null AND Stage__c ='Prelims'
                ];

                Set<Id> contactIdsToQuery = new Set<Id>();
                Map<Id, String> contactIdToRole = new Map<Id, String>();

                if (!ppaList.isEmpty()) {
                    hostContactsSourcedFromParticipants = true;
                    for (Proposal_Participant_Association__c ppa : ppaList) {
                        contactIdsToQuery.add(ppa.Participant__c);
                        contactIdToRole.put(ppa.Participant__c, ppa.Roles__c);
                    }
                } else if (hostAccountId != null) {
                    List<Contact> hostAccountContacts = [
                        SELECT Id FROM Contact WHERE AccountId = :hostAccountId
                    ];
                    for (Contact con : hostAccountContacts) {
                        contactIdsToQuery.add(con.Id);
                    }
                }

                if (!contactIdsToQuery.isEmpty()) {
                    List<Contact> contacts = [
                        SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                               AccountId, Email, Birthdate, Department, Gender__c, Nationality__c,Position__c,Phone,Research_Experience_After_Viva_Date_Yrs__c,Research_Experience_After_Viva_Date_Mont__c,
                               MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                               OwnerId, CreatedById, LastModifiedById, CurrencyIsoCode
                        FROM Contact
                        WHERE Id IN :contactIdsToQuery
                    ];

                    for (Contact con : contacts) {
                        HostContactWrapper hostWrapper = new HostContactWrapper();
                        hostWrapper.contactId = con.Id;
                        hostWrapper.name = con.Name;
                        hostWrapper.salutation = con.Salutation;
                        hostWrapper.firstName = con.FirstName;
                        hostWrapper.middleName = con.MiddleName;
                        hostWrapper.lastName = con.LastName;
                        hostWrapper.suffix = con.Suffix;
                        hostWrapper.accountId = con.AccountId;
                        hostWrapper.organisation = con.Account.Name;
                        hostWrapper.email = con.Email;
                        hostWrapper.birthdate = con.Birthdate;
                        hostWrapper.department = con.Department;
                        hostWrapper.gender = con.Gender__c;
                        hostWrapper.nationality = con.Nationality__c;
                        hostWrapper.currentPosition = con.Position__c;
                        hostWrapper.telePhone =con.Phone;
                        hostWrapper.experienceinMonths = con.Research_Experience_After_Viva_Date_Mont__c;
                        hostWrapper.experienceinYears = con.Research_Experience_After_Viva_Date_Yrs__c;
                        hostWrapper.mailingStreet = con.MailingStreet;
                        hostWrapper.mailingCity = con.MailingCity;
                        hostWrapper.mailingState = con.MailingState;
                        hostWrapper.mailingPostalCode = con.MailingPostalCode;
                        hostWrapper.mailingCountry = con.MailingCountry;
                        //hostWrapper.currencyPicklist = con.CurrencyIsoCode;
                        hostWrapper.role = contactIdToRole.get(con.Id);
                        hostContactDetails.add(hostWrapper);
                    }
                }
            }

            response.hostAccountId = hostAccountId;
            response.hostAccountName = hostAccountName;
            response.hostContactDetails = hostContactDetails;
            response.hostContactsSourcedFromParticipants = hostContactsSourcedFromParticipants;

            // =========================================================
            // Additional_Partcipant__c (non-Supervisor/Sponsor roles saved
            // by SaveProposalDeclarationAPI's Branch 2 — no Contact involved).
            // Mirrors GetProposalParticipantFullAPI's "Wrapper 2", scoped to
            // Stage__c = 'Prelims' to match the stage used on save here.
            // =========================================================
            List<AdditionalParticipantWrapper> additionalParticipants = new List<AdditionalParticipantWrapper>();

            if (apaRecord.Proposal__c != null) {
                List<Additional_Partcipant__c> additionalList = [
                    SELECT Id, Roles__c, First_Name__c, Last_Name__c, Email__c, Department__c,
                           Designation__c, Gender__c, Nationality__c, Organisation__c, Telephone__c, Title__c, Stage__c
                    FROM Additional_Partcipant__c
                    WHERE Proposal__c = :apaRecord.Proposal__c AND Stage__c = 'Prelims'
                ];

                for (Additional_Partcipant__c ap : additionalList) {
                    AdditionalParticipantWrapper aw = new AdditionalParticipantWrapper();
                    aw.id = ap.Id;
                    aw.role = ap.Roles__c;
                    aw.firstName = ap.First_Name__c;
                    aw.lastName = ap.Last_Name__c;
                    aw.email = ap.Email__c;
                    aw.department = ap.Department__c;
                    aw.designation = ap.Designation__c;
                    aw.gender = ap.Gender__c;
                    aw.nationality = ap.Nationality__c;
                    aw.organisation = ap.Organisation__c;
                    aw.telephone = ap.Telephone__c;
                    aw.title = ap.Title__c;
                    additionalParticipants.add(aw);
                }
            }
            response.additionalParticipants = additionalParticipants;

            List<Scheme_Section__c> schemeSectionList = [
                SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c,Reopen_Status__c,Application_Stages__c,Page_Name_URL__c,Is_Mandatory__c
                FROM Scheme_Section__c
                WHERE Applicant_Proposal_Association__c = :apaId AND Application_Stages__c ='Prelims'
            ];
            System.debug('schemeSectionList: ' + schemeSectionList);
            List<SectionWrapper> sectionWrappers = new List<SectionWrapper>();
            for (Scheme_Section__c section : schemeSectionList) {
                SectionWrapper sw = new SectionWrapper();
                sw.sectionId = section.Id;
                sw.sectionName = section.Section_Name__c;
                sw.sectionStatus = section.Data_Filled_Successfully__c;
                sw.sectionReopenStatus = section.Reopen_Status__c;
                sw.sectionPageNameURL = section.Page_Name_URL__c;
                sw.sectionMandatory = section.Is_Mandatory__c;
                sectionWrappers.add(sw);
            }
            response.sections = sectionWrappers;

            response.success = true;
            response.message = 'Declaration and proposal details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class GetDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global Boolean declaration1;
        global Boolean declaration2;
        global String proposalStatus;
        global Date applicationDate;
        global Id hostAccountId;
        global String hostAccountName;
        global List<HostContactWrapper> hostContactDetails;
        global Boolean hostContactsSourcedFromParticipants;
        global List<AdditionalParticipantWrapper> additionalParticipants;
        global List<SectionWrapper> sections;
    }

    global class HostContactWrapper {
        global Id contactId;
        global String name;
        global String salutation;
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global Id accountId;
        global String organisation;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition;
        global String telePhone;
        global Decimal experienceinMonths;
        global Decimal experienceinYears;
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
       // global String currencyPicklist;
        global String role;
    }

    global class AdditionalParticipantWrapper {
        global Id id;                  // Additional_Partcipant__c record Id
        global String role;
        global String firstName;
        global String lastName;
        global String email;
        global String department;
        global String designation;
        global String gender;
        global String nationality;
        global String organisation;
        global String telephone;
        global String title;
    }

    global class SectionWrapper {
        global String sectionId;
        global String sectionName;
        global Boolean sectionStatus;
        global String sectionReopenStatus;
        global String sectionPageNameURL;
        global Boolean sectionMandatory;

    }
}
*/






/*@RestResource(urlMapping='/ProposalDeclaration/get/*')
global without sharing class GetProposalDeclarationAPI {

    @HttpGet
    global static GetDeclarationResponseWrapper getDeclaration() {
        GetDeclarationResponseWrapper response = new GetDeclarationResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String apaId = req.params.get('apaId');
            String proposalId = req.params.get('proposalId');
            String contactId = req.params.get('contactId');

            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(proposalId) && String.isNotBlank(contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :proposalId
                    AND Contact__c = :contactId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given proposalId/contactId combination.';
                    return response;
                }
                apaRecord = apaList[0];

            } else {
                response.success = false;
                response.message = 'Either apaId, or both proposalId and contactId, must be provided.';
                return response;
            }

            response.declaration1 = apaRecord.Declaration_1__c;
            response.declaration2 = apaRecord.Declaration_2__c;
            response.apaId = apaRecord.Id;

            if (apaRecord.Proposal__c != null) {
                List<Proposal__c> proposalList = [
                    SELECT Id, Proposal_Status__c, Application_Date__c
                    FROM Proposal__c
                    WHERE Id = :apaRecord.Proposal__c
                    LIMIT 1
                ];
                if (!proposalList.isEmpty()) {
                    response.proposalId = proposalList[0].Id;
                    response.proposalStatus = proposalList[0].Proposal_Status__c;
                    response.applicationDate = proposalList[0].Application_Date__c;
                }
            }

            // ---- Host Contact details ----
            // Priority 1: contacts already saved as Proposal_Participant_Association__c for this proposal
            // Priority 2 (fallback): all contacts under the Host Account(s) linked via Applicant_Host_Association__c
            List<HostContactWrapper> hostContactDetails = new List<HostContactWrapper>();
            Boolean hostContactsSourcedFromParticipants = false;

            // ---- Resolved Host Account (the one new participants get auto-tagged to) ----
            // Mirrors the "first AHA found, ordered by CreatedDate" resolution used in
            // SaveProposalDeclarationAPI, so the UI can show/confirm the same Host.
            Id hostAccountId;
            String hostAccountName;

            if (apaRecord.Proposal__c != null) {

                List<Applicant_Host_Association__c> ahaList = [
                    SELECT Id, Host__c, Host__r.Name
                    FROM Applicant_Host_Association__c
                    WHERE Proposal__c = :apaRecord.Proposal__c
                    AND Host__c != null
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ];
                if (!ahaList.isEmpty()) {
                    hostAccountId = ahaList[0].Host__c;
                    hostAccountName = ahaList[0].Host__r.Name;
                }

                List<Proposal_Participant_Association__c> ppaList = [
                    SELECT Id, Participant__c, Roles__c
                    FROM Proposal_Participant_Association__c
                    WHERE Proposal__c = :apaRecord.Proposal__c
                    AND Participant__c != null AND Stage__c ='Prelims'
                ];

                Set<Id> contactIdsToQuery = new Set<Id>();
                Map<Id, String> contactIdToRole = new Map<Id, String>();

                if (!ppaList.isEmpty()) {
                    hostContactsSourcedFromParticipants = true;
                    for (Proposal_Participant_Association__c ppa : ppaList) {
                        contactIdsToQuery.add(ppa.Participant__c);
                        contactIdToRole.put(ppa.Participant__c, ppa.Roles__c);
                    }
                } else if (hostAccountId != null) {
                    List<Contact> hostAccountContacts = [
                        SELECT Id FROM Contact WHERE AccountId = :hostAccountId
                    ];
                    for (Contact con : hostAccountContacts) {
                        contactIdsToQuery.add(con.Id);
                    }
                }

                if (!contactIdsToQuery.isEmpty()) {
                    List<Contact> contacts = [
                        SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                               AccountId, Email, Birthdate, Department, Gender__c, Nationality__c,Position__c,Phone,Research_Experience_After_Viva_Date_Yrs__c,Research_Experience_After_Viva_Date_Mont__c,
                               MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                               OwnerId, CreatedById, LastModifiedById, CurrencyIsoCode
                        FROM Contact
                        WHERE Id IN :contactIdsToQuery
                    ];

                    for (Contact con : contacts) {
                        HostContactWrapper hostWrapper = new HostContactWrapper();
                        hostWrapper.contactId = con.Id;
                        hostWrapper.name = con.Name;
                        hostWrapper.salutation = con.Salutation;
                        hostWrapper.firstName = con.FirstName;
                        hostWrapper.middleName = con.MiddleName;
                        hostWrapper.lastName = con.LastName;
                        hostWrapper.suffix = con.Suffix;
                        hostWrapper.accountId = con.AccountId;
                        hostWrapper.organisation = con.Account.Name;
                        hostWrapper.email = con.Email;
                        hostWrapper.birthdate = con.Birthdate;
                        hostWrapper.department = con.Department;
                        hostWrapper.gender = con.Gender__c;
                        hostWrapper.nationality = con.Nationality__c;
                        hostWrapper.currentPosition = con.Position__c;
                        hostWrapper.telePhone =con.Phone;
                        hostWrapper.experienceinMonths = con.Research_Experience_After_Viva_Date_Mont__c;
                        hostWrapper.experienceinYears = con.Research_Experience_After_Viva_Date_Yrs__c;
                        hostWrapper.mailingStreet = con.MailingStreet;
                        hostWrapper.mailingCity = con.MailingCity;
                        hostWrapper.mailingState = con.MailingState;
                        hostWrapper.mailingPostalCode = con.MailingPostalCode;
                        hostWrapper.mailingCountry = con.MailingCountry;
                        //hostWrapper.currencyPicklist = con.CurrencyIsoCode;
                        hostWrapper.role = contactIdToRole.get(con.Id);
                        hostContactDetails.add(hostWrapper);
                    }
                }
            }

            response.hostAccountId = hostAccountId;
            response.hostAccountName = hostAccountName;
            response.hostContactDetails = hostContactDetails;
            response.hostContactsSourcedFromParticipants = hostContactsSourcedFromParticipants;

            List<Scheme_Section__c> schemeSectionList = [
                SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c,Reopen_Status__c,Application_Stages__c
                FROM Scheme_Section__c
                WHERE Applicant_Proposal_Association__c = :apaId AND Application_Stages__c ='Prelims'
            ];
            System.debug('schemeSectionList: ' + schemeSectionList);
            List<SectionWrapper> sectionWrappers = new List<SectionWrapper>();
            for (Scheme_Section__c section : schemeSectionList) {
                SectionWrapper sw = new SectionWrapper();
                sw.sectionId = section.Id;
                sw.sectionName = section.Section_Name__c;
                sw.sectionStatus = section.Data_Filled_Successfully__c;
                sw.sectionReopenStatus = section.Reopen_Status__c;
                sectionWrappers.add(sw);
            }
            response.sections = sectionWrappers;

            response.success = true;
            response.message = 'Declaration and proposal details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class GetDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global Boolean declaration1;
        global Boolean declaration2;
        global String proposalStatus;
        global Date applicationDate;
        global Id hostAccountId;
        global String hostAccountName;
        global List<HostContactWrapper> hostContactDetails;
        global Boolean hostContactsSourcedFromParticipants;
        global List<SectionWrapper> sections;
    }

    global class HostContactWrapper {
        global Id contactId;
        global String name;
        global String salutation;
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global Id accountId;
        global String organisation;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition;
        global String telePhone;
        global Decimal experienceinMonths;
        global Decimal experienceinYears;
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
       // global String currencyPicklist;
        global String role;
    }

    global class SectionWrapper {
        global String sectionId;
        global String sectionName;
        global Boolean sectionStatus;
        global String sectionReopenStatus;
    }
}*/

/*
@RestResource(urlMapping='/ProposalDeclaration/get/*')
global without sharing class GetProposalDeclarationAPI {

    @HttpGet
    global static GetDeclarationResponseWrapper getDeclaration() {
        GetDeclarationResponseWrapper response = new GetDeclarationResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String apaId = req.params.get('apaId');
            String proposalId = req.params.get('proposalId');
            String contactId = req.params.get('contactId');

            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(proposalId) && String.isNotBlank(contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :proposalId
                    AND Contact__c = :contactId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given proposalId/contactId combination.';
                    return response;
                }
                apaRecord = apaList[0];

            } else {
                response.success = false;
                response.message = 'Either apaId, or both proposalId and contactId, must be provided.';
                return response;
            }

            response.declaration1 = apaRecord.Declaration_1__c;
            response.declaration2 = apaRecord.Declaration_2__c;
            response.apaId = apaRecord.Id;

            if (apaRecord.Proposal__c != null) {
                List<Proposal__c> proposalList = [
                    SELECT Id, Proposal_Status__c, Application_Date__c
                    FROM Proposal__c
                    WHERE Id = :apaRecord.Proposal__c
                    LIMIT 1
                ];
                if (!proposalList.isEmpty()) {
                    response.proposalId = proposalList[0].Id;
                    response.proposalStatus = proposalList[0].Proposal_Status__c;
                    response.applicationDate = proposalList[0].Application_Date__c;
                }
            }

            response.success = true;
            response.message = 'Declaration and proposal details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class GetDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global Boolean declaration1;
        global Boolean declaration2;
        global String proposalStatus;
        global Date applicationDate;
    }
}*/