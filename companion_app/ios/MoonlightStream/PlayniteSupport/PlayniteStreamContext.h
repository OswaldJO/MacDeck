#import "PlayniteStreamSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface PlayniteStreamContext : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, nullable) PlayniteStreamSettings *streamSettings;

@end

NS_ASSUME_NONNULL_END
