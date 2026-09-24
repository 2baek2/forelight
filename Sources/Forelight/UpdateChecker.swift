import Foundation

struct ReleaseInfo: Equatable, Sendable {
    var version: String
    var pageURL: URL
    var dmgURL: URL?
    var notes: String?
}

enum UpdateError: LocalizedError {
    case badResponse
    case invalidVersion
    case noAsset

    var errorDescription: String? {
        switch self {
        case .badResponse: return "The update server returned an unexpected response."
        case .invalidVersion: return "The latest release has an unreadable version."
        case .noAsset: return "The latest release has no download."
        }
    }
}

/// Checks the GitHub releases of Forelight for a newer version. Update builds
/// are ad-hoc signed, so this only offers the download instead of installing it.
enum UpdateChecker {
    static let repository = "2baek2/forelight"

    static func latestRelease(timeout: TimeInterval = 15) async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw UpdateError.badResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let rawTag = json["tag_name"] as? String,
              let version = normalizedVersion(rawTag),
              let pageURL = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw UpdateError.invalidVersion
        }

        var dmgURL: URL?
        for asset in (json["assets"] as? [[String: Any]] ?? []) {
            guard let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                  let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
                continue
            }
            dmgURL = url
            break
        }

        return ReleaseInfo(
            version: version,
            pageURL: pageURL,
            dmgURL: dmgURL,
            notes: json["body"] as? String
        )
    }

    /// Downloads a release asset into ~/Downloads and returns its location.
    static func download(_ url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }

        let directory = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    /// Turns "v1.2.3" (or "1.2.3") into "1.2.3", or nil when unreadable.
    static func normalizedVersion(_ tag: String) -> String? {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        guard !value.isEmpty,
              value.split(separator: ".").allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return value
    }

    /// Compares dotted numeric versions. Missing components count as zero.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}
