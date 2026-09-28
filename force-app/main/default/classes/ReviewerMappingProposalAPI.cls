@RestResource(urlMapping='/reviewerMappingProposal/*')
global without sharing class ReviewerMappingProposalAPI {

    @HttpGet
    global static ResponseWrapper getProposalByReviewerMapping() {
        ResponseWrapper response = new ResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String reviewerMappingId = req.params.get('reviewerMappingId');
            String apaId = req.params.get('apaId');

            if (String.isBlank(reviewerMappingId) && String.isBlank(apaId)) {
                response.success = false;
                response.message = 'Provide either reviewerMappingId or apaId';
                return response;
            }

            Id proposalId;

            if (String.isNotBlank(apaId)) {
                // ---- Use provided APA Id to resolve proposal and contact ---- //
                List<Applicant_Proposal_Association__c> apas = [
                    SELECT Id, Proposal__c, Contact__c,
                           Contact__r.Salutation, Contact__r.Title, Contact__r.Title__c,
                           Contact__r.Name, Contact__r.Account.Name,
                           Proposal__r.Proposal_Id__c,
                           Proposal__r.Project_Title__c,
                           Proposal__r.Research_Title__c,
                           Proposal__r.Outline_of_proposed_research__c,
                           Proposal__r.Grand_Total_Cost__c,
                           Abstract_Ongoing__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaId
                    LIMIT 1
                ];

                if (apas.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId';
                    return response;
                }

                Applicant_Proposal_Association__c apa = apas[0];
                if (apa.Proposal__c == null) {
                    response.success = false;
                    response.message = 'No Proposal linked to the given apaId';
                    return response;
                }

                proposalId = apa.Proposal__c;

                ProposalWrapper proposal = new ProposalWrapper();
                proposal.proposalRecordId = apa.Proposal__c;
                proposal.proposalId = apa.Proposal__r.Proposal_Id__c;
                proposal.projectTitle = apa.Proposal__r.Project_Title__c;
                proposal.researchTitle = apa.Proposal__r.Research_Title__c;
                proposal.abstractText = String.isNotBlank(apa.Proposal__r.Outline_of_proposed_research__c)
                    ? apa.Proposal__r.Outline_of_proposed_research__c
                    : apa.Abstract_Ongoing__c;
                proposal.requestedAmount = apa.Proposal__r.Grand_Total_Cost__c;
                response.proposal = proposal;

                if (apa.Contact__r != null) {
                    ContactWrapper cw = new ContactWrapper();
                    String title = resolveTitle(apa.Contact__r);
                    cw.title = title;
                    cw.name = buildDisplayName(apa.Contact__r, title);
                    cw.accountName = apa.Contact__r.Account != null ? apa.Contact__r.Account.Name : null;
                    response.applicantContact = cw;
                }
            } else {
                // ---- Use Reviewer Mapping Id to resolve proposal ----
                List<Reviewer_Mapping__c> mappings = [
                    SELECT Id, Reviewer__c, Proposal__c,
                           Proposal__r.Proposal_Id__c,
                           Proposal__r.Project_Title__c,
                           Proposal__r.Research_Title__c,
                           Proposal__r.Outline_of_proposed_research__c,
                           Proposal__r.Grand_Total_Cost__c
                    FROM Reviewer_Mapping__c
                    WHERE Id = :reviewerMappingId
                    LIMIT 1
                ];

                if (mappings.isEmpty()) {
                    response.success = false;
                    response.message = 'No Reviewer Mapping found for the given reviewerMappingId';
                    return response;
                }

                Reviewer_Mapping__c mapping = mappings[0];
                response.reviewerMappingId = mapping.Id;

                if (mapping.Proposal__c == null) {
                    response.success = false;
                    response.message = 'No Proposal linked to the given Reviewer Mapping';
                    return response;
                }

                proposalId = mapping.Proposal__c;

                ProposalWrapper proposal = new ProposalWrapper();
                proposal.proposalRecordId = mapping.Proposal__c;
                proposal.proposalId = mapping.Proposal__r.Proposal_Id__c;
                proposal.projectTitle = mapping.Proposal__r.Project_Title__c;
                proposal.researchTitle = mapping.Proposal__r.Research_Title__c;
                proposal.requestedAmount = mapping.Proposal__r.Grand_Total_Cost__c;

                // ---- First Applicant Proposal Association and its Contact ---- //
                List<Applicant_Proposal_Association__c> apas = [
                    SELECT Id, Contact__c, Contact__r.Salutation, Contact__r.Title, Contact__r.Title__c,
                           Contact__r.Name, Contact__r.Account.Name, Contact__r.Position__c,
                           Abstract_Ongoing__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :proposalId
                    AND Contact__c != null
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ];

                Applicant_Proposal_Association__c apa = null;
                if (!apas.isEmpty()) {
                    apa = apas[0];

                    ContactWrapper cw = new ContactWrapper();
                    String title = resolveTitle(apa.Contact__r);
                    cw.title = title;
                    cw.name = buildDisplayName(apa.Contact__r, title);
                    cw.accountName = apa.Contact__r != null && apa.Contact__r.Account != null
                        ? apa.Contact__r.Account.Name
                        : null;
                    cw.position = apa.Contact__r != null ? apa.Contact__r.Position__c : null;
                    response.applicantContact = cw;
                }

                proposal.abstractText = String.isNotBlank(mapping.Proposal__r.Outline_of_proposed_research__c)
                    ? mapping.Proposal__r.Outline_of_proposed_research__c
                    : (apa != null ? apa.Abstract_Ongoing__c : null);
                response.proposal = proposal;
            }

            response.proposalParticipants = getParticipants(proposalId);

            response.success = true;
            response.message = 'Proposal and participant details fetched successfully';
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
        }

        return response;
    }

    /**
     * Returns participants from ALL sources combined into one list
     * (same ParticipantWrapper for every source):
     *   1. Proposal_Participant_Association__c (PPA)
     *   2. Additional_Partcipant__c
     *   3. WOHI_Collaboration__c (linked via Applicant_Proposal_Association__c)
     */
    private static List<ParticipantWrapper> getParticipants(Id proposalId) {
        List<ParticipantWrapper> participants = new List<ParticipantWrapper>();

        // ---- Source 1: PPA ---- //
        List<Proposal_Participant_Association__c> ppaRecords = [
            SELECT Id, Participant__c, Participant__r.Name, Participant__r.Position__c,
                   Participant__r.Account.Name, Roles__c, Proposal__c
            FROM Proposal_Participant_Association__c
            WHERE Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
        ];

        for (Proposal_Participant_Association__c ppa : ppaRecords) {
            ParticipantWrapper pw = new ParticipantWrapper();
            pw.participantName = ppa.Participant__r != null ? ppa.Participant__r.Name : null;
            pw.participantPosition = ppa.Participant__r != null ? ppa.Participant__r.Position__c : null;
            pw.participantOrganization = (ppa.Participant__r != null && ppa.Participant__r.Account != null)
                ? ppa.Participant__r.Account.Name
                : null;
            pw.role = ppa.Roles__c;
            participants.add(pw);
        }

        // ---- Source 2: Additional Participants ---- //
        List<Additional_Partcipant__c> additionalParticipants = [
            SELECT Id, Full_Name__c, Designation__c, Organisation__c, Roles__c
            FROM Additional_Partcipant__c
            WHERE Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
        ];

        for (Additional_Partcipant__c ap : additionalParticipants) {
            ParticipantWrapper pw = new ParticipantWrapper();
            pw.participantName = ap.Full_Name__c;
            pw.participantPosition = ap.Designation__c;
            pw.participantOrganization = ap.Organisation__c;
            pw.role = ap.Roles__c;
            participants.add(pw);
        }

        // ---- Source 3: WOHI Collaborations (linked via APA) ---- //
        List<WOHI_Collaboration__c> wohiRecords = [
            SELECT Id, Full_Name__c, Current_Position__c, Organisation__c, Roles__c,Type__c
            FROM WOHI_Collaboration__c
            WHERE Applicant_Proposal_Association__r.Proposal__c = :proposalId
            ORDER BY CreatedDate ASC
        ];

        for (WOHI_Collaboration__c wc : wohiRecords) {
            ParticipantWrapper pw = new ParticipantWrapper();
            pw.participantName = wc.Full_Name__c;
            pw.participantPosition = wc.Current_Position__c;
            pw.participantOrganization = wc.Organisation__c;
            //pw.role = wc.Type__c == 'Collaborator' ? 'Collaborator' : wc.Roles__c;
            if (wc.Type__c == 'Collaborator') {
                    pw.role = 'Collaborator';
                } else if (wc.Type__c == 'WOHI' && String.isBlank(wc.Roles__c)) {
                    pw.role = 'External Sponsor';
                } else {
                    pw.role = wc.Roles__c;
                }
            participants.add(pw);
        }

        return participants;
    }

    private static String resolveTitle(SObject contact) {
        if (contact == null) return null;

        String salutation = (String) contact.get('Salutation');
        if (String.isNotBlank(salutation)) return salutation;

        String title = (String) contact.get('Title');
        if (String.isNotBlank(title)) return title;

        String titleCustom = (String) contact.get('Title__c');
        if (String.isNotBlank(titleCustom)) return titleCustom;

        return null;
    }

    private static String buildDisplayName(SObject contact, String title) {
        if (contact == null) return null;

        String name = (String) contact.get('Name');
        if (String.isNotBlank(title) && String.isNotBlank(name)) {
            return title + ' ' + name;
        }

        return name;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public String reviewerMappingId;
        public ProposalWrapper proposal;
        public ContactWrapper applicantContact;
        public List<ParticipantWrapper> proposalParticipants;
    }

    global class ProposalWrapper {
        public String proposalRecordId;
        public String proposalId;
        public String projectTitle;
        public String researchTitle;
        public String abstractText;
        public Decimal requestedAmount;
    }

    global class ContactWrapper {
        public String title;
        public String name;
        public String position;
        public String accountName;
    }

    global class ParticipantWrapper {
        public String participantName;
        public String participantPosition;
        public String participantOrganization;
        public String role;
    }
}




/*
@RestResource(urlMapping='/reviewerMappingProposal/*')
global without sharing class ReviewerMappingProposalAPI {

    @HttpGet
    global static ResponseWrapper getProposalByReviewerMapping() {
        ResponseWrapper response = new ResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String reviewerMappingId = req.params.get('reviewerMappingId');
            String apaId = req.params.get('apaId');

            if (String.isBlank(reviewerMappingId) && String.isBlank(apaId)) {
                response.success = false;
                response.message = 'Provide either reviewerMappingId or apaId';
                return response;
            }

            Id proposalId;

            if (String.isNotBlank(apaId)) {
                // ---- Use provided APA Id to resolve proposal and contact ---- //
                List<Applicant_Proposal_Association__c> apas = [
                    SELECT Id, Proposal__c, Contact__c,
                           Contact__r.Salutation, Contact__r.Title, Contact__r.Title__c,
                           Contact__r.Name, Contact__r.Account.Name,
                           Proposal__r.Proposal_Id__c,
                           Proposal__r.Project_Title__c,
                           Proposal__r.Research_Title__c,
                           Proposal__r.Requested_Amount__c,
                           Abstract_Ongoing__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaId
                    LIMIT 1
                ];

                if (apas.isEmpty()) {
                    response.success = false;
                    response.message = 'No Applicant Proposal Association found for the given apaId';
                    return response;
                }

                Applicant_Proposal_Association__c apa = apas[0];
                if (apa.Proposal__c == null) {
                    response.success = false;
                    response.message = 'No Proposal linked to the given apaId';
                    return response;
                }

                proposalId = apa.Proposal__c;

                ProposalWrapper proposal = new ProposalWrapper();
                proposal.proposalRecordId = apa.Proposal__c;
                proposal.proposalId = apa.Proposal__r.Proposal_Id__c;
                proposal.projectTitle = apa.Proposal__r.Project_Title__c;
                proposal.researchTitle = apa.Proposal__r.Research_Title__c;
                proposal.abstractText = String.isNotBlank(apa.Proposal__r.Abstract_of_proposed_work__c)
                    ? apa.Proposal__r.Abstract_of_proposed_work__c
                    : apa.Abstract_Ongoing__c ;
                proposal.requestedAmount = apa.Proposal__r.Requested_Amount__c;
                response.proposal = proposal;

                if (apa.Contact__r != null) {
                    ContactWrapper cw = new ContactWrapper();
                    String title = resolveTitle(apa.Contact__r);
                    cw.title = title;
                    cw.name = buildDisplayName(apa.Contact__r, title);
                    cw.accountName = apa.Contact__r.Account != null ? apa.Contact__r.Account.Name : null;
                    response.applicantContact = cw;
                }
            } else {
                // ---- Use Reviewer Mapping Id to resolve proposal ----
                List<Reviewer_Mapping__c> mappings = [
                    SELECT Id, Reviewer__c, Proposal__c,
                           Proposal__r.Proposal_Id__c,
                           Proposal__r.Project_Title__c,
                           Proposal__r.Research_Title__c,
                           Proposal__r.Abstract_of_proposed_work__c,
                           Proposal__r.Requested_Amount__c
                    FROM Reviewer_Mapping__c
                    WHERE Id = :reviewerMappingId
                    LIMIT 1
                ];

                if (mappings.isEmpty()) {
                    response.success = false;
                    response.message = 'No Reviewer Mapping found for the given reviewerMappingId';
                    return response;
                }

                Reviewer_Mapping__c mapping = mappings[0];
                response.reviewerMappingId = mapping.Id;

                if (mapping.Proposal__c == null) {
                    response.success = false;
                    response.message = 'No Proposal linked to the given Reviewer Mapping';
                    return response;
                }

                proposalId = mapping.Proposal__c;

                ProposalWrapper proposal = new ProposalWrapper();
                proposal.proposalRecordId = mapping.Proposal__c;
                proposal.proposalId = mapping.Proposal__r.Proposal_Id__c;
                proposal.projectTitle = mapping.Proposal__r.Project_Title__c;
                proposal.researchTitle = mapping.Proposal__r.Research_Title__c;
                proposal.requestedAmount = mapping.Proposal__r.Requested_Amount__c;

                // ---- First Applicant Proposal Association and its Contact ---- //
                List<Applicant_Proposal_Association__c> apas = [
                    SELECT Id, Contact__c, Contact__r.Salutation, Contact__r.Title, Contact__r.Title__c,
                           Contact__r.Name, Contact__r.Account.Name, Contact__r.Position__c,
                           Abstract_Ongoing__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Proposal__c = :proposalId
                    AND Contact__c != null
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ];

                Applicant_Proposal_Association__c apa = null;
                if (!apas.isEmpty()) {
                    apa = apas[0];

                    ContactWrapper cw = new ContactWrapper();
                    String title = resolveTitle(apa.Contact__r);
                    cw.title = title;
                    cw.name = buildDisplayName(apa.Contact__r, title);
                    cw.accountName = apa.Contact__r != null && apa.Contact__r.Account != null
                        ? apa.Contact__r.Account.Name
                        : null;
                    cw.position = apa.Contact__r != null ? apa.Contact__r.Position__c : null;
                    response.applicantContact = cw;
                }

                proposal.abstractText = String.isNotBlank(mapping.Proposal__r.Abstract_of_proposed_work__c)
                    ? mapping.Proposal__r.Abstract_of_proposed_work__c
                    : (apa != null ? apa.Abstract_Ongoing__c : null);
                response.proposal = proposal;
            }

            List<Proposal_Participant_Association__c> ppaRecords = [
                SELECT Id, Participant__c, Participant__r.Name, Participant__r.Position__c, Participant__r.Account.Name,
                Roles__c, Proposal__c
                FROM Proposal_Participant_Association__c
                WHERE Proposal__c = :proposalId
                ORDER BY CreatedDate ASC
            ];

            response.proposalParticipants = new List<ParticipantWrapper>();
            for (Proposal_Participant_Association__c ppa : ppaRecords) {
                ParticipantWrapper pw = new ParticipantWrapper();
                // pw.participantAssociationId = ppa.Id;
                // pw.participantId = ppa.Participant__c;
                pw.participantName = ppa.Participant__r != null ? ppa.Participant__r.Name : null;
                pw.participantPosition = ppa.Participant__r != null ? ppa.Participant__r.Position__c : null;
                pw.participantOrganization = ppa.Participant__r != null ? ppa.Participant__r.Account.Name : null;

                pw.role = ppa.Roles__c;
                response.proposalParticipants.add(pw);
            }

            response.success = true;
            response.message = 'Proposal and participant details fetched successfully';
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
        }

        return response;
    }

    private static String resolveTitle(SObject contact) {
        if (contact == null) return null;

        String salutation = (String) contact.get('Salutation');
        if (String.isNotBlank(salutation)) return salutation;

        String title = (String) contact.get('Title');
        if (String.isNotBlank(title)) return title;

        String titleCustom = (String) contact.get('Title__c');
        if (String.isNotBlank(titleCustom)) return titleCustom;

        return null;
    }

    private static String buildDisplayName(SObject contact, String title) {
        if (contact == null) return null;

        String name = (String) contact.get('Name');
        if (String.isNotBlank(title) && String.isNotBlank(name)) {
            return title + ' ' + name;
        }

        return name;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public String reviewerMappingId;
        public ProposalWrapper proposal;
        public ContactWrapper applicantContact;
        public List<ParticipantWrapper> proposalParticipants;
    }

    global class ProposalWrapper {
        public String proposalRecordId;
        public String proposalId;
        public String projectTitle;
        public String researchTitle;
        public String abstractText;
        public Decimal requestedAmount;
    }

    global class ContactWrapper {
        public String title;
        public String name;
        public String position;
        public String accountName;
    }

    global class ParticipantWrapper {
        public String participantName;
        public String participantPosition;
        public String participantOrganization;
        public String role;
    }
}
*/