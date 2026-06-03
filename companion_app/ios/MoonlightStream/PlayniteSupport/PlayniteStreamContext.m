#import "PlayniteStreamContext.h"

@implementation PlayniteStreamContext

+ (instancetype)shared {
    static PlayniteStreamContext *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[PlayniteStreamContext alloc] init];
    });
    return instance;
}

@end
