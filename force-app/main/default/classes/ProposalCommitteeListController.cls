public with sharing class ProposalCommitteeListController {

    @AuraEnabled(cacheable=true)
    public static List<CommitteeRowWrapper> getProposalCommitteeRecords(Id proposalId) {
        List<CommitteeRowWrapper> results = new List<CommitteeRowWrapper>();
        if (proposalId == null) {
            return results;
        }

        for (Proposal_Committee__c pc : [
            SELECT Id, Commitee_Member_Name__c, Type__c, Status__c, Committee_Reviewer__c,
                   Reviewer_Response__c, Conflict_Status__c, Overall_Score__c
            FROM Proposal_Committee__c
            WHERE Proposal__c = :proposalId
            ORDER BY Type__c ASC, Commitee_Member_Name__c ASC
        ]) {
            results.add(new CommitteeRowWrapper(pc));
        }

        return results;
    }

    @AuraEnabled
    public static void updateCommitteeRows(String updatesJson) {
        List<CommitteeRowUpdate> updates;
        try {
            updates = String.isBlank(updatesJson)
                ? new List<CommitteeRowUpdate>()
                : (List<CommitteeRowUpdate>) JSON.deserialize(updatesJson, List<CommitteeRowUpdate>.class);
        } catch (JSONException e) {
            throw new AuraHandledException('Invalid changes: ' + e.getMessage());
        }
        if (updates.isEmpty()) {
            throw new AuraHandledException('No changes to save.');
        }
        List<Proposal_Committee__c> recordsToUpdate = new List<Proposal_Committee__c>();
        for (CommitteeRowUpdate u : updates) {
            recordsToUpdate.add(new Proposal_Committee__c(
                Id = u.id,
                Type__c = u.type,
                Committee_Reviewer__c = u.committeeReviewer == true
            ));
        }
        try {
            update recordsToUpdate;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to save changes: ' + e.getDmlMessage(0));
        }
    }

    // Every Committee_Master__c (active or not), flagged when the master is already on this
    // proposal's committee - the master is matched through Committee_Member__c.Committee_Master__c.
    // Not cacheable: the "already added" flag changes as soon as members are added.
    @AuraEnabled
    public static List<CommitteeMasterWrapper> getCommitteeMasters(Id proposalId) {
        Set<Id> addedMasterIds = new Set<Id>();
        if (proposalId != null) {
            for (Proposal_Committee__c pc : [
                SELECT Committee_Member__r.Committee_Master__c
                FROM Proposal_Committee__c
                WHERE Proposal__c = :proposalId AND Committee_Member__r.Committee_Master__c != null
            ]) {
                addedMasterIds.add(pc.Committee_Member__r.Committee_Master__c);
            }
        }

        List<CommitteeMasterWrapper> results = new List<CommitteeMasterWrapper>();
        for (Committee_Master__c master : [
            SELECT Id, Title__c, First_Name__c, Last_Name__c, Email__c, Organisation_Name__c
            FROM Committee_Master__c
            ORDER BY First_Name__c ASC NULLS LAST, Last_Name__c ASC NULLS LAST
        ]) {
            results.add(new CommitteeMasterWrapper(master, addedMasterIds.contains(master.Id)));
        }
        return results;
    }

    // Adds the selected masters to this proposal's committee. Proposal_Committee__c can only
    // look up to Committee_Member__c, so each master is resolved to a Committee_Member__c
    // first: the proposal's Yearly Scheme's own member for that master if there is one,
    // otherwise a new Committee_Member__c copied from the master. New members are created
    // WITHOUT a Yearly Scheme on purpose - a scheme-less member never joins the scheme's
    // committee ring (cloneCommitteeMember / round robin both query by Yearly_Schemes__c),
    // so adding someone to one proposal doesn't silently add them to every future proposal.
    @AuraEnabled
    public static void addCommitteeMasters(Id proposalId, String selectionsJson) {
        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }
        // Passed as a JSON string rather than List<MasterSelection>: Aura wasn't binding the
        // inner-class list's fields (masterId/type arrived blank).
        List<MasterSelection> selections;
        try {
            selections = String.isBlank(selectionsJson)
                ? new List<MasterSelection>()
                : (List<MasterSelection>) JSON.deserialize(selectionsJson, List<MasterSelection>.class);
        } catch (JSONException e) {
            throw new AuraHandledException('Invalid selection: ' + e.getMessage());
        }
        if (selections == null || selections.isEmpty()) {
            throw new AuraHandledException('Select at least one Committee Master.');
        }

        Proposal__c proposal = [
            SELECT Id, Yearly_Scheme__c, Application_Stages__c, Proposal_Status__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        Map<Id, String> typeByMasterId = new Map<Id, String>();
        Map<Id, Boolean> reviewerByMasterId = new Map<Id, Boolean>();
        for (MasterSelection sel : selections) {
            if (sel.masterId == null || String.isBlank(sel.type)) {
                throw new AuraHandledException('Select a Type for every selected Committee Master.');
            }
            typeByMasterId.put(sel.masterId, sel.type);
            reviewerByMasterId.put(sel.masterId, sel.committeeReviewer == true);
        }

        // Masters already on this proposal are skipped (no duplicates).
        for (Proposal_Committee__c pc : [
            SELECT Committee_Member__r.Committee_Master__c
            FROM Proposal_Committee__c
            WHERE Proposal__c = :proposalId
            AND Committee_Member__r.Committee_Master__c IN :typeByMasterId.keySet()
        ]) {
            typeByMasterId.remove(pc.Committee_Member__r.Committee_Master__c);
        }
        if (typeByMasterId.isEmpty()) {
            throw new AuraHandledException('The selected Committee Masters are already on this proposal.');
        }

        Map<Id, Id> memberIdByMasterId = new Map<Id, Id>();
        if (proposal.Yearly_Scheme__c != null) {
            for (Committee_Member__c member : [
                SELECT Id, Committee_Master__c
                FROM Committee_Member__c
                WHERE Yearly_Schemes__c = :proposal.Yearly_Scheme__c
                AND Committee_Master__c IN :typeByMasterId.keySet()
            ]) {
                memberIdByMasterId.put(member.Committee_Master__c, member.Id);
            }
        }

        List<Committee_Member__c> newMembers = new List<Committee_Member__c>();
        List<Id> newMemberMasterIds = new List<Id>();
        for (Committee_Master__c master : [
            SELECT Id, Title__c, First_Name__c, Last_Name__c, Email__c, Mobile_Number__c,
                   Alternative_Mobile_Number__c, Organisation_Name__c, Department__c,
                   Designation__c, City__c, State__c, Country__c
            FROM Committee_Master__c
            WHERE Id IN :typeByMasterId.keySet()
        ]) {
            if (memberIdByMasterId.containsKey(master.Id)) {
                continue;
            }
            newMembers.add(new Committee_Member__c(
                Committee_Master__c = master.Id,
                Title__c = master.Title__c,
                First_Name__c = master.First_Name__c,
                Last_Name__c = master.Last_Name__c,
                Email__c = master.Email__c,
                Mobile_Number__c = master.Mobile_Number__c,
                Alternative_Mobile_Number__c = master.Alternative_Mobile_Number__c,
                Organisation_Name__c = master.Organisation_Name__c,
                Department__c = master.Department__c,
                Designation__c = master.Designation__c,
                City__c = master.City__c,
                State__c = master.State__c,
                Country__c = master.Country__c,
                Type__c = typeByMasterId.get(master.Id)
            ));
            newMemberMasterIds.add(master.Id);
        }

        try {
            if (!newMembers.isEmpty()) {
                insert newMembers;
                for (Integer i = 0; i < newMembers.size(); i++) {
                    memberIdByMasterId.put(newMemberMasterIds[i], newMembers[i].Id);
                }
            }

            List<Proposal_Committee__c> newRecords = new List<Proposal_Committee__c>();
            for (Id masterId : typeByMasterId.keySet()) {
                Id memberId = memberIdByMasterId.get(masterId);
                if (memberId == null) {
                    continue;
                }
                newRecords.add(new Proposal_Committee__c(
                    Proposal__c = proposalId,
                    Committee_Member__c = memberId,
                    Status__c = 'Assigned',
                    Type__c = typeByMasterId.get(masterId),
                    Committee_Reviewer__c = reviewerByMasterId.get(masterId),
                    Application_Stages__c = proposal.Application_Stages__c
                ));
            }
            insert newRecords;

            // The assignment email normally goes out once, when the Proposal moves to Committee
            // Review (ReviewerController.sendCommitteeAssignmentEmails) - members added afterwards
            // would never get it, so send it to just them. Skipped while the proposal is still
            // before the committee stage (they'll get it with everyone else at Committee Review).
            if (ReviewerController.COMMITTEE_STAGE_STATUSES.contains(proposal.Proposal_Status__c)) {
                Set<Id> newRecordIds = new Set<Id>();
                for (Proposal_Committee__c pc : newRecords) {
                    newRecordIds.add(pc.Id);
                }
                ReviewerController.sendCommitteeEmails(new Set<Id>{ proposalId }, newRecordIds);
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to add committee members: ' + e.getDmlMessage(0));
        }
    }

    public class MasterSelection {
        public Id masterId;
        public String type;
        public Boolean committeeReviewer;
    }

    public class CommitteeMasterWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String organization;
        @AuraEnabled public Boolean alreadyAdded;

        public CommitteeMasterWrapper(Committee_Master__c master, Boolean alreadyAdded) {
            this.id = master.Id;
            List<String> parts = new List<String>();
            for (String part : new List<String>{ master.Title__c, master.First_Name__c, master.Last_Name__c }) {
                if (String.isNotBlank(part)) {
                    parts.add(part.trim());
                }
            }
            this.name = String.join(parts, ' ');
            this.email = master.Email__c;
            this.organization = master.Organisation_Name__c;
            this.alreadyAdded = alreadyAdded;
        }
    }

    // Full row state (type + reviewer flag) for each edited row, sent as JSON.
    public class CommitteeRowUpdate {
        public Id id;
        public String type;
        public Boolean committeeReviewer;
    }

    public class CommitteeRowWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String memberName;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean committeeReviewer;
        @AuraEnabled public String reviewerResponse;
        @AuraEnabled public String conflictStatus;
        @AuraEnabled public Decimal overallScore;

        public CommitteeRowWrapper(Proposal_Committee__c pc) {
            this.id = pc.Id;
            this.memberName = pc.Commitee_Member_Name__c;
            this.type = pc.Type__c;
            this.status = pc.Status__c;
            this.committeeReviewer = pc.Committee_Reviewer__c;
            this.reviewerResponse = pc.Reviewer_Response__c;
            this.conflictStatus = pc.Conflict_Status__c;
            this.overallScore = pc.Overall_Score__c;
        }
    }
}