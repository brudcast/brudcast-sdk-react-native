import { processColor, type EventSubscription } from 'react-native';

import type { BrudcastAction, BrudcastActionHandler, BrudcastActionResult } from './action';
import { guardBrudcastCall, runBrudcastHandler } from './handlers';
import { BrudcastLog } from './log';
import type { BrudcastEnvironment, BrudcastIdentifyOptions, BrudcastOptions } from './options';
import { brudcastProperties } from './properties';
import NativeBrudcast, {
  type NativeActionRequest,
  type NativeEnvironment,
  type NativeOptions,
} from './specs/NativeBrudcast';
import { brudcastReactNativeVersion } from './version';

const eventName = /^[A-Za-z][A-Za-z0-9_.:-]{0,63}$/;

let actionHandler: BrudcastActionHandler | null = null;
let actionSubscription: EventSubscription | null = null;

/**
 * What the module packages add to `Brudcast`: `inApp` from `@brudcast/react-native-in-app` and
 * `push` from `@brudcast/react-native-push`. Each package declares its member here and installs it
 * when it is imported.
 */
export interface BrudcastExtensions {}

const core = {
  /**
   * Starts the SDK.
   *
   * @param publishableKey The application's publishable key (`bpk_...`) from the dashboard. It is
   *   public by design; never ship the identity secret in the app.
   * @param options The environment, logging, appearance and the modules to run.
   */
  async initialize(publishableKey: string, options: BrudcastOptions = {}): Promise<void> {
    if (publishableKey.trim().length === 0) {
      const message = 'Brudcast.initialize needs a publishable key';
      if (__DEV__) throw new Error(message);
      BrudcastLog.error(message);
      return;
    }
    BrudcastLog.setLevel(options.logLevel ?? 'warning');
    await guardBrudcastCall('initialize', () =>
      NativeBrudcast.initialize(publishableKey, nativeOptions(options))
    );
  },

  /**
   * Identifies the signed-in user.
   *
   * @param externalId Your id for the user, at most 191 characters.
   * @param options `userHash` is `HMAC-SHA256(identitySecret, externalId)` in hex, computed on
   *   your server; it is required when the application enforces identity verification. `traits`
   *   fill the contact Brudcast creates.
   */
  async identify(externalId: string, options: BrudcastIdentifyOptions = {}): Promise<void> {
    await guardBrudcastCall('identify', () =>
      NativeBrudcast.identify(externalId, options.userHash ?? null, options.traits ?? {})
    );
  },

  /**
   * Forgets the user on logout. The device keeps its id, and its push token stops reaching the
   * previous user.
   */
  async reset(): Promise<void> {
    await guardBrudcastCall('reset', () => NativeBrudcast.reset());
  },

  /**
   * Records a custom event. In-app messages triggered by it show at once.
   *
   * @param name A letter, then up to 63 letters, digits and `_ . : -`.
   * @param properties Strings, numbers, booleans and nulls; other values are dropped with a
   *   warning.
   */
  async track(name: string, properties: Readonly<Record<string, unknown>> = {}): Promise<void> {
    if (!core.isValidEventName(name)) {
      BrudcastLog.error(
        `track ignored "${name}": names start with a letter and use at most 64 letters, digits and _ . : -`
      );
      return;
    }
    await guardBrudcastCall('track', () =>
      NativeBrudcast.track(name, brudcastProperties(properties))
    );
  },

  /**
   * Records that the user is on a screen. In-app messages triggered by it show at once.
   *
   * @param name The screen's name.
   * @param properties Strings, numbers, booleans and nulls; other values are dropped with a
   *   warning.
   */
  async screen(name: string, properties: Readonly<Record<string, unknown>> = {}): Promise<void> {
    await guardBrudcastCall('screen', () =>
      NativeBrudcast.screen(name, brudcastProperties(properties))
    );
  },

  /**
   * Stops in-app campaign messages for this user. Transactional messages still arrive.
   */
  async optOut(): Promise<void> {
    await guardBrudcastCall('optOut', () => NativeBrudcast.setOptedOut(true));
  },

  /**
   * Resumes in-app campaign messages for this user.
   */
  async optIn(): Promise<void> {
    await guardBrudcastCall('optIn', () => NativeBrudcast.setOptedOut(false));
  },

  /**
   * Stops collecting and sending events, for consent frameworks. Waiting events are discarded.
   */
  async disableTracking(): Promise<void> {
    await guardBrudcastCall('disableTracking', () => NativeBrudcast.setTrackingEnabled(false));
  },

  /**
   * Resumes collecting events after `disableTracking`.
   */
  async enableTracking(): Promise<void> {
    await guardBrudcastCall('enableTracking', () => NativeBrudcast.setTrackingEnabled(true));
  },

  /**
   * Sends waiting events now instead of on the next timer tick.
   */
  async flush(): Promise<void> {
    await guardBrudcastCall('flush', () => NativeBrudcast.flush());
  },

  /**
   * Sets the handler for deep links, URLs and custom events from in-app buttons and push taps.
   * Return `handled` to skip the default behaviour, which opens the link.
   *
   * Set it early, next to `initialize`: a push tap that launched the app waits up to five seconds
   * for it.
   *
   * @param handler The handler, or null to restore the defaults.
   */
  async setActionHandler(handler: BrudcastActionHandler | null): Promise<void> {
    actionHandler = handler;
    if (handler && !actionSubscription) {
      actionSubscription = NativeBrudcast.onActionRequest(answerAction);
    } else if (!handler && actionSubscription) {
      actionSubscription.remove();
      actionSubscription = null;
    }
    await guardBrudcastCall('setActionHandler', () =>
      NativeBrudcast.setActionHandlerEnabled(handler !== null)
    );
  },

  /**
   * This install's device id, a random UUID the native SDK keeps.
   *
   * @returns The id, or null before `initialize`.
   */
  async getDeviceId(): Promise<string | null> {
    return (await guardBrudcastCall('getDeviceId', () => NativeBrudcast.getDeviceId())) ?? null;
  },

  /**
   * Checks an event name against the rule the service applies.
   *
   * @param name The name.
   * @returns True for a letter followed by up to 63 letters, digits and `_ . : -`.
   */
  isValidEventName(name: string): boolean {
    return eventName.test(name);
  },
};

/** The Brudcast SDK, with the members the installed module packages add. */
export type BrudcastSdk = typeof core & BrudcastExtensions;

/**
 * The Brudcast SDK.
 *
 * Call `initialize` once, early, before the first render. Every other call may come before it:
 * the native SDK holds calls made earlier and runs them once it starts. No call throws into the
 * app; failures are logged.
 */
export const Brudcast = core as BrudcastSdk;

/**
 * Adds a module package's member to `Brudcast`, such as `inApp` or `push`.
 *
 * @param name The member's name.
 * @param value The member.
 */
export function extendBrudcast(name: string, value: object): void {
  Object.defineProperty(core, name, { value, enumerable: true, configurable: true });
}

/**
 * Runs the app's action handler for a native request and sends its answer back.
 *
 * @param request The action, with the id native waits on.
 */
async function answerAction(request: NativeActionRequest): Promise<void> {
  const handler = actionHandler;
  const result: BrudcastActionResult = handler
    ? await runBrudcastHandler(
        'action handler',
        () => handler(actionFromNative(request)),
        'useDefault'
      )
    : 'useDefault';
  await guardBrudcastCall('resolveAction', () =>
    NativeBrudcast.resolveAction(request.requestId, result)
  );
}

/**
 * Converts an action request from native.
 *
 * @param request The request.
 * @returns The action the app sees.
 */
function actionFromNative(request: NativeActionRequest): BrudcastAction {
  return Object.freeze({
    kind: request.kind as BrudcastAction['kind'],
    value: request.value,
    opensInApp: request.opensInApp,
    source: Object.freeze({
      origin: request.source === 'push' ? 'push' : 'inApp',
      messageId: request.messageId,
      ...(request.buttonId ? { buttonId: request.buttonId } : {}),
    }),
    verified: request.verified,
  });
}

/**
 * Converts options for native.
 *
 * @param options The app's options.
 * @returns The options native takes.
 */
function nativeOptions(options: BrudcastOptions): NativeOptions {
  const color = options.accentColor == null ? null : processColor(options.accentColor);
  return {
    environment: nativeEnvironment(options.environment ?? 'production'),
    logLevel: options.logLevel ?? 'warning',
    appearance: options.appearance ?? 'system',
    ...(typeof color === 'number' ? { accentColor: color } : {}),
    modules: [...new Set((options.modules ?? []).map((module) => module.name))],
    ...(options.appGroupIdentifier ? { appGroupIdentifier: options.appGroupIdentifier } : {}),
    wrapperVersion: brudcastReactNativeVersion,
  };
}

/**
 * Converts an environment for native.
 *
 * @param environment The app's environment.
 * @returns The environment native takes.
 */
function nativeEnvironment(environment: BrudcastEnvironment): NativeEnvironment {
  if (typeof environment === 'string') return { kind: environment };
  if (environment.kind === 'custom') return { kind: 'custom', baseUrl: environment.baseUrl };
  return {
    kind: 'local',
    port: environment.port ?? 8191,
    androidHost: environment.androidHost ?? '10.0.2.2',
  };
}
