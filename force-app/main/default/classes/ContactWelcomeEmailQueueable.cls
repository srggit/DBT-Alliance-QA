public without sharing class ContactWelcomeEmailQueueable
    implements Queueable, Database.AllowsCallouts {

    private List<Id> contactIds;
    private String templateDeveloperName;

    public ContactWelcomeEmailQueueable(
        List<Id> contactIds,
        String templateDeveloperName
    ) {
        this.contactIds = contactIds;
        this.templateDeveloperName = templateDeveloperName;
    }

    public void execute(QueueableContext context) {

        if (contactIds == null || contactIds.isEmpty()) {
            return;
        }

        List<Contact> contacts = [
            SELECT Id,Salutation,Title__c,
                   FirstName,
                   LastName,
                   Email
            FROM Contact
            WHERE Id IN :contactIds
        ];

        for (Contact con : contacts) {

            if (String.isBlank(con.Email)) {
                continue;
            }

            Map<String, String> mergeValues =
                new Map<String, String>{
                    'Applicant_Name'  => buildApplicantName(con),
                    'Applicant_Email' => con.Email
                };

            System.debug(
                'Welcome Email Merge Values => ' + mergeValues
            );

            try {

                HttpResponse response = SESService.sendEmail(
                    con.Email,
                    templateDeveloperName,
                    mergeValues
                );

                if (
                    response != null &&
                    response.getStatusCode() >= 200 &&
                    response.getStatusCode() < 300
                ) {

                    System.debug(
                        'Contact welcome email sent successfully. ' +
                        'Contact Id: ' + con.Id +
                        ', Email: ' + con.Email +
                        ', Status: ' + response.getStatusCode()
                    );

                } else {

                    System.debug(
                        'Contact welcome email failed. ' +
                        'Contact Id: ' + con.Id +
                        ', Email: ' + con.Email +
                        ', Status: ' +
                        (
                            response == null
                                ? 'NULL'
                                : String.valueOf(
                                    response.getStatusCode()
                                )
                        ) +
                        ', Body: ' +
                        (
                            response == null
                                ? ''
                                : response.getBody()
                        )
                    );
                }

            } catch (Exception ex) {

                System.debug(
                    'Contact welcome email exception. ' +
                    'Contact Id: ' + con.Id +
                    ', Email: ' + con.Email +
                    ', Error: ' + ex.getMessage()
                );
            }
        }
    }

    private static String buildApplicantName(Contact con) {

        List<String> nameParts = new List<String>();
        String titleValue;
        
        if (String.isNotBlank(con.Salutation)) 
        { 
            titleValue = con.Salutation;
        } else if (String.isNotBlank(con.Title__c))
        {
            titleValue = con.Title__c;
        }
        if (String.isNotBlank(titleValue)) { nameParts.add(titleValue); }

        if (String.isNotBlank(con.FirstName)) {
            nameParts.add(con.FirstName);
        }

        if (String.isNotBlank(con.LastName)) {
            nameParts.add(con.LastName);
        }

        return String.join(nameParts, ' ');
    }
}