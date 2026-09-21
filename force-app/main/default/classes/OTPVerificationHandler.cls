public class OTPVerificationHandler {
    
    // Generates a 6-digit OTP and sets Valid__c to true
    public static void generateOTP(List<OTP_Verification__c> newRecords) {
        for(OTP_Verification__c otpRec : newRecords) {
            // Generate a random number between 100000 and 999999
            Integer randomOTP = Math.round(Math.random() * (999999 - 100000)) + 100000;
            otpRec.OTP__c = randomOTP;
            otpRec.Valid__c = true;
        }
    }

    public static void sendOTPEmails(List<OTP_Verification__c> newRecords) {

        List<Id> otpIds = new List<Id>();

        for (OTP_Verification__c otpRec : newRecords) {

            if (String.isBlank(otpRec.Email__c)) {
                continue;
            }

            otpIds.add(otpRec.Id);
        }

        if (otpIds.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new EmailNotificationQueueable(
                'OTP_VERIFICATION',
                otpIds,
                'OTP_Verification_Email'
            )
        );
    }
}