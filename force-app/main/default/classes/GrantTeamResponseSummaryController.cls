public with sharing class GrantTeamResponseSummaryController {

    public class MemberColumn {
        @AuraEnabled public String memberId;
        @AuraEnabled public String responseId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
    }

    public class AnswerCell {
        @AuraEnabled public String value;
        @AuraEnabled public String responseId;
        @AuraEnabled public Boolean isYes;
        @AuraEnabled public Boolean isNo;
        @AuraEnabled public Boolean isAnswered;
        @AuraEnabled public Boolean isNotSubmitted;
    }

    public class QuestionRow {
        @AuraEnabled public String question;
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public List<AnswerCell> answers;
    }

    public class StageSummary {
        @AuraEnabled public String stage;
        @AuraEnabled public String subtitle;
        @AuraEnabled public Integer answeredCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public String answeredLabel;
        @AuraEnabled public String badgeClass;
        @AuraEnabled public String badgeIcon;
        @AuraEnabled public String cardClass;
        @AuraEnabled public String themeClass;
        @AuraEnabled public String headerIcon;
        @AuraEnabled public String iconClass;
        @AuraEnabled public List<MemberColumn> members;
        @AuraEnabled public List<QuestionRow> rows;
    }

    public class SummaryResult {
        @AuraEnabled public String proposalApplicationStage;
        @AuraEnabled public List<StageSummary> stages;
    }

    @AuraEnabled(cacheable=true)
    public static SummaryResult getResponseSummary(Id proposalId) {
        SummaryResult result = new SummaryResult();
        result.stages = new List<StageSummary>();

        if (proposalId == null) {
            return result;
        }

        List<Proposal__c> proposals = [
            SELECT Id, Application_Stages__c, Yearly_Scheme__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];
        if (proposals.isEmpty()) {
            return result;
        }

        Proposal__c proposal = proposals[0];
        result.proposalApplicationStage = proposal.Application_Stages__c;

        // Show only the section matching the Proposal's current stage - once it's at Full,
        // the Prelims section (already decided) no longer needs to be shown alongside it.
        List<String> stages = proposal.Application_Stages__c == 'Full'
            ? new List<String>{ 'Full' }
            : new List<String>{ 'Prelims' };

        if (proposal.Yearly_Scheme__c == null) {
            return result;
        }

        for (String stage : stages) {
            StageSummary stageSummary = new StageSummary();
            stageSummary.stage = stage;
            stageSummary.members = new List<MemberColumn>();
            stageSummary.rows = new List<QuestionRow>();

            // Grants Team Members are no longer split by stage - the same response record
            // (one per member) is shared across both the Prelims and Full stage columns here,
            // so no Stage__c filter is applied; resolveResponseStatus below reads whichever of
            // Eligible_For_Prelim__c/Eligible_For_Full__c applies to this stage.
            List<Grants_Team_Response__c> responses = [
                SELECT Id,
                       Grants_Team_Members__c,
                       Grants_Team_Members__r.User__c,
                       Grants_Team_Members__r.User__r.Name,
                       Grants_Team_Members__r.Grants_Team_Member_Id__c,
                       Status__c,
                       Eligible_For_Prelim__c,
                       Eligible_For_Full__c
                FROM Grants_Team_Response__c
                WHERE Proposal__c = :proposalId
            ];

            Map<Id, MemberColumn> memberByResponse = new Map<Id, MemberColumn>();
            for (Grants_Team_Response__c resp : responses) {
                MemberColumn col = new MemberColumn();
                col.memberId = resp.Grants_Team_Members__c;
                col.responseId = resp.Id;
                col.name = resolveMemberName(resp);
                col.status = resolveResponseStatus(resp, stage);
                stageSummary.members.add(col);
                memberByResponse.put(resp.Id, col);
            }

            // Group response items by the Eligibility_Check_List__c they answer (a real lookup,
            // immune to the question wording being edited later). Records inserted before this
            // lookup existed won't have it populated, so itemsByQuestionTextFallback keeps the
            // old text-based match as a fallback for that legacy data only.
            Map<Id, List<Grants_Team_Response_Item__c>> itemsByChecklistId = new Map<Id, List<Grants_Team_Response_Item__c>>();
            Map<String, List<Grants_Team_Response_Item__c>> itemsByQuestionTextFallback = new Map<String, List<Grants_Team_Response_Item__c>>();
            if (!memberByResponse.isEmpty()) {
                for (Grants_Team_Response_Item__c item : [
                    SELECT Id, Eligibility_Check_List__c, Question__c, Answer__c, Grants_Team_Response__c
                    FROM Grants_Team_Response_Item__c
                    WHERE Grants_Team_Response__c IN :memberByResponse.keySet()
                ]) {
                    if (item.Eligibility_Check_List__c != null) {
                        if (!itemsByChecklistId.containsKey(item.Eligibility_Check_List__c)) {
                            itemsByChecklistId.put(item.Eligibility_Check_List__c, new List<Grants_Team_Response_Item__c>());
                        }
                        itemsByChecklistId.get(item.Eligibility_Check_List__c).add(item);
                    } else {
                        if (!itemsByQuestionTextFallback.containsKey(item.Question__c)) {
                            itemsByQuestionTextFallback.put(item.Question__c, new List<Grants_Team_Response_Item__c>());
                        }
                        itemsByQuestionTextFallback.get(item.Question__c).add(item);
                    }
                }
            }

            // Use the original Eligibility_Check_List__c records to define question order.
            List<Eligibility_Check_List__c> checklists = [
                SELECT Id, Display_Question__c, Stage__c
                FROM Eligibility_Check_List__c
                WHERE Yearly_Scheme__c = :proposal.Yearly_Scheme__c
                AND Stage__c = :stage
                ORDER BY Name
            ];

            Integer rowNumber = 1;
            for (Eligibility_Check_List__c ecl : checklists) {
                QuestionRow row = new QuestionRow();
                row.rowNumber = rowNumber++;
                row.question = ecl.Display_Question__c;
                row.answers = new List<AnswerCell>();

                List<Grants_Team_Response_Item__c> items = itemsByChecklistId.get(ecl.Id);
                if (items == null) {
                    items = itemsByQuestionTextFallback.get(ecl.Display_Question__c);
                }
                for (MemberColumn col : stageSummary.members) {
                    AnswerCell cell = new AnswerCell();
                    cell.responseId = col.responseId;
                    if (items != null) {
                        for (Grants_Team_Response_Item__c it : items) {
                            if (it.Grants_Team_Response__c == col.responseId) {
                                if ('Yes'.equalsIgnoreCase(it.Answer__c)) {
                                    cell.isYes = true;
                                    cell.value = 'Yes';
                                } else if ('No'.equalsIgnoreCase(it.Answer__c)) {
                                    cell.isNo = true;
                                    cell.value = 'No';
                                } else if (String.isNotBlank(it.Answer__c)) {
                                    cell.isAnswered = true;
                                    cell.value = it.Answer__c;
                                }
                                break;
                            }
                        }
                    }
                    if (cell.value == null) {
                        cell.isNotSubmitted = true;
                        cell.value = 'Not Submitted';
                    }
                    row.answers.add(cell);
                }

                stageSummary.rows.add(row);
            }

            stageSummary.totalCount = stageSummary.rows.size();
            stageSummary.answeredCount = 0;
            for (QuestionRow r : stageSummary.rows) {
                for (AnswerCell cell : r.answers) {
                    if (cell.isYes == true || cell.isNo == true || cell.isAnswered == true) {
                        stageSummary.answeredCount++;
                        break;
                    }
                }
            }
            stageSummary.answeredLabel = stageSummary.answeredCount + ' of ' + stageSummary.totalCount + ' answered';
            if (stage == 'Prelims') {
                stageSummary.badgeClass = 'slds-badge prelims-badge';
                stageSummary.badgeIcon = 'action:check';
                stageSummary.themeClass = 'prelims-theme';
                stageSummary.subtitle = 'Eligibility responses reviewed during the prelims stage.';
            } else if (stage == 'Full') {
                stageSummary.badgeClass = 'slds-badge full-badge';
                stageSummary.badgeIcon = 'utility:clock';
                stageSummary.themeClass = 'full-theme';
                stageSummary.subtitle = 'Eligibility responses reviewed during the full application stage.';
            } else {
                stageSummary.badgeClass = 'slds-badge slds-theme_default';
                stageSummary.badgeIcon = 'utility:clock';
                stageSummary.themeClass = 'default-theme';
                stageSummary.subtitle = 'Eligibility responses reviewed during the ' + stage + ' stage.';
            }
            stageSummary.cardClass = 'slds-card slds-m-top_medium ' + stageSummary.themeClass;
            stageSummary.headerIcon = 'utility:checklist';
            stageSummary.iconClass = 'slds-m-right_small ' + stageSummary.themeClass + '-icon';

            result.stages.add(stageSummary);
        }

        return result;
    }

    private static String resolveMemberName(Grants_Team_Response__c resp) {
        if (resp.Grants_Team_Members__r == null) {
            return 'Unknown';
        }
        if (resp.Grants_Team_Members__r.User__r != null &&
            String.isNotBlank(resp.Grants_Team_Members__r.User__r.Name)) {
            return resp.Grants_Team_Members__r.User__r.Name;
        }
        if (String.isNotBlank(resp.Grants_Team_Members__r.Grants_Team_Member_Id__c)) {
            return resp.Grants_Team_Members__r.Grants_Team_Member_Id__c;
        }
        return 'Unknown';
    }

    // A single response now spans both stages, so the response's overall Status__c ('Pending'
    // vs 'Submitted') no longer tells you whether THIS stage specifically has been answered -
    // that stage's own Eligible_For_Prelim__c/Eligible_For_Full__c field (set independently as
    // that stage's items are completed) is the only reliable per-stage "submitted" signal.
    private static String resolveResponseStatus(Grants_Team_Response__c resp, String stage) {
        if (stage == 'Prelims') {
            return String.isNotBlank(resp.Eligible_For_Prelim__c) ? resp.Eligible_For_Prelim__c : 'Not Submitted';
        }
        if (stage == 'Full') {
            return String.isNotBlank(resp.Eligible_For_Full__c) ? resp.Eligible_For_Full__c : 'Not Submitted';
        }
        return '';
    }
}