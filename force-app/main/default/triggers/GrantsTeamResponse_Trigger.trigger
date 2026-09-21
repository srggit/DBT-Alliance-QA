trigger GrantsTeamResponse_Trigger on Grants_Team_Response__c (after update,before update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        GrantsTeamResponseHandler.updateProposalStatus(Trigger.new, Trigger.oldMap);
        GrantsTeamResponseHandler.grantTeamMemberChange(Trigger.new, Trigger.oldMap, false);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        GrantsTeamResponseHandler.grantTeamMemberChange(Trigger.new, Trigger.oldMap, true);
    }
}