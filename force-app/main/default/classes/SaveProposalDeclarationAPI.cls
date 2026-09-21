@RestResource(urlMapping='/ProposalDeclaration/submit/*')
global without sharing class SaveProposalDeclarationAPI {

    private static final String PROPOSAL_STATUS_DRAFT = 'Draft';
    private static final String REOPEN_STATUS_CLOSED = 'Closed';
    private static final Set<String> CONTACT_BACKED_ROLES = new Set<String>{'Supervisor', 'Sponsor'};
    private static final String EXTERNAL_SPONSOR_ROLE = 'External Sponsor';
    private static final String SAVE_TYPE_DRAFT = 'Draft';
    private static final String SAVE_TYPE_SUBMIT = 'Submit';
    private static final String PPA_STAGE = 'Prelims';
    private static final String ADDITIONAL_PARTICIPANT_STAGE = 'Prelims';
    private static final String WOHI_STAGE = 'Prelims';
    private static final String ROLE_SPONSOR = 'Sponsor';
    private static final String ROLE_SUPERVISOR = 'Supervisor';

    @HttpPost
    global static SaveDeclarationResponseWrapper saveDeclaration() {
        SaveDeclarationResponseWrapper response = new SaveDeclarationResponseWrapper();
        Savepoint sp = Database.setSavepoint();

        try {
            RestRequest req = RestContext.request;
            SaveDeclarationRequestWrapper reqBody = (SaveDeclarationRequestWrapper) JSON.deserialize(req.requestBody.toString(), SaveDeclarationRequestWrapper.class);

            System.debug('req ====> ' + req);

            // ---- Resolve the APA record (dual-lookup pattern) ----
            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(reqBody.apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :reqBody.apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(reqBody.proposalId) && String.isNotBlank(reqBody.contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :reqBody.proposalId
                    AND Contact__c = :reqBody.contactId
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

            // ---- Validate saveType (Draft/Submit) ----
            String saveType = reqBody.saveType;
            if (String.isBlank(saveType) ||
                !(saveType.equalsIgnoreCase(SAVE_TYPE_DRAFT) || saveType.equalsIgnoreCase(SAVE_TYPE_SUBMIT))) {
                response.success = false;
                response.message = 'saveType is required and must be either \'Draft\' or \'Submit\'.';
                return response;
            }
            Boolean isDraftSave = saveType.equalsIgnoreCase(SAVE_TYPE_DRAFT);

            if (apaRecord.Applicant_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Applicant already submitted the Proposal and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = apaRecord.Proposal__c ;
                Database.rollback(sp);
                return response;
            }
            // ---- Update APA declarations ----
            apaRecord.Declaration_1__c = reqBody.declaration1;
            apaRecord.Declaration_2__c = reqBody.declaration2;
            apaRecord.Applicant_Status__c = isDraftSave ? SAVE_TYPE_DRAFT : 'Submitted';
            update apaRecord;

            // ---- Update related Proposal__c ----
            if (apaRecord.Proposal__c == null) {
                response.success = false;
                response.message = 'Applicant Proposal Association is not linked to a Proposal record.';
                Database.rollback(sp);
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id, Proposal_Status__c, Application_Date__c
                FROM Proposal__c
                WHERE Id = :apaRecord.Proposal__c
                LIMIT 1
            ];

            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'Linked Proposal record could not be found.';
                Database.rollback(sp);
                return response;
            }

            Proposal__c proposalRecord = proposalList[0];

            // ---- Idempotency guard: block re-submission ----
            if (proposalRecord.Proposal_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Proposal has already been submitted and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = proposalRecord.Id;
                Database.rollback(sp);
                return response;
            }

            proposalRecord.Proposal_Status__c = isDraftSave ? SAVE_TYPE_DRAFT : 'Submitted';
            proposalRecord.Application_Date__c = Date.today();
            update proposalRecord;

            // ---- Proposal not in Draft -> close out Scheme_Section__c records ----
            // Same condition style as saveOtherGrantsAndApplicationDetails:
            // gate on Proposal_Status__c != 'Draft' rather than closing
            // unconditionally. proposalRecord already reflects the in-memory
            // 'Submitted' value set just above, so no re-query is needed.
            // Bulk-close all Scheme_Section__c records under this APA
            // (Reopen_Status__c = 'Closed'), skipping ones already closed.
            Integer sectionsClosedCount = 0;
            if (proposalRecord.Proposal_Status__c != PROPOSAL_STATUS_DRAFT) {

                List<Scheme_Section__c> sectionsToClose = [
                    SELECT Id, Reopen_Status__c,Application_Stages__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :apaRecord.Id
                    AND Reopen_Status__c != :REOPEN_STATUS_CLOSED AND Section_Name__c = :reqBody.sectionName AND Application_Stages__c ='Prelims'
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

            // =========================================================
            // Participant processing — role-based branching, mirroring
            // SaveProposalParticipantFullAPI, with UPSERT semantics so
            // repeated Draft saves update existing records instead of
            // creating duplicates on every call:
            //   BRANCH 1: Supervisor / Sponsor -> Contact + PPA
            //             - existing contactId  -> update Contact,
            //               update existing PPA (matched by
            //               Proposal__c + Participant__c + Stage__c)
            //               or insert a new PPA if none exists yet
            //             - blank contactId      -> create new Contact,
            //               insert new PPA
            //             NOTE: Contact.Added_as_Sponsor__c /
            //             Contact.Added_as_Supervisor__c are set to true
            //             based on the participant's role, on both the
            //             insert and update paths.
            //   BRANCH 2: any other role -> Additional_Partcipant__c
            //             - existing additionalParticipantId (validated
            //               against this Proposal) -> update in place
            //             - blank/invalid additionalParticipantId -> insert
            //   BRANCH 1.5: External Sponsor -> WOHI_Collaboration__c
            // =========================================================
            List<Id> ppaIds = new List<Id>();
            List<Id> additionalParticipantIds = new List<Id>();
            List<Id> createdParticipantContactIds = new List<Id>();
            List<Id> wohiIds = new List<Id>();

            if (reqBody.participants != null && !reqBody.participants.isEmpty()) {

                System.debug('reqBody.participants ===> ' + reqBody.participants);

                List<Integer> ppaIndexes = new List<Integer>();
                List<Integer> additionalIndexes = new List<Integer>();
                List<Integer> wohiIndexes = new List<Integer>();

                for (Integer i = 0; i < reqBody.participants.size(); i++) {
                    ParticipantWrapper p = reqBody.participants[i];
                    if (p.role != null && CONTACT_BACKED_ROLES.contains(p.role)) {
                        ppaIndexes.add(i);
                    } else if (p.role == EXTERNAL_SPONSOR_ROLE) {
                        wohiIndexes.add(i);
                    } else {
                        additionalIndexes.add(i);
                    }
                }

                // ---------------------------------------------------
                // BRANCH 1: Supervisor / Sponsor -> Contact + PPA
                // ---------------------------------------------------
                if (!ppaIndexes.isEmpty()) {

                    // 1. Resolve the fallback Host Account for this Proposal.
                    //    Only needed if at least one genuinely NEW participant
                    //    (blank contactId) does NOT explicitly supply
                    //    organisationId.
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
                            WHERE Proposal__c = :proposalRecord.Id
                            AND Host__c != null
                            ORDER BY CreatedDate ASC
                            LIMIT 1
                        ];
                        if (!ahaList.isEmpty()) {
                            fallbackHostAccountId = ahaList[0].Host__c;
                        }
                    }

                    // 2. Update existing Contacts for rows that already carry a
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
                                Research_Experience_After_Viva_Date_Mont__c = p.experienceinMonths,
                                Research_Experience_After_Viva_Date_Yrs__c = p.experienceinYears,
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

                    // 3. Bulk create Contacts for rows with a blank contactId.
                    //    AccountId = payload's organisationId if provided,
                    //    otherwise falls back to the resolved Host Account.
                    List<Integer> newContactParticipantIndexes = new List<Integer>();
                    List<Contact> newContactsToInsert = new List<Contact>();

                    for (Integer idx : ppaIndexes) {
                        ParticipantWrapper p = reqBody.participants[idx];

                        if (String.isBlank(p.contactId)) {
                            Id resolvedAccountId = String.isNotBlank(p.organisationId) ? (Id) p.organisationId : fallbackHostAccountId;
                            if (resolvedAccountId == null) {
                                continue; // no organisationId supplied and no Host Account resolvable
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
                            con.Research_Experience_After_Viva_Date_Mont__c = p.experienceinMonths;
                            con.Research_Experience_After_Viva_Date_Yrs__c = p.experienceinYears;
                            con.MailingStreet = p.mailingStreet;
                            con.MailingCity = p.mailingCity;
                            con.MailingState = p.mailingState;
                            con.MailingPostalCode = p.mailingPostalCode;
                            con.MailingCountry = p.mailingCountry;
                            con.Added_as_Sponsor__c = (p.role == ROLE_SPONSOR);
                            con.Added_as_Supervisor__c = (p.role == ROLE_SUPERVISOR);
                            newContactsToInsert.add(con);
                            newContactParticipantIndexes.add(idx);
                        }
                    }

                    if (!newContactsToInsert.isEmpty()) {
                        insert newContactsToInsert;

                        for (Integer k = 0; k < newContactParticipantIndexes.size(); k++) {
                            Integer pIdx = newContactParticipantIndexes[k];
                            reqBody.participants[pIdx].contactId = newContactsToInsert[k].Id;
                            createdParticipantContactIds.add(newContactsToInsert[k].Id);
                        }
                    }

                    // 4. Look up any PPA records that already exist for these
                    //    Contacts under this Proposal, so we update rather
                    //    than duplicate them.
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
                            WHERE Proposal__c = :proposalRecord.Id
                            AND Participant__c IN :allContactIdsInvolved
                            AND Stage__c = :PPA_STAGE
                        ]) {
                            contactIdToExistingPpaId.put(existingPpa.Participant__c, existingPpa.Id);
                        }
                    }

                    // 5. Upsert the PPA records — update ones that already
                    //    exist for this Contact/Proposal/Stage, insert only
                    //    the genuinely new ones.
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
                                Notify_through_Email__c = p.notifyThroughEmailForPPA != null ? p.notifyThroughEmailForPPA : false
                            ));
                        } else {
                            ppaListToInsert.add(new Proposal_Participant_Association__c(
                                Proposal__c = proposalRecord.Id,
                                Participant__c = p.contactId,
                                Roles__c = p.role,
                                Stage__c = PPA_STAGE,
                                Notify_through_Email__c = p.notifyThroughEmailForPPA != null ? p.notifyThroughEmailForPPA : false
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

                // ---------------------------------------------------
                // BRANCH 1.5: External Sponsor -> WOHI_Collaboration__c
                // ---------------------------------------------------
                if (!wohiIndexes.isEmpty()) {

                    // 1. Split rows into "update" (an existing additionalParticipantId was
                    //    supplied) vs "insert" (blank => brand new additionalParticipantId record).
                    Set<Id> candidateWohiUpdateIds = new Set<Id>();
                    for (Integer idx : wohiIndexes) {
                        ParticipantWrapper p = reqBody.participants[idx];
                        if (String.isNotBlank(p.additionalParticipantId)) {
                            candidateWohiUpdateIds.add((Id) p.additionalParticipantId);
                        }
                    }

                    // 2. Validate the supplied Ids actually belong to this APA
                    //    before trusting them for an update.
                    Set<Id> validWohiUpdateIds = new Set<Id>();
                    if (!candidateWohiUpdateIds.isEmpty()) {
                        for (WOHI_Collaboration__c existingWohi : [
                            SELECT Id
                            FROM WOHI_Collaboration__c
                            WHERE Id IN :candidateWohiUpdateIds
                            AND Applicant_Proposal_Association__c = :apaRecord.Id
                        ]) {
                            validWohiUpdateIds.add(existingWohi.Id);
                        }
                    }

                    List<WOHI_Collaboration__c> wohiListToUpdate = new List<WOHI_Collaboration__c>();
                    List<WOHI_Collaboration__c> wohiListToInsert = new List<WOHI_Collaboration__c>();

                    for (Integer idx : wohiIndexes) {
                        ParticipantWrapper p = reqBody.participants[idx];
                        Id existingWohiId = String.isNotBlank(p.additionalParticipantId) ? (Id) p.additionalParticipantId : null;

                        if (existingWohiId != null && validWohiUpdateIds.contains(existingWohiId)) {
                            wohiListToUpdate.add(new WOHI_Collaboration__c(
                                Id = existingWohiId,
                                Title__c = p.salutation,
                                FirstName__c = p.firstName,
                                Last_Name__c = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown',
                                Email__c = p.email,
                                Department__c = p.department,
                                Current_Position__c = p.currentPosition,
                                Gender__c = p.gender,
                                Nationality__c = p.nationality,
                                Organisation__c = p.organisationName,
                                TelephoneNo__c = p.telePhone,
                                City_Town__c = p.mailingCity,
                                State__c = p.mailingState,
                                Postcode__c = p.mailingPostalCode,
                                Type__c = 'WOHI',
                                Application_Stage__c = WOHI_STAGE,
                                Roles__c = p.role
                            ));
                        } else {
                            wohiListToInsert.add(new WOHI_Collaboration__c(
                                Applicant_Proposal_Association__c = apaRecord.Id,
                                Title__c = p.salutation,
                                FirstName__c = p.firstName,
                                Last_Name__c = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown',
                                Email__c = p.email,
                                Department__c = p.department,
                                Current_Position__c = p.currentPosition,
                                Gender__c = p.gender,
                                Nationality__c = p.nationality,
                                Organisation__c = p.organisationName,
                                TelephoneNo__c = p.telePhone,
                                City_Town__c = p.mailingCity,
                                State__c = p.mailingState,
                                Postcode__c = p.mailingPostalCode,
                                Type__c = 'WOHI',
                                Status__c = 'Pending',
                                Application_Stage__c = WOHI_STAGE,
                                Roles__c = p.role
                            ));
                        }
                    }

                    if (!wohiListToUpdate.isEmpty()) {
                        update wohiListToUpdate;
                        for (WOHI_Collaboration__c wohi : wohiListToUpdate) {
                            wohiIds.add(wohi.Id);
                        }
                    }
                    if (!wohiListToInsert.isEmpty()) {
                        insert wohiListToInsert;
                        for (WOHI_Collaboration__c wohi : wohiListToInsert) {
                            wohiIds.add(wohi.Id);
                        }
                    }
                }

                // ---------------------------------------------------
                // BRANCH 2: any role other than Supervisor/Sponsor
                //           -> Additional_Partcipant__c (no Contact involved)
                // ---------------------------------------------------
                if (!additionalIndexes.isEmpty()) {

                    // 1. Split rows into "update" (an existing
                    //    additionalParticipantId was supplied) vs "insert"
                    //    (blank => brand new row).
                    Set<Id> candidateUpdateIds = new Set<Id>();
                    for (Integer idx : additionalIndexes) {
                        ParticipantWrapper p = reqBody.participants[idx];
                        if (String.isNotBlank(p.additionalParticipantId)) {
                            candidateUpdateIds.add((Id) p.additionalParticipantId);
                        }
                    }

                    // 2. Validate the supplied Ids actually belong to this
                    //    Proposal before trusting them for an update — avoids
                    //    a DML failure on a stale/foreign Id and prevents
                    //    cross-proposal edits.
                    Set<Id> validUpdateIds = new Set<Id>();
                    if (!candidateUpdateIds.isEmpty()) {
                        for (Additional_Partcipant__c existingAp : [
                            SELECT Id
                            FROM Additional_Partcipant__c
                            WHERE Id IN :candidateUpdateIds
                            AND Proposal__c = :proposalRecord.Id
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
								Contact__c =p.contactId,
                                // Notify_through_Email__c = !isDraftSave
                                Notify_through_Email__c = p.notifyThroughEmail != null ? p.notifyThroughEmail : false
                            ));
                        } else {
                            additionalListToInsert.add(new Additional_Partcipant__c(
                                Proposal__c = proposalRecord.Id,
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
                                Stage__c = ADDITIONAL_PARTICIPANT_STAGE,
								Contact__c =p.contactId,
                                // Notify_through_Email__c = !isDraftSave
                                 Notify_through_Email__c = p.notifyThroughEmail != null ? p.notifyThroughEmail : false
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
            }

            response.success = true;
            response.message = isDraftSave ? 'Declarations saved as Draft successfully.' : 'Declarations saved and proposal submitted successfully.';
            response.apaId = apaRecord.Id;
            response.proposalId = proposalRecord.Id;
            response.ppaIds = ppaIds;
            response.additionalParticipantIds = additionalParticipantIds;
            response.createdParticipantContactIds = createdParticipantContactIds;
            response.wohiIds = wohiIds;


            String sectionName = reqBody.sectionName;

            if (String.isNotBlank(reqBody.sectionName)) { 
                List<Scheme_Section__c> schemeSectionList = [
                    SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c,Application_Stages__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :reqBody.apaId
                    AND Section_Name__c = :reqBody.sectionName
                    AND Application_Stages__c ='Prelims'
                ];

                if (!schemeSectionList.isEmpty()) {
                    schemeSectionList[0].Data_Filled_Successfully__c = true;
                    update schemeSectionList;
                    response.sectionUpdateResult = true;
                } 
                else {
                    response.sectionUpdateResult = false;
                }
            }

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = 'Error saving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class SaveDeclarationRequestWrapper {
        global String apaId;
        global String proposalId;
        global String contactId;
        global String sectionName;
        global String saveType;        // 'Draft' or 'Submit'
        global Boolean declaration1;
        global Boolean declaration2;
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global String contactId;   // Branch 1 (Supervisor/Sponsor) only.
                                    // Blank => create a new Contact + PPA.
                                    // Populated (e.g. from a prior GET) =>
                                    // update that Contact, and update the
                                    // existing PPA for this Proposal/Contact
                                    // if one exists, otherwise insert one.

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
        // If provided, this Account Id is used directly as a NEW Contact's
        // AccountId. If blank, falls back to the Proposal's resolved Host
        // Account (first Applicant_Host_Association__c, ordered by CreatedDate).
        // Ignored once a contactId is supplied (existing Contact's AccountId
        // is left untouched).
        global String organisationId;
        global Decimal experienceinMonths;
        global Decimal experienceinYears;
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;

        // Additional Participant branch only
        global String organisationName;        // free-text Organisation__c
        global String additionalParticipantId; // Blank => insert a new
                                                 // Additional_Partcipant__c row.
                                                 // Populated (e.g. from a prior
                                                 // GET's AdditionalParticipantWrapper.id)
                                                 // => update that row in place,
                                                 // provided it belongs to this
                                                 // Proposal.
        global Boolean notifyThroughEmail;
        global Boolean notifyThroughEmailForPPA;
    }

    global class SaveDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global List<Id> ppaIds;
        global List<Id> additionalParticipantIds;
        global List<Id> createdParticipantContactIds;
        global List<Id> wohiIds;
        public Boolean sectionUpdateResult;
        public Integer sectionsClosedCount;
    }
}







/*latest one 
@RestResource(urlMapping='/ProposalDeclaration/submit/*')
global without sharing class SaveProposalDeclarationAPI {

    private static final String PROPOSAL_STATUS_DRAFT = 'Draft';
    private static final String REOPEN_STATUS_CLOSED = 'Closed';
    private static final Set<String> CONTACT_BACKED_ROLES = new Set<String>{'Supervisor', 'Sponsor'};

    @HttpPost
    global static SaveDeclarationResponseWrapper saveDeclaration() {
        SaveDeclarationResponseWrapper response = new SaveDeclarationResponseWrapper();
        Savepoint sp = Database.setSavepoint();

        try {
            RestRequest req = RestContext.request;
            SaveDeclarationRequestWrapper reqBody =
                (SaveDeclarationRequestWrapper) JSON.deserialize(
                    req.requestBody.toString(), SaveDeclarationRequestWrapper.class
                );

            System.debug('req ====> ' + req);

            // ---- Resolve the APA record (dual-lookup pattern) ----
            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(reqBody.apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :reqBody.apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(reqBody.proposalId) && String.isNotBlank(reqBody.contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :reqBody.proposalId
                    AND Contact__c = :reqBody.contactId
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

            if (apaRecord.Applicant_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Applicant already submitted the Proposal and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = apaRecord.Proposal__c ;
                Database.rollback(sp);
                return response;
            }
            // ---- Update APA declarations ----
            apaRecord.Declaration_1__c = reqBody.declaration1;
            apaRecord.Declaration_2__c = reqBody.declaration2;
            apaRecord.Applicant_Status__c = 'Submitted';
            update apaRecord;

            // ---- Update related Proposal__c ----
            if (apaRecord.Proposal__c == null) {
                response.success = false;
                response.message = 'Applicant Proposal Association is not linked to a Proposal record.';
                Database.rollback(sp);
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id, Proposal_Status__c, Application_Date__c
                FROM Proposal__c
                WHERE Id = :apaRecord.Proposal__c
                LIMIT 1
            ];

            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'Linked Proposal record could not be found.';
                Database.rollback(sp);
                return response;
            }

            Proposal__c proposalRecord = proposalList[0];

            // ---- Idempotency guard: block re-submission ----
            if (proposalRecord.Proposal_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Proposal has already been submitted and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = proposalRecord.Id;
                Database.rollback(sp);
                return response;
            }

            proposalRecord.Proposal_Status__c = 'Submitted';
            proposalRecord.Application_Date__c = Date.today();
            update proposalRecord;

            // ---- Proposal not in Draft -> close out Scheme_Section__c records ----
            // Same condition style as saveOtherGrantsAndApplicationDetails:
            // gate on Proposal_Status__c != 'Draft' rather than closing
            // unconditionally. proposalRecord already reflects the in-memory
            // 'Submitted' value set just above, so no re-query is needed.
            // Bulk-close all Scheme_Section__c records under this APA
            // (Reopen_Status__c = 'Closed'), skipping ones already closed.
            Integer sectionsClosedCount = 0;
            if (proposalRecord.Proposal_Status__c != PROPOSAL_STATUS_DRAFT) {

                List<Scheme_Section__c> sectionsToClose = [
                    SELECT Id, Reopen_Status__c,Application_Stages__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :apaRecord.Id
                    AND Reopen_Status__c != :REOPEN_STATUS_CLOSED AND Section_Name__c = :reqBody.sectionName AND Application_Stages__c ='Prelims'
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

            // =========================================================
            // Participant processing — role-based branching, mirroring
            // SaveProposalParticipantFullAPI:
            //   BRANCH 1: Supervisor / Sponsor -> Contact + PPA
            //   BRANCH 2: any other role       -> Additional_Partcipant__c
            //             (no Contact involved)
            // =========================================================
            List<Id> ppaIds = new List<Id>();
            List<Id> additionalParticipantIds = new List<Id>();
            List<Id> createdParticipantContactIds = new List<Id>();

            if (reqBody.participants != null && !reqBody.participants.isEmpty()) {

                System.debug('reqBody.participants ===> ' + reqBody.participants);

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

                // ---------------------------------------------------
                // BRANCH 1: Supervisor / Sponsor -> Contact + PPA
                // ---------------------------------------------------
                if (!ppaIndexes.isEmpty()) {

                    // 1. Resolve the fallback Host Account for this Proposal.
                    //    Only needed if at least one NEW participant (blank
                    //    contactId) does NOT explicitly supply organisationId.
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
                            WHERE Proposal__c = :proposalRecord.Id
                            AND Host__c != null
                            ORDER BY CreatedDate ASC
                            LIMIT 1
                        ];
                        if (!ahaList.isEmpty()) {
                            fallbackHostAccountId = ahaList[0].Host__c;
                        }
                    }

                    // 2. Bulk-create Contacts for participants with a blank
                    //    contactId. AccountId = payload's organisationId if
                    //    provided, otherwise falls back to the resolved Host
                    //    Account.
                    List<Integer> newContactParticipantIndexes = new List<Integer>();
                    List<Contact> newContactsToInsert = new List<Contact>();

                    for (Integer idx : ppaIndexes) {
                        ParticipantWrapper p = reqBody.participants[idx];

                        System.debug('p ====> ' + p);

                        if (String.isBlank(p.contactId)) {
                            Id resolvedAccountId = String.isNotBlank(p.organisationId) ? (Id) p.organisationId : fallbackHostAccountId;
                            if (resolvedAccountId == null) {
                                continue; // no organisationId supplied and no Host Account resolvable
                            }

                            System.debug('p.experienceinMonths ==> ' + p.experienceinMonths);
                            System.debug('p.experienceinYears ==> ' + p.experienceinYears);

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
                            con.Research_Experience_After_Viva_Date_Mont__c = p.experienceinMonths;
                            con.Research_Experience_After_Viva_Date_Yrs__c = p.experienceinYears;
                            con.MailingStreet = p.mailingStreet;
                            con.MailingCity = p.mailingCity;
                            con.MailingState = p.mailingState;
                            con.MailingPostalCode = p.mailingPostalCode;
                            con.MailingCountry = p.mailingCountry;
                            newContactsToInsert.add(con);
                            newContactParticipantIndexes.add(idx);
                        }
                    }

                    if (!newContactsToInsert.isEmpty()) {
                        insert newContactsToInsert;
                        System.debug('newContactsToInsert Success');

                        for (Integer k = 0; k < newContactParticipantIndexes.size(); k++) {
                            Integer pIdx = newContactParticipantIndexes[k];
                            reqBody.participants[pIdx].contactId = newContactsToInsert[k].Id;
                            createdParticipantContactIds.add(newContactsToInsert[k].Id);
                        }
                    }

                    // 3. Build the Proposal_Participant_Association__c records
                    //    (contactId is now populated for newly created
                    //    Contacts too)
                    List<Proposal_Participant_Association__c> ppaListToInsert = new List<Proposal_Participant_Association__c>();

                    for (Integer idx : ppaIndexes) {
                        ParticipantWrapper p = reqBody.participants[idx];
                        if (String.isBlank(p.contactId)) {
                            continue; // still incomplete: no existing Id, and no Account to create one under
                        }
                        ppaListToInsert.add(new Proposal_Participant_Association__c(
                            Proposal__c = proposalRecord.Id,
                            Participant__c = p.contactId,
                            Roles__c = p.role,
                            Stage__c = 'Prelims'
                        ));
                    }

                    if (!ppaListToInsert.isEmpty()) {
                        insert ppaListToInsert;
                        for (Proposal_Participant_Association__c ppa : ppaListToInsert) {
                            ppaIds.add(ppa.Id);
                        }
                    }
                }

                // ---------------------------------------------------
                // BRANCH 2: any role other than Supervisor/Sponsor
                //           -> Additional_Partcipant__c (no Contact involved)
                // ---------------------------------------------------
                if (!additionalIndexes.isEmpty()) {
                    List<Additional_Partcipant__c> additionalListToInsert = new List<Additional_Partcipant__c>();

                    for (Integer idx : additionalIndexes) {
                        ParticipantWrapper p = reqBody.participants[idx];
                        additionalListToInsert.add(new Additional_Partcipant__c(
                            Proposal__c = proposalRecord.Id,
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
                            Stage__c = 'Prelims'
                        ));
                    }

                    insert additionalListToInsert;
                    for (Additional_Partcipant__c ap : additionalListToInsert) {
                        additionalParticipantIds.add(ap.Id);
                    }
                }
            }

            response.success = true;
            response.message = 'Declarations saved and proposal submitted successfully.';
            response.apaId = apaRecord.Id;
            response.proposalId = proposalRecord.Id;
            response.ppaIds = ppaIds;
            response.additionalParticipantIds = additionalParticipantIds;
            response.createdParticipantContactIds = createdParticipantContactIds;


            String sectionName = reqBody.sectionName;

            if (String.isNotBlank(reqBody.sectionName)) { 
                List<Scheme_Section__c> schemeSectionList = [
                    SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c,Application_Stages__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :reqBody.apaId
                    AND Section_Name__c = :reqBody.sectionName
                    AND Application_Stages__c ='Prelims'
                ];

                if (!schemeSectionList.isEmpty()) {
                    schemeSectionList[0].Data_Filled_Successfully__c = true;
                    update schemeSectionList;
                    response.sectionUpdateResult = true;
                } 
                else {
                    response.sectionUpdateResult = false;
                }
            }

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = 'Error saving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class SaveDeclarationRequestWrapper {
        global String apaId;
        global String proposalId;
        global String contactId;
        global String sectionName;
        global Boolean declaration1;
        global Boolean declaration2;
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global String contactId;   // blank/null => create a new Contact (Supervisor/Sponsor branch only)

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
        // If provided, this Account Id is used directly as the new Contact's
        // AccountId. If blank, falls back to the Proposal's resolved Host
        // Account (first Applicant_Host_Association__c, ordered by CreatedDate).
        global String organisationId;
        global Decimal experienceinMonths;
        global Decimal experienceinYears;
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;

        // Additional Participant branch only
        global String organisationName; // free-text Organisation__c
    }

    global class SaveDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global List<Id> ppaIds;
        global List<Id> additionalParticipantIds;
        global List<Id> createdParticipantContactIds;
        public Boolean sectionUpdateResult;
        public Integer sectionsClosedCount;
    }
}
*/






/*@RestResource(urlMapping='/ProposalDeclaration/submit/*')
global without sharing class SaveProposalDeclarationAPI {

    private static final String PROPOSAL_STATUS_DRAFT = 'Draft';
    private static final String REOPEN_STATUS_CLOSED = 'Closed';

    @HttpPost
    global static SaveDeclarationResponseWrapper saveDeclaration() {
        SaveDeclarationResponseWrapper response = new SaveDeclarationResponseWrapper();
        Savepoint sp = Database.setSavepoint();

        try {
            RestRequest req = RestContext.request;
            SaveDeclarationRequestWrapper reqBody =
                (SaveDeclarationRequestWrapper) JSON.deserialize(
                    req.requestBody.toString(), SaveDeclarationRequestWrapper.class
                );

            System.debug('req ====> ' + req);

            // ---- Resolve the APA record (dual-lookup pattern) ----
            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(reqBody.apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :reqBody.apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(reqBody.proposalId) && String.isNotBlank(reqBody.contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :reqBody.proposalId
                    AND Contact__c = :reqBody.contactId
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

            if (apaRecord.Applicant_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Applicant already submitted the Proposal and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = apaRecord.Proposal__c ;
                Database.rollback(sp);
                return response;
            }
            // ---- Update APA declarations ----
            apaRecord.Declaration_1__c = reqBody.declaration1;
            apaRecord.Declaration_2__c = reqBody.declaration2;
            apaRecord.Applicant_Status__c = 'Submitted';
            update apaRecord;

            // ---- Update related Proposal__c ----
            if (apaRecord.Proposal__c == null) {
                response.success = false;
                response.message = 'Applicant Proposal Association is not linked to a Proposal record.';
                Database.rollback(sp);
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id, Proposal_Status__c, Application_Date__c
                FROM Proposal__c
                WHERE Id = :apaRecord.Proposal__c
                LIMIT 1
            ];

            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'Linked Proposal record could not be found.';
                Database.rollback(sp);
                return response;
            }

            Proposal__c proposalRecord = proposalList[0];

            // ---- Idempotency guard: block re-submission ----
            if (proposalRecord.Proposal_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Proposal has already been submitted and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = proposalRecord.Id;
                Database.rollback(sp);
                return response;
            }

            proposalRecord.Proposal_Status__c = 'Submitted';
            proposalRecord.Application_Date__c = Date.today();
            update proposalRecord;

            // ---- Proposal not in Draft -> close out Scheme_Section__c records ----
            // Same condition style as saveOtherGrantsAndApplicationDetails:
            // gate on Proposal_Status__c != 'Draft' rather than closing
            // unconditionally. proposalRecord already reflects the in-memory
            // 'Submitted' value set just above, so no re-query is needed.
            // Bulk-close all Scheme_Section__c records under this APA
            // (Reopen_Status__c = 'Closed'), skipping ones already closed.
            Integer sectionsClosedCount = 0;
            if (proposalRecord.Proposal_Status__c != PROPOSAL_STATUS_DRAFT) {

                List<Scheme_Section__c> sectionsToClose = [
                    SELECT Id, Reopen_Status__c,Application_Stages__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :apaRecord.Id
                    AND Reopen_Status__c != :REOPEN_STATUS_CLOSED AND Section_Name__c = :reqBody.sectionName AND Application_Stages__c ='Prelims'
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

            // ---- Proposal Participant Association creation from selected/new host contacts ----
            List<Id> ppaIds = new List<Id>();
            List<Id> createdParticipantContactIds = new List<Id>();

            if (reqBody.participants != null && !reqBody.participants.isEmpty()) {

                System.debug('reqBody.participants ===> ' + reqBody.participants);

                // 1. Resolve the fallack Host Account for this Proposal.
                //    Only needed if at least one NEW participant (blank contactId)
                //    does NOT explicitly supply organisationId in the payload.
                Boolean needsFallbackHostAccount = false;
                for (ParticipantWrapper p : reqBody.participants) {
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
                        WHERE Proposal__c = :proposalRecord.Id
                        AND Host__c != null
                        ORDER BY CreatedDate ASC
                        LIMIT 1
                    ];
                    if (!ahaList.isEmpty()) {
                        fallbackHostAccountId = ahaList[0].Host__c;
                    }
                }

                // 2. Bulk-create Contacts for participants with a blank contactId.
                //    AccountId = payload's organisationId if provided,
                //    otherwise falls back to the resolved Host Account.
                List<Integer> newContactParticipantIndexes = new List<Integer>();
                List<Contact> newContactsToInsert = new List<Contact>();

                for (Integer i = 0; i < reqBody.participants.size(); i++) {
                    ParticipantWrapper p = reqBody.participants[i];

                    System.debug('p ====> ' + p);

                    if (String.isBlank(p.contactId)) {
                        Id resolvedAccountId = String.isNotBlank(p.organisationId) ? (Id) p.organisationId : fallbackHostAccountId;
                        if (resolvedAccountId == null) {
                            continue; // no organisationId supplied and no Host Account resolvable
                        }
                        
                        System.debug('p.experienceinMonths ==> ' + p.experienceinMonths);
                        System.debug('p.experienceinYears ==> ' + p.experienceinYears);

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
                        con.Research_Experience_After_Viva_Date_Mont__c = p.experienceinMonths;
                        con.Research_Experience_After_Viva_Date_Yrs__c = p.experienceinYears;
                        con.MailingStreet = p.mailingStreet;
                        con.MailingCity = p.mailingCity;
                        con.MailingState = p.mailingState;
                        con.MailingPostalCode = p.mailingPostalCode;
                        con.MailingCountry = p.mailingCountry;
                        newContactsToInsert.add(con);
                        newContactParticipantIndexes.add(i);
                    }
                }

                if (!newContactsToInsert.isEmpty()) {
                    insert newContactsToInsert;
                    System.debug('newContactsToInsert Success');
                    
                    for (Integer k = 0; k < newContactParticipantIndexes.size(); k++) {
                        Integer pIdx = newContactParticipantIndexes[k];
                        reqBody.participants[pIdx].contactId = newContactsToInsert[k].Id;
                        createdParticipantContactIds.add(newContactsToInsert[k].Id);
                    }
                }

                // 3. Build the Proposal_Participant_Association__c records
                //    (contactId is now populated for newly created Contacts too)
                List<Proposal_Participant_Association__c> ppaListToInsert = new List<Proposal_Participant_Association__c>();

                for (ParticipantWrapper participant : reqBody.participants) {
                    if (String.isBlank(participant.contactId)) {
                        continue; // still incomplete: no existing Id, and no Account to create one under
                    }
                    ppaListToInsert.add(new Proposal_Participant_Association__c(
                        Proposal__c = proposalRecord.Id,
                        Participant__c = participant.contactId,
                        Roles__c = participant.role,
                        Stage__c ='Prelims'
                    ));
                }

                if (!ppaListToInsert.isEmpty()) {
                    insert ppaListToInsert;
                    for (Proposal_Participant_Association__c ppa : ppaListToInsert) {
                        ppaIds.add(ppa.Id);
                    }
                }
            }

            response.success = true;
            response.message = 'Declarations saved and proposal submitted successfully.';
            response.apaId = apaRecord.Id;
            response.proposalId = proposalRecord.Id;
            response.ppaIds = ppaIds;
            response.createdParticipantContactIds = createdParticipantContactIds;


            String sectionName = reqBody.sectionName;

            if (String.isNotBlank(reqBody.sectionName)) { 
                List<Scheme_Section__c> schemeSectionList = [
                    SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c,Application_Stages__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :reqBody.apaId
                    AND Section_Name__c = :reqBody.sectionName
                    AND Application_Stages__c ='Prelims'
                ];

                if (!schemeSectionList.isEmpty()) {
                    schemeSectionList[0].Data_Filled_Successfully__c = true;
                    update schemeSectionList;
                    response.sectionUpdateResult = true;
                } 
                else {
                    response.sectionUpdateResult = false;
                }
            }

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = 'Error saving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class SaveDeclarationRequestWrapper {
        global String apaId;
        global String proposalId;
        global String contactId;
        global String sectionName;
        global Boolean declaration1;
        global Boolean declaration2;
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global String contactId;   // blank/null => create a new Contact

        global String role;

        // New-Contact fields (ignored if contactId is provided).
        global String salutation;
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global String email;
        global Date birthdate;
        // If provided, this Account Id is used directly as the new Contact's
        // AccountId. If blank, falls back to the Proposal's resolved Host
        // Account (first Applicant_Host_Association__c, ordered by CreatedDate).
        global String organisationId;
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

    global class SaveDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global List<Id> ppaIds;
        global List<Id> createdParticipantContactIds;
        public Boolean sectionUpdateResult;
        public Integer sectionsClosedCount;
    }
}*/



/*
@RestResource(urlMapping='/ProposalDeclaration/submit/*')
global without sharing class SaveProposalDeclarationAPI {

    @HttpPost
    global static SaveDeclarationResponseWrapper saveDeclaration() {
        SaveDeclarationResponseWrapper response = new SaveDeclarationResponseWrapper();
        Savepoint sp = Database.setSavepoint();

        try {
            RestRequest req = RestContext.request;
            SaveDeclarationRequestWrapper reqBody =
                (SaveDeclarationRequestWrapper) JSON.deserialize(
                    req.requestBody.toString(), SaveDeclarationRequestWrapper.class
                );

            System.debug('req ====> ' + req);

            // ---- Resolve the APA record (dual-lookup pattern) ----
            Applicant_Proposal_Association__c apaRecord;

            if (String.isNotBlank(reqBody.apaId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :reqBody.apaId
                    LIMIT 1
                ];
                if (apaList.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId.';
                    return response;
                }
                apaRecord = apaList[0];

            } else if (String.isNotBlank(reqBody.proposalId) && String.isNotBlank(reqBody.contactId)) {
                List<Applicant_Proposal_Association__c> apaList = [
                    SELECT Id, Declaration_1__c, Declaration_2__c, Proposal__c,Applicant_Status__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :reqBody.proposalId
                    AND Contact__c = :reqBody.contactId
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

            if (apaRecord.Applicant_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Applicant already submitted the Proposal and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = apaRecord.Proposal__c ;
                Database.rollback(sp);
                return response;
            }
            // ---- Update APA declarations ----
            apaRecord.Declaration_1__c = reqBody.declaration1;
            apaRecord.Declaration_2__c = reqBody.declaration2;
            apaRecord.Applicant_Status__c = 'Submitted';
            update apaRecord;

            // ---- Update related Proposal__c ----
            if (apaRecord.Proposal__c == null) {
                response.success = false;
                response.message = 'Applicant Proposal Association is not linked to a Proposal record.';
                Database.rollback(sp);
                return response;
            }

            List<Proposal__c> proposalList = [
                SELECT Id, Proposal_Status__c, Application_Date__c
                FROM Proposal__c
                WHERE Id = :apaRecord.Proposal__c
                LIMIT 1
            ];

            if (proposalList.isEmpty()) {
                response.success = false;
                response.message = 'Linked Proposal record could not be found.';
                Database.rollback(sp);
                return response;
            }

            Proposal__c proposalRecord = proposalList[0];

            // ---- Idempotency guard: block re-submission ----
            if (proposalRecord.Proposal_Status__c == 'Submitted') {
                response.success = false;
                response.message = 'Proposal has already been submitted and cannot be re-submitted.';
                response.apaId = apaRecord.Id;
                response.proposalId = proposalRecord.Id;
                Database.rollback(sp);
                return response;
            }

            proposalRecord.Proposal_Status__c = 'Submitted';
            proposalRecord.Application_Date__c = Date.today();
            update proposalRecord;

            // ---- Proposal Participant Association creation from selected/new host contacts ----
            List<Id> ppaIds = new List<Id>();
            List<Id> createdParticipantContactIds = new List<Id>();

            if (reqBody.participants != null && !reqBody.participants.isEmpty()) {

                System.debug('reqBody.participants ===> ' + reqBody.participants);

                // 1. Resolve the fallack Host Account for this Proposal.
                //    Only needed if at least one NEW participant (blank contactId)
                //    does NOT explicitly supply organisationId in the payload.
                Boolean needsFallbackHostAccount = false;
                for (ParticipantWrapper p : reqBody.participants) {
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
                        WHERE Proposal__c = :proposalRecord.Id
                        AND Host__c != null
                        ORDER BY CreatedDate ASC
                        LIMIT 1
                    ];
                    if (!ahaList.isEmpty()) {
                        fallbackHostAccountId = ahaList[0].Host__c;
                    }
                }

                // 2. Bulk-create Contacts for participants with a blank contactId.
                //    AccountId = payload's organisationId if provided,
                //    otherwise falls back to the resolved Host Account.
                List<Integer> newContactParticipantIndexes = new List<Integer>();
                List<Contact> newContactsToInsert = new List<Contact>();

                for (Integer i = 0; i < reqBody.participants.size(); i++) {
                    ParticipantWrapper p = reqBody.participants[i];

                    System.debug('p ====> ' + p);

                    if (String.isBlank(p.contactId)) {
                        Id resolvedAccountId = String.isNotBlank(p.organisationId) ? (Id) p.organisationId : fallbackHostAccountId;
                        if (resolvedAccountId == null) {
                            continue; // no organisationId supplied and no Host Account resolvable
                        }
                        
                        System.debug('p.experienceinMonths ==> ' + p.experienceinMonths);
                        System.debug('p.experienceinYears ==> ' + p.experienceinYears);

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
                        con.Research_Experience_After_Viva_Date_Mont__c = p.experienceinMonths;
                        con.Research_Experience_After_Viva_Date_Yrs__c = p.experienceinYears;
                        con.MailingStreet = p.mailingStreet;
                        con.MailingCity = p.mailingCity;
                        con.MailingState = p.mailingState;
                        con.MailingPostalCode = p.mailingPostalCode;
                        con.MailingCountry = p.mailingCountry;
                        newContactsToInsert.add(con);
                        newContactParticipantIndexes.add(i);
                    }
                }

                if (!newContactsToInsert.isEmpty()) {
                    insert newContactsToInsert;
                    System.debug('newContactsToInsert Success');
                    
                    for (Integer k = 0; k < newContactParticipantIndexes.size(); k++) {
                        Integer pIdx = newContactParticipantIndexes[k];
                        reqBody.participants[pIdx].contactId = newContactsToInsert[k].Id;
                        createdParticipantContactIds.add(newContactsToInsert[k].Id);
                    }
                }

                // 3. Build the Proposal_Participant_Association__c records
                //    (contactId is now populated for newly created Contacts too)
                List<Proposal_Participant_Association__c> ppaListToInsert = new List<Proposal_Participant_Association__c>();

                for (ParticipantWrapper participant : reqBody.participants) {
                    if (String.isBlank(participant.contactId)) {
                        continue; // still incomplete: no existing Id, and no Account to create one under
                    }
                    ppaListToInsert.add(new Proposal_Participant_Association__c(
                        Proposal__c = proposalRecord.Id,
                        Participant__c = participant.contactId,
                        Roles__c = participant.role,
                        Stage__c ='Prelims'
                    ));
                }

                if (!ppaListToInsert.isEmpty()) {
                    insert ppaListToInsert;
                    for (Proposal_Participant_Association__c ppa : ppaListToInsert) {
                        ppaIds.add(ppa.Id);
                    }
                }
            }

            response.success = true;
            response.message = 'Declarations saved and proposal submitted successfully.';
            response.apaId = apaRecord.Id;
            response.proposalId = proposalRecord.Id;
            response.ppaIds = ppaIds;
            response.createdParticipantContactIds = createdParticipantContactIds;


            String sectionName = reqBody.sectionName;

            if (String.isNotBlank(reqBody.sectionName)) { 
                List<Scheme_Section__c> schemeSectionList = [
                    SELECT Id, Name, Applicant_Proposal_Association__c, Data_Filled_Successfully__c, Section_Name__c
                    FROM Scheme_Section__c
                    WHERE Applicant_Proposal_Association__c = :reqBody.apaId
                    AND Section_Name__c = :reqBody.sectionName
                ];

                if (!schemeSectionList.isEmpty()) {
                    schemeSectionList[0].Data_Filled_Successfully__c = true;
                    update schemeSectionList;
                    response.sectionUpdateResult = true;
                } 
                else {
                    response.sectionUpdateResult = false;
                }
            }

        } catch (Exception ex) {
            Database.rollback(sp);
            response.success = false;
            response.message = 'Error saving declaration: ' + ex.getMessage();
        }

        return response;
    }

    global class SaveDeclarationRequestWrapper {
        global String apaId;
        global String proposalId;
        global String contactId;
        global String sectionName;
        global Boolean declaration1;
        global Boolean declaration2;
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global String contactId;   // blank/null => create a new Contact

        global String role;

        // New-Contact fields (ignored if contactId is provided).
        global String salutation;
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global String email;
        global Date birthdate;
        // If provided, this Account Id is used directly as the new Contact's
        // AccountId. If blank, falls back to the Proposal's resolved Host
        // Account (first Applicant_Host_Association__c, ordered by CreatedDate).
        global String organisationId;
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

    global class SaveDeclarationResponseWrapper {
        global Boolean success;
        global String message;
        global String apaId;
        global String proposalId;
        global List<Id> ppaIds;
        global List<Id> createdParticipantContactIds;
        public Boolean sectionUpdateResult;
    }
}
*/