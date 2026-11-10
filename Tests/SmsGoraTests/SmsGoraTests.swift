import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SmsGora

final class Recorder {
    var last: URLRequest?
    var status = 200
    var reply = #"{"success":true,"data":{"message_ids":[1873]}}"#
    var headers: [String: String] = ["Content-Type": "application/json"]

    var lastBody: [String: Any]? {
        guard let data = last?.httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

final class SmsGoraTests: XCTestCase {
    func makeClient(_ r: Recorder) -> SmsGoraClient {
        SmsGoraClient(apiKey: "sgk_test", baseURL: "https://example.test/api/", transport: { req in
            r.last = req
            let res = HTTPURLResponse(url: req.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
            return (Data(r.reply.utf8), res)
        })
    }

    func testSendSMS() async throws {
        let r = Recorder()
        let result = try await makeClient(r).sendSMS(to: "+15551234567", message: "Hi")
        XCTAssertEqual(result["message_ids"]?[0]?.intValue, 1873)
        XCTAssertEqual(r.last?.httpMethod, "POST")
        XCTAssertEqual(r.last?.url?.absoluteString, "https://example.test/api/send-sms")
        XCTAssertEqual(r.last?.value(forHTTPHeaderField: "x-api-key"), "sgk_test")
        XCTAssertEqual(r.lastBody?["recipients"] as? [String], ["+15551234567"])
        XCTAssertEqual(r.lastBody?["message"] as? String, "Hi")
        XCTAssertNil(r.lastBody?["sim_slot"])
    }

    func testSendFromDeviceScheduled() async throws {
        let r = Recorder()
        _ = try await makeClient(r).sendSMS(to: ["+1", "+2"], message: "x", deviceId: 42, simSlot: 1,
                                            scheduleAt: Date(timeIntervalSince1970: 1_796_112_000))
        XCTAssertEqual(r.last?.url?.path, "/api/devices/42/send-sms")
        XCTAssertEqual(r.lastBody?["sim_slot"] as? Int, 1)
        XCTAssertEqual(r.lastBody?["schedule_at"] as? String, "2026-12-01T08:00:00Z")
        XCTAssertEqual((r.lastBody?["recipients"] as? [String])?.count, 2)
    }

    func testBulkAndPaths() async throws {
        let r = Recorder()
        let c = makeClient(r)
        _ = try await c.sendBulkSMS(deviceId: 42, messages: [BulkMessage(recipients: ["+1"], message: "a"), BulkMessage(recipients: ["+2"])],
                                    messageTemplate: "t")
        XCTAssertEqual(r.last?.url?.path, "/api/devices/42/send-bulk-sms")
        XCTAssertEqual(r.lastBody?["messageTemplate"] as? String, "t")
        let items = r.lastBody?["messages"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 2)
        XCTAssertNil(items?[1]["message"])

        _ = try await c.cancelMessage(7)
        XCTAssertEqual(r.last?.url?.path, "/api/messages/7/cancel")
        _ = try await c.listReceivedSMS(["since": "2026-11-01", "phone": "+1555"])
        XCTAssertEqual(r.last?.url?.absoluteString, "https://example.test/api/received-sms?phone=%2B1555&since=2026-11-01")
        _ = try await c.listReceivedSMS(deviceId: 3)
        XCTAssertEqual(r.last?.url?.path, "/api/devices/3/get-received-sms")
        _ = try await c.createWebhook(url: "https://my.app/hook")
        XCTAssertEqual(r.lastBody?["events"] as? [String], ["sms.received"])
        _ = try await c.deleteWebhook(9)
        XCTAssertEqual(r.last?.httpMethod, "DELETE")
    }

    func testErrors() async {
        let r = Recorder()
        r.status = 429
        r.reply = #"{"success":false,"message":"Too many requests","errors":{"recipients":["bad"]}}"#
        r.headers["Retry-After"] = "12"
        do {
            _ = try await makeClient(r).getAccount()
            XCTFail("expected error")
        } catch let e as SmsGoraError {
            XCTAssertEqual(e.status, 429)
            XCTAssertEqual(e.message, "Too many requests")
            XCTAssertEqual(e.retryAfter, 12)
            XCTAssertEqual(e.errors?["recipients"]?[0]?.stringValue, "bad")
        } catch {
            XCTFail("wrong error \(error)")
        }

        r.status = 502
        r.reply = "<html>bad gateway</html>"
        do {
            _ = try await makeClient(r).listDevices()
            XCTFail("expected error")
        } catch let e as SmsGoraError {
            XCTAssertEqual(e.message, "HTTP 502")
            XCTAssertEqual(e.body, .string("<html>bad gateway</html>"))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testHMAC() {
        XCTAssertEqual(HMACSHA256.hex(HMACSHA256.sha256([])), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(HMACSHA256.hex(HMACSHA256.hmac(key: Array(repeating: UInt8(ascii: "k"), count: 100),
                                                      message: Array(String(repeating: "abc", count: 50).utf8))),
                       "b2f2222673f70e4563af636099533dc20d077b754c16c8c3962f57e789350dd0")
    }

    func testVerifyWebhook() {
        let body = #"{"event":"sms.received","data":{"from":"+15551234567"}}"#
        let sig = "sha256=e125c07dfbecb498e8979383d7b9f0815efb128755409794b486d4bbb7199583"
        XCTAssertTrue(SmsGoraClient.verifyWebhook(rawBody: body, signature: sig, secret: "whsec_test"))
        XCTAssertFalse(SmsGoraClient.verifyWebhook(rawBody: body, signature: sig, secret: "other"))
        XCTAssertFalse(SmsGoraClient.verifyWebhook(rawBody: body + " ", signature: sig, secret: "whsec_test"))
        XCTAssertFalse(SmsGoraClient.verifyWebhook(rawBody: body, signature: nil, secret: "whsec_test"))
    }
}
