import type {} from '@brudcast/react-native';
import { extendBrudcast } from '@brudcast/react-native/module';

import { BrudcastInApp } from './inApp';

declare module '@brudcast/react-native' {
  interface BrudcastExtensions {
    /** In-app messaging: display control, the message handler and the inbox. */
    readonly inApp: typeof BrudcastInApp;
  }
}

extendBrudcast('inApp', BrudcastInApp);

export { BrudcastInApp, BrudcastInbox } from './inApp';
export { BrudcastInboxMessage, type BrudcastInboxMessageProps } from './BrudcastInboxMessage';
export { useInbox, useInboxUnreadCount, type BrudcastInboxState } from './hooks';
export {
  BrudcastInboxError,
  designDocument,
  type BrudcastInAppMessage,
  type BrudcastInboxPage,
  BrudcastMessageDecision,
  type BrudcastMessageFormat,
  type BrudcastMessageHandler,
} from './models';
