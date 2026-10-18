/** What an action asks the app to do: open a deep link or a web page, or handle a custom event. */
export type BrudcastActionKind = 'deeplink' | 'url' | 'customEvent';

/** Where an action came from: a button of an in-app message, or a tap on a push notification. */
export type BrudcastActionOrigin = 'inApp' | 'push';

/** The message, and for in-app messages the button, an action came from. */
export type BrudcastActionSource = {
  readonly origin: BrudcastActionOrigin;
  readonly messageId: string;
  readonly buttonId?: string;
};

/**
 * Something a message asked the app to do. `verified` is false on Android when the action came
 * from a push tap the SDK cannot prove it created, which another app could forge; check it before
 * routing a deep link to a private screen.
 */
export type BrudcastAction = {
  readonly kind: BrudcastActionKind;
  readonly value: string;
  readonly opensInApp: boolean;
  readonly source: BrudcastActionSource;
  readonly verified: boolean;
};

/**
 * What the action handler did with an action: `handled` skips the default, and `useDefault` opens
 * the link, or does nothing for a custom event.
 */
export type BrudcastActionResult = 'handled' | 'useDefault';

/**
 * Decides what to do with an action before the default behaviour. It has two seconds to answer,
 * after which the default runs.
 */
export type BrudcastActionHandler = (
  action: BrudcastAction
) => BrudcastActionResult | Promise<BrudcastActionResult>;
