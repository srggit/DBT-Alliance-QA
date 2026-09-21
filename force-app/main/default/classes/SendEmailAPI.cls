@RestResource(urlMapping='/sendEmail')
global with sharing class SendEmailAPI {
    
    /**
* Request wrapper for incoming JSON.
*/
    global class EmailRequest {
        public String to;
        public String subject;
        public String body;
    }
    
    /**
* Response wrapper.
*/
    global class EmailResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public String responseBody;
    }
    
    /**
* POST
* /services/apexrest/sendEmail
*/
    @HttpPost
    global static EmailResponse sendEmail() {
        
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        EmailResponse response = new EmailResponse();
        
        try {
            
            // Validate request body
            if (req.requestBody == null) {
                throw new AuraHandledException('Request body is required.');
            }
            
            // Deserialize request
            EmailRequest emailRequest =
                (EmailRequest) JSON.deserialize(
                    req.requestBody.toString(),
                    EmailRequest.class
                );
            
            // Validate fields
            if (String.isBlank(emailRequest.to)) {
                throw new AuraHandledException('Recipient email is required.');
            }
            
            if (String.isBlank(emailRequest.subject)) {
                throw new AuraHandledException('Subject is required.');
            }
            
            if (String.isBlank(emailRequest.body)) {
                throw new AuraHandledException('Email body is required.');
            }
            
            // Call SES Service
            HttpResponse awsResponse = SESService.sendEmail(
                emailRequest.to,
                emailRequest.subject,
                emailRequest.body
            );
            
            response.success = awsResponse.getStatusCode() >= 200 &&
                awsResponse.getStatusCode() < 300;
            
            response.statusCode = awsResponse.getStatusCode();
            response.message = awsResponse.getStatus();
            response.responseBody = awsResponse.getBody();
            
            res.statusCode = awsResponse.getStatusCode();
            
        }
        catch (Exception ex) {
            
            response.success = false;
            response.statusCode = 500;
            response.message = ex.getMessage();
            response.responseBody = '';
            
            res.statusCode = 500;
            
            System.debug(
                LoggingLevel.ERROR,
                'SendEmailAPI Error : ' + ex.getMessage()
            );
        }
        
        return response;
    }
}