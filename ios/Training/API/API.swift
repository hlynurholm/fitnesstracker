import Foundation
import Observation
import Security

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Client for the Cloudflare Worker. The Worker stays the source of truth: this only reads and writes through /api.
/// Writes that fail because the network is down are queued on the phone and replayed later, like the web app does.
@MainActor @Observable
final class API {
    static let shared = API()
    static let defaultBaseURL = "https://fitness-tracker.hlynurholm97.workers.dev"

    var baseURL: String { didSet { UserDefaults.standard.set(baseURL, forKey: "baseURL") } }
    private(set) var hasToken: Bool
    /// True when the last read was served from the on-device cache.
    private(set) var offline = false
    private(set) var pendingWrites = 0

    private var token: String?
    private var queue: [QueuedWrite] = []
    private var flushing = false
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private init() {
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? Self.defaultBaseURL
        var saved = Keychain.read()
        #if DEBUG
        // Debug builds can be pointed at a local `wrangler dev` from the launch environment (see ios/README.md).
        let env = ProcessInfo.processInfo.environment
        if let url = env["TRAINING_BASE_URL"] { baseURL = url }
        if let t = env["TRAINING_TOKEN"] { saved = t }
        #endif
        token = saved
        hasToken = saved != nil
        queue = (try? JSONDecoder().decode([QueuedWrite].self, from: Data(contentsOf: Self.queueFile))) ?? []
        pendingWrites = queue.count
    }

    /// The API token lives in the Keychain only. It is never written to disk in plain text or to the repo.
    func setToken(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        token = (trimmed?.isEmpty ?? true) ? nil : trimmed
        Keychain.write(token)
        hasToken = token != nil
    }

    // MARK: Reads

    /// GET and decode. With `cache`, the last good response is kept on the phone and used when the network is down.
    func get<T: Decodable>(_ path: String, cache: Bool = false) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path, cache: cache))
    }

    func data(_ path: String, cache: Bool = false) async throws -> Data {
        do {
            let data = try await perform(request("GET", path))
            if cache { try? data.write(to: Self.cacheFile(path)) }
            offline = false
            return data
        } catch let error as URLError {
            if cache, let data = try? Data(contentsOf: Self.cacheFile(path)) { offline = true; return data }
            throw APIError(message: error.localizedDescription)
        }
    }

    // MARK: Writes

    /// Send JSON and decode the response. Throws on any failure.
    @discardableResult
    func send<T: Decodable>(_ method: String, _ path: String, _ body: [String: Any?] = [:]) async throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: await perform(request(method, path, json: body)))
        } catch let error as URLError {
            throw APIError(message: error.localizedDescription)
        }
    }

    func send(_ method: String, _ path: String, _ body: [String: Any?] = [:]) async throws {
        let _: Ignored = try await send(method, path, body)
    }

    /// Write that must not be lost: on a network failure it is queued under `key` (newest body per key wins) and nil is returned.
    func write<T: Decodable>(_ method: String, _ path: String, _ body: [String: Any?], key: String) async throws -> T? {
        let json = Self.json(body)
        do {
            let data = try await perform(request(method, path, body: json))
            Task { await flush() }
            return try JSONDecoder().decode(T.self, from: data)
        } catch is URLError {
            queue.removeAll { $0.key == key }
            queue.append(QueuedWrite(key: key, method: method, path: path, body: json))
            saveQueue()
            return nil
        }
    }

    /// Replays queued writes in order. Stops at the first network failure; drops writes the server rejects.
    func flush() async {
        guard !flushing, !queue.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        while let item = queue.first {
            do {
                _ = try await perform(request(item.method, item.path, body: item.body))
            } catch is URLError {
                break
            } catch {
                // Rejected by the server: keeping it would block the queue forever.
            }
            queue.removeFirst()
            saveQueue()
        }
    }

    /// Multipart upload of Garmin or MyFitnessPal files to /api/uploads.
    func upload(files: [URL], fields: [String: String]) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        for url in files {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent.replacingOccurrences(of: "\"", with: "")
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        var req = try request("POST", "/api/uploads")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 120
        do {
            return try JSONDecoder().decode(UploadResponse.self, from: await perform(req))
        } catch let error as URLError {
            throw APIError(message: error.localizedDescription)
        }
    }

    // MARK: Plumbing

    private func request(_ method: String, _ path: String, json: [String: Any?]) throws -> URLRequest {
        try request(method, path, body: method == "GET" || method == "DELETE" ? nil : Self.json(json))
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) throws -> URLRequest {
        guard let token else { throw APIError(message: "Add the API token in Settings.") }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + path), url.scheme?.hasPrefix("http") == true else {
            throw APIError(message: "The server address in Settings is not a valid URL.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    /// Runs the request. URLError means the network failed; APIError means the server answered with an error.
    private func perform(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 { throw APIError(message: "The server rejected the API token. Check it in Settings.") }
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
            throw APIError(message: message ?? "Request failed (\(status))")
        }
        return data
    }

    private static func json(_ body: [String: Any?]) -> Data {
        (try? JSONSerialization.data(withJSONObject: body.mapValues { $0 ?? NSNull() })) ?? Data("{}".utf8)
    }

    private func saveQueue() {
        pendingWrites = queue.count
        try? JSONEncoder().encode(queue).write(to: Self.queueFile, options: .atomic)
    }

    private static let queueFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("write-queue.json")
    }()

    private static func cacheFile(_ path: String) -> URL {
        let name = path.replacingOccurrences(of: "[^A-Za-z0-9-]", with: "_", options: .regularExpression)
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("api\(name).json")
    }

    private struct QueuedWrite: Codable { let key: String; let method: String; let path: String; let body: Data }
    private struct ServerError: Decodable { let error: String }
    private struct Ignored: Decodable { init(from decoder: Decoder) throws {} }
}

/// Encodes a plan so it can go into a request body with its keys untouched.
extension Array where Element == PlanEntry {
    var jsonObject: Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) ?? [] }
}

private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hlynurholm.training",
        kSecAttrAccount as String: "api-token",
    ]

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String?) {
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var q = query
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
