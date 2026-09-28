public without sharing class EmailNotificationQueueable implements Queueable, Database.AllowsCallouts {

    private static final String JOB_WOHI_COLLABORATION  = 'WOHI_COLLABORATION';
    private static final String JOB_REFEREE             = 'REFEREE';
    private static final String REFEREE_CON				= 'CONREFEREE';
    private static final String JOB_CONTACT_WELCOME     = 'CONTACT_WELCOME';
    private static final String JOB_OTP_VERIFICATION    = 'OTP_VERIFICATION';
    private static final String JOB_REVIEWER_ASSIGNMENT = 'REVIEWER_ASSIGNMENT';
    private static final String JOB_PROPOSAL_PARTICIPANT_HOST = 'PROPOSAL_PARTICIPANT_HOST';
    private static final String JOB_FULL_APPLICATION_ELIGIBLE = 'FULL_APPLICATION_ELIGIBLE';
    private static final String JOB_REVIEWER_MAPPING_APPROVED = 'REVIEWER_MAPPING_APPROVED';

    // Literal placeholder token the New_Proposal_Assignment template's "Proceed to Portal"
    // link uses (both HTML href and plain-text fallback) - matching this fixed token, rather
    // than reconstructing the literal URL the template happens to hardcode, keeps this working
    // regardless of what URL_s__mdt.React_Site_Link resolves to or whether the template's own
    // hardcoded domain drifts out of sync with it (exactly what caused the link to go out
    // unreplaced/dataless before this fix).
    private static final String REVIEWER_REGISTER_URL_PLACEHOLDER = '{!templateUrl}';

    private String jobType;
    private String templateDeveloperName;

    private List<Id> recordIds;
    private Map<Id, String> invitationLinks;

    public EmailNotificationQueueable(
        String jobType,
        List<Id> recordIds,
        Map<Id, String> invitationLinks,
        String templateDeveloperName
    ) {
        this.jobType = jobType;
        this.recordIds = recordIds;
        this.invitationLinks = invitationLinks;
        this.templateDeveloperName = templateDeveloperName;
    }

    public EmailNotificationQueueable(
        String jobType,
        List<Id> recordIds
    ) {
        this.jobType = jobType;
        this.recordIds = recordIds;
        this.invitationLinks = new Map<Id, String>();
        this.templateDeveloperName = null;
    }

    /*
     * ============================================================
     * Constructor for Contact Welcome Email
     * ============================================================
     */
    public EmailNotificationQueueable(
        String jobType,
        List<Id> contactIds,
        String templateDeveloperName
    ) {
        this.jobType = jobType;
        this.recordIds = contactIds;
        this.templateDeveloperName = templateDeveloperName;
        this.invitationLinks = new Map<Id, String>();
    }

    /*
     * ============================================================
     * EXECUTE
     * ============================================================
     */
    public void execute(QueueableContext context) {

        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }

        if (jobType == JOB_WOHI_COLLABORATION) {
            processWOHICollaboration();
        } else if (jobType == JOB_REFEREE) {
            processReferee();
        } else if (jobType == JOB_CONTACT_WELCOME) {
            processContactWelcome();
        } else if (jobType == JOB_OTP_VERIFICATION) {
            processOTPVerification();
        } else if (jobType == JOB_REVIEWER_ASSIGNMENT) {
            processReviewerAssignment();
        } else if (jobType == REFEREE_CON) {
           processContactReferee();

        } else if (jobType == JOB_PROPOSAL_PARTICIPANT_HOST) {
            processProposalParticipantHost();
        } else if (jobType == JOB_FULL_APPLICATION_ELIGIBLE) {
            processFullApplicationEligible();
        } else if (jobType == JOB_REVIEWER_MAPPING_APPROVED) {
            processReviewerMappingApproved();
        } else {
            System.debug('Unknown EmailNotificationQueueable Job Type: ' + jobType);
        }
    }

    /*
     * ============================================================
     * WOHI COLLABORATION
     * ============================================================
     */
    private void processWOHICollaboration() {

        List<WOHI_Collaboration__c> records = [
            SELECT Id,
                   Title__c,
                   FirstName__c,
                   Applicant_Proposal_Association__r.Proposal__r.Proposal_Id__c,
                   Applicant_Proposal_Association__r.Yearly_Scheme__r.Scheme__c,
                   Applicant_Proposal_Association__r.Contact__r.Title,
                   Applicant_Proposal_Association__r.Contact__r.FirstName,
                   Applicant_Proposal_Association__r.Contact__r.LastName,
                   Applicant_Proposal_Association__r.Contact__c,
                   Last_Name__c,
                   Organisation__c,
                   Email__c,
                   Type__c
            FROM WOHI_Collaboration__c
            WHERE Id IN :recordIds
        ];
        List<Notification__c>notificationCon = new List<Notification__c>();
        

        List<WOHI_Collaboration__c> recordsToUpdate = new List<WOHI_Collaboration__c>();

        for (WOHI_Collaboration__c wc : records) {

            if (String.isBlank(wc.Email__c)) {
                continue;
            }
            Notification__c nc = new Notification__c();
            String title = String.isBlank(wc.Title__c) ? '' : wc.Title__c + ' ';
            String firstName = String.isBlank(wc.FirstName__c) ? '' : wc.FirstName__c + ' ';
            String lastName = String.isBlank(wc.Last_Name__c) ? '' : wc.Last_Name__c + ' ';
            String type = String.isBlank(wc.Type__c) ? '' : wc.Type__c + ' ';
            nc.Title__c = type +' Assigned';
            nc.Description__c = title + firstName + lastName +' '+ type + ' Assigned';
            nc.Expiry_Date__c = system.today().addDays(10);
            nc.Contact__c = wc.Applicant_Proposal_Association__r.Contact__c;
            notificationCon.add(nc);
            

            String invitationLink = invitationLinks.get(wc.Id);

            Map<String, String> mergeValues = new Map<String, String>{
                'Title'          => wc.Title__c,
                'FirstName'      => wc.FirstName__c,
                'LastName'       => wc.Last_Name__c,
                'Type'           => String.isNotBlank(wc.Type__c) ? wc.Type__c : '',
                'ConTitle'       => wc.Applicant_Proposal_Association__r.Contact__r.Title,
                'ConFirstName'   => wc.Applicant_Proposal_Association__r.Contact__r.FirstName,
                'ConLastName'    => wc.Applicant_Proposal_Association__r.Contact__r.LastName,
                'SchemeName'     => wc.Applicant_Proposal_Association__r.Yearly_Scheme__r.Scheme__c,
                'ProposalId'     => wc.Applicant_Proposal_Association__r.Proposal__r.Proposal_Id__c,
                'Organisation'   => wc.Organisation__c,
                'Email'          => wc.Email__c,
                'InvitationLink' => invitationLink
            };

            System.debug('WOHI Merge Values ==> ' + mergeValues);

            Boolean emailSent = false;

            try {
                HttpResponse response = SESService.sendEmail(wc.Email__c, templateDeveloperName, mergeValues);

                if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    emailSent = true;
                    System.debug(
                        'WOHI invitation email sent successfully. ' +
                        'Record Id: ' + wc.Id +
                        ', Email: ' + wc.Email__c +
                        ', Status: ' + response.getStatusCode()
                    );
                } else {
                    System.debug(
                        'WOHI invitation email failed. ' +
                        'Record Id: ' + wc.Id +
                        ', Email: ' + wc.Email__c +
                        ', Status: ' + (response == null ? 'NULL' : String.valueOf(response.getStatusCode())) +
                        ', Body: ' + (response == null ? '' : response.getBody())
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    'WOHI invitation email exception. ' +
                    'Record Id: ' + wc.Id +
                    ', Email: ' + wc.Email__c +
                    ', Error: ' + ex.getMessage()
                );
            }

            recordsToUpdate.add(
                new WOHI_Collaboration__c(
                    Id = wc.Id,
                    Invitation_Link__c = invitationLink,
                    Notified__c = emailSent
                )
            );
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
        if(!notificationCon.isEmpty()){
            insert notificationCon;
        }
    }

    /*
     * ============================================================
     * REFEREE
     * ============================================================
     */
    private void processReferee() {

        List<Additional_Partcipant__c> records = [
            SELECT Id,
                   Title__c,
                   First_Name__c,
                   Proposal__r.Proposal_Id__c,
                   Proposal__r.Yearly_Scheme__r.Scheme__c,
                   Last_Name__c,
                   Organisation__c,
                   Email__c,
                   Roles__c,
                   Email_Sent__c
            FROM Additional_Partcipant__c
            WHERE Id IN :recordIds
        ];

        List<Additional_Partcipant__c> recordsToUpdate = new List<Additional_Partcipant__c>();
         Map<Id, Applicant_Proposal_Association__c> applicantByProposal = new Map<Id, Applicant_Proposal_Association__c>();
        Set<Id> proposalIds = new Set<Id>();
        for (Additional_Partcipant__c referee : records) {
            if (referee.Proposal__c != null) {
                proposalIds.add(referee.Proposal__c);
            }
        }
        if (!proposalIds.isEmpty()) {
            for (Applicant_Proposal_Association__c apa : [
                SELECT Id,
                       Proposal__c,
                       Contact__c,
                       Contact__r.Title__c,
                       Contact__r.Salutation,
                       Contact__r.FirstName,
                       Contact__r.LastName,
                       Contact__r.Email
                FROM Applicant_Proposal_Association__c
                WHERE Proposal__c IN :proposalIds
            ]) {
                if (!applicantByProposal.containsKey(apa.Proposal__c)) {
                    applicantByProposal.put(
                        apa.Proposal__c,
                        apa
                    );
                }
            }
        }
        
        
        // List<Notification__c> notiContact = new List<Notification__c>();
        // Notification__c creation for Referee/Mentor disabled per request.
        // for (Additional_Partcipant__c referee : records) {
        //      Applicant_Proposal_Association__c applicantAssociation = applicantByProposal.get(referee.Proposal__c);
        //      Contact contact = applicantAssociation.Contact__r;
        //     String title = String.isBlank(referee.Title__c) ? '' : referee.Title__c + ' ';
        //     String firstName = String.isBlank(referee.First_Name__c) ? '' : referee.First_Name__c + ' ';
        //     String lastName = String.isBlank(referee.Last_Name__c) ? '' : referee.Last_Name__c + ' ';
        //     Notification__c nc = new Notification__c();
        //     nc.Contact__c = applicantAssociation.Contact__c;
        //     nc.Expiry_Date__c = system.today().addDays(10);
        //     nc.Title__c ='Participant Assigned';
        //     nc.Description__c =title + firstName + lastName+ ' ' +referee.Roles__c +' has been assigned to you.';
        //     notiContact.add(nc);

        // }
       
                

        for (Additional_Partcipant__c ap : records) {

            if (String.isBlank(ap.Email__c)) {
                continue;
            }
            

            String invitationLink = invitationLinks.get(ap.Id);

            Map<String, String> mergeValues = new Map<String, String>{
                'Title'          => ap.Title__c,
                'FirstName'      => ap.First_Name__c,
                'LastName'       => ap.Last_Name__c,
                'SchemeName'     => ap.Proposal__r.Yearly_Scheme__r.Scheme__c,
                'ProposalId'     => ap.Proposal__r.Proposal_Id__c,
                'Organisation'   => ap.Organisation__c,
                'Email'          => ap.Email__c,
                'InvitationLink' => invitationLink
            };

            System.debug('Referee Merge Values ==> ' + mergeValues);

            Boolean emailSent = false;

            try {
                HttpResponse response = SESService.sendEmail(ap.Email__c, templateDeveloperName, mergeValues);

                if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    emailSent = true;
                    System.debug(
                        'Referee invitation email sent successfully. ' +
                        'Record Id: ' + ap.Id +
                        ', Email: ' + ap.Email__c +
                        ', Status: ' + response.getStatusCode()
                    );
                } else {
                    System.debug(
                        'Referee invitation email failed. ' +
                        'Record Id: ' + ap.Id +
                        ', Email: ' + ap.Email__c +
                        ', Status: ' + (response == null ? 'NULL' : String.valueOf(response.getStatusCode())) +
                        ', Body: ' + (response == null ? '' : response.getBody())
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    'Referee invitation email exception. ' +
                    'Record Id: ' + ap.Id +
                    ', Email: ' + ap.Email__c +
                    ', Error: ' + ex.getMessage()
                );
            }

            recordsToUpdate.add(
                new Additional_Partcipant__c(
                    Id = ap.Id,
                    Email_Sent__c = emailSent,
                    Invitation_Link__c = invitationLink
                )
            );
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
        // if(!notiContact.isEmpty()){
        //     Insert notiContact;
        // }
    }

    /*
     * ============================================================
     * CONTACT WELCOME EMAIL
     * ============================================================
     */
    private void processContactWelcome() {

        List<Contact> contacts = [
            SELECT Id,
                   Salutation,
                   Title__c,
                   FirstName,
                   LastName,
                   Email
            FROM Contact
            WHERE Id IN :recordIds
        ];

        for (Contact con : contacts) {

            if (String.isBlank(con.Email)) {
                continue;
            }

            Map<String, String> mergeValues = new Map<String, String>{
                'Applicant_Name'  => buildApplicantName(con),
                'Applicant_Email' => con.Email
            };

            System.debug('Contact Welcome Merge Values ==> ' + mergeValues);

            try {
                HttpResponse response = SESService.sendEmail(con.Email, templateDeveloperName, mergeValues);

                if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    System.debug(
                        'Contact welcome email sent successfully. ' +
                        'Contact Id: ' + con.Id +
                        ', Email: ' + con.Email +
                        ', Status: ' + response.getStatusCode()
                    );
                } else {
                    System.debug(
                        'Contact welcome email failed. ' +
                        'Contact Id: ' + con.Id +
                        ', Email: ' + con.Email +
                        ', Status: ' + (response == null ? 'NULL' : String.valueOf(response.getStatusCode())) +
                        ', Body: ' + (response == null ? '' : response.getBody())
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    'Contact welcome email exception. ' +
                    'Contact Id: ' + con.Id +
                    ', Email: ' + con.Email +
                    ', Error: ' + ex.getMessage()
                );
            }
        }
    }

    /*
     * ============================================================
     * BUILD CONTACT/APPLICANT NAME
     * ============================================================
     */
    private static String buildApplicantName(Contact con) {

        List<String> nameParts = new List<String>();

        String titleValue;

        if (String.isNotBlank(con.Salutation)) {
            titleValue = con.Salutation;
        } else if (String.isNotBlank(con.Title__c)) {
            titleValue = con.Title__c;
        }

        if (String.isNotBlank(titleValue)) {
            nameParts.add(titleValue);
        }

        if (String.isNotBlank(con.FirstName)) {
            nameParts.add(con.FirstName);
        }

        if (String.isNotBlank(con.LastName)) {
            nameParts.add(con.LastName);
        }

        return String.join(nameParts, ' ');
    }

    /*
     * ============================================================
     * OTP VERIFICATION
     * ============================================================
     */
    private void processOTPVerification() {

        List<OTP_Verification__c> otpRecords = [
            SELECT Id,
                   OTP__c,
                   Valid__c,
                   Email__c
            FROM OTP_Verification__c
            WHERE Id IN :recordIds
        ];

        for (OTP_Verification__c otpRec : otpRecords) {

            if (String.isBlank(otpRec.Email__c)) {
                continue;
            }

            Map<String, String> mergeValues = new Map<String, String>{
                'otpVerification' => String.valueOf(otpRec.OTP__c)
            };

            System.debug('OTP Email Merge Values ==> ' + mergeValues);

            try {
                HttpResponse response = SESService.sendEmail(otpRec.Email__c, templateDeveloperName, mergeValues);

                if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    System.debug(
                        'OTP email sent successfully. ' +
                        'OTP Verification Id: ' + otpRec.Id +
                        ', Email: ' + otpRec.Email__c +
                        ', Status: ' + response.getStatusCode()
                    );
                } else {
                    System.debug(
                        'OTP email failed. ' +
                        'OTP Verification Id: ' + otpRec.Id +
                        ', Email: ' + otpRec.Email__c +
                        ', Status: ' + (response == null ? 'NULL' : String.valueOf(response.getStatusCode())) +
                        ', Body: ' + (response == null ? '' : response.getBody())
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    'OTP email exception. ' +
                    'OTP Verification Id: ' + otpRec.Id +
                    ', Email: ' + otpRec.Email__c +
                    ', Error: ' + ex.getMessage()
                );
            }
        }
    }

    /*
     * ============================================================
     * REVIEWER ASSIGNMENT
     * ============================================================
     */
    private void processReviewerAssignment() {

        /*
         * --------------------------------------------------------
         * GET URLS
         * --------------------------------------------------------
         */

        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');

        String reactBaseUrl =
            (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c))
                ? reactSiteLink.URL_Value__c
                : '';

        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }

        String baseURL     = reactBaseUrl + 'reviewer_register_verifyemail';
        String loginURL    = reactBaseUrl + 'login';
        String templateUrl = reactBaseUrl + 'reviewer_register';

        /*
         * --------------------------------------------------------
         * GET REVIEWER MAPPINGS
         * --------------------------------------------------------
         */

        List<Reviewer_Mapping__c> mappings = [
            SELECT Id,
                   Reviewer__c,
                   Reviewer__r.Id,
                   Reviewer__r.Email_Address__c,
                   Reviewer__r.Title__c,
                   Reviewer__r.First_Name__c,
                   Reviewer__r.Last_Name__c,
                   Reviewer__r.Firebase_UID__c,
                   Reviewer__r.Reviewer_Type__c,
                   Proposal__c,
                   Proposal__r.Proposal_Id__c,
                   Proposal__r.Application_Stages__c,
                   Proposal__r.Project_Title__c,
                   Proposal__r.Abstract_of_proposed_work__c,
                   Scheme_Name__c,
                   Reviewer_Type__c,
                   Deadline_Date__c
            FROM Reviewer_Mapping__c
            WHERE Id IN :recordIds
        ];

        if (mappings.isEmpty()) {
            return;
        }

        /*
         * --------------------------------------------------------
         * COLLECT PROPOSAL IDS
         * --------------------------------------------------------
         */

        Set<Id> proposalIds = new Set<Id>();

        for (Reviewer_Mapping__c mapping : mappings) {
            if (mapping.Proposal__c != null) {
                proposalIds.add(mapping.Proposal__c);
            }
        }

        /*
         * --------------------------------------------------------
         * APPLICANT ASSOCIATION
         * --------------------------------------------------------
         */

        Map<Id, Applicant_Proposal_Association__c> applicantByProposal =
            new Map<Id, Applicant_Proposal_Association__c>();

        if (!proposalIds.isEmpty()) {
            for (
                Applicant_Proposal_Association__c apa : [
                    SELECT Proposal__c,
                           Contact__r.Title__c,
                           Contact__r.Salutation,
                           Contact__r.FirstName,
                           Contact__r.LastName
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c IN :proposalIds
                ]
            ) {
                if (!applicantByProposal.containsKey(apa.Proposal__c)) {
                    applicantByProposal.put(apa.Proposal__c, apa);
                }
            }
        }

        /*
         * --------------------------------------------------------
         * HOST ASSOCIATION
         * --------------------------------------------------------
         */

        Map<Id, Applicant_Host_Association__c> hostByProposal =
            new Map<Id, Applicant_Host_Association__c>();

        if (!proposalIds.isEmpty()) {
            for (
                Applicant_Host_Association__c aha : [
                    SELECT Proposal__c,
                           Host__r.Name
                    FROM Applicant_Host_Association__c
                    WHERE Proposal__c IN :proposalIds
                ]
            ) {
                if (!hostByProposal.containsKey(aha.Proposal__c)) {
                    hostByProposal.put(aha.Proposal__c, aha);
                }
            }
        }

        /*
         * --------------------------------------------------------
         * PROCESS EACH REVIEWER MAPPING
         * --------------------------------------------------------
         */

        for (Reviewer_Mapping__c mapping : mappings) {

            if (mapping.Reviewer__r == null || String.isBlank(mapping.Reviewer__r.Email_Address__c)) {
                continue;
            }

            /*
             * ----------------------------------------------------
             * PROPOSAL STAGE / REVIEWER TYPE VALIDATION
             * ----------------------------------------------------
             */

            String proposalStage = mapping.Proposal__r.Application_Stages__c;

            String expectedTypeForStage =
                (proposalStage == 'Prelims') ? 'Ex-Grantee' :
                (proposalStage == 'Full')    ? 'Peer' :
                null;

            if (
                String.isNotBlank(expectedTypeForStage) &&
                mapping.Reviewer__r.Reviewer_Type__c != expectedTypeForStage
            ) {
                System.debug(
                    'Skipping reviewer email - Reviewer type mismatch. ' +
                    'Stage: ' + proposalStage +
                    ', Reviewer Type: ' + mapping.Reviewer__r.Reviewer_Type__c
                );
                continue;
            }

            /*
             * ----------------------------------------------------
             * SELECT TEMPLATE
             * ----------------------------------------------------
             */

            String selectedTemplate = (proposalStage == 'Full')
                ? 'X19ReviewInvitation'
                : 'New_Proposal_Assignment';

            /*
             * ----------------------------------------------------
             * REVIEWER VALUES
             * ----------------------------------------------------
             */

            String reviewerId       = mapping.Reviewer__r.Id == null ? '' : String.valueOf(mapping.Reviewer__r.Id);
            String title            = mapping.Reviewer__r.Title__c == null ? '' : mapping.Reviewer__r.Title__c;
            String firstName        = mapping.Reviewer__r.First_Name__c == null ? '' : mapping.Reviewer__r.First_Name__c;
            String lastName         = mapping.Reviewer__r.Last_Name__c == null ? '' : mapping.Reviewer__r.Last_Name__c;
            String emailAddress     = mapping.Reviewer__r.Email_Address__c;
            String reviewerType     = mapping.Reviewer_Type__c == null ? '' : mapping.Reviewer_Type__c;
            String proposalIdText   = mapping.Proposal__r.Proposal_Id__c == null ? '' : mapping.Proposal__r.Proposal_Id__c;
            String schemeName       = mapping.Scheme_Name__c == null ? '' : mapping.Scheme_Name__c;
            String deadlineDate     = mapping.Deadline_Date__c == null ? '' : String.valueOf(mapping.Deadline_Date__c);
            String projectTitle     = mapping.Proposal__r.Project_Title__c == null ? '' : mapping.Proposal__r.Project_Title__c;
            String projectAbstract  = mapping.Proposal__r.Abstract_of_proposed_work__c == null ? '' : mapping.Proposal__r.Abstract_of_proposed_work__c;

            /*
             * ----------------------------------------------------
             * APPLICANT NAME
             * ----------------------------------------------------
             */

            String applicantName = '';

            Applicant_Proposal_Association__c applicantAssociation = applicantByProposal.get(mapping.Proposal__c);

            if (applicantAssociation != null && applicantAssociation.Contact__r != null) {

                List<String> nameParts = new List<String>();

                String appTitle   = applicantAssociation.Contact__r.Title__c;
                String salutation = applicantAssociation.Contact__r.Salutation;

                if (String.isNotBlank(appTitle)) {
                    nameParts.add(appTitle);
                } else if (String.isNotBlank(salutation)) {
                    nameParts.add(salutation);
                }

                if (String.isNotBlank(applicantAssociation.Contact__r.FirstName)) {
                    nameParts.add(applicantAssociation.Contact__r.FirstName);
                }

                if (String.isNotBlank(applicantAssociation.Contact__r.LastName)) {
                    nameParts.add(applicantAssociation.Contact__r.LastName);
                }

                applicantName = String.join(nameParts, ' ');
            }

            /*
             * ----------------------------------------------------
             * HOST NAME
             * ----------------------------------------------------
             */

            String hostName = '';

            Applicant_Host_Association__c hostAssociation = hostByProposal.get(mapping.Proposal__c);

            if (hostAssociation != null && hostAssociation.Host__r != null) {
                hostName = hostAssociation.Host__r.Name;
            }

            /*
             * ----------------------------------------------------
             * PERSONALIZED URL
             * ----------------------------------------------------
             */

            String personalizedURL;

            if (String.isBlank(mapping.Reviewer__r.Firebase_UID__c)) {
                personalizedURL =
                    baseURL +
                    '?reviewerId=' + EncodingUtil.urlEncode(reviewerId, 'UTF-8') +
                    '&title=' + EncodingUtil.urlEncode(title, 'UTF-8') +
                    '&firstName=' + EncodingUtil.urlEncode(firstName, 'UTF-8') +
                    '&lastName=' + EncodingUtil.urlEncode(lastName, 'UTF-8') +
                    '&reviewerType=' + EncodingUtil.urlEncode(reviewerType, 'UTF-8') +
                    '&deadlineDate=' + EncodingUtil.urlEncode(deadlineDate, 'UTF-8') +
                    '&email=' + EncodingUtil.urlEncode(emailAddress, 'UTF-8');
            } else {
                personalizedURL = loginURL;
            }

            /*
             * ----------------------------------------------------
             * ACCEPT URL
             * ----------------------------------------------------
             */

            String encodedRedirect = EncodingUtil.urlEncode(personalizedURL, 'UTF-8');

            String acceptedURL =
                reactBaseUrl +
                'reviewer-action?proposalId=' + mapping.Proposal__c +
                '&reviewerId=' + reviewerId +
                '&reviewerMappingId=' + mapping.Id +
                '&actionType=Accepted' +
                '&redirectUrl=' + encodedRedirect;

            /*
             * ----------------------------------------------------
             * MERGE VALUES
             * ----------------------------------------------------
             *
             * These are passed to SESService.
             *
             * IMPORTANT:
             * Your SESService must replace these placeholders
             * in the template.
             * ----------------------------------------------------
             */

            Map<String, String> mergeValues = new Map<String, String>{
                'Reviewer_FirstName' => firstName,
                'Reviewer_LastName'  => lastName,
                'ProposalId'         => proposalIdText,
                'SchemeName'         => schemeName,
                'ApplicantName'      => applicantName,
                'HostInstitution'    => hostName,
                'ProjectTitle'       => projectTitle,
                'ProjectAbstract'    => projectAbstract,
                'ReviewerMappingId'  => String.valueOf(mapping.Id),
                'ReviewerId'         => reviewerId,
                'ProposalIdRecord'   => String.valueOf(mapping.Proposal__c),
                'ReviewerType'       => reviewerType,
                'DeadlineDate'       => deadlineDate,
                'PersonalizedURL'    => personalizedURL,
                'AcceptedURL'        => acceptedURL,
                'Email'              => emailAddress
            };

            System.debug('Reviewer Assignment Merge Values ==> ' + mergeValues);

            /*
             * ----------------------------------------------------
             * SEND THROUGH SES
             * ----------------------------------------------------
             */

            try {
                HttpResponse response = SESService.sendEmail(emailAddress, selectedTemplate, mergeValues);

                if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    System.debug(
                        'Reviewer assignment email sent successfully. ' +
                        'Mapping Id: ' + mapping.Id +
                        ', Email: ' + emailAddress +
                        ', Template: ' + selectedTemplate +
                        ', Status: ' + response.getStatusCode()
                    );
                } else {
                    System.debug(
                        'Reviewer assignment email failed. ' +
                        'Mapping Id: ' + mapping.Id +
                        ', Email: ' + emailAddress +
                        ', Template: ' + selectedTemplate +
                        ', Status: ' + (response == null ? 'NULL' : String.valueOf(response.getStatusCode())) +
                        ', Body: ' + (response == null ? '' : response.getBody())
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    'Reviewer assignment email exception. ' +
                    'Mapping Id: ' + mapping.Id +
                    ', Email: ' + emailAddress +
                    ', Template: ' + selectedTemplate +
                    ', Error: ' + ex.getMessage()
                );
            }
        }
    }
    private void processContactReferee() {    
        List<Additional_Partcipant__c> referees = [ SELECT Id, Proposal__c, Email__c, Title__c, First_Name__c, Last_Name__c,Roles__c FROM Additional_Partcipant__c WHERE Id IN :recordIds ];
        if (referees.isEmpty()) {
            return;
        }
        Set<Id> proposalIds = new Set<Id>();
        for (Additional_Partcipant__c referee : referees) {
            if (referee.Proposal__c != null) {
                proposalIds.add(referee.Proposal__c);
            }
        }
        Map<Id, Applicant_Proposal_Association__c> applicantByProposal = new Map<Id, Applicant_Proposal_Association__c>();
        if (!proposalIds.isEmpty()) {
            for (Applicant_Proposal_Association__c apa : [
                SELECT Id,
                       Proposal__c,
                       Contact__c,
                       Contact__r.Title__c,
                       Contact__r.Salutation,
                       Contact__r.FirstName,
                       Contact__r.LastName,
                       Contact__r.Email
                FROM Applicant_Proposal_Association__c
                WHERE Proposal__c IN :proposalIds
            ]) {
                if (!applicantByProposal.containsKey(apa.Proposal__c)) {
                    applicantByProposal.put(
                        apa.Proposal__c,
                        apa
                    );
                }
            }
        }
        List<Notification__c>notifContact = new List<Notification__c>();
        for (Additional_Partcipant__c referee : referees) {
            Applicant_Proposal_Association__c applicantAssociation = applicantByProposal.get(referee.Proposal__c);
            if ( applicantAssociation == null || applicantAssociation.Contact__r == null || String.isBlank(applicantAssociation.Contact__r.Email) ) {
                System.debug('Skipping CONREFEREE email. ' + 'No Contact found for Proposal: ' + referee.Proposal__c);
                continue;
            }
            List<String> refereeNameParts = new List<String>();
            
    
            if (String.isNotBlank(referee.Title__c)) {
                refereeNameParts.add(referee.Title__c);
            }
    
            if (String.isNotBlank(referee.First_Name__c)) {
                refereeNameParts.add(referee.First_Name__c);
            }
    
            if (String.isNotBlank(referee.Last_Name__c)) {
                refereeNameParts.add(referee.Last_Name__c);
            }
    
            String refereeName =  String.join( refereeNameParts,   ' '  );
    
            Contact contact = applicantAssociation.Contact__r;
            
            Notification__c nc = new Notification__c();
            nc.Contact__c = applicantAssociation.Contact__c;
            nc.Expiry_Date__c = system.today().addDays(10);
            nc.Title__c = referee.Roles__c + ' Uploaded Document';
            nc.Description__c = 'Document has been Updated by ' +  refereeName;
            notifContact.add(nc);
            
    
            List<String> contactNameParts = new List<String>();
            if (String.isNotBlank(contact.Title__c)) {
                contactNameParts.add(contact.Title__c );
            } else if (String.isNotBlank(contact.Salutation)) {
                contactNameParts.add(
                    contact.Salutation
                );
            }
            if (String.isNotBlank(contact.FirstName)) {
                contactNameParts.add(
                    contact.FirstName
                );
            }
            if (String.isNotBlank(contact.LastName)) {
                contactNameParts.add(
                    contact.LastName
                );
            }
            String applicantName = String.join(contactNameParts, ' ');
    
            Map<String, String> mergeValues = new Map<String, String>{ 'ApplicantName' => applicantName,  'RefereeName' =>  refereeName  };
            System.debug( 'CONREFEREE Merge Values ==> ' +  mergeValues );
            try {
    
                HttpResponse response = SESService.sendEmail(
                        contact.Email,
                        templateDeveloperName,
                        mergeValues
                    );
    
    
                if (
                    response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300
                ) {
    
                    System.debug(
                        'CONREFEREE email sent successfully. ' +
                        'Referee Id: ' + referee.Id +
                        ', Contact Id: ' + contact.Id +
                        ', Contact Email: ' + contact.Email
                    );
    
                } else {
    
                    System.debug(
                        'CONREFEREE email failed. ' +
                        'Referee Id: ' + referee.Id +
                        ', Contact Id: ' + contact.Id +
                        ', Status: ' +
                        (
                            response == null
                                ? 'NULL'
                                : String.valueOf(
                                    response.getStatusCode()
                                )
                        ) +
                        ', Body: ' +
                        (
                            response == null
                                ? ''
                                : response.getBody()
                        )
                    );
                }
    
            } catch (Exception ex) {
    
                System.debug(
                    'CONREFEREE email exception. ' +
                    'Referee Id: ' + referee.Id +
                    ', Contact Id: ' + contact.Id +
                    ', Error: ' + ex.getMessage()
                );
            }
        }
        if (!notifContact.isEmpty()){
            insert notifContact;
        }

    }

    /*
     * ============================================================
     * PROPOSAL PARTICIPANT HOST
     * ============================================================
     */
    private void processProposalParticipantHost() {

        List<Proposal_Participant_Association__c> records = [
            SELECT Id,
                   Participant__c,
                   Participant__r.Salutation,
                   Participant__r.Title__c,
                   Participant__r.FirstName,
                   Participant__r.LastName,
                   Participant__r.Email,
                   Proposal__c,
                   Proposal__r.Proposal_Id__c,
                   Proposal__r.Yearly_Scheme__r.Scheme__c
            FROM Proposal_Participant_Association__c
            WHERE Id IN :recordIds
        ];

        List<Proposal_Participant_Association__c> recordsToUpdate = new List<Proposal_Participant_Association__c>();

        for (Proposal_Participant_Association__c ppa : records) {

            String toEmail = ppa.Participant__r != null ? ppa.Participant__r.Email : null;

            if (String.isBlank(toEmail)) {
                continue;
            }

            String title = String.isNotBlank(ppa.Participant__r.Salutation)
                ? ppa.Participant__r.Salutation
                : ppa.Participant__r.Title__c;

            String invitationLink = invitationLinks.get(ppa.Id);

            Map<String, String> mergeValues = new Map<String, String>{
                'Title'          => title,
                'FirstName'      => ppa.Participant__r.FirstName,
                'LastName'       => ppa.Participant__r.LastName,
                'ProposalId'     => ppa.Proposal__r != null ? ppa.Proposal__r.Proposal_Id__c : null,
                'SchemeName'     => ppa.Proposal__r != null ? ppa.Proposal__r.Yearly_Scheme__r.Scheme__c : null,
                'Email'          => toEmail,
                'InvitationLink' => invitationLink
            };

            System.debug('Proposal Participant Host Merge Values ==> ' + mergeValues);

            Boolean emailSent = false;

            try {
                HttpResponse response = SESService.sendEmail(toEmail, templateDeveloperName, mergeValues);

                if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    emailSent = true;
                    System.debug(
                        'Proposal Participant host invitation email sent successfully. ' +
                        'Record Id: ' + ppa.Id +
                        ', Email: ' + toEmail +
                        ', Status: ' + response.getStatusCode()
                    );
                } else {
                    System.debug(
                        'Proposal Participant host invitation email failed. ' +
                        'Record Id: ' + ppa.Id +
                        ', Email: ' + toEmail +
                        ', Status: ' + (response == null ? 'NULL' : String.valueOf(response.getStatusCode())) +
                        ', Body: ' + (response == null ? '' : response.getBody())
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    'Proposal Participant host invitation email exception. ' +
                    'Record Id: ' + ppa.Id +
                    ', Email: ' + toEmail +
                    ', Error: ' + ex.getMessage()
                );
            }

            recordsToUpdate.add(
                new Proposal_Participant_Association__c(
                    Id = ppa.Id,
                    Invitation_Link__c = invitationLink,
                    Email_Sent__c = emailSent
                )
            );
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    /*
     * ============================================================
     * FULL APPLICATION ELIGIBLE
     * ============================================================
     * recordIds here are Proposal__c Ids (not a child object) - see
     * ProposalTriggerHandler.notifyApplicantOnFullApplicationEligibility, which enqueues this
     * job as soon as Proposal_Status__c becomes 'Full Application'. Mirrors
     * processWOHICollaboration above: creates the in-app Notification__c here (the
     * After_Insert_Notification_Create_Notification_Status flow creates the matching
     * Notification_Status__c automatically) and sends the email via SESService in the same pass.
     */
    private void processFullApplicationEligible() {

        List<Proposal__c> proposals = [
            SELECT Id,
                   Proposal_Id__c,
                   Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Proposal__c
            WHERE Id IN :recordIds
        ];

        if (proposals.isEmpty()) {
            return;
        }

        Map<Id, Applicant_Proposal_Association__c> applicantByProposal =
            new Map<Id, Applicant_Proposal_Association__c>();

        for (
            Applicant_Proposal_Association__c apa : [
                SELECT Proposal__c,
                       Contact__c,
                       Contact__r.Title__c,
                       Contact__r.Salutation,
                       Contact__r.FirstName,
                       Contact__r.LastName,
                       Contact__r.Email
                FROM Applicant_Proposal_Association__c
                WHERE Proposal__c IN :recordIds
                AND Contact__c != null
                ORDER BY CreatedDate ASC
            ]
        ) {
            if (!applicantByProposal.containsKey(apa.Proposal__c)) {
                applicantByProposal.put(apa.Proposal__c, apa);
            }
        }

        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        String portalLoginURL = reactBaseUrl + 'login';

        List<Notification__c> notificationsToInsert = new List<Notification__c>();

        for (Proposal__c proposal : proposals) {

            Applicant_Proposal_Association__c applicantAssociation = applicantByProposal.get(proposal.Id);
            if (applicantAssociation == null || applicantAssociation.Contact__r == null) {
                System.debug('Skipping FULL_APPLICATION_ELIGIBLE - no Applicant found for Proposal: ' + proposal.Id);
                continue;
            }

            Contact contact = applicantAssociation.Contact__r;

            String proposalIdText = proposal.Proposal_Id__c == null ? '' : proposal.Proposal_Id__c;
            String schemeName = (proposal.Yearly_Scheme__r != null && proposal.Yearly_Scheme__r.Scheme_Items__r != null)
                ? proposal.Yearly_Scheme__r.Scheme_Items__r.Name
                : '';

            List<String> nameParts = new List<String>();
            if (String.isNotBlank(contact.Title__c)) {
                nameParts.add(contact.Title__c);
            } else if (String.isNotBlank(contact.Salutation)) {
                nameParts.add(contact.Salutation);
            }
            if (String.isNotBlank(contact.FirstName)) {
                nameParts.add(contact.FirstName);
            }
            if (String.isNotBlank(contact.LastName)) {
                nameParts.add(contact.LastName);
            }
            String applicantName = String.join(nameParts, ' ');

            Notification__c notif = new Notification__c();
            notif.Contact__c = applicantAssociation.Contact__c;
            notif.Title__c = 'Eligible for Full Application';
            notif.Description__c = 'Your proposal ' + proposalIdText + ' is now eligible for the Full Application stage under ' + schemeName + '.';
            notif.Expiry_Date__c = System.today().addDays(10);
            notificationsToInsert.add(notif);

            if (String.isBlank(contact.Email)) {
                System.debug('Skipping FULL_APPLICATION_ELIGIBLE email - no Contact email for Proposal: ' + proposal.Id);
                continue;
            }

            Map<String, String> mergeValues = new Map<String, String>{
                'Applicant_Name' => applicantName,
                'ProposalId'     => proposalIdText,
                'SchemeName'     => schemeName,
                'PortalLink'     => portalLoginURL
            };

            System.debug('Full Application Eligible Merge Values ==> ' + mergeValues);

            try {
                HttpResponse response = SESService.sendEmail(contact.Email, 'Eligible_for_Full_Stage_Email_Template', mergeValues);

                if (response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    System.debug(
                        'Full Application eligible email sent successfully. ' +
                        'Proposal Id: ' + proposal.Id +
                        ', Email: ' + contact.Email +
                        ', Status: ' + response.getStatusCode()
                    );
                } else {
                    System.debug(
                        'Full Application eligible email failed. ' +
                        'Proposal Id: ' + proposal.Id +
                        ', Email: ' + contact.Email +
                        ', Status: ' + (response == null ? 'NULL' : String.valueOf(response.getStatusCode())) +
                        ', Body: ' + (response == null ? '' : response.getBody())
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    'Full Application eligible email exception. ' +
                    'Proposal Id: ' + proposal.Id +
                    ', Email: ' + contact.Email +
                    ', Error: ' + ex.getMessage()
                );
            }
        }

        if (!notificationsToInsert.isEmpty()) {
            insert notificationsToInsert;
        }
    }

    /*
     * ============================================================
     * REVIEWER MAPPING APPROVED
     * ============================================================
     * recordIds here are Reviewer_Mapping__c Ids - see
     * ReviewerMappingTriggerHandler.handleAfterUpdate, which enqueues this job as soon as
     * Grant_Member_Status__c becomes 'Approved'. Ported from the old
     * ReviewerController.sendReviewerAssignmentEmails (previously called synchronously, right
     * after Reviewer_Mapping__c creation) - same templates, same personalized-link logic, same
     * manual {!Object.Field}-style placeholder replacement. Moved here so it (a) runs async in
     * a context that allows the callout-adjacent Messaging.sendEmail work without risking the
     * record creation transaction, and (b) fires at the new trigger point - approval, not
     * creation - and any failure here only fails this queued job, never the caller's DML.
     */
    private void processReviewerMappingApproved() {

        List<Reviewer_Mapping__c> mappings = [
            SELECT Id, Reviewer__r.Email_Address__c, Reviewer__r.Title__c, Reviewer__r.First_Name__c, Reviewer__r.Last_Name__c,
                   Proposal__r.Proposal_Id__c, Scheme_Name__c, Reviewer__r.Firebase_UID__c, Reviewer__r.Reviewer_Type__c,
                   Proposal__r.Application_Stages__c, Proposal__r.Project_Title__c, Deadline_Date__c,
                   Proposal__r.Abstract_of_proposed_work__c, Reviewer_Type__c, Proposal__c
            FROM Reviewer_Mapping__c
            WHERE Id IN :recordIds
        ];

        if (mappings.isEmpty()) {
            return;
        }

        Map<String, EmailTemplate> templateMap = new Map<String, EmailTemplate>();
        for (EmailTemplate et : [
            SELECT Id, DeveloperName, Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName IN ('New_Proposal_Assignment', 'X19ReviewInvitation')
            AND IsActive = true
        ]) {
            templateMap.put(et.DeveloperName, et);
        }

        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        String baseURL = reactBaseUrl + 'reviewer_register_verifyemail';
        String loginURL = reactBaseUrl + 'login';

        Set<Id> proposalIds = new Set<Id>();
        for (Reviewer_Mapping__c mapping : mappings) {
            if (mapping.Proposal__c != null) {
                proposalIds.add(mapping.Proposal__c);
            }
        }

        Map<Id, Applicant_Proposal_Association__c> applicantByProposal = new Map<Id, Applicant_Proposal_Association__c>();
        for (Applicant_Proposal_Association__c apa : [
            SELECT Proposal__c, Contact__r.Title__c, Contact__r.Salutation, Contact__r.FirstName, Contact__r.LastName
            FROM Applicant_Proposal_Association__c
            WHERE Proposal__c IN :proposalIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!applicantByProposal.containsKey(apa.Proposal__c)) {
                applicantByProposal.put(apa.Proposal__c, apa);
            }
        }

        Map<Id, Applicant_Host_Association__c> hostByProposal = new Map<Id, Applicant_Host_Association__c>();
        for (Applicant_Host_Association__c aha : [
            SELECT Proposal__c, Host__r.Name
            FROM Applicant_Host_Association__c
            WHERE Proposal__c IN :proposalIds
        ]) {
            if (!hostByProposal.containsKey(aha.Proposal__c)) {
                hostByProposal.put(aha.Proposal__c, aha);
            }
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> mappingIdsByEmail = new List<Id>();

        for (Reviewer_Mapping__c mapping : mappings) {

            if (mapping.Reviewer__r == null || String.isBlank(mapping.Reviewer__r.Email_Address__c)) {
                System.debug('Skipping reviewer assignment email - no Reviewer email for mapping: ' + mapping.Id);
                continue;
            }

            // Defense-in-depth: only email a reviewer whose Reviewer_Type__c actually matches
            // the proposal's stage (Prelims -> Ex-Grantee, Full -> Peer).
            String proposalStage = mapping.Proposal__r != null ? mapping.Proposal__r.Application_Stages__c : null;
            String expectedTypeForStage = (proposalStage == 'Prelims')
                ? 'Ex-Grantee'
                : (proposalStage == 'Full') ? 'Peer' : null;
            if (String.isNotBlank(expectedTypeForStage) && mapping.Reviewer__r.Reviewer_Type__c != expectedTypeForStage) {
                System.debug('Skipping reviewer assignment email - Reviewer_Type__c mismatch for stage ' + proposalStage
                    + ': ' + mapping.Reviewer__r.Reviewer_Type__c);
                continue;
            }

            EmailTemplate template = (proposalStage == 'Full')
                ? templateMap.get('X19ReviewInvitation')
                : templateMap.get('New_Proposal_Assignment');
            if (template == null) {
                System.debug('Skipping reviewer assignment email - template not found/active for stage ' + proposalStage);
                continue;
            }

            String emailHtml = template.HtmlValue == null ? '' : template.HtmlValue;
            String emailText = template.Body == null ? '' : template.Body;
            String reviewerId = mapping.Reviewer__r.Id == null ? '' : String.valueOf(mapping.Reviewer__r.Id);
            String title = mapping.Reviewer__r.Title__c == null ? '' : mapping.Reviewer__r.Title__c;
            String firstName = mapping.Reviewer__r.First_Name__c == null ? '' : mapping.Reviewer__r.First_Name__c;
            String lastName = mapping.Reviewer__r.Last_Name__c == null ? '' : mapping.Reviewer__r.Last_Name__c;
            String emailAddress = mapping.Reviewer__r.Email_Address__c;
            String proposalIdText = mapping.Proposal__r.Proposal_Id__c == null ? '' : mapping.Proposal__r.Proposal_Id__c;
            String schemeName = mapping.Scheme_Name__c == null ? '' : mapping.Scheme_Name__c;

            String applicantName = '';
            Applicant_Proposal_Association__c applicantAssociation = applicantByProposal.get(mapping.Proposal__c);
            if (applicantAssociation != null && applicantAssociation.Contact__r != null) {
                List<String> nameParts = new List<String>();
                String appTitle = applicantAssociation.Contact__r.Title__c;
                String salutation = applicantAssociation.Contact__r.Salutation;
                if (String.isNotBlank(appTitle)) {
                    nameParts.add(appTitle);
                } else if (String.isNotBlank(salutation)) {
                    nameParts.add(salutation);
                }
                if (String.isNotBlank(applicantAssociation.Contact__r.FirstName)) {
                    nameParts.add(applicantAssociation.Contact__r.FirstName);
                }
                if (String.isNotBlank(applicantAssociation.Contact__r.LastName)) {
                    nameParts.add(applicantAssociation.Contact__r.LastName);
                }
                applicantName = String.join(nameParts, ' ');
            }

            String hostName = '';
            Applicant_Host_Association__c hostAssociation = hostByProposal.get(mapping.Proposal__c);
            if (hostAssociation != null && hostAssociation.Host__r != null) {
                hostName = hostAssociation.Host__r.Name;
            }

            String reviewerType = mapping.Reviewer_Type__c == null ? '' : mapping.Reviewer_Type__c;
            String deadlineDate = mapping.Deadline_Date__c == null ? '' : String.valueOf(mapping.Deadline_Date__c);

            String personalizedURL;
            if (String.isBlank(mapping.Reviewer__r.Firebase_UID__c)) {
                personalizedURL = baseURL +
                    '?reviewerId=' + EncodingUtil.urlEncode(reviewerId, 'UTF-8') +
                    '&title=' + EncodingUtil.urlEncode(title, 'UTF-8') +
                    '&firstName=' + EncodingUtil.urlEncode(firstName, 'UTF-8') +
                    '&lastName=' + EncodingUtil.urlEncode(lastName, 'UTF-8') +
                    '&reviewerType=' + EncodingUtil.urlEncode(reviewerType, 'UTF-8') +
                    '&deadlineDate=' + EncodingUtil.urlEncode(deadlineDate, 'UTF-8') +
                    '&email=' + EncodingUtil.urlEncode(emailAddress, 'UTF-8');
            } else {
                personalizedURL = loginURL;
            }

            String projectTitle = mapping.Proposal__r.Project_Title__c == null ? '' : mapping.Proposal__r.Project_Title__c;
            String projectAbstract = mapping.Proposal__r.Abstract_of_proposed_work__c == null ? '' : mapping.Proposal__r.Abstract_of_proposed_work__c;
            String encodedRedirect = EncodingUtil.urlEncode(personalizedURL, 'UTF-8');
            String originalAcceptParam = 'actionType=Accepted';
            String acceptedURL = reactBaseUrl + 'reviewer-action?proposalId=' + mapping.Proposal__c +
                '&reviewerId=' + reviewerId +
                '&reviewerMappingId=' + mapping.Id +
                '&actionType=Accepted&redirectUrl=' + encodedRedirect;

            emailHtml = emailHtml.replace(REVIEWER_REGISTER_URL_PLACEHOLDER, personalizedURL);
            emailHtml = emailHtml.replace(originalAcceptParam, acceptedURL);
            emailHtml = emailHtml.replace('{!Reviewer__c.First_Name__c}', firstName);
            emailHtml = emailHtml.replace('{!Reviewer__c.Last_Name__c}', lastName);
            emailHtml = emailHtml.replace('{!Reviewer_Mapping__c.Proposal_ID_Text__c}', proposalIdText);
            emailHtml = emailHtml.replace('{Applicants_name}', applicantName);
            emailHtml = emailHtml.replace('{!Reviewer_Mapping__c.Applicant_Name__c}', applicantName);
            emailHtml = emailHtml.replace('{HostInstitution}', hostName);
            emailHtml = emailHtml.replace('{!Reviewer_Mapping__r.Proposal__r.Project_Title__c}', projectTitle);
            emailHtml = emailHtml.replace('{!Reviewer_Mapping__r.Proposal__r.Abstract_of_proposed_work__c}', projectAbstract);
            emailHtml = emailHtml.replace('{!Reviewer_Mapping__c.Id}', String.valueOf(mapping.Id));
            emailHtml = emailHtml.replace('{!Reviewer_Mapping__c.Scheme_Name__c}', schemeName);
            emailHtml = emailHtml.replace('{!Reviewer__c.Id}', reviewerId);
            emailHtml = emailHtml.replace('{!Reviewer_Mapping__c.Proposal__c}', String.valueOf(mapping.Proposal__c));

            emailText = emailText.replace(REVIEWER_REGISTER_URL_PLACEHOLDER, personalizedURL);
            emailText = emailText.replace(originalAcceptParam, acceptedURL);
            emailText = emailText.replace('{!Reviewer__c.First_Name__c}', firstName);
            emailText = emailText.replace('{!Reviewer__c.Last_Name__c}', lastName);
            emailText = emailText.replace('{!Reviewer_Mapping__c.Proposal_ID_Text__c}', proposalIdText);
            emailText = emailText.replace('{!Reviewer_Mapping__c.Scheme_Name__c}', schemeName);
            emailText = emailText.replace('{Applicants_name}', applicantName);
            emailText = emailText.replace('{HostInstitution}', hostName);
            emailText = emailText.replace('{!Reviewer_Mapping__r.Proposal__r.Project_Title__c}', projectTitle);
            emailText = emailText.replace('{!Reviewer_Mapping__r.Proposal__r.Abstract_of_proposed_work__c}', projectAbstract);
            emailText = emailText.replace('{!Reviewer_Mapping__c.Id}', String.valueOf(mapping.Id));
            emailText = emailText.replace('{!Reviewer__c.Id}', reviewerId);
            emailText = emailText.replace('{!Reviewer_Mapping__c.Proposal__c}', String.valueOf(mapping.Proposal__c));

            try {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ emailAddress });
                email.setSubject(template.Subject);
                email.setSaveAsActivity(false);
                email.setHtmlBody(emailHtml);
                email.setPlainTextBody(emailText);
                emails.add(email);
                mappingIdsByEmail.add(mapping.Id);
            } catch (Exception e) {
                System.debug('Reviewer assignment email build failed for mapping ' + mapping.Id + ': ' + e.getMessage());
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(emails, false);
                List<Reviewer_Mapping__c> mappingsToUpdate = new List<Reviewer_Mapping__c>();
                Datetime sentTime = System.now();

                for (Integer index = 0; index < sendResults.size(); index++) {
                    if (sendResults[index].isSuccess()) {
                        mappingsToUpdate.add(new Reviewer_Mapping__c(
                            Id = mappingIdsByEmail[index],
                            Email_Sent_Time__c = sentTime
                        ));
                    } else {
                        System.debug('Reviewer assignment email failed for mapping ' + mappingIdsByEmail[index]
                            + ': ' + sendResults[index].getErrors());
                    }
                }

                if (!mappingsToUpdate.isEmpty()) {
                    update mappingsToUpdate;
                }
            } catch (Exception e) {
                System.debug('Reviewer assignment email send failed: ' + e.getMessage());
            }
        }
    }
}