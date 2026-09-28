public with sharing class SchemeReviewerSelectorController {

    // Yearly Schemes for the picker shown when the component is placed somewhere with no
    // record context (App Page / Tab / Home Page). Not cacheable: new schemes appear at once.
    @AuraEnabled
    public static List<SchemeOption> getYearlySchemes() {
        List<SchemeOption> options = new List<SchemeOption>();
        for (Yearly_Schemes__c scheme : [
            SELECT Id, Name, Scheme_Items__r.Name
            FROM Yearly_Schemes__c
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            String label = scheme.Name;
            if (scheme.Scheme_Items__r != null && String.isNotBlank(scheme.Scheme_Items__r.Name)) {
                label += ' - ' + scheme.Scheme_Items__r.Name;
            }
            options.add(new SchemeOption(scheme.Id, label));
        }
        return options;
    }

    // Every Reviewer__c (the master list), flagged when it is already a Scheme_Reviewer__c of
    // this Yearly Scheme. Not cacheable: the "already added" flag changes as soon as you save.
    @AuraEnabled
    public static List<ReviewerRow> getReviewers(Id yearlySchemeId) {
        if (yearlySchemeId == null) {
            throw new AuraHandledException('Yearly Scheme is required.');
        }

        Set<Id> addedReviewerIds = new Set<Id>();
        for (Scheme_Reviewer__c existing : [
            SELECT Reviewer__c
            FROM Scheme_Reviewer__c
            WHERE Yearly_Schemes__c = :yearlySchemeId AND Reviewer__c != null
        ]) {
            addedReviewerIds.add(existing.Reviewer__c);
        }

        List<ReviewerRow> rows = new List<ReviewerRow>();
        for (Reviewer__c reviewer : [
            SELECT Id, Title__c, First_Name__c, Last_Name__c, Email_Address__c,
                   Reviewer_Type__c, Organisation__r.Name
            FROM Reviewer__c
            ORDER BY First_Name__c ASC NULLS LAST, Last_Name__c ASC NULLS LAST
        ]) {
            rows.add(new ReviewerRow(reviewer, addedReviewerIds.contains(reviewer.Id)));
        }
        return rows;
    }

    // Creates one Scheme_Reviewer__c under the Yearly Scheme for each selected reviewer, with the
    // chosen Is_Active__c. Reviewers already on the scheme are skipped (no duplicates).
    // selectionsJson: [{ "reviewerId": "<Id>", "isActive": true }, ...] - a JSON string because
    // Aura doesn't reliably bind a list of custom Apex objects passed from LWC.
    @AuraEnabled
    public static Integer saveSchemeReviewers(Id yearlySchemeId, String selectionsJson) {
        if (yearlySchemeId == null) {
            throw new AuraHandledException('Yearly Scheme is required.');
        }
        List<ReviewerSelection> selections;
        try {
            selections = String.isBlank(selectionsJson)
                ? new List<ReviewerSelection>()
                : (List<ReviewerSelection>) JSON.deserialize(selectionsJson, List<ReviewerSelection>.class);
        } catch (JSONException e) {
            throw new AuraHandledException('Invalid selection: ' + e.getMessage());
        }
        if (selections.isEmpty()) {
            throw new AuraHandledException('Select at least one Reviewer.');
        }

        Map<Id, Boolean> isActiveByReviewerId = new Map<Id, Boolean>();
        for (ReviewerSelection selection : selections) {
            if (selection.reviewerId != null) {
                isActiveByReviewerId.put(selection.reviewerId, selection.isActive == true);
            }
        }

        for (Scheme_Reviewer__c existing : [
            SELECT Reviewer__c
            FROM Scheme_Reviewer__c
            WHERE Yearly_Schemes__c = :yearlySchemeId AND Reviewer__c IN :isActiveByReviewerId.keySet()
        ]) {
            isActiveByReviewerId.remove(existing.Reviewer__c);
        }
        if (isActiveByReviewerId.isEmpty()) {
            throw new AuraHandledException('The selected Reviewers are already on this Yearly Scheme.');
        }

        List<Scheme_Reviewer__c> toInsert = new List<Scheme_Reviewer__c>();
        for (Id reviewerId : isActiveByReviewerId.keySet()) {
            toInsert.add(new Scheme_Reviewer__c(
                Yearly_Schemes__c = yearlySchemeId,
                Reviewer__c = reviewerId,
                Is_Active__c = isActiveByReviewerId.get(reviewerId)
            ));
        }
        try {
            insert toInsert;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to save Scheme Reviewers: ' + e.getDmlMessage(0));
        }
        return toInsert.size();
    }

    public class ReviewerSelection {
        public Id reviewerId;
        public Boolean isActive;
    }

    public class SchemeOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;

        public SchemeOption(Id value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class ReviewerRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String organization;
        @AuraEnabled public String reviewerType;
        @AuraEnabled public Boolean alreadyAdded;

        public ReviewerRow(Reviewer__c reviewer, Boolean alreadyAdded) {
            this.id = reviewer.Id;
            List<String> parts = new List<String>();
            for (String part : new List<String>{ reviewer.Title__c, reviewer.First_Name__c, reviewer.Last_Name__c }) {
                if (String.isNotBlank(part)) {
                    parts.add(part.trim());
                }
            }
            this.name = String.join(parts, ' ');
            this.email = reviewer.Email_Address__c;
            this.organization = reviewer.Organisation__r != null ? reviewer.Organisation__r.Name : null;
            this.reviewerType = reviewer.Reviewer_Type__c;
            this.alreadyAdded = alreadyAdded;
        }
    }
}