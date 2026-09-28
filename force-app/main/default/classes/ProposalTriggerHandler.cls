public without sharing class ProposalTriggerHandler {

    public static void generateProposalId(Set<Id> proposalIds) {

        List<Proposal__c> proposals = [SELECT Id,Name,Proposal_Id__c,Yearly_Scheme__r.Application_Stages__c,
										Yearly_Scheme__r.Year__r.Name,Yearly_Scheme__r.Scheme_Items__r.Name 
										FROM Proposal__c WHERE Id IN :proposalIds];

        List<Proposal__c> updates = new List<Proposal__c>();

        for (Proposal__c proposal : proposals) {
            if(proposal.Yearly_Scheme__r == null)
                continue;

            String schemeName = proposal.Yearly_Scheme__r.Scheme_Items__r.Name;
            String schemeCode = '';

            // Extract value inside []
            Integer startIndex = schemeName.indexOf('[');
			Integer endIndex = schemeName.indexOf(']');

			if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
				schemeCode = schemeName.substring(startIndex + 1, endIndex);
			}
            // P or F
            String stageCode = proposal.Yearly_Scheme__r.Application_Stages__c == 'Prelims' ? 'P' : 'F';
            // Last two digits of Year
            String yearCode = '';
            if(proposal.Yearly_Scheme__r.Year__r.Name != null &&
               proposal.Yearly_Scheme__r.Year__r.Name.length() >= 2){
                yearCode = proposal.Yearly_Scheme__r.Year__r.Name.right(2);
            }
            // PROP-00001 -> 00001
            String autoNumber = '';
            if(proposal.Name != null && proposal.Name.contains('-')){
                autoNumber = proposal.Name.substringAfter('-');
            }

            proposal.Proposal_Id__c = 'IA/BRCP/' + schemeCode + '/' + stageCode + '/' + yearCode + '/' + autoNumber;
            updates.add(proposal);
        }

        if(!updates.isEmpty()){
            update updates;
        }
    }

    // Method to update proposal ids to full when yearly scheme is updated to full
    public static void updateProposalIdsToFull(Set<Id> yearlySchemeIds){

        List<Proposal__c> proposals = [
            SELECT Id,
                   Proposal_Id__c, Proposal_Status__c, Application_Stages__c, Yearly_Scheme__c
            FROM Proposal__c
            WHERE Yearly_Scheme__c IN :yearlySchemeIds
            AND Proposal_Status__c = 'Draft'
            AND Application_Stages__c = 'Prelims'
        ];
    
        List<Proposal__c> updates = new List<Proposal__c>();
    
        for(Proposal__c proposal : proposals){
    
            if(String.isBlank(proposal.Proposal_Id__c)){
                continue;
            }

            if(proposal.Application_Stages__c == 'Full'){
                continue;
            }

            if(proposal.Proposal_Id__c.contains('/F/')){
                continue;
            }

            proposal.Old_Proposal_Id__c = proposal.Proposal_Id__c;
            proposal.Application_Stages__c = 'Full';
    
            if(proposal.Proposal_Id__c.contains('/P/')){
    
                proposal.Proposal_Id__c =  proposal.Proposal_Id__c.replace('/P/', '/F/');
    
                updates.add(proposal);
            }
    
        }
    
        if(!updates.isEmpty()){
            update updates;
        }
    
    }


    public static void cloneEligibilityChecklist(List<Proposal__c> newProposals) {

        // Step 1: Collect Yearly_Scheme__c Ids from the newly inserted Proposals
        Set<Id> yearlySchemeIds = new Set<Id>();
        for (Proposal__c prop : newProposals) {
            if (prop.Yearly_Scheme__c != null) {
                yearlySchemeIds.add(prop.Yearly_Scheme__c);
            }
        }
        if (yearlySchemeIds.isEmpty()) {
            return;
        }

        // Step 2: Query all Eligibility_Check_List__c records tied to those Yearly Schemes
        Map<Id, List<Eligibility_Check_List__c>> schemeToChecklists = new Map<Id, List<Eligibility_Check_List__c>>();
        for (Eligibility_Check_List__c ecl : [
            SELECT Id, Display_Question__c, Stage__c, Type__c, Yearly_Scheme__c, CurrencyIsoCode
            FROM Eligibility_Check_List__c
            WHERE Yearly_Scheme__c IN :yearlySchemeIds
        ]) {
            if (!schemeToChecklists.containsKey(ecl.Yearly_Scheme__c)) {
                schemeToChecklists.put(ecl.Yearly_Scheme__c, new List<Eligibility_Check_List__c>());
            }
            schemeToChecklists.get(ecl.Yearly_Scheme__c).add(ecl);
        }
        if (schemeToChecklists.isEmpty()) {
            return;
        }

        // Step 3: Build Proposal_Eligibility_Check_List__c records to insert
        List<Proposal_Eligibility_Check_List__c> newPeclList = new List<Proposal_Eligibility_Check_List__c>();
        for (Proposal__c prop : newProposals) {
            if (prop.Yearly_Scheme__c == null) {
                continue;
            }
            List<Eligibility_Check_List__c> checklistsForScheme = schemeToChecklists.get(prop.Yearly_Scheme__c);
            if (checklistsForScheme == null || checklistsForScheme.isEmpty()) {
                continue;
            }
            for (Eligibility_Check_List__c ecl : checklistsForScheme) {
                Proposal_Eligibility_Check_List__c pecl = new Proposal_Eligibility_Check_List__c();
                pecl.Proposal__c        = prop.Id;
                pecl.Display_Question__c = ecl.Display_Question__c;
                pecl.Stage__c           = ecl.Stage__c;
                pecl.Type__c            = ecl.Type__c;
                pecl.CurrencyIsoCode    = ecl.CurrencyIsoCode;
                newPeclList.add(pecl);
            }
        }
        // Step 4: Single bulk DML with savepoint/rollback
        if (!newPeclList.isEmpty()) {
            Savepoint sp = Database.setSavepoint();
            try {
                insert newPeclList;
            } catch (Exception e) {
                Database.rollback(sp);
                throw new AuraHandledException('Error cloning Eligibility Checklist: ' + e.getMessage());
            }
        }
    }

    // Fires at Proposal creation (after insert), one Grants_Team_Response__c per
    // Grants_Team_Members__c on the Proposal's Yearly Scheme - Grants Team Members are no
    // longer split by Application_Stages__c, so every member gets a single response covering
    // both stages: it carries the FULL set of Eligibility_Check_List__c items (both Prelims-
    // and Full-tagged) as its Grants_Team_Response_Item__c children, each item keeping its own
    // Stage__c so the response-entry UI can still show only the questions for whichever stage
    // the Proposal is currently at (see GrantTeamResponseItemsController).
    public static void createGrantsTeamResponses(List<Proposal__c> newProposals) {
        List<Proposal__c> proposalsToProcess = new List<Proposal__c>();
        for (Proposal__c prop : newProposals) {
            if (prop.Yearly_Scheme__c != null) {
                proposalsToProcess.add(prop);
            }
        }
        if (proposalsToProcess.isEmpty()) {
            return;
        }

        Set<Id> yearlySchemeIds = new Set<Id>();
        for (Proposal__c prop : proposalsToProcess) {
            yearlySchemeIds.add(prop.Yearly_Scheme__c);
        }

        Map<Id, List<Grants_Team_Members__c>> membersByScheme = new Map<Id, List<Grants_Team_Members__c>>();
        for (Grants_Team_Members__c member : [
            SELECT Id, Yearly_Scheme__c
            FROM Grants_Team_Members__c
            WHERE Yearly_Scheme__c IN :yearlySchemeIds
        ]) {
            if (!membersByScheme.containsKey(member.Yearly_Scheme__c)) {
                membersByScheme.put(member.Yearly_Scheme__c, new List<Grants_Team_Members__c>());
            }
            membersByScheme.get(member.Yearly_Scheme__c).add(member);
        }
        if (membersByScheme.isEmpty()) {
            return;
        }

        Map<Id, List<Eligibility_Check_List__c>> checklistsByScheme = new Map<Id, List<Eligibility_Check_List__c>>();
        for (Eligibility_Check_List__c ecl : [
            SELECT Id, Display_Question__c, Stage__c, Type__c, Yearly_Scheme__c
            FROM Eligibility_Check_List__c
            WHERE Yearly_Scheme__c IN :yearlySchemeIds
        ]) {
            if (!checklistsByScheme.containsKey(ecl.Yearly_Scheme__c)) {
                checklistsByScheme.put(ecl.Yearly_Scheme__c, new List<Eligibility_Check_List__c>());
            }
            checklistsByScheme.get(ecl.Yearly_Scheme__c).add(ecl);
        }
        if (checklistsByScheme.isEmpty()) {
            return;
        }

        List<Grants_Team_Response__c> responsesToInsert = new List<Grants_Team_Response__c>();
        Map<Integer, List<Eligibility_Check_List__c>> responseIndexToChecklists = new Map<Integer, List<Eligibility_Check_List__c>>();

        for (Proposal__c prop : proposalsToProcess) {
            List<Grants_Team_Members__c> members = membersByScheme.get(prop.Yearly_Scheme__c);
            List<Eligibility_Check_List__c> checklists = checklistsByScheme.get(prop.Yearly_Scheme__c);
            if (members == null || members.isEmpty() || checklists == null || checklists.isEmpty()) {
                continue;
            }

            for (Grants_Team_Members__c member : members) {
                responsesToInsert.add(new Grants_Team_Response__c(
                    Proposal__c = prop.Id,
                    Grants_Team_Members__c = member.Id,
                    Status__c = 'Pending',
                    Assigned_Date__c = System.today()
                ));
                responseIndexToChecklists.put(responsesToInsert.size() - 1, checklists);
            }
        }

        if (responsesToInsert.isEmpty()) {
            return;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            insert responsesToInsert;

            List<Grants_Team_Response_Item__c> itemsToInsert = new List<Grants_Team_Response_Item__c>();
            for (Integer i = 0; i < responsesToInsert.size(); i++) {
                Grants_Team_Response__c resp = responsesToInsert[i];
                List<Eligibility_Check_List__c> relevantChecklists = responseIndexToChecklists.get(i);
                if (relevantChecklists == null || relevantChecklists.isEmpty()) {
                    continue;
                }
                for (Eligibility_Check_List__c ecl : relevantChecklists) {
                    itemsToInsert.add(new Grants_Team_Response_Item__c(
                        Grants_Team_Response__c = resp.Id,
                        Eligibility_Check_List__c = ecl.Id,
                        Question__c = ecl.Display_Question__c,
                        Type__c = ecl.Type__c,
                        Stage__c = ecl.Stage__c
                    ));
                }
            }

            if (!itemsToInsert.isEmpty()) {
                insert itemsToInsert;
            }
            // Notify per actual assignment (one Grants_Team_Response__c = one member
            // assigned to one proposal), not per scheme - see sendNotifications() below.
            sendNotifications(responsesToInsert);
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error creating Grants Team Response records: ' + e.getMessage());
        }
    }

    // The Grants_Team_Response__c records themselves are now created at Proposal insert
    // (see createGrantsTeamResponses above), but Proposal_Status__c should still only reach
    // 'Eligibility Check' once the applicant actually submits - this is the standalone piece
    // of that old combined method, kept as its own after-update DML (not a before-update field
    // set) so sendSubmissionConfirmation still observes the real 'Submitted' value first.
    public static void advanceToEligibilityCheckOnSubmit(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldProposalMap) {
        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProposal = oldProposalMap != null ? oldProposalMap.get(prop.Id) : null;
            if (prop.Proposal_Status__c == 'Submitted' &&
                oldProposal != null &&
                oldProposal.Proposal_Status__c == 'Draft') {
                proposalsToUpdate.add(new Proposal__c(Id = prop.Id, Proposal_Status__c = 'Eligibility Check'));
            }
        }
        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }


    private static final String NOTIFICATION_TYPE_DEVELOPER_NAME = 'Bulk_Eligibility_Check_Alert';

    // Sends one notification per actual assignment - one Grants_Team_Response__c record
    // (a single member assigned to a single proposal) means one notification to that
    // member. A member assigned to 3 proposals (whether under the same scheme or
    // different schemes) gets 3 separate notifications, not one combined/deduped one.
    // Only called with already-inserted Grants_Team_Response__c records, so every
    // notification here corresponds to a real assignment - unlike the previous
    // scheme-level version, this can't notify someone about a proposal that was
    // actually skipped (e.g. scheme had members but no eligibility checklist).
    public static void sendNotifications(List<Grants_Team_Response__c> insertedResponses) {
        if (insertedResponses == null || insertedResponses.isEmpty()) {
            throw new AuraHandledException('No Grants Team Response records to notify.');
        }

        List<CustomNotificationType> notifTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_DEVELOPER_NAME
            LIMIT 1
        ];
        System.debug('notifTypes : ' + notifTypes);

        if (notifTypes.isEmpty()) {
            throw new AuraHandledException('Bulk Eligibility Check notification type is not configured.');
        }
        Id notificationTypeId = notifTypes[0].Id;
        System.debug('notificationTypeId : ' + notificationTypeId);

        Set<Id> proposalIds = new Set<Id>();
        Set<Id> memberIds = new Set<Id>();
        for (Grants_Team_Response__c resp : insertedResponses) {
            proposalIds.add(resp.Proposal__c);
            memberIds.add(resp.Grants_Team_Members__c);
        }
        System.debug('proposalIds : ' + proposalIds);
        System.debug('memberIds : ' + memberIds);

        Map<Id, Proposal__c> proposalsById = new Map<Id, Proposal__c>([
            SELECT Id, Proposal_Id__c
            FROM Proposal__c
            WHERE Id IN :proposalIds
        ]);
        System.debug('proposalsById : ' + proposalsById);

        Map<Id, Grants_Team_Members__c> membersById = new Map<Id, Grants_Team_Members__c>([
            SELECT Id, User__c
            FROM Grants_Team_Members__c
            WHERE Id IN :memberIds
            AND User__c != NULL
        ]);
        System.debug('membersById : ' + membersById);

        Integer notifiedCount = 0;
        for (Grants_Team_Response__c resp : insertedResponses) {
            Grants_Team_Members__c member = membersById.get(resp.Grants_Team_Members__c);
            if (member == null) {
                // Either the member record has no User__c, or wasn't found - nobody to notify.
                continue;
            }

            Proposal__c prop = proposalsById.get(resp.Proposal__c);
            String proposalIdC = (prop != null && String.isNotBlank(prop.Proposal_Id__c))
                ? prop.Proposal_Id__c
                : '';

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            // notification.setTitle('Eligibility Check Assigned.');
            notification.setTitle('New Proposal has been assigned to you ' + proposalIdC);
            notification.setBody('You have been assigned to review Proposal ' + proposalIdC + '.');
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(resp.Proposal__c);

            try {
                notification.send(new Set<String>{ member.User__c });
                notifiedCount++;
            } catch (Exception ex) {
                throw new AuraHandledException('Unable to send notification: ' + ex.getMessage());
            }
            System.debug('notifiedCount  : ' + notifiedCount);
        }

        if (notifiedCount == 0) {
            throw new AuraHandledException('No Grant Team Members found for the selected Proposals.');
        }
    }

    public static void sendSubmissionConfirmation(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldProposalMap) {
        Set<Id> proposalIdsToNotify = new Set<Id>();

        for (Proposal__c proposal : newProposals) {
            Proposal__c oldProposal = oldProposalMap.get(proposal.Id);
            if (proposal.Proposal_Status__c == 'Submitted' && oldProposal.Proposal_Status__c != 'Submitted') {
                proposalIdsToNotify.add(proposal.Id);
            }
        }

        if (proposalIdsToNotify.isEmpty()) {
            return;
        }

        List<Applicant_Proposal_Association__c> apasToNotify = [
            SELECT Id, Proposal__c, Contact__r.Id, Contact__r.Email
            FROM Applicant_Proposal_Association__c
            WHERE Proposal__c IN :proposalIdsToNotify AND Contact__r.Email != null
        ];

        if (apasToNotify.isEmpty()) {
            return;
        }

        EmailTemplate template = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = 'Proposal_Submission_Confirmation'
            LIMIT 1
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Applicant_Proposal_Association__c apa : apasToNotify) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTemplateId(template.Id);
            email.setTargetObjectId(apa.Contact__r.Id);
            email.setWhatId(apa.Proposal__c);
            email.setSaveAsActivity(false);
            emails.add(email);
        }

        Messaging.sendEmail(emails);
    }

    // Description: This method is used to autoassign the Reviewers as soon as:
    /*
    Runs when Eligible_For_Prelim__c or Eligible_For_Full__c changes to 'Eligible',
    OR when Proposal_Status__c is manually changed to 'Prelim Review' (lets a Grants
    Team member force this same assignment logic without going through the
    eligibility fields).
    Uses the same keyword matching logic as the Assign Reviewers component (reviewer keyword substring-matched against proposal keywords).
    If a proposal has no keywords, it skips that proposal entirely (no mappings, no emails).
    Skips reviewers that are already mapped to the proposal when looking for new matches.
    Enforces the minimum reviewer count: 2 for Prelims / 3 for Full - counting BOTH reviewers
    already mapped to the proposal from an earlier run AND newly keyword-matched reviewers
    together, so a proposal that already has enough reviewers assigned still gets its status
    updated even if this pass finds zero new matches (e.g. eligibility re-flips to 'Eligible'
    after reviewers were already assigned the first time).
    Creates Reviewer_Mapping__c records only for the newly matched reviewers, and updates
    Proposal_Status__c to 'Prelim Review' or 'Full Application' for every proposal that
    qualifies. Assignment emails are no longer sent from here - see
    ReviewerMappingTriggerHandler.handleAfterUpdate, which fires them once the Grants Team
    approves each reviewer.

    RECURSION GUARD: Step 6 below updates Proposal_Status__c to 'Prelim Review'/'Peer
    Review' as its own outcome. Since Proposal_Status__c == 'Prelim Review' is now also
    a trigger condition (see Step 1), that update would otherwise re-fire this same
    trigger and re-run this method on the same proposal a second time in the same
    transaction. recursionGuardProcessedProposalIds records every proposal Id already
    handled in this transaction so that second, self-triggered pass short-circuits
    immediately instead of redoing the matching work.
    */
    private static Set<Id> recursionGuardProcessedProposalIds = new Set<Id>();

    // Set true (and reset to false when done) by code that sets Proposal_Status__c to
    // 'Prelim Review' as the RESULT of an already-curated reviewer assignment (e.g.
    // ReviewerController.createReviewerMappings) rather than as a request for this method
    // to auto-match reviewers by keyword. Without this, the manuallySetToPrelimReview
    // escape hatch below re-runs keyword matching on that same status change and can
    // auto-add extra reviewers the Grants Team member never selected.
    public static Boolean bypassAutoAssignReviewers = false;

    public static void autoAssignReviewers(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (bypassAutoAssignReviewers) {
            return;
        }
        // Step 1: Find proposals whose Prelim/Full eligibility just changed to 'Eligible',
        // or whose Proposal_Status__c was just manually set to 'Prelim Review'.
        Map<Id, String> proposalIdToStage = new Map<Id, String>();
        for (Proposal__c prop : newProposals) {
            if (recursionGuardProcessedProposalIds.contains(prop.Id)) {
                continue;
            }
            Proposal__c oldProp = oldMap != null ? oldMap.get(prop.Id) : null;
            if (oldProp == null) {
                continue;
            }
            Boolean becamePrelimEligible = prop.Eligible_For_Prelim__c == 'Eligible' && oldProp.Eligible_For_Prelim__c != 'Eligible';
            Boolean manuallySetToPrelimReview = prop.Proposal_Status__c == 'Prelim Review' && oldProp.Proposal_Status__c != 'Prelim Review';
            // Reacts directly to Eligible_For_Full__c becoming 'Eligible' - GrantsTeamResponseHandler
            // has already set that field AND advanced Proposal_Status__c to 'Peer Review' as its own
            // outcome by this point, unconditionally, with no dependency on reviewer availability.
            // Step 6 below never writes Proposal_Status__c for the Full stage, so this can safely
            // react to the eligibility field without re-overwriting the status.
            Boolean becameFullEligible = prop.Eligible_For_Full__c == 'Eligible' && oldProp.Eligible_For_Full__c != 'Eligible';

            if (becamePrelimEligible || manuallySetToPrelimReview) {
                proposalIdToStage.put(prop.Id, 'Prelims');
            } else if (becameFullEligible) {
                proposalIdToStage.put(prop.Id, 'Full');
            }
        }
        if (proposalIdToStage.isEmpty()) {
            return;
        }
        // Mark these proposals as handled before any further processing, so the
        // Proposal_Status__c update in Step 6 (which re-fires this trigger) sees
        // them in recursionGuardProcessedProposalIds and skips straight past Step 1.
        recursionGuardProcessedProposalIds.addAll(proposalIdToStage.keySet());

        // Step 2: Fetch proposal keywords and determine reviewer type
        // ---- Previous version (kept for reference, do not remove) ----
        // Map<Id, List<String>> proposalKeywordsById = new Map<Id, List<String>>();
        // Set<String> requiredReviewerTypes = new Set<String>();
        // for (Proposal__c prop : [
        //     SELECT Id, Application_Stages__c, Keywords__c
        //     FROM Proposal__c
        //     WHERE Id IN :proposalIdToStage.keySet()
        // ]) {
        //     String stage = proposalIdToStage.get(prop.Id);
        //     String reviewerType = (stage == 'Prelims') ? 'Ex-Grantee' : 'Peer';
        //     requiredReviewerTypes.add(reviewerType);
        //
        //     List<String> keywords = new List<String>();
        //     if (String.isNotBlank(prop.Keywords__c)) {
        //         for (String kw : prop.Keywords__c.split(',')) {
        //             String normalized = kw.trim().toLowerCase();
        //             if (String.isNotBlank(normalized)) {
        //                 keywords.add(normalized);
        //             }
        //         }
        //     }
        //     proposalKeywordsById.put(prop.Id, keywords);
        // }
        // if (proposalKeywordsById.isEmpty()) {
        //     return;
        // }

        // ---- New version: also capture the proposal's Yearly_Scheme__c so Step 4 can
        // narrow the reviewer pool via Scheme_Reviewer__c instead of searching every
        // Reviewer__c org-wide. ----
        Map<Id, List<String>> proposalKeywordsById = new Map<Id, List<String>>();
        Map<Id, Id> proposalYearlySchemeById = new Map<Id, Id>();
        Set<String> requiredReviewerTypes = new Set<String>();
        for (Proposal__c prop : [
            SELECT Id, Application_Stages__c, Keywords__c, Yearly_Scheme__c
            FROM Proposal__c
            WHERE Id IN :proposalIdToStage.keySet()
        ]) {
            String stage = proposalIdToStage.get(prop.Id);
            String reviewerType = (stage == 'Prelims') ? 'Ex-Grantee' : 'Peer';
            requiredReviewerTypes.add(reviewerType);

            List<String> keywords = new List<String>();
            if (String.isNotBlank(prop.Keywords__c)) {
                for (String kw : prop.Keywords__c.split(',')) {
                    String normalized = kw.trim().toLowerCase();
                    if (String.isNotBlank(normalized)) {
                        keywords.add(normalized);
                    }
                }
            }
            proposalKeywordsById.put(prop.Id, keywords);
            proposalYearlySchemeById.put(prop.Id, prop.Yearly_Scheme__c);
        }
        if (proposalKeywordsById.isEmpty()) {
            return;
        }

        // Step 3: Fetch existing reviewer mappings to avoid duplicates
        Map<Id, Set<Id>> existingReviewerIdsByProposal = new Map<Id, Set<Id>>();
        for (Reviewer_Mapping__c existing : [
            SELECT Proposal__c, Reviewer__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c IN :proposalIdToStage.keySet()
        ]) {
            if (!existingReviewerIdsByProposal.containsKey(existing.Proposal__c)) {
                existingReviewerIdsByProposal.put(existing.Proposal__c, new Set<Id>());
            }
            existingReviewerIdsByProposal.get(existing.Proposal__c).add(existing.Reviewer__c);
        }

        // Step 4: Fetch reviewers and their keywords in bulk
        // ---- Previous version (kept for reference, do not remove) ----
        // Map<String, List<Reviewer__c>> reviewersByType = new Map<String, List<Reviewer__c>>();
        // for (Reviewer__c rev : [
        //     SELECT Id, First_Name__c, Last_Name__c, Email_Address__c, Reviewer_Type__c,
        //            (SELECT Keyword_Name__c FROM Keywords__r)
        //     FROM Reviewer__c
        //     WHERE Reviewer_Type__c IN :requiredReviewerTypes
        //     AND Email_Address__c != null
        // ]) {
        //     if (!reviewersByType.containsKey(rev.Reviewer_Type__c)) {
        //         reviewersByType.put(rev.Reviewer_Type__c, new List<Reviewer__c>());
        //     }
        //     reviewersByType.get(rev.Reviewer_Type__c).add(rev);
        // }

        // ---- New version: narrow candidates to reviewers explicitly linked to the
        // proposal's Yearly_Scheme__c via the Scheme_Reviewer__c junction (500+ reviewers
        // org-wide would otherwise all be keyword-matched; this scopes it down to just the
        // reviewers assigned to that scheme). The reviewer type is read from
        // Scheme_Reviewer__c.Type_of_Reviewer__c (the older Reviewer_Type__c picklist on that
        // object is being retired; not the master Reviewer__c either), since that's the record that
        // says what role this reviewer plays for this specific scheme. Keyed by
        // '<yearlySchemeId>::<type>' since different proposals in this batch can belong to
        // different schemes. ----
        Set<Id> yearlySchemeIds = new Set<Id>();
        for (Id schemeId : proposalYearlySchemeById.values()) {
            if (schemeId != null) {
                yearlySchemeIds.add(schemeId);
            }
        }

        // Required reviewer counts are configured per Yearly Scheme; blank falls back to the
        // defaults (Prelims 2, Full 3).
        Map<Id, Yearly_Schemes__c> schemeThresholdsById = new Map<Id, Yearly_Schemes__c>();
        if (!yearlySchemeIds.isEmpty()) {
            schemeThresholdsById = new Map<Id, Yearly_Schemes__c>([
                SELECT Id, Prelim_Reviewers_Required__c, Full_Reviewers_Required__c
                FROM Yearly_Schemes__c
                WHERE Id IN :yearlySchemeIds
            ]);
        }

        Map<String, Set<Id>> reviewerIdsBySchemeAndType = new Map<String, Set<Id>>();
        Set<Id> candidateReviewerIds = new Set<Id>();
        if (!yearlySchemeIds.isEmpty()) {
            for (Scheme_Reviewer__c sr : [
                SELECT Reviewer__c, Type_of_Reviewer__c, Yearly_Schemes__c
                FROM Scheme_Reviewer__c
                WHERE Yearly_Schemes__c IN :yearlySchemeIds
                AND Type_of_Reviewer__c IN :requiredReviewerTypes
                AND Reviewer__c != null
                AND Is_Active__c = true
            ]) {
                String key = sr.Yearly_Schemes__c + '::' + sr.Type_of_Reviewer__c;
                if (!reviewerIdsBySchemeAndType.containsKey(key)) {
                    reviewerIdsBySchemeAndType.put(key, new Set<Id>());
                }
                reviewerIdsBySchemeAndType.get(key).add(sr.Reviewer__c);
                candidateReviewerIds.add(sr.Reviewer__c);
            }
        }

        Map<Id, Reviewer__c> reviewersById = new Map<Id, Reviewer__c>();
        if (!candidateReviewerIds.isEmpty()) {
            for (Reviewer__c rev : [
                SELECT Id, First_Name__c, Last_Name__c, Email_Address__c, Reviewer_Type__c, Organisation__c,
                       (SELECT Keyword_Name__c FROM Keywords__r)
                FROM Reviewer__c
                WHERE Id IN :candidateReviewerIds
                AND Email_Address__c != null
                AND Is_Active__c = true
            ]) {
                reviewersById.put(rev.Id, rev);
            }
        }

        // Step 5: Match reviewers to each proposal based on keywords
        Map<Id, List<Id>> proposalToMatchedReviewerIds = new Map<Id, List<Id>>();
        // Proposals that qualify to move to the next status - either from newly matched
        // reviewers, or because they already have enough reviewers mapped from an earlier
        // pass (e.g. eligibility flips to 'Eligible' again after reviewers were already
        // assigned the first time, leaving zero *new* matches but still >= minRequired total).
        Set<Id> proposalIdsToUpdateStatus = new Set<Id>();
        Map<Id, Reviewer_Assignment_Logs__c> logByProposalId = new Map<Id, Reviewer_Assignment_Logs__c>();

        for (Id propId : proposalIdToStage.keySet()) {
            List<String> propKeywords = proposalKeywordsById.get(propId);
            if (propKeywords == null || propKeywords.isEmpty()) {
                // No proposal keywords means no automatic matching, but status still advances -
                // the Grants Team manually assigns reviewers from the relevant view.
                logByProposalId.put(propId, buildLog(propId, 'Skipped', 'No keywords defined on proposal'));
                proposalIdsToUpdateStatus.add(propId);
                continue;
            }
            String stage = proposalIdToStage.get(propId);
            String reviewerType = (stage == 'Prelims') ? 'Ex-Grantee' : 'Peer';
            // ---- Previous version (kept for reference, do not remove) ----
            // List<Reviewer__c> reviewers = reviewersByType.get(reviewerType);
            // if (reviewers == null || reviewers.isEmpty()) {
            //     logByProposalId.put(propId, buildLog(propId, 'Skipped', 'No active ' + reviewerType + ' reviewers found'));
            //     continue;
            // }

            // ---- New version: candidates are scoped to this proposal's Yearly_Scheme__c
            // via Scheme_Reviewer__c ----
            Id yearlyScheme = proposalYearlySchemeById.get(propId);
            if (yearlyScheme == null) {
                logByProposalId.put(propId, buildLog(propId, 'Skipped', 'No Yearly Scheme set on proposal'));
                proposalIdsToUpdateStatus.add(propId);
                continue;
            }
            Set<Id> schemeReviewerIds = reviewerIdsBySchemeAndType.get(yearlyScheme + '::' + reviewerType);
            if (schemeReviewerIds == null || schemeReviewerIds.isEmpty()) {
                logByProposalId.put(propId, buildLog(propId, 'Skipped', 'No ' + reviewerType + ' Scheme Reviewers found for this Yearly Scheme'));
                proposalIdsToUpdateStatus.add(propId);
                continue;
            }
            List<Reviewer__c> reviewers = new List<Reviewer__c>();
            for (Id schemeRevId : schemeReviewerIds) {
                Reviewer__c rev = reviewersById.get(schemeRevId);
                if (rev != null) {
                    reviewers.add(rev);
                }
            }
            if (reviewers.isEmpty()) {
                logByProposalId.put(propId, buildLog(propId, 'Skipped', 'No active ' + reviewerType + ' reviewers found'));
                proposalIdsToUpdateStatus.add(propId);
                continue;
            }
            Set<Id> existingIds = existingReviewerIdsByProposal.get(propId);
            if (existingIds == null) {
                existingIds = new Set<Id>();
            }
            List<Id> matchedIds = new List<Id>();
            for (Reviewer__c rev : reviewers) {
                if (existingIds.contains(rev.Id)) {
                    continue;
                }
                List<SObject> revKeywords = rev.getSObjects('Keywords__r');
                if (revKeywords == null || revKeywords.isEmpty()) {
                    continue;
                }
                for (SObject kwr : revKeywords) {
                    String keywordName = (String) kwr.get('Keyword_Name__c');
                    if (String.isBlank(keywordName)) {
                        continue;
                    }
                    String revKw = keywordName.toLowerCase();
                    Boolean isMatch = false;
                    for (String propKw : propKeywords) {
                        if (propKw.contains(revKw)) {
                            isMatch = true;
                            break;
                        }
                    }
                    if (isMatch) {
                        matchedIds.add(rev.Id);
                        break;
                    }
                }
            }
            // Reviewer count (minRequired) is informational only for both stages now - never a
            // gate. Whatever is matched gets created as a Reviewer_Mapping__c, and status always
            // advances regardless of outcome (Prelims here; Full/Peer's status was already set
            // independently by GrantsTeamResponseHandler before this method even runs). The
            // Grants Team manually assigns any still-missing reviewers from the relevant view.
            Yearly_Schemes__c schemeThresholds = schemeThresholdsById.get(yearlyScheme);
            Integer minRequired = (stage == 'Prelims') ? 2 : 3;
            if (schemeThresholds != null) {
                Decimal configured = (stage == 'Prelims')
                    ? schemeThresholds.Prelim_Reviewers_Required__c
                    : schemeThresholds.Full_Reviewers_Required__c;
                if (configured != null) {
                    minRequired = Integer.valueOf(configured);
                }
            }
            Integer alreadyMappedCount = existingIds.size();
            Integer totalReviewerCount = alreadyMappedCount + matchedIds.size();
            Boolean thresholdMet = totalReviewerCount >= minRequired;

            if (!matchedIds.isEmpty()) {
                proposalToMatchedReviewerIds.put(propId, matchedIds);
            }
            String outcome = thresholdMet ? 'Success' : 'Skipped';
            String outcomeMsg;
            if (matchedIds.isEmpty() && alreadyMappedCount == 0) {
                outcomeMsg = 'No ' + minRequired + ' required reviewers matched by keyword';
            } else {
                outcomeMsg = 'Auto-assigned ' + matchedIds.size() + ' reviewer(s)'
                    + (alreadyMappedCount > 0 ? ' (plus ' + alreadyMappedCount + ' already mapped)' : '')
                    + (thresholdMet ? '' : ' - below the required ' + minRequired);
            }
            logByProposalId.put(propId, buildLog(propId, outcome, outcomeMsg));

            proposalIdsToUpdateStatus.add(propId);
        }

        if (proposalIdsToUpdateStatus.isEmpty()) {
            insertAssignmentLogs(logByProposalId.values());
            return;
        }

        // Step 6: Create Reviewer Mapping records (only for newly matched reviewers) and
        // update proposal status (for every proposal that now qualifies, whether from new
        // matches, already-mapped reviewers, or a mix of both).
        List<Reviewer_Mapping__c> mappingsToInsert = new List<Reviewer_Mapping__c>();
        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();
        for (Id propId : proposalToMatchedReviewerIds.keySet()) {
            String stage = proposalIdToStage.get(propId);
            for (Id revId : proposalToMatchedReviewerIds.get(propId)) {
                Reviewer__c matchedReviewer = reviewersById.get(revId);
                mappingsToInsert.add(new Reviewer_Mapping__c(
                    Proposal__c = propId,
                    Reviewer__c = revId,
                    Status__c = 'Pending',
                    Application_Stages__c = stage,
                    // Copy the reviewer's own Organisation onto the mapping so
                    // ProposalReviewerController can compare it against the applicant's
                    // organization without an extra join back to Reviewer__c.
                    Organization__c = matchedReviewer != null ? matchedReviewer.Organisation__c : null
                ));
            }
        }
        for (Id propId : proposalIdsToUpdateStatus) {
            String stage = proposalIdToStage.get(propId);
            // Full stage: Proposal_Status__c is already 'Peer Review' (set by
            // GrantsTeamResponseHandler.updateProposalStatus before this method ever runs) -
            // leave it untouched here, only Prelims advances status as its own outcome.
            if (stage == 'Prelims') {
                proposalsToUpdate.add(new Proposal__c(Id = propId, Proposal_Status__c = 'Prelim Review'));
            }
        }

        Savepoint sp = Database.setSavepoint();
        try {
            if (!mappingsToInsert.isEmpty()) {
                insert mappingsToInsert;
            }
            if (!proposalsToUpdate.isEmpty()) {
                update proposalsToUpdate;
            }
            // Assignment emails no longer sent here - they now fire from
            // ReviewerMappingTriggerHandler.handleAfterUpdate as soon as the Grants Team
            // approves the reviewer (Grant_Member_Status__c becoming 'Approved'), via an
            // async EmailNotificationQueueable job.
        } catch (Exception e) {
            Database.rollback(sp);
            for (Proposal__c prop : newProposals) {
                if (proposalIdToStage.containsKey(prop.Id)) {
                    prop.addError('Error auto-assigning reviewers: ' + e.getMessage());
                }
            }
            // The insert rolled back, so overwrite the optimistic 'Success' outcome
            // for every proposal that was part of this failed attempt.
            for (Id propId : proposalIdsToUpdateStatus) {
                logByProposalId.put(propId, buildLog(propId, 'Failed', 'Error auto-assigning reviewers: ' + e.getMessage()));
            }
        }

        insertAssignmentLogs(logByProposalId.values());
    }

    private static Reviewer_Assignment_Logs__c buildLog(Id proposalId, String outcome, String reason) {
        return new Reviewer_Assignment_Logs__c(
            Proposal__c = proposalId,
            Outcome__c = outcome,
            Reason__c = reason
        );
    }

    private static void insertAssignmentLogs(List<Reviewer_Assignment_Logs__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        try {
            insert logs;
        } catch (Exception e) {
            // Logging must never break the actual assignment process.
            System.debug(LoggingLevel.ERROR, 'Failed to insert Reviewer_Assignment_Logs__c: ' + e.getMessage());
        }
    }
    public static void cloneCommitteeMember(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldProposalMap) {
        System.debug('newProposals====>>'+newProposals);
        System.debug('oldProposalMap====>>'+oldProposalMap);
        Set<Id> yearlySchemeIds = new Set<Id>();
    	Set<Id> proposalIds = new Set<Id>();
        for (Proposal__c proposal : newProposals) {
            Proposal__c oldProposal = oldProposalMap.get(proposal.Id);
            // Trigger point moved from 'Committee Review' to 'Peer Review' per request -
            // Proposal_Committee__c junctions now exist well before Committee Review itself,
            // but assignRoundRobinReviewers/sendCommitteeAssignmentEmails are unaffected:
            // both are independently gated on the 'Committee Review' transition and query
            // Proposal_Committee__c fresh, not relying on this method running in the same
            // transaction.
            if (proposal.Yearly_Scheme__c != null &&
             proposal.Proposal_Status__c =='Peer Review') {
                yearlySchemeIds.add(proposal.Yearly_Scheme__c);
                proposalIds.add(proposal.Id);
            }
        }
        System.debug('yearlySchemeIds====>>'+yearlySchemeIds);
        System.debug('proposalIds====>>'+proposalIds);
        if (yearlySchemeIds.isEmpty()) {
         System.debug('No Yearly Scheme Id Found Line 645');
            return;
        }
        List<Committee_Member__c> committeeMembers = [ SELECT Id, Yearly_Schemes__c,Type__c FROM Committee_Member__c WHERE Yearly_Schemes__c IN :yearlySchemeIds ];
 		System.debug('committeeMembers====>>'+committeeMembers);
        if (committeeMembers.isEmpty()) {
        System.debug('No committeeMembers Found');
             return;
        }
        Set<Id> committeeMemberIds = new Set<Id>();
        for (Committee_Member__c member : committeeMembers) {
            committeeMemberIds.add(member.Id);
        }
        System.debug('committeeMemberIds===>'+committeeMemberIds);
        Set<String> existingCombinations = new Set<String>();
		for (Proposal_Committee__c existing : [SELECT Id, Proposal__c, Committee_Member__c  FROM Proposal_Committee__c
                                               WHERE Proposal__c IN :proposalIds AND Committee_Member__c IN :committeeMemberIds ]) {
            existingCombinations.add( existing.Proposal__c + '-' + existing.Committee_Member__c );
        }
        List<Proposal_Committee__c> proposalCommittees =  new List<Proposal_Committee__c>();
         for (Proposal__c proposal : newProposals) {
                if (proposal.Yearly_Scheme__c == null || !yearlySchemeIds.contains(proposal.Yearly_Scheme__c)) {
                    continue;
                }
             for (Committee_Member__c member : committeeMembers) {
                if (member.Yearly_Schemes__c != proposal.Yearly_Scheme__c) {
                    continue;
                }
                String combination =  proposal.Id + '-' + member.Id;
                if (!existingCombinations.contains(combination)) {
                    proposalCommittees.add(
                        new Proposal_Committee__c(
                            Proposal__c = proposal.Id,
                            Committee_Member__c = member.Id,
                            Status__c = 'Assigned',
                            Type__c = member.Type__c,
                            Application_Stages__c = proposal.Application_Stages__c
                        )
                    );
                    existingCombinations.add(combination);
                }
            }
  		  }
        if (!proposalCommittees.isEmpty()) {
            insert proposalCommittees;
        }
    }

    // Round-robin assignment: for each Proposal that just moved into 'Committee Review',
    // pick the next Threshold__c committee members from the Yearly Scheme's ring
    // (ordered by Sequence__c) and mark their Proposal_Committee__c.Committee_Reviewer__c
    // true. Round_Robin_Pointer__c on the Yearly Scheme just keeps incrementing forever -
    // wraparound comes from applying "mod N" whenever it's read, so it never needs resetting.
    // Must run after cloneCommitteeMember() so the Proposal_Committee__c junction records
    // for this proposal already exist.
    // Every committee member (DCM, Chair and Co-chair alike) rotates through this ring and
    // can be picked as a reviewer.
    public static void assignRoundRobinReviewers(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldProposalMap) {
        // Step 1: only proposals that just transitioned into 'Committee Review'.
        Map<Id, Id> yearlySchemeIdByProposalId = new Map<Id, Id>();
        for (Proposal__c proposal : newProposals) {
            Proposal__c oldProposal = oldProposalMap != null ? oldProposalMap.get(proposal.Id) : null;
            Boolean justEnteredCommitteeReview =
                proposal.Proposal_Status__c == 'Committee Review' &&
                (oldProposal == null || oldProposal.Proposal_Status__c != 'Committee Review');
            if (justEnteredCommitteeReview && proposal.Yearly_Scheme__c != null) {
                yearlySchemeIdByProposalId.put(proposal.Id, proposal.Yearly_Scheme__c);
            }
        }
        if (yearlySchemeIdByProposalId.isEmpty()) {
            return;
        }

        // Step 2: lock the Yearly Scheme rows so concurrent transactions can't read
        // the same pointer value and double-assign the same members.
        Set<Id> yearlySchemeIds = new Set<Id>(yearlySchemeIdByProposalId.values());
        Map<Id, Yearly_Schemes__c> schemesById = new Map<Id, Yearly_Schemes__c>([
            SELECT Id, Round_Robin_Pointer__c, Threshold__c
            FROM Yearly_Schemes__c
            WHERE Id IN :yearlySchemeIds
            FOR UPDATE
        ]);

        // Step 3: committee ring per scheme, ordered by Sequence__c. All member types
        // (DCM, Chair, Co-chair) are part of the ring.
        Map<Id, List<Committee_Member__c>> ringByScheme = new Map<Id, List<Committee_Member__c>>();
        for (Committee_Member__c member : [
            SELECT Id, Yearly_Schemes__c, Sequence__c, Assignment_Count__c
            FROM Committee_Member__c
            WHERE Yearly_Schemes__c IN :yearlySchemeIds
            ORDER BY Sequence__c ASC NULLS LAST
        ]) {
            if (!ringByScheme.containsKey(member.Yearly_Schemes__c)) {
                ringByScheme.put(member.Yearly_Schemes__c, new List<Committee_Member__c>());
            }
            ringByScheme.get(member.Yearly_Schemes__c).add(member);
        }

        // Step 4: existing Proposal_Committee__c junctions for these proposals (created
        // by cloneCommitteeMember just before this method runs).
        Map<String, Proposal_Committee__c> proposalCommitteeByKey = new Map<String, Proposal_Committee__c>();
        for (Proposal_Committee__c pc : [
            SELECT Id, Proposal__c, Committee_Member__c, Committee_Reviewer__c
            FROM Proposal_Committee__c
            WHERE Proposal__c IN :yearlySchemeIdByProposalId.keySet()
        ]) {
            proposalCommitteeByKey.put(pc.Proposal__c + '-' + pc.Committee_Member__c, pc);
        }

        // Step 5: process proposals scheme-by-scheme, walking the pointer forward for
        // each one (in Trigger.new order) so a batch of proposals hitting Committee
        // Review together in the same transaction still get distinct, sequential picks.
        Map<Id, List<Proposal__c>> proposalsByScheme = new Map<Id, List<Proposal__c>>();
        for (Proposal__c proposal : newProposals) {
            Id schemeId = yearlySchemeIdByProposalId.get(proposal.Id);
            if (schemeId == null) {
                continue;
            }
            if (!proposalsByScheme.containsKey(schemeId)) {
                proposalsByScheme.put(schemeId, new List<Proposal__c>());
            }
            proposalsByScheme.get(schemeId).add(proposal);
        }

        List<Proposal_Committee__c> proposalCommitteesToUpdate = new List<Proposal_Committee__c>();
        Map<Id, Integer> assignmentCountIncrementByMemberId = new Map<Id, Integer>();
        List<Yearly_Schemes__c> schemesToUpdate = new List<Yearly_Schemes__c>();

        for (Id schemeId : proposalsByScheme.keySet()) {
            Yearly_Schemes__c scheme = schemesById.get(schemeId);
            List<Committee_Member__c> ring = ringByScheme.get(schemeId);
            if (scheme == null || ring == null || ring.isEmpty()) {
                continue; // nothing to assign against for this scheme
            }

            Integer n = ring.size();
            Integer threshold = scheme.Threshold__c == null ? 2 : Integer.valueOf(scheme.Threshold__c);
            Integer picksPerProposal = Math.min(threshold, n); // can't pick more distinct members than exist
            Integer pointer = scheme.Round_Robin_Pointer__c == null ? 0 : Integer.valueOf(scheme.Round_Robin_Pointer__c);

            for (Proposal__c proposal : proposalsByScheme.get(schemeId)) {
                Set<Integer> pickedIndexes = new Set<Integer>();
                Integer offset = 0;
                while (pickedIndexes.size() < picksPerProposal) {
                    Integer idx = Math.mod(pointer + offset, n);
                    pickedIndexes.add(idx);
                    offset++;
                }

                for (Integer idx : pickedIndexes) {
                    Committee_Member__c member = ring[idx];
                    String key = proposal.Id + '-' + member.Id;
                    Proposal_Committee__c pc = proposalCommitteeByKey.get(key);
                    if (pc == null) {
                        continue; // junction record should exist via cloneCommitteeMember; skip defensively if not
                    }
              
                    pc.Committee_Reviewer__c = true;
                    proposalCommitteesToUpdate.add(pc);

                    Integer currentIncrement = assignmentCountIncrementByMemberId.containsKey(member.Id)
                        ? assignmentCountIncrementByMemberId.get(member.Id)
                        : 0;
                    assignmentCountIncrementByMemberId.put(member.Id, currentIncrement + 1);
                }

                pointer += threshold; // always advance by the configured Threshold__c, even if picksPerProposal was capped
            }

            scheme.Round_Robin_Pointer__c = pointer;
            schemesToUpdate.add(scheme);
        }

        // Step 6: apply Assignment_Count__c increments.
        List<Committee_Member__c> membersToUpdate = new List<Committee_Member__c>();
        for (List<Committee_Member__c> ring : ringByScheme.values()) {
            for (Committee_Member__c member : ring) {
                if (assignmentCountIncrementByMemberId.containsKey(member.Id)) {
                    Integer current = member.Assignment_Count__c == null ? 0 : Integer.valueOf(member.Assignment_Count__c);
                    membersToUpdate.add(new Committee_Member__c(
                        Id = member.Id,
                        Assignment_Count__c = current + assignmentCountIncrementByMemberId.get(member.Id)
                    ));
                }
            }
        }

        Savepoint sp = Database.setSavepoint();
        try {
            if (!proposalCommitteesToUpdate.isEmpty()) {
                // sendCommitteeAssignmentEmails runs right after this and emails every member
                // (reviewers with the "assigned as the Reviewer" wording) - so the per-record
                // reviewer email on Committee_Reviewer__c false -> true must not also fire here.
                ProposalCommitteeTriggerHandler.suppressReviewerEmail = true;
                try {
                    update proposalCommitteesToUpdate;
                } finally {
                    ProposalCommitteeTriggerHandler.suppressReviewerEmail = false;
                }
            }
            if (!membersToUpdate.isEmpty()) {
                update membersToUpdate;
            }
            if (!schemesToUpdate.isEmpty()) {
                update schemesToUpdate;
            }
        } catch (Exception e) {
            Database.rollback(sp);
            for (Proposal__c proposal : newProposals) {
                if (yearlySchemeIdByProposalId.containsKey(proposal.Id)) {
                    proposal.addError('Error assigning round-robin committee reviewers: ' + e.getMessage());
                }
            }
        }
    }

    /*
     Advances Proposal_Status__c from 'Prelim Review' to 'Shortlisting' as soon as
     Prelim_Reviewer_Eligibility_Status__c changes to 'Submitted' - regardless of whether
     that field change came from ReviewerMappingTriggerHandler's reviewer-count automation
     or a manual edit directly on the Proposal. Same pattern as Eligible_For_Prelim__c
     driving Proposal_Status__c = 'Prelim Review' elsewhere in this class: the field that
     gets computed and the reaction to it changing live on separate triggers/objects.
     Only fires from 'Prelim Review' specifically, so it never overwrites a status that
     has already moved further along some other way.
    */
    public static void updateShortlistingStatus(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            Boolean becameReviewerEligible =
                prop.Prelim_Reviewer_Eligibility_Status__c == 'Submitted' &&
                oldProp.Prelim_Reviewer_Eligibility_Status__c != 'Submitted';
            if (becameReviewerEligible && prop.Proposal_Status__c == 'Prelim Review') {
                proposalsToUpdate.add(new Proposal__c(Id = prop.Id, Proposal_Status__c = 'Shortlisting'));
            }
        }
        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }

    /*
     Same pattern as updateShortlistingStatus above, for the Peer/Full side: advances
     Proposal_Status__c from 'Peer Review' to 'Peer Shortlisting' as soon as
     Peer_Reviewer_Eligibility_Status__c changes to 'Submitted' - regardless of whether that
     field change came from ReviewerMappingTriggerHandler's reviewer-count automation (3
     Full-stage Reviewer_Mapping__c submissions) or a manual edit directly on the Proposal.
     Only fires from 'Peer Review' specifically, so it never overwrites a status that has
     already moved further along some other way.
    */
    public static void updatePeerShortlistingStatus(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            Boolean becamePeerReviewerEligible =
                prop.Peer_Reviewer_Eligibility_Status__c == 'Submitted' &&
                oldProp.Peer_Reviewer_Eligibility_Status__c != 'Submitted';
            if (becamePeerReviewerEligible && prop.Proposal_Status__c == 'Peer Review') {
                proposalsToUpdate.add(new Proposal__c(Id = prop.Id, Proposal_Status__c = 'Peer Shortlisting'));
            }
        }
        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }

    /*
     Sends the Grants Team notification when Prelim_Reviewer_Eligibility_Status__c or
     Peer_Reviewer_Eligibility_Status__c transitions to 'Submitted' - reacting to the field
     change on the Proposal trigger itself (same pattern as updateShortlistingStatus just
     above) rather than living inside ReviewerMappingTriggerHandler's field-computation
     method, so it fires exactly once whether the change came from that automation's own
     update or a direct/manual edit to the field on the Proposal record.
    */
    public static void sendReviewerEligibilityNotifications(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }

        Map<Id, String> prelimProposalNumberById = new Map<Id, String>();
        Map<Id, String> peerProposalNumberById = new Map<Id, String>();

        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            if (prop.Prelim_Reviewer_Eligibility_Status__c == 'Submitted'
                && oldProp.Prelim_Reviewer_Eligibility_Status__c != 'Submitted') {
                prelimProposalNumberById.put(prop.Id, prop.Proposal_Id__c);
            }
            if (prop.Peer_Reviewer_Eligibility_Status__c == 'Submitted'
                && oldProp.Peer_Reviewer_Eligibility_Status__c != 'Submitted') {
                peerProposalNumberById.put(prop.Id, prop.Proposal_Id__c);
            }
        }

        if (prelimProposalNumberById.isEmpty() && peerProposalNumberById.isEmpty()) {
            return;
        }

        Set<Id> allProposalIds = new Set<Id>();
        allProposalIds.addAll(prelimProposalNumberById.keySet());
        allProposalIds.addAll(peerProposalNumberById.keySet());

        // Reviewer counts are only for the notification's wording - grouped by proposal +
        // stage in one bulkified aggregate query rather than per-proposal queries.
        Map<Id, Integer> prelimSubmittedCounts = new Map<Id, Integer>();
        Map<Id, Integer> fullSubmittedCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Proposal__c, Application_Stages__c, COUNT(Id) reviewerCount
            FROM Reviewer_Mapping__c
            WHERE Proposal__c IN :allProposalIds
            AND Application_Stages__c IN ('Prelims', 'Full')
            AND Status__c = 'Submitted'
            GROUP BY Proposal__c, Application_Stages__c
        ]) {
            Id propId = (Id) ar.get('Proposal__c');
            String stage = (String) ar.get('Application_Stages__c');
            Integer reviewerCount = (Integer) ar.get('reviewerCount');
            if (stage == 'Prelims') {
                prelimSubmittedCounts.put(propId, reviewerCount);
            } else if (stage == 'Full') {
                fullSubmittedCounts.put(propId, reviewerCount);
            }
        }

        for (Id propId : prelimProposalNumberById.keySet()) {
            Integer count = prelimSubmittedCounts.containsKey(propId) ? prelimSubmittedCounts.get(propId) : 0;
            ReviewerMappingNotificationService.sendEligibilitySubmittedNotification(
                propId,
                'Prelim Reviewer Eligibility Submitted',
                'Prelim reviewer eligibility for proposal ' + prelimProposalNumberById.get(propId)
                    + ' has been marked Submitted' + (count > 0 ? ' - ' + count + ' Prelim reviewer(s) have submitted their response.' : '.')
            );
        }

        for (Id propId : peerProposalNumberById.keySet()) {
            Integer count = fullSubmittedCounts.containsKey(propId) ? fullSubmittedCounts.get(propId) : 0;
            ReviewerMappingNotificationService.sendEligibilitySubmittedNotification(
                propId,
                'Peer Reviewer Eligibility Submitted',
                'Peer reviewer eligibility for proposal ' + peerProposalNumberById.get(propId)
                    + ' has been marked Submitted' + (count > 0 ? ' - ' + count + ' Peer reviewer(s) have submitted their response.' : '.')
            );
        }
    }

    /*
     Notifies the Grants Team (via Grants_Team_Response__c on this proposal, same audience
     and mechanism as sendReviewerEligibilityNotifications above) when Proposal_Status__c
     changes to 'Full Application'. Reacts to the field itself on the Proposal trigger, so it
     fires exactly once no matter which path set the status - autoAssignReviewers, the manual
     assignReviewers/ReviewerController.createReviewerMappings flow, or a direct/manual edit.
    */
    public static void sendFullApplicationNotifications(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            if (prop.Proposal_Status__c == 'Full Application' && oldProp.Proposal_Status__c != 'Full Application') {
                ReviewerMappingNotificationService.sendEligibilitySubmittedNotification(
                    prop.Id,
                    'Proposal Moved to Full Application',
                    'Proposal ' + prop.Proposal_Id__c + ' has moved to the Full Application stage.'
                );
            }
        }
    }

    /*
     Notifies the Applicant (not the Grants Team - see sendFullApplicationNotifications above)
     as soon as Proposal_Status__c transitions to 'Full Application', regardless of which path
     set it. Only enqueues the work here - EmailNotificationQueueable.processFullApplicationEligible
     does the actual Notification__c insert and the SES email send, since this runs in a trigger
     context which cannot perform the HTTP callout SESService needs synchronously (same reasoning
     as WOHI_CollaborationTriggerHandler.sendInvitationEmails).
    */
    public static void notifyApplicantOnFullApplicationEligibility(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        List<Id> proposalIds = new List<Id>();
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            if (prop.Proposal_Status__c == 'Full Application' && oldProp.Proposal_Status__c != 'Full Application') {
                proposalIds.add(prop.Id);
            }
        }
        if (proposalIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new EmailNotificationQueueable('FULL_APPLICATION_ELIGIBLE', proposalIds));
    }

    /*
     Notifies the Applicant (email only, via the Supervisor's name resolved from
     Proposal_Participant_Association__c where Roles__c = 'Supervisor') as soon as
     Peer_Application_Stage__c transitions to 'Final Submit' - regardless of which path set
     it. The recordIds passed to the queueable are Proposal__c Ids, not PPA Ids - the
     Supervisor lookup happens inside EmailNotificationQueueable.processSupervisorFullSubmission
     itself, since Peer_Application_Stage__c lives on the Proposal, not the participant.
    */
    public static void notifySupervisorFullSubmission(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        List<Id> proposalIds = new List<Id>();
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            if (prop.Peer_Application_Stage__c == 'Final Submit' && oldProp.Peer_Application_Stage__c != 'Final Submit') {
                proposalIds.add(prop.Id);
            }
        }
        if (proposalIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new EmailNotificationQueueable('SUPERVISOR_FULL_SUBMISSION', proposalIds));
    }

    /*
     Resets Peer_Application_Stage__c to 'Draft' and Application_Stages__c to 'Full' as soon as
     Proposal_Status__c transitions to 'Full Application', regardless of which path set the
     status - same "react to the field itself" reasoning as sendFullApplicationNotifications
     above. Runs in a before-update context so it sets the fields directly on Trigger.new
     without a separate DML/re-trigger.
    */
    public static void resetPeerApplicationStageOnFullApplication(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            if (prop.Proposal_Status__c == 'Full Application' && oldProp.Proposal_Status__c != 'Full Application') {
                prop.Peer_Application_Stage__c = 'Draft';
                prop.Application_Stages__c = 'Full';
            }
        }
    }

    /*
     Advances Proposal_Status__c to 'Peer Review' as soon as Eligible_For_Full__c changes to
     'Eligible', regardless of which path set it - GrantsTeamResponseHandler's consensus
     decision, or a direct/manual edit to the field on the Proposal record. Same "react to the
     field itself" reasoning as updateShortlistingStatus/resetPeerApplicationStageOnFullApplication
     above, so GrantsTeamResponseHandler no longer needs to set Proposal_Status__c itself.
     Skips proposals already at 'Peer Review' or 'Rejected' so a locked/rejected outcome is
     never resurrected. Runs in a before-update context so it sets the field directly on
     Trigger.new without a separate DML/re-trigger.
    */
    public static void advanceToPeerReviewOnFullEligible(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            if (prop.Eligible_For_Full__c == 'Eligible' && oldProp.Eligible_For_Full__c != 'Eligible'
                && prop.Proposal_Status__c != 'Peer Review' && prop.Proposal_Status__c != 'Rejected') {
                prop.Proposal_Status__c = 'Peer Review';
            }
        }
    }

    /*
     Advances Proposal_Status__c to 'Rejected' as soon as Eligible_For_Prelim__c changes to
     'Not Eligible' - same "react to the field itself" reasoning as
     advanceToPeerReviewOnFullEligible above, so it catches both GrantsTeamResponseHandler's
     consensus decision and a direct/manual edit to the field. Also auto-fills
     Reason_for_Rejection__c with a generic message when blank, since Reason_is_mandatory_when_
     stage_is_reject on Proposal__c requires it whenever Proposal_Status__c = 'Rejected', and the
     Prelim eligibility checklist has no free-text reason field of its own (unlike the manual
     "Reviewer Rating and Comments" modal, which already collects one). Runs in a before-update
     context so it sets the fields directly on Trigger.new without a separate DML/re-trigger.
    */
    public static void advanceToRejectedOnPrelimNotEligible(List<Proposal__c> newProposals, Map<Id, Proposal__c> oldMap) {
        if (oldMap == null) {
            return;
        }
        for (Proposal__c prop : newProposals) {
            Proposal__c oldProp = oldMap.get(prop.Id);
            if (oldProp == null) {
                continue;
            }
            if (prop.Eligible_For_Prelim__c == 'Not Eligible' && oldProp.Eligible_For_Prelim__c != 'Not Eligible'
                && prop.Proposal_Status__c != 'Rejected') {
                prop.Proposal_Status__c = 'Rejected';
                if (String.isBlank(prop.Reason_for_Rejection__c)) {
                    prop.Reason_for_Rejection__c = 'Rejected based on Grants Team Prelim eligibility check.';
                }
            }
        }
    }

}