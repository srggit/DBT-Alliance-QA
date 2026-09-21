/**
 * Backing controller for the `caseMessages` LWC (Case Record Action).
 *
 * Conversation model:
 *  - Case                 = the ticket / thread container
 *  - Case_Message__c      = one record per message (Master-Detail to Case)
 *  - Inbound  message     = from the Committee Member (Sender_Type__c = 'Committee Member')
 *  - Outbound message     = from the Grant Team      (Sender_Type__c = 'Grant Team')
 *
 * The Committee Member is NOT a Salesforce User, so the inbound sender name is
 * taken from Case.Committee_Master__c. Outbound messages use Sender_User__c.
 */
public with sharing class CaseMessagesController {

    // ---- Picklist / status API values (verified against the org) -------------
    @TestVisible private static final String SENDER_TYPE_GRANT_TEAM   = 'Grant Team';
    @TestVisible private static final String SENDER_TYPE_COMMITTEE    = 'Committee Member';
    @TestVisible private static final String DIRECTION_INBOUND        = 'Inbound';
    @TestVisible private static final String DIRECTION_OUTBOUND       = 'Outbound';
    @TestVisible private static final String CASE_STATUS_IN_PROGRESS  = 'In Progress';

    private static final Integer PREVIEW_LENGTH = 255;

    /**
     * Load the whole conversation for a Case and, by default, mark inbound
     * (Committee Member) messages as read by the Grant Team.
     */
    @AuraEnabled
    public static Conversation getConversation(Id caseId, Boolean markRead) {
        if (caseId == null) {
            throw new AuraHandledException('Missing Case Id.');
        }
        Boolean doMarkRead = (markRead == null) ? true : markRead;

        Case cs = loadCase(caseId);
        String committeeName = committeeMasterName(cs);

        List<Case_Message__c> records = [
            SELECT Id, Body__c, Sender_Type__c, Direction__c, Is_Read__c, Read_DateTime__c,
                   Read_By_Committee__c, Read_By_Committee_DateTime__c,
                   Sent_DateTime__c, CreatedDate, CreatedBy.Name, Sender_User__r.Name
            FROM Case_Message__c
            WHERE Case__c = :caseId
            ORDER BY Sent_DateTime__c ASC NULLS FIRST, CreatedDate ASC
        ];

        List<Message> msgs = new List<Message>();
        List<Case_Message__c> toFlag = new List<Case_Message__c>();
        Datetime now = System.now();

        for (Case_Message__c r : records) {
            Boolean inbound = isInbound(r);

            Message m = new Message();
            m.id = r.Id;
            m.body = r.Body__c;
            m.senderType = r.Sender_Type__c;
            m.inbound = inbound;
            m.senderName = inbound
                ? (String.isNotBlank(committeeName) ? committeeName : 'Committee Member')
                : (r.Sender_User__r.Name != null ? r.Sender_User__r.Name : r.CreatedBy.Name);
            m.sentDateTime = (r.Sent_DateTime__c != null) ? r.Sent_DateTime__c : r.CreatedDate;
            m.isRead = r.Is_Read__c;
            m.readByCommittee = r.Read_By_Committee__c == true;
            m.readByCommitteeDateTime = r.Read_By_Committee_DateTime__c;
            msgs.add(m);

            if (doMarkRead && inbound && r.Is_Read__c != true) {
                toFlag.add(new Case_Message__c(
                    Id = r.Id, Is_Read__c = true, Read_DateTime__c = now
                ));
            }
        }

        if (!toFlag.isEmpty()) {
            update toFlag;
            for (Message m : msgs) {
                if (m.inbound) {
                    m.isRead = true;
                }
            }
        }

        Conversation conv = new Conversation();
        conv.caseId = cs.Id;
        conv.caseNumber = cs.CaseNumber;
        conv.subject = cs.Subject;
        conv.status = cs.Status;
        conv.createdDate = cs.CreatedDate;
        conv.applicantName = cs.Applicant_Name__c;
        conv.committeeMemberName = committeeName;
        conv.committeeMemberOrg = (cs.Committee_Master__c != null)
            ? cs.Committee_Master__r.Organisation_Name__c : null;
        conv.messages = msgs;
        return conv;
    }

    /**
     * Grant Team posts a reply. Inserts an outbound Case Message, moves the
     * Case to In Progress, and refreshes the Last Message summary fields.
     * Returns the refreshed conversation so the LWC can re-render.
     */
    @AuraEnabled
    public static Conversation sendReply(Id caseId, String body) {
        if (caseId == null) {
            throw new AuraHandledException('Missing Case Id.');
        }
        String preview = stripHtml(body);
        if (String.isBlank(preview)) {
            throw new AuraHandledException('Reply cannot be empty.');
        }

        Datetime now = System.now();

        // Is_Read__c tracks "read by the Grant Team" and is not meaningful for an
        // outbound message. Read_By_Committee__c stays false until the Committee
        // Member views the message through the portal (see markReadByCommittee).
        insert new Case_Message__c(
            Case__c = caseId,
            Body__c = body,
            Sender_Type__c = SENDER_TYPE_GRANT_TEAM,
            Direction__c = DIRECTION_OUTBOUND,
            Sender_User__c = UserInfo.getUserId(),
            Sent_DateTime__c = now,
            Is_Read__c = false,
            Read_By_Committee__c = false
        );

        update new Case(
            Id = caseId,
            Status = CASE_STATUS_IN_PROGRESS,
            Last_Message__c = preview.abbreviate(PREVIEW_LENGTH),
            Last_Message_DateTime__c = now,
            Sender_Type__c = SENDER_TYPE_GRANT_TEAM
        );

        return getConversation(caseId, false);
    }

    /**
     * Marks the Grant Team's outbound messages on a Case as read by the Committee
     * Member. Intended to be called from the portal / API layer at the moment the
     * Committee Member fetches or opens the conversation. Returns the number of
     * messages updated.
     */
    @AuraEnabled
    public static Integer markReadByCommittee(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Missing Case Id.');
        }

        Datetime now = System.now();
        List<Case_Message__c> toFlag = new List<Case_Message__c>();
        for (Case_Message__c r : [
            SELECT Id
            FROM Case_Message__c
            WHERE Case__c = :caseId
              AND Direction__c = :DIRECTION_OUTBOUND
              AND Read_By_Committee__c = false
        ]) {
            toFlag.add(new Case_Message__c(
                Id = r.Id, Read_By_Committee__c = true, Read_By_Committee_DateTime__c = now
            ));
        }

        if (!toFlag.isEmpty()) {
            update toFlag;
        }
        return toFlag.size();
    }

    // ---- helpers ------------------------------------------------------------

    private static Case loadCase(Id caseId) {
        List<Case> rows = [
            SELECT Id, CaseNumber, Subject, Status, CreatedDate, Applicant_Name__c,
                   Committee_Master__c, Committee_Master__r.First_Name__c,
                   Committee_Master__r.Last_Name__c, Committee_Master__r.Organisation_Name__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Case not found or not accessible.');
        }
        return rows[0];
    }

    private static Boolean isInbound(Case_Message__c r) {
        if (String.isNotBlank(r.Sender_Type__c)) {
            return r.Sender_Type__c == SENDER_TYPE_COMMITTEE;
        }
        return r.Direction__c == DIRECTION_INBOUND;
    }

    private static String committeeMasterName(Case cs) {
        if (cs.Committee_Master__c == null || cs.Committee_Master__r == null) {
            return null;
        }
        String fn = cs.Committee_Master__r.First_Name__c;
        String ln = cs.Committee_Master__r.Last_Name__c;
        return ((String.isBlank(fn) ? '' : fn.trim()) + ' ' +
                (String.isBlank(ln) ? '' : ln.trim())).trim();
    }

    @TestVisible
    private static String stripHtml(String input) {
        if (String.isBlank(input)) {
            return '';
        }
        return input.replaceAll('<[^>]+>', ' ')
                    .replaceAll('&nbsp;', ' ')
                    .replaceAll('\\s+', ' ')
                    .trim();
    }

    // ---- wrappers ---------------------------------------------------------

    public class Conversation {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String committeeMemberName;
        @AuraEnabled public String committeeMemberOrg;
        @AuraEnabled public List<Message> messages = new List<Message>();
    }

    public class Message {
        @AuraEnabled public Id id;
        @AuraEnabled public String body;
        @AuraEnabled public String senderType;
        @AuraEnabled public String senderName;
        @AuraEnabled public Boolean inbound;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public Boolean readByCommittee;
        @AuraEnabled public Datetime readByCommitteeDateTime;
        @AuraEnabled public Datetime sentDateTime;
    }
}