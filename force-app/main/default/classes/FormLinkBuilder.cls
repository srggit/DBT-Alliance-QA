public with sharing class FormLinkBuilder {
    public static final String PORTAL_BASE_URL;

    static {
        URL_s__mdt reactSiteLink = URL_s__mdt.getInstance('React_Site_Link');
        String reactBaseUrl = (reactSiteLink != null && String.isNotBlank(reactSiteLink.URL_Value__c)) ? reactSiteLink.URL_Value__c : '';
        if (String.isNotBlank(reactBaseUrl) && !reactBaseUrl.endsWith('/')) {
            reactBaseUrl += '/';
        }
        PORTAL_BASE_URL = reactBaseUrl + 'wohi';
    }

    /**
     * Builds an encoded URL containing the form data as a single JSON payload.
     * The React app can read the `data` query parameter, decode it, and
     * populate the form.
     *
     * @param formData Map of field names to values.
     * @return The encoded portal URL.
     */
    public static String buildEncodedUrl(Map<String, Object> formData) {
        if (formData == null || formData.isEmpty()) {
            return PORTAL_BASE_URL;
        }

        String jsonData = JSON.serialize(formData);
        String encodedData = EncodingUtil.urlEncode(jsonData, 'UTF-8');
        return PORTAL_BASE_URL + '?data=' + encodedData;
    }

    /**
     * Builds an encoded URL from a JSON string.
     *
     * @param jsonData JSON representation of the form data.
     * @return The encoded portal URL.
     */
    public static String buildEncodedUrl(String jsonData) {
        if (String.isBlank(jsonData)) {
            return PORTAL_BASE_URL;
        }

        String encodedData = EncodingUtil.urlEncode(jsonData, 'UTF-8');
        return PORTAL_BASE_URL + '?data=' + encodedData;
    }

    /**
     * Returns a simple HTML email body containing the encoded link.
     *
     * @param formData Map of field names to values.
     * @return HTML body for the email.
     */
    public static String buildEmailBody(Map<String, Object> formData) {
        String url = buildEncodedUrl(formData);

        System.debug('Form URL: ' + url);
        return '<p>Please complete your form by clicking the link below:</p>'
             + '<a href="' + url + '">Complete Form</a>';

        
    }
}