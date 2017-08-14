//
//  SimpleLoggerTests.m
//  SimpleLoggerTests
//
//  Created by Bill Burgess on 7/25/17.
//  Copyright © 2017 Simply Made Apps Inc. All rights reserved.
//

#import "SLTestCase.h"

@interface SimpleLoggerTests : SLTestCase

@end

@implementation SimpleLoggerTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
	[SimpleLogger removeAllLogFiles];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
	[SimpleLogger removeAllLogFiles];
	[self deleteRegularFiles];
	
    [super tearDown];
}

#pragma mark - Public Methods
- (void)testSharedLoggerNotNil {
	XCTAssertNotNil([SimpleLogger sharedLogger]);
}

- (void)testLoggerInitsWithCorrectDefaults {
	SimpleLogger *logger = [[SimpleLogger alloc] init];
	
	XCTAssertNotNil(logger.logFormatter);
	XCTAssertNotNil(logger.filenameFormatter);
	XCTAssertEqual(logger.retentionDays, kLoggerRetentionDaysDefault);
	XCTAssertEqualObjects(logger.filenameExtension, kLoggerFilenameExtension);
}

- (void)testAmazonInitStoresValuesCorrectly {
	[SimpleLogger initWithAWSRegion:AWSRegionUSEast1 bucket:@"test_bucket" accessToken:@"test_token" secret:@"test_secret"];
	
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	
	XCTAssertNotNil(logger);
	XCTAssertNotNil(logger.awsBucket);
	XCTAssertNotNil(logger.awsAccessToken);
	XCTAssertNotNil(logger.awsSecret);
	
	XCTAssertEqual(logger.awsRegion, AWSRegionUSEast1);
	XCTAssertEqualObjects(logger.awsBucket, @"test_bucket");
	XCTAssertEqualObjects(logger.awsAccessToken, @"test_token");
	XCTAssertEqualObjects(logger.awsSecret, @"test_secret");
}

- (void)testLogEvent {
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	NSDate *date = [NSDate date];
	
	[SimpleLogger logEvent:@"my test string"];
	
	NSString *log = [SimpleLogger logOutputForFileDate:date];
	NSString *compare = [NSString stringWithFormat:@"[%@] my test string", [logger.logFormatter stringFromDate:date]];
	XCTAssertNotNil(log);
	XCTAssertEqualObjects(log, compare);
}

- (void)testLogEventAppendsNewLines {
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	NSDate *date = [NSDate date];
	
	[SimpleLogger logEvent:@"my test string"];
	[SimpleLogger logEvent:@"other test string"];
	
	NSString *log = [SimpleLogger logOutputForFileDate:date];
	NSString *compare = [NSString stringWithFormat:@"[%@] my test string\n[%@] other test string", [logger.logFormatter stringFromDate:date], [logger.logFormatter stringFromDate:date]];
	XCTAssertNotNil(log);
	XCTAssertEqualObjects(log, compare);
}

- (void)testEventStringGetsFormattedCorrectly {
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	
	NSString *eventString = [logger eventString:@"test event" forDate:[self testDate]];
	
	XCTAssertNotNil(eventString);
	XCTAssertEqualObjects(eventString, @"[2017-07-15 10:10:00] test event");
}

- (void)testRemoveAllFilesWorksCorrectly {	
	[self saveDummyFiles:5];
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *docDirectory = paths[0];
	
	NSError *error;
	NSArray *content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDirectory error:&error];
	
	// should have 5 files saved
	XCTAssertEqual(content.count, 5);
	
	[SimpleLogger removeAllLogFiles];
	
	content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDirectory error:&error];
	
	XCTAssertEqual(content.count, 0);
}

- (void)testRemoveAllFilesKeepsNonLogFiles {
	[self saveDummyFiles:1];
	[self saveRegularFiles:2];
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *docDirectory = paths[0];
	
	NSError *error;
	NSArray *content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDirectory error:&error];
	
	// should have 3 files saved
	XCTAssertEqual(content.count, 3);
	
	[SimpleLogger removeAllLogFiles];
	
	content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDirectory error:&error];
	
	XCTAssertEqual(content.count, 2);
}

- (void)testUploadFilesWithCompletionWhileInProgress {
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	logger.uploadInProgress = YES;
	logger.currentUploadCount = 1;
	
	XCTestExpectation *expect = [self expectationWithDescription:@"Upload In Progress"];
	[SimpleLogger uploadAllFilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
		XCTAssertFalse(success);
		XCTAssertNil(error);
		XCTAssertEqual(logger.currentUploadCount, 1);
		[expect fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testUploadFilesWithCompletionSuccess {
	[SimpleLogger initWithAWSRegion:AWSRegionUSEast1 bucket:@"test_bucket" accessToken:@"test_token" secret:@"test_secret"];

	AWSS3TransferManager *transferManager = [AWSS3TransferManager defaultS3TransferManager];
	
	id mock = OCMPartialMock(transferManager);
	[[[mock stub] upload:[OCMArg any]] continueWithExecutor:[OCMArg any] withBlock:[OCMArg checkWithBlock:^BOOL(AWSContinuationBlock block) {
		AWSTask *task = [[AWSTask alloc] init];
		block(task);
		return YES;
	}]];
	
	[self saveDummyFiles:1];
	
	XCTestExpectation *expect = [self expectationWithDescription:@"Upload All Files"];
	
	[SimpleLogger uploadAllFilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
		XCTAssertTrue(success);
		XCTAssertNil(error);
		
		[expect fulfill];
	}];
	
	[self waitForExpectationsWithTimeout:1 handler:nil];
	
	[mock stopMocking];
	mock = nil;
}

- (void)testUploadFilesWithCompletionError {
	[SimpleLogger initWithAWSRegion:AWSRegionUSEast1 bucket:@"test_bucket" accessToken:@"test_token" secret:@"test_secret"];
	
	//AWSTask *task = [[AWSTask alloc] init];
	//id taskMock = OCMPartialMock(task);
	//[[[taskMock stub] andReturn:[NSError errorWithDomain:@"com.test.error" code:123 userInfo:nil]] error];
	
	//id mock = OCMPartialMock(transferManager);
	//[[[mock stub] upload:[OCMArg any]] continueWithExecutor:[OCMArg any] withBlock:[OCMArg checkWithBlock:^BOOL(AWSContinuationBlock block) {
	//	block(task);
	//	return YES;
	//}]];
	
	[self saveDummyFiles:1];
	
	XCTestExpectation *expect = [self expectationWithDescription:@"Upload All Files"];
	
	[SimpleLogger uploadAllFilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
		XCTAssertFalse(success);
		XCTAssertNotNil(error);
		
		[expect fulfill];
	}];
	
	//[mock verify];
	//[mock stopMocking];
	//mock = nil;
	
	//[taskMock verify];
	//[taskMock stopMocking];
	//taskMock = nil;
	
	[self waitForExpectationsWithTimeout:1 handler:nil];
}

#pragma mark - Private Methods
- (void)testLastRetentionDateReturnsCorrectly {
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	
	NSDate *now = [self testDate];
	NSDate *lastRetainDate = [logger lastRetentionDateForDate:now];
	
	XCTAssertNotNil(lastRetainDate);
	NSString *dateString = [logger.filenameFormatter stringFromDate:lastRetainDate];
	XCTAssertNotNil(dateString);
	XCTAssertEqualObjects(dateString, @"2017-07-09");
}

- (void)testFileTruncationWorksCorrectly {
	[self saveDummyFiles:8];
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *docDirectory = paths[0];
	
	NSError *error;
	NSArray *content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDirectory error:&error];
	
	// should have 8 files saved
	XCTAssertEqual(content.count, 8);
	
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	
	[logger truncateFilesBeyondRetentionForDate:[self testDate]];
	
	content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDirectory error:&error];
	
	XCTAssertEqual(content.count, 6); // doesn't make file for current day, so dropping 2
}

- (void)testUploadFilepathToAmazonWithTaskNil {
	
}

- (void)testUploadFilepathToAmazonWithTask {
	
}

#pragma mark - Helpers
- (void)testFilenameForDateReturnsCorrectly {
	SimpleLogger *logger = [SimpleLogger sharedLogger];
	NSDate *date = [self testDate];
	NSString *filename = [logger filenameForDate:date];
	
	XCTAssertNotNil(filename);
	XCTAssertEqualObjects(filename, @"2017-07-15.log");
}

@end
