public with sharing class BulkEligibilityCheckController {

    private static final String NOTIFICATION_TYPE_DEVELOPER_NAME = 'Bulk_Eligibility_Check_Alert';

    @AuraEnabled(cacheable=true)
    public static List<SchemeGroup> getSchemeGroups(List<Id> proposalIds) {
        if (proposalIds == null || proposalIds.isEmpty()) {
            throw new AuraHandledException('Select at least one Proposal.');
        }

        return buildSchemeGroups(proposalIds);
    }

    @AuraEnabled
    public static void sendNotifications(List<Id> proposalIds) {
        if (proposalIds == null || proposalIds.isEmpty()) {
            throw new AuraHandledException('Select at least one Proposal.');
        }

        List<SchemeGroup> groups = buildSchemeGroups(proposalIds);
        if (groups.isEmpty()) {
            throw new AuraHandledException('No Grant Team Members found for the selected Proposals.');
        }

        Id notificationTypeId = getNotificationTypeId();
        if (notificationTypeId == null) {
            throw new AuraHandledException('Bulk Eligibility Check notification type is not configured.');
        }

        Map<Id, Id> firstAssignmentIdByMemberId = createAssignments(groups);

        Integer notifiedRecipientCount = 0;

        for (SchemeGroup schemeGroup : groups) {
            if (schemeGroup.members.isEmpty()) {
                continue;
            }

            String body = 'Bulk eligibility check requested for ' + schemeGroup.proposalCount +
                ' proposal(s) under ' + schemeGroup.schemeNumber + '.';

            for (MemberInfo member : schemeGroup.members) {
                Id targetId = firstAssignmentIdByMemberId.containsKey(member.userId)
                    ? firstAssignmentIdByMemberId.get(member.userId)
                    : schemeGroup.schemeId;

                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('Bulk Eligibility Check');
                notification.setBody(body);
                notification.setNotificationTypeId(notificationTypeId);
                notification.setTargetId(targetId);

                try {
                    notification.send(new Set<String>{ member.userId });
                    notifiedRecipientCount++;
                } catch (Exception ex) {
                    throw new AuraHandledException('Unable to send notification: ' + ex.getMessage());
                }
            }
        }

        if (notifiedRecipientCount == 0) {
            throw new AuraHandledException('No Grant Team Members found for the selected Proposals.');
        }
    }

    private static Map<Id, Id> createAssignments(List<SchemeGroup> groups) {
        Set<Id> proposalIds = new Set<Id>();
        for (SchemeGroup schemeGroup : groups) {
            for (ProposalInfo proposal : schemeGroup.proposals) {
                proposalIds.add(proposal.proposalId);
            }
        }

        Set<String> existingPairKeys = new Set<String>();
        if (!proposalIds.isEmpty()) {
            for (Eligibility_Check_Assignment__c assignment : [
                SELECT Proposal__c, Grant_Team_Member__c
                FROM Eligibility_Check_Assignment__c
                WHERE Proposal__c IN :proposalIds
                AND Status__c = 'Pending'
            ]) {
                existingPairKeys.add(assignment.Proposal__c + ':' + assignment.Grant_Team_Member__c);
            }
        }

        List<Eligibility_Check_Assignment__c> assignmentsToInsert = new List<Eligibility_Check_Assignment__c>();
        for (SchemeGroup schemeGroup : groups) {
            for (ProposalInfo proposal : schemeGroup.proposals) {
                for (MemberInfo member : schemeGroup.members) {
                    String pairKey = proposal.proposalId + ':' + member.userId;
                    if (existingPairKeys.contains(pairKey)) {
                        continue;
                    }
                    existingPairKeys.add(pairKey);

                    assignmentsToInsert.add(new Eligibility_Check_Assignment__c(
                        Proposal__c = proposal.proposalId,
                        Grant_Team_Member__c = member.userId,
                        Grants_Team_Members__c = member.grantsTeamMemberId,
                        Yearly_Scheme__c = schemeGroup.schemeId,
                        Status__c = 'Pending',
                        OwnerId = member.userId
                    ));
                }
            }
        }

        if (!assignmentsToInsert.isEmpty()) {
            insert assignmentsToInsert;
        }

        Map<Id, Id> firstAssignmentIdByMemberId = new Map<Id, Id>();
        for (Eligibility_Check_Assignment__c assignment : assignmentsToInsert) {
            if (!firstAssignmentIdByMemberId.containsKey(assignment.Grant_Team_Member__c)) {
                firstAssignmentIdByMemberId.put(assignment.Grant_Team_Member__c, assignment.Id);
            }
        }

        return firstAssignmentIdByMemberId;
    }

    private static List<SchemeGroup> buildSchemeGroups(List<Id> proposalIds) {
        Map<Id, List<ProposalInfo>> proposalsBySchemeId = new Map<Id, List<ProposalInfo>>();
        Map<Id, String> schemeNumberById = new Map<Id, String>();
        Map<Id, String> schemeLabelById = new Map<Id, String>();
        Set<Id> proposalIdsWithScheme = new Set<Id>();

        Map<Id, Proposal__c> proposalsById = new Map<Id, Proposal__c>([
            SELECT Id, Name, Project_Title__c, Application_Date__c, Proposal_Status__c,
                Yearly_Scheme__c, Yearly_Scheme__r.Name, Yearly_Scheme__r.Scheme_Items__r.Name
            FROM Proposal__c
            WHERE Id IN :proposalIds
            AND Yearly_Scheme__c != NULL
        ]);

        for (Proposal__c proposal : proposalsById.values()) {
            proposalIdsWithScheme.add(proposal.Id);
            schemeNumberById.put(proposal.Yearly_Scheme__c, proposal.Yearly_Scheme__r.Name);
            schemeLabelById.put(
                proposal.Yearly_Scheme__c,
                proposal.Yearly_Scheme__r.Scheme_Items__r != null
                    ? proposal.Yearly_Scheme__r.Scheme_Items__r.Name
                    : null
            );
        }

        if (schemeNumberById.isEmpty()) {
            return new List<SchemeGroup>();
        }

        Map<Id, String> submittedByByProposalId = new Map<Id, String>();
        for (Applicant_Proposal_Association__c association : [
            SELECT Proposal__c, Contact__r.Name
            FROM Applicant_Proposal_Association__c
            WHERE Proposal__c IN :proposalIdsWithScheme
            AND Contact__c != NULL
        ]) {
            submittedByByProposalId.put(association.Proposal__c, association.Contact__r.Name);
        }

        for (Proposal__c proposal : proposalsById.values()) {
            Id schemeId = proposal.Yearly_Scheme__c;
            if (!proposalsBySchemeId.containsKey(schemeId)) {
                proposalsBySchemeId.put(schemeId, new List<ProposalInfo>());
            }
            proposalsBySchemeId.get(schemeId).add(new ProposalInfo(
                proposal.Id,
                proposal.Name,
                proposal.Project_Title__c,
                submittedByByProposalId.get(proposal.Id),
                proposal.Application_Date__c,
                proposal.Proposal_Status__c
            ));
        }

        Map<Id, List<MemberInfo>> membersBySchemeId = new Map<Id, List<MemberInfo>>();
        for (Grants_Team_Members__c member : [
            SELECT Id, User__c, User__r.Name, User__r.Email, User__r.Phone, User__r.UserRole.Name, Yearly_Scheme__c
            FROM Grants_Team_Members__c
            WHERE Yearly_Scheme__c IN :schemeNumberById.keySet()
            AND User__c != NULL
        ]) {
            if (!membersBySchemeId.containsKey(member.Yearly_Scheme__c)) {
                membersBySchemeId.put(member.Yearly_Scheme__c, new List<MemberInfo>());
            }
            membersBySchemeId.get(member.Yearly_Scheme__c).add(
                new MemberInfo(
                    member.User__c,
                    member.User__r.Name,
                    member.User__r.Email,
                    member.User__r.Phone,
                    member.User__r.UserRole != null ? member.User__r.UserRole.Name : null,
                    member.Id
                )
            );
        }

        List<SchemeGroup> groups = new List<SchemeGroup>();
        for (Id schemeId : schemeNumberById.keySet()) {
            List<ProposalInfo> proposals = proposalsBySchemeId.get(schemeId);
            groups.add(new SchemeGroup(
                schemeId,
                schemeNumberById.get(schemeId),
                schemeLabelById.get(schemeId),
                proposals.size(),
                membersBySchemeId.containsKey(schemeId) ? membersBySchemeId.get(schemeId) : new List<MemberInfo>(),
                proposals
            ));
        }

        return groups;
    }

    private static Id getNotificationTypeId() {
        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_DEVELOPER_NAME
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    public class SchemeGroup {
        @AuraEnabled public Id schemeId;
        @AuraEnabled public String schemeNumber;
        @AuraEnabled public String schemeLabel;
        @AuraEnabled public Integer proposalCount;
        @AuraEnabled public List<MemberInfo> members;
        @AuraEnabled public List<ProposalInfo> proposals;

        public SchemeGroup(
            Id schemeId,
            String schemeNumber,
            String schemeLabel,
            Integer proposalCount,
            List<MemberInfo> members,
            List<ProposalInfo> proposals
        ) {
            this.schemeId = schemeId;
            this.schemeNumber = schemeNumber;
            this.schemeLabel = schemeLabel;
            this.proposalCount = proposalCount;
            this.members = members;
            this.proposals = proposals;
        }
    }

    public class MemberInfo {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String role;
        @AuraEnabled public Id grantsTeamMemberId;

        public MemberInfo(Id userId, String name, String email, String phone, String role, Id grantsTeamMemberId) {
            this.userId = userId;
            this.name = name;
            this.email = email;
            this.phone = phone;
            this.role = role;
            this.grantsTeamMemberId = grantsTeamMemberId;
        }
    }

    public class ProposalInfo {
        @AuraEnabled public Id proposalId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String submittedBy;
        @AuraEnabled public Date submittedDate;
        @AuraEnabled public String status;

        public ProposalInfo(
            Id proposalId,
            String name,
            String title,
            String submittedBy,
            Date submittedDate,
            String status
        ) {
            this.proposalId = proposalId;
            this.name = name;
            this.title = title;
            this.submittedBy = submittedBy;
            this.submittedDate = submittedDate;
            this.status = status;
        }
    }
}