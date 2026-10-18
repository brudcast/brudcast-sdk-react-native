#import "RNBrudcastPush.h"

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

#if __has_include(<BrudcastPush/BrudcastPush-Swift.h>)
#import <BrudcastPush/BrudcastPush-Swift.h>
#else
#import "BrudcastPush-Swift.h"
#endif

@implementation RNBrudcastPush {
  RNBrudcastPushBridge *_bridge;
}

+ (void)load
{
  [RNBrudcastPushBridge registerModule];
}

+ (NSString *)moduleName
{
  return @"BrudcastPush";
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (instancetype)init
{
  if (self = [super init]) {
    _bridge = [RNBrudcastPushBridge new];
    __weak RNBrudcastPush *weakSelf = self;
    _bridge.emitNotificationRequest = ^(NSDictionary *request) {
      [weakSelf emitOnNotificationRequest:request];
    };
    _bridge.emitPermission = ^(NSString *status) {
      [weakSelf emitOnPermissionChange:status];
    };
  }
  return self;
}

/**
 * Starts the native subscriptions once React Native has attached the event emitter. An event sent
 * before then would call an empty callback and abort the app.
 *
 * @param eventEmitterCallbackWrapper The emitter React Native attaches.
 */
- (void)setEventEmitterCallback:(EventEmitterCallbackWrapper *)eventEmitterCallbackWrapper
{
  [super setEventEmitterCallback:eventEmitterCallbackWrapper];
  RNBrudcastPushBridge *bridge = _bridge;
  [self onMain:^{
    [bridge moduleCreated];
  }];
}

- (void)invalidate
{
  RNBrudcastPushBridge *bridge = _bridge;
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

- (void)setToken:(NSString *)token
{
  RNBrudcastPushBridge *bridge = _bridge;
  [self onMain:^{
    [bridge setToken:token];
  }];
}

- (void)requestPermission:(BOOL)provisional resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  RNBrudcastPushBridge *bridge = _bridge;
  [self onMain:^{
    [bridge requestPermissionWithProvisional:provisional
                                  completion:^(NSString *status) {
                                    resolve(status);
                                  }];
  }];
}

- (void)getPermissionStatus:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  RNBrudcastPushBridge *bridge = _bridge;
  [self onMain:^{
    resolve([bridge permissionStatus]);
  }];
}

- (void)setNotificationHandlerEnabled:(BOOL)enabled
{
  RNBrudcastPushBridge *bridge = _bridge;
  [self onMain:^{
    [bridge setNotificationHandlerEnabled:enabled];
  }];
}

- (void)resolveNotification:(NSString *)requestId decision:(NSString *)decision
{
  RNBrudcastPushBridge *bridge = _bridge;
  [self onMain:^{
    [bridge resolveNotificationWithRequestId:requestId decision:decision];
  }];
}

- (void)handleForegroundMessage:(NSDictionary *)data
                          title:(NSString *)title
                           body:(NSString *)body
                       imageUrl:(NSString *)imageUrl
                        resolve:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject
{
  resolve(@(data[@"bc_mid"] != nil));
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeBrudcastPushSpecJSI>(params);
}

@end
