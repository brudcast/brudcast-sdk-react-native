/**
 * Whether the app may show notifications: not asked yet, refused or turned off, allowed, or on iOS
 * delivered quietly without having asked.
 */
export type BrudcastPushPermission = 'notDetermined' | 'denied' | 'authorized' | 'provisional';

/** What the notification handler wants done with a Brudcast notification: show it, or not. */
export type BrudcastNotificationDecision = 'show' | 'suppress';

/** The data keys Brudcast adds to every push notification. */
export const BrudcastPushKeys = Object.freeze({
  messageId: 'bc_mid',
  campaignId: 'bc_cid',
  applicationId: 'bc_app',
  clickUrl: 'click_url',
});

/** A push notification Brudcast sent. `data` holds the campaign's custom data. */
export type BrudcastPushNotification = {
  readonly messageId: string;
  readonly campaignId?: string;
  readonly applicationId?: string;
  readonly title?: string;
  readonly body?: string;
  readonly imageUrl?: string;
  readonly clickUrl?: string;
  readonly data: Readonly<Record<string, string>>;
};

/**
 * Decides whether a notification arriving while the app is open shows. It has two seconds to
 * answer, after which the notification shows.
 */
export type BrudcastNotificationHandler = (
  notification: BrudcastPushNotification
) => BrudcastNotificationDecision | Promise<BrudcastNotificationDecision>;

/**
 * The shape of a message from `@react-native-firebase/messaging`, which
 * `handleForegroundMessage` takes. Any object with these fields works.
 */
export type BrudcastRemoteMessage = {
  readonly data?: Readonly<Record<string, unknown>>;
  readonly notification?: {
    readonly title?: string;
    readonly body?: string;
    readonly android?: { readonly imageUrl?: string };
  };
};
