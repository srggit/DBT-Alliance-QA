public with sharing class PortalSsoController {

    private static final Integer TOKEN_VALID_MINUTES = 5;

    @AuraEnabled
    public static String generateLoginToken(Id proposalId) {
        if (proposalId == null) {
            throw new AuraHandledException('Proposal Id is required.');
        }

        List<Applicant_Proposal_Association__c> associations = [
            SELECT Contact__c
            FROM Applicant_Proposal_Association__c
            WHERE Proposal__c = :proposalId
            AND Contact__c != null
            LIMIT 1
        ];

        if (associations.isEmpty()) {
            throw new AuraHandledException('No applicant Contact found for this proposal.');
        }

        Id contactId = associations[0].Contact__c;
        String token = generateRandomToken();

        insert new Portal_Login_Token__c(
            Token__c = token,
            Contact__c = contactId,
            Proposal__c = proposalId,
            Expires_At__c = Datetime.now().addMinutes(TOKEN_VALID_MINUTES),
            Used__c = false
        );

        return token;
    }

    private static String generateRandomToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    }
}