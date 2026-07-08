import Foundation
import Security
import CryptoKit
import os

private let pinLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.shashankshekhar.vigilant",
    category: "CertificatePinner"
)

/// SPKI-based (Subject Public Key Info) TLS certificate pinner for GitHub's endpoints.
///
/// Acts as the `URLSessionDelegate` for the sessions used by `GitHubAPIClient` and
/// `DeviceFlowManager`. On a server-trust challenge it:
///   1. lets the OS evaluate the chain (`SecTrustEvaluateWithError`) — a chain the OS
///      itself rejects is rejected here too;
///   2. walks every certificate in the chain, computes the SHA-256 of each cert's SPKI
///      DER, and requires at least one to match a pinned hash.
///
/// We pin the Sectigo *intermediate* and *root* public keys (not the leaf), so routine
/// leaf-certificate rotation by GitHub does not break the app. See ``pinnedSPKIHashes``.
///
/// In `DEBUG` builds enforcement is a no-op (`.performDefaultHandling`) so the local mock
/// server and tests that talk to non-GitHub hosts keep working. The pin-computation code
/// itself always compiles and is unit-tested directly.
public final class CertificatePinner: NSObject, URLSessionDelegate, @unchecked Sendable {

    /// Base64-encoded SHA-256 hashes of the pinned Subject Public Key Info (SPKI) DER.
    ///
    /// Both hosts (`api.github.com`, `github.com`) currently chain through the same
    /// Sectigo CA. We pin both the intermediate and the root; a match on *either* passes.
    ///
    /// - `ZSagvDzjltLkewXEBuDxIzpW/dpVw1Juvvmd0hhkzdY=`
    ///   CN=Sectigo Public Server Authentication CA DV E36 (intermediate, EC).
    /// - `sLVjNUaFYfW7n6EtgBeEpjOlcnBdNPMrZDRF36iwBdE=`
    ///   CN=Sectigo Public Server Authentication Root E46 (root, EC).
    public static let pinnedSPKIHashes: Set<String> = [
        "ZSagvDzjltLkewXEBuDxIzpW/dpVw1Juvvmd0hhkzdY=",
        "sLVjNUaFYfW7n6EtgBeEpjOlcnBdNPMrZDRF36iwBdE=",
    ]

    /// Hosts for which pinning is enforced. Other hosts fall through to default handling.
    public static let pinnedHosts: Set<String> = [
        "api.github.com",
        "github.com",
    ]

    public override init() {
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only server-trust challenges are our concern; anything else uses default handling.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        #if DEBUG
        // Pinning is a no-op in DEBUG so the mock server / test hosts keep working.
        // The pin-computation code below still compiles and is unit-tested.
        completionHandler(.performDefaultHandling, nil)
        return
        #else
        // 1. The OS must trust the chain first — reject anything it wouldn't accept.
        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            pinLogger.error("System trust evaluation failed for host \(challenge.protectionSpace.host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 2. Only enforce pinning on the hosts we have pins for. Other hosts are accepted
        //    on the basis of the (already validated) system trust.
        let host = challenge.protectionSpace.host
        guard Self.pinnedHosts.contains(host) else {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        // 3. Require at least one cert in the chain to match a pinned SPKI hash.
        if Self.trustMatchesPin(serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            pinLogger.error("Certificate pin mismatch for host \(host, privacy: .public) — rejecting connection")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
        #endif
    }

    // MARK: - Pin evaluation

    /// Returns true if any certificate in `trust` has an SPKI SHA-256 hash in ``pinnedSPKIHashes``.
    static func trustMatchesPin(_ trust: SecTrust) -> Bool {
        for certificate in certificateChain(of: trust) {
            if let hash = spkiSHA256Base64(for: certificate),
               pinnedSPKIHashes.contains(hash) {
                return true
            }
        }
        return false
    }

    /// The certificate chain for a `SecTrust`, from leaf to anchor.
    static func certificateChain(of trust: SecTrust) -> [SecCertificate] {
        (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
    }

    // MARK: - SPKI hashing

    /// SHA-256 of a certificate's Subject Public Key Info DER, base64-encoded.
    ///
    /// `SecKeyCopyExternalRepresentation` yields the *raw* public key bytes (X9.63 point
    /// for EC, PKCS#1 `RSAPublicKey` for RSA) — i.e. the contents that sit inside the SPKI
    /// BIT STRING, without the algorithm-identifier header. We reconstruct the full SPKI by
    /// prepending the correct ASN.1 header for the key type (the TrustKit technique) and
    /// hash the result. This yields the same value as
    /// `openssl x509 -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256`.
    static func spkiSHA256Base64(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }
        return spkiSHA256Base64(for: publicKey)
    }

    /// SHA-256 (base64) of the SPKI DER reconstructed from a `SecKey`.
    static func spkiSHA256Base64(for publicKey: SecKey) -> String? {
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        guard let attributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any],
              let header = asn1SPKIHeader(for: attributes) else {
            return nil
        }

        var spki = Data(header)
        spki.append(keyData)
        let digest = SHA256.hash(data: spki)
        return Data(digest).base64EncodedString()
    }

    /// The ASN.1 SubjectPublicKeyInfo header for a given key type/size, or nil if unsupported.
    ///
    /// Headers are the standard TrustKit constants. They encode the algorithm identifier and
    /// the outer `SEQUENCE`/`BIT STRING` wrappers that precede the raw key bytes returned by
    /// `SecKeyCopyExternalRepresentation`.
    static func asn1SPKIHeader(for attributes: [CFString: Any]) -> [UInt8]? {
        guard let keyType = attributes[kSecAttrKeyType] as? String,
              let keySize = attributes[kSecAttrKeySizeInBits] as? Int else {
            return nil
        }

        let rsa = kSecAttrKeyTypeRSA as String
        let ec = kSecAttrKeyTypeECSECPrimeRandom as String

        switch (keyType, keySize) {
        case (rsa, 2048):
            return [
                0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86,
                0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03,
                0x82, 0x01, 0x0f, 0x00,
            ]
        case (rsa, 4096):
            return [
                0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86,
                0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03,
                0x82, 0x02, 0x0f, 0x00,
            ]
        case (ec, 256):
            return [
                0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce,
                0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d,
                0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
            ]
        case (ec, 384):
            return [
                0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce,
                0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22,
                0x03, 0x62, 0x00,
            ]
        default:
            return nil
        }
    }

    // MARK: - Session factory

    /// A `URLSession` that enforces GitHub certificate pinning (no-op in DEBUG).
    ///
    /// The pinner is retained as the session delegate. Preserves the default request/resource
    /// timeouts of a `.default` configuration.
    public static func makePinnedSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        return URLSession(
            configuration: configuration,
            delegate: CertificatePinner(),
            delegateQueue: nil
        )
    }

    /// Shared pinned session used as the default transport for GitHub network calls.
    public static let sharedPinnedSession: URLSession = makePinnedSession()
}
