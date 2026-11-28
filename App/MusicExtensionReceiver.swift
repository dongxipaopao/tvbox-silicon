#if os(tvOS)
import SwiftUI
import Network
import Observation
import Darwin
import TVCore

/// Apple TV has no Files picker. While the "Add from Phone" screen is open, the TV serves one small page on the
/// local network (address with a random token); a phone or computer browser on the same network picks the script
/// file and sends it. The script is held, never run, until the person presses Add on the TV.
@MainActor @Observable final class MusicExtensionReceiver {
    static let sizeLimit = 5_000_000
    private(set) var address: String?
    private(set) var pendingName: String?
    private(set) var note: String?
    private var pendingScript: String?
    private var server: Server?
    var changed: () -> Void = {}

    func start() {
        guard server == nil else { return }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let made = Server(token: token) { [weak self] script in
            await MainActor.run { self?.received(script) ?? false }
        }
        server = made
        Task {
            do {
                let port = try await made.start()
                guard server === made else { return }
                let host = Self.localAddress() ?? "127.0.0.1"
                address = "http://\(host):\(port)/\(token)"
            } catch { note = error.localizedDescription }
        }
    }

    /// Closes the listener and drops anything not yet accepted.
    func stop() {
        server?.stop(); server = nil
        address = nil; pendingName = nil; pendingScript = nil
    }

    private func received(_ script: String) -> Bool {
        guard pendingScript == nil else { return false }
        pendingScript = script
        pendingName = MusicExtension.header(script)["name"] ?? L10n.text("Music Extension")
        note = nil
        return true
    }

    func reject() { pendingScript = nil; pendingName = nil; note = nil }

    func accept(_ model: MusicExtensionsModel) {
        guard let script = pendingScript else { return }
        pendingScript = nil; pendingName = nil
        model.add(script: script)
    }

    nonisolated static func localAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: String?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let sa = entry.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let text = String(cString: buffer)
                if String(cString: entry.pointee.ifa_name).hasPrefix("en") { return text }
                found = found ?? text
            }
        }
        return found
    }

    /// The listener: GET /token gives the page, POST /token takes the script text. Everything else is 404.
    final class Server: @unchecked Sendable {
        private let token: String
        private let deliver: @Sendable (String) async -> Bool
        private let queue = DispatchQueue(label: "xiplayer.extension.receiver")
        private var listener: NWListener?
        private let lock = NSLock()
        private var open = 0
        init(token: String, deliver: @escaping @Sendable (String) async -> Bool) { self.token = token; self.deliver = deliver }

        func start() async throws -> UInt16 {
            let server = try NWListener(using: .tcp)
            listener = server
            server.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            return try await withCheckedThrowingContinuation { continuation in
                let once = NSLock(); var done = false
                server.stateUpdateHandler = { state in
                    once.lock(); defer { once.unlock() }
                    guard !done else { return }
                    switch state {
                    case .ready: done = true; continuation.resume(returning: server.port?.rawValue ?? 0)
                    case .failed(let error): done = true; continuation.resume(throwing: error)
                    default: break
                    }
                }
                server.start(queue: queue)
            }
        }

        func stop() { listener?.cancel(); listener = nil }

        private func accept(_ connection: NWConnection) {
            lock.lock(); let busy = open >= 4; if !busy { open += 1 }; lock.unlock()
            guard !busy else { connection.cancel(); return }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 20) { connection.cancel() }
            read(connection, Data())
        }

        private func finish(_ connection: NWConnection, _ status: String, _ type: String, _ body: Data) {
            var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
            head += ""
            var out = Data(head.utf8); out.append(body)
            connection.send(content: out, completion: .contentProcessed { [weak self] _ in
                connection.cancel()
                self?.lock.lock(); self?.open -= 1; self?.lock.unlock()
            })
        }

        private func read(_ connection: NWConnection, _ buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if buffer.count > MusicExtensionReceiver.sizeLimit + 8192 { self.finish(connection, "413 Payload Too Large", "text/plain", Data("too large".utf8)); return }
                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                    let lines = head.components(separatedBy: "\r\n")
                    let parts = lines[0].split(separator: " ").map(String.init)
                    let length = lines.dropFirst().compactMap { line -> Int? in
                        let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        return kv.count == 2 && kv[0].lowercased() == "content-length" ? Int(kv[1]) : nil
                    }.first ?? 0
                    guard parts.count >= 2, parts[1] == "/\(self.token)" else { self.finish(connection, "404 Not Found", "text/plain", Data("not found".utf8)); return }
                    if parts[0] == "GET" { self.finish(connection, "200 OK", "text/html; charset=utf-8", Data(Self.page.utf8)); return }
                    guard parts[0] == "POST" else { self.finish(connection, "405 Method Not Allowed", "text/plain", Data("no".utf8)); return }
                    guard length > 0, length <= MusicExtensionReceiver.sizeLimit else { self.finish(connection, "413 Payload Too Large", "text/plain", Data("size".utf8)); return }
                    let body = buffer[range.upperBound...]
                    if body.count >= length {
                        let text = String(data: body.prefix(length), encoding: .utf8)
                        guard let text else { self.finish(connection, "400 Bad Request", "text/plain", Data("not text".utf8)); return }
                        Task {
                            let taken = await self.deliver(text)
                            self.finish(connection, taken ? "200 OK" : "409 Conflict", "text/plain; charset=utf-8", Data((taken ? "OK" : "BUSY").utf8))
                        }
                        return
                    }
                }
                if complete || error != nil { connection.cancel(); self.lock.lock(); self.open -= 1; self.lock.unlock(); return }
                self.read(connection, buffer)
            }
        }

        static let page = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>XiPlayer</title></head><body style="font-family:-apple-system,sans-serif;max-width:560px;margin:32px auto;padding:0 16px">
        <h2>Add a music extension</h2>
        <p>Pick the script (.js) file. It is sent to your Apple TV, which asks you to confirm.</p>
        <input id="f" type="file" accept=".js,text/javascript,text/plain"><p><button id="b" style="font-size:18px;padding:10px 20px">Send to Apple TV</button></p>
        <p id="m"></p>
        <script>
        document.getElementById('b').onclick=async function(){
          var m=document.getElementById('m'),f=document.getElementById('f').files[0];
          if(!f){m.textContent='Pick a file first.';return}
          try{var t=await f.text();var r=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'text/plain'},body:t});
          var s=await r.text();m.textContent=r.ok?'Sent. Confirm on your Apple TV.':(r.status==409?'The TV is already waiting for an answer.':'Failed: '+s)}
          catch(e){m.textContent='Failed: '+e}
        }
        </script></body></html>
        """
    }
}

struct MusicExtensionReceiveScreen: View {
    let model: MusicExtensionsModel
    @State private var receiver = MusicExtensionReceiver()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 28) {
            Text(L10n.text("Add from Phone")).font(.title2.bold())
            Text(L10n.text("On a phone or computer on the same Wi-Fi, open this address and pick the extension file:")).multilineTextAlignment(.center)
            Text(receiver.address ?? L10n.text("Starting…")).font(.system(size: 34, weight: .semibold, design: .monospaced))
                .accessibilityIdentifier("ext.receiver.address")
            if let name = receiver.pendingName {
                Text(L10n.text("Received “%@”. Add it?", name)).font(.headline).accessibilityIdentifier("ext.receiver.pending")
                HStack(spacing: 24) {
                    Button(L10n.text("Add")) { receiver.accept(model); dismiss() }.accessibilityIdentifier("ext.receiver.accept")
                    Button(L10n.text("Discard")) { receiver.reject() }.accessibilityIdentifier("ext.receiver.reject")
                }
            }
            if let note = receiver.note { Text(note).foregroundStyle(.secondary) }
            Button(L10n.text("Close")) { dismiss() }.accessibilityIdentifier("ext.receiver.close")
        }
        .padding(60)
        .onAppear { receiver.start() }
        .onDisappear { receiver.stop() }
    }
}
#endif
