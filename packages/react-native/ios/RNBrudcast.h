#import <BrudcastReactNativeSpec/BrudcastReactNativeSpec.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The core Brudcast TurboModule. It converts the codegen types and hands every call to the Swift
 * bridge on the main queue.
 */
@interface RNBrudcast : NativeBrudcastSpecBase <NativeBrudcastSpec>

@end

NS_ASSUME_NONNULL_END
