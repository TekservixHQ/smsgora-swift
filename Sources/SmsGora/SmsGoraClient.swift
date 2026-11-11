import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends a request and returns the raw body and response. Swap it out in tests
/// or to add your own logging, retries or proxy.
public typealias SmsGoraTransport = (URLRequest) async throws -> (Data, HTTPURLResponse)

/// Thrown when the API answers with an error.
public struct SmsGoraError: Error, LocalizedError, CustomStringConvertible {
    /// HTTP status (0 when the request never reached the API).
    public let status: Int
    public let message: String
    /// Field errors, when the API sends them.
    public let errors: JSONValue?
    /// Parsed JSON body, or the raw text in `.string` when it was not JSON.
    public let body: JSONValue?
    /// Seconds to wait before retrying (sent with 429).
    public let retryAfter: Double?

    public var description: String { "SmsGora: \(message) (HTTP \(status))" }
    public var errorDescription: String? { description }
}

/// One entry for `sendBulkSMS`. Leave `message` nil to use the shared template.
public struct BulkMessage {
    public var recipients: [String]
    public var message: String?

    public init(recipients: [String], message: String? = nil) {
        self.recipients = recipients
        self.message = message
    }
}

/// Swift client for the SMS Gora SMS Gateway API (https://tekservix.com/smsgora/).
///
///     let sms = SmsGoraClient(apiKey: ProcessInfo.processInfo.environment["SMSGORA_KEY"]!)
///     let result = try await sms.sendSMS(to: "+15551234567", message: "Your code is 482913")
///
/// Keep the key on your server. Never ship it inside an iOS or macOS app.
public final class SmsGoraClient {
    public static let version = "1.0.1"
    public static let defaultBaseURL = "https://tekservix.com/smsgora/api/v1"

    public let baseURL: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let transport: SmsGoraTransport

    /// - Parameters:
    ///   - apiKey: your SMS Gora API key (starts with `sgk_`), from SMS Gora -> API keys.
    ///   - baseURL: change only for testing.
    ///   - timeout: seconds per request.
    ///   - transport: custom HTTP sender; defaults to `URLSession.shared`.
    public init(apiKey: String, baseURL: String = SmsGoraClient.defaultBaseURL, timeout: TimeInterval = 30, transport: SmsGoraTransport? = nil) {
        precondition(!apiKey.isEmpty, "SmsGora: apiKey is required (create one in SMS Gora -> API keys)")
        self.apiKey = apiKey
        var url = baseURL
        while url.hasSuffix("/") { url.removeLast() }
        self.baseURL = url
        self.timeout = timeout
        self.transport = transport ?? SmsGoraClient.urlSessionTransport(.shared)
    }

    /// Default transport built on URLSession (works on Apple platforms and Linux).
    public static func urlSessionTransport(_ session: URLSession) -> SmsGoraTransport {
        return { request in
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let http = response as? HTTPURLResponse {
                        continuation.resume(returning: (data ?? Data(), http))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                task.resume()
            }
        }
    }

    // MARK: - Any endpoint

    /// Call any documented endpoint, e.g. `request("GET", "/devices")`. Returns the `data` field.
    @discardableResult
    public func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> JSONValue {
        guard let url = URL(string: baseURL + path) else {
            throw SmsGoraError(status: 0, message: "Invalid URL: \(baseURL + path)", errors: nil, body: nil, retryAfter: nil)
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method.uppercased()
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("smsgora-swift/\(SmsGoraClient.version)", forHTTPHeaderField: "User-Agent")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }

        let (data, response) = try await transport(req)
        let status = response.statusCode
        let json: JSONValue? = data.isEmpty ? nil : try? JSONDecoder().decode(JSONValue.self, from: data)

        if status >= 400 || json?["success"] == .bool(false) {
            throw SmsGoraError(
                status: status,
                message: json?["message"]?.stringValue ?? "HTTP \(status)",
                errors: json?["errors"],
                body: json ?? .string(String(decoding: data, as: UTF8.self)),
                retryAfter: header(response, "Retry-After").flatMap { Double($0) }
            )
        }
        if let inner = json?["data"] { return inner }
        return json ?? .null
    }

    // MARK: - Sending

    /// Send an SMS to up to 1,000 numbers. Uses your best online phone unless `deviceId` is given.
    /// - Parameters:
    ///   - simSlot: 0 = SIM 1, 1 = SIM 2.
    ///   - scheduleAt: send later instead of now.
    /// - Returns: `{"message_ids": [...]}`.
    @discardableResult
    public func sendSMS(to recipients: [String], message: String, deviceId: Int? = nil, simSlot: Int? = nil, scheduleAt: Date? = nil) async throws -> JSONValue {
        var body: [String: Any] = ["recipients": recipients, "message": message]
        if let simSlot = simSlot { body["sim_slot"] = simSlot }
        if let scheduleAt = scheduleAt { body["schedule_at"] = ISO8601DateFormatter().string(from: scheduleAt) }
        let path = deviceId.map { "/devices/\($0)/send-sms" } ?? "/send-sms"
        return try await request("POST", path, body: body)
    }

    /// Send an SMS to one number.
    @discardableResult
    public func sendSMS(to recipient: String, message: String, deviceId: Int? = nil, simSlot: Int? = nil, scheduleAt: Date? = nil) async throws -> JSONValue {
        try await sendSMS(to: [recipient], message: message, deviceId: deviceId, simSlot: simSlot, scheduleAt: scheduleAt)
    }

    /// Different texts for different people in one call (up to 5,000 recipients).
    @discardableResult
    public func sendBulkSMS(deviceId: Int, messages: [BulkMessage], messageTemplate: String? = nil) async throws -> JSONValue {
        let items: [[String: Any]] = messages.map { m in
            var item: [String: Any] = ["recipients": m.recipients]
            if let text = m.message { item["message"] = text }
            return item
        }
        var body: [String: Any] = ["messages": items]
        if let template = messageTemplate { body["messageTemplate"] = template }
        return try await request("POST", "/devices/\(deviceId)/send-bulk-sms", body: body)
    }

    // MARK: - Messages

    /// Status is queued, dispatched, sent, delivered, failed or cancelled.
    public func getMessage(_ id: Int) async throws -> JSONValue {
        try await request("GET", "/messages/\(id)")
    }

    /// Cancel a queued or scheduled message.
    @discardableResult
    public func cancelMessage(_ id: Int) async throws -> JSONValue {
        try await request("POST", "/messages/\(id)/cancel")
    }

    /// Filters: direction (in/out), status, device_id, phone, since, after_id, page, limit.
    public func listMessages(_ filters: [String: String] = [:]) async throws -> JSONValue {
        try await request("GET", "/messages" + query(filters))
    }

    /// Incoming SMS for all phones, or one phone with `deviceId`.
    public func listReceivedSMS(deviceId: Int? = nil, _ filters: [String: String] = [:]) async throws -> JSONValue {
        let path = deviceId.map { "/devices/\($0)/get-received-sms" } ?? "/received-sms"
        return try await request("GET", path + query(filters))
    }

    public func getBatch(_ id: Int) async throws -> JSONValue {
        try await request("GET", "/batches/\(id)")
    }

    // MARK: - Phones and account

    /// Your linked Android phones.
    public func listDevices() async throws -> JSONValue {
        try await request("GET", "/devices")
    }

    public func getDevice(_ id: Int) async throws -> JSONValue {
        try await request("GET", "/devices/\(id)")
    }

    /// Account, plan and usage.
    public func getAccount() async throws -> JSONValue {
        try await request("GET", "/account")
    }

    // MARK: - Webhooks

    public func listWebhooks() async throws -> JSONValue {
        try await request("GET", "/webhooks")
    }

    /// Register a webhook. The answer includes the secret (returned only once).
    @discardableResult
    public func createWebhook(url: String, events: [String] = ["sms.received"], deviceId: Int? = nil) async throws -> JSONValue {
        var body: [String: Any] = ["url": url, "events": events]
        if let deviceId = deviceId {
            body["device_id"] = deviceId
        } else {
            body["device_id"] = NSNull()
        }
        return try await request("POST", "/webhooks", body: body)
    }

    @discardableResult
    public func deleteWebhook(_ id: Int) async throws -> JSONValue {
        try await request("DELETE", "/webhooks/\(id)")
    }

    /// Check the `X-SmsGora-Signature` header (`sha256=<hex HMAC-SHA256 of the raw body>`).
    /// Pass the raw request body exactly as received, before any JSON parsing.
    public static func verifyWebhook(rawBody: Data, signature: String?, secret: String) -> Bool {
        guard let signature = signature, !signature.isEmpty, !secret.isEmpty, !rawBody.isEmpty else { return false }
        let mac = HMACSHA256.hmac(key: Array(secret.utf8), message: Array(rawBody))
        let expected = "sha256=" + HMACSHA256.hex(mac)
        return HMACSHA256.equal(Array(expected.utf8), Array(signature.utf8))
    }

    public static func verifyWebhook(rawBody: String, signature: String?, secret: String) -> Bool {
        verifyWebhook(rawBody: Data(rawBody.utf8), signature: signature, secret: secret)
    }

    // MARK: - Helpers

    private func query(_ params: [String: String]) -> String {
        let pairs = params.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
        if pairs.isEmpty { return "" }
        return "?" + pairs.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&")
    }

    private func escape(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func header(_ response: HTTPURLResponse, _ name: String) -> String? {
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, k.caseInsensitiveCompare(name) == .orderedSame { return "\(value)" }
        }
        return nil
    }
}
