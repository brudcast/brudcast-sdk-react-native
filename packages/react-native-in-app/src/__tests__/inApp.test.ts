import { fakeEmitter, flushPromises } from '../../../react-native/src/__tests__/fakeEmitter';

const mockNative = {
  pauseDisplay: jest.fn(),
  resumeDisplay: jest.fn(),
  sync: jest.fn(),
  setMessageHandlerEnabled: jest.fn(),
  resolveMessage: jest.fn(),
  reportImpression: jest.fn(),
  reportClick: jest.fn(),
  reportDismiss: jest.fn(),
  presentInbox: jest.fn(),
  listInbox: jest.fn(),
  markRead: jest.fn(),
  deleteMessage: jest.fn(),
  getUnreadCount: jest.fn(async () => 3),
  onMessageRequest: fakeEmitter<Record<string, unknown>>(),
  onUnreadCountChange: fakeEmitter<number>(),
};

jest.mock('../specs/NativeBrudcastInApp', () => ({
  __esModule: true,
  get default() {
    return mockNative;
  },
}));

jest.mock('../../../react-native/src/specs/NativeBrudcast', () => ({
  __esModule: true,
  default: { onActionRequest: () => ({ remove() {} }) },
}));

jest.mock('../specs/BrudcastInboxMessageNativeComponent', () => ({
  __esModule: true,
  default: 'BrudcastInboxMessageView',
}));

import { Brudcast } from '@brudcast/react-native';
import {
  BrudcastInApp,
  BrudcastInboxError,
  designDocument,
  type BrudcastInAppMessage,
} from '../index';

const nativeMessage = {
  id: 'm1',
  campaignId: 'c1',
  format: 'modal',
  isTest: false,
  title: 'Welcome',
  preview: 'Hello there',
  isRead: false,
  createdAtMillis: 1_760_000_000_000,
  design: '{"title":"Welcome"}',
};

beforeEach(() => {
  jest.clearAllMocks();
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  jest.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(async () => {
  await BrudcastInApp.setMessageHandler(null);
  jest.useRealTimers();
});

it('installs itself on Brudcast', () => {
  expect(Brudcast.inApp).toBe(BrudcastInApp);
  expect(BrudcastInApp.module).toEqual({ name: 'in_app' });
});

describe('the inbox', () => {
  it('converts a page and clamps the limit', async () => {
    mockNative.listInbox.mockResolvedValueOnce({
      messages: [
        nativeMessage,
        { ...nativeMessage, id: 'm2', campaignId: undefined, thumbnailUrl: 'https://img/x.png' },
      ],
      unreadCount: 2,
      hasMore: true,
    });

    const page = await BrudcastInApp.inbox.list({ before: new Date(1_000), limit: 500 });

    expect(mockNative.listInbox).toHaveBeenCalledWith(1_000, 100);
    expect(page.unreadCount).toBe(2);
    expect(page.hasMore).toBe(true);
    expect(page.messages[0]).toEqual({
      id: 'm1',
      campaignId: 'c1',
      format: 'modal',
      isTest: false,
      title: 'Welcome',
      preview: 'Hello there',
      isRead: false,
      createdAt: new Date(1_760_000_000_000),
      design: '{"title":"Welcome"}',
    });
    expect(page.messages[1]).not.toHaveProperty('campaignId');
    expect(page.messages[1]?.thumbnailUrl).toBe('https://img/x.png');
  });

  it('asks for the newest page with no date', async () => {
    mockNative.listInbox.mockResolvedValueOnce({ messages: [], unreadCount: 0, hasMore: false });

    await BrudcastInApp.inbox.list();

    expect(mockNative.listInbox).toHaveBeenCalledWith(null, 20);
  });

  it('rejects with the native error code', async () => {
    mockNative.listInbox.mockRejectedValueOnce(
      Object.assign(new Error('Brudcast is not initialized'), { code: 'not_initialized' })
    );

    const error = await BrudcastInApp.inbox.list().catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(BrudcastInboxError);
    expect(error).toMatchObject({
      code: 'not_initialized',
      message: 'Brudcast is not initialized',
    });
  });

  it('follows the unread count from its current value', async () => {
    const seen: number[] = [];
    const subscription = BrudcastInApp.inbox.addUnreadCountListener((count) => seen.push(count));
    await flushPromises();
    mockNative.onUnreadCountChange.emit(4);
    mockNative.onUnreadCountChange.emit(4);
    subscription.remove();
    mockNative.onUnreadCountChange.emit(5);

    expect(seen).toEqual([3, 4]);
    expect(BrudcastInApp.inbox.getUnreadCount()).toBe(5);
  });

  it('forwards the entry calls', async () => {
    await BrudcastInApp.inbox.markRead('m1');
    await BrudcastInApp.inbox.delete('m2');
    await BrudcastInApp.inbox.present();

    expect(mockNative.markRead).toHaveBeenCalledWith('m1');
    expect(mockNative.deleteMessage).toHaveBeenCalledWith('m2');
    expect(mockNative.presentInbox).toHaveBeenCalledWith('Inbox');
  });
});

describe('the message handler', () => {
  it('answers native with the decision', async () => {
    const handler = jest.fn((_message: BrudcastInAppMessage) => 'custom' as const);
    await BrudcastInApp.setMessageHandler(handler);

    mockNative.onMessageRequest.emit({ requestId: 'r1', message: nativeMessage });
    await flushPromises();

    expect(handler.mock.calls[0]?.[0].id).toBe('m1');
    expect(mockNative.resolveMessage).toHaveBeenCalledWith('r1', 'custom');
  });

  it('shows the message when the handler takes too long', async () => {
    jest.useFakeTimers();
    await BrudcastInApp.setMessageHandler(() => new Promise(() => {}));

    mockNative.onMessageRequest.emit({ requestId: 'r2', message: nativeMessage });
    await flushPromises();
    jest.advanceTimersByTime(2000);
    await flushPromises();

    expect(mockNative.resolveMessage).toHaveBeenCalledWith('r2', 'show');
  });

  it('turns the native handler off when cleared', async () => {
    await BrudcastInApp.setMessageHandler(() => 'show');
    await BrudcastInApp.setMessageHandler(null);

    expect(mockNative.setMessageHandlerEnabled.mock.calls).toEqual([[true], [false]]);
    expect(mockNative.onMessageRequest.listenerCount()).toBe(0);
  });
});

describe('the report calls', () => {
  it('forward to native', async () => {
    await BrudcastInApp.reportImpression('m1');
    await BrudcastInApp.reportClick('m1', 'b1');
    await BrudcastInApp.reportDismiss('m1');
    await BrudcastInApp.pauseDisplay();
    await BrudcastInApp.resumeDisplay();
    await BrudcastInApp.sync();

    expect(mockNative.reportImpression).toHaveBeenCalledWith('m1');
    expect(mockNative.reportClick).toHaveBeenCalledWith('m1', 'b1');
    expect(mockNative.reportDismiss).toHaveBeenCalledWith('m1');
    expect(mockNative.pauseDisplay).toHaveBeenCalled();
    expect(mockNative.resumeDisplay).toHaveBeenCalled();
    expect(mockNative.sync).toHaveBeenCalled();
  });
});

describe('designDocument', () => {
  it('decodes an object and ignores anything else', () => {
    const message = { design: '{"a":1}' } as BrudcastInAppMessage;

    expect(designDocument(message)).toEqual({ a: 1 });
    expect(designDocument({ ...message, design: '[1]' })).toEqual({});
    expect(designDocument({ ...message, design: 'not json' })).toEqual({});
  });
});
