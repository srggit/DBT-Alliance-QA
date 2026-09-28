public with sharing class ReviewerController {
    // Placeholder token in the New_Proposal_Assignment_commitee email template
    // (both the HTML button href and the plain-text fallback link) that gets
    // swapped for each recipient's personalized reviewer-portal URL. Using a
    // fixed token here - rather than matching the literal reactBaseUrl - keeps
    // this working regardless of what URL_s__mdt.React_Site_Link resolves to
    // in the org the template happens to be deployed in.
    private static final String REVIEWER_PORTAL_URL_PLACEHOLDER = '{!Reviewer_Portal_URL__c}';

    // Placeholder in the committee assignment template: replaced with a bold "assigned as the
    // Reviewer" line for members with Committee_Reviewer__c = true, and with nothing for the rest.
    private static final String REVIEWER_NOTICE_PLACEHOLDER = '{!Reviewer_Assignment_Notice__c}';
    private static final String REVIEWER_SUBJECT = 'New Proposal Assigned - You are the Reviewer';

    // Proposal statuses at which the committee has already been notified (or is being notified):
    // members added / made reviewers from then on get their own email right away.
    public static final Set<String> COMMITTEE_STAGE_STATUSES = new Set<String>{
        'Committee Review', 'Chair/Co-Chair', 'Committee Shortlisting'
    };

    public class ReviewerResult implements Comparable {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Email;
        @AuraEnabled public String Phone;
        @AuraEnabled public String reviewerType;
        @AuraEnabled public String qualifyingDegree;
        @AuraEnabled public Integer matchCount;
        @AuraEnabled public String matchedKeywords;
        @AuraEnabled public Boolean isAlreadyMapped;

        public Integer compareTo(Object obj) {
            ReviewerResult other = (ReviewerResult) obj;
            if (this.isAlreadyMapped != other.isAlreadyMapped) {
                return this.isAlreadyMapped ? 1 : -1;
            }
            if (this.matchCount > other.matchCount) {
                return -1;
            }
            if (this.matchCount < other.matchCount) {
                return 1;
            }
            return this.Name.compareTo(other.Name);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ReviewerResult> getReviewerContacts(Id proposalId) {
        // Build the normalized list of proposal keywords from the proposal record.
        List<String> proposalKeywords = getProposalKeywords(proposalId);
        Boolean hasProposalKeywords = !proposalKeywords.isEmpty();

        // Identify reviewers already mapped to this proposal.
        Set<Id> mappedReviewerIds = new Set<Id>();
        if (proposalId != null) {
            for (Reviewer_Mapping__c existing : [
                SELECT Reviewer__c, Proposal__c, Proposal__r.Application_Stages__c
                FROM Reviewer_Mapping__c
                WHERE Proposal__c = :proposalId
            ]) {
                mappedReviewerIds.add(existing.Reviewer__c);
            }
        }

        List<Proposal__c> proposalList = [SELECT Id, Application_Stages__c FROM Proposal__c WHERE Id = :proposalId];

        String proposalApplicationStage;
        String reviewerType;

        if(! proposalList.isEmpty()){
            proposalApplicationStage = proposalList[0].Application_Stages__c;
        }

        if(proposalApplicationStage == 'Prelims'){
            reviewerType = 'Ex-Grantee';
        }

        if(proposalApplicationStage == 'Full'){
            reviewerType = 'Peer';
        }

        // Query all reviewers and their related keyword records.
        List<Reviewer__c> reviewerRecords = [
            SELECT
                Id, Title__c, First_Name__c, Last_Name__c, Mobile_Number__c, Alternate_Phone_Number__c,
                Designation__c, Department__c, Country__c, State_Province__c, City__c, Organisation__c,
                Email_Address__c, Reviewer_Type__c, Is_Active__c,
                (SELECT Keyword_Name__c FROM Keywords__r)
            FROM Reviewer__c
            WHERE Reviewer_Type__c = :reviewerType
            AND Is_Active__c = true
            LIMIT 1000
        ];

        // Score each reviewer and build a result for every reviewer.
        List<ReviewerResult> results = new List<ReviewerResult>();
        for (Reviewer__c reviewer : reviewerRecords) {
            Set<String> matchedKeywordNames = new Set<String>();

            // A reviewer keyword matches when it is a substring of a proposal keyword.
            // Comparison is case-insensitive.
            List<SObject> keywordRecords = reviewer.getSObjects('Keywords__r');
            if (keywordRecords != null) {
                for (SObject keywordRecord : keywordRecords) {
                    String keywordName = (String) keywordRecord.get('Keyword_Name__c');
                    if (String.isBlank(keywordName)) {
                        continue;
                    }
                    String reviewerKeyword = keywordName.toLowerCase();

                    for (String proposalKeyword : proposalKeywords) {
                        if (proposalKeyword.contains(reviewerKeyword)) {
                            matchedKeywordNames.add(keywordName);
                        }
                    }
                }
            }

            ReviewerResult result = new ReviewerResult();
            result.Id = reviewer.Id;
            result.Name = buildReviewerName(reviewer.First_Name__c, reviewer.Last_Name__c);
            result.Email = reviewer.Email_Address__c;
            result.Phone = reviewer.Mobile_Number__c;
            result.reviewerType = reviewer.Reviewer_Type__c;
            result.qualifyingDegree = '';
            result.isAlreadyMapped = mappedReviewerIds.contains(reviewer.Id);
            result.matchCount = matchedKeywordNames.size();
            // Produce a deterministic, comma-separated list of matched keywords for display.
            List<String> matchedList = new List<String>(matchedKeywordNames);
            matchedList.sort();
            result.matchedKeywords = String.join(matchedList, ', ');

            // Include all keyword-matched reviewers. Already-mapped reviewers are shown in the
            // component with disabled checkboxes so they cannot be re-selected.
            Boolean hasMatches = !matchedKeywordNames.isEmpty();
            if (hasMatches || !hasProposalKeywords) {
                results.add(result);
            }
        }

        // Rank results by number of matched keywords, then alphabetically by name.
        results.sort();
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static String getProposalApplicationStage(Id proposalId) {
        if (proposalId == null) {
            return null;
        }

        List<Proposal__c> proposals = [
            SELECT Application_Stages__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        return proposals.isEmpty() ? null : proposals[0].Application_Stages__c;
    }

    @AuraEnabled(cacheable=true)
    public static Integer getExistingReviewerCount(Id proposalId) {
        if (proposalId == null) {
            return 0;
        }

        List<Proposal__c> proposals = [
            SELECT Application_Stages__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        if (proposals.isEmpty()) {
            return 0;
        }

        String stage = proposals[0].Application_Stages__c;
        String reviewerType;
        if (stage == 'Prelims') {
            reviewerType = 'Ex-Grantee';
        } else if (stage == 'Full') {
            reviewerType = 'Peer';
        } else {
            return 0;
        }

        Integer existingCount = [
            SELECT COUNT()
            FROM Reviewer_Mapping__c
            WHERE Proposal__c = :proposalId AND Reviewer__r.Reviewer_Type__c = :reviewerType
        ];

        return existingCount;
    }

    private static List<String> getProposalKeywords(Id proposalId) {
        List<String> keywords = new List<String>();

        if (proposalId == null) {
            return keywords;
        }

        List<Proposal__c> proposals = [
            SELECT Keywords__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        if (proposals.isEmpty() || String.isBlank(proposals[0].Keywords__c)) {
            return keywords;
        }

        for (String keyword : proposals[0].Keywords__c.split(',')) {
            String normalized = keyword.trim().toLowerCase();
            if (String.isNotBlank(normalized)) {
                keywords.add(normalized);
            }
        }

        return keywords;
    }

    @AuraEnabled
    public static void createReviewerMappings(Id proposalId, List<Id> reviewerIds) {
        if (proposalId == null || reviewerIds == null || reviewerIds.isEmpty()) {
            throw new AuraHandledException('Proposal and at least one reviewer are required.');
        }

        List<Proposal__c> proposals = [
            SELECT Application_Stages__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        if (proposals.isEmpty()) {
            throw new AuraHandledException('Proposal not found.');
        }

        Integer minReviewers = 0;
        String expectedReviewerType = null;
        String stage = proposals[0].Application_Stages__c;
        if (stage == 'Prelims') {
            minReviewers = 2;
            expectedReviewerType = 'Ex-Grantee';
        } else if (stage == 'Full') {
            minReviewers = 3;
            expectedReviewerType = 'Peer';
        }

        // Guard: reject any selected reviewer whose Reviewer_Type__c doesn't match this
        // stage's expected type. getReviewerContacts already filters the picker so this
        // should never happen through the UI - but this method is @AuraEnabled and
        // therefore directly callable, so it must not just trust the client-supplied
        // reviewerIds. Only enforced for stages with a defined expected type (Prelims/Full).
        if (String.isNotBlank(expectedReviewerType)) {
            List<String> mismatchedNames = new List<String>();
            for (Reviewer__c reviewer : [
                SELECT Id, First_Name__c, Last_Name__c, Reviewer_Type__c
                FROM Reviewer__c
                WHERE Id IN :reviewerIds
                AND Reviewer_Type__c != :expectedReviewerType
            ]) {
                mismatchedNames.add(buildReviewerName(reviewer.First_Name__c, reviewer.Last_Name__c) + ' (' + reviewer.Reviewer_Type__c + ')');
            }
            if (!mismatchedNames.isEmpty()) {
                throw new AuraHandledException(
                    'The ' + stage + ' stage only accepts ' + expectedReviewerType + ' reviewers. '
                    + 'These selected reviewers are the wrong type: ' + String.join(mismatchedNames, ', ')
                );
            }
        }

        Boolean hasRequiredExistingReviewers = false;
        if (minReviewers > 0 && String.isNotBlank(expectedReviewerType)) {
            Integer existingCount = [
                SELECT COUNT()
                FROM Reviewer_Mapping__c
                WHERE Proposal__c = :proposalId AND Reviewer__r.Reviewer_Type__c = :expectedReviewerType
            ];
            hasRequiredExistingReviewers = existingCount >= minReviewers;
        }

        if (minReviewers > 0 && !hasRequiredExistingReviewers && reviewerIds.size() < minReviewers) {
            throw new AuraHandledException(
                'Please select at least ' + minReviewers + ' reviewers for the ' + stage + ' stage.'
            );
        }

        Set<Id> uniqueReviewerIds = new Set<Id>(reviewerIds);

        Set<Id> existingReviewerIds = new Set<Id>();
        for (Reviewer_Mapping__c existing : [
            SELECT Reviewer__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c = :proposalId AND Reviewer__c IN :uniqueReviewerIds
        ]) {
            existingReviewerIds.add(existing.Reviewer__c);
        }

        // Same reasoning as ProposalTriggerHandler.autoAssignReviewers - copy the reviewer's
        // own Organisation onto the mapping so ProposalReviewerController can compare it
        // against the applicant's organization without an extra join back to Reviewer__c.
        Map<Id, Reviewer__c> reviewersById = new Map<Id, Reviewer__c>([
            SELECT Id, Organisation__c
            FROM Reviewer__c
            WHERE Id IN :uniqueReviewerIds
        ]);

        List<Reviewer_Mapping__c> mappingsToInsert = new List<Reviewer_Mapping__c>();
        for (Id reviewerId : uniqueReviewerIds) {
            if (!existingReviewerIds.contains(reviewerId)) {
                Reviewer__c reviewer = reviewersById.get(reviewerId);
                mappingsToInsert.add(
                    new Reviewer_Mapping__c(
                        Proposal__c = proposalId,
                        Reviewer__c = reviewerId,
                        Status__c = 'Pending',
                        Application_Stages__c = stage,
                        Organization__c = reviewer != null ? reviewer.Organisation__c : null
                    )
                );
            }
        }

        if (!mappingsToInsert.isEmpty()) {
            try {
                insert mappingsToInsert;

                // Mirrors ProposalTriggerHandler.autoAssignReviewers's outcome for the
                // auto-assignment path, so a manual assignment through this component
                // (e.g. the "Needs Reviewer Assignment" flow on My Dashboard) advances
                // Proposal_Status__c the same way an automatic assignment would.
                // Bypass autoAssignReviewers while doing so - the reviewers here were
                // already hand-picked and inserted above, so its keyword-matching
                // 'manuallySetToPrelimReview' escape hatch must not re-run and auto-add
                // extra reviewers nobody selected.
                if (stage == 'Prelims' || stage == 'Full') {
                    ProposalTriggerHandler.bypassAutoAssignReviewers = true;
                    try {
                        update new Proposal__c(
                            Id = proposalId,
                            Proposal_Status__c = (stage == 'Prelims') ? 'Prelim Review' : 'Full Application'
                        );
                    } finally {
                        ProposalTriggerHandler.bypassAutoAssignReviewers = false;
                    }
                }

            } catch (DmlException e) {
                throw new AuraHandledException('Unable to create reviewer mappings: ' + e.getDmlMessage(0));
            }
        }
    }
    // Reviewer assignment emails moved to EmailNotificationQueueable.processReviewerMappingApproved -
    // the trigger point changed from "as soon as the Reviewer_Mapping__c is created" to "as soon
    // as the Grants Team approves the reviewer" (Grant_Member_Status__c becoming 'Approved'), and
    // running async means an email failure can no longer roll back the mapping creation itself.
    // See ReviewerMappingTriggerHandler.handleAfterUpdate for the new trigger point.

    private static String buildReviewerName(String firstName, String lastName) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(firstName)) {
            parts.add(firstName.trim());
        }
        if (String.isNotBlank(lastName)) {
            parts.add(lastName.trim());
        }
        return String.join(parts, ' ');
    }
    public static void sendCommitteeAssignmentEmails( List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap ) {
        if (newProposals == null || newProposals.isEmpty()) {
            return;
        }

        // ---------------------------------------------------------
        // 1. Identify proposals whose status CHANGED to Committee Review
        // ---------------------------------------------------------
        Set<Id> proposalIds = new Set<Id>();

        for (Proposal__c proposal : newProposals) {

            Proposal__c oldProposal = oldMap != null
                ? oldMap.get(proposal.Id)
                : null;

            if (
                proposal.Proposal_Status__c == 'Committee Review' &&
                oldProposal != null &&
                oldProposal.Proposal_Status__c != 'Committee Review' &&
                proposal.Yearly_Scheme__c != null
            ) {
                proposalIds.add(proposal.Id);
            }
        }

        if (proposalIds.isEmpty()) {
           System.debug('No proposals with status changed to Committee Review found.');
            return;
        }

        sendCommitteeEmails(proposalIds, null);
    }

    // Sends the committee assignment email for the given proposals. onlyProposalCommitteeIds
    // null = every Proposal_Committee__c member on those proposals (the Committee Review status
    // change); otherwise just those junction records (members added later from the Proposal
    // Committee screen).
    public static void sendCommitteeEmails(Set<Id> proposalIds, Set<Id> onlyProposalCommitteeIds) {
        // ---------------------------------------------------------
        // 2. Re-query Proposal
        //    Trigger.new does NOT contain relationship fields
        // ---------------------------------------------------------
        List<Proposal__c> proposals = [
            SELECT
                Id,
                Proposal_Status__c,
                Proposal_Id__c,
                Yearly_Scheme__c,
                Yearly_Scheme__r.Name,Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Proposal__c
            WHERE Id IN :proposalIds
        ];

        // ---------------------------------------------------------
        // 3. Get Email Template
        // ---------------------------------------------------------
        EmailTemplate committeeTemplate;

        try {

            committeeTemplate = [
                SELECT
                    Id,
                    DeveloperName,
                    Subject,
                    Body,
                    HtmlValue
                FROM EmailTemplate
                WHERE DeveloperName = 'New_Proposal_Assignment_commitee'
                AND IsActive = true
                LIMIT 1
            ];

        } catch (QueryException e) {

            System.debug(
                'Committee email template not found: ' +
                e.getMessage()
            );

            return;
        }

        // ---------------------------------------------------------
        // 4. Query every committee member on these proposals (every
        //    Proposal_Committee__c junction cloneCommitteeMember created,
        //    both round-robin-selected DCM reviewers and Chair/Co-chair) -
        //    no longer just the Committee_Reviewer__c = true subset.
        // ---------------------------------------------------------
        List<Proposal_Committee__c> assignedReviewers;
        if (onlyProposalCommitteeIds == null) {
            assignedReviewers = [
                SELECT
                    Proposal__c,
                    Committee_Member__r.First_Name__c, Committee_Member__r.Committee_Master__r.First_Name__c,
                    Committee_Member__r.Last_Name__c, Committee_Member__r.Committee_Master__r.Last_Name__c,
                    Committee_Member__r.Title__c, Committee_Member__r.Committee_Master__r.Title__c,
                    Committee_Member__r.Email__c, Committee_Member__r.Committee_Master__r.Email__c,
                    Committee_Member__r.Community_Member_UUID__c, Committee_Member__r.Committee_Master__r.Firebase_UID__c,
                    Committee_Member__r.Type__c, Committee_Reviewer__c
                FROM Proposal_Committee__c
                WHERE Proposal__c IN :proposalIds
                AND Committee_Member__r.Email__c != null
            ];
        } else {
            assignedReviewers = [
                SELECT
                    Proposal__c,
                    Committee_Member__r.First_Name__c, Committee_Member__r.Committee_Master__r.First_Name__c,
                    Committee_Member__r.Last_Name__c, Committee_Member__r.Committee_Master__r.Last_Name__c,
                    Committee_Member__r.Title__c, Committee_Member__r.Committee_Master__r.Title__c,
                    Committee_Member__r.Email__c, Committee_Member__r.Committee_Master__r.Email__c,
                    Committee_Member__r.Community_Member_UUID__c, Committee_Member__r.Committee_Master__r.Firebase_UID__c,
                    Committee_Member__r.Type__c, Committee_Reviewer__c
                FROM Proposal_Committee__c
                WHERE Proposal__c IN :proposalIds
                AND Id IN :onlyProposalCommitteeIds
                AND Committee_Member__r.Email__c != null
            ];
        }

        if (assignedReviewers.isEmpty()) {
            System.debug('No assigned reviewers found for these proposals.');
            return;
        }

        // ---------------------------------------------------------
        // 5. Group assigned reviewers by Proposal
        // ---------------------------------------------------------
        Map<Id, List<Proposal_Committee__c>> reviewersByProposal = new Map<Id, List<Proposal_Committee__c>>();

        for (Proposal_Committee__c pc : assignedReviewers) {

            if (!reviewersByProposal.containsKey(pc.Proposal__c)) {

                reviewersByProposal.put(
                    pc.Proposal__c,
                    new List<Proposal_Committee__c>()
                );
            }

            reviewersByProposal
                .get(pc.Proposal__c)
                .add(pc);
        }

        // ---------------------------------------------------------
        // 6. URLs
        // ---------------------------------------------------------
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }

        String baseURL = reactBaseUrl + 'reviewer_register_verifyemail';

        String loginURL = reactBaseUrl + 'login';

        // ---------------------------------------------------------
        // 8. Prepare emails
        // ---------------------------------------------------------
        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        for (Proposal__c proposal : proposals) {

            List<Proposal_Committee__c> reviewers =
                reviewersByProposal.get(proposal.Id);

            if (reviewers == null || reviewers.isEmpty()) {
                continue;
            }

            String proposalIdText =
                proposal.Proposal_Id__c == null
                    ? ''
                    : String.valueOf(proposal.Proposal_Id__c);

            String schemeName =
                proposal.Yearly_Scheme__r.Scheme_Items__r != null
                    ? proposal.Yearly_Scheme__r.Scheme_Items__r.Name
                    : '';

            // -----------------------------------------------------
            // 9. Send email to every committee member on this proposal
            // -----------------------------------------------------
            for (Proposal_Committee__c pc : reviewers) {

                Committee_Member__c member = pc.Committee_Member__r;
                Committee_Master__c master = member.Committee_Master__r;

                // Committee_Master__r is the deduped master identity record - when a member
                // is linked to one, its First_Name__c/Last_Name__c/Title__c/Email__c take
                // precedence over Committee_Member__r's own (per-scheme, possibly stale)
                // copies of the same fields; members with no linked master yet fall back to
                // their own fields as before.
                String firstName =
                    master != null && String.isNotBlank(master.First_Name__c)
                        ? master.First_Name__c
                        : (member.First_Name__c == null ? '' : member.First_Name__c);

                String lastName =
                    master != null && String.isNotBlank(master.Last_Name__c)
                        ? master.Last_Name__c
                        : (member.Last_Name__c == null ? '' : member.Last_Name__c);

                String title =
                    master != null && String.isNotBlank(master.Title__c)
                        ? master.Title__c
                        : (member.Title__c == null ? '' : member.Title__c);

                String emailAddress =
                    master != null && String.isNotBlank(master.Email__c)
                        ? master.Email__c
                        : member.Email__c;

                String type =
                    member.Type__c == null
                        ? ''
                        : member.Type__c;

                // Role is always Committee
                String role = 'Committee';

                // -------------------------------------------------
                // 10. Generate URL
                // -------------------------------------------------
                String personalizedURL;

                // Either UUID counts as "already registered" - a member can be identified by
                // their own Community_Member_UUID__c or, once linked, by their master
                // record's Firebase_UID__c.
                Boolean isAlreadyRegistered =
                    String.isNotBlank(member.Community_Member_UUID__c) ||
                    (master != null && String.isNotBlank(master.Firebase_UID__c));

                if (!isAlreadyRegistered) {

                    // New Committee Member
                    personalizedURL =
                        baseURL +
                        '?committeeMemberId=' +
                        EncodingUtil.urlEncode(
                            String.valueOf(master.Id),
                            'UTF-8'
                        ) +
                        '&title=' +
                        EncodingUtil.urlEncode(
                            title,
                            'UTF-8'
                        ) +
                        '&firstName=' +
                        EncodingUtil.urlEncode(
                            firstName,
                            'UTF-8'
                        ) +
                        '&lastName=' +
                        EncodingUtil.urlEncode(
                            lastName,
                            'UTF-8'
                        ) +
                        '&role=' +
                        EncodingUtil.urlEncode(
                            role,
                            'UTF-8'
                        ) +
                        '&email=' +
                        EncodingUtil.urlEncode(
                            emailAddress,
                            'UTF-8'
                        ) +
                        '&type=' +
                        EncodingUtil.urlEncode(
                            type,
                            'UTF-8'
                        );

                } else {

                    // Existing Committee Member
                    personalizedURL = loginURL;
                }

                System.debug(
                    'Committee Member Id: ' +
                    member.Id
                );

                System.debug(
                    'Committee Member Email: ' +
                    emailAddress
                );

                System.debug(
                    'Committee Member UUID: ' +
                    member.Community_Member_UUID__c
                );

                System.debug(
                    'Committee Login/Registration URL: ' +
                    personalizedURL
                );

                // -------------------------------------------------
                // 11. Get template body
                // -------------------------------------------------
                String emailHtml =
                    committeeTemplate.HtmlValue == null
                        ? ''
                        : committeeTemplate.HtmlValue;

                String emailText =
                    committeeTemplate.Body == null
                        ? ''
                        : committeeTemplate.Body;

                // -------------------------------------------------
                // 12. Replace URL - uses a fixed placeholder token, not the
                // literal reactBaseUrl, so this keeps working even if the
                // template is deployed to an org whose URL_s__mdt value
                // differs from wherever the template was authored.
                // -------------------------------------------------
                emailHtml = emailHtml.replace(
                    REVIEWER_PORTAL_URL_PLACEHOLDER,
                    personalizedURL
                );

                emailText = emailText.replace(
                    REVIEWER_PORTAL_URL_PLACEHOLDER,
                    personalizedURL
                );

                // -------------------------------------------------
                // 12b. Reviewer notice - bold line for Committee_Reviewer__c members,
                // removed (empty) for everyone else.
                Boolean isReviewer = pc.Committee_Reviewer__c == true;
                String reviewerNoticeHtml = isReviewer
                    ? '<p style="margin:0 0 16px 0;"><strong>You have been assigned as the Reviewer for proposal '
                        + proposalIdText + '.</strong></p>'
                    : '';
                String reviewerNoticeText = isReviewer
                    ? 'You have been assigned as the Reviewer for proposal ' + proposalIdText + '.'
                    : '';
                emailHtml = emailHtml.replace(REVIEWER_NOTICE_PLACEHOLDER, reviewerNoticeHtml);
                emailText = emailText.replace(REVIEWER_NOTICE_PLACEHOLDER, reviewerNoticeText);

                // -------------------------------------------------
                // 13. Replace Committee Member fields
                // -------------------------------------------------
                emailHtml = emailHtml.replace(
                    '{!Committee_Member__c.First_Name__c}',
                    firstName
                );

                emailHtml = emailHtml.replace(
                    '{!Committee_Member__c.Last_Name__c}',
                    lastName
                );

                emailText = emailText.replace(
                    '{!Committee_Member__c.First_Name__c}',
                    firstName
                );

                emailText = emailText.replace(
                    '{!Committee_Member__c.Last_Name__c}',
                    lastName
                );

                // -------------------------------------------------
                // 14. Replace Proposal Committee fields
                // -------------------------------------------------
                emailHtml = emailHtml.replace(
                    '{!Proposal_Committee__c.Proposal_ID_Text__c}',
                    proposalIdText
                );

                emailHtml = emailHtml.replace(
                    '{!Proposal_Committee__c.Scheme_Name__c}',
                    schemeName
                );

                emailText = emailText.replace(
                    '{!Proposal_Committee__c.Proposal_ID_Text__c}',
                    proposalIdText
                );

                emailText = emailText.replace(
                    '{!Proposal_Committee__c.Scheme_Name__c}',
                    schemeName
                );

                // -------------------------------------------------
                // 15. Create email
                // -------------------------------------------------
                Messaging.SingleEmailMessage email =
                    new Messaging.SingleEmailMessage();

                email.setToAddresses(
                    new List<String>{ emailAddress }
                );

                email.setSubject(
                    isReviewer ? REVIEWER_SUBJECT : committeeTemplate.Subject
                );

                email.setSaveAsActivity(false);

                email.setHtmlBody(emailHtml);

                email.setPlainTextBody(emailText);

                emails.add(email);
            }
        }

        // ---------------------------------------------------------
        // 16. Send emails
        // ---------------------------------------------------------
        if (!emails.isEmpty()) {

            try {

                Messaging.SendEmailResult[] results =
                    Messaging.sendEmail(emails, false);

                for (Integer i = 0; i < results.size(); i++) {

                    if (results[i].isSuccess()) {

                        System.debug(
                            'Committee email sent successfully: ' +
                            i
                        );

                    } else {

                        System.debug(
                            'Committee email failed: ' +
                            results[i].getErrors()
                        );
                    }
                }

            } catch (Exception e) {

                System.debug(
                    'Committee email sending failed: ' +
                    e.getMessage()
                );
            }
        }
    }
}


// public with sharing class ReviewerController {
//     public class ReviewerResult implements Comparable {
//         @AuraEnabled public Id Id;
//         @AuraEnabled public String Name;
//         @AuraEnabled public String Email;
//         @AuraEnabled public String Phone;
//         @AuraEnabled public String reviewerType;
//         @AuraEnabled public String qualifyingDegree;
//         @AuraEnabled public Integer matchCount;
//         @AuraEnabled public String matchedKeywords;
//         @AuraEnabled public Boolean isAlreadyMapped;

//         public Integer compareTo(Object obj) {
//             ReviewerResult other = (ReviewerResult) obj;
//             if (this.isAlreadyMapped != other.isAlreadyMapped) {
//                 return this.isAlreadyMapped ? 1 : -1;
//             }
//             if (this.matchCount > other.matchCount) {
//                 return -1;
//             }
//             if (this.matchCount < other.matchCount) {
//                 return 1;
//             }
//             return this.Name.compareTo(other.Name);
//         }
//     }

//     @AuraEnabled(cacheable=true)
//     public static List<ReviewerResult> getReviewerContacts(Id proposalId) {
//         // Build the normalized list of proposal keywords from the proposal record.
//         List<String> proposalKeywords = getProposalKeywords(proposalId);
//         Boolean hasProposalKeywords = !proposalKeywords.isEmpty();

//         // Identify reviewers already mapped to this proposal.
//         Set<Id> mappedReviewerIds = new Set<Id>();
//         if (proposalId != null) {
//             for (Reviewer_Mapping__c existing : [
//                 SELECT Reviewer__c
//                 FROM Reviewer_Mapping__c
//                 WHERE Proposal__c = :proposalId
//             ]) {
//                 mappedReviewerIds.add(existing.Reviewer__c);
//             }
//         }

//         List<Proposal__c> proposalList = [SELECT Id, Application_Stages__c FROM Proposal__c WHERE Id = :proposalId];

//         String proposalApplicationStage;
//         String reviewerType;

//         if(! proposalList.isEmpty()){
//             proposalApplicationStage = proposalList[0].Application_Stages__c;
//         }

//         if(proposalApplicationStage == 'Prelims'){
//             reviewerType = 'Ex-Grantee';
//         }

//         if(proposalApplicationStage == 'Full'){
//             reviewerType = 'International';
//         }

//         // Query all reviewers and their related keyword records.
//         List<Reviewer__c> reviewerRecords = [
//             SELECT
//                 Id, Title__c, First_Name__c, Last_Name__c, Mobile_Number__c, Alternate_Phone_Number__c,
//                 Designation__c, Department__c, Country__c, State_Province__c, City__c, Organisation__c,
//                 Email_Address__c, Reviewer_Type__c,
//                 (SELECT Keyword_Name__c FROM Keywords__r)
//             FROM Reviewer__c
//             WHERE Reviewer_Type__c = :reviewerType
//             LIMIT 1000
//         ];

//         // Score each reviewer and build a result for every reviewer.
//         List<ReviewerResult> results = new List<ReviewerResult>();
//         for (Reviewer__c reviewer : reviewerRecords) {
//             Set<String> matchedKeywordNames = new Set<String>();

//             // A reviewer keyword matches when it is a substring of a proposal keyword.
//             // Comparison is case-insensitive.
//             List<SObject> keywordRecords = reviewer.getSObjects('Keywords__r');
//             if (keywordRecords != null) {
//                 for (SObject keywordRecord : keywordRecords) {
//                     String keywordName = (String) keywordRecord.get('Keyword_Name__c');
//                     if (String.isBlank(keywordName)) {
//                         continue;
//                     }
//                     String reviewerKeyword = keywordName.toLowerCase();

//                     for (String proposalKeyword : proposalKeywords) {
//                         if (proposalKeyword.contains(reviewerKeyword)) {
//                             matchedKeywordNames.add(keywordName);
//                         }
//                     }
//                 }
//             }

//             ReviewerResult result = new ReviewerResult();
//             result.Id = reviewer.Id;
//             result.Name = buildReviewerName(reviewer.First_Name__c, reviewer.Last_Name__c);
//             result.Email = reviewer.Email_Address__c;
//             result.Phone = reviewer.Mobile_Number__c;
//             result.reviewerType = reviewer.Reviewer_Type__c;
//             result.qualifyingDegree = '';
//             result.isAlreadyMapped = mappedReviewerIds.contains(reviewer.Id);
//             result.matchCount = matchedKeywordNames.size();
//             // Produce a deterministic, comma-separated list of matched keywords for display.
//             List<String> matchedList = new List<String>(matchedKeywordNames);
//             matchedList.sort();
//             result.matchedKeywords = String.join(matchedList, ', ');

//             // Include all keyword-matched reviewers. Already-mapped reviewers are shown in the
//             // component with disabled checkboxes so they cannot be re-selected.
//             Boolean hasMatches = !matchedKeywordNames.isEmpty();
//             if (hasMatches || !hasProposalKeywords) {
//                 results.add(result);
//             }
//         }

//         // Rank results by number of matched keywords, then alphabetically by name.
//         results.sort();
//         return results;
//     }

//     private static List<String> getProposalKeywords(Id proposalId) {
//         List<String> keywords = new List<String>();

//         if (proposalId == null) {
//             return keywords;
//         }

//         List<Proposal__c> proposals = [
//             SELECT Keywords__c
//             FROM Proposal__c
//             WHERE Id = :proposalId
//             LIMIT 1
//         ];

//         if (proposals.isEmpty() || String.isBlank(proposals[0].Keywords__c)) {
//             return keywords;
//         }

//         for (String keyword : proposals[0].Keywords__c.split(',')) {
//             String normalized = keyword.trim().toLowerCase();
//             if (String.isNotBlank(normalized)) {
//                 keywords.add(normalized);
//             }
//         }

//         return keywords;
//     }

//     @AuraEnabled
//     public static void createReviewerMappings(Id proposalId, List<Id> reviewerIds) {
//         if (proposalId == null || reviewerIds == null || reviewerIds.isEmpty()) {
//             throw new AuraHandledException('Proposal and at least one reviewer are required.');
//         }

//         Set<Id> uniqueReviewerIds = new Set<Id>(reviewerIds);

//         Set<Id> existingReviewerIds = new Set<Id>();
//         for (Reviewer_Mapping__c existing : [
//             SELECT Reviewer__c
//             FROM Reviewer_Mapping__c
//             WHERE Proposal__c = :proposalId AND Reviewer__c IN :uniqueReviewerIds
//         ]) {
//             existingReviewerIds.add(existing.Reviewer__c);
//         }

//         List<Reviewer_Mapping__c> mappingsToInsert = new List<Reviewer_Mapping__c>();
//         for (Id reviewerId : uniqueReviewerIds) {
//             if (!existingReviewerIds.contains(reviewerId)) {
//                 mappingsToInsert.add(
//                     new Reviewer_Mapping__c(Proposal__c = proposalId, Reviewer__c = reviewerId, Status__c = 'Assigned')
//                 );
//             }
//         }

//         if (!mappingsToInsert.isEmpty()) {
//             try {
//                 insert mappingsToInsert;
//                 System.debug('------------------- mappings inserted successfully ----------------------');

//                 // Update Proposal Status to 'Prelim Review';
//                 Proposal__c prop = new Proposal__c(Id = proposalId);
//                 prop.Proposal_Status__c = 'Prelim Review';
//                 update prop;
                
//                 sendReviewerAssignmentEmails(mappingsToInsert);
//             } catch (DmlException e) {
//                 throw new AuraHandledException('Unable to create reviewer mappings: ' + e.getDmlMessage(0));
//             }
//         }
//     }

//     public static void sendReviewerAssignmentEmails(List<Reviewer_Mapping__c> mappings) {
//         if (mappings == null || mappings.isEmpty()) {
//             return;
//         }

//         EmailTemplate template;
//         try {
//             template = [SELECT Id, Subject, Body FROM EmailTemplate WHERE Id = '00XC3000001MYqT' AND IsActive = true LIMIT 1];
//         } catch (QueryException e) {
//             return;
//         }

//         String templateUrl = 'https://dbt-react-d198b.web.app/reviewer_register';
//         String baseURL = 'https://dbt-react-d198b.web.app/reviewer_register_verifyemail';

//         Set<Id> mappingIds = new Set<Id>();
//         for (Reviewer_Mapping__c mapping : mappings) {
//             if (mapping.Id != null) {
//                 mappingIds.add(mapping.Id);
//             }
//         }

//         List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
//         List<Id> mappingIdsByEmail = new List<Id>();
//         for (Reviewer_Mapping__c mapping : [
//             SELECT Id, Reviewer__r.Email_Address__c, Reviewer__r.Title__c, Reviewer__r.First_Name__c, Reviewer__r.Last_Name__c,
//                 Proposal__r.Proposal_Id__c, Scheme_Name__c, Reviewer__r.Firebase_UID__c
//             FROM Reviewer_Mapping__c
//             WHERE Id IN :mappingIds
//         ]) {
//             if (mapping.Reviewer__r == null || String.isBlank(mapping.Reviewer__r.Email_Address__c)) {
//                 continue;
//             }

//                 String personalizedURL;

//                 String emailBody = template.Body == null ? '' : template.Body;
//                 String reviewerId = mapping.Reviewer__r.Id == null ? '' : mapping.Reviewer__r.Id;
//                 String title = mapping.Reviewer__r.Title__c == null ? '' : mapping.Reviewer__r.Title__c;
//                 String firstName = mapping.Reviewer__r.First_Name__c == null ? '' : mapping.Reviewer__r.First_Name__c;
//                 String lastName = mapping.Reviewer__r.Last_Name__c == null ? '' : mapping.Reviewer__r.Last_Name__c;
//                 String emailAddress = mapping.Reviewer__r.Email_Address__c;
//                 String proposalIdText = mapping.Proposal__r.Proposal_Id__c == null ? '' : mapping.Proposal__r.Proposal_Id__c;
//                 String schemeName = mapping.Scheme_Name__c == null ? '' : mapping.Scheme_Name__c;

//                 if(mapping.Reviewer__r.Firebase_UID__c == null || mapping.Reviewer__r.Firebase_UID__c == ''){
//                     personalizedURL = baseURL +
//                         '?reviewerId=' + EncodingUtil.urlEncode(reviewerId, 'UTF-8') +
//                         '&title=' + EncodingUtil.urlEncode(title, 'UTF-8') +
//                         '&firstName=' + EncodingUtil.urlEncode(firstName, 'UTF-8') +
//                         '&lastName=' + EncodingUtil.urlEncode(lastName, 'UTF-8') +
//                         '&email=' + emailAddress;
//                 }
//                 else{
//                     personalizedURL = 'https://dbt-react-d198b.web.app/login';
//                 }

//                 emailBody = emailBody.replace(templateUrl, personalizedURL);
//                 emailBody = emailBody.replace('{!Reviewer__c.First_Name__c}', firstName);
//                 emailBody = emailBody.replace('{!Reviewer__c.Last_Name__c}', lastName);
//                 emailBody = emailBody.replace('{!Reviewer_Mapping__c.Proposal_ID_Text__c}', proposalIdText);
//                 emailBody = emailBody.replace('{!Reviewer_Mapping__c.Scheme_Name__c}', schemeName);
            
//             System.debug('Generated URL: ' + personalizedURL);

//             try {
//                 Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
//                 email.setToAddresses(new List<String>{ mapping.Reviewer__r.Email_Address__c });
//                 email.setSubject(template.Subject);
//                 email.setSaveAsActivity(false);
//                 email.setPlainTextBody(emailBody);
//                 emails.add(email);
//                 mappingIdsByEmail.add(mapping.Id);
//             } catch (Exception e) {
//                 System.debug('----------- Email Sent Failed -----------');
//                 throw new AuraHandledException('Unable to send email: ' + e.getMessage());
//             }
//         }

//         if (!emails.isEmpty()) {
//             try {
//                 Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(emails, false);
//                 List<Reviewer_Mapping__c> mappingsToUpdate = new List<Reviewer_Mapping__c>();
//                 Datetime sentTime = System.now();

//                 for (Integer index = 0; index < sendResults.size(); index++) {
//                     if (sendResults[index].isSuccess()) {
//                         mappingsToUpdate.add(new Reviewer_Mapping__c(
//                             Id = mappingIdsByEmail[index],
//                             Email_Sent_Time__c = sentTime
//                         ));
//                     }
//                 }

//                 if (!mappingsToUpdate.isEmpty()) {
//                     update mappingsToUpdate;
//                 }
//             } catch (Exception e) {
//                 System.debug('----------- Email Send Failed ------------');
//                 throw new AuraHandledException('Unable to send email: ' + e.getMessage());
//             }
//         }
//     }

//     private static String buildReviewerName(String firstName, String lastName) {
//         List<String> parts = new List<String>();
//         if (String.isNotBlank(firstName)) {
//             parts.add(firstName.trim());
//         }
//         if (String.isNotBlank(lastName)) {
//             parts.add(lastName.trim());
//         }
//         return String.join(parts, ' ');
//     }
// }