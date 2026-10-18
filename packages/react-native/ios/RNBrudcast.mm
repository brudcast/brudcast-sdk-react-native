#import "RNBrudcast.h"

#if __has_include(<Brudcast/Brudcast-Swift.h>)
#import <Brudcast/Brudcast-Swift.h>
#else
#import "Brudcast-Swift.h"
#endif

@implementation RNBrudcast {
  RNBrudcastBridge *_bridge;
}

+ (NSString *)moduleName
{
  return @"Brudcast";
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (instancetype)init
{
  if (self = [super init]) {
    _bridge = [RNBrudcastBridge new];
    __weak RNBrudcast *weakSelf = self;
    _bridge.emitActionRequest = ^(NSDictionary *request) {
      [weakSelf emitOnActionRequest:request];
    };
    RNBrudcastBridge *bridge = _bridge;
    [self onMain:^{
      [bridge moduleCreated];
    }];
  }
  return self;
}

- (void)invalidate
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge invalidate];
  }];
}

/**
 * Runs a block on the main queue, at once when already on it.
 *
 * @param block The block.
 */
- (void)onMain:(dispatch_block_t)block
{
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

- (void)initialize:(NSString *)publishableKey options:(JS::NativeBrudcast::NativeOptions &)options
{
  NSMutableDictionary *environment = [NSMutableDictionary new];
  environment[@"kind"] = options.environment().kind();
  if (options.environment().androidHost()) {
    environment[@"androidHost"] = options.environment().androidHost();
  }
  if (options.environment().port().has_value()) {
    environment[@"port"] = @(options.environment().port().value());
  }
  if (options.environment().baseUrl()) {
    environment[@"baseUrl"] = options.environment().baseUrl();
  }
  NSMutableArray<NSString *> *modules = [NSMutableArray new];
  for (NSString *module : options.modules()) {
    [modules addObject:module];
  }
  NSMutableDictionary *converted = [NSMutableDictionary new];
  converted[@"environment"] = environment;
  converted[@"logLevel"] = options.logLevel();
  converted[@"appearance"] = options.appearance();
  converted[@"modules"] = modules;
  converted[@"wrapperVersion"] = options.wrapperVersion();
  if (options.accentColor().has_value()) {
    converted[@"accentColor"] = @((uint32_t)(int64_t)options.accentColor().value());
  }
  if (options.appGroupIdentifier()) {
    converted[@"appGroupIdentifier"] = options.appGroupIdentifier();
  }
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge initializeWithPublishableKey:publishableKey options:converted];
  }];
}

- (void)identify:(NSString *)externalId userHash:(NSString *)userHash traits:(JS::NativeBrudcast::NativeTraits &)traits
{
  NSMutableDictionary *converted = [NSMutableDictionary new];
  converted[@"email"] = traits.email();
  converted[@"phone"] = traits.phone();
  converted[@"firstName"] = traits.firstName();
  converted[@"lastName"] = traits.lastName();
  converted[@"language"] = traits.language();
  converted[@"timezone"] = traits.timezone();
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge identifyWithExternalId:externalId userHash:userHash traits:converted.count > 0 ? converted : nil];
  }];
}

- (void)reset
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge reset];
  }];
}

- (void)track:(NSString *)name properties:(NSDictionary *)properties
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge trackWithName:name properties:properties];
  }];
}

- (void)screen:(NSString *)name properties:(NSDictionary *)properties
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge screenWithName:name properties:properties];
  }];
}

- (void)setOptedOut:(BOOL)optedOut
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge setOptedOut:optedOut];
  }];
}

- (void)setTrackingEnabled:(BOOL)enabled
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge setTrackingEnabled:enabled];
  }];
}

- (void)flush
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge flush];
  }];
}

- (void)setActionHandlerEnabled:(BOOL)enabled
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge setActionHandlerEnabled:enabled];
  }];
}

- (void)resolveAction:(NSString *)requestId result:(NSString *)result
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    [bridge resolveActionWithRequestId:requestId result:result];
  }];
}

- (void)getDeviceId:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  RNBrudcastBridge *bridge = _bridge;
  [self onMain:^{
    resolve([bridge deviceId]);
  }];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeBrudcastSpecJSI>(params);
}

@end
