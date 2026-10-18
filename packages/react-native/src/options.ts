import type { ColorValue } from 'react-native';

/**
 * The Brudcast environment the SDK talks to: a named deployment, the service on the development
 * machine, or any other deployment by the base URL of its SDK API.
 */
export type BrudcastEnvironment =
  | 'production'
  | 'staging'
  | 'uat'
  | 'development'
  | { kind: 'local'; port?: number; androidHost?: string }
  | { kind: 'custom'; baseUrl: string };

/** How much the SDK logs, from everything to nothing. */
export type BrudcastLogLevel = 'verbose' | 'debug' | 'info' | 'warning' | 'error' | 'none';

/** Which appearance in-app messages use: the device's setting, or always light or dark. */
export type BrudcastAppearance = 'system' | 'light' | 'dark';

/**
 * A feature module the SDK runs, such as in-app messaging or push. Add `BrudcastInApp.module` from
 * `@brudcast/react-native-in-app` and `BrudcastPush.module` from `@brudcast/react-native-push` to
 * `BrudcastOptions.modules`.
 */
export type BrudcastModule = {
  readonly name: string;
};

/** Configuration passed to `Brudcast.initialize`. Every field is optional. */
export type BrudcastOptions = {
  environment?: BrudcastEnvironment;
  logLevel?: BrudcastLogLevel;
  appearance?: BrudcastAppearance;
  accentColor?: ColorValue;
  modules?: readonly BrudcastModule[];
  appGroupIdentifier?: string;
};

/**
 * Optional traits sent with `identify`. Brudcast uses them to fill a new contact; they never
 * overwrite values a contact already has.
 */
export type BrudcastTraits = {
  email?: string;
  phone?: string;
  firstName?: string;
  lastName?: string;
  language?: string;
  timezone?: string;
};

/** The options of `identify`. */
export type BrudcastIdentifyOptions = {
  userHash?: string;
  traits?: BrudcastTraits;
};

/**
 * Creates the environment for the service on the development machine: `localhost` from the iOS
 * simulator, and `androidHost`, `10.0.2.2` by default, from the Android emulator.
 *
 * @param options The port, 8191 by default, and the host the Android emulator uses.
 * @returns The environment.
 */
export function localEnvironment(
  options: { port?: number; androidHost?: string } = {}
): BrudcastEnvironment {
  return { kind: 'local', ...options };
}

/**
 * Creates the environment for any other deployment.
 *
 * @param baseUrl The base URL of its SDK API, ending in `/sdk/v1`.
 * @returns The environment.
 */
export function customEnvironment(baseUrl: string): BrudcastEnvironment {
  return { kind: 'custom', baseUrl };
}
