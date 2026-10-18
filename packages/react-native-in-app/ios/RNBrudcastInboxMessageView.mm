#import "RNBrudcastInboxMessageView.h"

#import <react/renderer/components/BrudcastReactNativeInAppSpec/ComponentDescriptors.h>
#import <react/renderer/components/BrudcastReactNativeInAppSpec/EventEmitters.h>
#import <react/renderer/components/BrudcastReactNativeInAppSpec/Props.h>
#import <react/renderer/components/BrudcastReactNativeInAppSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

#if __has_include(<BrudcastInApp/BrudcastInApp-Swift.h>)
#import <BrudcastInApp/BrudcastInApp-Swift.h>
#else
#import "BrudcastInApp-Swift.h"
#endif

using namespace facebook::react;

@interface RNBrudcastInboxMessageView () <RCTBrudcastInboxMessageViewViewProtocol>
@end

@implementation RNBrudcastInboxMessageView {
  UIView *_container;
  UIView *_message;
  NSString *_messageId;
  CGFloat _height;
  CGFloat _emittedHeight;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<BrudcastInboxMessageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const BrudcastInboxMessageViewProps>();
    _props = defaultProps;
    _container = [[UIView alloc] initWithFrame:self.bounds];
    _container.clipsToBounds = YES;
    self.contentView = _container;
    _height = -1;
    _emittedHeight = -1;
  }
  return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<BrudcastInboxMessageViewProps const>(props);
  NSString *messageId = [NSString stringWithUTF8String:newProps.messageId.c_str()];
  if (![messageId isEqualToString:_messageId ?: @""]) {
    _messageId = messageId;
    [self render];
  }
  [super updateProps:props oldProps:oldProps];
}

/**
 * Replaces the drawn entry with the one for the current message id.
 */
- (void)render
{
  [_message removeFromSuperview];
  _message = nil;
  _height = -1;
  _emittedHeight = -1;
  if (_messageId.length == 0) {
    return;
  }
  __weak RNBrudcastInboxMessageView *weakSelf = self;
  UIView *view = [RNBrudcastInboxRenderer viewWithMessageId:_messageId
                                                   onHeight:^(CGFloat height) {
                                                     [weakSelf reportHeight:height];
                                                   }];
  if (view == nil) {
    [self reportHeight:0];
    return;
  }
  view.frame = _container.bounds;
  view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [_container addSubview:view];
  _message = view;
}

/**
 * Keeps the height the design needs and tells JavaScript.
 *
 * @param height The height in points.
 */
- (void)reportHeight:(CGFloat)height
{
  _height = height;
  [self emitHeight];
}

/**
 * Tells JavaScript the last height, once the event emitter is attached and when it changed.
 */
- (void)emitHeight
{
  if (_height < 0 || _height == _emittedHeight || !_eventEmitter) {
    return;
  }
  _emittedHeight = _height;
  std::static_pointer_cast<const BrudcastInboxMessageViewEventEmitter>(_eventEmitter)
      ->onContentHeightChange(BrudcastInboxMessageViewEventEmitter::OnContentHeightChange{.height = _height});
}

- (void)updateEventEmitter:(EventEmitter::Shared const &)eventEmitter
{
  [super updateEventEmitter:eventEmitter];
  _emittedHeight = -1;
  [self emitHeight];
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  [_message removeFromSuperview];
  _message = nil;
  _messageId = nil;
  _height = -1;
  _emittedHeight = -1;
}

@end

Class<RCTComponentViewProtocol> RNBrudcastInboxMessageViewCls(void)
{
  return RNBrudcastInboxMessageView.class;
}
