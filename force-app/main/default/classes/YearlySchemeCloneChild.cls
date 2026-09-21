public without sharing class YearlySchemeCloneChild {

    // Simple label/value wrapper — shape matches what lightning-combobox expects.
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled
    public static Yearly_Schemes__c getYearlySchemeDetails(Id recordId) {
        List<Yearly_Schemes__c> results = [ SELECT Id, Name, Is_Active__c, Year__c, Year__r.Name, Scheme_Start_Date__c, Second_Stage_Start_Date__c,Round__c,
                                            Scheme_Items__c, Scheme_Items__r.Name, Scheme_End_Date__c, Second_Stage_End_Date__c,
                                            Application_Stages__c, Budget_Cap__c, Experience_Required__c, Required_Degree__c, Team_Size_Limits__c,
                                            CurrencyIsoCode, Scheme_Visibility__c, OwnerId, Owner.Name FROM Yearly_Schemes__c WHERE Id = :recordId];
        if (results.isEmpty()) {
            throw new AuraHandledException('Yearly Scheme not found for Id: ' + recordId);
        }
        return results[0];
    }

    @AuraEnabled
    public static List<Scheme_Questionnaire__c> getQuestionnairesByItem(Id schemeItemId) {
        if (schemeItemId == null) {
            return new List<Scheme_Questionnaire__c>();
        }
        return [SELECT Id, Name, Display_Name__c, Is_Active__c,Max_Limit__c,Min_Limit__c,Stage__c,Type__c,Mandatory__c,SL_No__c,Section__c,Picklist_Values__c,Dynamic_Question__c FROM Scheme_Questionnaire__c WHERE Scheme_Items__c = :schemeItemId AND Dynamic_Question__c = :true ORDER BY Name];
    }

    @AuraEnabled
    public static List<sObject> getChildRecords(Id recordId, String objectApiName) {
        String query;
        if (objectApiName == 'Eligibility_Check_List__c') {
            query = 'SELECT Id, Name, Stage__c, CurrencyIsoCode,Display_Question__c,Type__c, CreatedDate ' +
                     'FROM Eligibility_Check_List__c ' +
                     'WHERE Yearly_Scheme__c = :recordId ORDER BY CreatedDate DESC';
        } else if (objectApiName == 'Eligibility_Criteria__c') {
            query = 'SELECT Id, Name, Validation_Type__c,Formula__c, Is_Active__c, Fail_Message__c, Pass_Message__c, Stage__c, Eligibility_Type__c, Yearly_Scheme__c ' +
                     'FROM Eligibility_Criteria__c ' +
                     'WHERE Yearly_Scheme__c = :recordId ORDER BY CreatedDate DESC';
        } else if (objectApiName == 'Scheme_Question_Items__c') {
            query = 'SELECT Id, Name, Stage__c, CurrencyIsoCode, Is_Active__c, Mandatory__c, Max_Character__c, CreatedDate, Min_Character__c, Question__c, Type__c,Attachments__c,SL_No__c,Section__c,Picklist_Values__c, ' +
                     'Scheme_Questionnaire__c, Scheme_Questionnaire__r.Name, Scheme_Questionnaire__r.Display_Name__c ' +
                     'FROM Scheme_Question_Items__c ' +
                     'WHERE Yearly_Scheme__c = :recordId ORDER BY CreatedDate DESC';
        } else if (objectApiName == 'Documents__c') {
            query = 'SELECT Id, Name, CreatedDate, Document_Master__c, Document_Name__c, Is_Active__c, Is_Required__c, Roles__c, Stage__c, Yearly_Scheme__c ' +
                    'FROM Documents__c ' +
                    'WHERE Yearly_Scheme__c = :recordId ORDER BY CreatedDate DESC';
        }else if (objectApiName == 'External_Participants__c') {
            query = 'SELECT Id, External_Participants__c, External_Participants_Count__c, CreatedDate, Name, External_Participants_Status__c, Maximum_Participants_Count__c, Stage__c, Yearly_Scheme__c ' +
                    'FROM External_Participants__c ' +
                    'WHERE Yearly_Scheme__c = :recordId ORDER BY CreatedDate DESC';
        }else if (objectApiName == 'Reviewer_Question_Template__c') {
            query = 'SELECT Id, Is_Visible_To_Peer_Reviewer__c, CreatedDate, Name, Question__c, Scheme_Questionnaire__c, Section__c, SL_No__c, Stage__c, Yearly_Schemes__c ' +
                    'FROM Reviewer_Question_Template__c ' +
                    'WHERE Yearly_Schemes__c = :recordId ORDER BY CreatedDate DESC';
        }else if (objectApiName == 'Yearly_Scheme_Instructions__c') {
            query = 'SELECT Id, CreatedDate, Instructions__c, Know_More__c, Name, Pages_Name__c, Stage__c, Type__c, Yearly_Scheme__c ' +
                    'FROM Yearly_Scheme_Instructions__c ' +
                    'WHERE Yearly_Scheme__c = :recordId ORDER BY CreatedDate DESC';
        }else if (objectApiName == 'Committee_Member__c') {
            query = 'SELECT Id, Alternative_Mobile_Number__c, Assignment_Count__c, City__c, Committee_Master__c, Community_Member_Password__c, Community_Member_UUID__c, Country__c, CreatedDate, Department__c, Designation__c, Email__c, First_Name__c, Is_Committee_Review__c, Last_Name__c, Mobile_Number__c, Name, Organisation_Name__c, Sequence__c, State__c, Title__c, Type__c, Yearly_Schemes__c ' +
                    'FROM Committee_Member__c ' +
                    'WHERE Yearly_Schemes__c = :recordId ORDER BY CreatedDate DESC';
        }else if (objectApiName == 'Grants_Team_Members__c') {
            query = 'SELECT Id, Application_Stages__c, CreatedDate, Grants_Team_Member_Id__c, Name, User__c, Yearly_Scheme__c ' +
                    'FROM Grants_Team_Members__c ' +
                    'WHERE Yearly_Scheme__c = :recordId ORDER BY CreatedDate DESC';
        }
        else {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }
        return Database.query(query);
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPicklistValues(String objectApiName, String fieldApiName) {
        List<PicklistOption> options = new List<PicklistOption>();

        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectApiName);
        if (targetType == null) {
            throw new AuraHandledException('Unknown object: ' + objectApiName);
        }

        Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe().fields.getMap();
        Schema.SObjectField targetField = fieldMap.get(fieldApiName);
        if (targetField == null) {
            throw new AuraHandledException('Unknown field: ' + fieldApiName + ' on ' + objectApiName);
        }

        for (Schema.PicklistEntry entry : targetField.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getCloneScreenPicklistOptions() {
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        result.put('publishStatus', getPicklistValues('Yearly_Schemes__c', 'Scheme_Visibility__c'));
        result.put('checkListStage', getPicklistValues('Eligibility_Check_List__c', 'Stage__c'));
        result.put('rulesStage', getPicklistValues('Eligibility_Criteria__c', 'Stage__c'));
        result.put('rulesValidationType', getPicklistValues('Eligibility_Criteria__c', 'Validation_Type__c'));
        result.put('questionItemStage', getPicklistValues('Scheme_Question_Items__c', 'Stage__c'));
        result.put('questionItemType', getPicklistValues('Scheme_Question_Items__c', 'Type__c'));
        result.put('questionItemAttachments', getPicklistValues('Scheme_Question_Items__c', 'Attachments__c'));  // NEW
        result.put('applicationStages', getPicklistValues('Yearly_Schemes__c', 'Application_Stages__c'));   // NEW
        result.put('requiredDegree', getPicklistValues('Yearly_Schemes__c', 'Required_Degree__c'));   
        result.put('stageForDocument', getPicklistValues('Documents__c', 'Stage__c'));       //      // NEW (multi-select)
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean yearlySchemeExists(Id yearId, Id schemeItemId) {
        return [SELECT COUNT()FROM Yearly_Schemes__c WHERE Year__c = :yearId AND Scheme_Items__c = :schemeItemId] > 0;
    }

    @AuraEnabled
    public static Id cloneYearlyScheme(Id recordId,Yearly_Schemes__c parentOverrides,List<Eligibility_Check_List__c> checkListRecords,
                                        List<Eligibility_Criteria__c> rulesRecords,List<Scheme_Question_Items__c> questionItemRecords,List<Documents__c> documentsRecords,  List<External_Participants__c> externalParticipantsRecords,    List<Reviewer_Question_Template__c> reviewerQuestionTemplateRecords, List<Yearly_Scheme_Instructions__c> yearlySchemeInstructionsRecords ){
        try {
            List<Yearly_Schemes__c> originalList = [SELECT Id, OwnerId FROM Yearly_Schemes__c WHERE Id = :recordId LIMIT 1];

            if (originalList.isEmpty()) {
                throw new AuraHandledException('Yearly Scheme not found for Id: ' + recordId);
            }
            Yearly_Schemes__c original = originalList[0];

            //==========================
            // Create Parent Clone
            //==========================
            Yearly_Schemes__c cloned = new Yearly_Schemes__c();
            cloned.OwnerId = UserInfo.getUserId();
            if (parentOverrides != null) {
                cloned.Scheme_Items__c = parentOverrides.Scheme_Items__c;
                cloned.Year__c = parentOverrides.Year__c;
                cloned.Is_Active__c = parentOverrides.Is_Active__c;
                cloned.Scheme_Start_Date__c = parentOverrides.Scheme_Start_Date__c;
                cloned.Second_Stage_Start_Date__c = parentOverrides.Second_Stage_Start_Date__c;
                cloned.Scheme_End_Date__c = parentOverrides.Scheme_End_Date__c;
                cloned.Second_Stage_End_Date__c = parentOverrides.Second_Stage_End_Date__c;
                cloned.Scheme_Visibility__c = parentOverrides.Scheme_Visibility__c;
                cloned.CurrencyIsoCode = parentOverrides.CurrencyIsoCode;
                cloned.Round__c = parentOverrides.Round__c;

                // NEW fields
                cloned.Team_Size_Limits__c = parentOverrides.Team_Size_Limits__c;
                cloned.Required_Degree__c = parentOverrides.Required_Degree__c;
                cloned.Experience_Required__c = parentOverrides.Experience_Required__c;
                cloned.Experience_Required_To__c = parentOverrides.Experience_Required_To__c;
                cloned.Budget_Cap__c = parentOverrides.Budget_Cap__c;
                cloned.Application_Stages__c = parentOverrides.Application_Stages__c;
            }
            insert cloned;

            //====================================================
            // Clone Eligibility Check List (values as edited on screen)
            //====================================================
            if (checkListRecords != null && !checkListRecords.isEmpty()) {
                List<Eligibility_Check_List__c> newRecords = new List<Eligibility_Check_List__c>();
                for (Eligibility_Check_List__c src : checkListRecords) {
                    Eligibility_Check_List__c rec = new Eligibility_Check_List__c();
                    rec.Stage__c = src.Stage__c;
                    rec.Display_Question__c = src.Display_Question__c;
                    rec.Type__c = src.Type__c;
                    rec.CurrencyIsoCode = src.CurrencyIsoCode;
                    rec.Yearly_Scheme__c = cloned.Id;
                    newRecords.add(rec);
                }
                insert newRecords;
            }
            //====================================================
            // Clone Eligibility Rules (values as edited on screen)
            //====================================================
            if (rulesRecords != null && !rulesRecords.isEmpty()) {
                List<Eligibility_Criteria__c> newCriteriaList  = new List<Eligibility_Criteria__c>();
                Map<Id, Id> criteriaIdMap = new Map<Id, Id>();
                for (Eligibility_Criteria__c src : rulesRecords) {
                    
                    Eligibility_Criteria__c newCriteria = src.clone(false, true, false, false);
                    newCriteria.Yearly_Scheme__c = cloned.Id;
                    newCriteriaList.add(newCriteria);
                }
                if (!newCriteriaList.isEmpty()) {
                    insert newCriteriaList ;
                }
                for (Integer i = 0; i < rulesRecords.size(); i++) {
                    criteriaIdMap.put(
                        rulesRecords[i].Id,
                        newCriteriaList[i].Id
                    );
                }
                List<Eligibility_Condition__c> oldConditions = [
                    SELECT Id,
                        Eligibility_Criteria__c,
                        Field_API_Name__c,
                        Logical_Operator__c,
                        Object_API_Name__c,
                        Operator__c,
                        Sequence__c,
                        Value__c
                    FROM Eligibility_Condition__c
                    WHERE Eligibility_Criteria__c IN :criteriaIdMap.keySet()
                ];
                List<Eligibility_Condition__c> newConditions = new List<Eligibility_Condition__c>();

                for (Eligibility_Condition__c oldCondition : oldConditions) {

                    Eligibility_Condition__c newCondition =
                        oldCondition.clone(false, true, false, false);

                    // IMPORTANT:
                    // Point condition to NEW Eligibility Criteria
                    newCondition.Eligibility_Criteria__c =
                        criteriaIdMap.get(oldCondition.Eligibility_Criteria__c);

                    newConditions.add(newCondition);
                }
                if (!newConditions.isEmpty()) {
                    insert newConditions;
                }
            }
            //====================================================
            // Create Scheme Question Items (fresh records from picked Questionnaires)
            //====================================================
            if (questionItemRecords != null && !questionItemRecords.isEmpty()) {
                List<Scheme_Question_Items__c> newRecords = new List<Scheme_Question_Items__c>();
                for (Scheme_Question_Items__c src : questionItemRecords) {
                    Scheme_Question_Items__c rec = new Scheme_Question_Items__c();
                    rec.Stage__c = src.Stage__c;
                    rec.CurrencyIsoCode = src.CurrencyIsoCode;
                    rec.Scheme_Questionnaire__c = src.Scheme_Questionnaire__c;
                    rec.Question__c = src.Question__c;
                    rec.Mandatory__c = src.Mandatory__c;
                    rec.Type__c = src.Type__c;
                    rec.Max_Character__c = src.Max_Character__c;
                    rec.Min_Character__c = src.Min_Character__c;
                    rec.Is_Active__c = src.Is_Active__c;
                    rec.Attachments__c = src.Attachments__c;
                    rec.Section__c = src.Section__c;                 
                    rec.SL_No__c = src.SL_No__c;                      
                    rec.Picklist_Values__c = src.Picklist_Values__c; 
                    rec.Dynamic_Question__c = true;
                    rec.Yearly_Scheme__c = cloned.Id;
                    newRecords.add(rec);
                }
                insert newRecords;
            }

        if (documentsRecords != null && !documentsRecords.isEmpty()) {
            List<Documents__c> newRecords = new List<Documents__c>();
            for (Documents__c src : documentsRecords) {
                Documents__c rec = new Documents__c();
                rec.Document_Master__c = src.Document_Master__c;
                rec.Document_Name__c = src.Document_Name__c;
                rec.Is_Active__c = src.Is_Active__c;
                rec.Is_Required__c = src.Is_Required__c;
                rec.Roles__c = src.Roles__c;
                rec.Stage__c = src.Stage__c;
                rec.Yearly_Scheme__c = cloned.Id;
                newRecords.add(rec);
            }

            insert newRecords;
        }
        //====================================================
        // Clone External Participants
        //====================================================

        if (externalParticipantsRecords != null &&
            !externalParticipantsRecords.isEmpty()) {

            List<External_Participants__c> newRecords =
                new List<External_Participants__c>();

            for (External_Participants__c src :
                externalParticipantsRecords) {

                External_Participants__c rec =
                    new External_Participants__c();

                rec.External_Participants__c =
                    src.External_Participants__c;

                rec.External_Participants_Count__c =
                    src.External_Participants_Count__c;

                rec.External_Participants_Status__c =
                    src.External_Participants_Status__c;

                rec.Maximum_Participants_Count__c =
                    src.Maximum_Participants_Count__c;

                rec.Stage__c =
                    src.Stage__c;

                rec.Yearly_Scheme__c =
                    cloned.Id;

                newRecords.add(rec);
            }

            insert newRecords;
        }
        //====================================================
    // Clone Reviewer Question Templates
    //====================================================

        if (reviewerQuestionTemplateRecords != null &&
            !reviewerQuestionTemplateRecords.isEmpty()) {

            List<Reviewer_Question_Template__c> newRecords =
                new List<Reviewer_Question_Template__c>();

            for (Reviewer_Question_Template__c src :
                reviewerQuestionTemplateRecords) {

                Reviewer_Question_Template__c rec =
                    new Reviewer_Question_Template__c();

                rec.Is_Visible_To_Peer_Reviewer__c =
                    src.Is_Visible_To_Peer_Reviewer__c;

                rec.Question__c =
                    src.Question__c;

                rec.Scheme_Questionnaire__c =
                    src.Scheme_Questionnaire__c;

                rec.Section__c =
                    src.Section__c;

                rec.SL_No__c =
                    src.SL_No__c;

                rec.Stage__c =
                    src.Stage__c;

                rec.Yearly_Schemes__c =
                    cloned.Id;

                newRecords.add(rec);
            }

            insert newRecords;
        }
            //====================================================
        // Clone Yearly Scheme Instructions
        //====================================================

        if (yearlySchemeInstructionsRecords != null &&
            !yearlySchemeInstructionsRecords.isEmpty()) {

            List<Yearly_Scheme_Instructions__c> newRecords =
                new List<Yearly_Scheme_Instructions__c>();

            for (Yearly_Scheme_Instructions__c src :
                yearlySchemeInstructionsRecords) {

                Yearly_Scheme_Instructions__c rec =
                    new Yearly_Scheme_Instructions__c();

                rec.Instructions__c =
                    src.Instructions__c;

                rec.Know_More__c =
                    src.Know_More__c;


                rec.Pages_Name__c =
                    src.Pages_Name__c;

                rec.Stage__c =
                    src.Stage__c;

                rec.Type__c =
                    src.Type__c;

                rec.Yearly_Scheme__c =
                    cloned.Id;

                newRecords.add(rec);
            }

            insert newRecords;
        }
        //====================================================
        // Clone Grants Team Members
        //====================================================

        // if (grantsTeamMembersRecords != null &&
  

        //     List<Grants_Team_Members__c> newRecords =
        //         new List<Grants_Team_Members__c>();

        //     for (Grants_Team_Members__c src :
        //         grantsTeamMembersRecords) {

        //         Grants_Team_Members__c rec =
        //             new Grants_Team_Members__c();

        //         rec.Application_Stages__c =
        //             src.Application_Stages__c;

        //         rec.User__c =
        //             src.User__c;

        //         rec.Yearly_Scheme__c =
        //             cloned.Id;

        //         newRecords.add(rec);
        //     }

        //     insert newRecords;
        // }
        //====================================================
        // Clone Committee Members
        //====================================================

        // if (committeeMembersRecords != null &&

        //     List<Committee_Member__c> newRecords = new List<Committee_Member__c>();

        //     for (Committee_Member__c src : committeeMembersRecords) {

        //         Committee_Member__c rec = new Committee_Member__c();

        //         rec.Alternative_Mobile_Number__c = src.Alternative_Mobile_Number__c;

        //         rec.Assignment_Count__c = src.Assignment_Count__c;

        //         rec.City__c = src.City__c;

        //         rec.Committee_Master__c = src.Committee_Master__c;

        //         rec.Country__c = src.Country__c;

        //         rec.Department__c = src.Department__c;

        //         rec.Designation__c = src.Designation__c;

        //         rec.Email__c = src.Email__c;

        //         rec.First_Name__c =
        //             src.First_Name__c;

        //         rec.Is_Committee_Review__c =
        //             src.Is_Committee_Review__c;

        //         rec.Last_Name__c =
        //             src.Last_Name__c;

        //         rec.Mobile_Number__c =
        //             src.Mobile_Number__c;

        //         rec.Organisation_Name__c =
        //             src.Organisation_Name__c;

        //         rec.Sequence__c =
        //             src.Sequence__c;

        //         rec.State__c =
        //             src.State__c;

        //         rec.Title__c =
        //             src.Title__c;

        //         rec.Type__c =
        //             src.Type__c;

        //         rec.Yearly_Schemes__c =
        //             cloned.Id;

        //         newRecords.add(rec);
        //     }

        //     insert newRecords;
        //}
        
            return cloned.Id;
        }
        catch (DmlException e) {
            if (e.getDmlMessage(0).contains('A Yearly Scheme already exists')) {
                throw new AuraHandledException(
                    'A Yearly Scheme already exists for the selected Year and Scheme. Please choose a different Year or Scheme before cloning.'
                );
            }
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Unable to clone the Yearly Scheme. Please contact your administrator if the problem persists.');
        }
    }



}