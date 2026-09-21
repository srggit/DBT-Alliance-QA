public class OTPExpirationJob implements Schedulable {
    private Id recordId;
    
    public OTPExpirationJob(Id recordId) {
        this.recordId = recordId;
    }
    
    public void execute(SchedulableContext sc) {
        // Update the record to make Valid__c false
        OTP_Verification__c recordToUpdate = new OTP_Verification__c(
            Id = this.recordId, 
            Valid__c = false
        );
        update recordToUpdate;
        
        // Abort the job automatically after it executes to keep the queue clean
        System.abortJob(sc.getTriggerId());
    }
}