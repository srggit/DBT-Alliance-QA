@RestResource(urlMapping='/GetProposalParticipantFull/*')
global without sharing class GetProposalParticipantFullAPI {

    @HttpGet
    global static GetParticipantResponseWrapper getParticipants() {
        GetParticipantResponseWrapper response = new GetParticipantResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String proposalId = req.params.get('proposalId');

            if (String.isBlank(proposalId)) {
                response.success = false;
                response.message = 'proposalId is required.';
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id FROM Proposal__c WHERE Id = :proposalId LIMIT 1
            ];
            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'No Proposal found for the given proposalId.';
                return response;
            }
            Id resolvedProposalId = proposalList[0].Id;
            response.proposalId = resolvedProposalId;

            // ---- Resolve Host Account (via Applicant_Host_Association__c) ----
            Id hostAccountId;
            String hostAccountName;

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
            response.hostAccountId = hostAccountId;
            response.hostAccountName = hostAccountName;

            // =========================================================
            // WRAPPER 1: Proposal_Participant_Association__c (Stage = Full)
            //            -> resolve linked Contacts (Supervisor / Sponsor)
            //            -> now also carries the PPA record's own Id
            //               (ppaId) so the frontend can round-trip it on
            //               save instead of relying purely on contactId +
            //               proposalId + Stage__c matching server-side.
            // =========================================================
            List<ParticipantWrapper> participantDetails = new List<ParticipantWrapper>();

            List<Proposal_Participant_Association__c> ppaList = [
                SELECT Id, Participant__c, Roles__c, Relationship_of_current_app_to_Host__c,Added_for_Additional_Role__c,Notify_through_Email__c,Added_for_Full__c,
                       How_will_you_support_Applicant_s_career__c,Document_Uploaded__c,Stage__c
                FROM Proposal_Participant_Association__c
                WHERE Proposal__c = :resolvedProposalId                
                AND Participant__c != null
            ];

            Map<Id, Proposal_Participant_Association__c> contactIdToPPA = new Map<Id, Proposal_Participant_Association__c>();
            for (Proposal_Participant_Association__c ppa : ppaList) {
                contactIdToPPA.put(ppa.Participant__c, ppa);
            }

            if (!contactIdToPPA.isEmpty()) {
                List<Contact> contacts = [
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                           AccountId, Email, Birthdate, Department, Gender__c, Nationality__c, Position__c, Phone,
                           MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                    FROM Contact
                    WHERE Id IN :contactIdToPPA.keySet()
                ];

                for (Contact con : contacts) {
                    ParticipantWrapper pw = new ParticipantWrapper();
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
                    pw.mailingStreet = con.MailingStreet;
                    pw.mailingCity = con.MailingCity;
                    pw.mailingState = con.MailingState;
                    pw.mailingPostalCode = con.MailingPostalCode;
                    pw.mailingCountry = con.MailingCountry;

                    Proposal_Participant_Association__c ppa = contactIdToPPA.get(con.Id);
                    pw.ppaId = ppa.Id;
                    pw.role = ppa.Roles__c;
                    pw.notifyThroughEmailForPPA = ppa.Notify_through_Email__c;
                    pw.partcipantAddedForFull = ppa.Added_for_Full__c;
                    pw.relationshipOfCurrentApplicant = ppa.Relationship_of_current_app_to_Host__c;
                    pw.addedForAdditionalRoleInPPA = ppa.Added_for_Additional_Role__c;
                    pw.howWillYouSupportApplicantsCareer = ppa.How_will_you_support_Applicant_s_career__c;
                    pw.documentUploadStatus = ppa.Document_Uploaded__c;
                    pw.stage = ppa.Stage__c;


                    participantDetails.add(pw);
                }
            }
            response.participants = participantDetails;

            // =========================================================
            // WRAPPER 2: Additional_Partcipant__c
            // =========================================================
            List<AdditionalParticipantWrapper> additionalParticipants = new List<AdditionalParticipantWrapper>();

            List<Additional_Partcipant__c> additionalList = [
                SELECT Id, Roles__c, First_Name__c, Last_Name__c, Email__c, Department__c, DocumentUploaded__c,Notify_through_Email__c,Referee_Added_For_Full__c,Added_for_Additional_Role__c,
                       Designation__c, Gender__c, Nationality__c, Organisation__c, Telephone__c, Title__c,Stage__c,What_guidance_from_chosen_mentor__c
                FROM Additional_Partcipant__c
                WHERE Proposal__c = :resolvedProposalId
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
                aw.whatGuidanceFromChosenMentor = ap.What_guidance_from_chosen_mentor__c;
                aw.documentUploadStatus = ap.DocumentUploaded__c;
                aw.refereeAddedForFull = ap.Referee_Added_For_Full__c;
                aw.notifyThroughEmail = ap.Notify_through_Email__c;
                aw.addedForAdditionalRoleInAP = ap.Added_for_Additional_Role__c;
                aw.stage = ap.Stage__c;
                additionalParticipants.add(aw);
            }
            response.additionalParticipants = additionalParticipants;

            // =========================================================
            // WRAPPER 3: Host Account Contacts (via AHA -> Host Account)
            //            -> always fetched independently, no fallback gate
            // =========================================================
            List<HostAccountContactWrapper> hostAccountContacts = new List<HostAccountContactWrapper>();

            if (hostAccountId != null) {
                List<Contact> hostAccountContactList = [
                    SELECT Id, FirstName, LastName, Email, Department, Position__c, Gender__c,
                           Nationality__c, Account.Name, Phone, Salutation
                    FROM Contact
                    WHERE AccountId = :hostAccountId
                ];

                for (Contact con : hostAccountContactList) {
                    HostAccountContactWrapper hw = new HostAccountContactWrapper();
                    hw.contactId = con.Id;
                    hw.firstName = con.FirstName;
                    hw.lastName = con.LastName;
                    hw.email = con.Email;
                    hw.department = con.Department;
                    hw.designation = con.Position__c;
                    hw.gender = con.Gender__c;
                    hw.nationality = con.Nationality__c;
                    hw.organisation = con.Account.Name;
                    hw.telephone = con.Phone;
                    hw.title = con.Salutation;
                    hostAccountContacts.add(hw);
                }
            }
            response.hostAccountContacts = hostAccountContacts;

            response.success = true;
            response.message = 'Participant details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class GetParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global Id proposalId;
        global Id hostAccountId;
        global String hostAccountName;
        global List<ParticipantWrapper> participants;
        global List<AdditionalParticipantWrapper> additionalParticipants;
        global List<HostAccountContactWrapper> hostAccountContacts;
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
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
        global String role;
        global String relationshipOfCurrentApplicant;
        global Boolean partcipantAddedForFull;
        global Boolean addedForAdditionalRoleInPPA;
        global Boolean notifyThroughEmailForPPA;
        global String howWillYouSupportApplicantsCareer;
        global Boolean documentUploadStatus;
        global String stage;
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
        global String whatGuidanceFromChosenMentor;
        global Boolean documentUploadStatus;
        global Boolean refereeAddedForFull;
        global Boolean notifyThroughEmail;
        global Boolean addedForAdditionalRoleInAP;
        global String stage;
    }

    global class HostAccountContactWrapper {
        global Id contactId;           // Contact record Id
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
}



/*Previous One
@RestResource(urlMapping='/GetProposalParticipantFull/*')
global without sharing class GetProposalParticipantFullAPI {

    @HttpGet
    global static GetParticipantResponseWrapper getParticipants() {
        GetParticipantResponseWrapper response = new GetParticipantResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String proposalId = req.params.get('proposalId');

            if (String.isBlank(proposalId)) {
                response.success = false;
                response.message = 'proposalId is required.';
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id FROM Proposal__c WHERE Id = :proposalId LIMIT 1
            ];
            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'No Proposal found for the given proposalId.';
                return response;
            }
            Id resolvedProposalId = proposalList[0].Id;
            response.proposalId = resolvedProposalId;

            // ---- Resolve Host Account (via Applicant_Host_Association__c) ----
            Id hostAccountId;
            String hostAccountName;

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
            response.hostAccountId = hostAccountId;
            response.hostAccountName = hostAccountName;

            // =========================================================
            // WRAPPER 1: Proposal_Participant_Association__c (Stage = Full)
            //            -> resolve linked Contacts (Supervisor / Sponsor)
            // =========================================================
            List<ParticipantWrapper> participantDetails = new List<ParticipantWrapper>();

            List<Proposal_Participant_Association__c> ppaList = [
                SELECT Id, Participant__c, Roles__c,Relationship_of_current_app_to_Host__c,How_will_you_support_Applicant_s_career__c
                FROM Proposal_Participant_Association__c
                WHERE Proposal__c = :resolvedProposalId                
                AND Participant__c != null
            ];

            Map<Id, String> contactIdToRole = new Map<Id, String>();
            for (Proposal_Participant_Association__c ppa : ppaList) {
                contactIdToRole.put(ppa.Participant__c, ppa.Roles__c);
            }

            if (!contactIdToRole.isEmpty()) {
                List<Contact> contacts = [
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                           AccountId, Email, Birthdate, Department, Gender__c, Nationality__c, Position__c, Phone,
                           MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                    FROM Contact
                    WHERE Id IN :contactIdToRole.keySet()
                ];

                for (Contact con : contacts) {
                    ParticipantWrapper pw = new ParticipantWrapper();
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
                    pw.mailingStreet = con.MailingStreet;
                    pw.mailingCity = con.MailingCity;
                    pw.mailingState = con.MailingState;
                    pw.mailingPostalCode = con.MailingPostalCode;
                    pw.mailingCountry = con.MailingCountry;
                    pw.role = contactIdToRole.get(con.Id);
                    participantDetails.add(pw);
                }
            }
            response.participants = participantDetails;

            // =========================================================
            // WRAPPER 2: Additional_Partcipant__c
            // =========================================================
            List<AdditionalParticipantWrapper> additionalParticipants = new List<AdditionalParticipantWrapper>();

            List<Additional_Partcipant__c> additionalList = [
                SELECT Id, Roles__c, First_Name__c, Last_Name__c, Email__c, Department__c,
                       Designation__c, Gender__c, Nationality__c, Organisation__c, Telephone__c, Title__c,Stage__c,What_guidance_from_chosen_mentor__c
                FROM Additional_Partcipant__c
                WHERE Proposal__c = :resolvedProposalId AND Stage__c = 'Full'
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
                aw.whatGuidanceFromChosenMentor = ap.What_guidance_from_chosen_mentor__c;
                additionalParticipants.add(aw);
            }
            response.additionalParticipants = additionalParticipants;

            // =========================================================
            // WRAPPER 3: Host Account Contacts (via AHA -> Host Account)
            //            -> always fetched independently, no fallback gate
            // =========================================================
            List<HostAccountContactWrapper> hostAccountContacts = new List<HostAccountContactWrapper>();

            if (hostAccountId != null) {
                List<Contact> hostAccountContactList = [
                    SELECT Id, FirstName, LastName, Email, Department, Position__c, Gender__c,
                           Nationality__c, Account.Name, Phone, Salutation
                    FROM Contact
                    WHERE AccountId = :hostAccountId
                ];

                for (Contact con : hostAccountContactList) {
                    HostAccountContactWrapper hw = new HostAccountContactWrapper();
                    hw.contactId = con.Id;
                    hw.firstName = con.FirstName;
                    hw.lastName = con.LastName;
                    hw.email = con.Email;
                    hw.department = con.Department;
                    hw.designation = con.Position__c;
                    hw.gender = con.Gender__c;
                    hw.nationality = con.Nationality__c;
                    hw.organisation = con.Account.Name;
                    hw.telephone = con.Phone;
                    hw.title = con.Salutation;
                    hostAccountContacts.add(hw);
                }
            }
            response.hostAccountContacts = hostAccountContacts;

            response.success = true;
            response.message = 'Participant details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class GetParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global Id proposalId;
        global Id hostAccountId;
        global String hostAccountName;
        global List<ParticipantWrapper> participants;
        global List<AdditionalParticipantWrapper> additionalParticipants;
        global List<HostAccountContactWrapper> hostAccountContacts;
    }

    global class ParticipantWrapper {
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
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
        global String role;
        global String relationshipOfCurrentApplicant;
        global String howWillYouSupportApplicantsCareer;
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
        global String whatGuidanceFromChosenMentor;
    }

    global class HostAccountContactWrapper {
        global Id contactId;           // Contact record Id
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
}*/


/*
@RestResource(urlMapping='/GetProposalParticipantFull/*')
global without sharing class GetProposalParticipantFullAPI {

    @HttpGet
    global static GetParticipantResponseWrapper getParticipants() {
        GetParticipantResponseWrapper response = new GetParticipantResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String proposalId = req.params.get('proposalId');

            if (String.isBlank(proposalId)) {
                response.success = false;
                response.message = 'proposalId is required.';
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id FROM Proposal__c WHERE Id = :proposalId LIMIT 1
            ];
            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'No Proposal found for the given proposalId.';
                return response;
            }
            Id resolvedProposalId = proposalList[0].Id;
            response.proposalId = resolvedProposalId;

            // ---- Resolve Host Account (via Applicant_Host_Association__c) ----
            Id hostAccountId;
            String hostAccountName;

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
            response.hostAccountId = hostAccountId;
            response.hostAccountName = hostAccountName;

            // =========================================================
            // PART 1: Proposal_Participant_Association__c (Stage = Full)
            //         -> resolve linked Contacts (Supervisor / Sponsor)
            // =========================================================
            List<ParticipantWrapper> participantDetails = new List<ParticipantWrapper>();

            List<Proposal_Participant_Association__c> ppaList = [
                SELECT Id, Participant__c, Roles__c
                FROM Proposal_Participant_Association__c
                WHERE Proposal__c = :resolvedProposalId
                AND Stage__c = 'Full'
                AND Participant__c != null
            ];

            Map<Id, String> contactIdToRole = new Map<Id, String>();
            for (Proposal_Participant_Association__c ppa : ppaList) {
                contactIdToRole.put(ppa.Participant__c, ppa.Roles__c);
            }

            if (!contactIdToRole.isEmpty()) {
                List<Contact> contacts = [
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                           AccountId, Email, Birthdate, Department, Gender__c, Nationality__c, Position__c, Phone,
                           MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                    FROM Contact
                    WHERE Id IN :contactIdToRole.keySet()
                ];

                for (Contact con : contacts) {
                    ParticipantWrapper pw = new ParticipantWrapper();
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
                    pw.mailingStreet = con.MailingStreet;
                    pw.mailingCity = con.MailingCity;
                    pw.mailingState = con.MailingState;
                    pw.mailingPostalCode = con.MailingPostalCode;
                    pw.mailingCountry = con.MailingCountry;
                    pw.role = contactIdToRole.get(con.Id);
                    participantDetails.add(pw);
                }
            }
            response.participants = participantDetails;

            // =========================================================
            // PART 2: Additional_Partcipant__c
            //         -> fallback to Host Account Contacts if empty
            // =========================================================
            List<AdditionalParticipantWrapper> additionalParticipants = new List<AdditionalParticipantWrapper>();
            Boolean additionalParticipantsSourcedFromHostAccount = false;

            List<Additional_Partcipant__c> additionalList = [
                SELECT Id, Roles__c, First_Name__c, Last_Name__c, Email__c, Department__c,
                       Designation__c, Gender__c, Nationality__c, Organisation__c, Telephone__c, Title__c
                FROM Additional_Partcipant__c
                WHERE Proposal__c = :resolvedProposalId
            ];

            if (!additionalList.isEmpty()) {
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
            } else if (hostAccountId != null) {
                additionalParticipantsSourcedFromHostAccount = true;

                List<Contact> hostAccountContacts = [
                    SELECT Id, FirstName, LastName, Email, Department, Position__c, Gender__c,
                           Nationality__c, Account.Name, Phone, Salutation
                    FROM Contact
                    WHERE AccountId = :hostAccountId
                ];

                for (Contact con : hostAccountContacts) {
                    AdditionalParticipantWrapper aw = new AdditionalParticipantWrapper();
                    aw.id = con.Id;
                    aw.role = null;
                    aw.firstName = con.FirstName;
                    aw.lastName = con.LastName;
                    aw.email = con.Email;
                    aw.department = con.Department;
                    aw.designation = con.Position__c;
                    aw.gender = con.Gender__c;
                    aw.nationality = con.Nationality__c;
                    aw.organisation = con.Account.Name;
                    aw.telephone = con.Phone;
                    aw.title = con.Salutation;
                    additionalParticipants.add(aw);
                }
            }

            response.additionalParticipants = additionalParticipants;
            response.additionalParticipantsSourcedFromHostAccount = additionalParticipantsSourcedFromHostAccount;

            response.success = true;
            response.message = 'Participant details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class GetParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global Id proposalId;
        global Id hostAccountId;
        global String hostAccountName;
        global List<ParticipantWrapper> participants;
        global List<AdditionalParticipantWrapper> additionalParticipants;
        global Boolean additionalParticipantsSourcedFromHostAccount;
    }

    global class ParticipantWrapper {
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
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
        global String role;
    }

    global class AdditionalParticipantWrapper {
        global Id id;
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
}*/

/*
@RestResource(urlMapping='/GetProposalParticipantFull/*')
global without sharing class GetProposalParticipantFullAPI {

    @HttpGet
    global static GetParticipantResponseWrapper getParticipants() {
        GetParticipantResponseWrapper response = new GetParticipantResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String proposalId = req.params.get('proposalId');

            if (String.isBlank(proposalId)) {
                response.success = false;
                response.message = 'proposalId is required.';
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id FROM Proposal__c WHERE Id = :proposalId LIMIT 1
            ];
            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'No Proposal found for the given proposalId.';
                return response;
            }
            Id resolvedProposalId = proposalList[0].Id;
            response.proposalId = resolvedProposalId;

            // ---- Resolve Host Account (via Applicant_Host_Association__c) ----
            Id hostAccountId;
            String hostAccountName;

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
            response.hostAccountId = hostAccountId;
            response.hostAccountName = hostAccountName;

            // =========================================================
            // CONDITION 1a: Proposal_Participant_Association__c (Stage = Full)
            //               -> resolve linked Contacts (Supervisor / Sponsor)
            // =========================================================
            List<ParticipantWrapper> participantDetails = new List<ParticipantWrapper>();

            List<Proposal_Participant_Association__c> ppaList = [
                SELECT Id, Participant__c, Roles__c
                FROM Proposal_Participant_Association__c
                WHERE Proposal__c = :resolvedProposalId
                AND Stage__c = 'Full'
                AND Participant__c != null
            ];

            Map<Id, String> contactIdToRole = new Map<Id, String>();
            for (Proposal_Participant_Association__c ppa : ppaList) {
                contactIdToRole.put(ppa.Participant__c, ppa.Roles__c);
            }

            if (!contactIdToRole.isEmpty()) {
                List<Contact> contacts = [
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName, Suffix, Account.Name,
                           AccountId, Email, Birthdate, Department, Gender__c, Nationality__c, Position__c, Phone,
                           MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                    FROM Contact
                    WHERE Id IN :contactIdToRole.keySet()
                ];

                for (Contact con : contacts) {
                    ParticipantWrapper pw = new ParticipantWrapper();
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
                    pw.mailingStreet = con.MailingStreet;
                    pw.mailingCity = con.MailingCity;
                    pw.mailingState = con.MailingState;
                    pw.mailingPostalCode = con.MailingPostalCode;
                    pw.mailingCountry = con.MailingCountry;
                    pw.role = contactIdToRole.get(con.Id);
                    participantDetails.add(pw);
                }
            }
            response.participants = participantDetails;

            // =========================================================
            // CONDITION 1b: Additional_Partcipant__c
            // =========================================================
            List<AdditionalParticipantWrapper> additionalParticipants = new List<AdditionalParticipantWrapper>();

            List<Additional_Partcipant__c> additionalList = [
                SELECT Id, Roles__c, First_Name__c, Last_Name__c, Email__c, Department__c,
                       Designation__c, Gender__c, Nationality__c, Organisation__c, Telephone__c, Title__c
                FROM Additional_Partcipant__c
                WHERE Proposal__c = :resolvedProposalId
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
            response.additionalParticipants = additionalParticipants;

            // =========================================================
            // CONDITION 2: fallback to Host Account Contacts
            //              -> ONLY when BOTH of the above are empty
            // =========================================================
            List<HostAccountContactWrapper> hostAccountContacts = new List<HostAccountContactWrapper>();
            Boolean hostContactsSourcedFromFallback = false;

            if (participantDetails.isEmpty() && additionalParticipants.isEmpty() && hostAccountId != null) {
                hostContactsSourcedFromFallback = true;

                List<Contact> hostAccountContactList = [
                    SELECT Id, FirstName, LastName, Email, Department, Position__c, Gender__c,
                           Nationality__c, Account.Name, Phone, Salutation
                    FROM Contact
                    WHERE AccountId = :hostAccountId
                ];

                for (Contact con : hostAccountContactList) {
                    HostAccountContactWrapper hw = new HostAccountContactWrapper();
                    hw.contactId = con.Id;
                    hw.firstName = con.FirstName;
                    hw.lastName = con.LastName;
                    hw.email = con.Email;
                    hw.department = con.Department;
                    hw.designation = con.Position__c;
                    hw.gender = con.Gender__c;
                    hw.nationality = con.Nationality__c;
                    hw.organisation = con.Account.Name;
                    hw.telephone = con.Phone;
                    hw.title = con.Salutation;
                    hostAccountContacts.add(hw);
                }
            }
            response.hostAccountContacts = hostAccountContacts;
            response.hostContactsSourcedFromFallback = hostContactsSourcedFromFallback;

            response.success = true;
            response.message = 'Participant details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class GetParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global Id proposalId;
        global Id hostAccountId;
        global String hostAccountName;
        global List<ParticipantWrapper> participants;
        global List<AdditionalParticipantWrapper> additionalParticipants;
        global List<HostAccountContactWrapper> hostAccountContacts;
        global Boolean hostContactsSourcedFromFallback;
    }

    global class ParticipantWrapper {
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
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;
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

    global class HostAccountContactWrapper {
        global Id contactId;           // Contact record Id
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
}*/