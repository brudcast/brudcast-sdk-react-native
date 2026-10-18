import type {} from '@brudcast/react-native';
import { extendBrudcast } from '@brudcast/react-native/module';

import { BrudcastPush } from './push';

declare module '@brudcast/react-native' {
  interface BrudcastExtensions {
    /** Push notifications: permission, the token and the notification handler. */
    readonly push: typeof BrudcastPush;
  }
}

extendBrudcast('push', BrudcastPush);

export { BrudcastPush } from './push';
export {
  BrudcastPushKeys,
  type BrudcastNotificationDecision,
  type BrudcastNotificationHandler,
  type BrudcastPushNotification,
  type BrudcastPushPermission,
  type BrudcastRemoteMessage,
} from './models';
