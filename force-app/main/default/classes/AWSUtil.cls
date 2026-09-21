public with sharing class AWSUtil {

    /**
     * Returns SHA-256 hash in hexadecimal format
     */
    public static String sha256Hex(String input) {

        Blob hash = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(input)
        );

        return EncodingUtil.convertToHex(hash).toLowerCase();
    }

    /**
     * Returns HMAC SHA-256
     */
    public static Blob hmacSHA256(Blob key, String data) {

        return Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(data),
            key
        );
    }

    /**
     * Converts Blob to lowercase hex
     */
    public static String blobToHex(Blob value) {

        return EncodingUtil.convertToHex(value).toLowerCase();
    }

}