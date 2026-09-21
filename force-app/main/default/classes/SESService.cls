public with sharing class SESService {
    
    private static AWS_Configuration__mdt getConfig() {
        AWS_Configuration__mdt config = AWS_Configuration__mdt.getInstance('Default');
        
        if (config == null) {
            throw new AuraHandledException(
                'AWS SES configuration record "Default" was not found.'
            );
        }
        
        if (
            String.isBlank(config.Access_Key__c) ||
            String.isBlank(config.Secret_Key__c) ||
            String.isBlank(config.Region__c) ||
            String.isBlank(config.SES_Endpoint__c) ||
            String.isBlank(config.From_Email__c)
        ) {
            throw new AuraHandledException(
                'AWS SES configuration is incomplete.'
            );
        }
        
        return config;
    }
    
    private static String sha256Hex(String value) {
        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(value == null ? '' : value)
        );
        
        return blobToHex(digest);
    }
    
    private static Blob hmacSHA256(Blob key, String data) {
        if (key == null) {
            throw new AuraHandledException('HMAC key is required.');
        }
        
        return Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(data == null ? '' : data),
            key
        );
    }
    
    private static String blobToHex(Blob value) {
        if (value == null) {
            throw new AuraHandledException('Blob value is required.');
        }
        
        return EncodingUtil.convertToHex(value).toLowerCase();
    }
    
    private static String getAmzDate() {
        return Datetime.now().formatGMT('yyyyMMdd\'T\'HHmmss\'Z\'');
    }
    
    private static String getDateStamp() {
        return Datetime.now().formatGMT('yyyyMMdd');
    }
    
    private static Blob getSignatureKey(
        String secretKey,
        String dateStamp,
        String region,
        String service
    ) {
        Blob kSecret = Blob.valueOf('AWS4' + secretKey);
        Blob kDate = hmacSHA256(kSecret, dateStamp);
        Blob kRegion = hmacSHA256(kDate, region);
        Blob kService = hmacSHA256(kRegion, service);
        
        return hmacSHA256(kService, 'aws4_request');
    }
    
    private static String buildCanonicalRequest(
        String amzDate,
        String payloadHash,
        String host
    ) {
        List<String> lines = new List<String>();
        
        lines.add('POST');
        lines.add('/v2/email/outbound-emails');
        lines.add('');
        lines.add('content-type:application/json');
        lines.add('host:' + host);
        lines.add('x-amz-date:' + amzDate);
        lines.add('');
        lines.add('content-type;host;x-amz-date');
        lines.add(payloadHash);
        
        return String.join(lines, '\n');
    }
    
    private static String buildStringToSign(
        String amzDate,
        String dateStamp,
        String region,
        String canonicalRequest
    ) {
        String credentialScope =
            dateStamp + '/' +
            region + '/' +
            'ses/aws4_request';
        
        return String.join(
            new List<String>{
                'AWS4-HMAC-SHA256',
                amzDate,
                credentialScope,
                sha256Hex(canonicalRequest)
            },
            '\n'
        );
    }
    
    private static String generateSignature(
        String stringToSign,
        Blob signingKey
    ) {
        return blobToHex(hmacSHA256(signingKey, stringToSign));
    }
    
    private static String buildAuthorizationHeader(
        String accessKey,
        String dateStamp,
        String region,
        String signature
    ) {
        String credentialScope =
            dateStamp + '/' +
            region + '/' +
            'ses/aws4_request';
        
        return
            'AWS4-HMAC-SHA256 ' +
            'Credential=' + accessKey + '/' + credentialScope +
            ', SignedHeaders=content-type;host;x-amz-date' +
            ', Signature=' + signature;
    }
    
    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        
        return value
            .replace('&', '&​amp;')
            .replace('<', '&​lt;')
            .replace('>', '&​gt;')
            .replace('"', '&​quot;')
            .replace('\'', '&​#39;');
    }
    private static HttpRequest buildRequest(
        String to,
        String subject,
        String htmlBody
    ) {
        AWS_Configuration__mdt config = getConfig();
        
        //String htmlBody = buildProfessionalEmailHtml(subject, body);
        
        Map<String, Object> payload = new Map<String, Object>{
            'FromEmailAddress' => config.From_Email__c,
            
            'Destination' => new Map<String, Object>{
                'ToAddresses' => new List<String>{ to }
            },
            
            'Content' => new Map<String, Object>{
                'Simple' => new Map<String, Object>{
                    'Subject' => new Map<String, String>{
                        'Data' => subject,
                        'Charset' => 'UTF-8'
                    },
                    
                    'Body' => new Map<String, Object>{
                        'Html' => new Map<String, String>{
                            'Data' => htmlBody,
                            'Charset' => 'UTF-8'
                        }
                    }
                }
            }
        };
        
        String requestBody = JSON.serialize(payload);
        
        String amzDate = getAmzDate();
        String dateStamp = getDateStamp();
        String payloadHash = sha256Hex(requestBody);
        
        String host = config.SES_Endpoint__c
            .replace('https://', '')
            .replace('http://', '');
        
        if (host.contains('/')) {
            host = host.substring(0, host.indexOf('/'));
        }
        
        String canonicalRequest = buildCanonicalRequest(
            amzDate,
            payloadHash,
            host
        );
        
        String stringToSign = buildStringToSign(
            amzDate,
            dateStamp,
            config.Region__c,
            canonicalRequest
        );
        
        Blob signingKey = getSignatureKey(
            config.Secret_Key__c,
            dateStamp,
            config.Region__c,
            'ses'
        );
        
        String signature = generateSignature(
            stringToSign,
            signingKey
        );
        
        String authorizationHeader = buildAuthorizationHeader(
            config.Access_Key__c,
            dateStamp,
            config.Region__c,
            signature
        );
        
        String endpoint = config.SES_Endpoint__c;
        
        if (endpoint.endsWith('/')) {
            endpoint = endpoint.substring(0, endpoint.length() - 1);
        }
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint + '/v2/email/outbound-emails');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Host', host);
        request.setHeader('X-Amz-Date', amzDate);
        request.setHeader('Authorization', authorizationHeader);
        request.setBody(requestBody);
        
        return request;
    }
    
    public static HttpResponse sendEmail(
        String to,
        String templateDeveloperName,
        Map<String, String> mergeValues
    ) {
        if (String.isBlank(to)) {
            throw new AuraHandledException(
                'Recipient email is required.'
            );
        }

        if (String.isBlank(templateDeveloperName)) {
            throw new AuraHandledException(
                'Email template DeveloperName is required.'
            );
        }

        EmailTemplate template;

        try {
            template = [
                SELECT Id,
                    Subject,
                    HtmlValue
                FROM EmailTemplate
                WHERE DeveloperName = :templateDeveloperName
                LIMIT 1
            ];
        } catch (QueryException ex) {
            throw new AuraHandledException(
                'Email template "' +
                templateDeveloperName +
                '" was not found.'
            );
        }

        String subject = template.Subject;
        String htmlBody = template.HtmlValue;

        if (mergeValues != null) {

            for (String key : mergeValues.keySet()) {

                String value = mergeValues.get(key);

                if (value == null) {
                    value = '';
                }

                htmlBody = htmlBody.replace(
                    '{{' + key + '}}',
                    escapeHtml(value)
                );

                subject = subject.replace(
                    '{{' + key + '}}',
                    value
                );
            }
        }

        try {

            Http http = new Http();

            return http.send(
                buildRequest(
                    to,
                    subject,
                    htmlBody
                )
            );

        } catch (Exception ex) {

            throw new AuraHandledException(
                'Failed to send email using AWS SES. ' +
                ex.getMessage()
            );
        }
    }
}