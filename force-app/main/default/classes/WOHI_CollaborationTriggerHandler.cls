public without sharing class WOHI_CollaborationTriggerHandler {

    private static final String WOHI_REACT_APP_URL;

    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        WOHI_REACT_APP_URL = reactBaseUrl + 'wohi';
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

            // On insert, oldMap is null - send whenever the checkbox is true on creation.
            // On update, only send when the checkbox flips from false/null to true.
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
        Map<String, Object> payload = new Map<String, Object>{ 'wohiCollabId' => wc.Id, 'type' => wc.Type__c };
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode( Blob.valueOf(jsonPayload) );
        String urlSafePayload = EncodingUtil.urlEncode( base64Payload, 'UTF-8' );

        return WOHI_REACT_APP_URL + '?data=' + urlSafePayload;
    }
}









/*public without sharing class WOHI_CollaborationTriggerHandler {

    private static final String WOHI_REACT_APP_URL;

    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        WOHI_REACT_APP_URL = reactBaseUrl + 'wohi';
    }
    public static void sendInvitationEmails( List<WOHI_Collaboration__c> newRecords ) {
        List<Id> collaborationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();
        for (WOHI_Collaboration__c wc : newRecords) {
            if (String.isBlank(wc.Email__c)) {
                continue;
            }
            String invitationLink =   buildInvitationLink(wc);
            collaborationIds.add(wc.Id);
            invitationLinks.put(wc.Id,invitationLink);
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
        Map<String, Object> payload =  new Map<String, Object>{ 'wohiCollabId' => wc.Id, 'type' => wc.Type__c };
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode( Blob.valueOf(jsonPayload) );
        String urlSafePayload = EncodingUtil.urlEncode( base64Payload, 'UTF-8' );

        return WOHI_REACT_APP_URL + '?data=' + urlSafePayload;
    }
}*/