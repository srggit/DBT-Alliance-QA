public class ApplicantProposalAssociationHandler {
    
    public static void copyDocumentsFromYearlyScheme(List<Applicant_Proposal_Association__c> newAPAs) {
        Set<Id> yearlySchemeIds = new Set<Id>();

        // Collect all related Yearly Scheme IDs from the newly inserted APAs
        for (Applicant_Proposal_Association__c apa : newAPAs) {
            if (apa.Yearly_Scheme__c != null) {
                yearlySchemeIds.add(apa.Yearly_Scheme__c);
            }
        }

        if (yearlySchemeIds.isEmpty()) {
            return;
        }

        // Query required Scheme Documents related to the Yearly Schemes
        // Replace Scheme_Document__c and field API names with your exact schema
        Map<Id, List<Documents__c>> schemeIdToDocsMap = new Map<Id, List<Documents__c>>();
        
        for (Documents__c schemeDoc : [
            SELECT Id, Name, Document_Name__c, Yearly_Scheme__c, Is_Required__c, Roles__c, Stage__c
            FROM Documents__c
            WHERE Yearly_Scheme__c IN :yearlySchemeIds
        ]) {
            if (!schemeIdToDocsMap.containsKey(schemeDoc.Yearly_Scheme__c)) {
                schemeIdToDocsMap.put(schemeDoc.Yearly_Scheme__c, new List<Documents__c>());
            }
            schemeIdToDocsMap.get(schemeDoc.Yearly_Scheme__c).add(schemeDoc);
        }

        // List to hold new Document records to be inserted
        List<User_Documents__c> docsToInsert = new List<User_Documents__c>();

        // Map and create Document records for each APA
        for (Applicant_Proposal_Association__c apa : newAPAs) {
            if (apa.Yearly_Scheme__c != null && schemeIdToDocsMap.containsKey(apa.Yearly_Scheme__c)) {
                for (Documents__c schemeDoc : schemeIdToDocsMap.get(apa.Yearly_Scheme__c)) {
                    User_Documents__c newDoc = new User_Documents__c();
                    
                    // Field Mappings
                    newDoc.Applicant_Proposal_Association__c = apa.Id;
                    newDoc.Roles__c = schemeDoc.Roles__c;
                    newDoc.Stages__c = schemeDoc.Stage__c;
                    newDoc.User_Document_Name__c = schemeDoc.Document_Name__c;
                    newDoc.Is_Required__c = schemeDoc.Is_Required__c;
                    
                    docsToInsert.add(newDoc);
                }
            }
        }

        // Insert new document records in bulk
        if (!docsToInsert.isEmpty()) {
            insert docsToInsert;
        }
    }

}