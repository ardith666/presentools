import AppKit
import CoreImage

@MainActor
final class RemoteControlWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let serverPort: UInt16
    private var qrImageView: NSImageView?
    private var urlLabel: NSTextField?
    private var statusLabel: NSTextField?

    init(port: UInt16 = NetworkServer.defaultPort) {
        self.serverPort = port
        super.init()
    }

    var serverURL: String {
        let ip = SlideController.localIPv4Address() ?? "127.0.0.1"
        return "http://\(ip):\(serverPort)"
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        refreshContent()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Web Remote Control"
        win.isReleasedWhenClosed = false
        win.delegate = self

        let container = NSView(frame: win.contentView?.bounds ?? .zero)
        container.wantsLayer = true

        // Judul
        let titleLabel = NSTextField(labelWithString: "Smartphone Remote")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // Subtitle instruksi
        let instructionLabel = NSTextField(labelWithString: "Scan QR code dari kamera HP dalam Wi-Fi yang sama untuk mengontrol slide & efek.")
        instructionLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.alignment = .center
        instructionLabel.maximumNumberOfLines = 2
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(instructionLabel)

        // QR Code Container Box
        let qrBox = NSView()
        qrBox.wantsLayer = true
        qrBox.layer?.backgroundColor = NSColor.white.cgColor
        qrBox.layer?.cornerRadius = 14
        qrBox.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(qrBox)

        let qrView = NSImageView()
        qrView.imageScaling = .scaleProportionallyUpOrDown
        qrView.translatesAutoresizingMaskIntoConstraints = false
        qrBox.addSubview(qrView)
        self.qrImageView = qrView

        // URL display
        let urlField = NSTextField(labelWithString: serverURL)
        urlField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        urlField.alignment = .center
        urlField.isSelectable = true
        urlField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(urlField)
        self.urlLabel = urlField

        // Buttons: Copy Link & Open Browser
        let btnStack = NSStackView()
        btnStack.orientation = .horizontal
        btnStack.spacing = 10
        btnStack.distribution = .fillEqually
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(btnStack)

        let copyBtn = NSButton(title: "Copy Link", target: self, action: #selector(copyLink))
        copyBtn.bezelStyle = .rounded
        btnStack.addArrangedSubview(copyBtn)

        let openBtn = NSButton(title: "Open Browser", target: self, action: #selector(openBrowser))
        openBtn.bezelStyle = .rounded
        btnStack.addArrangedSubview(openBtn)

        // Status Label
        let stLabel = NSTextField(labelWithString: "● Server Aktif di Port \(serverPort)")
        stLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        stLabel.textColor = .systemGreen
        stLabel.alignment = .center
        stLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stLabel)
        self.statusLabel = stLabel

        // Auto Layout Constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            instructionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            qrBox.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 16),
            qrBox.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            qrBox.widthAnchor.constraint(equalToConstant: 220),
            qrBox.heightAnchor.constraint(equalToConstant: 220),

            qrView.centerXAnchor.constraint(equalTo: qrBox.centerXAnchor),
            qrView.centerYAnchor.constraint(equalTo: qrBox.centerYAnchor),
            qrView.widthAnchor.constraint(equalToConstant: 196),
            qrView.heightAnchor.constraint(equalToConstant: 196),

            urlField.topAnchor.constraint(equalTo: qrBox.bottomAnchor, constant: 16),
            urlField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            urlField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            btnStack.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 14),
            btnStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            btnStack.widthAnchor.constraint(equalToConstant: 240),

            stLabel.topAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 14),
            stLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
        ])

        win.contentView = container
        self.window = win
    }

    private func refreshContent() {
        let currentURL = serverURL
        urlLabel?.stringValue = currentURL
        if let qrImage = generateQRCode(from: currentURL) {
            qrImageView?.image = qrImage
        }
    }

    @objc private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serverURL, forType: .string)
    }

    @objc private func openBrowser() {
        if let url = URL(string: serverURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = string.data(using: .utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputCIImage = filter.outputImage else { return nil }

        // Skalakan bitmap agar tajam (output native CIQRCodeGenerator hanya ~31x31 pixel)
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputCIImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
