trigger PatentTrigger on Patents__c (after insert) {
if (Trigger.isAfter && Trigger.isInsert) {
        // Handler respects GenericApplicantAssociationHandler.bypassAssociationSync
        // (set by APIs that insert both APA-tagged and Contact-tagged records themselves)

        GenericApplicantAssociationHandler.syncAssociationRecords(
            'Patents__c',
            Trigger.new
        );
    }
}