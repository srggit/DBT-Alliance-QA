public with sharing class ReviewerQuestionTemplateActionController {

    @AuraEnabled
    public static Yearly_Schemes__c getYearlySchemeInfo(Id recordId) {
        List<Yearly_Schemes__c> results = [SELECT Id, Name, Scheme_Items__c, Scheme_Items__r.Name FROM Yearly_Schemes__c WHERE Id = :recordId];
        if (results.isEmpty()) {
            throw new AuraHandledException('Yearly Scheme not found for Id: ' + recordId);
        }
        return results[0];
    }

    // All Scheme Questionnaires tied to the Scheme Item on this Yearly Scheme.
    // Section__c here is read from the Questionnaire, per the "section -> Scheme
    // Questionnaire" requirement (not the target Reviewer Question Template record).
    @AuraEnabled
    public static List<Scheme_Questionnaire__c> getQuestionnairesByItem(Id schemeItemId) {
        if (schemeItemId == null) {
            return new List<Scheme_Questionnaire__c>();
        }
        return [SELECT Id, Name, Display_Name__c, Section__c, SL_No__c,Stage__c FROM Scheme_Questionnaire__c WHERE Scheme_Items__c = :schemeItemId ORDER BY Name];
    }

    // Reviewer Question Template records already created for this Yearly Scheme,
    // keyed by the Scheme_Questionnaire__c they were sourced from, so rows already
    // added can be shown read-only instead of re-creatable.
    @AuraEnabled
    public static List<Reviewer_Question_Template__c> getExistingReviewerTemplates(Id recordId) {
        return [
            SELECT Id, Name, Question__c, Section__c, Is_Visible_To_Peer_Reviewer__c, Scheme_Questionnaire__c, SL_No__c,Stage__c, CreatedDate, CreatedBy.Name
            FROM Reviewer_Question_Template__c
            WHERE Yearly_Schemes__c = :recordId AND Scheme_Questionnaire__c != null
        ];
    }

    @AuraEnabled
    public static Integer saveReviewerQuestionTemplates(Id recordId, List<Reviewer_Question_Template__c> templateRecords) {
        try {
            if (templateRecords == null || templateRecords.isEmpty()) {
                throw new AuraHandledException('No questions were selected.');
            }

            List<Reviewer_Question_Template__c> newRecords = new List<Reviewer_Question_Template__c>();
            for (Reviewer_Question_Template__c src : templateRecords) {
                Reviewer_Question_Template__c rec = new Reviewer_Question_Template__c();
                rec.Scheme_Questionnaire__c = src.Scheme_Questionnaire__c;
                rec.Question__c = src.Question__c;
                rec.Section__c = src.Section__c;
                rec.SL_No__c = src.SL_No__c;
                rec.Stage__c = src.Stage__c;
                rec.Is_Visible_To_Peer_Reviewer__c = src.Is_Visible_To_Peer_Reviewer__c;
                rec.Yearly_Schemes__c = recordId;
                newRecords.add(rec);
            }
            insert newRecords;
            return newRecords.size();
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Unable to save Reviewer Question Templates. Please contact your administrator if the problem persists.');
        }
    }
}









// public with sharing class ReviewerQuestionTemplateActionController {

//     @AuraEnabled
//     public static Yearly_Schemes__c getYearlySchemeInfo(Id recordId) {
//         List<Yearly_Schemes__c> results = [SELECT Id, Name, Scheme_Items__c, Scheme_Items__r.Name FROM Yearly_Schemes__c WHERE Id = :recordId];
//         if (results.isEmpty()) {
//             throw new AuraHandledException('Yearly Scheme not found for Id: ' + recordId);
//         }
//         return results[0];
//     }

//     // All Scheme Questionnaires tied to the Scheme Item on this Yearly Scheme.
//     // Section__c here is read from the Questionnaire, per the "section -> Scheme
//     // Questionnaire" requirement (not the target Reviewer Question Template record).
//     @AuraEnabled
//     public static List<Scheme_Questionnaire__c> getQuestionnairesByItem(Id schemeItemId) {
//         if (schemeItemId == null) {
//             return new List<Scheme_Questionnaire__c>();
//         }
//         return [SELECT Id, Name, Display_Name__c, Section__c, SL_No__c,Stage__c FROM Scheme_Questionnaire__c WHERE Scheme_Items__c = :schemeItemId ORDER BY Name];
//     }

//     // Reviewer Question Template records already created for this Yearly Scheme,
//     // keyed by the Scheme_Questionnaire__c they were sourced from, so rows already
//     // added can be shown read-only instead of re-creatable.
//     @AuraEnabled
//     public static List<Reviewer_Question_Template__c> getExistingReviewerTemplates(Id recordId) {
//         return [
//             SELECT Id, Name, Question__c, Section__c, Is_Visible_To_Peer_Reviewer__c, Scheme_Questionnaire__c, SL_No__c,Stage__c, CreatedDate, CreatedBy.Name
//             FROM Reviewer_Question_Template__c
//             WHERE Yearly_Schemes__c = :recordId AND Scheme_Questionnaire__c != null
//         ];
//     }

//     @AuraEnabled
//     public static Integer saveReviewerQuestionTemplates(Id recordId, List<Reviewer_Question_Template__c> templateRecords) {
//         try {
//             if (templateRecords == null || templateRecords.isEmpty()) {
//                 throw new AuraHandledException('No questions were selected.');
//             }

//             List<Reviewer_Question_Template__c> newRecords = new List<Reviewer_Question_Template__c>();
//             for (Reviewer_Question_Template__c src : templateRecords) {
//                 Reviewer_Question_Template__c rec = new Reviewer_Question_Template__c();
//                 rec.Scheme_Questionnaire__c = src.Scheme_Questionnaire__c;
//                 rec.Question__c = src.Question__c;
//                 rec.Section__c = src.Section__c;
//                 rec.SL_No__c = src.SL_No__c;
//                 rec.Is_Visible_To_Peer_Reviewer__c = src.Is_Visible_To_Peer_Reviewer__c;
//                 rec.Yearly_Schemes__c = recordId;
//                 newRecords.add(rec);
//             }
//             insert newRecords;
//             return newRecords.size();
//         } catch (DmlException e) {
//             throw new AuraHandledException(e.getDmlMessage(0));
//         } catch (Exception e) {
//             throw new AuraHandledException('Unable to save Reviewer Question Templates. Please contact your administrator if the problem persists.');
//         }
//     }
// }