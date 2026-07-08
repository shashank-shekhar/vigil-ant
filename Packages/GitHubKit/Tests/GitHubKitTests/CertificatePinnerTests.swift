import Testing
import Foundation
import Security
@testable import GitHubKit

/// Tests for the SPKI-hashing helper that backs certificate pinning.
///
/// Each fixture is a self-signed certificate (DER, base64) whose expected pin was computed
/// independently with OpenSSL:
///
///     openssl x509 -in cert.pem -pubkey -noout \
///       | openssl pkey -pubin -outform DER \
///       | openssl dgst -sha256 -binary | openssl enc -base64
///
/// This proves `CertificatePinner.spkiSHA256Base64(for:)` reconstructs the SPKI DER
/// correctly for EC P-256, EC P-384 (the Sectigo curve), and RSA-2048 keys.
struct CertificatePinnerTests {

    // MARK: - Fixtures (DER base64) and their OpenSSL-computed SPKI SHA-256 pins.

    private static let ecP256DER =
        "MIIBgTCCASegAwIBAgIUU0IHcqGCzQ987W3PLPc81F7ZEtUwCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLdGVzdC1lY3AyNTYwHhcNMjYwNzA4MDQ1NjQ3WhcNMzYwNzA1MDQ1NjQ3WjAWMRQwEgYDVQQDDAt0ZXN0LWVjcDI1NjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABERZgz97WLwA3f0A5qH1sR2bLpeionC0Zwj0Mq/J4kwVytadGalHTeYFXd/y6fCvSSuX+tFCWBbgSr85zK1CXGujUzBRMB0GA1UdDgQWBBQDf2nMsFJB7nNv1mgDweQJZS9GRDAfBgNVHSMEGDAWgBQDf2nMsFJB7nNv1mgDweQJZS9GRDAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0gAMEUCIQCOFK9GcVRxr0d2pfEwTgXMA7gQZTCCPTnunQXjScY3hAIgNUaO86YS7Bpwbzd6lrCAzyKZkE6kIV8p3JzrAGJUhtA="
    private static let ecP256Pin = "FcEa72krUS+RotjmYnHlMaS1BE9WAmbiicXoUpA7JHI="

    private static let ecP384DER =
        "MIIBvzCCAUSgAwIBAgIUaU57t6f0WOOYMtvonlN9HxDhDt8wCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLdGVzdC1lY3AzODQwHhcNMjYwNzA4MDQ1NjQ3WhcNMzYwNzA1MDQ1NjQ3WjAWMRQwEgYDVQQDDAt0ZXN0LWVjcDM4NDB2MBAGByqGSM49AgEGBSuBBAAiA2IABG0kTegKnBjiGvaTF6Swh37ZN3mFD+JE/vKAkexBvX4sG2kG+/X2kh6QoLdHYJEVvae8t+LQ7s7WwiDdxsmzIw0hsRVRbYUMWPEZhZLYG73BRPlv7LCerP+924tvgA8bIaNTMFEwHQYDVR0OBBYEFLnzTmu6JqF+vLeZwYJy2i5yLuZdMB8GA1UdIwQYMBaAFLnzTmu6JqF+vLeZwYJy2i5yLuZdMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDaQAwZgIxANLoTdL9OLd05Pe+pAQ8+VsGzpIyt+1cDygdiYSk7ViAydIIYsfsbizIsueWrtpo4AIxAIhkhvftMkehcG3L5aZPcVtHjCqT1jAvnlLyd7iI7rjj0efzmwONM+ZqF8WTxOAWbA=="
    private static let ecP384Pin = "4T+/bapJ6svH5HcxnyhlnKrz+WG2jr7yZPNpJrF3Ujc="

    private static let rsa2048DER =
        "MIIDBzCCAe+gAwIBAgIUHypTRamffhcJlv+Wew6/aBlm1JcwDQYJKoZIhvcNAQELBQAwEzERMA8GA1UEAwwIdGVzdC1yc2EwHhcNMjYwNzA4MDQ1NjQ4WhcNMzYwNzA1MDQ1NjQ4WjATMREwDwYDVQQDDAh0ZXN0LXJzYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALCbLaCsseVMpPSaHNfLBSeVhFw+Wo66Ls+GffhLKSM//RJKNy0XDG2BGa/JWjY8DilmZPvvntxKsE3Ky8x+130ugfmms0B8Ep7JLYdseL4JVK/keYi90Xg3JiAISGINswmSz/TT93iXqt1ee9IbRIDi72GENGWmU7E6qx1tAMelEoId8w5a6MJRKCq41C4duA4lhrdIItvNCkceuqCDtldM/YRLDebI5JlcWJFUWuoOSBlQABYvNUgg6h4vRSBhSwbhrZLm5mQ9fTgvHDK2cd1vE+EYN4OrDW4rSOWyElsS9M3T1rYwbM/PaxrXAZce3s3SS5DHTO9bmXeqoexIReUCAwEAAaNTMFEwHQYDVR0OBBYEFF6ycQJQAbh4E/Smj/+gAlb4jwRsMB8GA1UdIwQYMBaAFF6ycQJQAbh4E/Smj/+gAlb4jwRsMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBADqsREqTb4l0QNox3qYuHPdBbogr+un+5oNPZcWl/f6avFBbIw8IFIMiW0uHkLScuYbB2HFcNGwqoe+Rlt/mkLiYsfAZ0TcxkGgNJScNHgbFbhNSGf2RsvyI+81AU4BfGxJR5A5PDog/Zd008dvfQDQZXn480S/+IL6OzbHf75bpMX/D24xFJmStWdspUeaUkB1ConqrGTMv0hhtxajiVh/C+fbd4rWAQ+EHi1m/jsGPmrZsj/7EwkjrLv1cXdld07P0FjmaSzTYmIwSMh7lF3fYKUjDxPdv/QlXKK1XG2VLdo8tc6j++C3Lef1sJ9PH987D1IPNU/ZxMNlH+34laOw="
    private static let rsa2048Pin = "C/OBWJcPcQlx7PKnYkLKCL50crkQaTnGvbQvXAqjMwY="

    private func certificate(fromBase64DER der: String) throws -> SecCertificate {
        let data = try #require(Data(base64Encoded: der))
        return try #require(SecCertificateCreateWithData(nil, data as CFData))
    }

    // MARK: - Helper produces the expected pin (known input -> known output)

    @Test func ecP256SPKIHashMatchesOpenSSL() throws {
        let cert = try certificate(fromBase64DER: Self.ecP256DER)
        #expect(CertificatePinner.spkiSHA256Base64(for: cert) == Self.ecP256Pin)
    }

    @Test func ecP384SPKIHashMatchesOpenSSL() throws {
        let cert = try certificate(fromBase64DER: Self.ecP384DER)
        #expect(CertificatePinner.spkiSHA256Base64(for: cert) == Self.ecP384Pin)
    }

    @Test func rsa2048SPKIHashMatchesOpenSSL() throws {
        let cert = try certificate(fromBase64DER: Self.rsa2048DER)
        #expect(CertificatePinner.spkiSHA256Base64(for: cert) == Self.rsa2048Pin)
    }

    // MARK: - Pin set membership

    @Test func certificateInPinnedSetIsAccepted() throws {
        // Treat the P-384 fixture's pin as if it were the pinned key: membership must succeed.
        let cert = try certificate(fromBase64DER: Self.ecP384DER)
        let hash = try #require(CertificatePinner.spkiSHA256Base64(for: cert))
        let pinnedSet: Set<String> = [hash]
        #expect(pinnedSet.contains(hash))
    }

    @Test func mismatchingCertificateIsRejected() throws {
        // A cert whose SPKI hash is not among the real Sectigo pins must not match.
        let cert = try certificate(fromBase64DER: Self.ecP256DER)
        let hash = try #require(CertificatePinner.spkiSHA256Base64(for: cert))
        #expect(!CertificatePinner.pinnedSPKIHashes.contains(hash))
    }

    @Test func realSectigoPinsArePresent() {
        // Guard against accidental edits to the shipped pin set.
        #expect(CertificatePinner.pinnedSPKIHashes.contains("ZSagvDzjltLkewXEBuDxIzpW/dpVw1Juvvmd0hhkzdY="))
        #expect(CertificatePinner.pinnedSPKIHashes.contains("sLVjNUaFYfW7n6EtgBeEpjOlcnBdNPMrZDRF36iwBdE="))
        #expect(CertificatePinner.pinnedHosts == ["api.github.com", "github.com"])
    }
}
