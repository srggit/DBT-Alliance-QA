/*
 * Called by the React Applicant Portal to exchange a one-time token
 * (minted by PortalSsoController.generateLoginToken, launched from the
 * Proposal record page in Salesforce) for the identity of the applicant
 * it was issued for.
 *
 * POST /services/apexrest/portal/ssoLogin
 * Body: { "token": "..." }
 *
 * Success (200): { "contactId": "...", "email": "...", "name": "...", "proposalId": "..." }
 * Failure (400): { "error": "Invalid or expired token." }
 */
@RestResource(urlMapping='/portal/ssoLogin')
global with sharing class PortalSsoRestService {

    global class TokenRequest {
        public String token;
    }

    global class IdentityResponse {
        public Id contactId;
        public String email;
        public String name;
        public Id proposalId;
    }

    global class ErrorResponse {
        public String error;

        public ErrorResponse(String error) {
            this.error = error;
        }
    }

    @HttpPost
    global static void validateToken() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        TokenRequest body;
        try {
            body = (TokenRequest) JSON.deserialize(req.requestBody.toString(), TokenRequest.class);
        } catch (Exception e) {
            writeError(res, 400, 'Malformed request body.');
            return;
        }

        if (body == null || String.isBlank(body.token)) {
            writeError(res, 400, 'Token is required.');
            return;
        }

        List<Portal_Login_Token__c> tokens = [
            SELECT Id, Contact__c, Contact__r.Email, Contact__r.Name, Proposal__c, Expires_At__c, Used__c
            FROM Portal_Login_Token__c
            WHERE Token__c = :body.token
            LIMIT 1
        ];

        if (tokens.isEmpty()) {
            writeError(res, 400, 'Invalid or expired token.');
            return;
        }

        Portal_Login_Token__c tokenRecord = tokens[0];
        if (tokenRecord.Used__c || tokenRecord.Expires_At__c < Datetime.now()) {
            writeError(res, 400, 'Invalid or expired token.');
            return;
        }

        tokenRecord.Used__c = true;
        update tokenRecord;

        IdentityResponse identity = new IdentityResponse();
        identity.contactId = tokenRecord.Contact__c;
        identity.email = tokenRecord.Contact__r.Email;
        identity.name = tokenRecord.Contact__r.Name;
        identity.proposalId = tokenRecord.Proposal__c;

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(identity));
    }

    private static void writeError(RestResponse res, Integer statusCode, String message) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(message)));
    }
}