// @RestResource(urlMapping='/getGlobalPicklistValues')
// global without sharing class GlobalPicklistValues {
	
//     @HttpGet
//     global static ResponseWrapper getPicklistValues(){
        
//         ResponseWrapper response = new ResponseWrapper();
        
//         Contact.Nationality__c.getDescribe();
        
//         Schema.DescribeFieldResult nationalityFieldResult = Contact.Nationality__c.getDescribe();
//         response.nationalityValues = getSafePicklistValues(nationalityFieldResult);
        
//         Schema.DescribeFieldResult institutionCategoriesFieldResult = Account.Institution_Categories__c.getDescribe();
// 		response.institutionalCategoriesValues = getSafePicklistValues(institutionCategoriesFieldResult);

//         Schema.DescribeFieldResult titleFieldResult = Contact.Title__c.getDescribe();
//         response.titleFieldResultValues = getSafePicklistValues(titleFieldResult);

//         Schema.DescribeFieldResult rolesFieldResult = Proposal_Participant_Association__c.Roles__c.getDescribe();
//         response.rolesValues = getSafePicklistValues(rolesFieldResult);

//         Schema.DescribeFieldResult decisionOnPreviousApplicationFieldResult = Applicant_Proposal_Association__c.Decision_on_previous_application__c.getDescribe();
//         response.decisionOnPreviousApplicationValues = getSafePicklistValues(decisionOnPreviousApplicationFieldResult);


//         Map<String, String> accountMap = new Map<String, String>();
//         for (Account acc : [ SELECT Id, Name FROM Account Where Organization_Status__c='Listed'
//                              ORDER BY Name]) {
//             accountMap.put(acc.Id, acc.Name);
//         }
//         response.accounts = accountMap;

//         return response;
//     }
    
    
//     private static FieldResult getSafePicklistValues(Schema.DescribeFieldResult fieldDescribe){
        
//         FieldResult result = new FieldResult();
        
//         try{    
//             List<String> activeValues = new List<String>();

//             List<Schema.PicklistEntry> nList = fieldDescribe.getPicklistValues();
//             for (Schema.PicklistEntry pickListVal : nList) {
//                 if (pickListVal.isActive()) {
//                     activeValues.add(pickListVal.getLabel()); // Use getValue() for API names
//                 }
//             }
            
//             result.status = 'Success';
//             result.values = activeValues;
            
//         }catch(Exception ex){
//             result.status = 'Error';
//             result.errorMessage = 'Error fetching picklist values: ' + ex.getMessage();
//         }
        
//         return result;
//     }
    
//     global class ResponseWrapper {
//         public FieldResult nationalityValues;
//         public FieldResult institutionalCategoriesValues;
//         public FieldResult titleFieldResultValues;
//         public FieldResult rolesValues;
//         public FieldResult decisionOnPreviousApplicationValues;
//         public Map<String, String> accounts;
//     }
    
//     global class FieldResult {
//         public String status;
//         public String errorMessage;
//         public List<String> values;
//     }   
// }


@RestResource(urlMapping='/getGlobalPicklistValues')
global without sharing class GlobalPicklistValues {

    @HttpGet
    global static ResponseWrapper getPicklistValues() {

        ResponseWrapper response = new ResponseWrapper();

        // Nationality
        Schema.DescribeFieldResult nationalityFieldResult = Contact.Nationality__c.getDescribe();
        response.nationalityValues = getSafePicklistValues(nationalityFieldResult);

        // Institution Categories
        Schema.DescribeFieldResult institutionCategoriesFieldResult = Account.Institution_Categories__c.getDescribe();
        response.institutionalCategoriesValues = getSafePicklistValues(institutionCategoriesFieldResult);

        // Title
        Schema.DescribeFieldResult titleFieldResult = Contact.Title__c.getDescribe();
        response.titleFieldResultValues = getSafePicklistValues(titleFieldResult);

        // Roles (Exclude Applicant)
        Schema.DescribeFieldResult rolesFieldResult = Proposal_Participant_Association__c.Roles__c.getDescribe();
        response.rolesValues = getSafePicklistValues(rolesFieldResult,
            new Set<String>{ 'Applicant' } // API Value
        );

        Schema.DescribeFieldResult jobTitleFieldResult = Staff_Budget__c.Job_Title__c.getDescribe();
        response.jobTitleFieldResultValues = getSafePicklistValues(jobTitleFieldResult);

        Schema.DescribeFieldResult yearFieldResult = Equipment__c.Year_Required__c.getDescribe();
        response.yearFieldResultResultValues = getSafePicklistValues(jobTitleFieldResult);

        // Country
        Schema.DescribeFieldResult countryFieldResult = Contact.Country__c.getDescribe();
        response.countryValues = getSafePicklistValues(countryFieldResult);

        // Decision on Previous Application
        Schema.DescribeFieldResult decisionOnPreviousApplicationFieldResult = Other_Grants__c.Decision_on_previous_application__c.getDescribe();
        response.decisionOnPreviousApplicationValues = getSafePicklistValues(decisionOnPreviousApplicationFieldResult);

        // HostAccounts
        Map<String, String> accountMap = new Map<String, String>();
        for (Account acc : [SELECT Id, Name FROM Account WHERE Organization_Status__c = 'Listed' ORDER BY Name]) {
            accountMap.put(acc.Id, acc.Name);
        }
        response.accounts = accountMap;

        //OrganiZation Accounts
        Map<String, String> organizationMap = new Map<String, String>();
        for (Account acc1 : [SELECT Id, Name FROM Account WHERE Type != 'Host' ORDER BY Name]) {
            organizationMap.put(acc1.Id, acc1.Name);
        }
        response.organizations = organizationMap;


        return response;
    }

    // Default method (No exclusions)
    private static FieldResult getSafePicklistValues(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        return getSafePicklistValues(fieldDescribe, new Set<String>());
    }

    // Overloaded method (Supports exclusions)
    private static FieldResult getSafePicklistValues(
        Schema.DescribeFieldResult fieldDescribe,
        Set<String> excludedValues
    ) {

        FieldResult result = new FieldResult();

        try {
            List<String> activeValues = new List<String>();

            for (Schema.PicklistEntry pickListVal : fieldDescribe.getPicklistValues()) {

                if (pickListVal.isActive()
                    && !excludedValues.contains(pickListVal.getValue())) {

                    // Use getLabel() if you want labels in the response
                    activeValues.add(pickListVal.getLabel());

                    // Or use getValue() if API values are required
                    // activeValues.add(pickListVal.getValue());
                }
            }

            result.status = 'Success';
            result.values = activeValues;

        } catch (Exception ex) {
            result.status = 'Error';
            result.errorMessage = 'Error fetching picklist values: ' + ex.getMessage();
        }

        return result;
    }

    global class ResponseWrapper {
        public FieldResult nationalityValues;
        public FieldResult institutionalCategoriesValues;
        public FieldResult titleFieldResultValues;
        public FieldResult jobTitleFieldResultValues;
        public FieldResult yearFieldResultResultValues;
        public FieldResult rolesValues;
        public FieldResult countryValues;
        public FieldResult decisionOnPreviousApplicationValues;
        public Map<String, String> accounts;
        public Map<String, String> organizations;
    }

    global class FieldResult {
        public String status;
        public String errorMessage;
        public List<String> values;
    }
}