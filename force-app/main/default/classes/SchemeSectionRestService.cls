@RestResource(urlMapping='/SchemeSectionRestService/*')
global with sharing class SchemeSectionRestService {

    global class RequestWrapper {
        public String schemeSectionId;
        public String rating;
        public String overallComments;
        public String reviewerMappingStatus;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public String schemeSectionId;
        public String reviewerMappingId;

        public ResponseWrapper(Boolean success, String message, String schemeSectionId, String reviewerMappingId) {
            this.success = success;
            this.message = message;
            this.schemeSectionId = schemeSectionId;
            this.reviewerMappingId = reviewerMappingId;
        }
    }

    @HttpPatch
    global static void updateSchemeSectionAndReviewer() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            // Parse JSON body (may be empty if only query params are sent)
            RequestWrapper data = new RequestWrapper();
            String requestBody = req.requestBody != null ? req.requestBody.toString() : null;
            if (String.isNotBlank(requestBody)) {
                data = (RequestWrapper) JSON.deserialize(requestBody, RequestWrapper.class);
            }

            // Priority: query param > body field > trailing URL path segment
            String targetId = req.params.get('schemeSectionId');
            if (String.isBlank(targetId)) targetId = data.schemeSectionId;
            if (String.isBlank(targetId)) {
                String path = req.requestURI;
                String lastSegment = path.substring(path.lastIndexOf('/') + 1);
                if (lastSegment.startsWith('a1Y') || lastSegment.length() == 15 || lastSegment.length() == 18) {
                    targetId = lastSegment;
                }
            }

            if (String.isBlank(targetId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ResponseWrapper(false, 'Scheme Section ID is required.', null, null)
                ));
                return;
            }

            List<Scheme_Section__c> sectionList = [
                SELECT Id, Rating__c, Overall_Comments__c, Status__c, Reviewer_Mapping__c 
                FROM Scheme_Section__c 
                WHERE Id = :targetId 
                LIMIT 1
            ];

            if (sectionList.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ResponseWrapper(false, 'Scheme_Section__c record not found.', null, null)
                ));
                return;
            }

            Scheme_Section__c sectionToUpdate = sectionList[0];

            if (String.isNotBlank(data.rating)) sectionToUpdate.Rating__c = data.rating;
            if (String.isNotBlank(data.overallComments)) sectionToUpdate.Overall_Comments__c = data.overallComments;

            update sectionToUpdate;

            String parentReviewerId = sectionToUpdate.Reviewer_Mapping__c;
            if (String.isNotBlank(data.reviewerMappingStatus) && String.isNotBlank(parentReviewerId)) {
                Reviewer_Mapping__c reviewerToUpdate = new Reviewer_Mapping__c(
                    Id = parentReviewerId,
                    Status__c = data.reviewerMappingStatus
                );
                update reviewerToUpdate;
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ResponseWrapper(true, 'Scheme Section and Reviewer Mapping updated successfully.', sectionToUpdate.Id, parentReviewerId)
            ));

        } catch (Exception ex) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ResponseWrapper(false, 'Error: ' + ex.getMessage(), null, null)
            ));
        }
    }
}