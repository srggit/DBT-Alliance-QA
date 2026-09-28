public class ProposalParticipantTriggerHandler {

    private static final String HOST_REACT_APP_BASE_URL;
    private static final String HOST_REACT_APP_URL;

    // Static initialization block
    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';

        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        HOST_REACT_APP_BASE_URL = reactBaseUrl;
        HOST_REACT_APP_URL = reactBaseUrl + 'login';
    }

    // ---- INSERT context: no old values to compare against ----
    public static void sendInvitationEmails(List<Proposal_Participant_Association__c> newRecords) {
        sendInvitationEmails(newRecords, null);
    }
    public static void sendFullInvitationEmails(List<Proposal_Participant_Association__c> newRecords) {
        sendFullInvitationEmails(newRecords, null);
    }

    // ---- Helper ----
    // true when Re_Notify_Count__c went up on this update (null treated as 0)
    private static Boolean isReNotified(Proposal_Participant_Association__c ppa, Map<Id, Proposal_Participant_Association__c> oldMap) {
        if (oldMap == null) {
            return false;
        }
        Proposal_Participant_Association__c oldPpa = oldMap.get(ppa.Id);
        if (oldPpa == null) {
            return false;
        }
        Decimal newCount = ppa.Re_Notify_Count__c == null ? 0 : ppa.Re_Notify_Count__c;
        Decimal oldCount = oldPpa.Re_Notify_Count__c == null ? 0 : oldPpa.Re_Notify_Count__c;
        return newCount > oldCount;
    }

    // ---- Notify_through_Email__c: Proposal_Participant_Host_Invitation ----
    // Send when: flag is true AND (insert OR flag just flipped to true OR Re_Notify_Count__c increased)
    public static void sendInvitationEmails(List<Proposal_Participant_Association__c> newRecords, Map<Id, Proposal_Participant_Association__c> oldMap) {
        List<Id> proposalParticipantAssociationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();
        Map<Id, Contact> contactMap = getContactFirebaseMap(newRecords);

        for (Proposal_Participant_Association__c ppa : newRecords) {
            if (ppa.Participant__c == null || ppa.Proposal__c == null || ppa.Notify_through_Email__c != true) {
                continue;
            }

            Boolean shouldSend = true; // insert case
            if (oldMap != null) {
                Proposal_Participant_Association__c oldPpa = oldMap.get(ppa.Id);
                Boolean flipped  = oldPpa == null || oldPpa.Notify_through_Email__c != true;
                Boolean reNotify = isReNotified(ppa, oldMap);
                shouldSend = flipped || reNotify;
            }

            if (shouldSend) {
                proposalParticipantAssociationIds.add(ppa.Id);
                invitationLinks.put(ppa.Id, buildInvitationLink(ppa, contactMap));
            }
        }

        if (proposalParticipantAssociationIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'PROPOSAL_PARTICIPANT_HOST',
                proposalParticipantAssociationIds,
                invitationLinks,
                'Proposal_Participant_Host_Invitation'
            )
        );
    }

    // ---- Added_for_Full__c: Proposal_Participant_Host_Invitation_for_Full ----
    // Send when: flag is true AND (insert OR flag just flipped to true OR Re_Notify_Count__c increased)
    public static void sendFullInvitationEmails(List<Proposal_Participant_Association__c> newRecords, Map<Id, Proposal_Participant_Association__c> oldMap) {
        List<Id> proposalParticipantAssociationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();
        Map<Id, Contact> contactMap = getContactFirebaseMap(newRecords);

        for (Proposal_Participant_Association__c ppa : newRecords) {
            if (ppa.Participant__c == null || ppa.Proposal__c == null || ppa.Added_for_Full__c != true) {
                continue;
            }

            Boolean shouldSend = true; // insert case
            if (oldMap != null) {
                Proposal_Participant_Association__c oldPpa = oldMap.get(ppa.Id);
                Boolean flipped  = oldPpa == null || oldPpa.Added_for_Full__c != true;
                Boolean reNotify = isReNotified(ppa, oldMap);
                shouldSend = flipped || reNotify;
            }

            if (shouldSend) {
                proposalParticipantAssociationIds.add(ppa.Id);
                invitationLinks.put(ppa.Id, buildInvitationLink(ppa, contactMap));
            }
        }

        if (proposalParticipantAssociationIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'PROPOSAL_PARTICIPANT_HOST',
                proposalParticipantAssociationIds,
                invitationLinks,
                'Proposal_Participant_Host_Invitation_for_Full'
            )
        );
    }

    // ---- Bulkified lookup of Contact.Firebase_UID__c for all participants in this batch ----
    private static Map<Id, Contact> getContactFirebaseMap(List<Proposal_Participant_Association__c> records) {
        Set<Id> participantIds = new Set<Id>();
        for (Proposal_Participant_Association__c ppa : records) {
            if (ppa.Participant__c != null) {
                participantIds.add(ppa.Participant__c);
            }
        }

        if (participantIds.isEmpty()) {
            return new Map<Id, Contact>();
        }

        return new Map<Id, Contact>(
            [SELECT Id, Firebase_UID__c FROM Contact WHERE Id IN :participantIds]
        );
    }

    // ---- Builds either the verify-email link (no Firebase_UID__c yet) or the standard login link ----
    private static String buildInvitationLink(Proposal_Participant_Association__c ppa, Map<Id, Contact> contactMap) {
        Contact con = contactMap.get(ppa.Participant__c);

        if (con != null && String.isBlank(con.Firebase_UID__c)) {
            return HOST_REACT_APP_BASE_URL + 'host-verify-email?contactId=' + ppa.Participant__c;
        }

        Map<String, Object> payload = new Map<String, Object>{ 'contactId' => ppa.Participant__c, 'type' => 'Host' };
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode(Blob.valueOf(jsonPayload));
        String urlSafePayload = EncodingUtil.urlEncode(base64Payload, 'UTF-8');

        return HOST_REACT_APP_URL + '?data=' + urlSafePayload;
    }

    // ---- INSERT context: no old values to compare against ----
    public static void createDocumentUploadedNotifications(List<Proposal_Participant_Association__c> newRecords) {
        createDocumentUploadedNotifications(newRecords, null);
    }

    // ---- INSERT + UPDATE context ----
    public static void createDocumentUploadedNotifications(List<Proposal_Participant_Association__c> newRecords, Map<Id, Proposal_Participant_Association__c> oldMap) {
        List<Proposal_Participant_Association__c> documentUploadedRecords = new List<Proposal_Participant_Association__c>();

        for (Proposal_Participant_Association__c ppa : newRecords) {
            if (ppa.Document_Uploaded__c != true) {
                continue;
            }

            if (oldMap != null) {
                Proposal_Participant_Association__c oldPpa = oldMap.get(ppa.Id);
                Boolean wasTrue = oldPpa != null && oldPpa.Document_Uploaded__c == true;
                if (wasTrue) {
                    continue; // already true before this update, don't re-notify
                }
            }

            documentUploadedRecords.add(ppa);
        }

        if (documentUploadedRecords.isEmpty()) {
            return;
        }

        NotificationHandler.createNotifications('Proposal_Participant_Association__c', documentUploadedRecords);

        List<Id> documentUploadedIds = new List<Id>();
        for (Proposal_Participant_Association__c ppa : documentUploadedRecords) {
            documentUploadedIds.add(ppa.Id);
        }
        System.enqueueJob(new EmailNotificationQueueable('PPA_DOCUMENT_SUBMITTED', documentUploadedIds));
    }
}









/*
public class ProposalParticipantTriggerHandler {

    private static final String HOST_REACT_APP_BASE_URL;
    private static final String HOST_REACT_APP_URL;

    // Static initialization block
    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';

        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        HOST_REACT_APP_BASE_URL = reactBaseUrl;
        HOST_REACT_APP_URL = reactBaseUrl + 'login';
    }

    // ---- INSERT context: no old values to compare against ----
    public static void sendInvitationEmails(List<Proposal_Participant_Association__c> newRecords) {
        sendInvitationEmails(newRecords, null);
    }
    public static void sendFullInvitationEmails(List<Proposal_Participant_Association__c> newRecords) {
        sendFullInvitationEmails(newRecords, null);
    }

    // ---- INSERT + UPDATE context ----
    // oldMap == null  => insert (send whenever Notify_through_Email__c is true)
    // oldMap != null  => update (send only when Notify_through_Email__c just
    //                    flipped from false/null to true, to avoid re-sending
    //                    on every subsequent edit of an already-notified row)
    public static void sendInvitationEmails(List<Proposal_Participant_Association__c> newRecords, Map<Id, Proposal_Participant_Association__c> oldMap) {
        List<Id> proposalParticipantAssociationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();
        Map<Id, Contact> contactMap = getContactFirebaseMap(newRecords);

        for (Proposal_Participant_Association__c ppa : newRecords) {
            if (ppa.Participant__c == null || ppa.Proposal__c == null || ppa.Notify_through_Email__c != true) {
                continue;
            }

            if (oldMap != null) {
                Proposal_Participant_Association__c oldPpa = oldMap.get(ppa.Id);
                Boolean wasTrue = oldPpa != null && oldPpa.Notify_through_Email__c == true;
                if (wasTrue) {
                    continue; // already true before this update, don't resend
                }
            }

            String invitationLink = buildInvitationLink(ppa, contactMap);
            proposalParticipantAssociationIds.add(ppa.Id);
            invitationLinks.put(ppa.Id, invitationLink);
        }

        if (proposalParticipantAssociationIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'PROPOSAL_PARTICIPANT_HOST',
                proposalParticipantAssociationIds,
                invitationLinks,
                'Proposal_Participant_Host_Invitation'
            )
        );
    }

    // ---- Added_for_Full__c flip context ----
    // oldMap == null  => insert (send whenever Added_for_Full__c is true on creation)
    // oldMap != null  => update (send only when Added_for_Full__c just flipped
    //                    from false/null to true, to avoid re-sending on every later edit)
    public static void sendFullInvitationEmails(List<Proposal_Participant_Association__c> newRecords, Map<Id, Proposal_Participant_Association__c> oldMap) {
        List<Id> proposalParticipantAssociationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();
        Map<Id, Contact> contactMap = getContactFirebaseMap(newRecords);

        for (Proposal_Participant_Association__c ppa : newRecords) {
            if (ppa.Participant__c == null || ppa.Proposal__c == null || ppa.Added_for_Full__c != true) {
                continue;
            }

            if (oldMap != null) {
                Proposal_Participant_Association__c oldPpa = oldMap.get(ppa.Id);
                Boolean wasTrue = oldPpa != null && oldPpa.Added_for_Full__c == true;
                if (wasTrue) {
                    continue; // already true before this update, don't resend
                }
            }

            String invitationLink = buildInvitationLink(ppa, contactMap);
            proposalParticipantAssociationIds.add(ppa.Id);
            invitationLinks.put(ppa.Id, invitationLink);
        }

        if (proposalParticipantAssociationIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'PROPOSAL_PARTICIPANT_HOST',
                proposalParticipantAssociationIds,
                invitationLinks,
                'Proposal_Participant_Host_Invitation_for_Full'
            )
        );
    }

    // ---- Bulkified lookup of Contact.Firebase_UID__c for all participants in this batch ----
    private static Map<Id, Contact> getContactFirebaseMap(List<Proposal_Participant_Association__c> records) {
        Set<Id> participantIds = new Set<Id>();
        for (Proposal_Participant_Association__c ppa : records) {
            if (ppa.Participant__c != null) {
                participantIds.add(ppa.Participant__c);
            }
        }

        if (participantIds.isEmpty()) {
            return new Map<Id, Contact>();
        }

        return new Map<Id, Contact>(
            [SELECT Id, Firebase_UID__c FROM Contact WHERE Id IN :participantIds]
        );
    }

    // ---- Builds either the verify-email link (no Firebase_UID__c yet) or the standard login link ----
    private static String buildInvitationLink(Proposal_Participant_Association__c ppa, Map<Id, Contact> contactMap) {
        Contact con = contactMap.get(ppa.Participant__c);

        if (con != null && String.isBlank(con.Firebase_UID__c)) {
            return HOST_REACT_APP_BASE_URL + 'host-verify-email?contactId=' + ppa.Participant__c;
        }

        Map<String, Object> payload = new Map<String, Object>{ 'contactId' => ppa.Participant__c, 'type' => 'Host' };
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode(Blob.valueOf(jsonPayload));
        String urlSafePayload = EncodingUtil.urlEncode(base64Payload, 'UTF-8');

        return HOST_REACT_APP_URL + '?data=' + urlSafePayload;
    }

    // ---- INSERT context: no old values to compare against ----
    public static void createDocumentUploadedNotifications(List<Proposal_Participant_Association__c> newRecords) {
        createDocumentUploadedNotifications(newRecords, null);
    }

    // ---- INSERT + UPDATE context ----
    // oldMap == null  => insert (notify whenever Document_Uploaded__c is true on creation)
    // oldMap != null  => update (notify only when Document_Uploaded__c just
    //                    flipped from false/null to true, to avoid re-notifying
    //                    on every subsequent edit of an already-notified row)
    public static void createDocumentUploadedNotifications(List<Proposal_Participant_Association__c> newRecords, Map<Id, Proposal_Participant_Association__c> oldMap) {
        List<Proposal_Participant_Association__c> documentUploadedRecords = new List<Proposal_Participant_Association__c>();

        for (Proposal_Participant_Association__c ppa : newRecords) {
            if (ppa.Document_Uploaded__c != true) {
                continue;
            }

            if (oldMap != null) {
                Proposal_Participant_Association__c oldPpa = oldMap.get(ppa.Id);
                Boolean wasTrue = oldPpa != null && oldPpa.Document_Uploaded__c == true;
                if (wasTrue) {
                    continue; // already true before this update, don't re-notify
                }
            }

            documentUploadedRecords.add(ppa);
        }

        if (documentUploadedRecords.isEmpty()) {
            return;
        }

        NotificationHandler.createNotifications('Proposal_Participant_Association__c', documentUploadedRecords);

        List<Id> documentUploadedIds = new List<Id>();
        for (Proposal_Participant_Association__c ppa : documentUploadedRecords) {
            documentUploadedIds.add(ppa.Id);
        }
        System.enqueueJob(new EmailNotificationQueueable('PPA_DOCUMENT_SUBMITTED', documentUploadedIds));
    }
}
*/