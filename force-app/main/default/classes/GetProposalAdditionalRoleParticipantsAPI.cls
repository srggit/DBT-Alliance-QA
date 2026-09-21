@RestResource(urlMapping='/GetProposalAdditionalRoleParticipants/*')
global without sharing class GetProposalAdditionalRoleParticipantsAPI {

    @HttpGet
    global static GetAdditionalRoleParticipantResponseWrapper getAdditionalRoleParticipants() {
        GetAdditionalRoleParticipantResponseWrapper response = new GetAdditionalRoleParticipantResponseWrapper();

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

            // =========================================================
            // WRAPPER 1: Proposal_Participant_Association__c
            //            (Added_for_Additional_Role__c = true)
            //            -> resolve linked Contacts (Supervisor / Sponsor)
            // =========================================================
            List<ParticipantWrapper> participantDetails = new List<ParticipantWrapper>();

            List<Proposal_Participant_Association__c> ppaList = [
                SELECT Id, Participant__c, Roles__c, Relationship_of_current_app_to_Host__c, Added_for_Additional_Role__c,
                       How_will_you_support_Applicant_s_career__c, Document_Uploaded__c, Stage__c
                FROM Proposal_Participant_Association__c
                WHERE Proposal__c = :resolvedProposalId
                AND Participant__c != null
                AND Added_for_Additional_Role__c = true
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
            //            (Added_for_Additional_Role__c = true)
            // =========================================================
            List<AdditionalParticipantWrapper> additionalParticipants = new List<AdditionalParticipantWrapper>();

            List<Additional_Partcipant__c> additionalList = [
                SELECT Id, Roles__c, First_Name__c, Last_Name__c, Email__c, Department__c, DocumentUploaded__c, Referee_Added_For_Full__c, Added_for_Additional_Role__c,
                       Designation__c, Gender__c, Nationality__c, Organisation__c, Telephone__c, Title__c, Stage__c, What_guidance_from_chosen_mentor__c
                FROM Additional_Partcipant__c
                WHERE Proposal__c = :resolvedProposalId
                AND Added_for_Additional_Role__c = true
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
                aw.addedForAdditionalRoleInAP = ap.Added_for_Additional_Role__c;
                aw.stage = ap.Stage__c;
                additionalParticipants.add(aw);
            }
            response.additionalParticipants = additionalParticipants;

            response.success = true;
            response.message = 'Additional role participant details retrieved successfully.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error retrieving additional role participants: ' + ex.getMessage();
        }

        return response;
    }

    global class GetAdditionalRoleParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global Id proposalId;
        global List<ParticipantWrapper> participants;
        global List<AdditionalParticipantWrapper> additionalParticipants;
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
        global Boolean addedForAdditionalRoleInPPA;
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
        global Boolean addedForAdditionalRoleInAP;
        global String stage;
    }
}