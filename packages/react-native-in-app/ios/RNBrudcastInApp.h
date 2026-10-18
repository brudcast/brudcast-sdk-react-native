#import <BrudcastReactNativeInAppSpec/BrudcastReactNativeInAppSpec.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The Brudcast in-app TurboModule. It hands every call to the Swift bridge on the main queue.
 */
@interface RNBrudcastInApp : NativeBrudcastInAppSpecBase <NativeBrudcastInAppSpec>

@end

NS_ASSUME_NONNULL_END
