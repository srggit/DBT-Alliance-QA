/**
 * GetProposalReviewerResponseAPI
 * ---------------------------------------------------------------------------
 * Returns Reviewer_Response_Line_Item__c questions paired with the matching
 * answer, grouped by Scheme_Section__c (so the UI can render section-wise
 * tabs/accordions, each with its own overall comments and rating).
 *
 * Answer resolution order per question:
 *   1. Match the question against a Proposal__c field (label/help text/
 *      description/substring) and read its value.
 *   2. If that value is null (field not matched, or matched but blank),
 *      fall back to the first Applicant_Proposal_Association__c (APA)
 *      record for this proposal, matching the question against APA's own
 *      fields the same way.
 *
 * Input (query params):
 *   - reviewerMappingId  (preferred, direct)
 *   - proposalId + reviewerId  (pins the exact mapping for that reviewer)
 *   - proposalId alone   (fallback: resolves the earliest Reviewer_Mapping__c
 *                          for that proposal, ordered by CreatedDate ASC)
 *   - contactId (optional) - pins the APA record (used for both the answer
 *                          fallback and the header's Applicant name) to a
 *                          specific applicant. If omitted, the earliest APA
 *                          record for the proposal is used instead.
 *
 * Output shape:
 *   proposalHeader: { proposalReferenceId, applicant, fellowshipType }
 *   sections: [
 *     {
 *       schemeSectionId, sectionName, overallComments, sectionRating,
 *       questionAnswers: [ { question, answer }, ... ]
 *     },
 *     ...
 *   ]
 * Line items with no Scheme_Section__c populated are bucketed under a final
 * "Unassigned" section rather than being silently dropped.
 *
 * NOTE: This relies on Setup metadata (labels/help text) staying in sync
 * with Question__c wording. If that drifts, matches will silently fail
 * (answer comes back null, not thrown as an error). For a more durable
 * design, consider a custom metadata mapping (Question_Field_Mapping__mdt)
 * or a direct API-name field on the line item itself.
 * ---------------------------------------------------------------------------
 */
/*
//passing apaId and Checking Contact matching (with Host Institution Name).
/*
@RestResource(urlMapping='/getProposalReviewerResponsefull/*')
global without sharing class GetProposalReviewerResponseFullAPI {

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

            // Header info (Proposal Reference Id, Applicant name, Fellowship Type,
            // Host Institution Name) - independent of question/answer matching entirely.
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

    // Resolves the Host Institution Name via Applicant_Host_Association__c -> Host__c (Account).
    // Falls back to the earliest AHA record (CreatedDate ASC) for the proposal if multiple exist.
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
    // Proposal Header (Proposal Reference Id / Applicant / Fellowship Type /
    // Host Institution Name) - independent of Reviewer Response Line Item /
    // question matching.
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
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName
                    FROM Contact
                    WHERE Id = :resolvedContactId
                    LIMIT 1
                ];
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
}*/


/*
@RestResource(urlMapping='/getProposalReviewerResponsefull/*')
global without sharing class GetProposalReviewerResponseFullAPI {

    // Cached per-transaction so repeated lookups within the same request
    // don't re-describe the objects.
    private static FieldLookupBundle proposalBundle;
    private static FieldLookupBundle apaBundle;
    private static FieldLookupBundle contactBundle;
    private static FieldLookupBundle ppaBundle;

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String reviewerMappingId = req.params.get('reviewerMappingId');
        String proposalId = req.params.get('proposalId');
        String reviewerId = req.params.get('reviewerId');
        String apaId = req.params.get('apaId');
        String ppaId = req.params.get('ppaId');

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

            // Contact record (via APA -> Contact__c) - third fallback tier for
            // answer matching, after Proposal__c and APA come up blank.
            SObject contactRecord = resolveContactRecord(apaRecord);

            // PPA record (Proposal_Participant_Association__c) - fourth fallback
            // tier, scoped directly off Proposal__c (no APA/Contact relationship
            // exists on this object). Pins to a specific PPA record if ppaId is
            // provided, else falls back to the earliest PPA record for the proposal.
            SObject ppaRecord = resolvePPARecord(resolvedProposalId, ppaId);

            buildFieldLookupMaps();

            List<SectionWrapper> sectionList = buildSectionGroupedResponse(
                schemeSections, lineItems, proposalRecord, apaRecord, contactRecord, ppaRecord
            );

            // Plain child-record lists under the APA - independent of Reviewer
            // Response Line Item / question matching entirely.
            Id resolvedApaId = apaRecord != null ? apaRecord.Id : null;
            ApplicantCVDetailsWrapper cvDetails = buildApplicantCVDetails(resolvedApaId);

            // Header info (Proposal Reference Id, Applicant name, Fellowship Type,
            // Host Institution Name) - independent of question/answer matching entirely.
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

    // Resolves the PPA record (Proposal_Participant_Association__c) for this
    // proposal - fourth field-matching fallback tier, after Proposal__c, APA,
    // and Contact come up blank. PPA has no Contact__c/APA relationship on it
    // (it links directly off Proposal__c), so - unlike resolveContactRecord -
    // this resolves straight from proposalId, same shape as resolveAPARecord:
    //   - if ppaId is provided, filters directly to Id = :ppaId (still scoped to
    //     Proposal__c = :proposalId, so a ppaId belonging to a different
    //     proposal returns nothing rather than silently pulling in the wrong record)
    //   - otherwise falls back to the earliest PPA record (CreatedDate ASC) for
    //     the proposal (a proposal can have multiple participants/PPAs)
    private static SObject resolvePPARecord(Id proposalId, String ppaId) {
        List<String> fieldNames = getAccessibleFieldNames(Schema.SObjectType.Proposal_Participant_Association__c);
        String baseSelect = 'SELECT ' + String.join(fieldNames, ', ')
            + ' FROM Proposal_Participant_Association__c WHERE Proposal__c = :proposalId AND Roles__c="Supervisor"';

        List<SObject> results;

        if (String.isNotBlank(ppaId)) {
            String query = baseSelect + ' AND Id = :ppaId LIMIT 1';
            results = Database.query(query);
        } else {
            String query = baseSelect + ' ORDER BY CreatedDate ASC LIMIT 1';
            results = Database.query(query);
        }

        return results.isEmpty() ? null : results[0];
    }

    // Resolves the Host Institution Name via Applicant_Host_Association__c -> Host__c (Account).
    // Falls back to the earliest AHA record (CreatedDate ASC) for the proposal if multiple exist.
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
    // Proposal Header (Proposal Reference Id / Applicant / Fellowship Type /
    // Host Institution Name) - independent of Reviewer Response Line Item /
    // question matching.
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
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName
                    FROM Contact
                    WHERE Id = :resolvedContactId
                    LIMIT 1
                ];
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
        ppaBundle = buildBundle(
            Schema.SObjectType.Proposal_Participant_Association__c,
            'Proposal_Participant_Association__c'
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

    private static QAWrapper buildQAWrapper(
        Reviewer_Response_Line_Item__c li,
        SObject proposalRecord,
        SObject apaRecord,
        SObject contactRecord,
        SObject ppaRecord
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

        // 4. Fall back to Proposal_Participant_Association__c (PPA) if still blank
        if (answerValue == null && ppaRecord != null) {
            String ppaFieldApiName = matchField(normalizedQuestion, ppaBundle);
            if (ppaFieldApiName != null) {
                answerValue = ppaRecord.get(ppaFieldApiName);
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
        SObject contactRecord,
        SObject ppaRecord
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
            QAWrapper qa = buildQAWrapper(li, proposalRecord, apaRecord, contactRecord, ppaRecord);

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
}*/





@RestResource(urlMapping='/getProposalReviewerResponsefull/*')
global without sharing class GetProposalReviewerResponseFullAPI {

    // Cached per-transaction so repeated lookups within the same request
    // don't re-describe the objects.
    private static FieldLookupBundle proposalBundle;
    private static FieldLookupBundle apaBundle;
    private static FieldLookupBundle contactBundle;
    private static FieldLookupBundle ppaBundle;

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String reviewerMappingId = req.params.get('reviewerMappingId');
        String proposalId = req.params.get('proposalId');
        String reviewerId = req.params.get('reviewerId');
        String apaId = req.params.get('apaId');
        String ppaId = req.params.get('ppaId');

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
                WHERE Reviewer_Mapping__c = :mapping.Id AND Application_Stages__c=:'Full'
                ORDER BY CreatedDate ASC
            ];

            List<Reviewer_Response_Line_Item__c> lineItems = [
                SELECT Id, Name, Question__c, Scheme_Section__c, SL_No__c,Application_Stages__c
                FROM Reviewer_Response_Line_Item__c
                WHERE Reviewer_Mapping__c = :mapping.Id AND Application_Stages__c=:'Full'
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

            // PPA record (Proposal_Participant_Association__c) - fourth fallback
            // tier, scoped directly off Proposal__c (no APA/Contact relationship
            // exists on this object). Pins to a specific PPA record if ppaId is
            // provided, else falls back to the earliest Supervisor PPA record
            // for the proposal.
            SObject ppaRecord = resolvePPARecord(resolvedProposalId, ppaId);

            buildFieldLookupMaps();

            List<SectionWrapper> sectionList = buildSectionGroupedResponse(
                schemeSections, lineItems, proposalRecord, apaRecord, contactRecord, ppaRecord
            );

            // Plain child-record lists under the APA - independent of Reviewer
            // Response Line Item / question matching entirely.
            Id resolvedApaId = apaRecord != null ? apaRecord.Id : null;
            ApplicantCVDetailsWrapper cvDetails = buildApplicantCVDetails(resolvedApaId);

            // Header info (Proposal Reference Id, Applicant name, Fellowship Type,
            // Host Institution Name) - independent of question/answer matching entirely.
            ProposalHeaderWrapper header = buildProposalHeader(resolvedProposalId, apaRecord);

            // Additional plain record lists - all independent of Reviewer Response
            // Line Item / question-answer matching, same pattern as applicantCVDetails.
            List<Human__c> humanDetails = buildHumanDetails(resolvedProposalId);
            List<Project_Milestone__c> projectMilestones = buildProjectMilestones(resolvedProposalId);
            List<AnimalWrapper> animalDetails = buildAnimalDetails(resolvedProposalId);
            List<Applicant_Host_Association__c> hostInstitutionDetails = buildHostInstitutionDetails(resolvedProposalId);
            List<Proposal_Participant_Association__c> fellowshipSupervisors = buildFellowshipSupervisors(resolvedProposalId);
            List<WOHICollaborationWrapper> wohiCollaborations = buildWOHICollaborations(resolvedApaId);

            response.success = true;
            response.message = 'Success';
            response.reviewerMappingId = mapping.Id;
            response.proposalId = resolvedProposalId;
            response.sections = sectionList;
            response.applicantCVDetails = cvDetails;
            response.proposalHeader = header;
            response.humanDetails = humanDetails;
            response.projectMilestones = projectMilestones;
            response.animalDetails = animalDetails;
            response.hostInstitutionDetails = hostInstitutionDetails;
            response.fellowshipSupervisors = fellowshipSupervisors;
            response.wohiCollaborations = wohiCollaborations;

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

    // Resolves the PPA record (Proposal_Participant_Association__c) for this
    // proposal - fourth field-matching fallback tier, after Proposal__c, APA,
    // and Contact come up blank. PPA has no Contact__c/APA relationship on it
    // (it links directly off Proposal__c), so - unlike resolveContactRecord -
    // this resolves straight from proposalId, same shape as resolveAPARecord.
    // Scoped to the Supervisor role, since that's the PPA whose answers are
    // relevant as a matching fallback tier:
    //   - if ppaId is provided, filters directly to Id = :ppaId (still scoped to
    //     Proposal__c = :proposalId, so a ppaId belonging to a different
    //     proposal returns nothing rather than silently pulling in the wrong record)
    //   - otherwise falls back to the earliest Supervisor PPA record
    //     (CreatedDate ASC) for the proposal
    private static SObject resolvePPARecord(Id proposalId, String ppaId) {
        List<String> fieldNames = getAccessibleFieldNames(Schema.SObjectType.Proposal_Participant_Association__c);
        String baseSelect = 'SELECT ' + String.join(fieldNames, ', ')
            + ' FROM Proposal_Participant_Association__c WHERE Proposal__c = :proposalId AND Roles__c=\'Supervisor\'';

        List<SObject> results;

        if (String.isNotBlank(ppaId)) {
            String query = baseSelect + ' AND Id = :ppaId LIMIT 1';
            results = Database.query(query);
        } else {
            String query = baseSelect + ' ORDER BY CreatedDate ASC LIMIT 1';
            results = Database.query(query);
        }

        return results.isEmpty() ? null : results[0];
    }

    // Resolves the Host Institution Name via Applicant_Host_Association__c -> Host__c (Account).
    // Falls back to the earliest AHA record (CreatedDate ASC) for the proposal if multiple exist.
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
    // Proposal Header (Proposal Reference Id / Applicant / Fellowship Type /
    // Host Institution Name) - independent of Reviewer Response Line Item /
    // question matching.
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
                    SELECT Id, Name, Salutation, FirstName, MiddleName, LastName
                    FROM Contact
                    WHERE Id = :resolvedContactId
                    LIMIT 1
                ];
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
    // Human Details (Human__c) - plain record list under the Proposal,
    // independent of Reviewer Response Line Item / question matching.
    // ===================================================================

    private static List<Human__c> buildHumanDetails(Id proposalId) {
        return [
            SELECT Id, Age_Maximum__c, Age_Minimum__c, Project_will_any_hospital_clinical_facil__c,
                    biohazards_are_associated_Biological__c
                   , CurrencyIsoCode,PersonalRegulatorybodiesethicalreview__c,
                    Details_of_stem_Cell_experiment_nature__c,
                   Eligibility_criteria__c, Biohazards_SafetyPrecaution__c, Name,regulatory_bodies_human_stem_cells__c,
                    Measure_taken_to_protect_privacy_rights__c,HumaRegulatory_bodies_for_ethical_review__c,
                   My_Project_Involve__c, Name_Address_of_Hospital_clinical__c,Details_of_source_of_personal_data__c,
                    Proposal__c,What_is_Protocol_for_waste_management__c,
                    Require_Consent_from_study_population__c,Regulatory_Bodies_Responsible__c,
                   Retention_and_retention_plan__c, Size_cal_including_statiscal_analysis__c,
                   Study_Population_Characteristics__c, Timeline__c, Biological_samples_nature_of_experimnt__c
                   
            FROM Human__c
            WHERE Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
        ];
    }

        // ===================================================================
    // Project Milestone Details (Project_Milestone__c) - plain record list
    // under the Proposal, independent of Reviewer Response Line Item /
    // question matching. Same pattern as buildHumanDetails.
    // ===================================================================

    private static List<Project_Milestone__c> buildProjectMilestones(Id proposalId) {
        return [
            SELECT Id, Name, CurrencyIsoCode, Deliverables_mapped_to_the_objective__c,
                   End_Date__c, Location_Expected_to_Deliver_Milestone__c,
                   Milestone__c, Proposal__c, Start_Date__c
            FROM Project_Milestone__c
            WHERE Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
        ];
    }

    // ===================================================================
    // Animal Details (Animals__c + child Animal_Species__c) - plain record
    // list under the Proposal, independent of Reviewer Response Line Item /
    // question matching. Two-pass read: parent Animals__c records first,
    // then child Animal_Species__c records in a single bulk query grouped
    // by parent Id - no SOQL in a loop.
    // ===================================================================

    private static List<AnimalWrapper> buildAnimalDetails(Id proposalId) {
        List<AnimalWrapper> wrappers = new List<AnimalWrapper>();

        List<Animals__c> animalRecords = [
            SELECT Id, Animal_Associated_Cost_Justification__c, Animal_Exp_Procedure_Cost_Justification__c,
                   Animal_Maintenance_Cost_Justification__c, Name, Animal_Purchase_Cost_Justification__c,
                   Animal_species__c, Any_procedures_of_substantial_Severity__c, biohazards_associated__c,
                   Budget__c, CurrencyIsoCode, Describe_procedure_to_be_implemented__c,
                   Exprmnt_on_animals_terminal__c, if_not_reviewed_by_IAEC_With_Timelines__c,
                   My_Proposal_Involves__c, Other_Animal_Names_to_be_Used__c, Proposal__c,
                   Proposal_Carried_out_on_animals__c, Proposed_source_of_the_animals__c,
                   Protocol_for_waste_management__c, Provide_details_of_source_of_stem_cellst__c,
                   Total_purchase_cost__c, Reviewed_by_IAEC_with_timelines__c,
                   Sample_size_justification_and_Power__c, Severity_of_the_procedures_on_the_animal__c,
                   Species_used__c, Total__c, Total_maintenance_and_procedure_cost__c,
                   Total_number_to_be_purchased__c, Why_is_animal_use_necessary__c,CCSEA_registration_number__c,
                   Why_is_are_the_species_most_appropriate__c
            FROM Animals__c
            WHERE Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
        ];

        if (animalRecords.isEmpty()) {
            return wrappers;
        }

        Set<Id> animalIds = new Map<Id, Animals__c>(animalRecords).keySet();

        List<Animal_Species__c> speciesRecords = [
            SELECT Id, Animal_Species__c, Name, Animal_Strain__c, Animals__c,
                   Experiment_Title__c, Group__c, No_of_Animals__c
            FROM Animal_Species__c
            WHERE Animals__c IN :animalIds
            ORDER BY CreatedDate ASC
        ];

        Map<Id, List<Animal_Species__c>> speciesByAnimalId = new Map<Id, List<Animal_Species__c>>();
        for (Animal_Species__c sp : speciesRecords) {
            if (!speciesByAnimalId.containsKey(sp.Animals__c)) {
                speciesByAnimalId.put(sp.Animals__c, new List<Animal_Species__c>());
            }
            speciesByAnimalId.get(sp.Animals__c).add(sp);
        }

        for (Animals__c animal : animalRecords) {
            AnimalWrapper aw = new AnimalWrapper();
            aw.animal = animal;
            aw.animalSpecies = speciesByAnimalId.containsKey(animal.Id)
                ? speciesByAnimalId.get(animal.Id)
                : new List<Animal_Species__c>();
            wrappers.add(aw);
        }

        return wrappers;
    }

    // ===================================================================
    // Host Institution Details (Applicant_Host_Association__c + Host__r
    // Account fields) - plain record list under the Proposal, independent
    // of Reviewer Response Line Item / question matching. Returns ALL AHA
    // records for the proposal (not just the earliest) since a proposal can
    // have multiple Host Institution associations.
    // ===================================================================

    private static List<Applicant_Host_Association__c> buildHostInstitutionDetails(Id proposalId) {
        return [
            SELECT Id, Name, CurrencyIsoCode, Is_the_Host_Instituition_not_for_profit__c,
                   Host__c, Host__r.Name, Host__r.Email__c, Host__r.District__c, Host__r.Phone,
                   Host__r.BillingStreet, Host__r.BillingCity, Host__r.BillingState,
                   Host__r.BillingPostalCode, Host__r.BillingCountry, Proposal__c
            FROM Applicant_Host_Association__c
            WHERE Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
        ];
    }

    // ===================================================================
    // Fellowship Supervisor Details (Proposal_Participant_Association__c +
    // Participant__r Contact fields) - plain record list under the
    // Proposal, independent of Reviewer Response Line Item / question
    // matching. Returns ALL PPA records for the proposal (Supervisor,
    // Sponsor, and any other participant roles), unlike the Roles__c =
    // 'Supervisor' filter used by resolvePPARecord for answer matching.
    // ===================================================================

    private static List<Proposal_Participant_Association__c> buildFellowshipSupervisors(Id proposalId) {
        return [
            SELECT Id, Name, Roles__c, Participant__c,
                   Participant__r.Name, Participant__r.Salutation, Participant__r.FirstName,
                   Participant__r.MiddleName, Participant__r.LastName, Participant__r.Suffix,
                   Participant__r.Account.Name, Participant__r.AccountId, Participant__r.Email,
                   Participant__r.Birthdate, Participant__r.Department, Participant__r.Gender__c,
                   Participant__r.Nationality__c, Participant__r.Position__c, Participant__r.Phone,
                   Participant__r.MailingStreet, Participant__r.MailingCity, Participant__r.MailingState,
                   Participant__r.MailingPostalCode, Participant__r.MailingCountry, Proposal__c
            FROM Proposal_Participant_Association__c
            WHERE Proposal__c = :proposalId AND Roles__c ='Supervisor'
            ORDER BY CreatedDate ASC
        ];
    }

    // ===================================================================
    // WOHI/Collaboration Details (WOHI_Collaboration__c + child
    // WOHI_Collaborator_Visit__c) - plain record list under the APA,
    // independent of Reviewer Response Line Item / question matching.
    // Two-pass read, same pattern as buildAnimalDetails: parent
    // WOHI_Collaboration__c records first, then child visit records in a
    // single bulk query grouped by parent Id - no SOQL in a loop.
    // ===================================================================

    private static List<WOHICollaborationWrapper> buildWOHICollaborations(Id apaId) {
        List<WOHICollaborationWrapper> wrappers = new List<WOHICollaborationWrapper>();

        if (apaId == null) {
            return wrappers;
        }

        List<WOHI_Collaboration__c> collabRecords = [
            SELECT Id, Applicant_Proposal_Association__c, City_Town__c, CurrencyIsoCode,
                   Current_Position__c, Department__c, District__c, Email__c,
                   Expected_outcome_from_each_visit__c, Expertise__c,Will_the_collaboration_require_MTA__c,
                   Extent_and_nature_of_Collaborator__c, FirstName__c, Gender__c,
                   Invitation_Link__c, Last_Name__c, Nationality__c, Notified__c,
                   Organisation__c, Postcode__c, Scientific_Justification_for_WOHI_lab__c,
                   State__c, Status__c, TelephoneNo__c, Title__c, Type__c,
                    Name,
                   Years_of_Experience_as_independent_PI__c
            FROM WOHI_Collaboration__c
            WHERE Applicant_Proposal_Association__c = :apaId
            ORDER BY CreatedDate ASC
        ];

        if (collabRecords.isEmpty()) {
            return wrappers;
        }

        Set<Id> collabIds = new Map<Id, WOHI_Collaboration__c>(collabRecords).keySet();

        List<WOHI_Collaborator_Visit__c> visitRecords = [
            SELECT Id, Duration_of_visit_in_months__c, End_Date__c, Name__c,
                   Organisation__c, Position__c, Start_Date__c,
                   Visit_is_related_to_Aim_Objective_No__c, WOHI_Collaboration__c, Name
            FROM WOHI_Collaborator_Visit__c
            WHERE WOHI_Collaboration__c IN :collabIds
            ORDER BY CreatedDate ASC
        ];

        Map<Id, List<WOHI_Collaborator_Visit__c>> visitsByCollabId = new Map<Id, List<WOHI_Collaborator_Visit__c>>();
        for (WOHI_Collaborator_Visit__c v : visitRecords) {
            if (!visitsByCollabId.containsKey(v.WOHI_Collaboration__c)) {
                visitsByCollabId.put(v.WOHI_Collaboration__c, new List<WOHI_Collaborator_Visit__c>());
            }
            visitsByCollabId.get(v.WOHI_Collaboration__c).add(v);
        }

        for (WOHI_Collaboration__c collab : collabRecords) {
            WOHICollaborationWrapper ww = new WOHICollaborationWrapper();
            ww.collaboration = collab;
            ww.visits = visitsByCollabId.containsKey(collab.Id)
                ? visitsByCollabId.get(collab.Id)
                : new List<WOHI_Collaborator_Visit__c>();
            wrappers.add(ww);
        }

        return wrappers;
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
        ppaBundle = buildBundle(
            Schema.SObjectType.Proposal_Participant_Association__c,
            'Proposal_Participant_Association__c'
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

    private static QAWrapper buildQAWrapper(
        Reviewer_Response_Line_Item__c li,
        SObject proposalRecord,
        SObject apaRecord,
        SObject contactRecord,
        SObject ppaRecord
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

        // 4. Fall back to Proposal_Participant_Association__c (PPA) if still blank
        if (answerValue == null && ppaRecord != null) {
            String ppaFieldApiName = matchField(normalizedQuestion, ppaBundle);
            if (ppaFieldApiName != null) {
                answerValue = ppaRecord.get(ppaFieldApiName);
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
        SObject contactRecord,
        SObject ppaRecord
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
            QAWrapper qa = buildQAWrapper(li, proposalRecord, apaRecord, contactRecord, ppaRecord);

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
        public List<Human__c> humanDetails;
        public List<Project_Milestone__c> projectMilestones;
        public List<AnimalWrapper> animalDetails;
        public List<Applicant_Host_Association__c> hostInstitutionDetails;
        public List<Proposal_Participant_Association__c> fellowshipSupervisors;
        public List<WOHICollaborationWrapper> wohiCollaborations;
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

    // Animals__c parent + its Animal_Species__c children (master-detail),
    // grouped together since a single flat Animals__c list would drop the
    // per-species/strain breakdown.
    global class AnimalWrapper {
        public Animals__c animal;
        public List<Animal_Species__c> animalSpecies;
    }

    // WOHI_Collaboration__c parent + its WOHI_Collaborator_Visit__c children,
    // grouped together for the same reason as AnimalWrapper.
    global class WOHICollaborationWrapper {
        public WOHI_Collaboration__c collaboration;
        public List<WOHI_Collaborator_Visit__c> visits;
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