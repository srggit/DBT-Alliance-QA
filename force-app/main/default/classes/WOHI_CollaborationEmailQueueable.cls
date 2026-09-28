public without sharing class WOHI_CollaborationEmailQueueable
    implements Queueable, Database.AllowsCallouts {
    private List<Id> collaborationIds;
    private Map<Id, String> invitationLinks;
    private String templateDeveloperName;

    public WOHI_CollaborationEmailQueueable( List<Id> collaborationIds, Map<Id, String> invitationLinks,
    String templateDeveloperName ) {
        System.debug('Inside Line 9 WOHI_CollaborationEmailQueueable');
        this.collaborationIds = collaborationIds;
        this.invitationLinks =  invitationLinks;
        this.templateDeveloperName = templateDeveloperName;
    }

    public void execute( QueueableContext context ) {
        if (  collaborationIds == null || collaborationIds.isEmpty() ) {
            return;
        }
        List<WOHI_Collaboration__c> records = [
            SELECT Id,
                   Title__c,
                   FirstName__c,
                   Applicant_Proposal_Association__r.Proposal__r.Proposal_Id__c,
                   Applicant_Proposal_Association__r.Yearly_Scheme__r.Scheme__c, 
            	   Applicant_Proposal_Association__r.Contact__r.Title,
            	   Applicant_Proposal_Association__r.Contact__r.FirstName,
            	   Applicant_Proposal_Association__r.Contact__r.LastName,
                   Last_Name__c,
                   Organisation__c,
                   Email__c,
                   Type__c
            FROM WOHI_Collaboration__c
            WHERE Id IN :collaborationIds
        ];
        List<WOHI_Collaboration__c> recordsToUpdate =
            new List<WOHI_Collaboration__c>();
        for (WOHI_Collaboration__c wc : records) {
            if (String.isBlank(wc.Email__c)) {
                continue;
            }
            String invitationLink = invitationLinks.get(wc.Id);
            Map<String, String> mergeValues =
                new Map<String, String>{
                    'Title' => wc.Title__c,
                    'FirstName' => wc.FirstName__c,
                    'LastName' => wc.Last_Name__c,
                    'ConTitle' => wc.Applicant_Proposal_Association__r.Contact__r.Title,
                    'ConFirstName' => wc.Applicant_Proposal_Association__r.Contact__r.FirstName,
                    'ConLastName' => wc.Applicant_Proposal_Association__r.Contact__r.LastName,
                    'SchemeName' => wc.Applicant_Proposal_Association__r.Yearly_Scheme__r.Scheme__c, 
                    'ProposalId' => wc.Applicant_Proposal_Association__r.Proposal__r.Proposal_Id__c,
                    'Organisation' => wc.Organisation__c,
                    'Email' => wc.Email__c,
                    'InvitationLink' => invitationLink
                };
            System.debug('Merge Value===>'+mergeValues);
            Boolean emailSent = false;
            try {
                HttpResponse response =  SESService.sendEmail( wc.Email__c, templateDeveloperName, mergeValues );
                if ( response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300 ) {
                    emailSent = true;
                    System.debug(  'WOHI invitation email sent successfully. ' +   'Record Id: ' + wc.Id +   ', Email: ' + wc.Email__c + ', Status: ' +  response.getStatusCode());
                } else {
                    System.debug(  'WOHI invitation email failed. ' + 'Record Id: ' + wc.Id + ', Email: ' + wc.Email__c + ', Status: ' + (
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
                System.debug('WOHI invitation email exception. ' +'Record Id: ' + wc.Id + ', Email: ' + wc.Email__c +  ', Error: ' + ex.getMessage());
            }
            recordsToUpdate.add( new WOHI_Collaboration__c( Id = wc.Id, Invitation_Link__c = invitationLink, Notified__c = emailSent ) );
        }
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }
}