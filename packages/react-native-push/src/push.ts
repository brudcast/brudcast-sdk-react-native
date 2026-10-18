import { Platform, type EventSubscription } from 'react-native';
import {
  BrudcastLog,
  guardBrudcastCall,
  runBrudcastHandler,
  type BrudcastModule,
} from '@brudcast/react-native/module';

import {
  BrudcastPushKeys,
  type BrudcastNotificationDecision,
  type BrudcastNotificationHandler,
  type BrudcastPushNotification,
  type BrudcastPushPermission,
  type BrudcastRemoteMessage,
} from './models';
import NativeBrudcastPush, {
  type NativeNotificationRequest,
  type NativePushNotification,
} from './specs/NativeBrudcastPush';

const permissions: readonly BrudcastPushPermission[] = [
  'notDetermined',
  'denied',
  'authorized',
  'provisional',
];

let notificationHandler: BrudcastNotificationHandler | null = null;
let notificationSubscription: EventSubscription | null = null;

/**
 * Push notifications. Brudcast sends through FCM, so pass the FCM token from
 * `@react-native-firebase/messaging` to `setToken`. Taps are recorded natively, with no
 * JavaScript code.
 */
export const BrudcastPush = {
  /** The module to list in `BrudcastOptions.modules`. */
  module: Object.freeze({ name: 'push' }) as BrudcastModule,

  /**
   * Stores the FCM registration token and registers it for this user. Pass the token from
   * `messaging().getToken()`, and every token from `onTokenRefresh`.
   *
   * @param token The token.
   */
  async setToken(token: string): Promise<void> {
    await guardBrudcastCall('setToken', () => NativeBrudcastPush.setToken(token));
  },

  /**
   * Asks the user for permission to show notifications, on Android 13 and later and on iOS. On
   * iOS it then registers with APNs.
   *
   * @param options `provisional` asks iOS for quiet delivery without a prompt.
   * @returns The status after the user answered.
   */
  async requestPermission(
    options: { provisional?: boolean } = {}
  ): Promise<BrudcastPushPermission> {
    const status = await guardBrudcastCall('requestPermission', () =>
      NativeBrudcastPush.requestPermission(options.provisional ?? false)
    );
    return permission(status);
  },

  /**
   * Reads the permission status.
   *
   * @returns The status, kept current as the user changes it in settings.
   */
  async getPermissionStatus(): Promise<BrudcastPushPermission> {
    return permission(
      await guardBrudcastCall('getPermissionStatus', () => NativeBrudcastPush.getPermissionStatus())
    );
  },

  /**
   * Follows the permission status as the user changes it, in the app or in settings.
   *
   * @param listener Called with each new status.
   * @returns A subscription; call `remove()` to stop.
   */
  addPermissionListener(listener: (status: BrudcastPushPermission) => void): EventSubscription {
    return NativeBrudcastPush.onPermissionChange((status) => listener(permission(status)));
  },

  /**
   * Sets the handler asked when a Brudcast notification arrives while the app is open.
   *
   * On iOS with `@react-native-firebase/messaging` installed, Brudcast notifications still reach
   * this handler; other notifications go on to Firebase's delegate.
   *
   * @param handler The handler, or null to show every notification.
   */
  async setNotificationHandler(handler: BrudcastNotificationHandler | null): Promise<void> {
    notificationHandler = handler;
    if (handler && !notificationSubscription) {
      notificationSubscription = NativeBrudcastPush.onNotificationRequest(answerNotification);
    } else if (!handler && notificationSubscription) {
      notificationSubscription.remove();
      notificationSubscription = null;
    }
    await guardBrudcastCall('setNotificationHandler', () =>
      NativeBrudcastPush.setNotificationHandlerEnabled(handler !== null)
    );
  },

  /**
   * Hands a message `@react-native-firebase/messaging` delivered in the foreground to the SDK.
   * On Android, Firebase does not show foreground notifications, so call this from
   * `messaging().onMessage`: the SDK records the message, asks the notification handler and shows
   * it. On iOS the system shows it, so this does nothing; call it on both platforms.
   *
   * @param message The remote message.
   * @returns True when the message is from Brudcast, so the app should not show it itself.
   */
  async handleForegroundMessage(message: BrudcastRemoteMessage): Promise<boolean> {
    const data = stringData(message.data ?? {});
    if (!BrudcastPush.isBrudcastNotification(data)) return false;
    if (Platform.OS !== 'android') return true;
    const handled = await guardBrudcastCall('handleForegroundMessage', () =>
      NativeBrudcastPush.handleForegroundMessage(
        data,
        message.notification?.title ?? null,
        message.notification?.body ?? null,
        message.notification?.android?.imageUrl ?? null
      )
    );
    return handled ?? true;
  },

  /**
   * Tells whether message data came from Brudcast: it carries a Brudcast message id. It needs no
   * native code, so it also works in `setBackgroundMessageHandler`, before the app mounts.
   *
   * @param data The message's data.
   * @returns True for a Brudcast notification.
   */
  isBrudcastNotification(data: Readonly<Record<string, unknown>> | undefined | null): boolean {
    const messageId = data?.[BrudcastPushKeys.messageId];
    return typeof messageId === 'string' && messageId.length > 0;
  },
};

/**
 * Runs the app's notification handler for a native request and sends its answer back.
 *
 * @param request The notification, with the id native waits on.
 */
async function answerNotification(request: NativeNotificationRequest): Promise<void> {
  const handler = notificationHandler;
  const decision: BrudcastNotificationDecision = handler
    ? await runBrudcastHandler(
        'notification handler',
        () => handler(notificationFromNative(request.notification)),
        'show'
      )
    : 'show';
  await guardBrudcastCall('resolveNotification', () =>
    NativeBrudcastPush.resolveNotification(request.requestId, decision)
  );
}

/**
 * Converts a notification from native.
 *
 * @param notification The notification.
 * @returns The notification the app sees.
 */
function notificationFromNative(notification: NativePushNotification): BrudcastPushNotification {
  const optional = (
    ['campaignId', 'applicationId', 'title', 'body', 'imageUrl', 'clickUrl'] as const
  ).reduce<Record<string, string>>((fields, key) => {
    const value = notification[key];
    if (value) fields[key] = value;
    return fields;
  }, {});
  return Object.freeze({
    messageId: notification.messageId,
    ...optional,
    data: Object.freeze(stringData(notification.data as Record<string, unknown>)),
  });
}

/**
 * Keeps the data values that are present, as strings, as FCM carries them.
 *
 * @param data The data.
 * @returns The data as strings.
 */
function stringData(data: Readonly<Record<string, unknown>>): Record<string, string> {
  const strings: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value !== null && value !== undefined) strings[key] = String(value);
  }
  return strings;
}

/**
 * Reads a permission status from native.
 *
 * @param status The status's name, or undefined when the call failed.
 * @returns The status, `notDetermined` when it is unknown.
 */
function permission(status: string | undefined): BrudcastPushPermission {
  if (status && (permissions as readonly string[]).includes(status)) {
    return status as BrudcastPushPermission;
  }
  if (status) BrudcastLog.warning(`Unknown permission status "${status}"`);
  return 'notDetermined';
}
