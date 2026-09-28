public class additionalParticipantTriggerHandler {

    private static final String REFEREE_REACT_APP_URL;
    // Static initialization block
    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';

        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        REFEREE_REACT_APP_URL = reactBaseUrl + 'refree';
    }

    // ---- INSERT context: no old values to compare against ----
    public static void sendInvitationEmails(List<Additional_Partcipant__c> newRecords) {
        sendInvitationEmails(newRecords, null);
    }
    public static void sendInvitationContactEmails(List<Additional_Partcipant__c> newRecords) {
        sendInvitationContactEmails(newRecords, null);
    }
    public static void sendFullInvitationEmails(List<Additional_Partcipant__c> newRecords) {
        sendFullInvitationEmails(newRecords, null);
    }

    // ---- INSERT + UPDATE context ----
    // oldMap == null  => insert (send whenever Notify_through_Email__c is true)
    // oldMap != null  => update (send only when Notify_through_Email__c just
    //                    flipped from false/null to true, to avoid re-sending
    //                    on every subsequent edit of an already-notified row)
    public static void sendInvitationEmails(List<Additional_Partcipant__c> newRecords, Map<Id, Additional_Partcipant__c> oldMap) {
        List<Id> additionalParticipantIds = new List<Id>();
        List<Id> contactIds = new List<Id>();
        List<Id> proposalIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();

        for (Additional_Partcipant__c ap : newRecords) {
            if (String.isBlank(ap.Email__c)) {
                continue;
            }
            if((ap.Roles__c == 'Referee' || ap.Roles__c == 'Mentor') && ap.Proposal__c != null  && ap.Notify_through_Email__c == true){
                if (oldMap != null) {
                    Additional_Partcipant__c oldAp = oldMap.get(ap.Id);
                    Boolean wasTrue = oldAp != null && oldAp.Notify_through_Email__c == true;
                    if (wasTrue) {
                        continue; // already true before this update, don't resend
                    }
            	}
                 String invitationLink = buildInvitationLink(ap);
                additionalParticipantIds.add(ap.Id);
                invitationLinks.put(ap.Id, invitationLink);
            }
        }

        if (additionalParticipantIds.isEmpty()) {
            return;
        }
        if(!additionalParticipantIds.isEmpty()){
            System.enqueueJob(
                new EmailNotificationQueueable(
                    'REFEREE',
                    additionalParticipantIds,
                    invitationLinks,
                    'Refferre_Invitation'
                )
            );
        }
    }

    // ---- Referee_Added_For_Full__c flip context ----
    // oldMap == null  => insert (send whenever Referee_Added_For_Full__c is true on creation)
    // oldMap != null  => update (send only when Referee_Added_For_Full__c just flipped
    //                    from false/null to true, to avoid re-sending on every later edit)
    public static void sendFullInvitationEmails(List<Additional_Partcipant__c> newRecords, Map<Id, Additional_Partcipant__c> oldMap) {
        List<Id> additionalParticipantIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();

        for (Additional_Partcipant__c ap : newRecords) {
            if (String.isBlank(ap.Email__c)) {
                continue;
            }
            if ((ap.Roles__c == 'Referee' || ap.Roles__c == 'Mentor') && ap.Proposal__c != null && ap.Referee_Added_For_Full__c == true) {
                if (oldMap != null) {
                    Additional_Partcipant__c oldAp = oldMap.get(ap.Id);
                    Boolean wasTrue = oldAp != null && oldAp.Referee_Added_For_Full__c == true;
                    if (wasTrue) {
                        continue; // already true before this update, don't resend
                    }
                }
                String invitationLink = buildInvitationLink(ap);
                additionalParticipantIds.add(ap.Id);
                invitationLinks.put(ap.Id, invitationLink);
            }
        }

        if (additionalParticipantIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'REFEREE',
                additionalParticipantIds,
                invitationLinks,
                'Refferre_Invitation_for_Full'
            )
        );
    }

    public static void sendInvitationContactEmails(List<Additional_Partcipant__c> newRecords, Map<Id, Additional_Partcipant__c> oldMap) {
        List<Id> additionalParticipantIdsForContactEmail = new List<Id>();

        for (Additional_Partcipant__c ap : newRecords) {
            if (String.isBlank(ap.Email__c)) {
                continue;
            }
            if ((ap.Roles__c == 'Referee' || ap.Roles__c == 'Mentor') && ap.Proposal__c != null && ap.DocumentUploaded__c != false ) {
                System.debug('REFEREE MENTOR DOC UPDATED');
                if (oldMap != null) {
                Additional_Partcipant__c oldAp = oldMap.get(ap.Id);
                Boolean wasTrue = oldAp != null && oldAp.DocumentUploaded__c == true;
                if (wasTrue) {
                    continue;
                }
                additionalParticipantIdsForContactEmail.add( ap.Id );
            }
            if(!additionalParticipantIdsForContactEmail.isEmpty()){
                System.enqueueJob(
                    new EmailNotificationQueueable(
                        'CONREFEREE',
                        additionalParticipantIdsForContactEmail,
                        null,
                        'RefereeContactEmail'
                    )
                );
             }   
            }
        }
    }

    private static String buildInvitationLink(Additional_Partcipant__c ap) {
        Map<String, Object> payload = new Map<String, Object>{ 'additionalParticipantId' => ap.Id, 'role' => ap.Roles__c, 'firstName' => ap.First_Name__c, 'lastName' => ap.Last_Name__c, 'title' => ap.Title__c, 'proposalId' => ap.Proposal_Id__c };
        System.debug('Proposal Id =====>' + ap.Proposal_Id__c);
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode(Blob.valueOf(jsonPayload));
        String urlSafePayload = EncodingUtil.urlEncode(base64Payload, 'UTF-8');

        return REFEREE_REACT_APP_URL + '?data=' + urlSafePayload;
    }
}










/*
public class additionalParticipantTriggerHandler {

    private static final String REFEREE_REACT_APP_URL;
    // Static initialization block
    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';

        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        REFEREE_REACT_APP_URL = reactBaseUrl + 'refree';
    }

    // ---- INSERT context: no old values to compare against ----
    public static void sendInvitationEmails(List<Additional_Partcipant__c> newRecords) {
        sendInvitationEmails(newRecords, null);
    }
	public static void sendInvitationContactEmails(List<Additional_Partcipant__c> newRecords) {
        sendInvitationContactEmails(newRecords, null);
    }

    // ---- INSERT + UPDATE context ----
    // oldMap == null  => insert (send whenever Notify_through_Email__c is true)
    // oldMap != null  => update (send only when Notify_through_Email__c just
    //                    flipped from false/null to true, to avoid re-sending
    //                    on every subsequent edit of an already-notified row)
    public static void sendInvitationEmails(List<Additional_Partcipant__c> newRecords, Map<Id, Additional_Partcipant__c> oldMap) {
        List<Id> additionalParticipantIds = new List<Id>();
        List<Id> contactIds = new List<Id>();
        List<Id> proposalIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();

        for (Additional_Partcipant__c ap : newRecords) {
            if (String.isBlank(ap.Email__c)) {
                continue;
            }
            if((ap.Roles__c == 'Referee' || ap.Roles__c == 'Mentor') && ap.Proposal__c != null  && ap.Notify_through_Email__c == true){
                if (oldMap != null) {
                    Additional_Partcipant__c oldAp = oldMap.get(ap.Id);
                    Boolean wasTrue = oldAp != null && oldAp.Notify_through_Email__c == true;
                    if (wasTrue) {
                        continue; // already true before this update, don't resend
                    }
            	}
                 String invitationLink = buildInvitationLink(ap);
                additionalParticipantIds.add(ap.Id);
                invitationLinks.put(ap.Id, invitationLink);
            }
        }

        if (additionalParticipantIds.isEmpty()) {
            return;
        }
        if(!additionalParticipantIds.isEmpty()){
            System.enqueueJob(
                new EmailNotificationQueueable(
                    'REFEREE',
                    additionalParticipantIds,
                    invitationLinks,
                    'Refferre_Invitation'
                )
            );
        }
    }
    public static void sendInvitationContactEmails(List<Additional_Partcipant__c> newRecords, Map<Id, Additional_Partcipant__c> oldMap) {
        List<Id> additionalParticipantIdsForContactEmail = new List<Id>();

        for (Additional_Partcipant__c ap : newRecords) {
            if (String.isBlank(ap.Email__c)) {
                continue;
            }
            if ((ap.Roles__c == 'Referee' || ap.Roles__c == 'Mentor') && ap.Proposal__c != null && ap.DocumentUploaded__c != false ) {
                System.debug('REFEREE MENTOR DOC UPDATED');
                if (oldMap != null) {
                Additional_Partcipant__c oldAp = oldMap.get(ap.Id);
                Boolean wasTrue = oldAp != null && oldAp.DocumentUploaded__c == true;
                if (wasTrue) {
                    continue;
                }
                additionalParticipantIdsForContactEmail.add( ap.Id );
            }
            if(!additionalParticipantIdsForContactEmail.isEmpty()){
                System.enqueueJob(
                    new EmailNotificationQueueable(
                        'CONREFEREE',
                        additionalParticipantIdsForContactEmail,
                        null,
                        'RefereeContactEmail'
                    )
                );
             }   
            }
        }
    }

    private static String buildInvitationLink(Additional_Partcipant__c ap) {
        Map<String, Object> payload = new Map<String, Object>{ 'additionalParticipantId' => ap.Id, 'role' => ap.Roles__c, 'firstName' => ap.First_Name__c, 'lastName' => ap.Last_Name__c, 'title' => ap.Title__c, 'proposalId' => ap.Proposal_Id__c };
        System.debug('Proposal Id =====>' + ap.Proposal_Id__c);
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode(Blob.valueOf(jsonPayload));
        String urlSafePayload = EncodingUtil.urlEncode(base64Payload, 'UTF-8');

        return REFEREE_REACT_APP_URL + '?data=' + urlSafePayload;
    }
}
8/








/*
public class additionalParticipantTriggerHandler {

    private static final String REFEREE_REACT_APP_URL;
    // Static initialization block
    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';

        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        REFEREE_REACT_APP_URL = reactBaseUrl + 'refree';
    }

    public static void sendInvitationEmails( List<Additional_Partcipant__c> newRecords ) {
        List<Id> additionalParticipantIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();

        for (Additional_Partcipant__c ap : newRecords) {
            if (String.isBlank(ap.Email__c)) {
                continue;
            }
			if(ap.Roles__c =='Referee' && ap.Proposal__c != null){
				String invitationLink =   buildInvitationLink(ap);
				additionalParticipantIds.add(ap.Id);
				invitationLinks.put(ap.Id,invitationLink);
			}
        }
        
        if (additionalParticipantIds.isEmpty()) {
            return;
        }
        System.enqueueJob( new Refferee_EmailQueueable( additionalParticipantIds, invitationLinks,'Refferre_Invitation'));
    }

    private static String buildInvitationLink( Additional_Partcipant__c ap) {
        Map<String, Object> payload =  new Map<String, Object>{ 'additionalParticipantId' => ap.Id, 'role' => ap.Roles__c,'firstName' => ap.First_Name__c , 'lastName' => ap.Last_Name__c , 'title' =>  ap.Title__c , 'proposalId' => ap.Proposal_Id__c };
        system.debug('Proposal Id =====>'+ap.Proposal_Id__c);
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode( Blob.valueOf(jsonPayload) );
        String urlSafePayload = EncodingUtil.urlEncode( base64Payload, 'UTF-8' );

        return REFEREE_REACT_APP_URL + '?data=' + urlSafePayload;
    }

}
*/