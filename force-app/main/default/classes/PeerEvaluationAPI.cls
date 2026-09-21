@RestResource(urlMapping='/peerEvaluation/*')
global without sharing class PeerEvaluationAPI {

    @HttpPost
    global static ResponseWrapper doPost() {
        ResponseWrapper response = new ResponseWrapper();

        try {
            RestRequest req = RestContext.request;

            if (req == null || req.requestBody == null) {
                response.success = false;
                response.message = 'Request body is required';
                return response;
            }

            String body = req.requestBody.toString();
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);

            String question = (String) payload.get('question');
            String description = (String) payload.get('description');
            String answer = (String) payload.get('answer');

            if (String.isBlank(question) || String.isBlank(answer)) {
                response.success = false;
                response.message = 'question and answer are required fields';
                return response;
            }

            Peer_Evaluation__c record = new Peer_Evaluation__c();
            record.Question__c = question;
            record.Description__c = description;
            record.Answer__c = answer;

            insert record;

            response.success = true;
            response.message = 'Peer Evaluation record created successfully';
            response.recordId = record.Id;
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
        }

        return response;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public String recordId;
    }
}