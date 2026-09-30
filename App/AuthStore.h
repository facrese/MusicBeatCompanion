#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthStore : NSObject
+ (nullable NSDictionary<NSString *, id> *)load;
+ (void)saveHeaders:(NSDictionary<NSString *, NSString *> *)headers
        storefront:(NSString *)storefront;
+ (void)clear;
@end

NS_ASSUME_NONNULL_END
