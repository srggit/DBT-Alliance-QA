public with sharing class AWSConfigService {

    public static AWS_Configuration__mdt getConfig() {

        AWS_Configuration__mdt config =
            AWS_Configuration__mdt.getInstance('Default');

        if (config == null) {
            throw new AuraHandledException(
                'AWS Configuration metadata not found.'
            );
        }

        return config;
    }
}