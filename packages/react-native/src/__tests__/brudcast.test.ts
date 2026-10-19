import { fakeEmitter, flushPromises } from './fakeEmitter';

const mockNative = {
  initialize: jest.fn(),
  identify: jest.fn(),
  reset: jest.fn(),
  track: jest.fn(),
  screen: jest.fn(),
  setOptedOut: jest.fn(),
  setTrackingEnabled: jest.fn(),
  flush: jest.fn(),
  setActionHandlerEnabled: jest.fn(),
  resolveAction: jest.fn(),
  getDeviceId: jest.fn(async () => 'device-1'),
  onActionRequest: fakeEmitter<Record<string, unknown>>(),
};

jest.mock('../specs/NativeBrudcast', () => ({
  __esModule: true,
  get default() {
    return mockNative;
  },
}));

import { Brudcast, customEnvironment, localEnvironment } from '../index';
import { extendBrudcast } from '../module';

const request = {
  requestId: 'r1',
  kind: 'deeplink',
  value: 'shop://checkout',
  opensInApp: false,
  source: 'push',
  messageId: 'm1',
  verified: false,
};

beforeEach(() => {
  jest.clearAllMocks();
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  jest.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(async () => {
  await Brudcast.setActionHandler(null);
  jest.useRealTimers();
});

describe('initialize', () => {
  it('sends defaults, the wrapper version and each module once', async () => {
    await Brudcast.initialize('bpk_test', {
      modules: [{ name: 'in_app' }, { name: 'push' }, { name: 'in_app' }],
    });

    expect(mockNative.initialize).toHaveBeenCalledWith('bpk_test', {
      environment: { kind: 'production' },
      logLevel: 'warning',
      appearance: 'system',
      modules: ['in_app', 'push'],
      wrapperVersion: '0.2.1',
    });
  });

  it('fills a local environment with the emulator host and port', async () => {
    await Brudcast.initialize('bpk_test', { environment: localEnvironment() });

    expect(mockNative.initialize.mock.calls[0][1].environment).toEqual({
      kind: 'local',
      port: 8191,
      androidHost: '10.0.2.2',
    });
  });

  it('passes a custom base URL and the accent colour as a number', async () => {
    await Brudcast.initialize('bpk_test', {
      environment: customEnvironment('https://in-app.example.com/sdk/v1'),
      accentColor: '#3355FF',
      appGroupIdentifier: 'group.example',
    });

    const options = mockNative.initialize.mock.calls[0][1];
    expect(options.environment).toEqual({
      kind: 'custom',
      baseUrl: 'https://in-app.example.com/sdk/v1',
    });
    expect(typeof options.accentColor).toBe('number');
    expect(options.appGroupIdentifier).toBe('group.example');
  });

  it('refuses an empty key in development', async () => {
    await expect(Brudcast.initialize('  ')).rejects.toThrow('publishable key');
    expect(mockNative.initialize).not.toHaveBeenCalled();
  });

  it('logs instead of throwing when mockNative fails', async () => {
    mockNative.initialize.mockImplementationOnce(() => {
      throw new Error('boom');
    });

    await expect(Brudcast.initialize('bpk_test')).resolves.toBeUndefined();
    expect(console.error).toHaveBeenCalledWith(expect.stringContaining('initialize failed'));
  });
});

describe('identify', () => {
  it('sends the hash and traits', async () => {
    await Brudcast.identify('user-1', { userHash: 'abc', traits: { email: 'a@example.com' } });

    expect(mockNative.identify).toHaveBeenCalledWith('user-1', 'abc', { email: 'a@example.com' });
  });

  it('sends null and empty traits when they are left out', async () => {
    await Brudcast.identify('user-1');

    expect(mockNative.identify).toHaveBeenCalledWith('user-1', null, {});
  });
});

describe('track', () => {
  it('drops an invalid event name', async () => {
    await Brudcast.track('1st-event');

    expect(mockNative.track).not.toHaveBeenCalled();
    expect(console.error).toHaveBeenCalledWith(expect.stringContaining('track ignored'));
  });

  it('keeps strings, finite numbers, booleans and nulls', async () => {
    await Brudcast.track('checkout_started', {
      total: 120,
      product: 'sneakers',
      gift: false,
      coupon: null,
      ratio: Number.NaN,
      tags: ['a'],
      when: new Date(),
      missing: undefined,
    });

    expect(mockNative.track).toHaveBeenCalledWith('checkout_started', {
      total: 120,
      product: 'sneakers',
      gift: false,
      coupon: null,
    });
    expect(console.warn).toHaveBeenCalledTimes(4);
  });

  it('accepts names up to 64 characters', () => {
    expect(Brudcast.isValidEventName(`a${'b'.repeat(63)}`)).toBe(true);
    expect(Brudcast.isValidEventName(`a${'b'.repeat(64)}`)).toBe(false);
    expect(Brudcast.isValidEventName('order.paid:v2-x')).toBe(true);
  });
});

describe('the simple calls', () => {
  it('forward to native', async () => {
    await Brudcast.screen('Checkout', { step: 2 });
    await Brudcast.optOut();
    await Brudcast.optIn();
    await Brudcast.disableTracking();
    await Brudcast.enableTracking();
    await Brudcast.flush();
    await Brudcast.reset();

    expect(mockNative.screen).toHaveBeenCalledWith('Checkout', { step: 2 });
    expect(mockNative.setOptedOut.mock.calls).toEqual([[true], [false]]);
    expect(mockNative.setTrackingEnabled.mock.calls).toEqual([[false], [true]]);
    expect(mockNative.flush).toHaveBeenCalled();
    expect(mockNative.reset).toHaveBeenCalled();
    await expect(Brudcast.getDeviceId()).resolves.toBe('device-1');
  });
});

describe('the action handler', () => {
  it('answers mockNative with what the handler decided', async () => {
    const handler = jest.fn((_action: unknown) => 'handled' as const);
    await Brudcast.setActionHandler(handler);
    expect(mockNative.setActionHandlerEnabled).toHaveBeenLastCalledWith(true);

    mockNative.onActionRequest.emit(request);
    await flushPromises();

    expect(handler).toHaveBeenCalledWith({
      kind: 'deeplink',
      value: 'shop://checkout',
      opensInApp: false,
      source: { origin: 'push', messageId: 'm1' },
      verified: false,
    });
    expect(mockNative.resolveAction).toHaveBeenCalledWith('r1', 'handled');
  });

  it('passes the button of an in-app action', async () => {
    const handler = jest.fn((_action: unknown) => 'useDefault' as const);
    await Brudcast.setActionHandler(handler);

    mockNative.onActionRequest.emit({ ...request, source: 'inApp', buttonId: 'b1' });
    await flushPromises();

    expect(handler.mock.calls[0]?.[0]).toMatchObject({
      source: { origin: 'inApp', messageId: 'm1', buttonId: 'b1' },
    });
  });

  it('uses the default when the handler throws', async () => {
    await Brudcast.setActionHandler(() => {
      throw new Error('router broke');
    });

    mockNative.onActionRequest.emit(request);
    await flushPromises();

    expect(mockNative.resolveAction).toHaveBeenCalledWith('r1', 'useDefault');
  });

  it('uses the default when the handler takes longer than two seconds', async () => {
    jest.useFakeTimers();
    await Brudcast.setActionHandler(() => new Promise(() => {}));

    mockNative.onActionRequest.emit(request);
    await flushPromises();
    jest.advanceTimersByTime(2000);
    await flushPromises();

    expect(mockNative.resolveAction).toHaveBeenCalledWith('r1', 'useDefault');
  });

  it('stops listening when the handler is cleared', async () => {
    await Brudcast.setActionHandler(() => 'handled');
    await Brudcast.setActionHandler(() => 'handled');
    expect(mockNative.onActionRequest.listenerCount()).toBe(1);

    await Brudcast.setActionHandler(null);

    expect(mockNative.onActionRequest.listenerCount()).toBe(0);
    expect(mockNative.setActionHandlerEnabled).toHaveBeenLastCalledWith(false);
  });
});

describe('extendBrudcast', () => {
  it('adds a module package member', () => {
    const member = { ping: () => 'pong' };
    extendBrudcast('example', member);

    expect((Brudcast as unknown as Record<string, unknown>).example).toBe(member);
  });
});
