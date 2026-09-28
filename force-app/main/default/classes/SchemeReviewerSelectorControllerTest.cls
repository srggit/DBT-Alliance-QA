@IsTest
private class SchemeReviewerSelectorControllerTest {

    private static Yearly_Schemes__c createYearlyScheme() {
        Scheme__c scheme = new Scheme__c();
        insert scheme;
        Scheme_Items__c schemeItem = new Scheme_Items__c(Scheme__c = scheme.Id);
        insert schemeItem;
        Yearly_Schemes__c yearlyScheme = new Yearly_Schemes__c(Scheme_Items__c = schemeItem.Id, Is_Active__c = true);
        insert yearlyScheme;
        return yearlyScheme;
    }

    private static List<Reviewer__c> createReviewers(Integer count) {
        List<Reviewer__c> reviewers = new List<Reviewer__c>();
        for (Integer i = 0; i < count; i++) {
            reviewers.add(new Reviewer__c(
                First_Name__c = 'Rev' + i,
                Last_Name__c = 'Test',
                Email_Address__c = 'rev' + i + '@example.com',
                Reviewer_Type__c = 'Peer'
            ));
        }
        insert reviewers;
        return reviewers;
    }

    @IsTest
    static void getYearlySchemesReturnsSchemes() {
        Yearly_Schemes__c yearlyScheme = createYearlyScheme();
        List<SchemeReviewerSelectorController.SchemeOption> options = SchemeReviewerSelectorController.getYearlySchemes();
        System.assert(!options.isEmpty());
        Boolean found = false;
        for (SchemeReviewerSelectorController.SchemeOption option : options) {
            if (option.value == yearlyScheme.Id) {
                found = true;
            }
        }
        System.assert(found);
    }

    @IsTest
    static void saveCreatesSchemeReviewersAndFlagsThemAsAdded() {
        Yearly_Schemes__c yearlyScheme = createYearlyScheme();
        List<Reviewer__c> reviewers = createReviewers(3);

        String json = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{ 'reviewerId' => reviewers[0].Id, 'isActive' => true },
            new Map<String, Object>{ 'reviewerId' => reviewers[1].Id, 'isActive' => false }
        });
        Test.startTest();
        Integer created = SchemeReviewerSelectorController.saveSchemeReviewers(yearlyScheme.Id, json);
        Test.stopTest();

        System.assertEquals(2, created);
        Map<Id, Scheme_Reviewer__c> byReviewer = new Map<Id, Scheme_Reviewer__c>();
        for (Scheme_Reviewer__c sr : [
            SELECT Reviewer__c, Is_Active__c FROM Scheme_Reviewer__c WHERE Yearly_Schemes__c = :yearlyScheme.Id
        ]) {
            byReviewer.put(sr.Reviewer__c, sr);
        }
        System.assertEquals(true, byReviewer.get(reviewers[0].Id).Is_Active__c);
        System.assertEquals(false, byReviewer.get(reviewers[1].Id).Is_Active__c);

        Integer addedCount = 0;
        for (SchemeReviewerSelectorController.ReviewerRow row : SchemeReviewerSelectorController.getReviewers(yearlyScheme.Id)) {
            if (row.alreadyAdded) {
                addedCount++;
            }
        }
        System.assertEquals(2, addedCount);
    }

    @IsTest
    static void savingAlreadyAddedReviewerIsRejected() {
        Yearly_Schemes__c yearlyScheme = createYearlyScheme();
        List<Reviewer__c> reviewers = createReviewers(1);
        String json = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{ 'reviewerId' => reviewers[0].Id, 'isActive' => true }
        });
        SchemeReviewerSelectorController.saveSchemeReviewers(yearlyScheme.Id, json);

        try {
            SchemeReviewerSelectorController.saveSchemeReviewers(yearlyScheme.Id, json);
            System.assert(false, 'Expected a duplicate to be rejected.');
        } catch (AuraHandledException e) {
            System.assertEquals(1, [SELECT COUNT() FROM Scheme_Reviewer__c WHERE Yearly_Schemes__c = :yearlyScheme.Id]);
        }
    }

    @IsTest
    static void validationErrors() {
        try {
            SchemeReviewerSelectorController.saveSchemeReviewers(null, '[]');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Yearly_Schemes__c yearlyScheme = createYearlyScheme();
        try {
            SchemeReviewerSelectorController.saveSchemeReviewers(yearlyScheme.Id, '[]');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            SchemeReviewerSelectorController.saveSchemeReviewers(yearlyScheme.Id, 'not json');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            SchemeReviewerSelectorController.getReviewers(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}