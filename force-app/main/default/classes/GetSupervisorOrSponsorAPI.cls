/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : GetSupervisorOrSponsorAPI
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

@RestResource(urlMapping='/GetSupervisorOrSponsors/*')
global without sharing class GetSupervisorOrSponsorAPI {

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

            // =========================================================
            // Proposal_Participant_Association__c -> Contact -> Account
            // =========================================================
            List<ParticipantWrapper> participantDetails = new List<ParticipantWrapper>();

            List<Proposal_Participant_Association__c> ppaList = [
                SELECT Id, Participant__c, Roles__c, Relationship_of_current_app_to_Host__c,
                       Added_for_Additional_Role__c, Notify_through_Email__c, Added_for_Full__c,
                       How_will_you_support_Applicant_s_career__c, Document_Uploaded__c, Stage__c,
                       Re_Notify_Count__c, First_Email_Sent_Date_and_Time__c,
                       Share_your_plan_how_you_will_manage__c,
                       Your_present_past_relevant_grants__c,
                       how_application_align__c,
                       Number_of_postdocs_trained_in_your_lab__c,
                       Participant__r.Id,
                       Participant__r.Name,
                       Participant__r.Salutation,
                       Participant__r.FirstName,
                       Participant__r.MiddleName,
                       Participant__r.LastName,
                       Participant__r.Suffix,
                       Participant__r.AccountId,
                       Participant__r.Account.Name,
                       Participant__r.Email,
                       Participant__r.Birthdate,
                       Participant__r.Department,
                       Participant__r.Gender__c,
                       Participant__r.Nationality__c,
                       Participant__r.Position__c,
                       Participant__r.Phone,
                       Participant__r.Title__c,
                       Participant__r.MailingStreet,
                       Participant__r.MailingCity,
                       Participant__r.MailingState,
                       Participant__r.MailingPostalCode,
                       Participant__r.MailingCountry
                FROM Proposal_Participant_Association__c
                WHERE Proposal__c = :resolvedProposalId
                AND Participant__c != null
            ];

            for (Proposal_Participant_Association__c ppa : ppaList) {
                ParticipantWrapper pw = new ParticipantWrapper();

                // PPA fields
                pw.ppaId = ppa.Id;
                pw.role = ppa.Roles__c;
                pw.notifyThroughEmailForPPA = ppa.Notify_through_Email__c;
                pw.partcipantAddedForFull = ppa.Added_for_Full__c;
                pw.relationshipOfCurrentApplicant = ppa.Relationship_of_current_app_to_Host__c;
                pw.addedForAdditionalRoleInPPA = ppa.Added_for_Additional_Role__c;
                pw.howWillYouSupportApplicantsCareer = ppa.How_will_you_support_Applicant_s_career__c;
                pw.documentUploadStatus = ppa.Document_Uploaded__c;
                pw.stage = ppa.Stage__c;
                pw.reNotifyCountForPPA = ppa.Re_Notify_Count__c;
                pw.firstEmailSentDateTimeForPPA = ppa.First_Email_Sent_Date_and_Time__c != null
                    ? ppa.First_Email_Sent_Date_and_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
                    : null;
                pw.shareYourPlanHowYouWillManage = ppa.Share_your_plan_how_you_will_manage__c;
                pw.yourPresentPastRelevantGrants = ppa.Your_present_past_relevant_grants__c;
                pw.howApplicationAlign = ppa.how_application_align__c;
                pw.numberOfPostdocsTrainedInYourLab = ppa.Number_of_postdocs_trained_in_your_lab__c;

                // Contact fields (via Participant__r)
                if (ppa.Participant__r != null) {
                    pw.contactId = ppa.Participant__r.Id;
                    pw.name = ppa.Participant__r.Name;
                    pw.salutation = ppa.Participant__r.Salutation;
                    pw.firstName = ppa.Participant__r.FirstName;
                    pw.middleName = ppa.Participant__r.MiddleName;
                    pw.lastName = ppa.Participant__r.LastName;
                    pw.suffix = ppa.Participant__r.Suffix;
                    pw.email = ppa.Participant__r.Email;
                    pw.birthdate = ppa.Participant__r.Birthdate;
                    pw.department = ppa.Participant__r.Department;
                    pw.gender = ppa.Participant__r.Gender__c;
                    pw.nationality = ppa.Participant__r.Nationality__c;
                    pw.currentPosition = ppa.Participant__r.Position__c;
                    pw.telePhone = ppa.Participant__r.Phone;
                    pw.title = ppa.Participant__r.Title__c;
                    pw.mailingStreet = ppa.Participant__r.MailingStreet;
                    pw.mailingCity = ppa.Participant__r.MailingCity;
                    pw.mailingState = ppa.Participant__r.MailingState;
                    pw.mailingPostalCode = ppa.Participant__r.MailingPostalCode;
                    pw.mailingCountry = ppa.Participant__r.MailingCountry;

                    // Account fields (via Participant__r.Account)
                    pw.accountId = ppa.Participant__r.AccountId;
                    pw.organisation = ppa.Participant__r.Account != null
                        ? ppa.Participant__r.Account.Name
                        : null;
                }

                participantDetails.add(pw);
            }

            response.participants = participantDetails;
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
        global List<ParticipantWrapper> participants;
    }

    global class ParticipantWrapper {
        global Id ppaId;
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
        global String title;
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
        global Decimal reNotifyCountForPPA;
        global String firstEmailSentDateTimeForPPA;
        global String shareYourPlanHowYouWillManage;
        global String yourPresentPastRelevantGrants;
        global String howApplicationAlign;
        global Decimal numberOfPostdocsTrainedInYourLab;
    }
}