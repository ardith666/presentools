import AppKit
import ServiceManagement

enum LoginItemStatus {
    case enabled
    case notRegistered
    case requiresApproval
    case unknown

    /// What the menu tick shows.
    ///
    /// Pure so `--selftest` can prove the mapping for all four cases without
    /// touching a login item. `.requiresApproval` gets `.mixed` rather than a
    /// bare tick: the user has to approve it in System Settings, and a tick
    /// that claims "on" when the system still says "needs approval" is a lie.
    var menuState: NSControl.StateValue {
        switch self {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        case .notRegistered, .unknown: return .off
        }
    }

    /// Whether the menu item should enable the item when clicked.
    /// `.requiresApproval` and `.unknown` both need a click to clear.
    var shouldEnableOnClick: Bool { self != .enabled }
}

@MainActor
final class LaunchAtLogin {
    static func status() -> LoginItemStatus {
        let s = SMAppService.mainApp.status
        switch s {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        // `.notFound` means the framework cannot locate the app as a login item,
        // which is what running the build from `build/` looks like.
        case .notFound: return .unknown
        @unknown default: return .unknown
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}