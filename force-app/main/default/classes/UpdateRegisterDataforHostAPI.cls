@RestResource(urlMapping='/registerDataForHost/update')
global class UpdateRegisterDataforHostAPI {

    @HttpPatch
    global static UpdateRegisterResponse updateUser() {

        UpdateRegisterResponse response = new UpdateRegisterResponse();

        try {
            System.debug('RestContext.request.requestBody.toString() : ' + RestContext.request.requestBody.toString());
            UpdateRegisterRequest req = (UpdateRegisterRequest) JSON.deserialize(RestContext.request.requestBody.toString(), UpdateRegisterRequest.class);

            if (String.isBlank(req.contactId)) {
                response.success = false;
                response.message = 'contactId is required';
                return response;
            }

            List<Contact> contacts = [
                SELECT Id, Title, Title__c, FirstName, LastName, Gender__c, BirthDate,
                       Nationality__c, Type__c,
                       MailingCity, MailingState, MailingCountry, MailingPostalCode,
                       Phone, MobilePhone, Email, Password__c, Password_Hash__c
                FROM Contact
                WHERE Id = :req.contactId
                LIMIT 1
            ];
            System.debug('contacts : ' + contacts);

            if (contacts.isEmpty()) {
                response.success = false;
                response.message = 'No Contact found for this contactId';
                return response;
            }

            Contact con = contacts[0];

            // Only update fields that were actually sent (non-null in payload)
            if (req.title != null)          { con.Title = req.title; con.Title__c = req.title; }
            if (req.firstName != null)      con.FirstName = req.firstName;
            if (req.lastName != null)       con.LastName = req.lastName;
            if (req.gender != null)         con.Gender__c = req.gender;
            if (req.dob != null)            con.BirthDate = req.dob;
            if (req.nationality != null)    con.Nationality__c = req.nationality;
            if (req.type != null)           con.Type__c = req.type;

            if (req.city != null)           con.MailingCity = req.city;
            if (req.state != null)          con.MailingState = req.state;
            if (req.country != null)        con.MailingCountry = req.country;
            if (req.postalCode != null)     con.MailingPostalCode = req.postalCode;

            if (req.telephoneNumber != null) {
                con.Phone = req.telephoneNumber;
                con.MobilePhone = req.telephoneNumber;
            }
            if (req.email != null)          con.Email = req.email;

            // Only rehash if a new password was actually supplied
            if (String.isNotBlank(req.password)) {
                con.Password__c = req.password;
                con.Password_Hash__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(req.password)));
            }

            update con;

            response.success = true;
            response.message = 'Contact Updated Successfully';
            response.contactId = con.Id;

        } catch (Exception e) {

            System.debug('###### e.getMessage : ' + e.getMessage());
            response.success = false;
            response.message = e.getMessage();
        }

        return response;
    }

    global class UpdateRegisterRequest {
        global String contactId;

        global String title;
        global String firstName;
        global String lastName;
        global String gender;
        global Date dob;
        global String nationality;
        global String type;

        global String city;
        global String state;
        global String country;
        global String postalCode;

        global String telephoneNumber;
        global String email;
        global String password;
    }

    global class UpdateRegisterResponse {
        global Boolean success;
        global String message;
        global String contactId;
    }
}