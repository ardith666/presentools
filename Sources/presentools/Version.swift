import Foundation

/// Version string parsing and comparison (numeric components, not lexicographic).
///
/// `1.10.0` > `1.9.0`. Missing components read as 0 (`1.2` == `1.2.0`). A leading
/// `v` is stripped. Any trailing non-numeric suffix is preserved for `display`
/// but ignored for numeric comparison (e.g. `1.2.0-beta1` compares as 1.2.0).
struct Version {
    let components: [Int]
    let display: String

    static func from(_ string: String) -> Version? {
        let raw = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = raw
        // Strip leading 'v' or 'V'
        let s = raw.hasPrefix("v") || raw.hasPrefix("V")
            ? String(raw.dropFirst())
            : raw
        // Split on dots first to get numeric prefix
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        var nums: [Int] = []
        for p in parts {
            // Take numeric prefix of this token (ignore suffix like -beta1, +build)
            let token = String(p)
            let digits = token.prefix { $0.isNumber }
            if digits.isEmpty { break } // no more numeric components
            if let v = Int(String(digits)) {
                nums.append(v)
            } else {
                break
            }
        }
        if nums.isEmpty { return nil }
        // Pad/truncate to at least 3 for typical semver, keep actual count
        return Version(components: nums, display: display)
    }

    static func isNewer(current: String, candidate: String) -> Bool {
        guard let c = from(current), let n = from(candidate) else { return false }
        // Compare by numeric components, pad to max length with 0
        let maxCount = max(c.components.count, n.components.count)
        for i in stride(from: 0, to: maxCount, by: 1) {
            let cv = i < c.components.count ? c.components[i] : 0
            let nv = i < n.components.count ? n.components[i] : 0
            if nv > cv { return true }
            if nv < cv { return false }
        }
        // Equal → not newer
        return false
    }
}