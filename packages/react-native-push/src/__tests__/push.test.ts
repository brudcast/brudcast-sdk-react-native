import { Platform } from 'react-native';

import { fakeEmitter, flushPromises } from '../../../react-native/src/__tests__/fakeEmitter';

const mockNative = {
  setToken: jest.fn(),
  requestPermission: jest.fn(async () => 'authorized'),
  getPermissionStatus: jest.fn(async () => 'denied'),
  setNotificationHandlerEnabled: jest.fn(),
  resolveNotification: jest.fn(),
  handleForegroundMessage: jest.fn(async () => true),
  onNotificationRequest: fakeEmitter<Record<string, unknown>>(),
  onPermissionChange: fakeEmitter<string>(),
};

jest.mock('../../../react-native/src/specs/NativeBrudcast', () => ({
  __esModule: true,
  default: { onActionRequest: () => ({ remove() {} }) },
}));

jest.mock('../specs/NativeBrudcastPush', () => ({
  __esModule: true,
  get default() {
    return mockNative;
  },
}));

import { Brudcast } from '@brudcast/react-native';
import { BrudcastPush, type BrudcastPushNotification } from '../index';

const brudcastMessage = {
  data: { bc_mid: 'pm1', bc_cid: 'c1', count: 3 as unknown as string },
  notification: { title: 'Sale', body: 'Today only', android: { imageUrl: 'https://img/x.png' } },
};

beforeEach(() => {
  jest.clearAllMocks();
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  jest.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(async () => {
  await BrudcastPush.setNotificationHandler(null);
  jest.useRealTimers();
  Platform.OS = 'ios';
});

it('installs itself on Brudcast', () => {
  expect(Brudcast.push).toBe(BrudcastPush);
  expect(BrudcastPush.module).toEqual({ name: 'push' });
});

describe('isBrudcastNotification', () => {
  it('needs a Brudcast message id', () => {
    expect(BrudcastPush.isBrudcastNotification({ bc_mid: 'pm1' })).toBe(true);
    expect(BrudcastPush.isBrudcastNotification({ bc_mid: '' })).toBe(false);
    expect(BrudcastPush.isBrudcastNotification({ other: 'x' })).toBe(false);
    expect(BrudcastPush.isBrudcastNotification(undefined)).toBe(false);
  });
});

describe('handleForegroundMessage', () => {
  it('hands a Brudcast message to native on Android, with its data as strings', async () => {
    Platform.OS = 'android';

    await expect(BrudcastPush.handleForegroundMessage(brudcastMessage)).resolves.toBe(true);

    expect(mockNative.handleForegroundMessage).toHaveBeenCalledWith(
      { bc_mid: 'pm1', bc_cid: 'c1', count: '3' },
      'Sale',
      'Today only',
      'https://img/x.png'
    );
  });

  it('only answers on iOS, where the system shows the notification', async () => {
    Platform.OS = 'ios';

    await expect(BrudcastPush.handleForegroundMessage(brudcastMessage)).resolves.toBe(true);

    expect(mockNative.handleForegroundMessage).not.toHaveBeenCalled();
  });

  it('leaves other senders to the app', async () => {
    Platform.OS = 'android';

    await expect(
      BrudcastPush.handleForegroundMessage({ data: { from: 'elsewhere' } })
    ).resolves.toBe(false);

    expect(mockNative.handleForegroundMessage).not.toHaveBeenCalled();
  });
});

describe('permission', () => {
  it('reads, requests and follows the status', async () => {
    await expect(BrudcastPush.getPermissionStatus()).resolves.toBe('denied');
    await expect(BrudcastPush.requestPermission({ provisional: true })).resolves.toBe('authorized');
    expect(mockNative.requestPermission).toHaveBeenCalledWith(true);

    const seen: string[] = [];
    const subscription = BrudcastPush.addPermissionListener((status) => seen.push(status));
    mockNative.onPermissionChange.emit('authorized');
    mockNative.onPermissionChange.emit('sideways');
    subscription.remove();

    expect(seen).toEqual(['authorized', 'notDetermined']);
  });

  it('answers notDetermined when native fails', async () => {
    mockNative.requestPermission.mockRejectedValueOnce(new Error('no activity'));

    await expect(BrudcastPush.requestPermission()).resolves.toBe('notDetermined');
  });
});

describe('the notification handler', () => {
  const request = {
    requestId: 'n1',
    notification: {
      messageId: 'pm1',
      campaignId: 'c1',
      title: 'Sale',
      clickUrl: 'shop://sale',
      data: { coupon: 'TEN' },
    },
  };

  it('answers native with the decision', async () => {
    const handler = jest.fn((_notification: BrudcastPushNotification) => 'suppress' as const);
    await BrudcastPush.setNotificationHandler(handler);

    mockNative.onNotificationRequest.emit(request);
    await flushPromises();

    expect(handler.mock.calls[0]?.[0]).toEqual({
      messageId: 'pm1',
      campaignId: 'c1',
      title: 'Sale',
      clickUrl: 'shop://sale',
      data: { coupon: 'TEN' },
    });
    expect(mockNative.resolveNotification).toHaveBeenCalledWith('n1', 'suppress');
  });

  it('shows the notification when the handler takes too long', async () => {
    jest.useFakeTimers();
    await BrudcastPush.setNotificationHandler(() => new Promise(() => {}));

    mockNative.onNotificationRequest.emit(request);
    await flushPromises();
    jest.advanceTimersByTime(2000);
    await flushPromises();

    expect(mockNative.resolveNotification).toHaveBeenCalledWith('n1', 'show');
  });
});

it('forwards the token', async () => {
  await BrudcastPush.setToken('fcm-token');

  expect(mockNative.setToken).toHaveBeenCalledWith('fcm-token');
});
