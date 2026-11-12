# SMS Gora Swift client

[![tests](https://github.com/TekservixHQ/smsgora-swift/actions/workflows/tests.yml/badge.svg)](https://github.com/TekservixHQ/smsgora-swift/actions/workflows/tests.yml)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FTekservixHQ%2Fsmsgora-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/TekservixHQ/smsgora-swift)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FTekservixHQ%2Fsmsgora-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/TekservixHQ/smsgora-swift)

**SMS Gora SMS Gateway** - official Swift client: send and receive SMS through your own Android phones. By Tekservix.

Swift client for the [SMS Gora SMS Gateway](https://tekservix.com/smsgora/) API.

SMS Gora turns Android phones with ordinary SIM cards into an SMS gateway. Your server calls the API, a linked phone sends the text, and replies and delivery reports come back to you. There's no sender ID registration and no per-message fee from us: your mobile operator bills the texts like any SMS.

- async/await, Swift 5.7+
- Linux (Vapor, Hummingbird), macOS, iOS, tvOS, watchOS
- No dependencies; webhook signature check built in (works on Linux, no CryptoKit needed)

## Install

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/TekservixHQ/smsgora-swift.git", from: "1.0.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "SmsGora", package: "smsgora-swift"),
    ]),
]
```

In Xcode: File -> Add Package Dependencies, then paste `https://github.com/TekservixHQ/smsgora-swift`.


## CocoaPods

```ruby
pod 'SmsGora', '~> 1.0'
```

## Objective-C

For Objective-C apps there is a separate pod with the same features, built on Foundation only:

```ruby
pod 'SmsGoraObjC', '~> 1.0'
```

```objc
#import <SmsGoraObjC/SmsGoraObjC.h>

TSXSmsGoraClient *client = [[TSXSmsGoraClient alloc] initWithAPIKey:@"sgk_your_key"];
[client sendSMSTo:@[@"+250788123456"]
          message:@"Your order #1042 has shipped."
       completion:^(id data, NSError *error) {
    if (error) NSLog(@"Failed: %@", error.localizedDescription);   // error.code = HTTP status
    else NSLog(@"Queued: %@", data);
}];

// Webhooks: check X-SmsGora-Signature
BOOL valid = [TSXSmsGoraClient verifyWebhookBody:rawBody signature:signatureHeader secret:@"whsec_..."];
```

## Quick start

Create an API key in the SMS Gora dashboard (SMS Gora -> API keys) and keep it on your server.

```swift
import SmsGora

let sms = SmsGoraClient(apiKey: Environment.get("SMSGORA_KEY")!) // Vapor; or ProcessInfo.processInfo.environment

let result = try await sms.sendSMS(to: "+15551234567", message: "Your verification code is 482913")
print(result["message_ids"]?[0]?.intValue ?? 0) // 1873
```

**Don't put the API key inside an iOS or macOS app.** Anyone can pull it out of the app bundle. From an app, call your own backend, and let the backend call SMS Gora.

## Sending

```swift
// Several recipients (up to 1,000 per call)
try await sms.sendSMS(to: ["+15551234567", "+447700900123"], message: "Your order has shipped")

// From a chosen phone and SIM, scheduled for later
try await sms.sendSMS(
    to: "+15551234567",
    message: "Reminder: your appointment is tomorrow at 10:00",
    deviceId: 42,
    simSlot: 1, // 0 = SIM 1, 1 = SIM 2
    scheduleAt: Date().addingTimeInterval(3600)
)

// Different texts for different people in one call (up to 5,000 recipients)
try await sms.sendBulkSMS(deviceId: 42, messages: [
    BulkMessage(recipients: ["+15551234567"], message: "Hi Aline, parcel #1042 is ready."),
    BulkMessage(recipients: ["+15557654321"]),
], messageTemplate: "Hello, your parcel is ready for pickup.")
```

## Delivery status and incoming SMS

```swift
let msg = try await sms.getMessage(1873)
msg["status"]?.stringValue // queued -> dispatched -> sent -> delivered (or failed)

try await sms.cancelMessage(1874) // works while queued or scheduled

let inbox   = try await sms.listReceivedSMS(["since": "2026-11-01", "limit": "50"])
let phones  = try await sms.listDevices()
let account = try await sms.getAccount()
```

Results are `JSONValue`: read them with subscripts (`result["data"]?[0]?["id"]`) and `.stringValue`, `.intValue`, `.boolValue`, or decode into your own type with `.decode(MyType.self)`.

Anything else in the [API reference](https://tekservix.com/smsgora/docs/) is one call away:

```swift
let batch = try await sms.request("GET", "/batches/311")
```

## Webhooks

Add your HTTPS URL in SMS Gora -> Webhooks (or with `createWebhook`) and keep the secret. Each request carries `X-SmsGora-Signature: sha256=...`, an HMAC-SHA256 of the raw body. Vapor example:

```swift
app.post("sms-webhook") { req async throws -> HTTPStatus in
    let raw = req.body.data.map { Data(buffer: $0) } ?? Data()
    guard SmsGoraClient.verifyWebhook(rawBody: raw,
                                      signature: req.headers.first(name: "X-SmsGora-Signature"),
                                      secret: Environment.get("SMSGORA_WEBHOOK_SECRET")!) else {
        return .unauthorized
    }
    let event = try JSONDecoder().decode(JSONValue.self, from: raw)
    if event["event"]?.stringValue == "sms.received" {
        // event["data"]?["from"], event["data"]?["message"]
    }
    return .ok // answer within 10 seconds; do slow work in a background job
}
```

## Errors

Failed calls throw `SmsGoraError` with `status`, `message`, field `errors` and, on 429, `retryAfter` in seconds.

```swift
do {
    try await sms.sendSMS(to: "+15551234567", message: "Hi")
} catch let e as SmsGoraError where e.status == 429 {
    // 300 requests/minute per key, or plan limit: wait e.retryAfter seconds
}
```

## Migrating from TextBee

SMS Gora accepts TextBee-style requests, so most integrations switch by changing the base URL and key. See the [compatibility notes](https://tekservix.com/smsgora/docs/).

## More from Tekservix

- [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/): send WhatsApp messages from your own number ([Swift client](https://github.com/TekservixHQ/waservix-swift))
- [AI Sales Agent](https://tekservix.com/ai-sales-agent): answers customers on WhatsApp and SMS using your website's content
- [Website to App](https://tekservix.com/mobile-apps): turn your website into Android and iOS apps
- SMS Gora is also available for Node.js, Python, PHP, Go, Java/Kotlin, .NET and Ruby: see [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
