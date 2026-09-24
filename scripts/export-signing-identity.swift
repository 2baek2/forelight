// Exports one keychain identity (certificate + private key) to a PKCS#12 file
// without going through the Keychain Access GUI, which is what you need to put a
// self-signed code-signing certificate into GitHub Actions secrets.
//
// Usage:
//   swift scripts/export-signing-identity.swift <label> <out.p12> <password>
import Foundation
import Security

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: swift export-signing-identity.swift <label> <out.p12> <password>\n".utf8))
    exit(2)
}
let label = args[1]
let outPath = args[2]
let password = args[3]

func fail(_ message: String, _ status: OSStatus? = nil) -> Never {
    if let status {
        FileHandle.standardError.write(Data("\(message) (OSStatus \(status))\n".utf8))
    } else {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
    exit(1)
}

func label(of identity: SecIdentity) -> String? {
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
          let certificate
    else { return nil }

    var value: CFTypeRef?
    let query: [String: Any] = [
        kSecClass as String: kSecClassCertificate,
        kSecValueRef as String: certificate,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
       let attributes = value as? [String: Any] {
        if let name = attributes[kSecAttrLabel as String] as? String, !name.isEmpty {
            return name
        }
    }
    return SecCertificateCopySubjectSummary(certificate) as String?
}

let allQuery: [String: Any] = [
    kSecClass as String: kSecClassIdentity,
    kSecMatchLimit as String: kSecMatchLimitAll,
    kSecReturnRef as String: true,
]
var found: CFTypeRef?
let status = SecItemCopyMatching(allQuery as CFDictionary, &found)
guard status == errSecSuccess else {
    fail("could not query the keychain", status)
}

let identities = (found as? [SecIdentity]) ?? []
guard !identities.isEmpty else {
    fail("no identities with a private key were found")
}

guard let identity = identities.first(where: { candidate in
    guard let name = label(of: candidate) else { return false }
    return name == label || name.localizedCaseInsensitiveContains(label)
}) else {
    let names = identities.compactMap(label(of:)).joined(separator: ", ")
    fail("identity \"\(label)\" not found. Available: \(names)")
}

var exported: CFData?
var keyParams = SecItemImportExportKeyParameters(
    version: UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION),
    flags: [],
    passphrase: Unmanaged.passUnretained(password as CFString as CFTypeRef),
    alertTitle: nil,
    alertPrompt: nil,
    accessRef: nil,
    keyUsage: nil,
    keyAttributes: nil
)
let exportStatus = SecItemExport(identity, .formatPKCS12, [], &keyParams, &exported)
guard exportStatus == errSecSuccess, let data = exported else {
    fail("exporting identity \"\(label)\" failed", exportStatus)
}

do {
    try (data as Data).write(to: URL(fileURLWithPath: outPath))
} catch {
    fail("writing \(outPath) failed: \(error)")
}

FileHandle.standardOutput.write(Data("wrote \(outPath)\n".utf8))
