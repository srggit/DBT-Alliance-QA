public without sharing class AssignCommitteeController {

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value){
            this.label = label;
            this.value = value;
        }
    }

    public class CommitteeMasterRow {
        @AuraEnabled public Id masterId;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String organisationName;
        @AuraEnabled public Boolean alreadyAdded;
        @AuraEnabled public String addedMessage;
        @AuraEnabled public Boolean selected;
        @AuraEnabled public String typePicklist;
        @AuraEnabled public Boolean isCommitteeReview;
    }

    // Default screen data: every active Committee Master, flagged if already
    // cloned into a Committee_Member__c for this Yearly Scheme (locked + shows saved values).
    @AuraEnabled
    public static List<CommitteeMasterRow> getCommitteeMasters(Id recordId){
        System.debug('getCommitteeMasters recordId: ' + recordId);
        Map<Id, Committee_Member__c> existingByMaster = new Map<Id, Committee_Member__c>();
        for(Committee_Member__c cm : [
            SELECT Id, Committee_Master__c, Type__c, Is_Committee_Review__c, CreatedDate, CreatedBy.Name
            FROM Committee_Member__c
            WHERE Yearly_Schemes__c = :recordId
            AND Committee_Master__c != null
        ]){
            existingByMaster.put(cm.Committee_Master__c, cm);
        }

        System.debug('getCommitteeMasters existingByMaster count: ' + existingByMaster.size());
        List<CommitteeMasterRow> rows = new List<CommitteeMasterRow>();
        for(Committee_Master__c m : [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Mobile_Number__c, Organisation_Name__c
            FROM Committee_Master__c
            WHERE Active__c = true
            ORDER BY First_Name__c ASC NULLS LAST, Last_Name__c ASC NULLS LAST
        ]){
            CommitteeMasterRow row = new CommitteeMasterRow();
            row.masterId = m.Id;
            row.fullName = trimName(m.First_Name__c, m.Last_Name__c);
            row.email = m.Email__c;
            row.phone = m.Mobile_Number__c;
            row.organisationName = m.Organisation_Name__c;
            row.selected = false;

            Committee_Member__c existing = existingByMaster.get(m.Id);
            if(existing != null){
                row.alreadyAdded = true;
                row.addedMessage = 'Already added by '
                    + (existing.CreatedBy != null ? existing.CreatedBy.Name : 'someone')
                    + ' on ' + existing.CreatedDate.format('dd/MM/yyyy');
                row.typePicklist = existing.Type__c;
                row.isCommitteeReview = existing.Is_Committee_Review__c == null ? false : existing.Is_Committee_Review__c;
            } else {
                row.alreadyAdded = false;
                row.addedMessage = '';
                row.typePicklist = '';
                row.isCommitteeReview = false;
            }
            rows.add(row);
        }
        System.debug('getCommitteeMasters rows returned: ' + rows.size());
        return rows;
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

    // Clones the selected Committee_Master__c records into Committee_Member__c,
    // stamping the Type__c / Is_Committee_Review__c chosen inline on the screen.
    @AuraEnabled
    public static Integer cloneSelectedMasters(Id recordId, List<CommitteeMasterRow> selectedRows){
        Savepoint sp = Database.setSavepoint();
        try{
            if(selectedRows == null || selectedRows.isEmpty()){
                throw new AuraHandledException('No committee master records were selected.');
            }

            System.debug('cloneSelectedMasters recordId: ' + recordId);
            System.debug('cloneSelectedMasters selectedRows size: ' + selectedRows.size());
            System.debug('cloneSelectedMasters selectedRows JSON: ' + JSON.serialize(selectedRows));

            Set<Id> masterIds = new Set<Id>();
            for(CommitteeMasterRow r : selectedRows){
                if(r.masterId == null){
                    throw new AuraHandledException('A selected row is missing its Committee Master Id — please refresh and try again.');
                }
                masterIds.add(r.masterId);
            }
            System.debug('cloneSelectedMasters masterIds: ' + masterIds);

            Map<Id, Committee_Master__c> masters = new Map<Id, Committee_Master__c>([
                SELECT Id, First_Name__c, Last_Name__c, Email__c, Mobile_Number__c,
                       Alternative_Mobile_Number__c, Organisation_Name__c, Designation__c,
                       Department__c, Title__c, City__c, State__c, Country__c
                FROM Committee_Master__c
                WHERE Id IN :masterIds
            ]);

            System.debug('cloneSelectedMasters masters found: ' + masters.size());
            if(masters.isEmpty()){
                throw new AuraHandledException('None of the selected Committee Master Ids matched existing records: ' + masterIds);
            }

            List<Committee_Member__c> toInsert = new List<Committee_Member__c>();
            for(CommitteeMasterRow r : selectedRows){
                Committee_Master__c m = masters.get(r.masterId);
                if(m == null){ continue; }

                Committee_Member__c cm = new Committee_Member__c();
                cm.Committee_Master__c            = m.Id;
                cm.Yearly_Schemes__c               = recordId;
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
                cm.Type__c                            = r.typePicklist;
                cm.Is_Committee_Review__c             = r.isCommitteeReview == null ? false : r.isCommitteeReview;
                toInsert.add(cm);
            }
            System.debug('cloneSelectedMasters toInsert size: ' + toInsert.size());

            if(toInsert.isEmpty()){
                throw new AuraHandledException('No valid Committee Member records could be built from the selection.');
            }

            insert toInsert;
            System.debug('cloneSelectedMasters inserted count: ' + toInsert.size());
            return toInsert.size();
        } catch(Exception e){
            System.debug('cloneSelectedMasters error: ' + e.getMessage());
            System.debug(e.getStackTraceString());
            Database.rollback(sp);
            // throw new AuraHandledException('Error cloning committee members: ' + e.getMessage());

            AuraHandledException ahe = new AuraHandledException('Error cloning committee members: ' + e.getMessage());
            ahe.setMessage('Error cloning committee members: ' + e.getMessage());
            throw ahe;
        }
    }

    private static String trimName(String f, String l){
        String result = '';
        if(f != null){ result += f; }
        if(l != null){ result += (result == '' ? '' : ' ') + l; }
        return result;
    }
}