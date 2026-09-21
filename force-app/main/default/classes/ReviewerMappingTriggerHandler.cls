/*
public without sharing class ReviewerMappingTriggerHandler {

    public static void createReviewerResponseLineItems(List<Reviewer_Mapping__c> reviewerMappings) {

        // Proposal Id -> Reviewer Mapping List
        Map<Id, List<Reviewer_Mapping__c>> proposalToReviewerMap = new Map<Id, List<Reviewer_Mapping__c>>();
        Set<Id> proposalIds = new Set<Id>();

        for (Reviewer_Mapping__c rm : reviewerMappings) {

            if (rm.Proposal__c == null)
                continue;

            proposalIds.add(rm.Proposal__c);

            if (!proposalToReviewerMap.containsKey(rm.Proposal__c)) {
                proposalToReviewerMap.put(rm.Proposal__c, new List<Reviewer_Mapping__c>());
            }

            proposalToReviewerMap.get(rm.Proposal__c).add(rm);
        }

        if (proposalIds.isEmpty()) {
            return;
        }

        // Get Proposal with Yearly Scheme
        Map<Id, Proposal__c> proposalMap = new Map<Id, Proposal__c>(
            [
                SELECT Id, Yearly_Scheme__c
                FROM Proposal__c
                WHERE Id IN :proposalIds
            ]
        );

        Set<Id> yearlySchemeIds = new Set<Id>();

        for (Proposal__c proposal : proposalMap.values()) {
            if (proposal.Yearly_Scheme__c != null) {
                yearlySchemeIds.add(proposal.Yearly_Scheme__c);
            }
        }

        if (yearlySchemeIds.isEmpty()) {
            return;
        }

        // Fetch all Question Items
        List<Scheme_Question_Items__c> questionItems = [
            SELECT Id,
                   Question__c,
                   Type__c,
                   Yearly_Scheme__c
                //    Is_Visible_To_Peer_Reviewer__c
            FROM Scheme_Question_Items__c
            WHERE Yearly_Scheme__c IN :yearlySchemeIds
        ];

        // Yearly Scheme -> Questions
        Map<Id, List<Scheme_Question_Items__c>> schemeQuestionMap = new Map<Id, List<Scheme_Question_Items__c>>();

        for (Scheme_Question_Items__c question : questionItems) {

            if (!schemeQuestionMap.containsKey(question.Yearly_Scheme__c)) {
                schemeQuestionMap.put(question.Yearly_Scheme__c, new List<Scheme_Question_Items__c>());
            }

            schemeQuestionMap.get(question.Yearly_Scheme__c).add(question);
        }

        List<Reviewer_Response_Line_Item__c> responseLines = new List<Reviewer_Response_Line_Item__c>();

        for (Id proposalId : proposalToReviewerMap.keySet()) {

            Proposal__c proposal = proposalMap.get(proposalId);

            if (proposal == null || proposal.Yearly_Scheme__c == null)
                continue;

            List<Scheme_Question_Items__c> questions = schemeQuestionMap.get(proposal.Yearly_Scheme__c);

            if (questions == null)
                continue;

            for (Reviewer_Mapping__c reviewer : proposalToReviewerMap.get(proposalId)) {

                for (Scheme_Question_Items__c question : questions) {

                    // Ex-Grantee -> Copy all questions
                    if (reviewer.Reviewer_Type__c == 'Ex-Grantee') {

                        responseLines.add(
                            new Reviewer_Response_Line_Item__c(
                                Reviewer_Mapping__c = reviewer.Id,
                                Question__c = question.Question__c
                                //Type__c = question.Type__c
                            )
                        );
                    }

                    // International -> Copy only Peer Reviewer questions
                    else if (
                        reviewer.Reviewer_Type__c == 'International' // && question.Is_Visible_To_Peer_Reviewer__c
                    ) {

                        responseLines.add(
                            new Reviewer_Response_Line_Item__c(
                                Reviewer_Mapping__c = reviewer.Id,
                                Question__c = question.Question__c
                                //Type__c = question.Type__c
                            )
                        );
                    }

                    // Other Reviewer Types -> Do Nothing
                }
            }
        }

        if (!responseLines.isEmpty()) {
            insert responseLines;
        }
    }
}
*/

public without sharing class ReviewerMappingTriggerHandler {
  
    /*latest one
    public static void createReviewerResponseLineItems(List<Reviewer_Mapping__c> reviewerMappings) {

        // Proposal Id -> Reviewer Mapping List
        Map<Id, List<Reviewer_Mapping__c>> proposalToReviewerMap = new Map<Id, List<Reviewer_Mapping__c>>();
        Set<Id> proposalIds = new Set<Id>();
        Set<Id> reviewerMappingIds = new Set<Id>();

        for (Reviewer_Mapping__c rm : reviewerMappings) {
            if (rm.Proposal__c == null)
                continue;
            proposalIds.add(rm.Proposal__c);
            reviewerMappingIds.add(rm.Id);
            if (!proposalToReviewerMap.containsKey(rm.Proposal__c)) {
                proposalToReviewerMap.put(rm.Proposal__c, new List<Reviewer_Mapping__c>());
            }
            proposalToReviewerMap.get(rm.Proposal__c).add(rm);
        }

        if (proposalIds.isEmpty()) {
            return;
        }

        // Get Proposal with Yearly Scheme
        // NOTE: assumes Proposal__c has an APA lookup (Applicant_Proposal_Association__c) - verify field API name against org schema
        Map<Id, Proposal__c> proposalMap = new Map<Id, Proposal__c>(
            [
                SELECT Id, Yearly_Scheme__c
                FROM Proposal__c
                WHERE Id IN :proposalIds
            ]
        );

        Set<Id> yearlySchemeIds = new Set<Id>();
        for (Proposal__c proposal : proposalMap.values()) {
            if (proposal.Yearly_Scheme__c != null) {
                yearlySchemeIds.add(proposal.Yearly_Scheme__c);
            }
        }

        // Fetch all Reviewer Question Templates for these Yearly Schemes
        Map<Id, List<Reviewer_Question_Template__c>> schemeQuestionMap = new Map<Id, List<Reviewer_Question_Template__c>>();
        if (!yearlySchemeIds.isEmpty()) {
            List<Reviewer_Question_Template__c> questionTemplates = [
                SELECT Id, Question__c, Is_Visible_To_Peer_Reviewer__c, Yearly_Schemes__c, Section__c, SL_No__c,Stage__c
                FROM Reviewer_Question_Template__c
                WHERE Yearly_Schemes__c IN :yearlySchemeIds
            ];

            for (Reviewer_Question_Template__c question : questionTemplates) {
                if (!schemeQuestionMap.containsKey(question.Yearly_Schemes__c)) {
                    schemeQuestionMap.put(question.Yearly_Schemes__c, new List<Reviewer_Question_Template__c>());
                }
                schemeQuestionMap.get(question.Yearly_Schemes__c).add(question);
            }
        }

        // Existing 'Documents' sections, so re-running this doesn't create duplicates
        Set<Id> reviewerMappingsWithDocsSection = new Set<Id>();
        if (!reviewerMappingIds.isEmpty()) {
            for (Scheme_Section__c existing : [
                SELECT Id, Reviewer_Mapping__c
                FROM Scheme_Section__c
                WHERE Reviewer_Mapping__c IN :reviewerMappingIds
                AND Section_Name__c = 'Documents'
            ]) {
                reviewerMappingsWithDocsSection.add(existing.Reviewer_Mapping__c);
            }
        }

        // ---------- PASS 1: Build Scheme_Section__c records (one per Reviewer Mapping + distinct Section) ----------

        List<Scheme_Section__c> schemeSectionsToInsert = new List<Scheme_Section__c>();

        // Key = ReviewerMappingId + '|' + SectionName -> index in schemeSectionsToInsert
        Map<String, Integer> sectionKeyToIndex = new Map<String, Integer>();

        for (Id proposalId : proposalToReviewerMap.keySet()) {

            Proposal__c proposal = proposalMap.get(proposalId);
            List<Reviewer_Question_Template__c> questions = (proposal != null && proposal.Yearly_Scheme__c != null)
                ? schemeQuestionMap.get(proposal.Yearly_Scheme__c)
                : null;

            for (Reviewer_Mapping__c reviewer : proposalToReviewerMap.get(proposalId)) {

                // Track which sections are needed for this reviewer, preserving first-seen order
                Set<String> sectionsNeeded = new Set<String>();

                if (questions != null) {
                    for (Reviewer_Question_Template__c question : questions) {

                        if (String.isBlank(question.Section__c))
                            continue;

                        Boolean include = false;

                        if (reviewer.Reviewer_Type__c == 'Ex-Grantee') {
                            include = true;
                        } else if (
                            reviewer.Reviewer_Type__c == 'Peer'
                            && question.Is_Visible_To_Peer_Reviewer__c
                        ) {
                            include = true;
                        }

                        if (!include)
                            continue;

                        sectionsNeeded.add(question.Section__c);
                    }
                }

                // Always ensure a 'Documents' section exists for this reviewer mapping
                if (!reviewerMappingsWithDocsSection.contains(reviewer.Id)) {
                    sectionsNeeded.add('Documents');
                }

                for (String sectionName : sectionsNeeded) {

                    String key = reviewer.Id + '|' + sectionName;

                    if (sectionKeyToIndex.containsKey(key))
                        continue;

                    schemeSectionsToInsert.add(
                        new Scheme_Section__c(
                            Reviewer_Mapping__c = reviewer.Id,
                            //Proposal__c = proposalId,
                            Section_Name__c = sectionName
                        )
                    );

                    sectionKeyToIndex.put(key, schemeSectionsToInsert.size() - 1);
                }
            }
        }

        if (schemeSectionsToInsert.isEmpty()) {
            return;
        }

        Savepoint sp = Database.setSavepoint();

        try {
            insert schemeSectionsToInsert;

            // ---------- PASS 2: Build Reviewer_Response_Line_Item__c records under each Scheme Section ----------
            // NOTE: 'Documents' sections intentionally get no line items here - they hold no
            // Reviewer_Question_Template__c-driven questions, only the section shell itself.

            List<Reviewer_Response_Line_Item__c> responseLines = new List<Reviewer_Response_Line_Item__c>();

            for (Id proposalId : proposalToReviewerMap.keySet()) {
                Proposal__c proposal = proposalMap.get(proposalId);
                if (proposal == null || proposal.Yearly_Scheme__c == null)
                    continue;

                List<Reviewer_Question_Template__c> questions = schemeQuestionMap.get(proposal.Yearly_Scheme__c);
                if (questions == null)
                    continue;

                for (Reviewer_Mapping__c reviewer : proposalToReviewerMap.get(proposalId)) {
                    for (Reviewer_Question_Template__c question : questions) {
                        if (String.isBlank(question.Section__c))
                            continue;

                        Boolean include = false;
                        if (reviewer.Reviewer_Type__c == 'Ex-Grantee') {
                            include = true;
                        } else if (
                            reviewer.Reviewer_Type__c == 'Peer'
                            && question.Is_Visible_To_Peer_Reviewer__c
                        ) {
                            include = true;
                        }
                        if (!include)
                            continue;

                        String key = reviewer.Id + '|' + question.Section__c;
                        Integer idx = sectionKeyToIndex.get(key);
                        if (idx == null)
                            continue; // should not happen, but guards against orphan line items

                        Id schemeSectionId = schemeSectionsToInsert[idx].Id;
                        responseLines.add(
                            new Reviewer_Response_Line_Item__c(
                                Reviewer_Mapping__c = reviewer.Id,
                                Scheme_Section__c = schemeSectionId,
                                Question__c = question.Question__c,
                                Section__c = question.Section__c,
                                SL_No__c = question.SL_No__c
                            )
                        );
                    }
                }
            }
            if (!responseLines.isEmpty()) {
                insert responseLines;
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }*/

    public static void createReviewerResponseLineItems(List<Reviewer_Mapping__c> reviewerMappings) {

        // Proposal Id -> Reviewer Mapping List
        Map<Id, List<Reviewer_Mapping__c>> proposalToReviewerMap = new Map<Id, List<Reviewer_Mapping__c>>();
        Set<Id> proposalIds = new Set<Id>();
        Set<Id> reviewerMappingIds = new Set<Id>();

        for (Reviewer_Mapping__c rm : reviewerMappings) {
            if (rm.Proposal__c == null)
                continue;
            proposalIds.add(rm.Proposal__c);
            reviewerMappingIds.add(rm.Id);
            if (!proposalToReviewerMap.containsKey(rm.Proposal__c)) {
                proposalToReviewerMap.put(rm.Proposal__c, new List<Reviewer_Mapping__c>());
            }
            proposalToReviewerMap.get(rm.Proposal__c).add(rm);
        }

        if (proposalIds.isEmpty()) {
            return;
        }

        // Get Proposal with Yearly Scheme
        // NOTE: assumes Proposal__c has an APA lookup (Applicant_Proposal_Association__c) - verify field API name against org schema
        Map<Id, Proposal__c> proposalMap = new Map<Id, Proposal__c>([SELECT Id, Yearly_Scheme__c FROM Proposal__c WHERE Id IN :proposalIds]);

        Set<Id> yearlySchemeIds = new Set<Id>();
        for (Proposal__c proposal : proposalMap.values()) {
            if (proposal.Yearly_Scheme__c != null) {
                yearlySchemeIds.add(proposal.Yearly_Scheme__c);
            }
        }

        // Fetch all Reviewer Question Templates for these Yearly Schemes
        Map<Id, List<Reviewer_Question_Template__c>> schemeQuestionMap = new Map<Id, List<Reviewer_Question_Template__c>>();
        if (!yearlySchemeIds.isEmpty()) {
            List<Reviewer_Question_Template__c> questionTemplates = [
                SELECT Id, Question__c, Is_Visible_To_Peer_Reviewer__c, Yearly_Schemes__c, Section__c, SL_No__c, Stage__c
                FROM Reviewer_Question_Template__c
                WHERE Yearly_Schemes__c IN :yearlySchemeIds
            ];

            for (Reviewer_Question_Template__c question : questionTemplates) {
                if (!schemeQuestionMap.containsKey(question.Yearly_Schemes__c)) {
                    schemeQuestionMap.put(question.Yearly_Schemes__c, new List<Reviewer_Question_Template__c>());
                }
                schemeQuestionMap.get(question.Yearly_Schemes__c).add(question);
            }
        }

        // Existing 'Documents' sections, so re-running this doesn't create duplicates
        // Now keyed by ReviewerMappingId + '|' + Application_Stages__c since Documents is per-stage too
        Set<String> reviewerMappingStagesWithDocsSection = new Set<String>();
        if (!reviewerMappingIds.isEmpty()) {
            for (Scheme_Section__c existing : [
                SELECT Id, Reviewer_Mapping__c, Application_Stages__c
                FROM Scheme_Section__c
                WHERE Reviewer_Mapping__c IN :reviewerMappingIds
                AND Section_Name__c = 'Documents'
            ]) {
                reviewerMappingStagesWithDocsSection.add(existing.Reviewer_Mapping__c + '|' + existing.Application_Stages__c);
            }
        }

        // ---------- PASS 1: Build Scheme_Section__c records (one per Reviewer Mapping + Section + Stage) ----------

        List<Scheme_Section__c> schemeSectionsToInsert = new List<Scheme_Section__c>();

        // Key = ReviewerMappingId + '|' + SectionName + '|' + Stage -> index in schemeSectionsToInsert
        Map<String, Integer> sectionKeyToIndex = new Map<String, Integer>();

        for (Id proposalId : proposalToReviewerMap.keySet()) {

            Proposal__c proposal = proposalMap.get(proposalId);
            List<Reviewer_Question_Template__c> questions = (proposal != null && proposal.Yearly_Scheme__c != null)
                ? schemeQuestionMap.get(proposal.Yearly_Scheme__c)
                : null;

            for (Reviewer_Mapping__c reviewer : proposalToReviewerMap.get(proposalId)) {

                // Track which section+stage combos are needed for this reviewer
                // Key = SectionName + '|' + Stage
                Set<String> sectionStagesNeeded = new Set<String>();

                // Track distinct stages this reviewer actually has questions for,
                // so we know which stage(s) need a 'Documents' section
                Set<String> stagesForReviewer = new Set<String>();

                if (questions != null) {
                    for (Reviewer_Question_Template__c question : questions) {
                        if (String.isBlank(question.Section__c))
                            continue;
                        Boolean include = false;

                        if (reviewer.Reviewer_Type__c == 'Ex-Grantee') {
                            include = true;
                        } else if (
                            reviewer.Reviewer_Type__c == 'Peer'
                            && question.Is_Visible_To_Peer_Reviewer__c
                        ) {
                            include = true;
                        }
                        if (!include)
                            continue;

                        String stage = question.Stage__c;
                        sectionStagesNeeded.add(question.Section__c + '|' + stage);
                        stagesForReviewer.add(stage);
                    }
                }

                // Ensure a 'Documents' section exists per stage for this reviewer mapping
                for (String stage : stagesForReviewer) {
                    String docsDedupeKey = reviewer.Id + '|' + stage;
                    if (!reviewerMappingStagesWithDocsSection.contains(docsDedupeKey)) {
                        sectionStagesNeeded.add('Documents' + '|' + stage);
                    }
                }

                for (String sectionStageKey : sectionStagesNeeded) {
                    // sectionStageKey = SectionName + '|' + Stage
                    List<String> parts = sectionStageKey.split('\\|', 2);
                    String sectionName = parts[0];
                    String stage = parts.size() > 1 ? parts[1] : null;

                    String key = reviewer.Id + '|' + sectionStageKey;

                    if (sectionKeyToIndex.containsKey(key))
                        continue;
                    schemeSectionsToInsert.add(
                        new Scheme_Section__c(
                            Reviewer_Mapping__c = reviewer.Id,
                            //Proposal__c = proposalId,
                            Section_Name__c = sectionName,
                            Application_Stages__c = stage
                        )
                    );
                    sectionKeyToIndex.put(key, schemeSectionsToInsert.size() - 1);
                }
            }
        }

        if (schemeSectionsToInsert.isEmpty()) {
            return;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            insert schemeSectionsToInsert;

            // ---------- PASS 2: Build Reviewer_Response_Line_Item__c records under each Scheme Section ----------
            // NOTE: 'Documents' sections intentionally get no line items here - they hold no
            // Reviewer_Question_Template__c-driven questions, only the section shell itself.
            
            List<Reviewer_Response_Line_Item__c> responseLines = new List<Reviewer_Response_Line_Item__c>();

            for (Id proposalId : proposalToReviewerMap.keySet()) {
                Proposal__c proposal = proposalMap.get(proposalId);
                if (proposal == null || proposal.Yearly_Scheme__c == null)
                    continue;

                List<Reviewer_Question_Template__c> questions = schemeQuestionMap.get(proposal.Yearly_Scheme__c);
                if (questions == null)
                    continue;

                for (Reviewer_Mapping__c reviewer : proposalToReviewerMap.get(proposalId)) {
                    for (Reviewer_Question_Template__c question : questions) {
                        if (String.isBlank(question.Section__c))
                            continue;

                        Boolean include = false;
                        if (reviewer.Reviewer_Type__c == 'Ex-Grantee') {
                            include = true;
                        } else if (
                            reviewer.Reviewer_Type__c == 'Peer'
                            && question.Is_Visible_To_Peer_Reviewer__c
                        ) {
                            include = true;
                        }
                        if (!include)
                            continue;

                        String stage = question.Stage__c;
                        String key = reviewer.Id + '|' + question.Section__c + '|' + stage;
                        Integer idx = sectionKeyToIndex.get(key);
                        if (idx == null)
                            continue; // should not happen, but guards against orphan line items

                        Id schemeSectionId = schemeSectionsToInsert[idx].Id;
                        responseLines.add(
                            new Reviewer_Response_Line_Item__c(
                                Reviewer_Mapping__c = reviewer.Id,
                                Scheme_Section__c = schemeSectionId,
                                Question__c = question.Question__c,
                                Section__c = question.Section__c,
                                SL_No__c = question.SL_No__c,
                                Application_Stages__c = stage
                            )
                        );
                    }
                }
            }
            if (!responseLines.isEmpty()) {
                insert responseLines;
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }



    public static void handleAfterUpdate(List<Reviewer_Mapping__c> newList,Map<Id, Reviewer_Mapping__c> oldMap) {

            List<Reviewer_Mapping__c> submittedRecords = new List<Reviewer_Mapping__c>();
            // Trigger point for the reviewer assignment email - fires once the Grants Team
            // approves the reviewer (Grant_Member_Status__c becoming 'Approved'), not at
            // Reviewer_Mapping__c creation. Reacts to the field itself, same "compute once,
            // react elsewhere" pattern used throughout this codebase, so it also catches a
            // direct/manual edit to the field, not just ProposalReviewerController.updateReviewerDecision.
            List<Id> justApprovedIds = new List<Id>();
            for(Reviewer_Mapping__c rm : newList){
                Reviewer_Mapping__c oldRec = oldMap.get(rm.Id);
                if(rm.Status__c == 'Submitted' && oldRec.Status__c != 'Submitted'){
                    submittedRecords.add(rm);
                }
                if (rm.Grant_Member_Status__c == 'Approved' && oldRec.Grant_Member_Status__c != 'Approved') {
                    justApprovedIds.add(rm.Id);
                }
            }
            if (!justApprovedIds.isEmpty()) {
                System.enqueueJob(new EmailNotificationQueueable('REVIEWER_MAPPING_APPROVED', justApprovedIds));
            }
            if(submittedRecords.isEmpty()){
                return;
            }
            ReviewerMappingNotificationService.process(submittedRecords);
            updateReviewerEligibilityStatus(submittedRecords);
    }

    /*
     Once at least this many Reviewer_Mapping__c records for a stage on a Proposal have
     Status__c = 'Submitted', the matching Prelim_Reviewer_Eligibility_Status__c /
     Peer_Reviewer_Eligibility_Status__c field on the Proposal is set to 'Submitted'. At the
     same moment, Prelim_Reviewers_Ratings__c / Peer_Reviewers_Ratings__c is set to the
     average of those same reviewers' Reviewer_Mapping__c.Overall_Score__c for that stage
     (nulls excluded) - mirrors the average shown live in reviewerRatingMatrix.js, but
     persisted on the Proposal for reporting once it's locked in.
     Only applies while the Proposal's own Application_Stages__c matches that same stage
     (so a Full-stage reviewer response never touches the Prelim fields and vice versa),
     and is locked once already 'Submitted' - never recomputed after that (so the ratings
     field is a snapshot as of the moment eligibility was decided, not a running average).

     This method ONLY sets those fields - it does not touch Proposal_Status__c.
     Advancing Proposal_Status__c to 'Shortlisting' once Prelim_Reviewer_Eligibility_Status__c
     is 'Submitted' is handled separately by ProposalTriggerHandler, reacting to that field
     change on the Proposal trigger itself - the same pattern already used for
     Eligible_For_Prelim__c -> 'Prelim Review'. Keeping "compute this field" and "react to
     this field changing" on their own triggers means the reaction also fires for a manual
     edit to the field, not just this automation.
    */
    private static final Integer PRELIMS_REQUIRED_REVIEWERS = 2;
    private static final Integer FULL_REQUIRED_REVIEWERS = 3;

    private static void updateReviewerEligibilityStatus(List<Reviewer_Mapping__c> justSubmitted) {
        Set<Id> proposalIds = new Set<Id>();
        for (Reviewer_Mapping__c rm : justSubmitted) {
            if (rm.Proposal__c != null && (rm.Application_Stages__c == 'Prelims' || rm.Application_Stages__c == 'Full')) {
                proposalIds.add(rm.Proposal__c);
            }
        }
        if (proposalIds.isEmpty()) {
            return;
        }

        Map<Id, Proposal__c> proposalsById = new Map<Id, Proposal__c>([
            SELECT Id, Application_Stages__c,
                   Prelim_Reviewer_Eligibility_Status__c, Peer_Reviewer_Eligibility_Status__c
            FROM Proposal__c
            WHERE Id IN :proposalIds
        ]);

        // Recount every Submitted Reviewer_Mapping__c per proposal/stage (not just the ones
        // in this trigger batch) so the threshold is based on the true current total. Also
        // sum Overall_Score__c per proposal/stage (skipping nulls) so the average rating can
        // be computed in the same pass - same reviewers, same query.
        Map<Id, Map<String, Integer>> submittedCountByProposalStage = new Map<Id, Map<String, Integer>>();
        Map<Id, Map<String, Decimal>> scoreSumByProposalStage = new Map<Id, Map<String, Decimal>>();
        Map<Id, Map<String, Integer>> scoreCountByProposalStage = new Map<Id, Map<String, Integer>>();
        for (Reviewer_Mapping__c rm : [
            SELECT Proposal__c, Application_Stages__c, Overall_Score__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c IN :proposalIds
            AND Application_Stages__c IN ('Prelims', 'Full')
            AND Status__c = 'Submitted'
        ]) {
            if (!submittedCountByProposalStage.containsKey(rm.Proposal__c)) {
                submittedCountByProposalStage.put(rm.Proposal__c, new Map<String, Integer>());
                scoreSumByProposalStage.put(rm.Proposal__c, new Map<String, Decimal>());
                scoreCountByProposalStage.put(rm.Proposal__c, new Map<String, Integer>());
            }
            Map<String, Integer> stageCounts = submittedCountByProposalStage.get(rm.Proposal__c);
            Integer currentCount = stageCounts.containsKey(rm.Application_Stages__c) ? stageCounts.get(rm.Application_Stages__c) : 0;
            stageCounts.put(rm.Application_Stages__c, currentCount + 1);

            if (rm.Overall_Score__c != null) {
                Map<String, Decimal> stageSums = scoreSumByProposalStage.get(rm.Proposal__c);
                Decimal currentSum = stageSums.containsKey(rm.Application_Stages__c) ? stageSums.get(rm.Application_Stages__c) : 0;
                stageSums.put(rm.Application_Stages__c, currentSum + rm.Overall_Score__c);

                Map<String, Integer> stageScoreCounts = scoreCountByProposalStage.get(rm.Proposal__c);
                Integer currentScoreCount = stageScoreCounts.containsKey(rm.Application_Stages__c) ? stageScoreCounts.get(rm.Application_Stages__c) : 0;
                stageScoreCounts.put(rm.Application_Stages__c, currentScoreCount + 1);
            }
        }

        // Notifying on eligibility becoming 'Submitted' is handled by
        // ProposalTriggerHandler.sendReviewerEligibilityNotifications, which reacts to the
        // Proposal field change itself (same pattern as updateShortlistingStatus) so it also
        // catches a direct/manual edit to the field, not just this automation's own updates -
        // and so it fires exactly once regardless of which path caused the change.
        List<Proposal__c> proposalsToUpdate = new List<Proposal__c>();

        for (Id proposalId : submittedCountByProposalStage.keySet()) {
            Proposal__c existing = proposalsById.get(proposalId);
            if (existing == null) {
                continue;
            }
            Map<String, Integer> stageCounts = submittedCountByProposalStage.get(proposalId);
            Proposal__c toUpdate = new Proposal__c(Id = proposalId);
            Boolean hasChange = false;

            Map<String, Decimal> scoreSums = scoreSumByProposalStage.get(proposalId);
            Map<String, Integer> scoreCounts = scoreCountByProposalStage.get(proposalId);

            Integer prelimCount = stageCounts.containsKey('Prelims') ? stageCounts.get('Prelims') : 0;
            if (existing.Application_Stages__c == 'Prelims'
                && existing.Prelim_Reviewer_Eligibility_Status__c != 'Submitted'
                && prelimCount >= PRELIMS_REQUIRED_REVIEWERS) {
                toUpdate.Prelim_Reviewer_Eligibility_Status__c = 'Submitted';
                hasChange = true;

                Integer prelimScoreCount = scoreCounts != null && scoreCounts.containsKey('Prelims') ? scoreCounts.get('Prelims') : 0;
                if (prelimScoreCount > 0) {
                    Decimal prelimScoreSum = scoreSums.get('Prelims');
                    toUpdate.Prelim_Reviewers_Ratings__c = (prelimScoreSum / prelimScoreCount).setScale(2, System.RoundingMode.HALF_UP);
                }
            }

            Integer fullCount = stageCounts.containsKey('Full') ? stageCounts.get('Full') : 0;
            if (existing.Application_Stages__c == 'Full'
                && existing.Peer_Reviewer_Eligibility_Status__c != 'Submitted'
                && fullCount >= FULL_REQUIRED_REVIEWERS) {
                toUpdate.Peer_Reviewer_Eligibility_Status__c = 'Submitted';
                hasChange = true;

                Integer fullScoreCount = scoreCounts != null && scoreCounts.containsKey('Full') ? scoreCounts.get('Full') : 0;
                if (fullScoreCount > 0) {
                    Decimal fullScoreSum = scoreSums.get('Full');
                    toUpdate.Peer_Reviewers_Ratings__c = (fullScoreSum / fullScoreCount).setScale(2, System.RoundingMode.HALF_UP);
                }
            }

            if (hasChange) {
                proposalsToUpdate.add(toUpdate);
            }
        }

        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }

}