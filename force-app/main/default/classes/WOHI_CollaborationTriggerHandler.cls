public without sharing class WOHI_CollaborationTriggerHandler {

    private static final String REACT_BASE_URL;

    private static final String TYPE_WOHI = 'WOHI';
    private static final String TYPE_COLLABORATOR = 'Collaborator';

    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String baseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(baseUrl) && !baseUrl.endsWith('/')) {
            baseUrl += '/';
        }
        REACT_BASE_URL = baseUrl;
    }

    // true when Re_Notify_Count__c went up on this update (null treated as 0)
    private static Boolean isReNotified(WOHI_Collaboration__c wc, Map<Id, WOHI_Collaboration__c> oldMap) {
        if (oldMap == null) {
            return false;
        }
        WOHI_Collaboration__c oldWc = oldMap.get(wc.Id);
        if (oldWc == null) {
            return false;
        }
        Decimal newCount = wc.Re_Notify_Count__c == null ? 0 : wc.Re_Notify_Count__c;
        Decimal oldCount = oldWc.Re_Notify_Count__c == null ? 0 : oldWc.Re_Notify_Count__c;
        return newCount > oldCount;
    }

    // Notify_through_Email__c: WOHI_Collaboration_Invitation
    // Send when: flag is true AND (insert OR flag just flipped to true OR Re_Notify_Count__c increased)
    public static void sendInvitationEmails( List<WOHI_Collaboration__c> newRecords, Map<Id, WOHI_Collaboration__c> oldMap ) {
        List<Id> collaborationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();

        for (WOHI_Collaboration__c wc : newRecords) {
            if (String.isBlank(wc.Email__c)) {
                continue;
            }
            if (wc.Notify_through_Email__c != true) {
                continue;
            }

            Boolean shouldSend = true; // insert case
            if (oldMap != null) {
                WOHI_Collaboration__c oldWc = oldMap.get(wc.Id);
                Boolean flipped  = oldWc == null || oldWc.Notify_through_Email__c != true;
                Boolean reNotify = isReNotified(wc, oldMap);
                shouldSend = flipped || reNotify;
            }

            if (shouldSend) {
                collaborationIds.add(wc.Id);
                invitationLinks.put(wc.Id, buildInvitationLink(wc));
            }
        }

        if (collaborationIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'WOHI_COLLABORATION',
                collaborationIds,
                invitationLinks,
                'WOHI_Collaboration_Invitation'
            )
        );
    }

    private static String buildInvitationLink( WOHI_Collaboration__c wc) {
        String WOHI_REACT_APP_URL = REACT_BASE_URL + getAppPathForType(wc.Type__c);

        Map<String, Object> payload = new Map<String, Object>{ 'wohiCollabId' => wc.Id, 'type' => wc.Type__c };
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode( Blob.valueOf(jsonPayload) );
        String urlSafePayload = EncodingUtil.urlEncode( base64Payload, 'UTF-8' );

        return WOHI_REACT_APP_URL + '?data=' + urlSafePayload;
    }

    private static String getAppPathForType(String typeValue) {
        if (TYPE_COLLABORATOR.equalsIgnoreCase(typeValue)) {
            return 'collaborator';
        }
        // Default to WOHI for the 'WOHI' picklist value and any unexpected value
        return 'wohi';
    }

    // Notifies the applicant (via the parent Applicant_Proposal_Association__c's Contact)
    // once a WOHI/Collaborator entry's document status is marked Submitted - fires on
    // insert if already true, or on update the moment it flips from not-true to true,
    // same guard pattern as sendInvitationEmails above so it never re-fires on later edits.
    public static void notifyApplicantOnDocumentSubmission(List<WOHI_Collaboration__c> newRecords, Map<Id, WOHI_Collaboration__c> oldMap) {
        Set<Id> justSubmittedIds = new Set<Id>();

        for (WOHI_Collaboration__c wc : newRecords) {
            if (wc.Wohi_User_Document_Status__c != true) {
                continue;
            }
            if (oldMap != null) {
                WOHI_Collaboration__c oldWc = oldMap.get(wc.Id);
                Boolean wasSubmitted = oldWc != null && oldWc.Wohi_User_Document_Status__c == true;
                if (wasSubmitted) {
                    continue;
                }
            }
            justSubmittedIds.add(wc.Id);
        }

        if (justSubmittedIds.isEmpty()) {
            return;
        }

        List<Notification__c> notificationsToInsert = new List<Notification__c>();
        for (WOHI_Collaboration__c wc : [
            SELECT Id, Type__c, Title__c, FirstName__c, Last_Name__c,
                   Applicant_Proposal_Association__r.Contact__c
            FROM WOHI_Collaboration__c
            WHERE Id IN :justSubmittedIds
        ]) {
            if (wc.Applicant_Proposal_Association__r == null || wc.Applicant_Proposal_Association__r.Contact__c == null) {
                continue;
            }
            String title = String.isBlank(wc.Title__c) ? '' : wc.Title__c + ' ';
            String firstName = String.isBlank(wc.FirstName__c) ? '' : wc.FirstName__c + ' ';
            String lastName = String.isBlank(wc.Last_Name__c) ? '' : wc.Last_Name__c;
            String fullName = (title + firstName + lastName).trim();
            String type = String.isBlank(wc.Type__c) ? 'WOHI' : wc.Type__c;

            Notification__c notif = new Notification__c();
            notif.Contact__c = wc.Applicant_Proposal_Association__r.Contact__c;
            notif.Title__c = 'Document Submitted';
            notif.Description__c = 'Your ' + type + ' (' + fullName + ') has submitted the required document.';
            notif.Expiry_Date__c = Date.today().addDays(10);
            notificationsToInsert.add(notif);
        }

        if (!notificationsToInsert.isEmpty()) {
            insert notificationsToInsert;
        }
    }
}









/*
public without sharing class WOHI_CollaborationTriggerHandler {

    private static final String REACT_BASE_URL;

    private static final String TYPE_WOHI = 'WOHI';
    private static final String TYPE_COLLABORATOR = 'Collaborator';

    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String baseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(baseUrl) && !baseUrl.endsWith('/')) {
            baseUrl += '/';
        }
        REACT_BASE_URL = baseUrl;
    }

    public static void sendInvitationEmails( List<WOHI_Collaboration__c> newRecords, Map<Id, WOHI_Collaboration__c> oldMap ) {
        List<Id> collaborationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();

        for (WOHI_Collaboration__c wc : newRecords) {
            if (String.isBlank(wc.Email__c)) {
                continue;
            }
            if (wc.Notify_through_Email__c != true) {
                continue;
            }

            if (oldMap != null) {
                WOHI_Collaboration__c oldWc = oldMap.get(wc.Id);
                Boolean wasNotify = oldWc != null && oldWc.Notify_through_Email__c == true;
                if (wasNotify) {
                    continue;
                }
            }

            String invitationLink = buildInvitationLink(wc);
            collaborationIds.add(wc.Id);
            invitationLinks.put(wc.Id, invitationLink);
        }

        if (collaborationIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'WOHI_COLLABORATION',
                collaborationIds,
                invitationLinks,
                'WOHI_Collaboration_Invitation'
            )
        );
    }

    private static String buildInvitationLink( WOHI_Collaboration__c wc) {
        String WOHI_REACT_APP_URL = REACT_BASE_URL + getAppPathForType(wc.Type__c);

        Map<String, Object> payload = new Map<String, Object>{ 'wohiCollabId' => wc.Id, 'type' => wc.Type__c };
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode( Blob.valueOf(jsonPayload) );
        String urlSafePayload = EncodingUtil.urlEncode( base64Payload, 'UTF-8' );

        return WOHI_REACT_APP_URL + '?data=' + urlSafePayload;
    }

    private static String getAppPathForType(String typeValue) {
        if (TYPE_COLLABORATOR.equalsIgnoreCase(typeValue)) {
            return 'collaborator';
        }
        // Default to WOHI for the 'WOHI' picklist value and any unexpected value
        return 'wohi';
    }

    // Notifies the applicant (via the parent Applicant_Proposal_Association__c's Contact)
    // once a WOHI/Collaborator entry's document status is marked Submitted - fires on
    // insert if already true, or on update the moment it flips from not-true to true,
    // same guard pattern as sendInvitationEmails above so it never re-fires on later edits.
    public static void notifyApplicantOnDocumentSubmission(List<WOHI_Collaboration__c> newRecords, Map<Id, WOHI_Collaboration__c> oldMap) {
        Set<Id> justSubmittedIds = new Set<Id>();

        for (WOHI_Collaboration__c wc : newRecords) {
            if (wc.Wohi_User_Document_Status__c != true) {
                continue;
            }
            if (oldMap != null) {
                WOHI_Collaboration__c oldWc = oldMap.get(wc.Id);
                Boolean wasSubmitted = oldWc != null && oldWc.Wohi_User_Document_Status__c == true;
                if (wasSubmitted) {
                    continue;
                }
            }
            justSubmittedIds.add(wc.Id);
        }

        if (justSubmittedIds.isEmpty()) {
            return;
        }

        List<Notification__c> notificationsToInsert = new List<Notification__c>();
        for (WOHI_Collaboration__c wc : [
            SELECT Id, Type__c, Title__c, FirstName__c, Last_Name__c,
                   Applicant_Proposal_Association__r.Contact__c
            FROM WOHI_Collaboration__c
            WHERE Id IN :justSubmittedIds
        ]) {
            if (wc.Applicant_Proposal_Association__r == null || wc.Applicant_Proposal_Association__r.Contact__c == null) {
                continue;
            }
            String title = String.isBlank(wc.Title__c) ? '' : wc.Title__c + ' ';
            String firstName = String.isBlank(wc.FirstName__c) ? '' : wc.FirstName__c + ' ';
            String lastName = String.isBlank(wc.Last_Name__c) ? '' : wc.Last_Name__c;
            String fullName = (title + firstName + lastName).trim();
            String type = String.isBlank(wc.Type__c) ? 'WOHI' : wc.Type__c;

            Notification__c notif = new Notification__c();
            notif.Contact__c = wc.Applicant_Proposal_Association__r.Contact__c;
            notif.Title__c = 'Document Submitted';
            notif.Description__c = 'Your ' + type + ' (' + fullName + ') has submitted the required document.';
            notif.Expiry_Date__c = Date.today().addDays(10);
            notificationsToInsert.add(notif);
        }

        if (!notificationsToInsert.isEmpty()) {
            insert notificationsToInsert;
        }
    }
}
*/