#import "RNBrudcastInApp.h"

#if __has_include(<BrudcastInApp/BrudcastInApp-Swift.h>)
#import <BrudcastInApp/BrudcastInApp-Swift.h>
#else
#import "BrudcastInApp-Swift.h"
#endif

@implementation RNBrudcastInApp {
  RNBrudcastInAppBridge *_bridge;
}

+ (void)load
{
  [RNBrudcastInAppBridge registerModule];
}

+ (NSString *)moduleName
{
  return @"BrudcastInApp";
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (instancetype)init
{
  if (self = [super init]) {
    _bridge = [RNBrudcastInAppBridge new];
    __weak RNBrudcastInApp *weakSelf = self;
    _bridge.emitMessageRequest = ^(NSDictionary *request) {
      [weakSelf emitOnMessageRequest:request];
    };
    _bridge.emitUnreadCount = ^(NSNumber *count) {
      [weakSelf emitOnUnreadCountChange:count];
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
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge moduleCreated];
  }];
}

- (void)invalidate
{
  RNBrudcastInAppBridge *bridge = _bridge;
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

- (void)pauseDisplay
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge pauseDisplay];
  }];
}

- (void)resumeDisplay
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge resumeDisplay];
  }];
}

- (void)sync
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge sync];
  }];
}

- (void)setMessageHandlerEnabled:(BOOL)enabled
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge setMessageHandlerEnabled:enabled];
  }];
}

- (void)resolveMessage:(NSString *)requestId decision:(NSString *)decision
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge resolveMessageWithRequestId:requestId decision:decision];
  }];
}

- (void)reportImpression:(NSString *)messageId
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge reportImpression:messageId];
  }];
}

- (void)reportClick:(NSString *)messageId buttonId:(NSString *)buttonId
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge reportClick:messageId buttonId:buttonId];
  }];
}

- (void)reportDismiss:(NSString *)messageId
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge reportDismiss:messageId];
  }];
}

- (void)presentInbox:(NSString *)title
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge presentInboxWithTitle:title];
  }];
}

- (void)listInbox:(NSNumber *)beforeMillis
            limit:(NSInteger)limit
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge listInboxBeforeMillis:beforeMillis
        limit:limit
        resolve:^(NSDictionary *page) {
          resolve(page);
        }
        reject:^(NSString *code, NSString *message) {
          reject(code, message, nil);
        }];
  }];
}

- (void)markRead:(NSString *)messageId
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge markRead:messageId];
  }];
}

- (void)deleteMessage:(NSString *)messageId
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    [bridge deleteMessage:messageId];
  }];
}

- (void)getUnreadCount:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  RNBrudcastInAppBridge *bridge = _bridge;
  [self onMain:^{
    resolve(@([bridge unreadCount]));
  }];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeBrudcastInAppSpecJSI>(params);
}

@end
