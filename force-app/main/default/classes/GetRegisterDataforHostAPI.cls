@RestResource(urlMapping='/registerDataForHost/*')
global class GetRegisterDataforHostAPI {

    @HttpGet
    global static GetRegisterResponse getUser() {

        GetRegisterResponse response = new GetRegisterResponse();

        try {
            String contactId = RestContext.request.params.get('contactId');
            System.debug('contactId param : ' + contactId);

            if (String.isBlank(contactId)) {
                response.success = false;
                response.message = 'contactId parameter is required';
                return response;
            }

            List<Contact> contacts = [
                SELECT Id, Title, Title__c, FirstName, LastName, Gender__c, BirthDate,
                       Nationality__c, Type__c,
                       MailingCity, MailingState, MailingCountry, MailingPostalCode,
                       Phone, MobilePhone, Email, Firebase_UID__c,Password__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            System.debug('contacts : ' + contacts);

            if (contacts.isEmpty()) {
                response.success = false;
                response.message = 'No Contact found for this contactId';
                return response;
            }

            Contact con = contacts[0];

            RegisteredUserWrapper wrapper = new RegisteredUserWrapper();
            wrapper.contactId = con.Id;
            wrapper.title = con.Title;
            wrapper.firstName = con.FirstName;
            wrapper.lastName = con.LastName;
            wrapper.gender = con.Gender__c;
            wrapper.dob = con.BirthDate;
            wrapper.nationality = con.Nationality__c;
           // wrapper.type = con.Type__c;

            wrapper.city = con.MailingCity;
            wrapper.state = con.MailingState;
            wrapper.country = con.MailingCountry;
            wrapper.postalCode = con.MailingPostalCode;

            wrapper.telephoneNumber = con.Phone;
            wrapper.mobilePhone = con.MobilePhone;
            wrapper.email = con.Email;
            wrapper.uid = con.Firebase_UID__c;
			wrapper.password = con.Password__c;
			

            response.success = true;
            response.message = 'Contact Retrieved Successfully';
            response.data = wrapper;

        } catch (Exception e) {

            System.debug('###### e.getMessage : ' + e.getMessage());
            response.success = false;
            response.message = e.getMessage();
        }

        return response;
    }

    global class RegisteredUserWrapper {
        global String contactId;
        global String title;
        global String firstName;
        global String lastName;
        global String gender;
        global Date dob;
        global String nationality;
        //global String type;

        global String city;
        global String state;
        global String country;
        global String postalCode;

        global String telephoneNumber;
        global String mobilePhone;
        global String email;
        global String uid;
		global String password;
    }

    global class GetRegisterResponse {
        global Boolean success;
        global String message;
        global RegisteredUserWrapper data;
    }
}