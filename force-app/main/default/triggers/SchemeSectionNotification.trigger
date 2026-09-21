trigger SchemeSectionNotification on Scheme_Section__c (after update) {
    NotificationHandler.createNotificationForSchemeSection(Trigger.new, Trigger.oldMap);
    SchemeSectionTriggerHandler.handleAfterUpdateofReopen(Trigger.new, Trigger.oldMap);
}