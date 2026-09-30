#import <Foundation/Foundation.h>

@class WKHTTPCookieStore;

NS_ASSUME_NONNULL_BEGIN

@interface BeatService : NSObject
@property (nonatomic, copy, nullable) void (^onChange)(void);
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, copy, readonly) NSString *statusText;
@property (nonatomic, copy, readonly) NSString *trackText;
@property (nonatomic, copy, readonly) NSString *authText;
@property (nonatomic, strong, nullable) WKHTTPCookieStore *cookieStore;

+ (instancetype)shared;
- (void)start;
- (void)stop;
- (void)testPulse;
- (void)acceptWebHeaders:(NSDictionary<NSString *, NSString *> *)headers
                    url:(NSString *)url;
@end

NS_ASSUME_NONNULL_END
