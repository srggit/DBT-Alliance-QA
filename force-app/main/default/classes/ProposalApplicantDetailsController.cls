public with sharing class ProposalApplicantDetailsController {

    private static final Set<String> EXCLUDED_FIELDS = new Set<String>{
        'CreatedDate',
        'LastModifiedDate',
        'CreatedById',
        'LastModifiedById',
        'SystemModstamp',
        'OwnerId',
        'RecordTypeId',
        'CurrencyIsoCode',
        'IsDeleted',
        'LastViewedDate',
        'LastReferencedDate',
        'Yearly_Scheme__c',
        'Password',
        'Password_Hash',
        'Password__c',
        'Password_Hash__c'
    };

    @AuraEnabled
    public static List<Scheme_Section__c> getSchemeSectionsForProposal(Id proposalId) {
        if (String.isBlank(proposalId)) {
            return new List<Scheme_Section__c>();
        }
        List<Proposal__c> proposals = [
            SELECT Application_Stages__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];
        if (proposals.isEmpty()) {
            return new List<Scheme_Section__c>();
        }
        return [
            SELECT Id, Name, Section_Name__c, Data_Filled_Successfully__c, Reopen_Status__c,
                   Re_Opening_Reason__c, Application_Stages__c
            FROM Scheme_Section__c
            WHERE Applicant_Proposal_Association__r.Proposal__c = :proposalId
            AND Application_Stages__c = :proposals[0].Application_Stages__c
            AND Can_Reopen_This_Section__c = TRUE
            ORDER BY Name
        ];
    }

    // Takes the request list as a JSON string rather than List<SectionReopenRequest> directly -
    // the LWC->Apex wire binding for a bare List<InnerWrapperClass> parameter was silently
    // dropping field values (reason came through blank server-side even though the client had
    // confirmed, via console logging, that it was sending a non-blank reason) - serializing on
    // the client and deserializing here with JSON.deserialize sidesteps that wire quirk entirely.
    @AuraEnabled
    public static void reopenSchemeSections(String sectionRequestsJson) {
        if (String.isBlank(sectionRequestsJson)) {
            return;
        }
        List<SectionReopenRequest> sectionRequests = (List<SectionReopenRequest>) JSON.deserialize(
            sectionRequestsJson,
            List<SectionReopenRequest>.class
        );
        if (sectionRequests == null || sectionRequests.isEmpty()) {
            return;
        }
        List<Scheme_Section__c> sections = new List<Scheme_Section__c>();
        for (SectionReopenRequest req : sectionRequests) {
            if (String.isBlank(req.reason)) {
                throw new AuraHandledException('A reopening reason is required for every selected section.');
            }
            sections.add(new Scheme_Section__c(
                Id = req.sectionId,
                Reopen_Status__c = 'Reopen',
                Re_Opening_Reason__c = req.reason
            ));
        }
        update sections;
    }

    public class SectionReopenRequest {
        @AuraEnabled
        public Id sectionId;
        @AuraEnabled
        public String reason;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getProposalSummary(Id proposalId) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(proposalId)) {
            return result;
        }

        List<Proposal__c> proposals = [
            SELECT Proposal_Id__c, Application_Stages__c, Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];
        if (proposals.isEmpty()) {
            return result;
        }
        Proposal__c proposal = proposals[0];

        String applicantName;
        for (Applicant_Proposal_Association__c apa : [
            SELECT Contact__r.Name
            FROM Applicant_Proposal_Association__c
            WHERE Proposal__c = :proposalId
            AND Contact__c != null
            ORDER BY CreatedDate ASC
            LIMIT 1
        ]) {
            applicantName = apa.Contact__r.Name;
        }

        result.put('proposalIdDisplay', proposal.Proposal_Id__c);
        result.put('applicationStage', proposal.Application_Stages__c);
        result.put('applicantName', applicantName);
        result.put(
            'schemeItemName',
            proposal.Yearly_Scheme__r != null && proposal.Yearly_Scheme__r.Scheme_Items__r != null
                ? proposal.Yearly_Scheme__r.Scheme_Items__r.Name
                : null
        );
        return result;
    }

    // Not cacheable: this reads the full, live state of the Proposal and every
    // related object (Animals__c, Project_Milestone__c, etc.), all of which keep
    // changing behind the scenes as the application is worked on and as new
    // fields/sections get added here - a cacheable read can silently serve a
    // stale response from before those changes, with no error to explain why
    // data appears to be missing.
    @AuraEnabled
    public static Map<String, Object> getProposalDetails(Id proposalId) {
        if (String.isBlank(proposalId)) {
            throw new AuraHandledException('Proposal Id is required.');
        }

        String proposalFields = getQueryableFieldList('Proposal__c');
        List<SObject> proposals = new List<SObject>();
        if (!String.isBlank(proposalFields)) {
            proposals = Database.query('SELECT ' + proposalFields + ' FROM Proposal__c WHERE Id = :proposalId');
        }
        if (proposals.isEmpty()) {
            throw new AuraHandledException('Proposal not found or you do not have access.');
        }

        Map<String, Object> result = new Map<String, Object>();
        result.put('proposal', toMap(proposals[0]));

        String proposalStage = (String) proposals[0].get('Application_Stages__c');

        String schemeItemName;
        List<Proposal__c> schemeInfo = [
            SELECT Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];
        if (!schemeInfo.isEmpty()
            && schemeInfo[0].Yearly_Scheme__r != null
            && schemeInfo[0].Yearly_Scheme__r.Scheme_Items__r != null) {
            schemeItemName = schemeInfo[0].Yearly_Scheme__r.Scheme_Items__r.Name;
        }
        result.put('schemeItemName', schemeItemName);

        String applicantFields = getQueryableFieldList('Applicant_Proposal_Association__c');
        List<SObject> applicants = new List<SObject>();
        if (!String.isBlank(applicantFields)) {
            applicants = Database.query('SELECT ' + applicantFields + ' FROM Applicant_Proposal_Association__c WHERE Proposal__c = :proposalId');
        }

        List<Map<String, Object>> applicantMaps = new List<Map<String, Object>>();
        Set<Id> applicantIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (SObject applicant : applicants) {
            Map<String, Object> applicantMap = toMap(applicant);
            applicantMaps.add(applicantMap);
            applicantIds.add((Id) applicant.get('Id'));
            if (applicant.get('Contact__c') != null) {
                contactIds.add((Id) applicant.get('Contact__c'));
            }
        }
        result.put('applicants', applicantMaps);

        List<Map<String, Object>> contactMaps = new List<Map<String, Object>>();
        if (!contactIds.isEmpty()) {
            String contactFields = getQueryableFieldList('Contact');
            if (!String.isBlank(contactFields)) {
                for (SObject contact : Database.query('SELECT ' + contactFields + ' FROM Contact WHERE Id IN :contactIds')) {
                    contactMaps.add(toMap(contact));
                }
            }
        }
        result.put('contacts', contactMaps);

        List<Map<String, Object>> participantMaps = new List<Map<String, Object>>();
        String participantLookupField = getLookupFieldName('Proposal_Participant_Association__c', 'Proposal__c');
        if (!String.isBlank(participantLookupField)) {
            String participantFields = getQueryableFieldList('Proposal_Participant_Association__c');
            if (!String.isBlank(participantFields)) {
                String participantQuery = 'SELECT ' + participantFields + ' FROM Proposal_Participant_Association__c WHERE ' +
                    participantLookupField + ' = :proposalId';
                if (!String.isBlank(proposalStage)) {
                    participantQuery += ' AND Stage__c = :proposalStage';
                }
                List<SObject> participantRecords = Database.query(participantQuery);

                String participantContactLookup = getLookupFieldName('Proposal_Participant_Association__c', 'Contact');
                Map<Id, Map<String, Object>> contactDataById = new Map<Id, Map<String, Object>>();
                if (!String.isBlank(participantContactLookup)) {
                    Set<Id> participantContactIds = new Set<Id>();
                    for (SObject participant : participantRecords) {
                        Id contactId = (Id) participant.get(participantContactLookup);
                        if (contactId != null) {
                            participantContactIds.add(contactId);
                        }
                    }
                    if (!participantContactIds.isEmpty()) {
                        String contactFields = getQueryableFieldList('Contact');
                        if (!String.isBlank(contactFields)) {
                            for (SObject contact : Database.query(
                                'SELECT ' + contactFields + ' FROM Contact WHERE Id IN :participantContactIds'
                            )) {
                                contactDataById.put((Id) contact.get('Id'), toMap(contact));
                            }
                        }
                    }
                }

                for (SObject participant : participantRecords) {
                    Map<String, Object> participantMap = toMap(participant);
                    if (!String.isBlank(participantContactLookup)) {
                        Id contactId = (Id) participant.get(participantContactLookup);
                        if (contactId != null && contactDataById.containsKey(contactId)) {
                            participantMap.put('contactData', contactDataById.get(contactId));
                        }
                    }
                    participantMaps.add(participantMap);
                }
            }
        }
        result.put('participants', participantMaps);

        // Fellowship Supervisor (Roles__c = 'Supervisor') is looked up on its own,
        // deliberately WITHOUT the Stage__c filter above - the same Supervisor
        // record set up during Prelims should keep showing on the Full form even
        // though it was never re-created with Stage__c = 'Full'.
        Map<String, Object> supervisorParticipantMap = new Map<String, Object>();
        if (!String.isBlank(participantLookupField)) {
            String supervisorFields = getQueryableFieldList('Proposal_Participant_Association__c');
            if (!String.isBlank(supervisorFields)) {
                List<SObject> supervisorRecords = Database.query(
                    'SELECT ' + supervisorFields + ' FROM Proposal_Participant_Association__c WHERE ' +
                    participantLookupField + ' = :proposalId AND Roles__c = \'Supervisor\' ' +
                    'ORDER BY CreatedDate DESC LIMIT 1'
                );
                if (!supervisorRecords.isEmpty()) {
                    SObject supervisorRecord = supervisorRecords[0];
                    supervisorParticipantMap = toMap(supervisorRecord);

                    String supervisorContactLookup = getLookupFieldName('Proposal_Participant_Association__c', 'Contact');
                    if (!String.isBlank(supervisorContactLookup)) {
                        Id supervisorContactId = (Id) supervisorRecord.get(supervisorContactLookup);
                        if (supervisorContactId != null) {
                            String contactFields = getQueryableFieldList('Contact');
                            if (!String.isBlank(contactFields)) {
                                List<SObject> supervisorContacts = Database.query(
                                    'SELECT ' + contactFields + ' FROM Contact WHERE Id = :supervisorContactId LIMIT 1'
                                );
                                if (!supervisorContacts.isEmpty()) {
                                    supervisorParticipantMap.put('contactData', toMap(supervisorContacts[0]));
                                }
                            }
                        }
                    }
                }
            }
        }
        result.put('supervisorParticipant', supervisorParticipantMap);

        List<Map<String, Object>> additionalParticipantMaps = new List<Map<String, Object>>();
        String additionalParticipantLookupField = getLookupFieldName('Additional_Partcipant__c', 'Proposal__c');
        if (!String.isBlank(additionalParticipantLookupField)) {
            String additionalParticipantFields = getQueryableFieldList('Additional_Partcipant__c');
            if (!String.isBlank(additionalParticipantFields)) {
                String additionalParticipantQuery = 'SELECT ' + additionalParticipantFields + ' FROM Additional_Partcipant__c WHERE ' +
                    additionalParticipantLookupField + ' = :proposalId';
                if (!String.isBlank(proposalStage)) {
                    additionalParticipantQuery += ' AND Stage__c = :proposalStage';
                }
                List<SObject> additionalParticipantRecords = Database.query(additionalParticipantQuery);
                for (SObject additionalParticipant : additionalParticipantRecords) {
                    additionalParticipantMaps.add(toMap(additionalParticipant));
                }
            }
        }
        result.put('additionalParticipants', additionalParticipantMaps);

        // Referees (Additional_Partcipant__c, Roles__c = 'Referee') - looked up
        // WITHOUT the Stage__c filter above, same reasoning as Supervisor: a
        // referee added earlier should keep showing on the Full form.
        List<Map<String, Object>> refereeMaps = new List<Map<String, Object>>();
        if (!String.isBlank(additionalParticipantLookupField)) {
            String refereeFields = getQueryableFieldList('Additional_Partcipant__c');
            if (!String.isBlank(refereeFields)) {
                List<SObject> refereeRecords = Database.query(
                    'SELECT ' + refereeFields + ' FROM Additional_Partcipant__c WHERE ' +
                    additionalParticipantLookupField + ' = :proposalId AND Roles__c = \'Referee\''
                );
                for (SObject refereeRecord : refereeRecords) {
                    refereeMaps.add(toMap(refereeRecord));
                }
            }
        }
        result.put('referees', refereeMaps);

        // Sponsors (Proposal_Participant_Association__c, Roles__c = 'Sponsor')
        // with their linked Contact - also unfiltered by Stage__c, same reasoning.
        List<Map<String, Object>> sponsorMaps = new List<Map<String, Object>>();
        if (!String.isBlank(participantLookupField)) {
            String sponsorFields = getQueryableFieldList('Proposal_Participant_Association__c');
            if (!String.isBlank(sponsorFields)) {
                List<SObject> sponsorRecords = Database.query(
                    'SELECT ' + sponsorFields + ' FROM Proposal_Participant_Association__c WHERE ' +
                    participantLookupField + ' = :proposalId AND Roles__c = \'Sponsor\''
                );

                String sponsorContactLookup = getLookupFieldName('Proposal_Participant_Association__c', 'Contact');
                Map<Id, Map<String, Object>> sponsorContactDataById = new Map<Id, Map<String, Object>>();
                if (!String.isBlank(sponsorContactLookup)) {
                    Set<Id> sponsorContactIds = new Set<Id>();
                    for (SObject sponsorRecord : sponsorRecords) {
                        Id sponsorContactId = (Id) sponsorRecord.get(sponsorContactLookup);
                        if (sponsorContactId != null) {
                            sponsorContactIds.add(sponsorContactId);
                        }
                    }
                    if (!sponsorContactIds.isEmpty()) {
                        String contactFields = getQueryableFieldList('Contact');
                        if (!String.isBlank(contactFields)) {
                            for (SObject contact : Database.query(
                                'SELECT ' + contactFields + ' FROM Contact WHERE Id IN :sponsorContactIds'
                            )) {
                                sponsorContactDataById.put((Id) contact.get('Id'), toMap(contact));
                            }
                        }
                    }
                }

                for (SObject sponsorRecord : sponsorRecords) {
                    Map<String, Object> sponsorMap = toMap(sponsorRecord);
                    if (!String.isBlank(sponsorContactLookup)) {
                        Id sponsorContactId = (Id) sponsorRecord.get(sponsorContactLookup);
                        if (sponsorContactId != null && sponsorContactDataById.containsKey(sponsorContactId)) {
                            sponsorMap.put('contactData', sponsorContactDataById.get(sponsorContactId));
                        }
                    }
                    sponsorMaps.add(sponsorMap);
                }
            }
        }
        result.put('sponsors', sponsorMaps);

        List<Map<String, Object>> hostAssociationMaps = new List<Map<String, Object>>();
        Map<String, Object> hostAccountMap = new Map<String, Object>();
        String hostAssociationLookupField = getLookupFieldName('Applicant_Host_Association__c', 'Proposal__c');
        if (!String.isBlank(hostAssociationLookupField)) {
            String hostAssociationFields = getQueryableFieldList('Applicant_Host_Association__c');
            if (!String.isBlank(hostAssociationFields)) {
                List<SObject> hostAssociationRecords = Database.query(
                    'SELECT ' + hostAssociationFields + ' FROM Applicant_Host_Association__c WHERE ' +
                    hostAssociationLookupField + ' = :proposalId ORDER BY CreatedDate ASC LIMIT 1'
                );
                if (!hostAssociationRecords.isEmpty()) {
                    SObject hostAssociation = hostAssociationRecords[0];
                    hostAssociationMaps.add(toMap(hostAssociation));
                    Id hostAccountId = (Id) hostAssociation.get('Host__c');
                    if (hostAccountId != null) {
                        String accountFields = getQueryableFieldList('Account');
                        if (!String.isBlank(accountFields)) {
                            List<SObject> accounts = Database.query(
                                'SELECT ' + accountFields + ' FROM Account WHERE Id = :hostAccountId LIMIT 1'
                            );
                            if (!accounts.isEmpty()) {
                                hostAccountMap = toMap(accounts[0]);
                            }
                        }
                    }
                }
            }
        }
        result.put('hostAssociations', hostAssociationMaps);
        result.put('hostAccount', hostAccountMap);

        List<String> childObjectNames = new List<String>{
            'Education_Details__c',
            'Employment_Details__c',
            'Patents__c',
            'Publications__c',
            'Achievements__c',
            'User_Documents__c',
            'Other_Grants__c',
            'Existing_Grants__c',
            'Scheme_Section__c',
            'Equipment__c',
            'Miscellaneous__c',
            'WOHI_Allowance__c'
        };

        for (String childObject : childObjectNames) {
            String lookupField = getLookupFieldName(childObject, 'Applicant_Proposal_Association__c');
            List<Map<String, Object>> childRecords = new List<Map<String, Object>>();
            if (!String.isBlank(lookupField) && !applicantIds.isEmpty()) {
                String childFields = getQueryableFieldList(childObject);
                if (!String.isBlank(childFields)) {
                    for (SObject child : Database.query('SELECT ' + childFields + ' FROM ' + childObject + ' WHERE ' + lookupField + ' IN :applicantIds')) {
                        Map<String, Object> childMap = toMap(child);
                        // User_Documents__c also has a Human__c lookup (used to link a
                        // document, e.g. the hospital-facility letter, to a specific
                        // Human__c record) - toMap() resolves it to the parent's Name
                        // since Human__c has one, so restore the raw Id here for joins.
                        if (childObject == 'User_Documents__c') {
                            childMap.put('Human__c', child.get('Human__c'));
                        }
                        childRecords.add(childMap);
                    }
                }
            }
            result.put(getResultKey(childObject), childRecords);
        }

        // Staff_Budget__c looks up to Applicant_Proposal_Association__c (same as the
        // generic childObjectNames block above), but it's shared across several
        // Budget tabs (Staff / Materials_and_Consumables / Access_Charges) via
        // RecordType - and RecordTypeId is in EXCLUDED_FIELDS (skipped everywhere
        // else to reduce noise), so it needs its own block that explicitly selects
        // RecordType.DeveloperName to tell the record types apart.
        List<Map<String, Object>> staffBudgetMaps = new List<Map<String, Object>>();
        String staffBudgetLookupField = getLookupFieldName('Staff_Budget__c', 'Applicant_Proposal_Association__c');
        if (!String.isBlank(staffBudgetLookupField) && !applicantIds.isEmpty()) {
            String staffBudgetFields = getQueryableFieldList('Staff_Budget__c');
            if (!String.isBlank(staffBudgetFields)) {
                for (SObject staffBudget : Database.query(
                    'SELECT ' + staffBudgetFields + ', RecordType.DeveloperName FROM Staff_Budget__c WHERE ' +
                    staffBudgetLookupField + ' IN :applicantIds'
                )) {
                    Map<String, Object> staffBudgetMap = toMap(staffBudget);
                    SObject recordType = staffBudget.getSObject('RecordType');
                    staffBudgetMap.put('RecordTypeDeveloperName', recordType != null ? recordType.get('DeveloperName') : null);
                    staffBudgetMaps.add(staffBudgetMap);
                }
            }
        }
        result.put('staffBudgets', staffBudgetMaps);

        // Project_Milestone__c looks up directly to Proposal__c (not to the APA like the
        // childObjectNames block above), so it needs its own query keyed on proposalId.
        List<Map<String, Object>> milestoneMaps = new List<Map<String, Object>>();
        String milestoneFields = getQueryableFieldList('Project_Milestone__c');
        if (!String.isBlank(milestoneFields)) {
            for (SObject milestone : Database.query(
                'SELECT ' + milestoneFields + ' FROM Project_Milestone__c WHERE Proposal__c = :proposalId ORDER BY Start_Date__c ASC NULLS LAST'
            )) {
                milestoneMaps.add(toMap(milestone));
            }
        }
        result.put('projectMilestones', milestoneMaps);

        // Animals__c also looks up directly to Proposal__c - one record per proposal
        // covering the "Research Involving Experiment on Animals" section. Its own
        // child, Animal_Species__c, looks up to the Animals__c record (not the
        // Proposal), so it's only queryable once we have that record's Id.
        Map<String, Object> animalsMap = new Map<String, Object>();
        List<Map<String, Object>> animalSpeciesMaps = new List<Map<String, Object>>();
        List<Map<String, Object>> animalAssociatedCostMaps = new List<Map<String, Object>>();
        String animalsFields = getQueryableFieldList('Animals__c');
        if (!String.isBlank(animalsFields)) {
            List<SObject> animalsRecords = Database.query(
                'SELECT ' + animalsFields + ' FROM Animals__c WHERE Proposal__c = :proposalId LIMIT 1'
            );
            if (!animalsRecords.isEmpty()) {
                animalsMap = toMap(animalsRecords[0]);
                Id animalsId = animalsRecords[0].Id;
                String animalSpeciesFields = getQueryableFieldList('Animal_Species__c');
                if (!String.isBlank(animalSpeciesFields)) {
                    for (SObject species : Database.query(
                        'SELECT ' + animalSpeciesFields + ' FROM Animal_Species__c WHERE Animals__c = :animalsId ORDER BY CreatedDate ASC'
                    )) {
                        animalSpeciesMaps.add(toMap(species));
                    }
                }

                // Animal_Associated_costs__c is another child of Animals__c (not of
                // Animal_Species__c), covering the "Associated Costs" Budget sub-tab.
                String animalAssociatedCostFields = getQueryableFieldList('Animal_Associated_costs__c');
                if (!String.isBlank(animalAssociatedCostFields)) {
                    for (SObject associatedCost : Database.query(
                        'SELECT ' + animalAssociatedCostFields + ' FROM Animal_Associated_costs__c WHERE Animals__c = :animalsId ORDER BY CreatedDate ASC'
                    )) {
                        animalAssociatedCostMaps.add(toMap(associatedCost));
                    }
                }
            }
        }
        result.put('animals', animalsMap);
        result.put('animalSpecies', animalSpeciesMaps);
        result.put('animalAssociatedCosts', animalAssociatedCostMaps);

        // Human__c also looks up directly to Proposal__c - one record per proposal,
        // same shape as Animals__c, covering the "Research Involving Human
        // Participants" section.
        Map<String, Object> humanMap = new Map<String, Object>();
        String humanFields = getQueryableFieldList('Human__c');
        if (!String.isBlank(humanFields)) {
            List<SObject> humanRecords = Database.query(
                'SELECT ' + humanFields + ' FROM Human__c WHERE Proposal__c = :proposalId LIMIT 1'
            );
            if (!humanRecords.isEmpty()) {
                humanMap = toMap(humanRecords[0]);
            }
        }
        result.put('human', humanMap);

        // WOHI_Collaboration__c looks up to Applicant_Proposal_Association__c (same
        // as the generic childObjectNames block above), but it needs its own block
        // here because its child, WOHI_Collaborator_Visit__c, looks up to the
        // WOHI_Collaboration__c record itself (not to the APA) - so the child query
        // needs the parent Ids first. Type__c on WOHI_Collaboration__c ('WOHI' vs
        // 'Collaborator') tells the WOHI section and the Collaboration section
        // apart; the LWC splits this one list by Type__c.
        List<Map<String, Object>> wohiCollaborationMaps = new List<Map<String, Object>>();
        List<Map<String, Object>> wohiCollaboratorVisitMaps = new List<Map<String, Object>>();
        String wohiLookupField = getLookupFieldName('WOHI_Collaboration__c', 'Applicant_Proposal_Association__c');
        if (!String.isBlank(wohiLookupField) && !applicantIds.isEmpty()) {
            String wohiFields = getQueryableFieldList('WOHI_Collaboration__c');
            if (!String.isBlank(wohiFields)) {
                List<SObject> wohiRecords = Database.query(
                    'SELECT ' + wohiFields + ' FROM WOHI_Collaboration__c WHERE ' + wohiLookupField + ' IN :applicantIds'
                );
                Set<Id> wohiCollaborationIds = new Set<Id>();
                for (SObject wohiRecord : wohiRecords) {
                    wohiCollaborationMaps.add(toMap(wohiRecord));
                    wohiCollaborationIds.add(wohiRecord.Id);
                }
                if (!wohiCollaborationIds.isEmpty()) {
                    String wohiVisitFields = getQueryableFieldList('WOHI_Collaborator_Visit__c');
                    if (!String.isBlank(wohiVisitFields)) {
                        for (SObject visit : Database.query(
                            'SELECT ' + wohiVisitFields + ' FROM WOHI_Collaborator_Visit__c WHERE ' +
                            'WOHI_Collaboration__c IN :wohiCollaborationIds ORDER BY CreatedDate ASC'
                        )) {
                            Map<String, Object> visitMap = toMap(visit);
                            // toMap() resolves Reference fields to the parent's Name (since
                            // WOHI_Collaboration__c has one), which overwrites the lookup
                            // value needed to join a visit back to its parent card in the
                            // LWC - restore the raw Id here so that join keeps working.
                            visitMap.put('WOHI_Collaboration__c', visit.get('WOHI_Collaboration__c'));
                            wohiCollaboratorVisitMaps.add(visitMap);
                        }
                    }
                }
            }
        }
        result.put('wohiCollaborations', wohiCollaborationMaps);
        result.put('wohiCollaboratorVisits', wohiCollaboratorVisitMaps);

        // Suggested_Reviewer__c also looks up directly to Proposal__c - covers both
        // the Potential Reviewers table (Type__c = 'Suggest') and the Restricted
        // Reviewer table (Type__c = 'Restrict') on the Letters and Declaration
        // section; the LWC splits the one list by Type__c.
        List<Map<String, Object>> suggestedReviewerMaps = new List<Map<String, Object>>();
        String suggestedReviewerFields = getQueryableFieldList('Suggested_Reviewer__c');
        if (!String.isBlank(suggestedReviewerFields)) {
            for (SObject suggestedReviewer : Database.query(
                'SELECT ' + suggestedReviewerFields + ' FROM Suggested_Reviewer__c WHERE Proposal__c = :proposalId ORDER BY SL_No__c ASC NULLS LAST'
            )) {
                suggestedReviewerMaps.add(toMap(suggestedReviewer));
            }
        }
        result.put('suggestedReviewers', suggestedReviewerMaps);

        Map<String, Object> fieldLabels = new Map<String, Object>();
        fieldLabels.put('Proposal__c', getFieldLabels('Proposal__c'));
        fieldLabels.put('Applicant_Proposal_Association__c', getFieldLabels('Applicant_Proposal_Association__c'));
        fieldLabels.put('Contact', getFieldLabels('Contact'));
        fieldLabels.put('Proposal_Participant_Association__c', getFieldLabels('Proposal_Participant_Association__c'));
        fieldLabels.put('Additional_Partcipant__c', getFieldLabels('Additional_Partcipant__c'));
        fieldLabels.put('Applicant_Host_Association__c', getFieldLabels('Applicant_Host_Association__c'));
        fieldLabels.put('Account', getFieldLabels('Account'));
        fieldLabels.put('Project_Milestone__c', getFieldLabels('Project_Milestone__c'));
        fieldLabels.put('Animals__c', getFieldLabels('Animals__c'));
        fieldLabels.put('Animal_Species__c', getFieldLabels('Animal_Species__c'));
        for (String childObject : childObjectNames) {
            fieldLabels.put(childObject, getFieldLabels(childObject));
        }
        result.put('fieldLabels', fieldLabels);

        return result;
    }

    private static Map<String, String> getFieldLabels(String objectApiName) {
        Map<String, String> labels = new Map<String, String>();
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return labels;
        }
        for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.isAccessible() && !fieldDescribe.isDeprecatedAndHidden()) {
                labels.put(fieldDescribe.getName(), fieldDescribe.getLabel());
            }
        }
        return labels;
    }

    private static String getQueryableFieldList(String objectApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return null;
        }
        List<String> fields = new List<String>();
        for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.isAccessible()
                && !fieldDescribe.isDeprecatedAndHidden()
                && !EXCLUDED_FIELDS.contains(fieldDescribe.getName())
                && fieldDescribe.getType() != Schema.DisplayType.Address
                && fieldDescribe.getType() != Schema.DisplayType.Location) {
                String fieldName = fieldDescribe.getName();
                fields.add(fieldName);
                if (fieldDescribe.getType() == Schema.DisplayType.Reference) {
                    String relFieldName = getRelationshipFieldName(fieldName);
                    if (!String.isBlank(relFieldName) && referenceHasNameField(fieldDescribe)) {
                        fields.add(relFieldName + '.Name');
                    }
                }
            }
        }
        return String.join(fields, ',');
    }

    // Not every lookup/master-detail target has a Name field (e.g. Case uses CaseNumber),
    // so only add the '<relationship>.Name' traversal when every possible target object
    // (polymorphic lookups can have more than one) actually has one.
    private static Boolean referenceHasNameField(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.SObjectType refType : fieldDescribe.getReferenceTo()) {
            if (!refType.getDescribe().fields.getMap().containsKey('Name')) {
                return false;
            }
        }
        return true;
    }

    private static Map<String, Object> toMap(SObject record) {
        Map<String, Object> result = new Map<String, Object>();
        if (record == null) {
            return result;
        }
        for (Schema.SObjectField field : record.getSObjectType().getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!fieldDescribe.isAccessible()
                || fieldDescribe.isDeprecatedAndHidden()
                || fieldDescribe.getType() == Schema.DisplayType.Address
                || fieldDescribe.getType() == Schema.DisplayType.Location) {
                continue;
            }
            String fieldName = fieldDescribe.getName();
            if (EXCLUDED_FIELDS.contains(fieldName)) {
                continue;
            }
            Object value;
            if (fieldDescribe.getType() == Schema.DisplayType.Reference) {
                String relFieldName = getRelationshipFieldName(fieldName);
                // Mirrors getQueryableFieldList's referenceHasNameField check - the
                // relationship was only ever queried (as '<relationship>.Name') when the
                // target object actually has a Name field, so only attempt to read it back
                // here under the same condition. Otherwise record.getSObject() throws
                // "SObject row was retrieved via SOQL without querying the requested field".
                SObject parent = (!String.isBlank(relFieldName) && referenceHasNameField(fieldDescribe))
                    ? record.getSObject(relFieldName)
                    : null;
                value = parent != null ? parent.get('Name') : null;
            } else {
                value = record.get(fieldName);
                if (value instanceof Date) {
                    value = ((Date) value).format();
                } else if (value instanceof Datetime) {
                    value = ((Datetime) value).format();
                }
            }
            result.put(fieldName, value);
        }
        return result;
    }

    private static String getRelationshipFieldName(String fieldName) {
        if (String.isBlank(fieldName)) {
            return null;
        }
        if (fieldName.endsWith('__c')) {
            return fieldName.substring(0, fieldName.length() - 3) + '__r';
        }
        if (fieldName.endsWith('Id')) {
            return fieldName.substring(0, fieldName.length() - 2);
        }
        return fieldName;
    }

    private static String getLookupFieldName(String childObjectName, String parentObjectName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(childObjectName);
        if (objectType == null) {
            return null;
        }
        for (Schema.SObjectField field : objectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.getType() == Schema.DisplayType.Reference) {
                for (Schema.SObjectType refTo : fieldDescribe.getReferenceTo()) {
                    if (String.valueOf(refTo) == parentObjectName) {
                        return fieldDescribe.getName();
                    }
                }
            }
        }
        return null;
    }

    private static String getResultKey(String objectApiName) {
        Map<String, String> resultKeyByObject = new Map<String, String>{
            'Education_Details__c' => 'educationDetails',
            'Employment_Details__c' => 'employmentDetails',
            'Patents__c' => 'patents',
            'Publications__c' => 'publications',
            'Achievements__c' => 'achievements',
            'User_Documents__c' => 'userDocuments',
            'Other_Grants__c' => 'otherGrants',
            'Existing_Grants__c' => 'existingGrants',
            'Scheme_Section__c' => 'schemeSections',
            'Equipment__c' => 'equipmentItems',
            'Miscellaneous__c' => 'miscellaneousItems',
            'WOHI_Allowance__c' => 'wohiAllowances'
        };
        String key = resultKeyByObject.get(objectApiName);
        if (String.isBlank(key)) {
            key = objectApiName.replaceAll('__c', '').replaceAll('_', '');
        }
        return key;
    }
}