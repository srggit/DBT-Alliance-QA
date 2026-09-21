public without sharing class EligibilityEvaluationService {

    private static final String OBJECT_CONTACT = 'Contact';

    @AuraEnabled
    public static EligibilityEvaluationResult evaluateYearlySchemeForCurrentUser(String yearlySchemeId) {
        Id contactId = resolveCurrentUserContactId();
        return evaluateYearlyScheme(contactId, yearlySchemeId);
    }

    @AuraEnabled
    public static EligibilityEvaluationResult evaluateYearlyScheme(Id contactId, Id yearlySchemeId) {
        if (contactId == null) {
            throw new AuraHandledException(
                'Contact is required for eligibility check. Provide a Contact Id or link one to the user.'
            );
        }

        if (yearlySchemeId == null) {
            throw new AuraHandledException('Yearly Scheme is required.');
        }

        try {
            Map<Id, EligibilityEvaluationResult> resultsBySchemeId = evaluateYearlySchemes(
                contactId,
                new Set<Id>{ yearlySchemeId }
            );
            EligibilityEvaluationResult evaluationResult = resultsBySchemeId.get(yearlySchemeId);

            if (evaluationResult == null) {
                throw new AuraHandledException('Unable to evaluate eligibility for this scheme.');
            }

            return evaluationResult;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (EligibilityEvaluationException evaluationException) {
            throw new AuraHandledException(evaluationException.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException('Eligibility check failed: ' + ex.getMessage());
        }
    }

    public static Map<Id, EligibilityEvaluationResult> evaluateYearlySchemes(
        Id contactId,
        Set<Id> yearlySchemeIds
    ) {
        Map<Id, EligibilityEvaluationResult> resultsBySchemeId = new Map<Id, EligibilityEvaluationResult>();

        if (contactId == null || yearlySchemeIds == null || yearlySchemeIds.isEmpty()) {
            return resultsBySchemeId;
        }

        for (Id yearlySchemeId : yearlySchemeIds) {
            resultsBySchemeId.put(yearlySchemeId, createUnconfiguredResult());
        }

        List<Eligibility_Criteria__c> criteriaRecords = [
            SELECT
                Id,
                Name,
                Sequence__c,
                Validation_Type__c,
                Eligibility_Type__c,
                Formula__c,
                Pass_Message__c,
                Fail_Message__c,
                Yearly_Scheme__c,
                (
                    SELECT
                        Id,
                        Sequence__c,
                        Object_API_Name__c,
                        Field_API_Name__c,
                        Operator__c,
                        Value__c,
                        Logical_Operator__c
                    FROM Eligibility_Conditions__r
                    ORDER BY Sequence__c ASC
                )
            FROM Eligibility_Criteria__c
            WHERE Yearly_Scheme__c IN :yearlySchemeIds
            AND Is_Active__c = true
            ORDER BY Sequence__c ASC NULLS LAST, CreatedDate ASC
        ];

        if (criteriaRecords.isEmpty()) {
            return resultsBySchemeId;
        }

        Map<Id, List<Eligibility_Criteria__c>> criteriaBySchemeId = new Map<Id, List<Eligibility_Criteria__c>>();

        for (Eligibility_Criteria__c criteriaRecord : criteriaRecords) {
            if (!criteriaBySchemeId.containsKey(criteriaRecord.Yearly_Scheme__c)) {
                criteriaBySchemeId.put(
                    criteriaRecord.Yearly_Scheme__c,
                    new List<Eligibility_Criteria__c>()
                );
            }

            criteriaBySchemeId.get(criteriaRecord.Yearly_Scheme__c).add(criteriaRecord);
        }

        Map<String, Set<String>> fieldsByObject = gatherFieldsByObject(criteriaRecords);
        String contactObjectApiName = resolveObjectApiName(contactId);
        String schemeObjectApiName = resolveObjectApiName(
            yearlySchemeIds.isEmpty() ? null : new List<Id>(yearlySchemeIds)[0]
        );

        addRelatedLookupFields(fieldsByObject, schemeObjectApiName, contactObjectApiName);

        SObject contactRecord = queryRecordById(
            contactId,
            contactObjectApiName,
            fieldsByObject.get(contactObjectApiName)
        );
        Map<Id, SObject> schemeRecordsById = queryRecordsByIds(
            yearlySchemeIds,
            schemeObjectApiName,
            fieldsByObject.get(schemeObjectApiName)
        );

        Map<String, RelatedObjectContext> relatedObjectContexts = resolveRelatedObjectContexts(
            fieldsByObject,
            schemeRecordsById,
            contactRecord,
            schemeObjectApiName,
            contactObjectApiName
        );

        for (Id yearlySchemeId : yearlySchemeIds) {
            List<Eligibility_Criteria__c> schemeCriteria = criteriaBySchemeId.get(yearlySchemeId);

            if (schemeCriteria != null && !schemeCriteria.isEmpty()) {
                Map<String, SObject> recordsByObject = new Map<String, SObject>();
                recordsByObject.put(contactObjectApiName, contactRecord);

                if (schemeRecordsById.containsKey(yearlySchemeId)) {
                    SObject schemeRecord = schemeRecordsById.get(yearlySchemeId);
                    recordsByObject.put(schemeObjectApiName, schemeRecord);

                    for (String relatedObjectApiName : relatedObjectContexts.keySet()) {
                        RelatedObjectContext relatedContext = relatedObjectContexts.get(relatedObjectApiName);
                        Id parentId = (Id) schemeRecord.get(relatedContext.lookupFieldApiName);

                        if (relatedContext.parentRecordsById.containsKey(parentId)) {
                            recordsByObject.put(
                                relatedObjectApiName,
                                relatedContext.parentRecordsById.get(parentId)
                            );
                        }
                    }
                }

                resultsBySchemeId.put(
                    yearlySchemeId,
                    evaluateCriteriaRecords(schemeCriteria, recordsByObject)
                );
            }
        }

        return resultsBySchemeId;
    }

    private static EligibilityEvaluationResult evaluateCriteriaRecords(
        List<Eligibility_Criteria__c> criteriaRecords,
        Map<String, SObject> recordsByObject
    ) {
        EligibilityEvaluationResult evaluationResult = new EligibilityEvaluationResult();
        evaluationResult.criteriaResults = new List<CriteriaResult>();
        evaluationResult.isEligible = true;
        evaluationResult.hasConfiguredCriteria = true;
        List<String> failureMessages = new List<String>();

        for (Eligibility_Criteria__c criteriaRecord : criteriaRecords) {
            CriteriaResult criteriaResult = evaluateCriteria(criteriaRecord, recordsByObject);
            evaluationResult.criteriaResults.add(criteriaResult);

            if (!criteriaResult.passed && isHardStop(criteriaRecord.Validation_Type__c)) {
                evaluationResult.isEligible = false;
                failureMessages.add(criteriaResult.message);
            }
        }

        evaluationResult.canApply = evaluationResult.isEligible;
        evaluationResult.overallMessage = evaluationResult.isEligible
            ? 'You are eligible to apply for this scheme.'
            : String.join(failureMessages, ' ');

        return evaluationResult;
    }

    public static EligibilityEvaluationResult evaluateYearlyScheme(Contact contactRecord, Id yearlySchemeId) {
        return evaluateYearlyScheme(contactRecord.Id, yearlySchemeId);
    }

    private static EligibilityEvaluationResult createUnconfiguredResult() {
        EligibilityEvaluationResult evaluationResult = new EligibilityEvaluationResult();
        evaluationResult.isEligible = true;
        evaluationResult.canApply = true;
        evaluationResult.hasConfiguredCriteria = false;
        evaluationResult.overallMessage = 'No eligibility criteria configured for this scheme.';
        evaluationResult.criteriaResults = new List<CriteriaResult>();
        return evaluationResult;
    }

    private static CriteriaResult evaluateCriteria(
        Eligibility_Criteria__c criteriaRecord,
        Map<String, SObject> recordsByObject
    ) {
        CriteriaResult criteriaResult = new CriteriaResult();
        criteriaResult.criteriaId = criteriaRecord.Id;
        criteriaResult.criteriaLabel = String.isNotBlank(criteriaRecord.Name)
            ? criteriaRecord.Name
            : 'Eligibility Criteria';
        criteriaResult.formula = criteriaRecord.Formula__c;
        criteriaResult.validationType = criteriaRecord.Validation_Type__c;
        criteriaResult.eligibilityType = criteriaRecord.Eligibility_Type__c;

        List<EligibilityFormulaParser.ParsedCondition> conditions = buildConditions(criteriaRecord);

        if (conditions.isEmpty()) {
            criteriaResult.passed = false;
            criteriaResult.status = 'Failed';
            criteriaResult.message = 'No valid conditions found for ' + criteriaResult.criteriaLabel + '.';
            return criteriaResult;
        }

        Boolean combinedResult = null;

        /*
        for (EligibilityFormulaParser.ParsedCondition condition : conditions) {
            Boolean conditionPassed = evaluateCondition(condition, recordsByObject);

            if (combinedResult == null) {
                combinedResult = conditionPassed;
                continue;
            }

            if (condition.logicalOperator == 'OR') {
                combinedResult = combinedResult || conditionPassed;
            } else {
                combinedResult = combinedResult && conditionPassed;
            }
        }
        */

        for (Integer i = 0; i < conditions.size(); i++) {
            Boolean conditionPassed = evaluateCondition(conditions[i], recordsByObject);
        
            if (i == 0) {
                combinedResult = conditionPassed;
            } else {
                String op = conditions[i - 1].logicalOperator;
                if (op == 'OR') {
                    combinedResult = combinedResult || conditionPassed;
                } else {
                    combinedResult = combinedResult && conditionPassed;
                }
            }
        }

        criteriaResult.passed = combinedResult == true;
        criteriaResult.status = criteriaResult.passed ? 'Passed' : 'Failed';
        criteriaResult.message = criteriaResult.passed
            ? resolvePassMessage(criteriaRecord, criteriaResult.criteriaLabel)
            : resolveFailMessage(criteriaRecord, criteriaResult.criteriaLabel, recordsByObject, conditions);

        return criteriaResult;
    }

    private static String resolvePassMessage(
        Eligibility_Criteria__c criteriaRecord,
        String criteriaLabel
    ) {
        if (String.isNotBlank(criteriaRecord.Pass_Message__c)) {
            return applyMessageTokens(
                criteriaRecord.Pass_Message__c,
                criteriaLabel,
                null,
                null,
                null,
                null
            );
        }

        return criteriaLabel + ' - Passed';
    }

    private static String resolveFailMessage(
        Eligibility_Criteria__c criteriaRecord,
        String criteriaLabel,
        Map<String, SObject> recordsByObject,
        List<EligibilityFormulaParser.ParsedCondition> conditions
    ) {
        String fieldLabel;
        String operatorToken;
        String expectedValue;
        String actualValue;

        for (EligibilityFormulaParser.ParsedCondition condition : conditions) {
            if (evaluateCondition(condition, recordsByObject)) {
                continue;
            }

            fieldLabel = getFieldLabel(condition.objectApiName, condition.fieldApiName);
            operatorToken = condition.operatorToken;
            expectedValue = condition.expectedValue;

            SObject targetRecord = recordsByObject.get(condition.objectApiName);
            Object fieldValue = targetRecord != null ? targetRecord.get(condition.fieldApiName) : null;
            actualValue = formatValue(fieldValue, condition.fieldApiName);
            break;
        }

        if (String.isNotBlank(criteriaRecord.Fail_Message__c)) {
            return applyMessageTokens(
                criteriaRecord.Fail_Message__c,
                criteriaLabel,
                fieldLabel,
                operatorToken,
                expectedValue,
                actualValue
            );
        }

        return buildFailureMessage(criteriaLabel, recordsByObject, conditions);
    }

    private static String applyMessageTokens(
        String template,
        String criteriaLabel,
        String fieldLabel,
        String operatorToken,
        String expectedValue,
        String actualValue
    ) {
        String resolvedMessage = template;
        resolvedMessage = resolvedMessage.replace('{label}', blankToEmpty(criteriaLabel));
        resolvedMessage = resolvedMessage.replace('{field}', blankToEmpty(fieldLabel));
        resolvedMessage = resolvedMessage.replace('{operator}', blankToEmpty(operatorToken));
        resolvedMessage = resolvedMessage.replace('{expected}', blankToEmpty(expectedValue));
        resolvedMessage = resolvedMessage.replace('{actual}', blankToEmpty(actualValue));
        return resolvedMessage;
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static List<EligibilityFormulaParser.ParsedCondition> buildConditions(
        Eligibility_Criteria__c criteriaRecord
    ) {
        if (criteriaRecord.Eligibility_Conditions__r != null && !criteriaRecord.Eligibility_Conditions__r.isEmpty()) {
            List<EligibilityFormulaParser.ParsedCondition> parsedConditions =
                new List<EligibilityFormulaParser.ParsedCondition>();

            for (Eligibility_Condition__c conditionRecord : criteriaRecord.Eligibility_Conditions__r) {
                EligibilityFormulaParser.ParsedCondition parsedCondition =
                    new EligibilityFormulaParser.ParsedCondition();
                parsedCondition.sequence = conditionRecord.Sequence__c != null
                    ? Integer.valueOf(conditionRecord.Sequence__c)
                    : parsedConditions.size() + 1;
                parsedCondition.objectApiName = conditionRecord.Object_API_Name__c;
                parsedCondition.fieldApiName = conditionRecord.Field_API_Name__c;
                parsedCondition.operatorToken = conditionRecord.Operator__c;
                parsedCondition.expectedValue = conditionRecord.Value__c;
                parsedCondition.logicalOperator = conditionRecord.Logical_Operator__c;
                parsedConditions.add(parsedCondition);
            }

            return parsedConditions;
        }

        return EligibilityFormulaParser.parse(criteriaRecord.Formula__c);
    }

    private static Boolean evaluateCondition(
        EligibilityFormulaParser.ParsedCondition condition,
        Map<String, SObject> recordsByObject
    ) {
        if (String.isBlank(condition.objectApiName) || String.isBlank(condition.fieldApiName)) {
            return false;
        }

        SObject targetRecord = recordsByObject.get(condition.objectApiName);
        if (targetRecord == null) {
            return false;
        }

        if (!isAllowedField(condition.objectApiName, condition.fieldApiName)) {
            return false;
        }

        Object actualValue = targetRecord.get(condition.fieldApiName);
        return compareValues(actualValue, condition.operatorToken, condition.expectedValue, condition.fieldApiName);
    }

    private static Boolean compareValues(
        Object actualValue,
        String operatorToken,
        String expectedValue,
        String fieldApiName
    ) {
        if (operatorToken == '=' || operatorToken == '!=') {
            String actualAsString = formatValue(actualValue, fieldApiName);
            Boolean isEqual = actualAsString.equalsIgnoreCase(String.valueOf(expectedValue).trim());

            if (operatorToken == '=') {
                return isEqual;
            }

            return !isEqual;
        }

        Decimal actualNumber = toDecimal(actualValue);
        Decimal expectedNumber = toDecimal(expectedValue);

        if (actualNumber == null || expectedNumber == null) {
            return false;
        }

        if (operatorToken == '>') {
            return actualNumber > expectedNumber;
        }
        if (operatorToken == '<') {
            return actualNumber < expectedNumber;
        }
        if (operatorToken == '>=') {
            return actualNumber >= expectedNumber;
        }
        if (operatorToken == '<=') {
            return actualNumber <= expectedNumber;
        }
        if (operatorToken == '+') {
            return actualNumber + expectedNumber >= 0;
        }
        if (operatorToken == '-') {
            return actualNumber - expectedNumber >= 0;
        }

        return false;
    }

    private static String buildFailureMessage(
        String criteriaLabel,
        Map<String, SObject> recordsByObject,
        List<EligibilityFormulaParser.ParsedCondition> conditions
    ) {
        List<String> detailMessages = new List<String>();

        for (EligibilityFormulaParser.ParsedCondition condition : conditions) {
            if (evaluateCondition(condition, recordsByObject)) {
                continue;
            }

            SObject targetRecord = recordsByObject.get(condition.objectApiName);
            Object fieldValue = targetRecord != null ? targetRecord.get(condition.fieldApiName) : null;
            String actualValue = formatValue(fieldValue, condition.fieldApiName);
            detailMessages.add(
                getFieldLabel(condition.objectApiName, condition.fieldApiName) +
                ' required ' +
                condition.operatorToken +
                ' ' +
                condition.expectedValue +
                '. Your value: ' +
                actualValue +
                '.'
            );
        }

        if (detailMessages.isEmpty()) {
            return criteriaLabel + ' - Failed';
        }

        return criteriaLabel + ' - Failed. ' + String.join(detailMessages, ' ');
    }

    private static Map<String, Set<String>> gatherFieldsByObject(List<Eligibility_Criteria__c> criteriaRecords) {
        Map<String, Set<String>> fieldsByObject = new Map<String, Set<String>>();

        for (Eligibility_Criteria__c criteriaRecord : criteriaRecords) {
            for (EligibilityFormulaParser.ParsedCondition condition : buildConditions(criteriaRecord)) {
                if (String.isBlank(condition.objectApiName) || String.isBlank(condition.fieldApiName)) {
                    continue;
                }

                if (!isAllowedField(condition.objectApiName, condition.fieldApiName)) {
                    continue;
                }

                if (!fieldsByObject.containsKey(condition.objectApiName)) {
                    fieldsByObject.put(condition.objectApiName, new Set<String>{ 'Id', 'Name' });
                }

                fieldsByObject.get(condition.objectApiName).add(condition.fieldApiName);
            }
        }

        return fieldsByObject;
    }

    private static String resolveObjectApiName(Id recordId) {
        if (recordId == null) {
            return null;
        }

        return recordId.getSobjectType().getDescribe().getName();
    }

    private static SObject queryRecordById(Id recordId, String objectApiName, Set<String> fieldApiNames) {
        Set<String> fieldsToQuery = new Set<String>{ 'Id', 'Name' };
        if (fieldApiNames != null) {
            fieldsToQuery.addAll(fieldApiNames);
        }

        String query =
            'SELECT ' +
            String.join(new List<String>(fieldsToQuery), ', ') +
            ' FROM ' +
            objectApiName +
            ' WHERE Id = :recordId LIMIT 1';

        List<SObject> records = Database.query(query);

        if (records.isEmpty()) {
            throw new EligibilityEvaluationException(
                objectApiName + ' record not found or not accessible: ' + recordId
            );
        }

        return records[0];
    }

    private static Map<Id, SObject> queryRecordsByIds(
        Set<Id> recordIds,
        String objectApiName,
        Set<String> fieldApiNames
    ) {
        Map<Id, SObject> recordsById = new Map<Id, SObject>();

        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return recordsById;
        }

        Set<String> fieldsToQuery = new Set<String>{ 'Id', 'Name' };
        if (fieldApiNames != null) {
            fieldsToQuery.addAll(fieldApiNames);
        }

        String query =
            'SELECT ' +
            String.join(new List<String>(fieldsToQuery), ', ') +
            ' FROM ' +
            objectApiName +
            ' WHERE Id IN :recordIds';

        for (SObject record : Database.query(query)) {
            recordsById.put(record.Id, record);
        }

        return recordsById;
    }

    private class RelatedObjectContext {
        String lookupFieldApiName;
        Map<Id, SObject> parentRecordsById;
    }

    private static Map<String, RelatedObjectContext> resolveRelatedObjectContexts(
        Map<String, Set<String>> fieldsByObject,
        Map<Id, SObject> schemeRecordsById,
        SObject contactRecord,
        String schemeObjectApiName,
        String contactObjectApiName
    ) {
        Map<String, RelatedObjectContext> result = new Map<String, RelatedObjectContext>();
        Set<String> relatedObjectApiNames = new Set<String>(fieldsByObject.keySet());
        relatedObjectApiNames.remove(schemeObjectApiName);
        relatedObjectApiNames.remove(contactObjectApiName);

        for (String objectApiName : relatedObjectApiNames) {
            String lookupField = findLookupField(schemeObjectApiName, objectApiName);

            if (String.isNotBlank(lookupField) && !schemeRecordsById.isEmpty()) {
                Set<Id> parentIds = new Set<Id>();

                for (SObject schemeRecord : schemeRecordsById.values()) {
                    Id parentId = (Id) schemeRecord.get(lookupField);
                    if (parentId != null) {
                        parentIds.add(parentId);
                    }
                }

                if (!parentIds.isEmpty()) {
                    Map<Id, SObject> parentRecordsById = queryRecordsByIds(
                        parentIds,
                        objectApiName,
                        fieldsByObject.get(objectApiName)
                    );

                    if (!parentRecordsById.isEmpty()) {
                        RelatedObjectContext context = new RelatedObjectContext();
                        context.lookupFieldApiName = lookupField;
                        context.parentRecordsById = parentRecordsById;
                        result.put(objectApiName, context);
                        continue;
                    }
                }
            }

            lookupField = findLookupField(contactObjectApiName, objectApiName);

            if (String.isNotBlank(lookupField) && contactRecord != null) {
                Id parentId = (Id) contactRecord.get(lookupField);

                if (parentId != null) {
                    try {
                        SObject parentRecord = queryRecordById(
                            parentId,
                            objectApiName,
                            fieldsByObject.get(objectApiName)
                        );

                        RelatedObjectContext context = new RelatedObjectContext();
                        context.lookupFieldApiName = lookupField;
                        context.parentRecordsById = new Map<Id, SObject>{
                            parentId => parentRecord
                        };
                        result.put(objectApiName, context);
                        continue;
                    } catch (Exception ex) {
                        // Parent record not accessible; leave it out of the context.
                    }
                }
            }
        }

        return result;
    }

    private static void addRelatedLookupFields(
        Map<String, Set<String>> fieldsByObject,
        String schemeObjectApiName,
        String contactObjectApiName
    ) {
        if (fieldsByObject == null) {
            return;
        }

        if (!fieldsByObject.containsKey(schemeObjectApiName)) {
            fieldsByObject.put(schemeObjectApiName, new Set<String>{ 'Id', 'Name' });
        }

        if (!fieldsByObject.containsKey(contactObjectApiName)) {
            fieldsByObject.put(contactObjectApiName, new Set<String>{ 'Id', 'Name' });
        }

        Set<String> targetObjects = new Set<String>(fieldsByObject.keySet());
        targetObjects.remove(schemeObjectApiName);
        targetObjects.remove(contactObjectApiName);

        Set<String> schemeFields = fieldsByObject.get(schemeObjectApiName);
        Set<String> contactFields = fieldsByObject.get(contactObjectApiName);

        for (String targetObject : targetObjects) {
            String lookupField = findLookupField(schemeObjectApiName, targetObject);

            if (String.isNotBlank(lookupField)) {
                schemeFields.add(lookupField);
                continue;
            }

            lookupField = findLookupField(contactObjectApiName, targetObject);

            if (String.isNotBlank(lookupField)) {
                contactFields.add(lookupField);
            }
        }
    }

    private static String findLookupField(String sourceObjectApiName, String targetObjectApiName) {
        if (String.isBlank(sourceObjectApiName) || String.isBlank(targetObjectApiName)) {
            return null;
        }

        Schema.SObjectType sourceType = findSObjectType(sourceObjectApiName);
        if (sourceType == null) {
            return null;
        }

        for (Schema.SObjectField fieldToken : sourceType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();

            if (!fieldDescribe.isAccessible()) {
                continue;
            }

            for (Schema.SObjectType referenceType : fieldDescribe.getReferenceTo()) {
                if (referenceType.getDescribe().getName().equalsIgnoreCase(targetObjectApiName)) {
                    return fieldDescribe.getName();
                }
            }
        }

        return null;
    }

    private static Schema.SObjectType findSObjectType(String objectApiName) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        if (globalDescribe.containsKey(objectApiName)) {
            return globalDescribe.get(objectApiName);
        }

        String lowerName = objectApiName.toLowerCase();
        for (String key : globalDescribe.keySet()) {
            if (key != null && key.toLowerCase() == lowerName) {
                return globalDescribe.get(key);
            }
        }

        return null;
    }

    private static Boolean isAllowedField(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return false;
        }

        Schema.SObjectType objectType = findSObjectType(objectApiName);
        if (objectType == null) {
            return false;
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        return fieldMap.containsKey(fieldApiName.toLowerCase());
    }

    private static String getFieldLabel(String objectApiName, String fieldApiName) {
        Schema.SObjectType objectType = findSObjectType(objectApiName);
        if (objectType == null) {
            return fieldApiName;
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        Schema.SObjectField fieldToken = fieldMap.get(fieldApiName.toLowerCase());

        if (fieldToken == null) {
            return fieldApiName;
        }

        return fieldToken.getDescribe().getLabel();
    }

    private static String formatValue(Object fieldValue, String fieldApiName) {
        if (fieldValue == null) {
            return 'not provided';
        }

        if (fieldValue instanceof Boolean) {
            return String.valueOf(fieldValue);
        }

        if (fieldValue instanceof Date) {
            return String.valueOf((Date) fieldValue);
        }

        if (fieldValue instanceof Datetime) {
            return String.valueOf((Datetime) fieldValue);
        }

        return String.valueOf(fieldValue);
    }

    private static Decimal toDecimal(Object fieldValue) {
        if (fieldValue == null) {
            return null;
        }

        if (fieldValue instanceof Decimal) {
            return (Decimal) fieldValue;
        }

        if (fieldValue instanceof Integer) {
            return Decimal.valueOf((Integer) fieldValue);
        }

        if (fieldValue instanceof Long) {
            return Decimal.valueOf((Long) fieldValue);
        }

        if (fieldValue instanceof Double) {
            return Decimal.valueOf((Double) fieldValue);
        }

        if (fieldValue instanceof Boolean) {
            return (Boolean) fieldValue ? 1 : 0;
        }

        String stringValue = String.valueOf(fieldValue).trim();
        if (String.isBlank(stringValue)) {
            return null;
        }

        try {
            return Decimal.valueOf(stringValue);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean isHardStop(String validationType) {
        if (String.isBlank(validationType)) {
            return true;
        }

        String normalizedValidationType = validationType.trim().toLowerCase();
        return normalizedValidationType.contains('hard') || normalizedValidationType.contains('stop');
    }

    private static Id resolveCurrentUserContactId() {
        List<User> users = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        return users.isEmpty() ? null : users[0].ContactId;
    }

    public class EligibilityEvaluationResult {
        @AuraEnabled
        public Boolean isEligible;
        @AuraEnabled
        public Boolean canApply;
        @AuraEnabled
        public Boolean hasConfiguredCriteria;
        @AuraEnabled
        public String overallMessage;
        @AuraEnabled
        public List<CriteriaResult> criteriaResults;
    }

    public class CriteriaResult {
        @AuraEnabled
        public String criteriaId;
        @AuraEnabled
        public String criteriaLabel;
        @AuraEnabled
        public Boolean passed;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public String formula;
        @AuraEnabled
        public String validationType;
        @AuraEnabled
        public String eligibilityType;
    }

    public class EligibilityEvaluationException extends Exception {
    }
}