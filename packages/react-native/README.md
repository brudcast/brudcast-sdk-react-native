# @brudcast/react-native

[![npm](https://img.shields.io/npm/v/@brudcast/react-native.svg)](https://www.npmjs.com/package/@brudcast/react-native)
[![CI](https://github.com/brudcast/brudcast-sdk-react-native/actions/workflows/ci.yml/badge.svg)](https://github.com/brudcast/brudcast-sdk-react-native/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://github.com/brudcast/brudcast-sdk-react-native/blob/main/LICENSE)

The [Brudcast](https://brudcast.com) SDK for React Native: sessions, identity, events and deep link
handling for in-app messaging and push notifications. It runs the native
[Android](https://github.com/brudcast/brudcast-sdk-android) and
[iOS](https://github.com/brudcast/brudcast-sdk-ios) SDKs, so storage, networking, the event queue,
triggers and message rendering are the same code a native app runs.

## Features

- Identify signed-in users with a hash computed on your server, and forget them on logout.
- Record events and screens that trigger in-app messages and segment users.
- Route deep links, URLs and custom events from messages and push taps to your app's router,
  including the tap that launches the app.
- Consent controls: opt out of campaign messages, or stop all event collection.
- Every call is safe before `initialize`, and nothing throws into your app.

Add the module packages for the channels you use:

| Package                                                                                        | Adds                                                          |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| [`@brudcast/react-native-in-app`](https://www.npmjs.com/package/@brudcast/react-native-in-app) | In-app messages, the inbox, its hooks and an entry view       |
| [`@brudcast/react-native-push`](https://www.npmjs.com/package/@brudcast/react-native-push)     | Push notifications through `@react-native-firebase/messaging` |

A push-only app adds `@brudcast/react-native-push` alone and never ships the in-app renderer.

## Platform support

| React Native                     | Android          | iOS            | Expo                         |
| -------------------------------- | ---------------- | -------------- | ---------------------------- |
| 0.86 and later, New Architecture | API 24 and later | 15.1 and later | SDK 57 and later, dev builds |

The packages are TurboModules and Fabric components only; the legacy architecture is not
supported. Expo Go cannot load them. Web and Windows are not supported.

## Getting started

```sh
yarn add @brudcast/react-native@0.2.0 @brudcast/react-native-in-app@0.2.0 @brudcast/react-native-push@0.2.0
cd ios && pod install
```

List every Brudcast package your app uses in its own `package.json`: autolinking only links direct
dependencies. In an Expo app, add `@brudcast/react-native-push` to `plugins` (see its README) and
run `npx expo prebuild`.

Start the SDK once, before the first render, in `index.js`:

```ts
import { Brudcast } from '@brudcast/react-native';
import { BrudcastInApp } from '@brudcast/react-native-in-app';
import { BrudcastPush } from '@brudcast/react-native-push';

Brudcast.setActionHandler(handleAction);
Brudcast.initialize('bpk_...', {
  modules: [BrudcastInApp.module, BrudcastPush.module],
});
```

The publishable key (`bpk_...`) is in the dashboard under the in-app application. It is public by
design. Never ship the identity secret in the app.

## Usage

### Identify the user

```ts
await Brudcast.identify(user.id, {
  userHash: user.brudcastHash,
  traits: { email: user.email, firstName: user.firstName },
});

await Brudcast.reset();
```

`userHash` is `hex(HMAC-SHA256(identitySecret, user.id))`, computed on your server and sent to the
app at sign-in. It is required when the application enforces identity verification. Call `reset`
on logout: the device keeps its id, and its push token stops reaching the previous user.

### Events and screens

```ts
Brudcast.track('checkout_started', { total: 120, product: 'sneakers' });
Brudcast.screen('Checkout');
```

Names start with a letter and hold up to 64 letters, digits and `_ . : -`. Properties hold strings,
numbers, booleans and nulls; anything else is dropped with a warning.

### Deep links and custom events

Messages and push taps can open a deep link, open a URL or fire a custom event. By default the SDK
opens the link. Set an action handler to route it yourself:

```ts
Brudcast.setActionHandler(async (action) => {
  if (action.kind === 'deeplink' && router.canOpen(action.value)) {
    router.open(action.value);
    return 'handled';
  }
  return 'useDefault';
});
```

Set it next to `initialize`: a push tap that launched the app waits up to five seconds for it. The
handler has two seconds to answer, after which the default runs. On Android, `action.verified` is
false for a push tap the SDK cannot prove it created; check it before opening a private screen.

### Consent

```ts
Brudcast.optOut();
Brudcast.optIn();
Brudcast.disableTracking();
Brudcast.enableTracking();
```

`optOut` stops campaign in-app messages for the user; transactional messages still arrive.
`disableTracking` stops collecting and sending events altogether and discards waiting ones.

### Environments

```ts
import { localEnvironment, customEnvironment } from '@brudcast/react-native';

Brudcast.initialize('bpk_...', { environment: 'staging' });
Brudcast.initialize('bpk_...', { environment: localEnvironment({ port: 8191 }) });
Brudcast.initialize('bpk_...', {
  environment: customEnvironment('https://in-app.example.com/sdk/v1'),
});
```

`localEnvironment` reaches the service on the development machine: `localhost` from the iOS
simulator, `10.0.2.2` from the Android emulator.

## Additional information

- **Versions.** Keep every Brudcast package on the same version; the module packages require the
  exact core version. The changelog names the native SDK version each release runs.
- **Dev reloads.** Handlers set from JavaScript are dropped when the bundle reloads and set again
  by your startup code. Messages and taps that were waiting on the old bundle get the default.
- **Example.** A complete app is in
  [`example`](https://github.com/brudcast/brudcast-sdk-react-native/tree/main/example).
- **Documentation:** [docs.brudcast.com](https://docs.brudcast.com).
- **Security:** report vulnerabilities as
  [SECURITY.md](https://github.com/brudcast/brudcast-sdk-react-native/blob/main/SECURITY.md)
  describes, never in a public issue.
- **License:** Apache License 2.0.
