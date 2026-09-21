@RestResource(urlMapping='/getNotificationDetails')
global with sharing class getNotificationDetails {

    @HttpGet
    global static ResponseWrapper getNotifications() {

        ResponseWrapper response = new ResponseWrapper();

        try {
            String contactId = RestContext.request.params.get('contactId');
            String reviewerId = RestContext.request.params.get('reviewerId');

            if (String.isBlank(contactId) && String.isBlank(reviewerId)) {
                response.success = false;
                response.message = 'Contact ID or Reviewer ID is required';
                return response;
            }

            Date today = Date.today();

            List<Notification__c> notifications;

            if (!String.isBlank(contactId)) {
                notifications = [
                    SELECT Id, Title__c, Description__c, Expiry_Date__c,
                           Yearly_Schemes__c, For_All__c, Contact__c
                    FROM Notification__c
                    WHERE Expiry_Date__c > :today
                    AND Contact__c = :contactId
                ];
            } else {
                notifications = [
                    SELECT Id, Title__c, Description__c, Expiry_Date__c,
                           Yearly_Schemes__c, For_All__c, Contact__c
                    FROM Notification__c
                    WHERE Expiry_Date__c > :today
                    AND Reviewer__c = :reviewerId
                ];
            }

            Set<Id> notificationIds = new Set<Id>();
            for (Notification__c n : notifications) {
                notificationIds.add(n.Id);
            }

            Map<Id, Notification_Status__c> statusByNotificationId = new Map<Id, Notification_Status__c>();

            if (!notificationIds.isEmpty()) {

                if (!String.isBlank(contactId)) {
                    for (Notification_Status__c status : [
                        SELECT Id, Status__c, Notification__c
                        FROM Notification_Status__c
                        WHERE Contact__c = :contactId
                        AND Notification__c IN :notificationIds
                    ]) {
                        statusByNotificationId.put(status.Notification__c, status);
                    }
                } else {
                    for (Notification_Status__c status : [
                        SELECT Id, Status__c, Notification__c
                        FROM Notification_Status__c
                        WHERE Reviewer__c = :reviewerId
                        AND Notification__c IN :notificationIds
                    ]) {
                        statusByNotificationId.put(status.Notification__c, status);
                    }
                }
            }

            List<NotificationResult> result = new List<NotificationResult>();

            for (Notification__c n : notifications) {
                Notification_Status__c existingStatus = statusByNotificationId.get(n.Id);
                String currentStatus = (existingStatus != null) ? existingStatus.Status__c : 'Unread';
                Id statusId = (existingStatus != null) ? existingStatus.Id : null;

                if (currentStatus == 'Unread') {
                    result.add(new NotificationResult(n, currentStatus, statusId));
                }
            }

            response.success = true;
            response.message = result.isEmpty() ? 'No notifications found.' : 'Notifications found.';
            response.notifications = result;

        } catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();
        }
        System.debug('Response-->'+response);

        return response;
    }

    // Response Wrapper
    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public List<NotificationResult> notifications;
    }

    // Data Wrapper
    global class NotificationResult {
        public Id notificationId;
        public Id notificationStatusId;
        public String title;
        public String description;
        public Date expiryDate;
        public Id schemeId;
        public Boolean forAll;
        public String status;

        public NotificationResult(Notification__c n, String status, Id statusId) {
            this.notificationId = n.Id;
            this.notificationStatusId = statusId;
            this.title = n.Title__c;
            this.description = n.Description__c;
            this.expiryDate = n.Expiry_Date__c;
            this.schemeId = n.Yearly_Schemes__c;
            this.forAll = n.For_All__c;
            this.status = status;
        }
    }
}