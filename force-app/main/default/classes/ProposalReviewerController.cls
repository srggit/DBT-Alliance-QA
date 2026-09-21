/**
 * ---------------------------------------------------------------
 * Class Name      : ProposalReviewerController
 * Author          : Ram Kumar
 * Created Date    : Sep 8, 2026
 * Description     : Proposal Reviewer Assignment
 * ---------------------------------------------------------------
 */
public with sharing class ProposalReviewerController {

    private static final Integer PAGE_SIZE = 20;

    @AuraEnabled(cacheable=true)
    public static List<String> getSchemeNameOptions() {

        Set<String> names = new Set<String>();

        for (AggregateResult ar : [
            SELECT Yearly_Scheme__r.Scheme_Items__r.Name schemeName
            FROM Proposal__c
            WHERE Proposal_Status__c IN ('Prelim Review', 'Peer Review')
            GROUP BY Yearly_Scheme__r.Scheme_Items__r.Name
            ORDER BY Yearly_Scheme__r.Scheme_Items__r.Name ASC NULLS LAST
        ]) {
            String schemeName = (String) ar.get('schemeName');
            if (String.isNotBlank(schemeName)) {
                names.add(schemeName);
            }
        }

        List<String> sortedNames = new List<String>(names);
        sortedNames.sort();
        return sortedNames;
    }

    @AuraEnabled(cacheable=true)
    public static ProposalPage getProposals(
        String cursorId,
        String direction,
        String statusFilter,
        String schemeFilter
    ) {

        Boolean isPrevious = direction == 'PREV';

        // Blank filter -> ignored
        schemeFilter = String.isBlank(schemeFilter) ? null : schemeFilter;

        Integer pageSize = PAGE_SIZE;

        // Status predicate
        String statusClause;

        if (statusFilter == 'PRELIM') {
            statusClause = 'Proposal_Status__c = \'Prelim Review\'';
        }
        else if (statusFilter == 'PEER') {
            statusClause = 'Proposal_Status__c = \'Peer Review\'';
        }
        else {
            statusClause = 'Proposal_Status__c IN (\'Prelim Review\', \'Peer Review\')';
        }

        // Optional Scheme Item name filter
        String schemeClause = schemeFilter == null
            ? ''
            : ' AND Yearly_Scheme__r.Scheme_Items__r.Name = :schemeFilter';

        // Cursor / direction
        String cursorClause = '';

        if (String.isNotBlank(cursorId)) {
            cursorClause = isPrevious ? ' AND Id < :cursorId' : ' AND Id > :cursorId';
        }

        String orderDir = isPrevious ? 'DESC' : 'ASC';

        String recordQuery =
            'SELECT Id, Proposal_Id__c, Proposal_Status__c, Yearly_Scheme__r.Scheme_Items__r.Name ' +
            'FROM Proposal__c ' +
            'WHERE ' + statusClause + schemeClause + cursorClause + ' ' +
            'ORDER BY Id ' + orderDir + ' ' +
            'LIMIT :pageSize';

        List<Proposal__c> proposals = Database.query(recordQuery);

        if (isPrevious) {
            List<Proposal__c> reversedProposals = new List<Proposal__c>();
            for (Integer i = proposals.size() - 1; i >= 0; i--) {
                reversedProposals.add(proposals[i]);
            }
            proposals = reversedProposals;
        }

        String countQuery =
            'SELECT COUNT() FROM Proposal__c WHERE ' + statusClause + schemeClause;

        Integer totalRecords = Database.countQuery(countQuery);

        if (proposals.isEmpty()) {
            return new ProposalPage(
                new List<ProposalRow>(),
                totalRecords,
                calculateTotalPages(totalRecords),
                false,
                false,
                null,
                null
            );
        }

        Set<Id> proposalIds = new Set<Id>();
        for (Proposal__c proposal : proposals) {
            proposalIds.add(proposal.Id);
        }

        List<Applicant_Proposal_Association__c> applicantAssociations = [
            SELECT Id, Proposal__c, Contact__r.Name, Contact__r.AccountId, Contact__r.Account.Name, Is_Coordinator__c
            FROM Applicant_Proposal_Association__c
            WHERE Proposal__c IN :proposalIds
            AND Is_Coordinator__c = true
        ];

        Map<Id, String> applicantByProposal = new Map<Id, String>();
        Map<Id, String> applicantOrganizationByProposal = new Map<Id, String>();
        // Account Id behind the Applicant Organization column - used only to detect a
        // reviewer/applicant organization conflict, never displayed itself.
        Map<Id, Id> applicantOrganizationIdByProposal = new Map<Id, Id>();
        for (Applicant_Proposal_Association__c association : applicantAssociations) {
            if (!applicantByProposal.containsKey(association.Proposal__c)) {
                applicantByProposal.put(
                    association.Proposal__c,
                    association.Contact__r != null ? association.Contact__r.Name : ''
                );
                applicantOrganizationByProposal.put(
                    association.Proposal__c,
                    association.Contact__r != null &&
                    association.Contact__r.Account != null
                        ? association.Contact__r.Account.Name
                        : ''
                );
                applicantOrganizationIdByProposal.put(
                    association.Proposal__c,
                    association.Contact__r != null ? association.Contact__r.AccountId : null
                );
            }
        }

        // MAIN TABLE BUSINESS RULE: Prelim Review -> Ex-Grantee, Peer Review -> Peer

        List<Reviewer_Mapping__c> reviewerMappings = [
            SELECT Id, Proposal__c, Reviewer_Name__c, Reviewer_Type__c, Organization__c, Organization__r.Name, Status__c, Grant_Member_Status__c, Conflict_Reason__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c IN :proposalIds
            AND Reviewer_Type__c IN ('Ex-Grantee', 'Peer')
        ];

        Map<Id, List<Reviewer_Mapping__c>> reviewersByProposal = new Map<Id, List<Reviewer_Mapping__c>>();

        for (Reviewer_Mapping__c reviewer : reviewerMappings) {
            if (!reviewersByProposal.containsKey(reviewer.Proposal__c)) {
                reviewersByProposal.put(reviewer.Proposal__c, new List<Reviewer_Mapping__c>());
            }
            reviewersByProposal.get(reviewer.Proposal__c).add(reviewer);
        }

        List<ProposalRow> rows = new List<ProposalRow>();

        for (Proposal__c proposal : proposals) {

            String expectedReviewerType;

            if (proposal.Proposal_Status__c == 'Prelim Review') {
                expectedReviewerType = 'Ex-Grantee';
            }
            else {
                expectedReviewerType = 'Peer';
            }

            List<Reviewer_Mapping__c> proposalReviewers = reviewersByProposal.get(proposal.Id);

            List<ReviewerDetail> reviewerDetails = new List<ReviewerDetail>();
            Id applicantOrgId = applicantOrganizationIdByProposal.get(proposal.Id);

            if (proposalReviewers != null) {

                for (Reviewer_Mapping__c reviewer : proposalReviewers) {

                    if (reviewer.Reviewer_Type__c != expectedReviewerType) {
                        continue;
                    }

                    String decision = 'Pending';

                    if (reviewer.Grant_Member_Status__c == 'Approved') {
                        decision = 'Approved';
                    }
                    else if (reviewer.Grant_Member_Status__c == 'Conflict') {
                        decision = 'Conflict';
                    }

                    // Organization conflict: the reviewer's Organization__c (Account) is
                    // the same Account as the applicant's - compared by Id, not Name.
                    Boolean hasOrganizationConflict =
                        reviewer.Organization__c != null &&
                        applicantOrgId != null &&
                        reviewer.Organization__c == applicantOrgId;

                    reviewerDetails.add(
                        new ReviewerDetail(
                            reviewer.Id,
                            reviewer.Reviewer_Name__c,
                            reviewer.Organization__r != null ? reviewer.Organization__r.Name : '',
                            decision,
                            reviewer.Conflict_Reason__c,
                            hasOrganizationConflict
                        )
                    );

                }

            }

            String schemeName = '';

            if (proposal.Yearly_Scheme__r != null && proposal.Yearly_Scheme__r.Scheme_Items__r != null) {
                schemeName = proposal.Yearly_Scheme__r.Scheme_Items__r.Name;
            }

            rows.add(
                new ProposalRow(
                    proposal.Id,
                    proposal.Proposal_Id__c,
                    applicantByProposal.get(proposal.Id),
                    applicantOrganizationByProposal.get(proposal.Id),
                    schemeName,
                    proposal.Proposal_Status__c,
                    reviewerDetails
                )
            );

        }

        Integer totalPages = calculateTotalPages(totalRecords);

        return new ProposalPage(
            rows,
            totalRecords,
            totalPages,
            !isPrevious && String.isNotBlank(proposals[proposals.size() - 1].Id),
            String.isNotBlank(cursorId),
            String.valueOf(proposals[0].Id),
            String.valueOf(proposals[proposals.size() - 1].Id)
        );

    }

    /*
     * POPUP PAGINATION IS HANDLED HERE. PAGE SIZE = 20
     * Directions: FIRST, NEXT, PREV, LAST
     */
    @AuraEnabled(cacheable=true)
    public static ReviewerPage getAvailableReviewers(
        Id proposalId,
        String nameSearch,
        String emailSearch,
        String cursorId,
        String direction
    ) {

        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }

        Proposal__c proposal = [
            SELECT Id, Proposal_Status__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        // Popup reviewer type: Prelim Review -> Ex-Grantee, Peer Review -> Peer

        String reviewerType;

        if (proposal.Proposal_Status__c == 'Prelim Review') {
            reviewerType = 'Ex-Grantee';
        }
        else if (proposal.Proposal_Status__c == 'Peer Review') {
            reviewerType = 'Peer';
        }
        else {
            throw new AuraHandledException('Reviewers cannot be added for this proposal status.');
        }

        // Existing mappings - prevent duplicate reviewer assignments

        Set<Id> existingReviewerIds = new Set<Id>();

        for (Reviewer_Mapping__c mapping : [
            SELECT Reviewer__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c = :proposalId
            AND Reviewer__c != null
        ]) {
            existingReviewerIds.add(mapping.Reviewer__c);
        }

        String namePattern;
        String emailPattern;

        if (String.isNotBlank(nameSearch)) {
            namePattern = '%' + String.escapeSingleQuotes(nameSearch.trim()) + '%';
        }

        if (String.isNotBlank(emailSearch)) {
            emailPattern = '%' + String.escapeSingleQuotes(emailSearch.trim()) + '%';
        }

        String whereClause = ' WHERE Reviewer_Type__c = :reviewerType ';

        // Existing reviewers should not appear

        if (!existingReviewerIds.isEmpty()) {
            whereClause += ' AND Id NOT IN :existingReviewerIds ';
        }

        // Name search: First Name OR Last Name

        if (String.isNotBlank(nameSearch)) {
            whereClause += ' AND (First_Name__c LIKE :namePattern ' +
                ' OR Last_Name__c LIKE :namePattern) ';
        }

        if (String.isNotBlank(emailSearch)) {
            whereClause += ' AND Email_Address__c LIKE :emailPattern ';
        }

        String countQuery =
            'SELECT COUNT() ' +
            'FROM Reviewer__c ' +
            whereClause;

        Integer totalRecords = Database.countQuery(countQuery);

        Integer totalPages = calculateTotalPages(totalRecords);

        String reviewerQuery =
            'SELECT ' +
                'Id, ' +
                'First_Name__c, ' +
                'Last_Name__c, ' +
                'Email_Address__c, ' +
                'Organisation__r.Name, ' +
                'Reviewer_Type__c ' +
            'FROM Reviewer__c ' +
            whereClause;

        String normalizedDirection = String.isBlank(direction) ? 'FIRST' : direction;

        List<Reviewer__c> reviewers;

        if (normalizedDirection == 'FIRST') {

            reviewerQuery += ' ORDER BY Id ASC LIMIT :PAGE_SIZE ';

            reviewers = Database.query(reviewerQuery);

        }
        else if (normalizedDirection == 'NEXT') {

            if (String.isNotBlank(cursorId)) {
                reviewerQuery += ' AND Id > :cursorId ';
            }

            reviewerQuery += ' ORDER BY Id ASC LIMIT :PAGE_SIZE ';

            reviewers = Database.query(reviewerQuery);

        }
        else if (normalizedDirection == 'PREV') {

            if (String.isBlank(cursorId)) {

                reviewerQuery += ' ORDER BY Id ASC LIMIT :PAGE_SIZE ';
                reviewers = Database.query(reviewerQuery);

            }
            else {

                reviewerQuery += ' AND Id < :cursorId ';
                reviewerQuery += ' ORDER BY Id DESC LIMIT :PAGE_SIZE ';
                reviewers = Database.query(reviewerQuery);

                // Reverse so UI remains ASC

                List<Reviewer__c> reversed = new List<Reviewer__c>();

                for (Integer i = reviewers.size() - 1; i >= 0; i--) {
                    reversed.add(reviewers[i]);
                }

                reviewers = reversed;

            }

        }
        else if (normalizedDirection == 'LAST') {

            reviewerQuery += ' ORDER BY Id DESC LIMIT :PAGE_SIZE ';

            reviewers = Database.query(reviewerQuery);

            // Reverse for ASC display

            List<Reviewer__c> reversed = new List<Reviewer__c>();

            for (Integer i = reviewers.size() - 1; i >= 0; i--) {
                reversed.add(reviewers[i]);
            }

            reviewers = reversed;

        }
        else {
            throw new AuraHandledException('Invalid reviewer pagination direction.');
        }

        List<ReviewerRow> rows = new List<ReviewerRow>();

        for (Reviewer__c reviewer : reviewers) {

            String fullName = '';

            if (String.isNotBlank(reviewer.First_Name__c)) {
                fullName += reviewer.First_Name__c;
            }

            if (String.isNotBlank(reviewer.Last_Name__c)) {
                if (String.isNotBlank(fullName)) {
                    fullName += ' ';
                }
                fullName += reviewer.Last_Name__c;
            }

            rows.add(
                new ReviewerRow(
                    reviewer.Id,
                    fullName,
                    reviewer.Email_Address__c,
                    reviewer.Reviewer_Type__c,
                    reviewer.Organisation__r != null ? reviewer.Organisation__r.Name : ''
                )
            );

        }

        String firstCursor;
        String lastCursor;

        if (!reviewers.isEmpty()) {
            firstCursor = String.valueOf(reviewers[0].Id);
            lastCursor = String.valueOf(reviewers[reviewers.size() - 1].Id);
        }

        return new ReviewerPage(
            rows,
            totalRecords,
            totalPages,
            String.isNotBlank(cursorId),
            rows.size() == PAGE_SIZE,
            firstCursor,
            lastCursor
        );

    }

    @AuraEnabled
    public static void addReviewersToProposal(
        Id proposalId,
        List<Id> reviewerIds
    ) {

        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }

        if (reviewerIds == null || reviewerIds.isEmpty()) {
            throw new AuraHandledException('Please select at least one reviewer.');
        }

        Proposal__c proposal = [
            SELECT Id, Proposal_Status__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        // Popup business rule: Prelim Review -> Ex-Grantee, Peer Review -> Peer

        String reviewerType;

        if (proposal.Proposal_Status__c == 'Prelim Review') {
            reviewerType = 'Ex-Grantee';
        }
        else if (proposal.Proposal_Status__c == 'Peer Review') {
            reviewerType = 'Peer';
        }
        else {
            throw new AuraHandledException('Reviewers cannot be added for this proposal status.');
        }

        Set<Id> existingReviewerIds = new Set<Id>();

        for (Reviewer_Mapping__c mapping : [
            SELECT Reviewer__c
            FROM Reviewer_Mapping__c
            WHERE Proposal__c = :proposalId
            AND Reviewer__c IN :reviewerIds
        ]) {
            if (mapping.Reviewer__c != null) {
                existingReviewerIds.add(mapping.Reviewer__c);
            }
        }

        List<Reviewer__c> selectedReviewers = [
            SELECT Id, First_Name__c, Last_Name__c, Email_Address__c, Reviewer_Type__c, Organisation__c
            FROM Reviewer__c
            WHERE Id IN :reviewerIds
        ];

        if (selectedReviewers.isEmpty()) {
            throw new AuraHandledException('Selected reviewers were not found.');
        }

        List<Reviewer_Mapping__c> mappingsToInsert = new List<Reviewer_Mapping__c>();

        for (Reviewer__c reviewer : selectedReviewers) {

            // Prevent duplicate

            if (existingReviewerIds.contains(reviewer.Id)) {
                continue;
            }

            // Validate reviewer type

            if (reviewer.Reviewer_Type__c != reviewerType) {
                throw new AuraHandledException(
                    'Reviewer ' + reviewer.First_Name__c + ' ' + reviewer.Last_Name__c +
                    ' is not valid for this proposal status.'
                );
            }

            mappingsToInsert.add(
                new Reviewer_Mapping__c(
                    Proposal__c = proposalId,
                    Reviewer__c = reviewer.Id,
                    // Same reasoning as ProposalTriggerHandler.autoAssignReviewers - copy the
                    // reviewer's own Organisation onto the mapping so it can be compared
                    // against the applicant's organization without an extra join.
                    Organization__c = reviewer.Organisation__c
                )
            );

        }

        if (mappingsToInsert.isEmpty()) {
            throw new AuraHandledException('All selected reviewers are already assigned to this proposal.');
        }

        insert mappingsToInsert;

    }

    @AuraEnabled
    public static void updateReviewerDecision(
        Id reviewerMappingId,
        String decision,
        String conflictReason
    ) {

        if (reviewerMappingId == null) {
            throw new AuraHandledException('Reviewer Mapping Id is required.');
        }

        if (decision != 'Pending' && decision != 'Approved' && decision != 'Conflict') {
            throw new AuraHandledException('Invalid reviewer decision.');
        }

        // Conflict requires reason

        if (decision == 'Conflict') {

            if (String.isBlank(conflictReason)) {
                throw new AuraHandledException('Please enter a conflict reason.');
            }

            if (conflictReason.length() > 255) {
                throw new AuraHandledException('Conflict reason cannot exceed 255 characters.');
            }

        }

        // Grant_Member_Status__c records the Grants Team's own approve/conflict decision about
        // this reviewer - distinct from Status__c, which tracks the reviewer's own review
        // progress (Assigned/Submitted/COI Submitted). This decision also resets Status__c to
        // reflect it (process change), but only while the reviewer hasn't already submitted -
        // once Status__c is 'Submitted' it's left untouched, so a Grants Team decision made
        // after the fact can't undo a real submission and desync
        // ReviewerMappingTriggerHandler.updateReviewerEligibilityStatus's submitted count.
        Reviewer_Mapping__c reviewer = [
            SELECT Id, Grant_Member_Status__c, Conflict_Reason__c, Status__c
            FROM Reviewer_Mapping__c
            WHERE Id = :reviewerMappingId
            LIMIT 1
        ];

        Boolean alreadySubmitted = reviewer.Status__c == 'Submitted';

        if (decision == 'Approved') {
            reviewer.Grant_Member_Status__c = 'Approved';
            if (!alreadySubmitted) {
                reviewer.Status__c = 'Assigned';
            }
            reviewer.Conflict_Reason__c = null;
        }
        else if (decision == 'Conflict') {
            reviewer.Grant_Member_Status__c = 'Conflict';
            if (!alreadySubmitted) {
                reviewer.Status__c = 'Pending';
            }
            reviewer.Conflict_Reason__c = conflictReason;
        }
        else {
            reviewer.Grant_Member_Status__c = 'Pending';
            if (!alreadySubmitted) {
                reviewer.Status__c = 'Pending';
            }
            reviewer.Conflict_Reason__c = null;
        }

        update reviewer;

    }

    private static Integer calculateTotalPages(Integer totalRecords) {

        if (totalRecords == 0) {
            return 0;
        }

        return (Integer) Math.ceil(
            Decimal.valueOf(totalRecords) / Decimal.valueOf(PAGE_SIZE)
        );

    }

    public class ReviewerDetail {

        @AuraEnabled public Id reviewerMappingId;
        @AuraEnabled public String reviewerName;
        @AuraEnabled public String organizationName;
        @AuraEnabled public String decision;
        @AuraEnabled public String conflictReason;
        @AuraEnabled public Boolean hasOrganizationConflict;

        public ReviewerDetail(
            Id reviewerMappingId,
            String reviewerName,
            String organizationName,
            String decision,
            String conflictReason,
            Boolean hasOrganizationConflict
        ) {
            this.reviewerMappingId = reviewerMappingId;
            this.reviewerName = reviewerName;
            this.organizationName = organizationName;
            this.decision = decision;
            this.conflictReason = conflictReason;
            this.hasOrganizationConflict = hasOrganizationConflict;
        }

    }

    public class ProposalRow {

        @AuraEnabled public Id proposalId;
        @AuraEnabled public String applicationId;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String schemeName;
        @AuraEnabled public String proposalStatus;
        @AuraEnabled public List<ReviewerDetail> reviewerDetails;
        @AuraEnabled public String applicantOrganization;

        public ProposalRow(
            Id proposalId,
            String applicationId,
            String applicantName,
            String applicantOrganization,
            String schemeName,
            String proposalStatus,
            List<ReviewerDetail> reviewerDetails
        ) {
            this.proposalId = proposalId;
            this.applicationId = applicationId;
            this.applicantName = applicantName;
            this.applicantOrganization = applicantOrganization;
            this.schemeName = schemeName;
            this.proposalStatus = proposalStatus;
            this.reviewerDetails = reviewerDetails;
        }

    }

    public class ProposalPage {

        @AuraEnabled public List<ProposalRow> records;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer totalPages;
        @AuraEnabled public Boolean hasNext;
        @AuraEnabled public Boolean hasPrevious;
        @AuraEnabled public String firstCursor;
        @AuraEnabled public String lastCursor;

        public ProposalPage(
            List<ProposalRow> records,
            Integer totalRecords,
            Integer totalPages,
            Boolean hasNext,
            Boolean hasPrevious,
            String firstCursor,
            String lastCursor
        ) {
            this.records = records;
            this.totalRecords = totalRecords;
            this.totalPages = totalPages;
            this.hasNext = hasNext;
            this.hasPrevious = hasPrevious;
            this.firstCursor = firstCursor;
            this.lastCursor = lastCursor;
        }

    }

    public class ReviewerRow {

        @AuraEnabled public Id reviewerId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String grantType;
        @AuraEnabled public String organizationName;

        public ReviewerRow(
            Id reviewerId,
            String name,
            String email,
            String grantType,
            String organizationName
        ) {
            this.reviewerId = reviewerId;
            this.name = name;
            this.email = email;
            this.grantType = grantType;
            this.organizationName = organizationName;
        }

    }

    public class ReviewerPage {

        @AuraEnabled public List<ReviewerRow> records;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer totalPages;
        @AuraEnabled public Boolean hasPrevious;
        @AuraEnabled public Boolean hasNext;
        @AuraEnabled public String firstCursor;
        @AuraEnabled public String lastCursor;

        public ReviewerPage(
            List<ReviewerRow> records,
            Integer totalRecords,
            Integer totalPages,
            Boolean hasPrevious,
            Boolean hasNext,
            String firstCursor,
            String lastCursor
        ) {
            this.records = records;
            this.totalRecords = totalRecords;
            this.totalPages = totalPages;
            this.hasPrevious = hasPrevious;
            this.hasNext = hasNext;
            this.firstCursor = firstCursor;
            this.lastCursor = lastCursor;
        }

    }

}