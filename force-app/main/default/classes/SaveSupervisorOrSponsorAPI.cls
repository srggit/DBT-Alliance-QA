/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : SaveSupervisorOrSponsorAPI
 * Author          : <YourName>
 * Created Date    : Sep 26, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Sep 26, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Sep 26, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@RestResource(urlMapping='/SaveSupervisorOrSponsors/*')
global without sharing class SaveSupervisorOrSponsorAPI {

    @HttpPost
    global static SaveParticipantResponseWrapper saveParticipants(List<ParticipantSaveWrapper> participants) {
        SaveParticipantResponseWrapper response = new SaveParticipantResponseWrapper();
        response.results = new List<SaveResultWrapper>();

        try {
            if (participants == null || participants.isEmpty()) {
                response.success = false;
                response.message = 'No participant data provided.';
                return response;
            }

            // ---- Collect all ppaIds from the payload ----
            Set<Id> ppaIds = new Set<Id>();
            for (ParticipantSaveWrapper pw : participants) {
                if (pw.ppaId != null) {
                    ppaIds.add(pw.ppaId);
                }
            }

            // ---- Fetch PPA -> Participant__c (Contact) in one query ----
            Map<Id, Proposal_Participant_Association__c> ppaMap = new Map<Id, Proposal_Participant_Association__c>();
            if (!ppaIds.isEmpty()) {
                ppaMap = new Map<Id, Proposal_Participant_Association__c>([
                    SELECT Id, Participant__c
                    FROM Proposal_Participant_Association__c
                    WHERE Id IN :ppaIds
                ]);
            }

            List<Contact> contactsToUpdate = new List<Contact>();
            List<Proposal_Participant_Association__c> ppasToUpdate = new List<Proposal_Participant_Association__c>();

            for (ParticipantSaveWrapper pw : participants) {

                if (pw.ppaId == null) {
                    continue; // ppaId is now mandatory since contactId is derived from it
                }

                Proposal_Participant_Association__c existingPpa = ppaMap.get(pw.ppaId);
                if (existingPpa == null) {
                    // ppaId sent by client doesn't exist in the org
                    SaveResultWrapper rw = new SaveResultWrapper();
                    rw.recordId = pw.ppaId;
                    rw.recordType = 'Proposal_Participant_Association__c';
                    rw.success = false;
                    rw.errorMessage = 'No Proposal_Participant_Association__c found for this Id.';
                    response.results.add(rw);
                    continue;
                }

                Id resolvedContactId = existingPpa.Participant__c;

                // ---- Contact update (contactId resolved from PPA, not client input) ----
                if (resolvedContactId != null) {
                    Contact con = new Contact(Id = resolvedContactId);
                    Boolean hasContactChange = false;

                    if (pw.salutation != null)        { con.Salutation = pw.salutation; hasContactChange = true; }
                    if (pw.firstName != null)          { con.FirstName = pw.firstName; hasContactChange = true; }
                    if (pw.middleName != null)         { con.MiddleName = pw.middleName; hasContactChange = true; }
                    if (pw.lastName != null)           { con.LastName = pw.lastName; hasContactChange = true; }
                    if (pw.suffix != null)             { con.Suffix = pw.suffix; hasContactChange = true; }
                    if (pw.email != null)              { con.Email = pw.email; hasContactChange = true; }
                    if (pw.birthdate != null)          { con.Birthdate = pw.birthdate; hasContactChange = true; }
                    if (pw.department != null)         { con.Department = pw.department; hasContactChange = true; }
                    if (pw.gender != null)             { con.Gender__c = pw.gender; hasContactChange = true; }
                    if (pw.nationality != null)        { con.Nationality__c = pw.nationality; hasContactChange = true; }
                    if (pw.currentPosition != null)    { con.Position__c = pw.currentPosition; hasContactChange = true; }
                    if (pw.telePhone != null)          { con.Phone = pw.telePhone; hasContactChange = true; }
                    if (pw.title != null)              { con.Title__c = pw.title; hasContactChange = true; }
                    if (pw.mailingStreet != null)      { con.MailingStreet = pw.mailingStreet; hasContactChange = true; }
                    if (pw.mailingCity != null)        { con.MailingCity = pw.mailingCity; hasContactChange = true; }
                    if (pw.mailingState != null)       { con.MailingState = pw.mailingState; hasContactChange = true; }
                    if (pw.mailingPostalCode != null)  { con.MailingPostalCode = pw.mailingPostalCode; hasContactChange = true; }
                    if (pw.mailingCountry != null)     { con.MailingCountry = pw.mailingCountry; hasContactChange = true; }

                    if (hasContactChange) {
                        contactsToUpdate.add(con);
                    }
                }

                // ---- PPA update ----
                Proposal_Participant_Association__c ppa = new Proposal_Participant_Association__c(Id = pw.ppaId);
                Boolean hasPpaChange = false;

                if (pw.role != null)                              { ppa.Roles__c = pw.role; hasPpaChange = true; }
                if (pw.relationshipOfCurrentApplicant != null)     { ppa.Relationship_of_current_app_to_Host__c = pw.relationshipOfCurrentApplicant; hasPpaChange = true; }
                if (pw.addedForAdditionalRoleInPPA != null)        { ppa.Added_for_Additional_Role__c = pw.addedForAdditionalRoleInPPA; hasPpaChange = true; }
                if (pw.notifyThroughEmailForPPA != null)           { ppa.Notify_through_Email__c = pw.notifyThroughEmailForPPA; hasPpaChange = true; }
                if (pw.partcipantAddedForFull != null)             { ppa.Added_for_Full__c = pw.partcipantAddedForFull; hasPpaChange = true; }
                if (pw.howWillYouSupportApplicantsCareer != null)  { ppa.How_will_you_support_Applicant_s_career__c = pw.howWillYouSupportApplicantsCareer; hasPpaChange = true; }
                if (pw.documentUploadStatus != null)               { ppa.Document_Uploaded__c = pw.documentUploadStatus; hasPpaChange = true; }
                if (pw.stage != null)                              { ppa.Stage__c = pw.stage; hasPpaChange = true; }
                if (pw.shareYourPlanHowYouWillManage != null)      { ppa.Share_your_plan_how_you_will_manage__c = pw.shareYourPlanHowYouWillManage; hasPpaChange = true; }
                if (pw.yourPresentPastRelevantGrants != null)      { ppa.Your_present_past_relevant_grants__c = pw.yourPresentPastRelevantGrants; hasPpaChange = true; }
                if (pw.howApplicationAlign != null)                { ppa.how_application_align__c = pw.howApplicationAlign; hasPpaChange = true; }
                if (pw.numberOfPostdocsTrainedInYourLab != null)   { ppa.Number_of_postdocs_trained_in_your_lab__c = pw.numberOfPostdocsTrainedInYourLab; hasPpaChange = true; }

                if (hasPpaChange) {
                    ppasToUpdate.add(ppa);
                }
            }

            // ---- DML: Contact updates ----
            if (!contactsToUpdate.isEmpty()) {
                List<Database.SaveResult> contactResults = Database.update(contactsToUpdate, false);
                for (Integer i = 0; i < contactResults.size(); i++) {
                    Database.SaveResult sr = contactResults[i];
                    SaveResultWrapper rw = new SaveResultWrapper();
                    rw.recordId = contactsToUpdate[i].Id;
                    rw.recordType = 'Contact';
                    rw.success = sr.isSuccess();
                    if (!sr.isSuccess()) {
                        rw.errorMessage = sr.getErrors()[0].getMessage();
                    }
                    response.results.add(rw);
                }
            }

            // ---- DML: PPA updates ----
            if (!ppasToUpdate.isEmpty()) {
                List<Database.SaveResult> ppaResults = Database.update(ppasToUpdate, false);
                for (Integer i = 0; i < ppaResults.size(); i++) {
                    Database.SaveResult sr = ppaResults[i];
                    SaveResultWrapper rw = new SaveResultWrapper();
                    rw.recordId = ppasToUpdate[i].Id;
                    rw.recordType = 'Proposal_Participant_Association__c';
                    rw.success = sr.isSuccess();
                    if (!sr.isSuccess()) {
                        rw.errorMessage = sr.getErrors()[0].getMessage();
                    }
                    response.results.add(rw);
                }
            }

            response.success = true;
            for (SaveResultWrapper rw : response.results) {
                if (!rw.success) {
                    response.success = false;
                    break;
                }
            }
            response.message = response.success
                ? 'All records saved successfully.'
                : 'One or more records failed to save. See results for details.';

        } catch (Exception ex) {
            response.success = false;
            response.message = 'Error saving participants: ' + ex.getMessage();
        }

        return response;
    }

    global class ParticipantSaveWrapper {
        global Id ppaId;   // mandatory now — contactId is resolved from this

        // Contact fields
        global String salutation;
        global String firstName;
        global String middleName;
        global String lastName;
        global String suffix;
        global String email;
        global Date birthdate;
        global String department;
        global String gender;
        global String nationality;
        global String currentPosition;
        global String telePhone;
        global String title;
        global String mailingStreet;
        global String mailingCity;
        global String mailingState;
        global String mailingPostalCode;
        global String mailingCountry;

        // PPA fields
        global String role;
        global String relationshipOfCurrentApplicant;
        global Boolean partcipantAddedForFull;
        global Boolean addedForAdditionalRoleInPPA;
        global Boolean notifyThroughEmailForPPA;
        global String howWillYouSupportApplicantsCareer;
        global Boolean documentUploadStatus;
        global String stage;
        global String shareYourPlanHowYouWillManage;
        global String yourPresentPastRelevantGrants;
        global String howApplicationAlign;
        global Decimal numberOfPostdocsTrainedInYourLab;
    }

    global class SaveResultWrapper {
        global Id recordId;
        global String recordType;
        global Boolean success;
        global String errorMessage;
    }

    global class SaveParticipantResponseWrapper {
        global Boolean success;
        global String message;
        global List<SaveResultWrapper> results;
    }
}