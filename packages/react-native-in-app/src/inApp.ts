import type { EventSubscription } from 'react-native';
import {
  BrudcastLog,
  guardBrudcastCall,
  runBrudcastHandler,
  type BrudcastModule,
} from '@brudcast/react-native/module';

import {
  BrudcastInboxError,
  messageFromNative,
  type BrudcastInboxPage,
  type BrudcastMessageDecision,
  type BrudcastMessageHandler,
} from './models';
import NativeBrudcastInApp, { type NativeMessageRequest } from './specs/NativeBrudcastInApp';

let messageHandler: BrudcastMessageHandler | null = null;
let messageSubscription: EventSubscription | null = null;

let unreadCount = 0;
let unreadSubscription: EventSubscription | null = null;
const unreadListeners = new Set<(count: number) => void>();

/** The inbox: messages to read later, kept by the service across devices. */
export const BrudcastInbox = {
  /**
   * Opens the native inbox screen, drawn in the accent colour in-app messages use.
   *
   * @param options The screen's title, `Inbox` by default.
   */
  async present(options: { title?: string } = {}): Promise<void> {
    await guardBrudcastCall('inbox.present', () =>
      NativeBrudcastInApp.presentInbox(options.title ?? 'Inbox')
    );
  },

  /**
   * Fetches a page of the inbox, newest first.
   *
   * @param options `before` keeps entries older than it; `limit` is at most 100, 20 by default.
   * @returns The page.
   * @throws {BrudcastInboxError} When the page cannot be loaded, such as offline or before
   *   `initialize`.
   */
  async list(options: { before?: Date; limit?: number } = {}): Promise<BrudcastInboxPage> {
    const limit = Math.min(Math.max(Math.trunc(options.limit ?? 20), 1), 100);
    try {
      const page = await NativeBrudcastInApp.listInbox(options.before?.getTime() ?? null, limit);
      setUnreadCount(page.unreadCount);
      return Object.freeze({
        messages: Object.freeze(page.messages.map(messageFromNative)),
        unreadCount: page.unreadCount,
        hasMore: page.hasMore,
      });
    } catch (error) {
      const code = (error as { code?: unknown }).code;
      throw new BrudcastInboxError(
        typeof code === 'string' ? code : 'inbox_failed',
        error instanceof Error ? error.message : String(error)
      );
    }
  },

  /**
   * Marks an entry read on every device.
   *
   * @param messageId The entry's message id.
   */
  async markRead(messageId: string): Promise<void> {
    await guardBrudcastCall('inbox.markRead', () => NativeBrudcastInApp.markRead(messageId));
  },

  /**
   * Deletes an entry from the inbox on every device.
   *
   * @param messageId The entry's message id.
   */
  async delete(messageId: string): Promise<void> {
    await guardBrudcastCall('inbox.delete', () => NativeBrudcastInApp.deleteMessage(messageId));
  },

  /**
   * The number of unread entries, as last reported by the service.
   *
   * @returns The count; 0 until the SDK has heard from the service.
   */
  getUnreadCount(): number {
    return unreadCount;
  },

  /**
   * Follows the unread count as messages arrive and are read, on this and the user's other
   * devices.
   *
   * @param listener Called with each new count.
   * @returns A subscription; call `remove()` to stop.
   */
  addUnreadCountListener(listener: (count: number) => void): EventSubscription {
    unreadListeners.add(listener);
    followUnreadCount();
    return {
      remove() {
        unreadListeners.delete(listener);
      },
    };
  },
};

/** In-app messaging: triggers, display rules and presentation run natively; this controls them. */
export const BrudcastInApp = {
  /** The module to list in `BrudcastOptions.modules`. */
  module: Object.freeze({ name: 'in_app' }) as BrudcastModule,

  /** The inbox. */
  inbox: BrudcastInbox,

  /**
   * Holds messages back without showing them, such as during checkout or a video. Triggers that
   * fire meanwhile are kept.
   */
  async pauseDisplay(): Promise<void> {
    await guardBrudcastCall('pauseDisplay', () => NativeBrudcastInApp.pauseDisplay());
  },

  /**
   * Shows held messages again after `pauseDisplay`.
   */
  async resumeDisplay(): Promise<void> {
    await guardBrudcastCall('resumeDisplay', () => NativeBrudcastInApp.resumeDisplay());
  },

  /**
   * Fetches the messages this device should hold now, instead of waiting for the next foreground.
   */
  async sync(): Promise<void> {
    await guardBrudcastCall('sync', () => NativeBrudcastInApp.sync());
  },

  /**
   * Sets the handler asked before each message shows. Answer `custom` to draw the message
   * yourself, then report what happened with `reportImpression`, `reportClick` and
   * `reportDismiss`.
   *
   * @param handler The handler, or null to show every message.
   */
  async setMessageHandler(handler: BrudcastMessageHandler | null): Promise<void> {
    messageHandler = handler;
    if (handler && !messageSubscription) {
      messageSubscription = NativeBrudcastInApp.onMessageRequest(answerMessage);
    } else if (!handler && messageSubscription) {
      messageSubscription.remove();
      messageSubscription = null;
    }
    await guardBrudcastCall('setMessageHandler', () =>
      NativeBrudcastInApp.setMessageHandlerEnabled(handler !== null)
    );
  },

  /**
   * Reports that the app showed a message it draws itself.
   *
   * @param messageId The message id.
   */
  async reportImpression(messageId: string): Promise<void> {
    await guardBrudcastCall('reportImpression', () =>
      NativeBrudcastInApp.reportImpression(messageId)
    );
  },

  /**
   * Reports a tap on a button of a message the app draws itself.
   *
   * @param messageId The message id.
   * @param buttonId The design's button id.
   */
  async reportClick(messageId: string, buttonId: string): Promise<void> {
    await guardBrudcastCall('reportClick', () =>
      NativeBrudcastInApp.reportClick(messageId, buttonId)
    );
  },

  /**
   * Reports that a message the app draws itself was closed without an action.
   *
   * @param messageId The message id.
   */
  async reportDismiss(messageId: string): Promise<void> {
    await guardBrudcastCall('reportDismiss', () => NativeBrudcastInApp.reportDismiss(messageId));
  },
};

/**
 * Runs the app's message handler for a native request and sends its answer back.
 *
 * @param request The message, with the id native waits on.
 */
async function answerMessage(request: NativeMessageRequest): Promise<void> {
  const handler = messageHandler;
  const decision: BrudcastMessageDecision = handler
    ? await runBrudcastHandler(
        'message handler',
        () => handler(messageFromNative(request.message)),
        'show'
      )
    : 'show';
  await guardBrudcastCall('resolveMessage', () =>
    NativeBrudcastInApp.resolveMessage(request.requestId, decision)
  );
}

/**
 * Starts following the native unread count, once, and reads its current value.
 */
function followUnreadCount(): void {
  if (unreadSubscription) return;
  unreadSubscription = NativeBrudcastInApp.onUnreadCountChange(setUnreadCount);
  NativeBrudcastInApp.getUnreadCount().then(setUnreadCount, (error: unknown) =>
    BrudcastLog.error(`Reading the unread count failed: ${String(error)}`)
  );
}

/**
 * Stores a new unread count and tells the listeners when it changed.
 *
 * @param count The count.
 */
function setUnreadCount(count: number): void {
  if (count === unreadCount) return;
  unreadCount = count;
  unreadListeners.forEach((listener) => listener(count));
}
