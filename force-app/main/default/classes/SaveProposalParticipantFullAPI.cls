@RestResource(urlMapping='/SaveProposalParticipantFull/*')
global without sharing class SaveProposalParticipantFullAPI {

    private static final Set<String> CONTACT_BACKED_ROLES = new Set<String>{'Supervisor', 'Sponsor'};
    private static final String PPA_STAGE = 'Full';
    private static final String ADDITIONAL_PARTICIPANT_STAGE = 'Full';
    private static final String ROLE_SPONSOR = 'Sponsor';
    private static final String ROLE_SUPERVISOR = 'Supervisor';

    @HttpPost
    global static SaveParticipantResponseWrapper saveParticipants() {
        SaveParticipantResponseWrapper response = new SaveParticipantResponseWrapper();
        Savepoint sp = Database.setSavepoint();

        try {
            RestRequest req = RestContext.request;
            SaveParticipantRequestWrapper reqBody =
                (SaveParticipantRequestWrapper) JSON.deserialize(
                    req.requestBody.toString(), SaveParticipantRequestWrapper.class
                );

            if (String.isBlank(reqBody.proposalId)) {
                response.success = false;
                response.message = 'proposalId is required.';
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id FROM Proposal__c WHERE Id = :reqBody.proposalId LIMIT 1
            ];
            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'Proposal record could not be found.';
                Database.rollback(sp);
                return response;
            }
            Id proposalId = proposalList[0].Id;

            if (reqBody.participants == null || reqBody.participants.isEmpty()) {
                response.success = true;
                response.message = 'No participants supplied.';
                response.proposalId = proposalId;
                return response;
            }

            List<Id> ppaIds = new List<Id>();
            List<Id> additionalParticipantIds = new List<Id>();
            List<Id> createdParticipantContactIds = new List<Id>();

            // ---- Split participants by role type ----
            List<Integer> ppaIndexes = new List<Integer>();
            List<Integer> additionalIndexes = new List<Integer>();

            for (Integer i = 0; i < reqBody.participants.size(); i++) {
                ParticipantWrapper p = reqBody.participants[i];
                if (p.role != null && CONTACT_BACKED_ROLES.contains(p.role)) {
                    ppaIndexes.add(i);
                } else {
                    additionalIndexes.add(i);
                }
            }

            // =========================================================
            // BRANCH 1: Supervisor / Sponsor -> Contact + PPA
            //           UPSERT semantics:
            //           - existing contactId -> update Contact, update the
            //             existing PPA (matched by Proposal__c +
            //             Participant__c + Stage__c) or insert one if none
            //             exists yet
            //           - blank contactId     -> create new Contact,
            //             insert new PPA
            //           NOTE: Contact.Added_as_Sponsor__c /
            //           Contact.Added_as_Supervisor__c are set to true
            //           based on the participant's role, on both the
            //           insert and update paths.
            // =========================================================
            if (!ppaIndexes.isEmpty()) {

                Boolean needsFallbackHostAccount = false;
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId) && String.isBlank(p.organisationId)) {
                        needsFallbackHostAccount = true;
                        break;
                    }
                }

                Id fallbackHostAccountId;
                if (needsFallbackHostAccount) {
                    List<Applicant_Host_Association__c> ahaList = [
                        SELECT Id, Host__c
                        FROM Applicant_Host_Association__c
                        WHERE Proposal__c = :proposalId
                        AND Host__c != null
                        ORDER BY CreatedDate ASC
                        LIMIT 1
                    ];
                    if (!ahaList.isEmpty()) {
                        fallbackHostAccountId = ahaList[0].Host__c;
                    }
                }

                // 1. Update existing Contacts for rows that already carry a
                //    contactId (bulk update — no re-query needed since we
                //    are overwriting explicit fields only).
                List<Contact> contactsToUpdate = new List<Contact>();
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isNotBlank(p.contactId)) {
                        contactsToUpdate.add(new Contact(
                            Id = (Id) p.contactId,
                            Salutation = p.salutation,
                            FirstName = p.firstName,
                            MiddleName = p.middleName,
                            LastName = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown',
                            Suffix = p.suffix,
                            Email = p.email,
                            Birthdate = p.birthdate,
                            Department = p.department,
                            Gender__c = p.gender,
                            Nationality__c = p.nationality,
                            Position__c = p.currentPosition,
                            Phone = p.telePhone,
                            MailingStreet = p.mailingStreet,
                            MailingCity = p.mailingCity,
                            MailingState = p.mailingState,
                            MailingPostalCode = p.mailingPostalCode,
                            MailingCountry = p.mailingCountry,
                            Added_as_Sponsor__c = (p.role == ROLE_SPONSOR),
                            Added_as_Supervisor__c = (p.role == ROLE_SUPERVISOR)
                        ));
                    }
                }
                if (!contactsToUpdate.isEmpty()) {
                    update contactsToUpdate;
                }

                // 2. Bulk create Contacts only for participants missing a
                //    contactId.
                List<Integer> newContactIndexes = new List<Integer>();
                List<Contact> newContactsToInsert = new List<Contact>();

                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId)) {
                        Id resolvedAccountId = String.isNotBlank(p.organisationId) ? (Id) p.organisationId : fallbackHostAccountId;
                        if (resolvedAccountId == null) {
                            continue; // no Account to hang the new Contact off of
                        }
                        Contact con = new Contact();
                        con.AccountId = resolvedAccountId;
                        con.Salutation = p.salutation;
                        con.FirstName = p.firstName;
                        con.MiddleName = p.middleName;
                        con.LastName = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown';
                        con.Suffix = p.suffix;
                        con.Email = p.email;
                        con.Birthdate = p.birthdate;
                        con.Department = p.department;
                        con.Gender__c = p.gender;
                        con.Nationality__c = p.nationality;
                        con.Position__c = p.currentPosition;
                        con.Phone = p.telePhone;
                        con.MailingStreet = p.mailingStreet;
                        con.MailingCity = p.mailingCity;
                        con.MailingState = p.mailingState;
                        con.MailingPostalCode = p.mailingPostalCode;
                        con.MailingCountry = p.mailingCountry;
                        con.Added_as_Sponsor__c = (p.role == ROLE_SPONSOR);
                        con.Added_as_Supervisor__c = (p.role == ROLE_SUPERVISOR);
                        newContactsToInsert.add(con);
                        newContactIndexes.add(idx);
                    }
                }

                if (!newContactsToInsert.isEmpty()) {
                    insert newContactsToInsert;
                    for (Integer k = 0; k < newContactIndexes.size(); k++) {
                        Integer pIdx = newContactIndexes[k];
                        reqBody.participants[pIdx].contactId = newContactsToInsert[k].Id;
                        createdParticipantContactIds.add(newContactsToInsert[k].Id);
                    }
                }

                // 3. Look up any PPA records that already exist for these
                //    Contacts under this Proposal, so we update rather than
                //    duplicate them.
                Set<Id> allContactIdsInvolved = new Set<Id>();
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isNotBlank(p.contactId)) {
                        allContactIdsInvolved.add((Id) p.contactId);
                    }
                }

                Map<Id, Id> contactIdToExistingPpaId = new Map<Id, Id>();
                if (!allContactIdsInvolved.isEmpty()) {
                    for (Proposal_Participant_Association__c existingPpa : [
                        SELECT Id, Participant__c
                        FROM Proposal_Participant_Association__c
                        WHERE Proposal__c = :proposalId
                        AND Participant__c IN :allContactIdsInvolved
                        AND Stage__c = :PPA_STAGE
                    ]) {
                        contactIdToExistingPpaId.put(existingPpa.Participant__c, existingPpa.Id);
                    }
                }

                // 4. Upsert the PPA records — update ones that already exist
                //    for this Contact/Proposal/Stage, insert only the
                //    genuinely new ones.
                List<Proposal_Participant_Association__c> ppaListToUpdate = new List<Proposal_Participant_Association__c>();
                List<Proposal_Participant_Association__c> ppaListToInsert = new List<Proposal_Participant_Association__c>();

                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId)) {
                        continue; // couldn't resolve or create a Contact for this row
                    }

                    Id existingPpaId = contactIdToExistingPpaId.get((Id) p.contactId);
                    if (existingPpaId != null) {
                        ppaListToUpdate.add(new Proposal_Participant_Association__c(
                            Id = existingPpaId,
                            Roles__c = p.role,
                            Relationship_of_current_app_to_Host__c = p.relationshipOfCurrentApplicant,
                            Added_for_Full__c = p.partcipantAddedForFull != null ? p.partcipantAddedForFull : false,
                            Notify_through_Email__c = p.notifyThroughEmailForPPA != null ? p.notifyThroughEmailForPPA : false, 
                            Added_for_Additional_Role__c = p.addedForAdditionalRoleInPPA != null ? p.addedForAdditionalRoleInPPA : false, 
                            How_will_you_support_Applicant_s_career__c = p.howWillYouSupportApplicantsCareer
                        ));
                    } else {
                        ppaListToInsert.add(new Proposal_Participant_Association__c(
                            Proposal__c = proposalId,
                            Participant__c = p.contactId,
                            Roles__c = p.role,
                            Stage__c = PPA_STAGE,
                            Relationship_of_current_app_to_Host__c = p.relationshipOfCurrentApplicant,
                            Added_for_Full__c = p.partcipantAddedForFull != null ? p.partcipantAddedForFull : false,
                            Notify_through_Email__c = p.notifyThroughEmailForPPA != null ? p.notifyThroughEmailForPPA : false,
                            Added_for_Additional_Role__c = p.addedForAdditionalRoleInPPA != null ? p.addedForAdditionalRoleInPPA : false,
                            How_will_you_support_Applicant_s_career__c = p.howWillYouSupportApplicantsCareer
                        ));
                    }
                }

                if (!ppaListToUpdate.isEmpty()) {
                    update ppaListToUpdate;
                    for (Proposal_Participant_Association__c ppa : ppaListToUpdate) {
                        ppaIds.add(ppa.Id);
                    }
                }
                if (!ppaListToInsert.isEmpty()) {
                    insert ppaListToInsert;
                    for (Proposal_Participant_Association__c ppa : ppaListToInsert) {
                        ppaIds.add(ppa.Id);
                    }
                }
            }

            // =========================================================
            // BRANCH 2: any role other than Supervisor/Sponsor
            //           -> Additional_Partcipant__c (no Contact involved)
            //           UPSERT semantics:
            //           - existing additionalParticipantId (validated
            //             against this Proposal) -> update in place
            //           - blank/invalid additionalParticipantId -> insert
            // =========================================================
            if (!additionalIndexes.isEmpty()) {

                // 1. Collect candidate Ids to update.
                Set<Id> candidateUpdateIds = new Set<Id>();
                for (Integer idx : additionalIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isNotBlank(p.additionalParticipantId)) {
                        candidateUpdateIds.add((Id) p.additionalParticipantId);
                    }
                }

                // 2. Validate the supplied Ids actually belong to this
                //    Proposal before trusting them for an update — avoids a
                //    DML failure on a stale/foreign Id and prevents
                //    cross-proposal edits.
                Set<Id> validUpdateIds = new Set<Id>();
                if (!candidateUpdateIds.isEmpty()) {
                    for (Additional_Partcipant__c existingAp : [
                        SELECT Id
                        FROM Additional_Partcipant__c
                        WHERE Id IN :candidateUpdateIds
                        AND Proposal__c = :proposalId
                    ]) {
                        validUpdateIds.add(existingAp.Id);
                    }
                }

                List<Additional_Partcipant__c> additionalListToUpdate = new List<Additional_Partcipant__c>();
                List<Additional_Partcipant__c> additionalListToInsert = new List<Additional_Partcipant__c>();

                for (Integer idx : additionalIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    Id existingId = String.isNotBlank(p.additionalParticipantId) ? (Id) p.additionalParticipantId : null;

                    // Checkbox fields cannot accept an explicit null in DML —
                    // if the frontend omits refereeAddedForFull, the wrapper
                    // Boolean deserializes to null, which Salesforce rejects
                    // with INVALID_TYPE_ON_FIELD_IN_RECORD. Coalesce to false.
                    Boolean refereeAddedForFullValue = p.refereeAddedForFull != null ? p.refereeAddedForFull : false;
                   

                    if (existingId != null && validUpdateIds.contains(existingId)) {
                        additionalListToUpdate.add(new Additional_Partcipant__c(
                            Id = existingId,
                            Roles__c = p.role,
                            First_Name__c = p.firstName,
                            Last_Name__c = p.lastName,
                            Email__c = p.email,
                            Department__c = p.department,
                            Designation__c = p.currentPosition,
                            Gender__c = p.gender,
                            Nationality__c = p.nationality,
                            Organisation__c = p.organisationName,
                            Telephone__c = p.telePhone,
                            Title__c = p.salutation,
                            What_guidance_from_chosen_mentor__c = p.whatGuidanceFromChosenMentor,
                            Referee_Added_For_Full__c = refereeAddedForFullValue,
                            Notify_through_Email__c = p.notifyThroughEmail != null ? p.notifyThroughEmail : false,
                            Added_for_Additional_Role__c = p.addedForAdditionalRoleInAP != null ? p.addedForAdditionalRoleInAP : false,                           
                            Contact__c = p.contactId
                        ));
                    } else {
                        additionalListToInsert.add(new Additional_Partcipant__c(
                            Proposal__c = proposalId,
                            Roles__c = p.role,
                            First_Name__c = p.firstName,
                            Last_Name__c = p.lastName,
                            Email__c = p.email,
                            Department__c = p.department,
                            Designation__c = p.currentPosition,
                            Gender__c = p.gender,
                            Nationality__c = p.nationality,
                            Organisation__c = p.organisationName,
                            Telephone__c = p.telePhone,
                            Title__c = p.salutation,
                            What_guidance_from_chosen_mentor__c = p.whatGuidanceFromChosenMentor,
                            Referee_Added_For_Full__c = refereeAddedForFullValue,
                            Notify_through_Email__c = p.notifyThroughEmail != null ? p.notifyThroughEmail : false,
                            Stage__c = ADDITIONAL_PARTICIPANT_STAGE,
                            Added_for_Additional_Role__c = p.addedForAdditionalRoleInAP != null ? p.addedForAdditionalRoleInAP : false,
                            Contact__c = p.contactId
                        ));
                    }
                }

                if (!additionalListToUpdate.isEmpty()) {
                    update additionalListToUpdate;
                    for (Additional_Partcipant__c ap : additionalListToUpdate) {
                        additionalParticipantIds.add(ap.Id);
                    }
                }
                if (!additionalListToInsert.isEmpty()) {
                    insert additionalListToInsert;
                    for (Additional_Partcipant__c ap : additionalListToInsert) {
                        additionalParticipantIds.add(ap.Id);
                    }
                }
            }

            response.success = true;
            response.message = 'Participants processed successfully.';
            response.proposalId = proposalId;
            response.ppaIds = ppaIds;
            response.additionalParticipantIds = additionalParticipantIds;
            response.createdParticipantContactIds = createdParticipantContactIds;

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = 'Error saving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class SaveParticipantRequestWrapper {
        global String proposalId;
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global String contactId;   // Branch 1 (Supervisor/Sponsor) only.
                                    // Blank => create a new Contact + PPA.
                                    // Populated => update that Contact, and
                                    // update the existing PPA for this
                                    // Proposal/Contact if one exists,
                                    // otherwise insert one.
        global String role;        // drives which branch this row goes to

        // Shared person fields
        global String salutation;      // Contact.Salutation / Additional_Partcipant__c.Title__c
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition; // Contact.Position__c / Additional_Partcipant__c.Designation__c
        global String telePhone;

        // Contact-branch only
        // Used only when creating a NEW Contact (blank contactId). Ignored
        // once a contactId is supplied — the existing Contact's AccountId is
        // left untouched.
        global String organisationId;  // Account Id used for new Contact creation
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;

        // PPA-branch only (Supervisor/Sponsor)
        global String relationshipOfCurrentApplicant;      // PPA.Relationship_of_current_app_to_Host__c
        global String howWillYouSupportApplicantsCareer;   // PPA.How_will_you_support_Applicant_s_career__c

        // Additional Participant branch only
        global String organisationName;         // free-text Organisation__c
        global String whatGuidanceFromChosenMentor;
        global Boolean partcipantAddedForFull;
        global Boolean addedForAdditionalRoleInPPA;
        global Boolean addedForAdditionalRoleInAP;
        global Boolean refereeAddedForFull;      // Checkbox on Additional_Partcipant__c.
                                                  // If omitted by the frontend, this
                                                  // deserializes to null; the save logic
                                                  // coalesces null to false before DML,
                                                  // since Checkbox fields cannot accept
                                                  // an explicit null value.
        global String additionalParticipantId;  // Blank => insert a new
                                                  // Additional_Partcipant__c row.
                                                  // Populated => update that
                                                  // row in place, provided it
                                                  // belongs to this Proposal.
        global Boolean notifyThroughEmail;
        global Boolean notifyThroughEmailForPPA;
    }

    global class SaveParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global String proposalId;
        global List<Id> ppaIds;
        global List<Id> additionalParticipantIds;
        global List<Id> createdParticipantContactIds;
    }
}







/*Previous One
@RestResource(urlMapping='/SaveProposalParticipantFull/*')
global without sharing class SaveProposalParticipantFullAPI {

    private static final Set<String> CONTACT_BACKED_ROLES = new Set<String>{'Supervisor', 'Sponsor'};
    private static final String PPA_STAGE = 'Full';
    private static final String ADDITIONAL_PARTICIPANT_STAGE = 'Full';

    @HttpPost
    global static SaveParticipantResponseWrapper saveParticipants() {
        SaveParticipantResponseWrapper response = new SaveParticipantResponseWrapper();
        Savepoint sp = Database.setSavepoint();

        try {
            RestRequest req = RestContext.request;
            SaveParticipantRequestWrapper reqBody =
                (SaveParticipantRequestWrapper) JSON.deserialize(
                    req.requestBody.toString(), SaveParticipantRequestWrapper.class
                );

            if (String.isBlank(reqBody.proposalId)) {
                response.success = false;
                response.message = 'proposalId is required.';
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id FROM Proposal__c WHERE Id = :reqBody.proposalId LIMIT 1
            ];
            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'Proposal record could not be found.';
                Database.rollback(sp);
                return response;
            }
            Id proposalId = proposalList[0].Id;

            if (reqBody.participants == null || reqBody.participants.isEmpty()) {
                response.success = true;
                response.message = 'No participants supplied.';
                response.proposalId = proposalId;
                return response;
            }

            List<Id> ppaIds = new List<Id>();
            List<Id> additionalParticipantIds = new List<Id>();
            List<Id> createdParticipantContactIds = new List<Id>();

            // ---- Split participants by role type ----
            List<Integer> ppaIndexes = new List<Integer>();
            List<Integer> additionalIndexes = new List<Integer>();

            for (Integer i = 0; i < reqBody.participants.size(); i++) {
                ParticipantWrapper p = reqBody.participants[i];
                if (p.role != null && CONTACT_BACKED_ROLES.contains(p.role)) {
                    ppaIndexes.add(i);
                } else {
                    additionalIndexes.add(i);
                }
            }

            // =========================================================
            // BRANCH 1: Supervisor / Sponsor -> Contact + PPA
            //           UPSERT semantics:
            //           - existing contactId -> update Contact, update the
            //             existing PPA (matched by Proposal__c +
            //             Participant__c + Stage__c) or insert one if none
            //             exists yet
            //           - blank contactId     -> create new Contact,
            //             insert new PPA
            // =========================================================
            if (!ppaIndexes.isEmpty()) {

                Boolean needsFallbackHostAccount = false;
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId) && String.isBlank(p.organisationId)) {
                        needsFallbackHostAccount = true;
                        break;
                    }
                }

                Id fallbackHostAccountId;
                if (needsFallbackHostAccount) {
                    List<Applicant_Host_Association__c> ahaList = [
                        SELECT Id, Host__c
                        FROM Applicant_Host_Association__c
                        WHERE Proposal__c = :proposalId
                        AND Host__c != null
                        ORDER BY CreatedDate ASC
                        LIMIT 1
                    ];
                    if (!ahaList.isEmpty()) {
                        fallbackHostAccountId = ahaList[0].Host__c;
                    }
                }

                // 1. Update existing Contacts for rows that already carry a
                //    contactId (bulk update — no re-query needed since we
                //    are overwriting explicit fields only).
                List<Contact> contactsToUpdate = new List<Contact>();
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isNotBlank(p.contactId)) {
                        contactsToUpdate.add(new Contact(
                            Id = (Id) p.contactId,
                            Salutation = p.salutation,
                            FirstName = p.firstName,
                            MiddleName = p.middleName,
                            LastName = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown',
                            Suffix = p.suffix,
                            Email = p.email,
                            Birthdate = p.birthdate,
                            Department = p.department,
                            Gender__c = p.gender,
                            Nationality__c = p.nationality,
                            Position__c = p.currentPosition,
                            Phone = p.telePhone,
                            MailingStreet = p.mailingStreet,
                            MailingCity = p.mailingCity,
                            MailingState = p.mailingState,
                            MailingPostalCode = p.mailingPostalCode,
                            MailingCountry = p.mailingCountry
                        ));
                    }
                }
                if (!contactsToUpdate.isEmpty()) {
                    update contactsToUpdate;
                }

                // 2. Bulk create Contacts only for participants missing a
                //    contactId.
                List<Integer> newContactIndexes = new List<Integer>();
                List<Contact> newContactsToInsert = new List<Contact>();

                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId)) {
                        Id resolvedAccountId = String.isNotBlank(p.organisationId) ? (Id) p.organisationId : fallbackHostAccountId;
                        if (resolvedAccountId == null) {
                            continue; // no Account to hang the new Contact off of
                        }
                        Contact con = new Contact();
                        con.AccountId = resolvedAccountId;
                        con.Salutation = p.salutation;
                        con.FirstName = p.firstName;
                        con.MiddleName = p.middleName;
                        con.LastName = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown';
                        con.Suffix = p.suffix;
                        con.Email = p.email;
                        con.Birthdate = p.birthdate;
                        con.Department = p.department;
                        con.Gender__c = p.gender;
                        con.Nationality__c = p.nationality;
                        con.Position__c = p.currentPosition;
                        con.Phone = p.telePhone;
                        con.MailingStreet = p.mailingStreet;
                        con.MailingCity = p.mailingCity;
                        con.MailingState = p.mailingState;
                        con.MailingPostalCode = p.mailingPostalCode;
                        con.MailingCountry = p.mailingCountry;
                        newContactsToInsert.add(con);
                        newContactIndexes.add(idx);
                    }
                }

                if (!newContactsToInsert.isEmpty()) {
                    insert newContactsToInsert;
                    for (Integer k = 0; k < newContactIndexes.size(); k++) {
                        Integer pIdx = newContactIndexes[k];
                        reqBody.participants[pIdx].contactId = newContactsToInsert[k].Id;
                        createdParticipantContactIds.add(newContactsToInsert[k].Id);
                    }
                }

                // 3. Look up any PPA records that already exist for these
                //    Contacts under this Proposal, so we update rather than
                //    duplicate them.
                Set<Id> allContactIdsInvolved = new Set<Id>();
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isNotBlank(p.contactId)) {
                        allContactIdsInvolved.add((Id) p.contactId);
                    }
                }

                Map<Id, Id> contactIdToExistingPpaId = new Map<Id, Id>();
                if (!allContactIdsInvolved.isEmpty()) {
                    for (Proposal_Participant_Association__c existingPpa : [
                        SELECT Id, Participant__c
                        FROM Proposal_Participant_Association__c
                        WHERE Proposal__c = :proposalId
                        AND Participant__c IN :allContactIdsInvolved
                        AND Stage__c = :PPA_STAGE
                    ]) {
                        contactIdToExistingPpaId.put(existingPpa.Participant__c, existingPpa.Id);
                    }
                }

                // 4. Upsert the PPA records — update ones that already exist
                //    for this Contact/Proposal/Stage, insert only the
                //    genuinely new ones.
                List<Proposal_Participant_Association__c> ppaListToUpdate = new List<Proposal_Participant_Association__c>();
                List<Proposal_Participant_Association__c> ppaListToInsert = new List<Proposal_Participant_Association__c>();

                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId)) {
                        continue; // couldn't resolve or create a Contact for this row
                    }

                    Id existingPpaId = contactIdToExistingPpaId.get((Id) p.contactId);
                    if (existingPpaId != null) {
                        ppaListToUpdate.add(new Proposal_Participant_Association__c(
                            Id = existingPpaId,
                            Roles__c = p.role
                        ));
                    } else {
                        ppaListToInsert.add(new Proposal_Participant_Association__c(
                            Proposal__c = proposalId,
                            Participant__c = p.contactId,
                            Roles__c = p.role,
                            Stage__c = PPA_STAGE
                        ));
                    }
                }

                if (!ppaListToUpdate.isEmpty()) {
                    update ppaListToUpdate;
                    for (Proposal_Participant_Association__c ppa : ppaListToUpdate) {
                        ppaIds.add(ppa.Id);
                    }
                }
                if (!ppaListToInsert.isEmpty()) {
                    insert ppaListToInsert;
                    for (Proposal_Participant_Association__c ppa : ppaListToInsert) {
                        ppaIds.add(ppa.Id);
                    }
                }
            }

            // =========================================================
            // BRANCH 2: any role other than Supervisor/Sponsor
            //           -> Additional_Partcipant__c (no Contact involved)
            //           UPSERT semantics:
            //           - existing additionalParticipantId (validated
            //             against this Proposal) -> update in place
            //           - blank/invalid additionalParticipantId -> insert
            // =========================================================
            if (!additionalIndexes.isEmpty()) {

                // 1. Collect candidate Ids to update.
                Set<Id> candidateUpdateIds = new Set<Id>();
                for (Integer idx : additionalIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isNotBlank(p.additionalParticipantId)) {
                        candidateUpdateIds.add((Id) p.additionalParticipantId);
                    }
                }

                // 2. Validate the supplied Ids actually belong to this
                //    Proposal before trusting them for an update — avoids a
                //    DML failure on a stale/foreign Id and prevents
                //    cross-proposal edits.
                Set<Id> validUpdateIds = new Set<Id>();
                if (!candidateUpdateIds.isEmpty()) {
                    for (Additional_Partcipant__c existingAp : [
                        SELECT Id
                        FROM Additional_Partcipant__c
                        WHERE Id IN :candidateUpdateIds
                        AND Proposal__c = :proposalId
                    ]) {
                        validUpdateIds.add(existingAp.Id);
                    }
                }

                List<Additional_Partcipant__c> additionalListToUpdate = new List<Additional_Partcipant__c>();
                List<Additional_Partcipant__c> additionalListToInsert = new List<Additional_Partcipant__c>();

                for (Integer idx : additionalIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    Id existingId = String.isNotBlank(p.additionalParticipantId) ? (Id) p.additionalParticipantId : null;

                    if (existingId != null && validUpdateIds.contains(existingId)) {
                        additionalListToUpdate.add(new Additional_Partcipant__c(
                            Id = existingId,
                            Roles__c = p.role,
                            First_Name__c = p.firstName,
                            Last_Name__c = p.lastName,
                            Email__c = p.email,
                            Department__c = p.department,
                            Designation__c = p.currentPosition,
                            Gender__c = p.gender,
                            Nationality__c = p.nationality,
                            Organisation__c = p.organisationName,
                            Telephone__c = p.telePhone,
                            Title__c = p.salutation,
                            What_guidance_from_chosen_mentor__c = p.whatGuidanceFromChosenMentor
                        ));
                    } else {
                        additionalListToInsert.add(new Additional_Partcipant__c(
                            Proposal__c = proposalId,
                            Roles__c = p.role,
                            First_Name__c = p.firstName,
                            Last_Name__c = p.lastName,
                            Email__c = p.email,
                            Department__c = p.department,
                            Designation__c = p.currentPosition,
                            Gender__c = p.gender,
                            Nationality__c = p.nationality,
                            Organisation__c = p.organisationName,
                            Telephone__c = p.telePhone,
                            Title__c = p.salutation,
                            What_guidance_from_chosen_mentor__c = p.whatGuidanceFromChosenMentor,
                            Stage__c = ADDITIONAL_PARTICIPANT_STAGE
                        ));
                    }
                }

                if (!additionalListToUpdate.isEmpty()) {
                    update additionalListToUpdate;
                    for (Additional_Partcipant__c ap : additionalListToUpdate) {
                        additionalParticipantIds.add(ap.Id);
                    }
                }
                if (!additionalListToInsert.isEmpty()) {
                    insert additionalListToInsert;
                    for (Additional_Partcipant__c ap : additionalListToInsert) {
                        additionalParticipantIds.add(ap.Id);
                    }
                }
            }

            response.success = true;
            response.message = 'Participants processed successfully.';
            response.proposalId = proposalId;
            response.ppaIds = ppaIds;
            response.additionalParticipantIds = additionalParticipantIds;
            response.createdParticipantContactIds = createdParticipantContactIds;

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = 'Error saving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class SaveParticipantRequestWrapper {
        global String proposalId;
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global String contactId;   // Branch 1 (Supervisor/Sponsor) only.
                                    // Blank => create a new Contact + PPA.
                                    // Populated => update that Contact, and
                                    // update the existing PPA for this
                                    // Proposal/Contact if one exists,
                                    // otherwise insert one.
        global String role;        // drives which branch this row goes to

        // Shared person fields
        global String salutation;      // Contact.Salutation / Additional_Partcipant__c.Title__c
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition; // Contact.Position__c / Additional_Partcipant__c.Designation__c
        global String telePhone;

        // Contact-branch only
        // Used only when creating a NEW Contact (blank contactId). Ignored
        // once a contactId is supplied — the existing Contact's AccountId is
        // left untouched.
        global String organisationId;  // Account Id used for new Contact creation
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;

        // Additional Participant branch only
        global String organisationName;         // free-text Organisation__c
        global String whatGuidanceFromChosenMentor;
        global String additionalParticipantId;  // Blank => insert a new
                                                  // Additional_Partcipant__c row.
                                                  // Populated => update that
                                                  // row in place, provided it
                                                  // belongs to this Proposal.
    }

    global class SaveParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global String proposalId;
        global List<Id> ppaIds;
        global List<Id> additionalParticipantIds;
        global List<Id> createdParticipantContactIds;
    }
}*/






/*
@RestResource(urlMapping='/SaveProposalParticipantFull/*')
global without sharing class SaveProposalParticipantFullAPI {

    private static final Set<String> CONTACT_BACKED_ROLES = new Set<String>{'Supervisor', 'Sponsor'};

    @HttpPost
    global static SaveParticipantResponseWrapper saveParticipants() {
        SaveParticipantResponseWrapper response = new SaveParticipantResponseWrapper();
        Savepoint sp = Database.setSavepoint();

        try {
            RestRequest req = RestContext.request;
            SaveParticipantRequestWrapper reqBody =
                (SaveParticipantRequestWrapper) JSON.deserialize(
                    req.requestBody.toString(), SaveParticipantRequestWrapper.class
                );

            if (String.isBlank(reqBody.proposalId)) {
                response.success = false;
                response.message = 'proposalId is required.';
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id FROM Proposal__c WHERE Id = :reqBody.proposalId LIMIT 1
            ];
            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'Proposal record could not be found.';
                Database.rollback(sp);
                return response;
            }
            Id proposalId = proposalList[0].Id;

            if (reqBody.participants == null || reqBody.participants.isEmpty()) {
                response.success = true;
                response.message = 'No participants supplied.';
                response.proposalId = proposalId;
                return response;
            }

            List<Id> ppaIds = new List<Id>();
            List<Id> additionalParticipantIds = new List<Id>();
            List<Id> createdParticipantContactIds = new List<Id>();

            // ---- Split participants by role type ----
            List<Integer> ppaIndexes = new List<Integer>();
            List<Integer> additionalIndexes = new List<Integer>();

            for (Integer i = 0; i < reqBody.participants.size(); i++) {
                ParticipantWrapper p = reqBody.participants[i];
                if (p.role != null && CONTACT_BACKED_ROLES.contains(p.role)) {
                    ppaIndexes.add(i);
                } else {
                    additionalIndexes.add(i);
                }
            }

            // =========================================================
            // BRANCH 1: Supervisor / Sponsor -> Contact + PPA
            // =========================================================
            if (!ppaIndexes.isEmpty()) {

                Boolean needsFallbackHostAccount = false;
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId) && String.isBlank(p.organisationId)) {
                        needsFallbackHostAccount = true;
                        break;
                    }
                }

                Id fallbackHostAccountId;
                if (needsFallbackHostAccount) {
                    List<Applicant_Host_Association__c> ahaList = [
                        SELECT Id, Host__c
                        FROM Applicant_Host_Association__c
                        WHERE Proposal__c = :proposalId
                        AND Host__c != null
                        ORDER BY CreatedDate ASC
                        LIMIT 1
                    ];
                    if (!ahaList.isEmpty()) {
                        fallbackHostAccountId = ahaList[0].Host__c;
                    }
                }

                // Bulk create Contacts only for participants missing a contactId
                List<Integer> newContactIndexes = new List<Integer>();
                List<Contact> newContactsToInsert = new List<Contact>();

                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId)) {
                        Id resolvedAccountId = String.isNotBlank(p.organisationId) ? (Id) p.organisationId : fallbackHostAccountId;
                        if (resolvedAccountId == null) {
                            continue; // no Account to hang the new Contact off of
                        }
                        Contact con = new Contact();
                        con.AccountId = resolvedAccountId;
                        con.Salutation = p.salutation;
                        con.FirstName = p.firstName;
                        con.MiddleName = p.middleName;
                        con.LastName = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown';
                        con.Suffix = p.suffix;
                        con.Email = p.email;
                        con.Birthdate = p.birthdate;
                        con.Department = p.department;
                        con.Gender__c = p.gender;
                        con.Nationality__c = p.nationality;
                        con.Position__c = p.currentPosition;
                        con.Phone = p.telePhone;
                        con.MailingStreet = p.mailingStreet;
                        con.MailingCity = p.mailingCity;
                        con.MailingState = p.mailingState;
                        con.MailingPostalCode = p.mailingPostalCode;
                        con.MailingCountry = p.mailingCountry;
                        newContactsToInsert.add(con);
                        newContactIndexes.add(idx);
                    }
                }

                if (!newContactsToInsert.isEmpty()) {
                    insert newContactsToInsert;
                    for (Integer k = 0; k < newContactIndexes.size(); k++) {
                        Integer pIdx = newContactIndexes[k];
                        reqBody.participants[pIdx].contactId = newContactsToInsert[k].Id;
                        createdParticipantContactIds.add(newContactsToInsert[k].Id);
                    }
                }

                // Build the PPA records — either tagging the passed contactId,
                // or the one we just created above.
                List<Proposal_Participant_Association__c> ppaListToInsert = new List<Proposal_Participant_Association__c>();
                for (Integer idx : ppaIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    if (String.isBlank(p.contactId)) {
                        continue; // couldn't resolve or create a Contact for this row
                    }
                    ppaListToInsert.add(new Proposal_Participant_Association__c(
                        Proposal__c = proposalId,
                        Participant__c = p.contactId,
                        Roles__c = p.role,
                        Stage__c = 'Full'                      
                    ));
                }

                if (!ppaListToInsert.isEmpty()) {
                    insert ppaListToInsert;
                    for (Proposal_Participant_Association__c ppa : ppaListToInsert) {
                        ppaIds.add(ppa.Id);
                    }
                }
            }

            // =========================================================
            // BRANCH 2: any role other than Supervisor/Sponsor
            //           -> Additional_Partcipant__c (no Contact involved)
            // =========================================================
            if (!additionalIndexes.isEmpty()) {
                List<Additional_Partcipant__c> additionalListToInsert = new List<Additional_Partcipant__c>();

                for (Integer idx : additionalIndexes) {
                    ParticipantWrapper p = reqBody.participants[idx];
                    additionalListToInsert.add(new Additional_Partcipant__c(
                        Proposal__c = proposalId,
                        Roles__c = p.role,
                        First_Name__c = p.firstName,
                        Last_Name__c = p.lastName,
                        Email__c = p.email,
                        Department__c = p.department,
                        Designation__c = p.currentPosition,
                        Gender__c = p.gender,
                        Nationality__c = p.nationality,
                        Organisation__c = p.organisationName,
                        Telephone__c = p.telePhone,
                        Title__c = p.salutation,
                        Stage__c = 'Full'
                    ));
                }

                insert additionalListToInsert;
                for (Additional_Partcipant__c ap : additionalListToInsert) {
                    additionalParticipantIds.add(ap.Id);
                }
            }

            response.success = true;
            response.message = 'Participants processed successfully.';
            response.proposalId = proposalId;
            response.ppaIds = ppaIds;
            response.additionalParticipantIds = additionalParticipantIds;
            response.createdParticipantContactIds = createdParticipantContactIds;

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = 'Error saving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class SaveParticipantRequestWrapper {
        global String proposalId;
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global String contactId;   // blank => create new Contact (Supervisor/Sponsor branch only)
        global String role;        // drives which branch this row goes to

        // Shared person fields
        global String salutation;      // Contact.Salutation / Additional_Partcipant__c.Title__c
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition; // Contact.Position__c / Additional_Partcipant__c.Designation__c
        global String telePhone;

        // Contact-branch only
        global String organisationId;  // Account Id used for new Contact creation
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;      
             

        // Additional Participant branch only
        global String organisationName; // free-text Organisation__c
    }

    global class SaveParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global String proposalId;
        global List<Id> ppaIds;
        global List<Id> additionalParticipantIds;
        global List<Id> createdParticipantContactIds;
    }
}*/