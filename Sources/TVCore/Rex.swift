import Foundation
import CryptoKit

/// Rex / ForwardWidgets modules: a `.rex` collection lists modules, each a plain JavaScript file that sets
/// `WidgetMetadata` and names the functions that return lists of titles. This runs the plain ones on QuickJS with a
/// small host (`assets://rex/prelude.js`); encrypted modules (`REXENC`) are recognised and reported, not run.
public struct RexCollection: Codable, Hashable, Sendable {
    public struct Widget: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var version: String
        public var author: String
        public var url: String
        public init(id: String, title: String, version: String = "", author: String = "", url: String) {
            self.id = id; self.title = title; self.version = version; self.author = author; self.url = url
        }
    }
    public var title: String
    public var widgets: [Widget]

    /// Reads a collection tolerantly: a module without a title or an address is skipped.
    public static func parse(_ data: Data) throws -> RexCollection {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data).object, let list = root["widgets"]?.array else {
            throw RexError.failed(L10n.text("This is not a Rex subscription."))
        }
        let widgets: [Widget] = list.compactMap { value in
            guard let object = value.object, let url = object["url"]?.string, !url.isEmpty else { return nil }
            let title = object["title"]?.string ?? object["id"]?.string ?? url
            return Widget(id: object["id"]?.string ?? url, title: title, version: object["version"]?.string ?? "", author: object["author"]?.string ?? "", url: url)
        }
        return RexCollection(title: root["title"]?.string ?? "Rex", widgets: widgets)
    }
}

public enum RexError: Error, LocalizedError, Sendable {
    case encrypted
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .encrypted: L10n.text("Encrypted Rex modules are not supported yet.")
        case .failed(let message): message
        }
    }
}

public struct RexParam: Hashable, Sendable {
    public struct Option: Hashable, Sendable { public let title: String; public let value: String }
    public let name: String
    public let title: String
    public let type: String
    public let value: String
    public let options: [Option]
}

public struct RexFunction: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let functionName: String
    public let params: [RexParam]
    /// A "stream" module resolves a play address rather than listing titles.
    public let listsTitles: Bool
}

public struct RexModule: Hashable, Sendable {
    public let widget: RexCollection.Widget
    public let title: String
    public let functions: [RexFunction]
    public let globals: [String: String]
}

public struct RexItem: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let poster: URL?
    public let overview: String
    public let rating: Double?
    public let year: Int?
}

public actor RexRuntime {
    public static let shared = RexRuntime()
    private struct Loaded { let session: ScriptSession; let module: RexModule }
    private var loaded: [String: Loaded] = [:]
    private var recent: [String] = []
    private static let maximumSessions = 6

    /// The module's source, or `.encrypted` for the Rex-encrypted kind.
    static func source(_ address: String) async throws -> String {
        if address.hasPrefix("assets://") {
            guard let text = ScriptAssets.bundled(address) else { throw RexError.failed("Missing bundled module") }
            return text
        }
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw RexError.failed(L10n.text("This is not a web address.")) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) { throw RexError.failed("HTTP \(code)") }
        let text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("REXENC") { throw RexError.encrypted }
        return text
    }

    public static func fetchCollection(_ address: String) async throws -> RexCollection {
        if address.hasPrefix("assets://") {
            guard let text = ScriptAssets.bundled(address) else { throw RexError.failed("Missing bundled collection") }
            return try RexCollection.parse(Data(text.utf8))
        }
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw RexError.failed(L10n.text("This is not a web address.")) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try RexCollection.parse(data)
    }

    /// Loads one module (reusing its runtime) and reads its metadata.
    public func module(_ widget: RexCollection.Widget) async throws -> RexModule {
        try await load(widget).module
    }

    /// Whether a module can be opened, without keeping it: nil when it can, else why not.
    public func probe(_ widget: RexCollection.Widget) async -> RexError? {
        do { _ = try await load(widget); return nil } catch let error as RexError { return error } catch { return .failed(error.localizedDescription) }
    }

    /// One function's titles. `params` start from the function's defaults; `overrides` replace them.
    public func items(_ widget: RexCollection.Widget, function: RexFunction, overrides: [String: String], page: Int) async throws -> [RexItem] {
        let entry = try await load(widget)
        var params = entry.module.globals
        for param in function.params where !param.value.isEmpty { params[param.name] = param.value }
        for (key, value) in overrides { params[key] = value }
        if function.params.contains(where: { $0.type == "page" }) { params["page"] = String(page) }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: [function.functionName], options: []), as: UTF8.self).dropFirst().dropLast()
        let envelope = await entry.session.evaluate("__rex.call(\(literal), \(json))", within: 40)
        guard let value = envelope["value"]?.object else {
            throw RexError.failed(String((envelope["error"]?.string ?? "The module did not answer").prefix(200)))
        }
        if let message = value["error"]?.string { throw RexError.failed(message) }
        return (value["items"]?.array ?? []).compactMap(Self.item)
    }

    private func load(_ widget: RexCollection.Widget) async throws -> Loaded {
        if let existing = loaded[widget.url] {
            recent.removeAll { $0 == widget.url }; recent.append(widget.url)
            return existing
        }
        let source = try await Self.source(widget.url)
        let profile = ScriptAssets.profiles.appendingPathComponent("rex-" + PluginChecksum.sha256(Data(widget.url.utf8)).prefix(16), isDirectory: true)
        let session = try await ScriptSession.start(module: "assets://rex/prelude.js", supplied: ["rex://module": source], profile: profile, label: "rex " + widget.title)
        let envelope = await session.evaluate("__rex.load()", within: 15)
        guard let meta = envelope["value"]?.object else {
            session.close()
            throw RexError.failed(String((envelope["error"]?.string ?? "The module could not be read").prefix(200)))
        }
        let entry = Loaded(session: session, module: Self.module(widget, meta))
        loaded[widget.url] = entry
        recent.append(widget.url)
        while recent.count > Self.maximumSessions {
            let evicted = recent.removeFirst()
            loaded.removeValue(forKey: evicted)?.session.close()
        }
        return entry
    }

    static func module(_ widget: RexCollection.Widget, _ meta: [String: JSONValue]) -> RexModule {
        func params(_ list: [JSONValue]?) -> [RexParam] {
            (list ?? []).compactMap { value in
                guard let object = value.object, let name = object["name"]?.string else { return nil }
                let options = (object["enumOptions"]?.array ?? []).compactMap { option -> RexParam.Option? in
                    guard let o = option.object, let value = o["value"]?.string else { return nil }
                    return RexParam.Option(title: o["title"]?.string ?? value, value: value)
                }
                return RexParam(name: name, title: object["title"]?.string ?? name, type: object["type"]?.string ?? "input",
                                value: object["value"]?.string ?? "", options: options)
            }
        }
        var globals: [String: String] = [:]
        for param in params(meta["globalParams"]?.array) where !param.value.isEmpty { globals[param.name] = param.value }
        let functions: [RexFunction] = (meta["modules"]?.array ?? []).compactMap { value in
            guard let object = value.object, let name = object["functionName"]?.string else { return nil }
            let type = object["type"]?.string ?? ""
            return RexFunction(id: object["id"]?.string ?? name, title: object["title"]?.string ?? name, functionName: name,
                               params: params(object["params"]?.array), listsTitles: type.isEmpty || type == "list")
        }
        return RexModule(widget: widget, title: meta["title"]?.string ?? widget.title, functions: functions, globals: globals)
    }

    static func item(_ value: JSONValue) -> RexItem? {
        guard let object = value.object, let title = object["title"]?.string, !title.isEmpty else { return nil }
        let date = object["releaseDate"]?.string ?? ""
        var poster = object["posterPath"]?.string ?? ""
        if poster.isEmpty { poster = object["backdropPath"]?.string ?? "" }
        var rating: Double?
        if case .number(let score)? = object["rating"], score > 0 { rating = score }
        return RexItem(id: object["id"]?.string ?? title, title: title, subtitle: object["subtitle"]?.string ?? object["genreTitle"]?.string ?? "",
                       poster: poster.isEmpty ? nil : URL(string: poster.replacingOccurrences(of: "http://", with: "https://")),
                       overview: object["description"]?.string ?? "", rating: rating, year: Int(date.prefix(4)))
    }
}

/// The collections a person imported (their addresses), kept on this device.
public enum RexStore {
    private static let key = "rex.collections"
    public static var addresses: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
