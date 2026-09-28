public without sharing class Refferee_EmailQueueable 
  implements Queueable, Database.AllowsCallouts {
    private List<Id> additionalParticipantIds;
    private Map<Id, String> invitationLinks;
    private String templateDeveloperName;

    public Refferee_EmailQueueable( List<Id> additionalParticipantIds, Map<Id, String> invitationLinks,
    String templateDeveloperName ) {
        this.additionalParticipantIds = additionalParticipantIds;
        this.invitationLinks =  invitationLinks;
        this.templateDeveloperName = templateDeveloperName;
    }

    public void execute( QueueableContext context ) {
        if (  additionalParticipantIds == null || additionalParticipantIds.isEmpty() ) {
            return;
        }
        List<Additional_Partcipant__c> records = [
            SELECT Id,
                   Title__c,
                   First_Name__c,
                   Proposal__r.Proposal_Id__c,
                   Proposal__r.Yearly_Scheme__r.Scheme__c, 
                   Last_Name__c,
                   Organisation__c,
                   Email__c,
                   Roles__c,
				   Email_Sent__c
            FROM Additional_Partcipant__c
            WHERE Id IN :additionalParticipantIds
        ];
        List<Additional_Partcipant__c> recordsToUpdate =
            new List<Additional_Partcipant__c>();
        for (Additional_Partcipant__c ap : records) {
            if (String.isBlank(ap.Email__c)) {
                continue;
            }
            String invitationLink = invitationLinks.get(ap.Id);
            Map<String, String> mergeValues =
                new Map<String, String>{
                    'Title' => ap.Title__c,
                    'FirstName' => ap.First_Name__c,
                    'LastName' => ap.Last_Name__c,
                    'SchemeName' => ap.Proposal__r.Yearly_Scheme__r.Scheme__c, 
                    'ProposalId' => ap.Proposal__r.Proposal_Id__c,
                    'Organisation' => ap.Organisation__c,
                    'Email' => ap.Email__c,
                    'InvitationLink' => invitationLink
                };
            System.debug('Merge Value===>'+mergeValues);
            Boolean emailSent = false;
            try {
                HttpResponse response =  SESService.sendEmail( ap.Email__c, templateDeveloperName, mergeValues );
                if ( response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300 ) {
                    emailSent = true;
                    System.debug(  'WOHI invitation email sent successfully. ' +   'Record Id: ' + ap.Id +   ', Email: ' + ap.Email__c + ', Status: ' +  response.getStatusCode());
                } else {
                    System.debug(  'WOHI invitation email failed. ' + 'Record Id: ' + ap.Id + ', Email: ' + ap.Email__c + ', Status: ' + (
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
                System.debug('WOHI invitation email exception. ' +'Record Id: ' + ap.Id + ', Email: ' + ap.Email__c +  ', Error: ' + ex.getMessage());
            }
            recordsToUpdate.add( new Additional_Partcipant__c( Id = ap.Id, 
           // Invitation_Link__c = invitationLink, 
            Email_Sent__c = emailSent ) );
        }
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
   }
}