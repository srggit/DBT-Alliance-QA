public class ProposalParticipantTriggerHandler {

    private static final String HOST_REACT_APP_URL;
    // Static initialization block
    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';

        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        HOST_REACT_APP_URL = reactBaseUrl + 'login';
    }

    // ---- INSERT context: no old values to compare against ----
    public static void sendInvitationEmails(List<Proposal_Participant_Association__c> newRecords) {
        sendInvitationEmails(newRecords, null);
    }

    // ---- INSERT + UPDATE context ----
    // oldMap == null  => insert (send whenever Notify_through_Email__c is true)
    // oldMap != null  => update (send only when Notify_through_Email__c just
    //                    flipped from false/null to true, to avoid re-sending
    //                    on every subsequent edit of an already-notified row)
    public static void sendInvitationEmails(List<Proposal_Participant_Association__c> newRecords, Map<Id, Proposal_Participant_Association__c> oldMap) {
        List<Id> proposalParticipantAssociationIds = new List<Id>();
        Map<Id, String> invitationLinks = new Map<Id, String>();

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

            String invitationLink = buildInvitationLink(ppa);
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

    private static String buildInvitationLink(Proposal_Participant_Association__c ppa) {
        Map<String, Object> payload = new Map<String, Object>{ 'contactId' => ppa.Participant__c, 'type' => 'Host' };
        String jsonPayload = JSON.serialize(payload);
        String base64Payload = EncodingUtil.base64Encode(Blob.valueOf(jsonPayload));
        String urlSafePayload = EncodingUtil.urlEncode(base64Payload, 'UTF-8');

        return HOST_REACT_APP_URL + '?data=' + urlSafePayload;
    }
}