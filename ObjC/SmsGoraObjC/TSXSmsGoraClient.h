//
//  TSXSmsGoraClient.h
//  SmsGoraObjC - SMS Gora SMS Gateway client for Objective-C, by Tekservix.
//
//  Send and receive SMS through your own Android phones and SIM cards.
//  You need a Tekservix account with SMS Gora and an API key (it starts with
//  "sgk_"). Create one at https://tekservix.com/smsgora/
//  API reference: https://tekservix.com/smsgora/docs/
//
//  MIT licensed.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for API and transport errors. For API errors the code is the HTTP status.
FOUNDATION_EXPORT NSErrorDomain const TSXSmsGoraErrorDomain;
/// userInfo key holding the raw response body (NSData) of a failed call.
FOUNDATION_EXPORT NSString *const TSXSmsGoraErrorBodyKey;
/// The library version.
FOUNDATION_EXPORT NSString *const TSXSmsGoraVersion;

/// Called on the session's delegate queue. On success `data` is the API's `data`
/// field (an NSDictionary, NSArray or other JSON value); on failure `error` is set.
typedef void (^TSXSmsGoraCompletion)(id _Nullable data, NSError *_Nullable error);

/// SMS Gora SMS Gateway client. Thread-safe; calls run on the given NSURLSession.
@interface TSXSmsGoraClient : NSObject

/// Client for the live API.
- (instancetype)initWithAPIKey:(NSString *)apiKey;
/// Client with another base URL or session (for tests or a proxy).
- (instancetype)initWithAPIKey:(NSString *)apiKey
                       baseURL:(NSURL *)baseURL
                       session:(NSURLSession *)session NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// `https://tekservix.com/smsgora/api/v1`
@property (class, nonatomic, readonly) NSURL *defaultBaseURL;
@property (nonatomic, readonly) NSURL *baseURL;
/// Request timeout in seconds (default 30).
@property (nonatomic) NSTimeInterval timeout;

#pragma mark Sending

/// One text to up to 1,000 numbers, from your best online phone.
- (NSURLSessionDataTask *)sendSMSTo:(NSArray<NSString *> *)recipients
                            message:(NSString *)message
                         completion:(TSXSmsGoraCompletion)completion;

/// Same, choosing the phone (deviceID), SIM (simSlot: 0 = SIM 1, 1 = SIM 2)
/// or an ISO 8601 time to send later. Pass nil to leave any of them out.
- (NSURLSessionDataTask *)sendSMSTo:(NSArray<NSString *> *)recipients
                            message:(NSString *)message
                           deviceID:(nullable NSNumber *)deviceID
                            simSlot:(nullable NSNumber *)simSlot
                         scheduleAt:(nullable NSString *)scheduleAt
                         completion:(TSXSmsGoraCompletion)completion;

/// Different texts for different people from one phone (up to 5,000 recipients).
/// Each message is a dictionary with "recipients" (array) and an optional "message";
/// `messageTemplate` is used for messages that have none.
- (NSURLSessionDataTask *)sendBulkSMSFromDevice:(NSInteger)deviceID
                                       messages:(NSArray<NSDictionary *> *)messages
                                messageTemplate:(nullable NSString *)messageTemplate
                                     completion:(TSXSmsGoraCompletion)completion;

#pragma mark Messages

/// One message; status is queued, dispatched, sent, delivered, failed or cancelled.
- (NSURLSessionDataTask *)getMessage:(NSInteger)messageID completion:(TSXSmsGoraCompletion)completion;
/// Cancels a queued or scheduled message.
- (NSURLSessionDataTask *)cancelMessage:(NSInteger)messageID completion:(TSXSmsGoraCompletion)completion;
/// Messages, filtered by direction, status, device_id, phone, since, page, limit.
- (NSURLSessionDataTask *)listMessagesWithQuery:(nullable NSDictionary<NSString *, NSString *> *)query
                                     completion:(TSXSmsGoraCompletion)completion;
/// Incoming SMS for one phone, or all phones when deviceID is nil.
- (NSURLSessionDataTask *)listReceivedSMSForDevice:(nullable NSNumber *)deviceID
                                             query:(nullable NSDictionary<NSString *, NSString *> *)query
                                        completion:(TSXSmsGoraCompletion)completion;
/// A bulk batch and its progress.
- (NSURLSessionDataTask *)getBatch:(NSInteger)batchID completion:(TSXSmsGoraCompletion)completion;

#pragma mark Phones and account

- (NSURLSessionDataTask *)listDevicesWithCompletion:(TSXSmsGoraCompletion)completion;
- (NSURLSessionDataTask *)getDevice:(NSInteger)deviceID completion:(TSXSmsGoraCompletion)completion;
/// Plan, limits and usage.
- (NSURLSessionDataTask *)getAccountWithCompletion:(TSXSmsGoraCompletion)completion;

#pragma mark Webhooks

- (NSURLSessionDataTask *)listWebhooksWithCompletion:(TSXSmsGoraCompletion)completion;
/// Adds a webhook for events such as "sms.received" or "sms.failed", optionally for one phone.
- (NSURLSessionDataTask *)createWebhookWithURL:(NSString *)url
                                        events:(NSArray<NSString *> *)events
                                      deviceID:(nullable NSNumber *)deviceID
                                    completion:(TSXSmsGoraCompletion)completion;
- (NSURLSessionDataTask *)deleteWebhook:(NSInteger)webhookID completion:(TSXSmsGoraCompletion)completion;

/// Checks the X-SmsGora-Signature header ("sha256=" + hex HMAC-SHA256 of the raw body,
/// keyed with your webhook secret) in constant time.
+ (BOOL)verifyWebhookBody:(NSData *)rawBody signature:(nullable NSString *)signature secret:(NSString *)secret;

#pragma mark Anything else

/// Calls any endpoint. `path` starts with "/", `body` is sent as JSON when not nil.
- (NSURLSessionDataTask *)requestWithMethod:(NSString *)method
                                       path:(NSString *)path
                                      query:(nullable NSDictionary<NSString *, NSString *> *)query
                                       body:(nullable id)body
                                 completion:(TSXSmsGoraCompletion)completion;

@end

NS_ASSUME_NONNULL_END
