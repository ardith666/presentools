import AppKit
import CoreGraphics
import Darwin

enum SlideAction: String, CaseIterable, Sendable {
    case next
    case prev
    case blank
    case escape

    var keyCode: CGKeyCode {
        switch self {
        case .next: return 124  // Right Arrow
        case .prev: return 123  // Left Arrow
        case .blank: return 11  // 'B' key (Standard presentation blackout)
        case .escape: return 53 // Esc key
        }
    }
}

final class SlideController: Sendable {
    static let shared = SlideController()

    /// Memeriksa apakah aplikasi memiliki izin Aksesibilitas di macOS
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Minta izin Aksesibilitas dengan memunculkan prompt dialog sistem jika belum diizinkan
    func requestAccessibilityPermission() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Mengirim keypress sintetis ke sistem macOS untuk mengendalikan slide presentasi aktif
    @discardableResult
    func trigger(_ action: SlideAction) -> Bool {
        let key = action.keyCode
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Menggeser kursor mouse dengan delta (dx, dy)
    @discardableResult
    func moveMouse(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let currentEvent = CGEvent(source: nil) else { return false }
        let currentPos = currentEvent.location
        let newX = max(0, currentPos.x + dx)
        let newY = max(0, currentPos.y + dy)
        let newPos = CGPoint(x: newX, y: newY)
        CGWarpMouseCursorPosition(newPos)
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
        return true
    }

    /// Melakukan klik kiri mouse
    @discardableResult
    func clickMouse() -> Bool {
        guard let currentEvent = CGEvent(source: nil) else { return false }
        let pos = currentEvent.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Melakukan klik kanan mouse
    @discardableResult
    func rightClickMouse() -> Bool {
        guard let currentEvent = CGEvent(source: nil) else { return false }
        let pos = currentEvent.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: pos, mouseButton: .right),
              let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: pos, mouseButton: .right) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Mendeteksi alamat IP IPv4 lokal untuk koneksi Wi-Fi (biasanya interface en0)
    static func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var wifiIP: String?
        var fallbackIP: String?

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let family = interface.ifa_addr.pointee.sa_family

            // Hanya interface aktif yang bukan loopback
            if (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 && family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let saLen = socklen_t(interface.ifa_addr.pointee.sa_len)
                if getnameinfo(
                    interface.ifa_addr,
                    saLen,
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let name = String(cString: interface.ifa_name)
                    let ip = hostname.withUnsafeBufferPointer { buffer in
                        buffer.baseAddress.map { String(cString: $0) }
                    } ?? ""
                    if !ip.isEmpty && ip != "127.0.0.1" {
                        if name == "en0" {
                            wifiIP = ip
                            break
                        } else if fallbackIP == nil {
                            fallbackIP = ip
                        }
                    }
                }
            }
            ptr = interface.ifa_next
        }

        return wifiIP ?? fallbackIP
    }
}
