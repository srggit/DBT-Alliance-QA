public without sharing class CommitteeMemberController {

    public class MasterRow {
        @AuraEnabled public Id masterId;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String organisationName;
        @AuraEnabled public Boolean alreadyAdded;
        @AuraEnabled public String addedMessage;
        @AuraEnabled public Integer existingSequence;
        @AuraEnabled public String existingType;
    }

    public class CommitteeMemberInput {
        @AuraEnabled public Id masterId;
        @AuraEnabled public String typeValue;
        @AuraEnabled public Boolean isReview;
        @AuraEnabled public Integer sequence;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value){
            this.label = label;
            this.value = value;
        }
    }

    // recordId here is the Yearly Scheme Id — flags rows already cloned into a
    // Committee_Member__c for THIS scheme so they can't be selected (and duplicated) again.
    @AuraEnabled(cacheable=true)
    public static List<MasterRow> getActiveCommitteeMasters(Id yearlySchemeId){
        Map<Id, Committee_Member__c> existingByMaster = new Map<Id, Committee_Member__c>();
        if(yearlySchemeId != null){
            for(Committee_Member__c cm : [
                SELECT Id, Committee_Master__c, Sequence__c, Type__c, CreatedDate, CreatedBy.Name
                FROM Committee_Member__c
                WHERE Yearly_Schemes__c = :yearlySchemeId
                AND Committee_Master__c != null
            ]){
                existingByMaster.put(cm.Committee_Master__c, cm);
            }
        }

        List<MasterRow> rows = new List<MasterRow>();
        for(Committee_Master__c m : [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Mobile_Number__c, Organisation_Name__c
            FROM Committee_Master__c
            WHERE Active__c = true
            ORDER BY First_Name__c ASC NULLS LAST, Last_Name__c ASC NULLS LAST
        ]){
            MasterRow row = new MasterRow();
            row.masterId = m.Id;
            row.fullName = trimName(m.First_Name__c, m.Last_Name__c);
            row.email = m.Email__c;
            row.phone = m.Mobile_Number__c;
            row.organisationName = m.Organisation_Name__c;

            Committee_Member__c existing = existingByMaster.get(m.Id);
            if(existing != null){
                row.alreadyAdded = true;
                row.addedMessage = 'Already added by '
                    + (existing.CreatedBy != null ? existing.CreatedBy.Name : 'someone')
                    + ' on ' + existing.CreatedDate.format('dd/MM/yyyy');
                row.existingSequence = existing.Sequence__c == null ? null : Integer.valueOf(existing.Sequence__c);
                row.existingType = existing.Type__c;
            } else {
                row.alreadyAdded = false;
                row.addedMessage = '';
            }
            rows.add(row);
        }
        return rows;
    }

    // Highest Sequence__c already saved for this Yearly Scheme's committee ring.
    // New selections continue numbering from here (append-only — never renumber existing members).
    // cacheable=true so this can be a reactive @wire on recordId, same as getActiveCommitteeMasters -
    // an imperative call in connectedCallback() ran before recordId was populated on quick-action screens.
    @AuraEnabled(cacheable=true)
    public static Integer getMaxSequence(Id yearlySchemeId){
        Integer maxSeq = 0;
        for(AggregateResult ar : [
            SELECT MAX(Sequence__c) maxSeq
            FROM Committee_Member__c
            WHERE Yearly_Schemes__c = :yearlySchemeId
        ]){
            Object val = ar.get('maxSeq');
            if(val != null){
                maxSeq = Integer.valueOf(val);
            }
        }
        return maxSeq;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getTypePicklistValues(){
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.DescribeFieldResult fieldResult = Committee_Member__c.Type__c.getDescribe();
        for(Schema.PicklistEntry entry : fieldResult.getPicklistValues()){
            if(entry.isActive()){
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    @AuraEnabled
    public static Integer createCommitteeMembers(Id yearlySchemeId, String selectedRowsJson){
        if (yearlySchemeId == null) {
            throw new AuraHandledException('Yearly Scheme record Id is required.');
        }
        if (String.isBlank(selectedRowsJson)) {
            throw new AuraHandledException('Select at least one Committee Master.');
        }

        List<CommitteeMemberInput> selectedRows = new List<CommitteeMemberInput>();
        for (Object o : (List<Object>) JSON.deserializeUntyped(selectedRowsJson)) {
            Map<String, Object> m = (Map<String, Object>) o;
            CommitteeMemberInput r = new CommitteeMemberInput();
            r.masterId   = (String) m.get('masterId');
            r.typeValue  = (String) m.get('typeValue');
            r.isReview   = m.get('isReview') == null ? false : (Boolean) m.get('isReview');
            r.sequence   = m.get('sequence') == null ? null : Integer.valueOf((Decimal) m.get('sequence'));
            selectedRows.add(r);
        }

        if (selectedRows.isEmpty()) {
            throw new AuraHandledException('Select at least one Committee Master.');
        }

        for (CommitteeMemberInput r : selectedRows) {
            if (r.masterId == null) {
                throw new AuraHandledException('A selected row is missing its Committee Master Id.');
            }
            if (String.isBlank(r.typeValue)) {
                throw new AuraHandledException('Select a Type for every selected committee member.');
            }
            if (r.sequence == null) {
                throw new AuraHandledException('A selected row is missing its Sequence number — please refresh and try again.');
            }
        }

        Set<Id> masterIds = new Set<Id>();
        for (CommitteeMemberInput r : selectedRows) {
            masterIds.add(r.masterId);
        }

        Set<Id> alreadyAddedMasterIds = new Set<Id>();
        for (Committee_Member__c existing : [
            SELECT Committee_Master__c
            FROM Committee_Member__c
            WHERE Yearly_Schemes__c = :yearlySchemeId
            AND Committee_Master__c IN :masterIds
        ]) {
            alreadyAddedMasterIds.add(existing.Committee_Master__c);
        }
        if (!alreadyAddedMasterIds.isEmpty()) {
            throw new AuraHandledException('One or more selected members are already added to this Yearly Scheme. Please refresh and try again.');
        }

        Map<Id, Committee_Master__c> masters = new Map<Id, Committee_Master__c>([
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Mobile_Number__c,
                   Alternative_Mobile_Number__c, Organisation_Name__c, Designation__c,
                   Department__c, Title__c, City__c, State__c, Country__c
            FROM Committee_Master__c
            WHERE Id IN :masterIds
              AND Active__c = true
        ]);

        List<Committee_Member__c> membersToInsert = new List<Committee_Member__c>();
        for (CommitteeMemberInput r : selectedRows) {
            Committee_Master__c m = masters.get(r.masterId);
            if (m == null) { continue; }

            Committee_Member__c cm = new Committee_Member__c();
            cm.Committee_Master__c            = m.Id;
            cm.Yearly_Schemes__c               = yearlySchemeId;
            cm.First_Name__c                   = m.First_Name__c;
            cm.Last_Name__c                     = m.Last_Name__c;
            cm.Email__c                          = m.Email__c;
            cm.Mobile_Number__c                  = m.Mobile_Number__c;
            cm.Alternative_Mobile_Number__c      = m.Alternative_Mobile_Number__c;
            cm.Organisation_Name__c              = m.Organisation_Name__c;
            cm.Designation__c                    = m.Designation__c;
            cm.Department__c                     = m.Department__c;
            cm.Title__c                           = m.Title__c;
            cm.City__c                            = m.City__c;
            cm.State__c                           = m.State__c;
            cm.Country__c                         = m.Country__c;
            cm.Type__c                            = r.typeValue;
            cm.Is_Committee_Review__c             = r.isReview == null ? false : r.isReview;
            cm.Sequence__c                        = r.sequence;
            membersToInsert.add(cm);
        }

        if (membersToInsert.isEmpty()) {
            throw new AuraHandledException('No valid Committee Member records could be built from the selection.');
        }

        try {
            insert membersToInsert;
            return membersToInsert.size();
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Committee Members: ' + e.getMessage());
        }
    }

    private static String trimName(String f, String l){
        String result = '';
        if(f != null){ result += f; }
        if(l != null){ result += (result == '' ? '' : ' ') + l; }
        return result;
    }
}