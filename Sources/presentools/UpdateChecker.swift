import AppKit
import Foundation
import CryptoKit

struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
    let size: Int?
}

struct GitHubRelease: Codable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String?
    let assets: [GitHubAsset]?
}

enum UpdateOutcome {
    case upToDate
    case newerAvailable(tag: String, release: GitHubRelease, assetURL: URL?, digest: String?)
    case failed(String)
}

final class UpdateChecker {
    static let repo = "ardith666/presentools"
    private let session = URLSession(configuration: .ephemeral)
    private let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func isNewer(current: String, tag: String) -> Bool {
        Version.isNewer(current: current, candidate: tag)
    }

    /// Extract first SHA-256 hex (case-insensitive) from release body. Looks for
    /// common forms: `sha256: abc...`, `SHA256 abc...`, `abc123...` (64 hex chars)
    static func extractDigest(from body: String) -> String? {
        let text = body
        // Try explicit labels
        let patterns = [
            "sha256[:\\s]+([0-9a-fA-F]{64})",
            "SHA256[:\\s]+([0-9a-fA-F]{64})",
            "shasum[:\\s]+([0-9a-fA-F]{64})",
            "(?<![0-9a-fA-F])([0-9a-fA-F]{64})(?![0-9a-fA-F])"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if let m = regex.firstMatch(in: text, options: [], range: range),
                   m.numberOfRanges >= 2 {
                    let r = m.range(at: m.numberOfRanges - 1)
                    if let s = Range(r, in: text) {
                        let hex = String(text[s]).lowercased()
                        if hex.count == 64 { return hex }
                    }
                }
            }
        }
        return nil
    }

    func check(onComplete: @escaping @Sendable (UpdateOutcome) -> Void) {
        let task = session.dataTask(with: apiURL) { data, _, err in
            if err != nil {
                onComplete(.failed("network error"))
                return
            }
            guard let data else {
                onComplete(.failed("no data"))
                return
            }
            do {
                let rel = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let tag = rel.tag_name
                let cur = Self.currentVersion()
                if !Self.isNewer(current: cur, tag: tag) {
                    onComplete(.upToDate)
                    return
                }
                let assetURL = rel.assets?.first(where: { $0.name.lowercased().hasSuffix(".dmg") })?.browser_download_url
                let digest = rel.body.flatMap { Self.extractDigest(from: $0) }
                if let u = assetURL, let url = URL(string: u) {
                    onComplete(.newerAvailable(tag: tag, release: rel, assetURL: url, digest: digest))
                } else {
                    onComplete(.newerAvailable(tag: tag, release: rel, assetURL: nil, digest: digest))
                }
            } catch {
                onComplete(.failed("malformed json"))
            }
        }
        task.resume()
    }

    func downloadAndOpenFolder(assetURL: URL, expectedDigest: String?, onComplete: @escaping @Sendable (Bool) -> Void) {
        let task = session.downloadTask(with: assetURL) { url, _, err in
            guard err == nil, let tmp = url else {
                onComplete(false)
                return
            }
            do {
                let fm = FileManager.default
                let destDir = fm.temporaryDirectory.appendingPathComponent("Presentools-Update", isDirectory: true)
                if !fm.fileExists(atPath: destDir.path) {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                }
                let dest = destDir.appendingPathComponent(assetURL.lastPathComponent)
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                try fm.moveItem(at: tmp, to: dest)
                if let want = expectedDigest, !want.isEmpty {
                    let data = try Data(contentsOf: dest)
                    let hash = SHA256.hash(data: data)
                    let got = hash.compactMap { String(format: "%02x", $0) }.joined()
                    if got != want.lowercased() {
                        try? fm.removeItem(at: dest)
                        onComplete(false)
                        return
                    }
                }
                NSWorkspace.shared.open(dest.deletingLastPathComponent())
                onComplete(true)
            } catch {
                onComplete(false)
            }
        }
        task.resume()
    }
}