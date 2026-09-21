public with sharing class NotificationHandler {

    private static final String STATUS_REJECTED          = 'Rejected';
    private static final String NOTIFICATION_STATUS_SENT = 'Sent'; // assumption - adjust if needed
    private static final String NOTIFICATION_STATUS_UNREAD = 'Unread'; // assumption - adjust if needed

    /**
     * Single method - call from both Proposal__c and Yearly_Schemes__c after-insert triggers:
     *   NotificationHandler.createNotifications('Yearly_Schemes__c', Trigger.new);
     *   NotificationHandler.createNotifications('Proposal__c', Trigger.new);
     */
    public static void createNotifications(String objectApiName, List<SObject> newRecords) {

        System.debug('========== NotificationHandler START ==========');
        System.debug('Object API Name: ' + objectApiName);
        List<Contact> contacts = [SELECT Id FROM Contact];
        // NULL CHECK: inputs must be valid
        if (String.isBlank(objectApiName)) {
            System.debug('Object API Name is blank. Exiting.');
            return;
        }

        if (newRecords == null || newRecords.isEmpty()) {
            System.debug('No records found. Exiting.');
            return;
        }

        List<Notification__c> notificationsToInsert = new List<Notification__c>();
        // ------------------------------------------------------------------
        // Yearly_Schemes__c -> one "For All" notification per newly active scheme
        // ------------------------------------------------------------------
        if (objectApiName == 'Yearly_Schemes__c') {

            for (SObject rec : newRecords) {

                // NULL CHECK: skip null entries
                if (rec == null) {
                    continue;
                }

                Yearly_Schemes__c scheme = (Yearly_Schemes__c) rec;

                // Only proceed when Is_Active__c is explicitly true (also handles null safely)
                if (scheme.Is_Active__c != true) {
                    System.debug('Skipping Yearly_Schemes__c ' + scheme.Id + ' - Is_Active__c not true.');
                    continue;
                }

                // NULL CHECK: Scheme__c must have a value to build the message
                if (String.isBlank(scheme.Scheme__c)) {
                    System.debug('Skipping Yearly_Schemes__c ' + scheme.Id + ' - Scheme__c is blank.');
                    continue;
                }

                // notificationsToInsert.add(notif);
                for (Contact con : contacts) {
                    Notification__c notif = new Notification__c();
                    notif.Contact__c = con.Id;
                    notif.For_all__c = True;
                    notif.Title__c = 'New Yearly Scheme';
                    notif.Description__c = 'New Yearly Scheme (' + scheme.Scheme__c + ') is introduced.';
                    notif.Yearly_Schemes__c = scheme.Id;
                    notif.Expiry_Date__c = Date.today().addDays(50);

                    notificationsToInsert.add(notif);
                }
            }
            

        // ------------------------------------------------------------------
        // Proposal__c -> one notification per Contact linked via
        // Applicant_Proposal_Association__c, when the Proposal is Rejected
        // ------------------------------------------------------------------
        } else if (objectApiName == 'Proposal__c') {

            // Step 1: collect Ids of newly-rejected proposals
            Set<Id> rejectedProposalIds = new Set<Id>();

            for (SObject rec : newRecords) {

                // NULL CHECK: skip null entries
                if (rec == null) {
                    continue;
                }

                Proposal__c proposal = (Proposal__c) rec;

                if (proposal.Id == null) {
                    continue;
                }

                if (proposal.Proposal_Status__c == STATUS_REJECTED) {
                    rejectedProposalIds.add(proposal.Id);
                }
            }

            System.debug('Rejected Proposal Ids: ' + rejectedProposalIds);

            if (!rejectedProposalIds.isEmpty()) {

                // Step 2: re-query proposals for Project_Title__c (safe even though it's
                // after-insert, guards against the field not being on the trigger's record set)
                Map<Id, Proposal__c> proposalsWithTitle = new Map<Id, Proposal__c>([
                    SELECT Id, Project_Title__c
                    FROM Proposal__c
                    WHERE Id IN :rejectedProposalIds
                ]);

                // Step 3: find Applicant_Proposal_Association__c records tied to these proposals
                List<Applicant_Proposal_Association__c> associations = [
                    SELECT Id, Contact__c, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c IN :rejectedProposalIds
                ];

                System.debug('Applicant Proposal Associations Found: ' + associations.size());

                for (Applicant_Proposal_Association__c apa : associations) {

                    // NULL CHECK: need both a Contact and a Proposal to build a valid notification
                    if (apa == null || apa.Contact__c == null || apa.Proposal__c == null) {
                        System.debug('Skipping invalid Applicant_Proposal_Association__c row: ' + apa);
                        continue;
                    }

                    Proposal__c relatedProposal = proposalsWithTitle.get(apa.Proposal__c);

                    // NULL CHECK: proposal must still be resolvable
                    if (relatedProposal == null) {
                        System.debug('No matching Proposal found for APA: ' + apa.Id);
                        continue;
                    }

                    String projectTitle = String.isBlank(relatedProposal.Project_Title__c)
                        ? ''
                        : relatedProposal.Project_Title__c;

                    Notification__c notif = new Notification__c();
                    notif.For_all__c = false;
                    notif.Contact__c = apa.Contact__c;
                    notif.Title__c = 'Proposal Rejected';
                    notif.Description__c = 'Your Proposal ' + projectTitle + ' is Rejected.';
                    notif.Expiry_Date__c = Date.today().addDays(10); 
                    notificationsToInsert.add(notif);
                }
            }
        } else if (objectApiName == 'Reviewer_Mapping__c') {

            Map<Id, List<Reviewer_Mapping__c>> reviewerMappingsByProposal = new Map<Id, List<Reviewer_Mapping__c>>();
            Map<Id, String> proposalNameByProposalId = new Map<Id, String>();

            for(Reviewer_Mapping__c rm : (List<Reviewer_Mapping__c>) newRecords){
                if(!reviewerMappingsByProposal.containsKey(rm.Proposal__c)){
                    reviewerMappingsByProposal.put(rm.Proposal__c, new List<Reviewer_Mapping__c>());
                    proposalNameByProposalId.put(rm.Proposal__c, rm.Proposal_Id__c);
                }
                reviewerMappingsByProposal.get(rm.Proposal__c).add(rm);
            }

            for(Id pId : reviewerMappingsByProposal.keySet()){
                List<Reviewer_Mapping__c> rms = reviewerMappingsByProposal.get(pId);
                // Process each reviewer mapping

                for(Reviewer_Mapping__c rm : rms){
                    Notification__c notif = new Notification__c();
                    notif.Reviewer__c = rm.Reviewer__c;
                    notif.Reviewer_Mapping__c = rm.Id;
                    notif.Title__c = 'New Proposal Assignment.';
                    notif.Description__c = 'New Proposal has been assigned to you for review : ' + proposalNameByProposalId.get(rm.Proposal__c)+'.';
                    notif.Expiry_Date__c = Date.today().addDays(50);
                    notificationsToInsert.add(notif);
                }
            }
        } else if (objectApiName == 'Proposal_Committee__c') {
        
            Set<Id> committeeMemberIds = new Set<Id>();
            for (SObject rec : newRecords) {
                if (rec == null) {
                    continue;
                }
                Proposal_Committee__c pc = (Proposal_Committee__c) rec;
                if (pc.Committee_Member__c != null) {
                    committeeMemberIds.add(pc.Committee_Member__c);
                }
            }
            Map<Id, Committee_Member__c> committeeMembersById =
                new Map<Id, Committee_Member__c>([
                    SELECT Id, Committee_Master__c
                    FROM Committee_Member__c
                    WHERE Id IN :committeeMemberIds
                ]);
            for (SObject rec : newRecords) {
                if (rec == null) {
                    continue;
                }
                Proposal_Committee__c pc = (Proposal_Committee__c) rec;
                if (pc.Committee_Member__c == null) {
                    System.debug(
                        'Proposal Committee Committee Member is null: ' + pc.Id
                    );
                    continue;
                }
                Committee_Member__c committeeMember =
                    committeeMembersById.get(pc.Committee_Member__c);
        
                if (committeeMember == null) {
                    System.debug(
                        'Committee Member not found: ' + pc.Committee_Member__c
                    );
                    continue;
                }
        
                if (committeeMember.Committee_Master__c == null) {
                    System.debug(
                        'Committee Master is null for Committee Member: ' +
                        pc.Committee_Member__c
                    );
                    continue;
                }
        
                Notification__c notif = new Notification__c();
        
                notif.Committee_Master__c = committeeMember.Committee_Master__c;
        
                notif.Title__c =
                    'You have been assigned to Proposal ' +
                    pc.Proposal_Id__c;
        
                notif.Description__c =
                     pc.Commitee_Member_Name__c +
                    ', have been tagged as a ' + pc.Type__c +
                    ' for proposal ' + pc.Proposal_Id__c +
                    ' = (' + pc.Scheme_Name__c +
                    ') Please review the proposal details.';
        
                notif.Expiry_Date__c = Date.today().addDays(50);
        
                notificationsToInsert.add(notif);
            }
        }

        else {
            System.debug('Unsupported Object API Name for notifications: ' + objectApiName);
            return;
        }

        System.debug('Total Notifications To Insert: ' + notificationsToInsert.size());

        if (!notificationsToInsert.isEmpty()) {
            insert notificationsToInsert;
            System.debug('Notifications Inserted Successfully.');
        } 
        else {
            System.debug('No Notifications to insert.');
        }

        System.debug('========== NotificationHandler END ==========');
    }

    public static void createNotificationForSchemeSection(
        List<Scheme_Section__c> newSections,
        Map<Id, Scheme_Section__c> oldSectionsById
    ) {
        if (newSections == null || newSections.isEmpty()) {
            System.debug('No Scheme_Section__c records provided. Exiting.');
            return;
        }

        // Resolved via Scheme_Section__c.Applicant_Proposal_Association__c (not Proposal__c) -
        // this IS the reliably-populated lookup on real reopened sections; the earlier attempt
        // to resolve via Proposal__c was based on a biased sample and was wrong.
        List<Scheme_Section__c> reopenedSections = new List<Scheme_Section__c>();
        Set<Id> apaIds = new Set<Id>();
        for (Scheme_Section__c section : newSections) {
            if (section.Reopen_Status__c != 'Reopen') {
                continue;
            }

            Scheme_Section__c oldSection = oldSectionsById != null ? oldSectionsById.get(section.Id) : null;
            if (oldSection != null && oldSection.Reopen_Status__c == 'Reopen') {
                continue;
            }

            reopenedSections.add(section);
            if (section.Applicant_Proposal_Association__c != null) {
                apaIds.add(section.Applicant_Proposal_Association__c);
            }
        }

        System.debug('Reopened Scheme_Section APA Ids: ' + apaIds);

        if (reopenedSections.isEmpty()) {
            return;
        }

        // Contact__r.Email pulled explicitly here (not just Contact__c) so the email step below
        // can check the Applicant actually has an email address before attempting to send, same
        // as sendSubmissionConfirmation does elsewhere. Proposal__c comes along too, purely to
        // resolve the Proposal Id for the email content and as the record the template merges
        // {!Proposal__c.*} fields from.
        Map<Id, Applicant_Proposal_Association__c> apaById = new Map<Id, Applicant_Proposal_Association__c>();
        if (!apaIds.isEmpty()) {
            apaById = new Map<Id, Applicant_Proposal_Association__c>([
                SELECT Id, Contact__c, Contact__r.Email, Proposal__c
                FROM Applicant_Proposal_Association__c
                WHERE Id IN :apaIds
            ]);
        }

        List<Notification__c> notificationsToInsert = new List<Notification__c>();
        // Grouped by APA (one Applicant per Proposal) so a Grants Team Member reopening several
        // sections at once (the Re-Open Section modal allows selecting multiple) results in one
        // combined email, not one email per section.
        Map<Id, List<Scheme_Section__c>> reopenedSectionsByApa = new Map<Id, List<Scheme_Section__c>>();

        for (Scheme_Section__c section : reopenedSections) {
            if (section.Applicant_Proposal_Association__c == null) {
                continue;
            }

            Applicant_Proposal_Association__c apa = apaById.get(section.Applicant_Proposal_Association__c);
            if (apa == null || apa.Contact__c == null) {
                System.debug('No valid Contact found for APA: ' + section.Applicant_Proposal_Association__c);
                continue;
            }

            Notification__c notif = new Notification__c();
            notif.Contact__c = apa.Contact__c;
            notif.Title__c = 'Section Re-opened';
            notif.Description__c = 'Please fill the required changes.';
            notif.Expiry_Date__c = Date.today().addDays(10);
            notificationsToInsert.add(notif);

            if (!reopenedSectionsByApa.containsKey(section.Applicant_Proposal_Association__c)) {
                reopenedSectionsByApa.put(section.Applicant_Proposal_Association__c, new List<Scheme_Section__c>());
            }
            reopenedSectionsByApa.get(section.Applicant_Proposal_Association__c).add(section);
        }

        System.debug('Scheme_Section notifications to insert: ' + notificationsToInsert.size());

        if (!notificationsToInsert.isEmpty()) {
            insert notificationsToInsert;
            System.debug('Scheme_Section notifications inserted successfully.');
        }

        sendSectionReopenEmails(reopenedSectionsByApa, apaById);
    }

    private static final String SECTION_REOPEN_TEMPLATE_NAME = 'Section_Reopen_Email_Template';
    private static final String SECTION_DETAILS_PLACEHOLDER = '{{SECTION_DETAILS}}';

    // Sends one combined email per Applicant (grouped by APA, since one APA = one Applicant on
    // one Proposal), listing every section reopened in this same transaction, using the same
    // setTemplateId/setTargetObjectId/setWhatId native-merge mechanism as
    // ProposalTriggerHandler.sendSubmissionConfirmation - only difference is the dynamic section
    // list, which the template can't merge natively (it's a variable-length list of child
    // records, not a single record's fields), so it's rendered via
    // Messaging.renderStoredEmailTemplate and then substituted into a plain placeholder token.
    private static void sendSectionReopenEmails(
        Map<Id, List<Scheme_Section__c>> reopenedSectionsByApa,
        Map<Id, Applicant_Proposal_Association__c> apaById
    ) {
        if (reopenedSectionsByApa.isEmpty()) {
            return;
        }

        EmailTemplate template;
        try {
            template = [
                SELECT Id
                FROM EmailTemplate
                WHERE DeveloperName = :SECTION_REOPEN_TEMPLATE_NAME
                AND IsActive = true
                LIMIT 1
            ];
        } catch (QueryException e) {
            System.debug('Section Reopen email template not found: ' + e.getMessage());
            return;
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id apaId : reopenedSectionsByApa.keySet()) {
            Applicant_Proposal_Association__c apa = apaById.get(apaId);
            if (apa == null || apa.Contact__c == null || String.isBlank(apa.Contact__r.Email)) {
                System.debug('Skipping Section Reopen email - no Contact email for APA: ' + apaId);
                continue;
            }

            List<String> plainLines = new List<String>();
            List<String> htmlRows = new List<String>();
            for (Scheme_Section__c section : reopenedSectionsByApa.get(apaId)) {
                String sectionName = String.isNotBlank(section.Section_Name__c) ? section.Section_Name__c : section.Name;
                String reason = String.isNotBlank(section.Re_Opening_Reason__c) ? section.Re_Opening_Reason__c : '';
                plainLines.add('- ' + sectionName + ': ' + reason);
                htmlRows.add(
                    '<tr>' +
                    '<td style="padding:8px 12px;color:#666666;font-weight:bold;width:38%;border-bottom:1px solid #e5e5e5;">' +
                    sectionName + '</td>' +
                    '<td style="padding:8px 12px;color:#333333;border-bottom:1px solid #e5e5e5;">' + reason + '</td>' +
                    '</tr>'
                );
            }
            String plainSectionDetails = String.join(plainLines, '\n');
            String htmlSectionDetails = String.join(htmlRows, '');

            try {
                Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                    template.Id,
                    apa.Contact__c,
                    apa.Proposal__c
                );

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(apa.Contact__c);
                email.setWhatId(apa.Proposal__c);
                email.setSaveAsActivity(false);
                email.setSubject(rendered.getSubject());

                String plainBody = rendered.getPlainTextBody() != null ? rendered.getPlainTextBody() : '';
                email.setPlainTextBody(plainBody.replace(SECTION_DETAILS_PLACEHOLDER, plainSectionDetails));

                if (String.isNotBlank(rendered.getHtmlBody())) {
                    email.setHtmlBody(rendered.getHtmlBody().replace(SECTION_DETAILS_PLACEHOLDER, htmlSectionDetails));
                }

                emails.add(email);
            } catch (Exception e) {
                System.debug('Error rendering Section Reopen email for APA ' + apaId + ': ' + e.getMessage());
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }
}