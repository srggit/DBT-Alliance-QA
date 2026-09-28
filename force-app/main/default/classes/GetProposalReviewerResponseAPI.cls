//passing apaId and Checking contact matching.
@RestResource(urlMapping='/getProposalReviewerResponse/*')
global without sharing class GetProposalReviewerResponseAPI {

    // Cached per-transaction so repeated lookups within the same request
    // don't re-describe the objects.
    private static FieldLookupBundle proposalBundle;
    private static FieldLookupBundle apaBundle;
    private static FieldLookupBundle contactBundle;

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String reviewerMappingId = req.params.get('reviewerMappingId');
        String proposalId = req.params.get('proposalId');
        String reviewerId = req.params.get('reviewerId');
        String apaId = req.params.get('apaId');

        ResponseWrapper response = new ResponseWrapper();

        try {
            if (String.isBlank(reviewerMappingId) && String.isBlank(proposalId)) {
                response.success = false;
                response.message = 'Provide reviewerMappingId, OR proposalId (optionally with reviewerId).';
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            Reviewer_Mapping__c mapping = resolveReviewerMapping(reviewerMappingId, proposalId, reviewerId);

            if (mapping == null) {
                response.success = false;
                response.message = 'No Reviewer Mapping found for the given input.';
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            Id resolvedProposalId = mapping.Proposal__c;

            List<Scheme_Section__c> schemeSections = [
                SELECT Id, Section_Name__c, Overall_Comments__c, Rating__c,Application_Stages__c
                FROM Scheme_Section__c
                WHERE Reviewer_Mapping__c = :mapping.Id AND Application_Stages__c=:'Prelims'
                ORDER BY CreatedDate ASC
            ];

            List<Reviewer_Response_Line_Item__c> lineItems = [
                SELECT Id, Name, Question__c, Scheme_Section__c, SL_No__c,Application_Stages__c
                FROM Reviewer_Response_Line_Item__c
                WHERE Reviewer_Mapping__c = :mapping.Id AND Application_Stages__c=:'Prelims'
                ORDER BY CreatedDate ASC
            ];

            SObject proposalRecord = getProposalRecord(resolvedProposalId);

            if (proposalRecord == null) {
                response.success = false;
                response.message = 'Proposal record not found: ' + resolvedProposalId;
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            // APA record used both as the fallback answer source and for the
            // header's Applicant name: pins to a specific APA record if
            // apaId is provided, else falls back to the earliest APA
            // record for this proposal.
            SObject apaRecord = resolveAPARecord(resolvedProposalId, apaId);

            // Contact record (via APA -> Contact__c) - third fallback tier for
            // answer matching, after Proposal__c and APA come up blank.
            SObject contactRecord = resolveContactRecord(apaRecord);

            buildFieldLookupMaps();

            List<SectionWrapper> sectionList = buildSectionGroupedResponse(
                schemeSections, lineItems, proposalRecord, apaRecord, contactRecord
            );

            // Plain child-record lists under the APA - independent of Reviewer
            // Response Line Item / question matching entirely.
            Id resolvedApaId = apaRecord != null ? apaRecord.Id : null;
            ApplicantCVDetailsWrapper cvDetails = buildApplicantCVDetails(resolvedApaId);

            // Header info (Proposal Reference Id, Applicant name, Fellowship Type) -
            // independent of question/answer matching entirely.
            ProposalHeaderWrapper header = buildProposalHeader(resolvedProposalId, apaRecord);

            response.success = true;
            response.message = 'Success';
            response.reviewerMappingId = mapping.Id;
            response.proposalId = resolvedProposalId;
            response.sections = sectionList;
            response.applicantCVDetails = cvDetails;
            response.proposalHeader = header;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage() + ' | Line: ' + e.getLineNumber();
        }

        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    // ===================================================================
    // Resolution helpers
    // ===================================================================

    private static Reviewer_Mapping__c resolveReviewerMapping(String reviewerMappingId, String proposalId, String reviewerId) {
        List<Reviewer_Mapping__c> mappings;

        if (String.isNotBlank(reviewerMappingId)) {
            // Tier 1: direct lookup by Reviewer Mapping Id
            mappings = [
                SELECT Id, Proposal__c
                FROM Reviewer_Mapping__c
                WHERE Id = :reviewerMappingId
                LIMIT 1
            ];
        } else if (String.isNotBlank(proposalId) && String.isNotBlank(reviewerId)) {
            // Tier 2: pin down the exact mapping for this proposal + this reviewer
            mappings = [
                SELECT Id, Proposal__c
                FROM Reviewer_Mapping__c
                WHERE Proposal__c = :proposalId
                AND Reviewer__c = :reviewerId
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
        } else {
            // Tier 3: proposalId only - falls back to earliest mapping for that proposal
            // (ambiguous if the proposal has multiple reviewers assigned; prefer Tier 1 or 2 where possible)
            mappings = [
                SELECT Id, Proposal__c
                FROM Reviewer_Mapping__c
                WHERE Proposal__c = :proposalId
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
        }

        return mappings.isEmpty() ? null : mappings[0];
    }

    // Builds the list of queryable field API names for a dynamic "SELECT *"-style
    // query: real (properly-cased) API names, filtered to only fields the running
    // context can actually read. Fields the user/integration context can't see via
    // FLS are silently omitted here - if they were included, Salesforce's dynamic
    // SOQL parser reports them as a non-existent column ("No such column") rather
    // than a permission error, which is what happens with compound-address fields
    // like OtherStreet when FLS blocks them.
    private static List<String> getAccessibleFieldNames(Schema.DescribeSObjectResult describeResult) {
        List<String> fieldNames = new List<String>();
        for (Schema.SObjectField sf : describeResult.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = sf.getDescribe();
            if (dfr.isAccessible()) {
                fieldNames.add(dfr.getName());
            }
        }
        return fieldNames;
    }

    private static SObject getProposalRecord(Id proposalId) {
        List<String> fieldNames = getAccessibleFieldNames(Schema.SObjectType.Proposal__c);
        String query = 'SELECT ' + String.join(fieldNames, ', ')
            + ' FROM Proposal__c WHERE Id = :proposalId LIMIT 1';
        List<SObject> results = Database.query(query);
        return results.isEmpty() ? null : results[0];
    }

    // Resolves the APA record for this proposal:
    //   - if apaId is provided, filters directly to Id = :apaId (still scoped to
    //     Proposal__c = :proposalId, so an apaId belonging to a different
    //     proposal returns nothing rather than silently pulling in the wrong record)
    //   - otherwise falls back to the earliest APA record (CreatedDate ASC) for the proposal
    private static SObject resolveAPARecord(Id proposalId, String apaId) {
        List<String> fieldNames = getAccessibleFieldNames(Schema.SObjectType.Applicant_Proposal_Association__c);
        String baseSelect = 'SELECT ' + String.join(fieldNames, ', ')
            + ' FROM Applicant_Proposal_Association__c WHERE Proposal__c = :proposalId';

        List<SObject> results;

        if (String.isNotBlank(apaId)) {
            String query = baseSelect + ' AND Id = :apaId LIMIT 1';
            results = Database.query(query);
        } else {
            String query = baseSelect + ' ORDER BY CreatedDate ASC LIMIT 1';
            results = Database.query(query);
        }

        return results.isEmpty() ? null : results[0];
    }

    // Resolves the full Contact record via APA -> Contact__c, dynamically
    // selecting all fields so it can be used as a third field-matching
    // fallback tier, same pattern as getProposalRecord/resolveAPARecord.
    private static SObject resolveContactRecord(SObject apaRecord) {
        if (apaRecord == null) {
            return null;
        }

        Object contactIdValue = apaRecord.get('Contact__c');
        if (contactIdValue == null) {
            return null;
        }

        Id contactId = (Id) contactIdValue;
        List<String> fieldNames = getAccessibleFieldNames(Schema.SObjectType.Contact);
        String query = 'SELECT ' + String.join(fieldNames, ', ')
            + ' FROM Contact WHERE Id = :contactId LIMIT 1';
        List<SObject> results = Database.query(query);
        return results.isEmpty() ? null : results[0];
    }


    private static String resolveHostInstitutionName(Id proposalId) {
        List<Applicant_Host_Association__c> ahaRecords = [
            SELECT Id, Host__r.Name
            FROM Applicant_Host_Association__c
            WHERE Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        if (!ahaRecords.isEmpty() && ahaRecords[0].Host__r != null) {
            return ahaRecords[0].Host__r.Name;
        }
        return null;
    }

    // ===================================================================
    // Applicant CV Details (Education / Employment / Patents / Publications /
    // Existing Grants / Other Grants) - plain child-record lists under the
    // APA, returned as-is, with no relation to Reviewer Response Line Item /
    // question matching at all.
    // ===================================================================

    private static ApplicantCVDetailsWrapper buildApplicantCVDetails(Id apaId) {
        ApplicantCVDetailsWrapper wrapper = new ApplicantCVDetailsWrapper();

        if (apaId == null) {
            wrapper.educationDetails = new List<Education_Details__c>();
            wrapper.employmentDetails = new List<Employment_Details__c>();
            wrapper.patents = new List<Patents__c>();
            wrapper.publications = new List<Publications__c>();
            wrapper.existingGrants = new List<Existing_Grants__c>();
            wrapper.otherGrants = new List<Other_Grants__c>();
            return wrapper;
        }

        wrapper.educationDetails = [
            SELECT Id, Qualification__c, Institution__c, University__c, Specify_the_University__c,
                   Department_School_Division__c, Division__c, Subject__c,
                    Country__c,
                   Start_Date__c, End_Date__c, Likely_date_of_completion__c, Grade__c,
                   CGPA_Division__c, Pursuing_Higher_Degree__c, Specify_the_pursuing_degree__c,
                   Specify_Other_Degree__c, Title_of_thesis_Dissertation__c, Supervisor__c,
                   Research_Summary_During_Highest_Degree__c, Reviewer__c
            FROM Education_Details__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.employmentDetails = [
            SELECT Id, Organisation__c, Position__c, Reporting_To__c, Roles_Responsibilities__c,
                   Start_Date__c, Start_Year__c, End_Date__c, End_Year_Present__c,
                   I_am_currently_working_here__c, Reviewer__c
            FROM Employment_Details__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.patents = [
            SELECT Id, Title__c, Inventors__c, Patent_Number__c, Patent_Id__c,
                   Filing_Granted_Date__c, Granting_Agency_Country__c, Status__c
            FROM Patents__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.publications = [
            SELECT Id, Title__c, Journal_Name__c, Author_Names__c, Applicant_Role__c,
                   PMID_DOI_URL__c, Number_of_citations_at_present__c, Sr_No__c
            FROM Publications__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.existingGrants = [
            SELECT Id, Title__c, Funding_Agency__c, Role_of_Applicant__c, Type__c,
                   Start_Date__c, End_Date__c, Duration_In_Months__c, Total_Award_Amount__c,
                   Currency__c, Other_Currency__c, Abstracts_of_ongoing_grants_fellowship__c
            FROM Existing_Grants__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.otherGrants = [
            SELECT Id, Name, Grants_Type__c,
                   Previous_Application_Reference_Number__c,
                   Previous_Scheme__c,
                   Previous_Application_Project_Title__c,
                   Decision_on_previous_application__c,
                   Key_difference_from_previous_application__c,
                   Name_of_Ongoing_funding_agency_Scheme__c,
                   Ongoing_Project_Title__c,
                   Abstract_Ongoing__c,
                   Overlap_with_current_IA_application__c,
                   Type_of_funding__c,
                   Your_Role_on_the_Application__c,
                   Expected_date_of_decision__c,
                   CurrencyIsoCode,
                   Applicant_Proposal_Association__c
            FROM Other_Grants__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        return wrapper;
    }

    // ===================================================================
    // Proposal Header (Proposal Reference Id / Applicant / Fellowship Type)
    // - independent of Reviewer Response Line Item / question matching.
    // ===================================================================

    private static ProposalHeaderWrapper buildProposalHeader(Id proposalId, SObject apaRecord) {
        ProposalHeaderWrapper header = new ProposalHeaderWrapper();

        // Proposal Reference Id + Fellowship Type via relationship traversal:
        // Proposal__c -> Yearly_Scheme__c -> Scheme_Items__c.Name
        List<Proposal__c> headerRecords = [
            SELECT Id, Proposal_Id__c, Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        if (!headerRecords.isEmpty()) {
            Proposal__c p = headerRecords[0];
            header.proposalReferenceId = p.Proposal_Id__c;
            if (p.Yearly_Scheme__r != null && p.Yearly_Scheme__r.Scheme_Items__r != null) {
                header.fellowshipType = p.Yearly_Scheme__r.Scheme_Items__r.Name;
            }
        }

        // Host Institution Name via Applicant_Host_Association__c -> Host__c (Account)
        header.hostInstitutionName = resolveHostInstitutionName(proposalId);

        // Applicant full name via APA -> Contact
        if (apaRecord != null) {
            Object contactIdValue = apaRecord.get('Contact__c');
            if (contactIdValue != null) {
                Id resolvedContactId = (Id) contactIdValue;
                List<Contact> contacts = [
                    SELECT Id, Name, Salutation,FirstName,MiddleName,LastName
                    FROM Contact
                    WHERE Id = :resolvedContactId
                    LIMIT 1
                ];
                // if (!contacts.isEmpty()) {
                //     header.applicant = contacts[0].Name;
                // }
                if (!contacts.isEmpty()) {
                    Contact c = contacts[0];

                    List<String> nameParts = new List<String>();

                    if (String.isNotBlank(c.Salutation)) {
                        nameParts.add(c.Salutation);
                    }
                    if (String.isNotBlank(c.FirstName)) {
                        nameParts.add(c.FirstName);
                    }
                    if (String.isNotBlank(c.MiddleName)) {
                        nameParts.add(c.MiddleName);
                    }
                    if (String.isNotBlank(c.LastName)) {
                        nameParts.add(c.LastName);
                    }

                    header.applicant = String.join(nameParts, ' ');
                }
            }
        }

        return header;
    }

    // ===================================================================
    // Field describe / lookup map construction (generic across objects)
    // ===================================================================

    private static void buildFieldLookupMaps() {
        if (proposalBundle != null) {
            return; // already built for this transaction
        }

        proposalBundle = buildBundle(Schema.SObjectType.Proposal__c, 'Proposal__c');
        apaBundle = buildBundle(
            Schema.SObjectType.Applicant_Proposal_Association__c,
            'Applicant_Proposal_Association__c'
        );
        contactBundle = buildBundle(Schema.SObjectType.Contact, 'Contact');
    }

    private static FieldLookupBundle buildBundle(Schema.DescribeSObjectResult describeResult, String objectApiName) {
        FieldLookupBundle bundle = new FieldLookupBundle();

        Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();

        for (String apiName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldsMap.get(apiName).getDescribe();
            String actualApiName = dfr.getName();

            String normalizedLabel = normalize(dfr.getLabel());
            if (String.isNotBlank(normalizedLabel)) {
                if (!bundle.labelMap.containsKey(normalizedLabel)) {
                    bundle.labelMap.put(normalizedLabel, actualApiName);
                }
                bundle.candidatesByLengthDesc.add(new LabelCandidate(normalizedLabel, actualApiName));
            }

            String normalizedHelp = normalize(dfr.getInlineHelpText());
            if (String.isNotBlank(normalizedHelp) && !bundle.helpTextMap.containsKey(normalizedHelp)) {
                bundle.helpTextMap.put(normalizedHelp, actualApiName);
            }
        }

        // Longest label first -> reduces false-positive substring matches
        // (e.g. a short generic label matching inside an unrelated long question).
        bundle.candidatesByLengthDesc.sort(new LabelLengthComparator());

        // FieldDefinition is a standard-SOQL-queryable entity (no Tooling API needed)
        // and is the only way to surface the admin-only "Description" field, since
        // Schema.DescribeFieldResult does not expose it (only getInlineHelpText()).
        List<FieldDefinition> fieldDefs = [
            SELECT QualifiedApiName, Description
            FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = :objectApiName
        ];

        for (FieldDefinition fd : fieldDefs) {
            String normalizedDesc = normalize(fd.Description);
            if (String.isNotBlank(normalizedDesc) && !bundle.descriptionMap.containsKey(normalizedDesc)) {
                bundle.descriptionMap.put(normalizedDesc, fd.QualifiedApiName);
            }
        }

        return bundle;
    }

    // Runs the 4-tier match (label exact / help text exact / description exact /
    // label substring) against a single bundle and returns the matched field API
    // name, or null if nothing matched.
    private static String matchField(String normalizedQuestion, FieldLookupBundle bundle) {
        if (bundle.labelMap.containsKey(normalizedQuestion)) {
            return bundle.labelMap.get(normalizedQuestion);
        }
        if (bundle.helpTextMap.containsKey(normalizedQuestion)) {
            return bundle.helpTextMap.get(normalizedQuestion);
        }
        if (bundle.descriptionMap.containsKey(normalizedQuestion)) {
            return bundle.descriptionMap.get(normalizedQuestion);
        }
        for (LabelCandidate candidate : bundle.candidatesByLengthDesc) {
            if (String.isNotBlank(candidate.normalizedLabel)
                && normalizedQuestion.contains(candidate.normalizedLabel)) {
                return candidate.apiName;
            }
        }
        return null;
    }

    // ===================================================================
    // Question/Answer + Section grouping
    // ===================================================================

    private static QAWrapper buildQAWrapper(
        Reviewer_Response_Line_Item__c li,
        SObject proposalRecord,
        SObject apaRecord,
        SObject contactRecord
    ) {
        QAWrapper qa = new QAWrapper();
        qa.reviewerResponseLineItemId = li.Id;
        qa.question = li.Question__c;
        qa.slNo = li.SL_No__c;

        String normalizedQuestion = normalize(li.Question__c);
        Object answerValue = null;

        // 1. Try Proposal__c first
        String proposalFieldApiName = matchField(normalizedQuestion, proposalBundle);
        if (proposalFieldApiName != null) {
            answerValue = proposalRecord.get(proposalFieldApiName);
        }

        // 2. Fall back to Applicant_Proposal_Association__c if still blank
        if (answerValue == null && apaRecord != null) {
            String apaFieldApiName = matchField(normalizedQuestion, apaBundle);
            if (apaFieldApiName != null) {
                answerValue = apaRecord.get(apaFieldApiName);
            }
        }

        // 3. Fall back to Contact if still blank
        if (answerValue == null && contactRecord != null) {
            String contactFieldApiName = matchField(normalizedQuestion, contactBundle);
            if (contactFieldApiName != null) {
                answerValue = contactRecord.get(contactFieldApiName);
            }
        }

        qa.answer = answerValue != null ? String.valueOf(answerValue) : null;
        return qa;
    }

    private static List<SectionWrapper> buildSectionGroupedResponse(
        List<Scheme_Section__c> schemeSections,
        List<Reviewer_Response_Line_Item__c> lineItems,
        SObject proposalRecord,
        SObject apaRecord,
        SObject contactRecord
    ) {
        // Build one SectionWrapper per Scheme_Section__c, preserving query order (CreatedDate ASC)
        Map<Id, SectionWrapper> sectionById = new Map<Id, SectionWrapper>();
        List<SectionWrapper> orderedSections = new List<SectionWrapper>();

        for (Scheme_Section__c ss : schemeSections) {
            SectionWrapper sw = new SectionWrapper();
            sw.schemeSectionId = ss.Id;
            sw.sectionName = ss.Section_Name__c;
            sw.overallComments = ss.Overall_Comments__c;
            sw.sectionRating = ss.Rating__c;
            sw.questionAnswers = new List<QAWrapper>();

            sectionById.put(ss.Id, sw);
            orderedSections.add(sw);
        }

        // Bucket for line items that (unexpectedly) have no Scheme_Section__c set,
        // so nothing silently disappears from the response.
        SectionWrapper unassignedSection = new SectionWrapper();
        unassignedSection.schemeSectionId = null;
        unassignedSection.sectionName = 'Unassigned';
        unassignedSection.overallComments = null;
        unassignedSection.sectionRating = null;
        unassignedSection.questionAnswers = new List<QAWrapper>();
        Boolean hasUnassigned = false;

        for (Reviewer_Response_Line_Item__c li : lineItems) {
            QAWrapper qa = buildQAWrapper(li, proposalRecord, apaRecord, contactRecord);

            if (li.Scheme_Section__c != null && sectionById.containsKey(li.Scheme_Section__c)) {
                sectionById.get(li.Scheme_Section__c).questionAnswers.add(qa);
            } else {
                unassignedSection.questionAnswers.add(qa);
                hasUnassigned = true;
            }
        }

        if (hasUnassigned) {
            orderedSections.add(unassignedSection);
        }

        return orderedSections;
    }

    // ===================================================================
    // Normalization
    // ===================================================================

    private static String normalize(String input) {
        if (String.isBlank(input)) {
            return '';
        }
        // Strip HTML tags in case a rich-text-sourced help text or label is passed in
        String stripped = input.replaceAll('<[^>]+>', '');
        stripped = stripped.toLowerCase().trim();
        stripped = stripped.replaceAll('[\\s]+', ' ');
        stripped = stripped.replaceAll('[^a-z0-9 ]', ''); // drop punctuation for robust comparison
        return stripped;
    }

    // ===================================================================
    // Wrappers
    // ===================================================================

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public Id reviewerMappingId;
        public Id proposalId;
        public List<SectionWrapper> sections;
        public ApplicantCVDetailsWrapper applicantCVDetails;
        public ProposalHeaderWrapper proposalHeader;
    }

    global class ProposalHeaderWrapper {
        public String proposalReferenceId;
        public String applicant;
        public String fellowshipType;
        public String hostInstitutionName;
    }

    global class ApplicantCVDetailsWrapper {
        public List<Education_Details__c> educationDetails;
        public List<Employment_Details__c> employmentDetails;
        public List<Patents__c> patents;
        public List<Publications__c> publications;
        public List<Existing_Grants__c> existingGrants;
        public List<Other_Grants__c> otherGrants;
    }

    global class SectionWrapper {
        public Id schemeSectionId;
        public String sectionName;
        public String overallComments;
        public String sectionRating;
        public List<QAWrapper> questionAnswers;
    }

    global class QAWrapper {
        public Id reviewerResponseLineItemId;
        public String question;
        public String answer;
        public Decimal slNo;
    }

    private class FieldLookupBundle {
        Map<String, String> labelMap = new Map<String, String>();
        Map<String, String> helpTextMap = new Map<String, String>();
        Map<String, String> descriptionMap = new Map<String, String>();
        List<LabelCandidate> candidatesByLengthDesc = new List<LabelCandidate>();
    }

    private class LabelCandidate {
        String normalizedLabel;
        String apiName;
        LabelCandidate(String normalizedLabel, String apiName) {
            this.normalizedLabel = normalizedLabel;
            this.apiName = apiName;
        }
    }

    private class LabelLengthComparator implements Comparator<LabelCandidate> {
        public Integer compare(LabelCandidate a, LabelCandidate b) {
            return b.normalizedLabel.length() - a.normalizedLabel.length();
        }
    }
}

//apaId Passing
/*
@RestResource(urlMapping='/getProposalReviewerResponse/*')
global without sharing class GetProposalReviewerResponseAPI {

    // Cached per-transaction so repeated lookups within the same request
    // don't re-describe the objects.
    private static FieldLookupBundle proposalBundle;
    private static FieldLookupBundle apaBundle;

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String reviewerMappingId = req.params.get('reviewerMappingId');
        String proposalId = req.params.get('proposalId');
        String reviewerId = req.params.get('reviewerId');
        String apaId = req.params.get('apaId');

        ResponseWrapper response = new ResponseWrapper();

        try {
            if (String.isBlank(reviewerMappingId) && String.isBlank(proposalId)) {
                response.success = false;
                response.message = 'Provide reviewerMappingId, OR proposalId (optionally with reviewerId).';
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            Reviewer_Mapping__c mapping = resolveReviewerMapping(reviewerMappingId, proposalId, reviewerId);

            if (mapping == null) {
                response.success = false;
                response.message = 'No Reviewer Mapping found for the given input.';
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            Id resolvedProposalId = mapping.Proposal__c;

            List<Scheme_Section__c> schemeSections = [
                SELECT Id, Section_Name__c, Overall_Comments__c, Rating__c
                FROM Scheme_Section__c
                WHERE Reviewer_Mapping__c = :mapping.Id
                ORDER BY CreatedDate ASC
            ];

            List<Reviewer_Response_Line_Item__c> lineItems = [
                SELECT Id, Name, Question__c, Scheme_Section__c, SL_No__c
                FROM Reviewer_Response_Line_Item__c
                WHERE Reviewer_Mapping__c = :mapping.Id
                ORDER BY CreatedDate ASC
            ];

            SObject proposalRecord = getProposalRecord(resolvedProposalId);

            if (proposalRecord == null) {
                response.success = false;
                response.message = 'Proposal record not found: ' + resolvedProposalId;
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            // APA record used both as the fallback answer source and for the
            // header's Applicant name: pins to a specific APA record if
            // apaId is provided, else falls back to the earliest APA
            // record for this proposal.
            SObject apaRecord = resolveAPARecord(resolvedProposalId, apaId);

            buildFieldLookupMaps();

            List<SectionWrapper> sectionList = buildSectionGroupedResponse(
                schemeSections, lineItems, proposalRecord, apaRecord
            );

            // Plain child-record lists under the APA - independent of Reviewer
            // Response Line Item / question matching entirely.
            Id resolvedApaId = apaRecord != null ? apaRecord.Id : null;
            ApplicantCVDetailsWrapper cvDetails = buildApplicantCVDetails(resolvedApaId);

            // Header info (Proposal Reference Id, Applicant name, Fellowship Type) -
            // independent of question/answer matching entirely.
            ProposalHeaderWrapper header = buildProposalHeader(resolvedProposalId, apaRecord);

            response.success = true;
            response.message = 'Success';
            response.reviewerMappingId = mapping.Id;
            response.proposalId = resolvedProposalId;
            response.sections = sectionList;
            response.applicantCVDetails = cvDetails;
            response.proposalHeader = header;

        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage() + ' | Line: ' + e.getLineNumber();
        }

        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    // ===================================================================
    // Resolution helpers
    // ===================================================================

    private static Reviewer_Mapping__c resolveReviewerMapping(String reviewerMappingId, String proposalId, String reviewerId) {
        List<Reviewer_Mapping__c> mappings;

        if (String.isNotBlank(reviewerMappingId)) {
            // Tier 1: direct lookup by Reviewer Mapping Id
            mappings = [
                SELECT Id, Proposal__c
                FROM Reviewer_Mapping__c
                WHERE Id = :reviewerMappingId
                LIMIT 1
            ];
        } else if (String.isNotBlank(proposalId) && String.isNotBlank(reviewerId)) {
            // Tier 2: pin down the exact mapping for this proposal + this reviewer
            mappings = [
                SELECT Id, Proposal__c
                FROM Reviewer_Mapping__c
                WHERE Proposal__c = :proposalId
                AND Reviewer__c = :reviewerId
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
        } else {
            // Tier 3: proposalId only - falls back to earliest mapping for that proposal
            // (ambiguous if the proposal has multiple reviewers assigned; prefer Tier 1 or 2 where possible)
            mappings = [
                SELECT Id, Proposal__c
                FROM Reviewer_Mapping__c
                WHERE Proposal__c = :proposalId
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
        }

        return mappings.isEmpty() ? null : mappings[0];
    }

    private static SObject getProposalRecord(Id proposalId) {
        Set<String> fieldNames = Schema.SObjectType.Proposal__c.fields.getMap().keySet();
        String query = 'SELECT ' + String.join(new List<String>(fieldNames), ', ')
            + ' FROM Proposal__c WHERE Id = :proposalId LIMIT 1';
        List<SObject> results = Database.query(query);
        return results.isEmpty() ? null : results[0];
    }

    // Resolves the APA record for this proposal:
    //   - if apaId is provided, filters directly to Id = :apaId (still scoped to
    //     Proposal__c = :proposalId, so an apaId belonging to a different
    //     proposal returns nothing rather than silently pulling in the wrong record)
    //   - otherwise falls back to the earliest APA record (CreatedDate ASC) for the proposal
    private static SObject resolveAPARecord(Id proposalId, String apaId) {
        Set<String> fieldNames = Schema.SObjectType.Applicant_Proposal_Association__c.fields.getMap().keySet();
        String baseSelect = 'SELECT ' + String.join(new List<String>(fieldNames), ', ')
            + ' FROM Applicant_Proposal_Association__c WHERE Proposal__c = :proposalId';

        List<SObject> results;

        if (String.isNotBlank(apaId)) {
            String query = baseSelect + ' AND Id = :apaId LIMIT 1';
            results = Database.query(query);
        } else {
            String query = baseSelect + ' ORDER BY CreatedDate ASC LIMIT 1';
            results = Database.query(query);
        }

        return results.isEmpty() ? null : results[0];
    }

    // ===================================================================
    // Applicant CV Details (Education / Employment / Patents / Publications /
    // Existing Grants / Other Grants) - plain child-record lists under the
    // APA, returned as-is, with no relation to Reviewer Response Line Item /
    // question matching at all.
    // ===================================================================

    private static ApplicantCVDetailsWrapper buildApplicantCVDetails(Id apaId) {
        ApplicantCVDetailsWrapper wrapper = new ApplicantCVDetailsWrapper();

        if (apaId == null) {
            wrapper.educationDetails = new List<Education_Details__c>();
            wrapper.employmentDetails = new List<Employment_Details__c>();
            wrapper.patents = new List<Patents__c>();
            wrapper.publications = new List<Publications__c>();
            wrapper.existingGrants = new List<Existing_Grants__c>();
            wrapper.otherGrants = new List<Other_Grants__c>();
            return wrapper;
        }

        wrapper.educationDetails = [
            SELECT Id, Qualification__c, Institution__c, University__c, Specify_the_University__c,
                   Department_School_Division__c, Division__c, Subject__c,
                    Country__c,
                   Start_Date__c, End_Date__c, Likely_date_of_completion__c, Grade__c,
                   CGPA_Division__c, Pursuing_Higher_Degree__c, Specify_the_pursuing_degree__c,
                   Specify_Other_Degree__c, Title_of_thesis_Dissertation__c, Supervisor__c,
                   Research_Summary_During_Highest_Degree__c, Reviewer__c
            FROM Education_Details__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.employmentDetails = [
            SELECT Id, Organisation__c, Position__c, Reporting_To__c, Roles_Responsibilities__c,
                   Start_Date__c, Start_Year__c, End_Date__c, End_Year_Present__c,
                   I_am_currently_working_here__c, Reviewer__c
            FROM Employment_Details__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.patents = [
            SELECT Id, Title__c, Inventors__c, Patent_Number__c, Patent_Id__c,
                   Filing_Granted_Date__c, Granting_Agency_Country__c, Status__c
            FROM Patents__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.publications = [
            SELECT Id, Title__c, Journal_Name__c, Author_Names__c, Applicant_Role__c,
                   PMID_DOI_URL__c, Number_of_citations_at_present__c, Sr_No__c
            FROM Publications__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.existingGrants = [
            SELECT Id, Title__c, Funding_Agency__c, Role_of_Applicant__c, Type__c,
                   Start_Date__c, End_Date__c, Duration_In_Months__c, Total_Award_Amount__c,
                   Currency__c, Other_Currency__c, Abstracts_of_ongoing_grants_fellowship__c
            FROM Existing_Grants__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        wrapper.otherGrants = [
            SELECT Id, Name, Grants_Type__c,
                   Previous_Application_Reference_Number__c,
                   Previous_Scheme__c,
                   Previous_Application_Project_Title__c,
                   Decision_on_previous_application__c,
                   Key_difference_from_previous_application__c,
                   Name_of_Ongoing_funding_agency_Scheme__c,
                   Ongoing_Project_Title__c,
                   Abstract_Ongoing__c,
                   Overlap_with_current_IA_application__c,
                   Type_of_funding__c,
                   Your_Role_on_the_Application__c,
                   Expected_date_of_decision__c,
                   CurrencyIsoCode,
                   Applicant_Proposal_Association__c
            FROM Other_Grants__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        return wrapper;
    }

    // ===================================================================
    // Proposal Header (Proposal Reference Id / Applicant / Fellowship Type)
    // - independent of Reviewer Response Line Item / question matching.
    // ===================================================================

    private static ProposalHeaderWrapper buildProposalHeader(Id proposalId, SObject apaRecord) {
        ProposalHeaderWrapper header = new ProposalHeaderWrapper();

        // Proposal Reference Id + Fellowship Type via relationship traversal:
        // Proposal__c -> Yearly_Scheme__c -> Scheme_Items__c.Name
        List<Proposal__c> headerRecords = [
            SELECT Id, Proposal_Id__c, Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        if (!headerRecords.isEmpty()) {
            Proposal__c p = headerRecords[0];
            header.proposalReferenceId = p.Proposal_Id__c;
            if (p.Yearly_Scheme__r != null && p.Yearly_Scheme__r.Scheme_Items__r != null) {
                header.fellowshipType = p.Yearly_Scheme__r.Scheme_Items__r.Name;
            }
        }

        // Applicant full name via APA -> Contact
        if (apaRecord != null) {
            Object contactIdValue = apaRecord.get('Contact__c');
            if (contactIdValue != null) {
                Id resolvedContactId = (Id) contactIdValue;
                List<Contact> contacts = [
                    SELECT Id, Name, Salutation,FirstName,MiddleName,LastName
                    FROM Contact
                    WHERE Id = :resolvedContactId
                    LIMIT 1
                ];
                // if (!contacts.isEmpty()) {
                //     header.applicant = contacts[0].Name;
                // }
                if (!contacts.isEmpty()) {
                    Contact c = contacts[0];

                    List<String> nameParts = new List<String>();

                    if (String.isNotBlank(c.Salutation)) {
                        nameParts.add(c.Salutation);
                    }
                    if (String.isNotBlank(c.FirstName)) {
                        nameParts.add(c.FirstName);
                    }
                    if (String.isNotBlank(c.MiddleName)) {
                        nameParts.add(c.MiddleName);
                    }
                    if (String.isNotBlank(c.LastName)) {
                        nameParts.add(c.LastName);
                    }

                    header.applicant = String.join(nameParts, ' ');
                }
            }
        }

        return header;
    }

    // ===================================================================
    // Field describe / lookup map construction (generic across objects)
    // ===================================================================

    private static void buildFieldLookupMaps() {
        if (proposalBundle != null) {
            return; // already built for this transaction
        }

        proposalBundle = buildBundle(Schema.SObjectType.Proposal__c, 'Proposal__c');
        apaBundle = buildBundle(
            Schema.SObjectType.Applicant_Proposal_Association__c,
            'Applicant_Proposal_Association__c'
        );
    }

    private static FieldLookupBundle buildBundle(Schema.DescribeSObjectResult describeResult, String objectApiName) {
        FieldLookupBundle bundle = new FieldLookupBundle();

        Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();

        for (String apiName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldsMap.get(apiName).getDescribe();
            String actualApiName = dfr.getName();

            String normalizedLabel = normalize(dfr.getLabel());
            if (String.isNotBlank(normalizedLabel)) {
                if (!bundle.labelMap.containsKey(normalizedLabel)) {
                    bundle.labelMap.put(normalizedLabel, actualApiName);
                }
                bundle.candidatesByLengthDesc.add(new LabelCandidate(normalizedLabel, actualApiName));
            }

            String normalizedHelp = normalize(dfr.getInlineHelpText());
            if (String.isNotBlank(normalizedHelp) && !bundle.helpTextMap.containsKey(normalizedHelp)) {
                bundle.helpTextMap.put(normalizedHelp, actualApiName);
            }
        }

        // Longest label first -> reduces false-positive substring matches
        // (e.g. a short generic label matching inside an unrelated long question).
        bundle.candidatesByLengthDesc.sort(new LabelLengthComparator());

        // FieldDefinition is a standard-SOQL-queryable entity (no Tooling API needed)
        // and is the only way to surface the admin-only "Description" field, since
        // Schema.DescribeFieldResult does not expose it (only getInlineHelpText()).
        List<FieldDefinition> fieldDefs = [
            SELECT QualifiedApiName, Description
            FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = :objectApiName
        ];

        for (FieldDefinition fd : fieldDefs) {
            String normalizedDesc = normalize(fd.Description);
            if (String.isNotBlank(normalizedDesc) && !bundle.descriptionMap.containsKey(normalizedDesc)) {
                bundle.descriptionMap.put(normalizedDesc, fd.QualifiedApiName);
            }
        }

        return bundle;
    }

    // Runs the 4-tier match (label exact / help text exact / description exact /
    // label substring) against a single bundle and returns the matched field API
    // name, or null if nothing matched.
    private static String matchField(String normalizedQuestion, FieldLookupBundle bundle) {
        if (bundle.labelMap.containsKey(normalizedQuestion)) {
            return bundle.labelMap.get(normalizedQuestion);
        }
        if (bundle.helpTextMap.containsKey(normalizedQuestion)) {
            return bundle.helpTextMap.get(normalizedQuestion);
        }
        if (bundle.descriptionMap.containsKey(normalizedQuestion)) {
            return bundle.descriptionMap.get(normalizedQuestion);
        }
        for (LabelCandidate candidate : bundle.candidatesByLengthDesc) {
            if (String.isNotBlank(candidate.normalizedLabel)
                && normalizedQuestion.contains(candidate.normalizedLabel)) {
                return candidate.apiName;
            }
        }
        return null;
    }

    // ===================================================================
    // Question/Answer + Section grouping
    // ===================================================================

    private static QAWrapper buildQAWrapper(Reviewer_Response_Line_Item__c li, SObject proposalRecord, SObject apaRecord) {
        QAWrapper qa = new QAWrapper();
        qa.reviewerResponseLineItemId = li.Id;
        qa.question = li.Question__c;
        qa.slNo = li.SL_No__c;

        String normalizedQuestion = normalize(li.Question__c);
        Object answerValue = null;

        // 1. Try Proposal__c first
        String proposalFieldApiName = matchField(normalizedQuestion, proposalBundle);
        if (proposalFieldApiName != null) {
            answerValue = proposalRecord.get(proposalFieldApiName);
        }

        // 2. Fall back to Applicant_Proposal_Association__c if still blank
        if (answerValue == null && apaRecord != null) {
            String apaFieldApiName = matchField(normalizedQuestion, apaBundle);
            if (apaFieldApiName != null) {
                answerValue = apaRecord.get(apaFieldApiName);
            }
        }

        qa.answer = answerValue != null ? String.valueOf(answerValue) : null;
        return qa;
    }

    private static List<SectionWrapper> buildSectionGroupedResponse(
        List<Scheme_Section__c> schemeSections,
        List<Reviewer_Response_Line_Item__c> lineItems,
        SObject proposalRecord,
        SObject apaRecord
    ) {
        // Build one SectionWrapper per Scheme_Section__c, preserving query order (CreatedDate ASC)
        Map<Id, SectionWrapper> sectionById = new Map<Id, SectionWrapper>();
        List<SectionWrapper> orderedSections = new List<SectionWrapper>();

        for (Scheme_Section__c ss : schemeSections) {
            SectionWrapper sw = new SectionWrapper();
            sw.schemeSectionId = ss.Id;
            sw.sectionName = ss.Section_Name__c;
            sw.overallComments = ss.Overall_Comments__c;
            sw.sectionRating = ss.Rating__c;
            sw.questionAnswers = new List<QAWrapper>();

            sectionById.put(ss.Id, sw);
            orderedSections.add(sw);
        }

        // Bucket for line items that (unexpectedly) have no Scheme_Section__c set,
        // so nothing silently disappears from the response.
        SectionWrapper unassignedSection = new SectionWrapper();
        unassignedSection.schemeSectionId = null;
        unassignedSection.sectionName = 'Unassigned';
        unassignedSection.overallComments = null;
        unassignedSection.sectionRating = null;
        unassignedSection.questionAnswers = new List<QAWrapper>();
        Boolean hasUnassigned = false;

        for (Reviewer_Response_Line_Item__c li : lineItems) {
            QAWrapper qa = buildQAWrapper(li, proposalRecord, apaRecord);

            if (li.Scheme_Section__c != null && sectionById.containsKey(li.Scheme_Section__c)) {
                sectionById.get(li.Scheme_Section__c).questionAnswers.add(qa);
            } else {
                unassignedSection.questionAnswers.add(qa);
                hasUnassigned = true;
            }
        }

        if (hasUnassigned) {
            orderedSections.add(unassignedSection);
        }

        return orderedSections;
    }

    // ===================================================================
    // Normalization
    // ===================================================================

    private static String normalize(String input) {
        if (String.isBlank(input)) {
            return '';
        }
        // Strip HTML tags in case a rich-text-sourced help text or label is passed in
        String stripped = input.replaceAll('<[^>]+>', '');
        stripped = stripped.toLowerCase().trim();
        stripped = stripped.replaceAll('[\\s]+', ' ');
        stripped = stripped.replaceAll('[^a-z0-9 ]', ''); // drop punctuation for robust comparison
        return stripped;
    }

    // ===================================================================
    // Wrappers
    // ===================================================================

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public Id reviewerMappingId;
        public Id proposalId;
        public List<SectionWrapper> sections;
        public ApplicantCVDetailsWrapper applicantCVDetails;
        public ProposalHeaderWrapper proposalHeader;
    }

    global class ProposalHeaderWrapper {
        public String proposalReferenceId;
        public String applicant;
        public String fellowshipType;
    }

    global class ApplicantCVDetailsWrapper {
        public List<Education_Details__c> educationDetails;
        public List<Employment_Details__c> employmentDetails;
        public List<Patents__c> patents;
        public List<Publications__c> publications;
        public List<Existing_Grants__c> existingGrants;
        public List<Other_Grants__c> otherGrants;
    }

    global class SectionWrapper {
        public Id schemeSectionId;
        public String sectionName;
        public String overallComments;
        public String sectionRating;
        public List<QAWrapper> questionAnswers;
    }

    global class QAWrapper {
        public Id reviewerResponseLineItemId;
        public String question;
        public String answer;
        public Decimal slNo;
    }

    private class FieldLookupBundle {
        Map<String, String> labelMap = new Map<String, String>();
        Map<String, String> helpTextMap = new Map<String, String>();
        Map<String, String> descriptionMap = new Map<String, String>();
        List<LabelCandidate> candidatesByLengthDesc = new List<LabelCandidate>();
    }

    private class LabelCandidate {
        String normalizedLabel;
        String apiName;
        LabelCandidate(String normalizedLabel, String apiName) {
            this.normalizedLabel = normalizedLabel;
            this.apiName = apiName;
        }
    }

    private class LabelLengthComparator implements Comparator<LabelCandidate> {
        public Integer compare(LabelCandidate a, LabelCandidate b) {
            return b.normalizedLabel.length() - a.normalizedLabel.length();
        }
    }
}
*/