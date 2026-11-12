//
//  TSXSmsGoraClient.m
//  SmsGoraObjC. MIT licensed.
//

#import "TSXSmsGoraClient.h"

#import <CommonCrypto/CommonHMAC.h>

NSErrorDomain const TSXSmsGoraErrorDomain = @"com.tekservix.smsgora";
NSString *const TSXSmsGoraErrorBodyKey = @"TSXSmsGoraErrorBody";
NSString *const TSXSmsGoraVersion = @"1.0.0";

@interface TSXSmsGoraClient ()
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation TSXSmsGoraClient

+ (NSURL *)defaultBaseURL {
    return [NSURL URLWithString:@"https://tekservix.com/smsgora/api/v1"];
}

- (instancetype)initWithAPIKey:(NSString *)apiKey {
    return [self initWithAPIKey:apiKey baseURL:[[self class] defaultBaseURL] session:[NSURLSession sharedSession]];
}

- (instancetype)initWithAPIKey:(NSString *)apiKey baseURL:(NSURL *)baseURL session:(NSURLSession *)session {
    NSParameterAssert(apiKey.length > 0);
    if ((self = [super init])) {
        _apiKey = [apiKey copy];
        NSString *base = baseURL.absoluteString;
        while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
        _baseURL = [NSURL URLWithString:base];
        _session = session;
        _timeout = 30;
    }
    return self;
}

#pragma mark Core

- (NSURLSessionDataTask *)requestWithMethod:(NSString *)method
                                       path:(NSString *)path
                                      query:(NSDictionary<NSString *, NSString *> *)query
                                       body:(id)body
                                 completion:(TSXSmsGoraCompletion)completion {
    NSURLComponents *components = [NSURLComponents componentsWithString:[self.baseURL.absoluteString stringByAppendingString:path]];
    if (query.count > 0) {
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
        for (NSString *key in [query.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [items addObject:[NSURLQueryItem queryItemWithName:key value:query[key]]];
        }
        components.queryItems = items;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    request.HTTPMethod = method;
    request.timeoutInterval = self.timeout;
    [request setValue:self.apiKey forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[@"smsgora-objc/" stringByAppendingString:TSXSmsGoraVersion] forHTTPHeaderField:@"User-Agent"];
    if (body) {
        NSError *jsonError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        if (!data) {
            NSURLSessionDataTask *noop = [self.session dataTaskWithURL:components.URL];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, jsonError); });
            return noop;
        }
        request.HTTPBody = data;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:NULL] : nil;
        if (status < 200 || status >= 300) {
            NSString *message = nil;
            if ([json isKindOfClass:[NSDictionary class]] && [json[@"message"] isKindOfClass:[NSString class]]) {
                message = json[@"message"];
            }
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"SMS Gora API error %ld: %@", (long)status,
                                               message ?: [NSHTTPURLResponse localizedStringForStatusCode:status]];
            if (data) info[TSXSmsGoraErrorBodyKey] = data;
            completion(nil, [NSError errorWithDomain:TSXSmsGoraErrorDomain code:status userInfo:info]);
            return;
        }
        if ([json isKindOfClass:[NSDictionary class]] && json[@"data"] != nil) {
            json = json[@"data"];
        }
        completion([json isKindOfClass:[NSNull class]] ? nil : json, nil);
    }];
    [task resume];
    return task;
}

- (NSURLSessionDataTask *)get:(NSString *)path completion:(TSXSmsGoraCompletion)completion {
    return [self requestWithMethod:@"GET" path:path query:nil body:nil completion:completion];
}

#pragma mark Sending

- (NSURLSessionDataTask *)sendSMSTo:(NSArray<NSString *> *)recipients message:(NSString *)message completion:(TSXSmsGoraCompletion)completion {
    return [self sendSMSTo:recipients message:message deviceID:nil simSlot:nil scheduleAt:nil completion:completion];
}

- (NSURLSessionDataTask *)sendSMSTo:(NSArray<NSString *> *)recipients
                            message:(NSString *)message
                           deviceID:(NSNumber *)deviceID
                            simSlot:(NSNumber *)simSlot
                         scheduleAt:(NSString *)scheduleAt
                         completion:(TSXSmsGoraCompletion)completion {
    NSMutableDictionary *body = [@{@"recipients": recipients ?: @[], @"message": message ?: @""} mutableCopy];
    if (simSlot) body[@"sim_slot"] = simSlot;
    if (scheduleAt) body[@"schedule_at"] = scheduleAt;
    NSString *path = deviceID ? [NSString stringWithFormat:@"/devices/%ld/send-sms", (long)deviceID.integerValue] : @"/send-sms";
    return [self requestWithMethod:@"POST" path:path query:nil body:body completion:completion];
}

- (NSURLSessionDataTask *)sendBulkSMSFromDevice:(NSInteger)deviceID
                                       messages:(NSArray<NSDictionary *> *)messages
                                messageTemplate:(NSString *)messageTemplate
                                     completion:(TSXSmsGoraCompletion)completion {
    NSMutableDictionary *body = [@{@"messages": messages ?: @[]} mutableCopy];
    if (messageTemplate) body[@"messageTemplate"] = messageTemplate;
    return [self requestWithMethod:@"POST"
                              path:[NSString stringWithFormat:@"/devices/%ld/send-bulk-sms", (long)deviceID]
                             query:nil
                              body:body
                        completion:completion];
}

#pragma mark Messages

- (NSURLSessionDataTask *)getMessage:(NSInteger)messageID completion:(TSXSmsGoraCompletion)completion {
    return [self get:[NSString stringWithFormat:@"/messages/%ld", (long)messageID] completion:completion];
}

- (NSURLSessionDataTask *)cancelMessage:(NSInteger)messageID completion:(TSXSmsGoraCompletion)completion {
    return [self requestWithMethod:@"POST" path:[NSString stringWithFormat:@"/messages/%ld/cancel", (long)messageID] query:nil body:nil completion:completion];
}

- (NSURLSessionDataTask *)listMessagesWithQuery:(NSDictionary<NSString *, NSString *> *)query completion:(TSXSmsGoraCompletion)completion {
    return [self requestWithMethod:@"GET" path:@"/messages" query:query body:nil completion:completion];
}

- (NSURLSessionDataTask *)listReceivedSMSForDevice:(NSNumber *)deviceID
                                             query:(NSDictionary<NSString *, NSString *> *)query
                                        completion:(TSXSmsGoraCompletion)completion {
    NSString *path = deviceID ? [NSString stringWithFormat:@"/devices/%ld/get-received-sms", (long)deviceID.integerValue] : @"/received-sms";
    return [self requestWithMethod:@"GET" path:path query:query body:nil completion:completion];
}

- (NSURLSessionDataTask *)getBatch:(NSInteger)batchID completion:(TSXSmsGoraCompletion)completion {
    return [self get:[NSString stringWithFormat:@"/batches/%ld", (long)batchID] completion:completion];
}

#pragma mark Phones and account

- (NSURLSessionDataTask *)listDevicesWithCompletion:(TSXSmsGoraCompletion)completion {
    return [self get:@"/devices" completion:completion];
}

- (NSURLSessionDataTask *)getDevice:(NSInteger)deviceID completion:(TSXSmsGoraCompletion)completion {
    return [self get:[NSString stringWithFormat:@"/devices/%ld", (long)deviceID] completion:completion];
}

- (NSURLSessionDataTask *)getAccountWithCompletion:(TSXSmsGoraCompletion)completion {
    return [self get:@"/account" completion:completion];
}

#pragma mark Webhooks

- (NSURLSessionDataTask *)listWebhooksWithCompletion:(TSXSmsGoraCompletion)completion {
    return [self get:@"/webhooks" completion:completion];
}

- (NSURLSessionDataTask *)createWebhookWithURL:(NSString *)url
                                        events:(NSArray<NSString *> *)events
                                      deviceID:(NSNumber *)deviceID
                                    completion:(TSXSmsGoraCompletion)completion {
    NSMutableDictionary *body = [@{@"url": url ?: @"", @"events": events ?: @[]} mutableCopy];
    if (deviceID) body[@"device_id"] = deviceID;
    return [self requestWithMethod:@"POST" path:@"/webhooks" query:nil body:body completion:completion];
}

- (NSURLSessionDataTask *)deleteWebhook:(NSInteger)webhookID completion:(TSXSmsGoraCompletion)completion {
    return [self requestWithMethod:@"DELETE" path:[NSString stringWithFormat:@"/webhooks/%ld", (long)webhookID] query:nil body:nil completion:completion];
}

+ (BOOL)verifyWebhookBody:(NSData *)rawBody signature:(NSString *)signature secret:(NSString *)secret {
    if (signature.length == 0 || secret.length == 0) return NO;
    NSData *key = [secret dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, rawBody.bytes, rawBody.length, mac);
    NSMutableString *expected = [NSMutableString stringWithString:@"sha256="];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [expected appendFormat:@"%02x", mac[i]];
    NSData *a = [expected dataUsingEncoding:NSUTF8StringEncoding];
    NSString *trimmed = [signature stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *b = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    if (a.length != b.length) return NO;
    const unsigned char *pa = a.bytes, *pb = b.bytes;
    unsigned char diff = 0;
    for (NSUInteger i = 0; i < a.length; i++) diff |= (unsigned char)(pa[i] ^ pb[i]);
    return diff == 0;
}

@end
