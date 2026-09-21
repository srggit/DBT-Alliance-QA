trigger OTPVerificationTrigger on OTP_Verification__c (before insert, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        OTPVerificationHandler.generateOTP(Trigger.new);
    }
    if(Trigger.isAfter && Trigger.isInsert){
        OTPVerificationHandler.sendOTPEmails(Trigger.new);
    }

}