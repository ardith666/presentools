import Foundation
import Network

final class NetworkServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 8765

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "id.my.digitechnesia.presentools.webserver", qos: .userInteractive)
    private let port: UInt16

    var getEffect: (@Sendable () -> Effect)?
    var onSetEffect: (@Sendable (Effect) -> Void)?
    var onSlideAction: (@Sendable (SlideAction) -> Void)?

    private(set) var isRunning: Bool = false

    init(port: UInt16 = NetworkServer.defaultPort) {
        self.port = port
    }

    func start() {
        guard !isRunning else { return }
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: nwPort)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    print("NetworkServer: Listening on port \(self?.port ?? 0)")
                    fflush(stdout)
                case .failed(let error):
                    self?.isRunning = false
                    print("NetworkServer: Failed with error \(error)")
                    fflush(stdout)
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }

            listener.start(queue: queue)
        } catch {
            print("NetworkServer: Error starting listener: \(error)")
            fflush(stdout)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveNextChunk(connection: connection, accumulatedData: Data())
    }

    private func receiveNextChunk(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var currentData = accumulatedData
            if let content {
                currentData.append(content)
            }

            // Cek apakah header HTTP sudah selesai diterima (\r\n\r\n)
            if let range = currentData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = currentData.subdata(in: 0..<range.lowerBound)
                let bodyData = currentData.subdata(in: range.upperBound..<currentData.count)

                if let headerString = String(data: headerData, encoding: .utf8) {
                    let lines = headerString.components(separatedBy: "\r\n")
                    guard let requestLine = lines.first else {
                        self.sendResponse(connection: connection, status: "400 Bad Request", body: Data())
                        return
                    }

                    let parts = requestLine.split(separator: " ")
                    guard parts.count >= 2 else {
                        self.sendResponse(connection: connection, status: "400 Bad Request", body: Data())
                        return
                    }

                    let method = String(parts[0])
                    let path = String(parts[1])

                    // Parse Content-Length jika method POST
                    var contentLength = 0
                    for line in lines {
                        let lower = line.lowercased()
                        if lower.hasPrefix("content-length:") {
                            let lenStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                            contentLength = Int(lenStr) ?? 0
                        }
                    }

                    // Tunggu jika body belum lengkap
                    if bodyData.count < contentLength {
                        self.receiveNextChunk(connection: connection, accumulatedData: currentData)
                        return
                    }

                    let fullBody = bodyData.prefix(contentLength)
                    self.routeRequest(connection: connection, method: method, path: path, body: Data(fullBody))
                    return
                }
            }

            if isComplete {
                connection.cancel()
            } else {
                self.receiveNextChunk(connection: connection, accumulatedData: currentData)
            }
        }
    }

    private func routeRequest(connection: NWConnection, method: String, path: String, body: Data) {
        if method == "GET" && (path == "/" || path == "/index.html") {
            let htmlData = Data(WebRemoteUI.html.utf8)
            sendResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: htmlData)
            return
        }

        if method == "GET" && path == "/api/status" {
            let current = getEffect?() ?? .none
            let trusted = SlideController.shared.isAccessibilityGranted
            let jsonString = """
            {"effect":"\(current.rawValue)","accessibilityGranted":\(trusted)}
            """
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: Data(jsonString.utf8))
            return
        }

        if method == "POST" && path == "/api/effect" {
            var selected: Effect = .none
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let name = obj["effect"] as? String,
               let parsed = Effect(rawValue: name) {
                selected = parsed
            }
            onSetEffect?(selected)
            let response = """
            {"ok":true,"effect":"\(selected.rawValue)"}
            """
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: Data(response.utf8))
            return
        }

        if method == "POST" && path == "/api/slide" {
            var action: SlideAction = .next
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let actStr = obj["action"] as? String,
               let parsed = SlideAction(rawValue: actStr) {
                action = parsed
            }
            onSlideAction?(action)
            let trusted = SlideController.shared.isAccessibilityGranted
            let response = """
            {"ok":true,"action":"\(action.rawValue)","requiresAccessibility":\(!trusted)}
            """
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: Data(response.utf8))
            return
        }

        sendResponse(connection: connection, status: "404 Not Found", body: Data("Not Found".utf8))
    }

    private func sendResponse(
        connection: NWConnection,
        status: String,
        contentType: String = "text/plain",
        body: Data
    ) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n\r\n"

        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
