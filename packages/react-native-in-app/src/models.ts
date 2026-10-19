import type { NativeInAppMessage } from './specs/NativeBrudcastInApp';

/**
 * How a message is drawn: a card over the app, a strip at the top or bottom, the whole screen, or
 * only in the inbox.
 */
export type BrudcastMessageFormat = 'modal' | 'banner' | 'fullscreen' | 'inboxOnly';

/** A message as the app sees it, in the message handler and the inbox. */
export type BrudcastInAppMessage = {
  readonly id: string;
  readonly campaignId?: string;
  readonly format: BrudcastMessageFormat;
  readonly isTest: boolean;
  readonly title: string;
  readonly preview: string;
  readonly thumbnailUrl?: string;
  readonly isRead: boolean;
  readonly createdAt: Date;
  readonly design: string;
};

/** One page of the inbox, newest first. */
export type BrudcastInboxPage = {
  readonly messages: readonly BrudcastInAppMessage[];
  readonly unreadCount: number;
  readonly hasMore: boolean;
};

/**
 * What the message handler wants done with a message about to show: show it, skip it for this
 * trigger, leave it for the next trigger, or draw it in the app and report what happened. The
 * handler may answer with these constants or with the strings they stand for.
 */
export const BrudcastMessageDecision = {
  Show: 'show',
  Suppress: 'suppress',
  Defer: 'defer',
  Custom: 'custom',
} as const;

/**
 * One of the `BrudcastMessageDecision` values: `show`, `suppress`, `defer` or `custom`.
 */
export type BrudcastMessageDecision =
  (typeof BrudcastMessageDecision)[keyof typeof BrudcastMessageDecision];

/**
 * Decides what happens to a message about to show. It has two seconds to answer, after which the
 * message shows.
 */
export type BrudcastMessageHandler = (
  message: BrudcastInAppMessage
) => BrudcastMessageDecision | Promise<BrudcastMessageDecision>;

/** Why the inbox could not be loaded. */
export class BrudcastInboxError extends Error {
  /**
   * Creates an error.
   *
   * @param code The service's error code, such as `not_initialized`, or `inbox_failed`.
   * @param message What went wrong.
   */
  constructor(
    readonly code: string,
    message: string
  ) {
    super(message);
    this.name = 'BrudcastInboxError';
  }
}

/**
 * Converts a message from native.
 *
 * @param message The message.
 * @returns The message the app sees.
 */
export function messageFromNative(message: NativeInAppMessage): BrudcastInAppMessage {
  return Object.freeze({
    id: message.id,
    ...(message.campaignId ? { campaignId: message.campaignId } : {}),
    format: message.format as BrudcastMessageFormat,
    isTest: message.isTest,
    title: message.title,
    preview: message.preview,
    ...(message.thumbnailUrl ? { thumbnailUrl: message.thumbnailUrl } : {}),
    isRead: message.isRead,
    createdAt: new Date(message.createdAtMillis),
    design: message.design,
  });
}

/**
 * Decodes a message's design document.
 *
 * @param message The message.
 * @returns The design, or an empty object when it is not a JSON object.
 */
export function designDocument(message: BrudcastInAppMessage): Readonly<Record<string, unknown>> {
  try {
    const decoded: unknown = JSON.parse(message.design);
    return decoded !== null && typeof decoded === 'object' && !Array.isArray(decoded)
      ? (decoded as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

/**
 * Copies a message marked read.
 *
 * @param message The message.
 * @returns The copy.
 */
export function markedRead(message: BrudcastInAppMessage): BrudcastInAppMessage {
  return Object.freeze({ ...message, isRead: true });
}
