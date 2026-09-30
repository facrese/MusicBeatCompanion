#import "AuthStore.h"
#import <Security/Security.h>

static NSString *const BHServiceName = @"com.facrese.musicbeatcompanion.web-auth";
static NSString *const BHAccountName = @"active";

@implementation AuthStore

+ (NSMutableDictionary *)query {
    return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: BHServiceName,
              (__bridge id)kSecAttrAccount: BHAccountName} mutableCopy];
}

+ (NSDictionary<NSString *, id> *)load {
    NSMutableDictionary *query = [self query];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

+ (void)saveHeaders:(NSDictionary<NSString *,NSString *> *)headers
        storefront:(NSString *)storefront {
    NSDictionary *record = @{@"headers": headers, @"storefront": storefront ?: @"tr"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    if (!data) return;
    NSMutableDictionary *query = [self query];
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
        (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
    if (status == errSecItemNotFound) {
        query[(__bridge id)kSecValueData] = data;
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
}

+ (void)clear { SecItemDelete((__bridge CFDictionaryRef)[self query]); }

@end
