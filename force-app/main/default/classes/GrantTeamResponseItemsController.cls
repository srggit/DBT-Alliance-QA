public with sharing class GrantTeamResponseItemsController {

    @AuraEnabled(cacheable=true)
    public static ResponseWrapper getGrantTeamResponseItems(Id proposalId) {
        try {
            if (proposalId == null) {
                throw new AuraHandledException('Proposal Id is required.');
            }

            Id currentUserId = UserInfo.getUserId();

            List<Proposal__c> proposals = [
                SELECT Id, Application_Stages__c, Yearly_Scheme__c
                FROM Proposal__c
                WHERE Id = :proposalId
                LIMIT 1
            ];
            if (proposals.isEmpty()) {
                throw new AuraHandledException('Proposal not found or access denied.');
            }

            String stage = proposals[0].Application_Stages__c;
            Id yearlySchemeId = proposals[0].Yearly_Scheme__c;

            // Grants Team Members are no longer split by Application_Stages__c - one member
            // record per user per scheme now holds a single Grants_Team_Response__c that spans
            // both stages, so there is no stage to match here anymore.
            List<Grants_Team_Members__c> members = [
                SELECT Id
                FROM Grants_Team_Members__c
                WHERE User__c = :currentUserId
                AND Yearly_Scheme__c = :yearlySchemeId
                LIMIT 1
            ];
            if (members.isEmpty()) {
                return new ResponseWrapper(null, new List<Grants_Team_Response_Item__c>(), false);
            }

            List<Grants_Team_Response__c> responses = [
                SELECT Id, Status__c
                FROM Grants_Team_Response__c
                WHERE Proposal__c = :proposalId
                AND Grants_Team_Members__c = :members[0].Id
                LIMIT 1
            ];
            if (responses.isEmpty()) {
                return new ResponseWrapper(null, new List<Grants_Team_Response_Item__c>(), false);
            }

            // The response itself now spans both stages, so "submitted" for the Proposal's
            // current stage means every item belonging to THAT stage has been answered - not
            // the response's overall Status__c, which only reflects whichever stage was
            // completed most recently and would otherwise wrongly lock out the other stage's
            // still-unanswered items (or wrongly unlock an already-answered stage).
            List<Grants_Team_Response_Item__c> items = [
                SELECT Id, Question__c, Name, Type__c, Answer__c, Stage__c
                FROM Grants_Team_Response_Item__c
                WHERE Grants_Team_Response__c = :responses[0].Id
                AND Stage__c = :stage
                ORDER BY Name
            ];

            Boolean isSubmitted = !items.isEmpty();
            for (Grants_Team_Response_Item__c item : items) {
                if (String.isBlank(item.Answer__c)) {
                    isSubmitted = false;
                    break;
                }
            }
            return new ResponseWrapper(responses[0].Id, items, isSubmitted);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching grant team response items: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveGrantTeamResponseItems(List<Grants_Team_Response_Item__c> items, Id responseId) {
        try {
            if (items == null || items.isEmpty()) {
                throw new AuraHandledException('No response items to save.');
            }

            List<Grants_Team_Response_Item__c> toUpdate = new List<Grants_Team_Response_Item__c>();
            for (Grants_Team_Response_Item__c item : items) {
                toUpdate.add(new Grants_Team_Response_Item__c(
                    Id = item.Id,
                    Answer__c = item.Answer__c
                ));
            }
            update toUpdate;

            if (responseId == null) {
                return;
            }

            Boolean hasNo = false;
            for (Grants_Team_Response_Item__c item : items) {
                if (item.Type__c == 'Boolean' && item.Answer__c == 'No') {
                    hasNo = true;
                    break;
                }
            }

            // The response no longer carries its own Stage__c (it spans both stages) - the
            // stage these items belong to is read straight off the items being saved instead,
            // which is always exactly one stage since getGrantTeamResponseItems only ever
            // returns one stage's items at a time.
            String stage = items[0].Stage__c;

            Grants_Team_Response__c response = new Grants_Team_Response__c(Id = responseId);
            response.Status__c = 'Submitted';

            String eligibility = hasNo ? 'Not Eligible' : 'Eligible';
            if (stage == 'Prelims') {
                response.Eligible_For_Prelim__c = eligibility;
            } else if (stage == 'Full') {
                response.Eligible_For_Full__c = eligibility;
            }

            update response;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving grant team response items: ' + e.getMessage());
        }
    }

    public class ResponseWrapper {
        @AuraEnabled public Id responseId;
        @AuraEnabled public List<Grants_Team_Response_Item__c> items;
        @AuraEnabled public Boolean isSubmitted;

        public ResponseWrapper(Id responseId, List<Grants_Team_Response_Item__c> items, Boolean isSubmitted) {
            this.responseId = responseId;
            this.items = items;
            this.isSubmitted = isSubmitted;
        }
    }
}