/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : YearlySchemeTriggerHandler
 * Author          : <YourName>
 * Created Date    : Jul 1, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 1, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 1, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class YearlySchemeTriggerHandler {

    public static void validateDuplicateYearScheme(List<Yearly_Schemes__c> newRecords) {

        Set<Id> yearIds = new Set<Id>();
        Set<Id> schemeIds = new Set<Id>();

        for (Yearly_Schemes__c ys : newRecords) {
            if (ys.Year__c != null) {
                yearIds.add(ys.Year__c);
            }
            if (ys.Scheme_Items__c != null) {
                schemeIds.add(ys.Scheme_Items__c);
            }
        }
        if (yearIds.isEmpty() || schemeIds.isEmpty()) {
            return;
        }

        List<Yearly_Schemes__c> existingRecords = [SELECT Id, Year__c, Scheme_Items__c FROM Yearly_Schemes__c 
													WHERE Year__c IN :yearIds AND Scheme_Items__c IN :schemeIds];

        Map<String, Id> existingMap = new Map<String, Id>();
        for (Yearly_Schemes__c record : existingRecords) {
            String key = record.Year__c + '-' + record.Scheme_Items__c;
            existingMap.put(key, record.Id);
        }

        Set<String> currentBatchKeys = new Set<String>();
        for (Yearly_Schemes__c ys : newRecords) {
            if (ys.Year__c == null || ys.Scheme_Items__c == null) {
                continue;
            }
            String key = ys.Year__c + '-' + ys.Scheme_Items__c;
            // Check duplicate within the same transaction
            if (currentBatchKeys.contains(key)) {
                //ys.addError('A Yearly Scheme already exists for the selected Year and Scheme.');
                continue;
            }
            currentBatchKeys.add(key);
            // Check duplicate against existing records
            if (existingMap.containsKey(key) && existingMap.get(key) != ys.Id) {
               // ys.addError('A Yearly Scheme already exists for the selected Year and Scheme.');
            }
        }
    }

    public static void updateProposalIds(Map<Id, Yearly_Schemes__c> newMap, Map<Id, Yearly_Schemes__c> oldMap){

        Set<Id> yearlySchemeIds = new Set<Id>();

        for(Id ysId : newMap.keySet()){

            Yearly_Schemes__c newRec = newMap.get(ysId);
            Yearly_Schemes__c oldRec = oldMap.get(ysId);

            if (
                newRec.Is_Active__c && oldRec.Is_Active__c &&
                newRec.Approval_Status__c == 'Approved' && oldRec.Approval_Status__c == 'Approved' &&
                oldRec.Application_Stages__c == 'Prelims' && newRec.Application_Stages__c == 'Full') {

                yearlySchemeIds.add(ysId);
            }
        }

        if(yearlySchemeIds.isEmpty()){
            return;
        }

        ProposalTriggerHandler.updateProposalIdsToFull(yearlySchemeIds);

    }
    public static void sendSchemeApprovalEmail(List<Yearly_Schemes__c> newSchemes) {
    
        if (newSchemes == null || newSchemes.isEmpty()) {
            return;
        }
    
        // Query Grant Manager
        List<User> grantManagers = [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true
            AND Profile.Name = 'System Administrator'
            AND Email != null
            AND Name LIKE '%ayush%'
            LIMIT 1
        ];
    
        if (grantManagers.isEmpty()) {
            return;
        }
    
        User grantManager = grantManagers[0];
    
        // Query Email Template
        List<EmailTemplate> templates = [
            SELECT Id, DeveloperName, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName = 'X2_Approve_Scheme_before_publishing'
            LIMIT 1
        ];
        Set<Id> schemeIds = new Map<Id, Yearly_Schemes__c>(newSchemes).keySet();

        Map<Id, Yearly_Schemes__c> schemeMap = new Map<Id, Yearly_Schemes__c>([
            SELECT Id, Scheme__c, CreatedDate, CreatedBy.Name, Scheme_Start_Date__c
            FROM Yearly_Schemes__c
            WHERE Id IN :schemeIds
        ]);
    
        if (templates.isEmpty()) {
            return;
        }
    
        EmailTemplate template = templates[0];
    
        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();
    
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
    
        for (Yearly_Schemes__c triggerScheme  : newSchemes) {
                Yearly_Schemes__c scheme = schemeMap.get(triggerScheme.Id);
    
            // Direct link to the Yearly Scheme record
            String reviewLink =
                baseUrl +
                '/lightning/r/Yearly_Schemes__c/' +
                scheme.Id +
                '/view';
    
            String schemeName = '';
            if (scheme.Scheme__c != null) {
                schemeName = scheme.Scheme__c;
            }
            System.debug('schemeName'+schemeName);
    
            String createdByName = '';
            if (scheme.CreatedBy != null) {
                createdByName = scheme.CreatedBy.Name;
            }
            System.debug('createdByName'+createdByName);
    
            // HTML Body
            String htmlBody = template.HtmlValue;
    
            if (htmlBody != null) {
                htmlBody = htmlBody
                    .replace('{{Grants_Manager_Name}}', grantManager.Name)
                    .replace('{{Scheme_Name}}', schemeName)
                    .replace('{{Created_By}}', createdByName)
                    .replace('{{Submission_Date}}', scheme.CreatedDate.format())
                    .replace('{{Proposed_Publish_Date}}',
                             scheme.Scheme_Start_Date__c != null
                                 ? scheme.Scheme_Start_Date__c.format()
                                 : '')
                    .replace('{{Review_Link}}', reviewLink);
            }
    
            // Plain Text Body
            String plainTextBody = template.Body;
    
            if (plainTextBody != null) {
                plainTextBody = plainTextBody
                    .replace('{{Grants_Manager_Name}}', grantManager.Name)
                    .replace('{{Scheme_Name}}', schemeName)
                    .replace('{{Created_By}}', createdByName)
                    .replace('{{Submission_Date}}', scheme.CreatedDate.format())
                    .replace('{{Proposed_Publish_Date}}',
                             scheme.Scheme_Start_Date__c != null
                                 ? scheme.Scheme_Start_Date__c.format()
                                 : '')
                    .replace('{{Review_Link}}', reviewLink);
            }
    
            Messaging.SingleEmailMessage email =
                new Messaging.SingleEmailMessage();
    
            email.setToAddresses(new String[] {
                grantManager.Email
            });
    
            email.setSubject(template.Subject);
            email.setHtmlBody(htmlBody);
            email.setPlainTextBody(plainTextBody);
            email.setSaveAsActivity(false);
    
            emails.add(email);
        }
    
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
	public static void sendSchemeDeactivationEmail( Map<Id, Yearly_Schemes__c> newMap, Map<Id, Yearly_Schemes__c> oldMap) {
        Set<Id> deactivatedSchemeIds = new Set<Id>();
        for (Yearly_Schemes__c scheme : newMap.values()) {
            Yearly_Schemes__c oldScheme = oldMap.get(scheme.Id);
            if (oldScheme.Is_Active__c == true &&
                scheme.Is_Active__c == false) {
                deactivatedSchemeIds.add(scheme.Id);
            }
        }
    
        if (deactivatedSchemeIds.isEmpty()) {
            return;
        }
    
        // Query deactivated schemes with required fields
        List<Yearly_Schemes__c> schemes = [
            SELECT Id,
                   Scheme__c,
                   Is_Active__c,
                   Deactivation_Reason__c,
                   LastModifiedDate,
                   LastModifiedBy.Name
            FROM Yearly_Schemes__c
            WHERE Id IN :deactivatedSchemeIds
        ];
    
        // Query Email Template
        List<EmailTemplate> templates = [
            SELECT Id, DeveloperName, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName = 'X3_Inform_interanl_users'
            LIMIT 1
        ];
    
        if (templates.isEmpty()) {
            return;
        }
    
        EmailTemplate template = templates[0];
    
        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();
    
        // TODO: Replace with the actual users/recipients
        List<User> recipients = [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true
            AND Profile.Name = 'System Administrator'
            AND Email != null
            AND Name LIKE '%ayush%'
        ];
    
        if (recipients.isEmpty()) {
            return;
        }
    
        String recipientEmail = recipients[0].Email;
    
        for (Yearly_Schemes__c scheme : schemes) {
    
            String schemeName = scheme.Scheme__c != null
                ? scheme.Scheme__c
                : '';
    
            String deactivatedBy = scheme.LastModifiedBy != null
                ? scheme.LastModifiedBy.Name
                : '';
    
            String deactivationDate = scheme.LastModifiedDate != null
                ? scheme.LastModifiedDate.format()
                : '';
    
            String deactivationReason = scheme.Deactivation_Reason__c != null
                ? scheme.Deactivation_Reason__c
                : '';
    
            // HTML body
            String htmlBody = template.HtmlValue;
    
            if (htmlBody != null) {
                htmlBody = htmlBody
                    .replace('{Scheme_Name}', schemeName)

                    .replace('{Deactivation_Date}', deactivationDate)
                    .replace('{Deactivation_Reason}', deactivationReason);
            }
    
            // Plain text body
            String plainTextBody = template.Body;
    
            if (plainTextBody != null) {
                plainTextBody = plainTextBody
                    .replace('{Scheme_Name}', schemeName)
                    .replace('{Deactivated_By}', deactivatedBy)
                    .replace('{Deactivation_Date}', deactivationDate)
                    .replace('{Deactivation_Reason}', deactivationReason);
            }
    
            Messaging.SingleEmailMessage email =
                new Messaging.SingleEmailMessage();
    
            email.setToAddresses(new String[] {
                recipientEmail
            });
    
            email.setSubject(template.Subject);
            email.setHtmlBody(htmlBody);
            email.setPlainTextBody(plainTextBody);
            email.setSaveAsActivity(false);
    
            emails.add(email);
        }
    
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
}