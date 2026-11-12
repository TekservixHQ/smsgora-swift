#import <XCTest/XCTest.h>

#import "TSXSmsGoraClient.h"

@interface TSXSmsGoraClientTests : XCTestCase
@end

@implementation TSXSmsGoraClientTests

- (void)testWebhookSignature {
    NSData *body = [@"{\"event\":\"sms.received\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *good = @"sha256=313fe9b54923f49c8b94d50c5b96fa44f3f5a7ca90ef52fd55afb2bfd3ae8f60";
    XCTAssertTrue([TSXSmsGoraClient verifyWebhookBody:body signature:good secret:@"whsec_test"]);
    NSString *padded = [NSString stringWithFormat:@" %@\n", good];
    XCTAssertTrue([TSXSmsGoraClient verifyWebhookBody:body signature:padded secret:@"whsec_test"]);
    XCTAssertFalse([TSXSmsGoraClient verifyWebhookBody:body signature:good secret:@"other"]);
    XCTAssertFalse([TSXSmsGoraClient verifyWebhookBody:body signature:@"" secret:@"whsec_test"]);
    XCTAssertFalse([TSXSmsGoraClient verifyWebhookBody:body signature:nil secret:@"whsec_test"]);
}

- (void)testBaseURLIsTrimmed {
    TSXSmsGoraClient *c = [[TSXSmsGoraClient alloc] initWithAPIKey:@"sgk_x"
                                                           baseURL:[NSURL URLWithString:@"https://example.com/api//"]
                                                           session:[NSURLSession sharedSession]];
    XCTAssertEqualObjects(c.baseURL.absoluteString, @"https://example.com/api");
    XCTAssertEqualObjects(TSXSmsGoraClient.defaultBaseURL.absoluteString, @"https://tekservix.com/smsgora/api/v1");
}

- (void)testLiveInvalidKeyGives401 {
    XCTestExpectation *done = [self expectationWithDescription:@"account"];
    TSXSmsGoraClient *c = [[TSXSmsGoraClient alloc] initWithAPIKey:@"sgk_invalid_objc_test"];
    [c getAccountWithCompletion:^(id data, NSError *error) {
        XCTAssertNil(data);
        XCTAssertEqualObjects(error.domain, TSXSmsGoraErrorDomain);
        XCTAssertEqual(error.code, 401);
        XCTAssertNotNil(error.userInfo[TSXSmsGoraErrorBodyKey]);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];
}

@end
