# @brudcast/react-native-push

[![npm](https://img.shields.io/npm/v/@brudcast/react-native-push.svg)](https://www.npmjs.com/package/@brudcast/react-native-push)
[![CI](https://github.com/brudcast/brudcast-sdk-react-native/actions/workflows/ci.yml/badge.svg)](https://github.com/brudcast/brudcast-sdk-react-native/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://github.com/brudcast/brudcast-sdk-react-native/blob/main/LICENSE)

Push notifications for the [Brudcast React Native SDK](https://www.npmjs.com/package/@brudcast/react-native).
Brudcast sends through FCM, and this package works alongside
[`@react-native-firebase/messaging`](https://rnfirebase.io/messaging/usage), which owns the
Firebase integration.

## Features

- Registers the FCM token for the signed-in user, and detaches it on logout.
- Records opens natively, with no JavaScript, including the tap that launches the app, and routes
  the notification's link through the action handler.
- Shows Brudcast notifications that arrive in the foreground on Android, which Firebase leaves to
  the app.
- Asks for notification permission, and reports the status as it changes.
- A handler to show or suppress notifications that arrive while the app is open.
- Notification images and `push_received` on iOS through a notification service extension, set up
  by an Expo config plugin or one Podfile target.

## Getting started

```sh
yarn add @brudcast/react-native@0.2.1 @brudcast/react-native-push@0.2.1 \
  @react-native-firebase/app @react-native-firebase/messaging
cd ios && pod install
```

1. Set up [`@brudcast/react-native`](https://www.npmjs.com/package/@brudcast/react-native#getting-started),
   and React Native Firebase for both platforms as its documentation describes.
2. Link the in-app application to a push application in the Brudcast dashboard.
3. Add the module when you initialise:

   ```ts
   import { BrudcastPush } from '@brudcast/react-native-push';

   Brudcast.initialize('bpk_...', { modules: [BrudcastPush.module] });
   ```

**Expo without React Native Firebase does not work on iOS.** `expo-notifications` hands the app the
APNs token there, not an FCM token, and Brudcast sends through FCM only. Add
`@react-native-firebase/messaging` for the token, even if you keep `expo-notifications`.

**Android:** do not declare `BrudcastFirebaseMessagingService` from the native SDK. Android gives
`MESSAGING_EVENT` to one service, and React Native Firebase declares its own. The small icon is
the one set for FCM in the manifest's `com.google.firebase.messaging.default_notification_icon`
meta-data, then a plain bell.

**iOS:** add the Push Notifications capability. Nothing else is needed for taps: when the app
finishes launching, the package puts a proxy in front of the notification center's delegate,
whether that is your `AppDelegate`, React Native Firebase or `expo-notifications`, and passes
everything on to it. To handle responses yourself instead, set `BrudcastAutomaticNotificationDelegate`
to `NO` in Info.plist and call `Brudcast.push.handleNotificationResponse` from native code.

### Images and `push_received` on iOS

A notification service extension attaches images and records that the device received each
notification. It shares an App Group with the app.

**Expo:** add the plugin, then `npx expo prebuild`:

```json
{
  "expo": {
    "ios": { "bundleIdentifier": "com.example.app" },
    "plugins": [
      "@react-native-firebase/app",
      "@react-native-firebase/messaging",
      ["@brudcast/react-native-push", { "appGroupIdentifier": "group.com.example.app.brudcast" }]
    ]
  }
}
```

The plugin adds the push entitlement, the App Group, and a `BrudcastNotificationExtension` target
signed with the app by EAS Build. Options: `appGroupIdentifier` (default
`group.<bundle id>.brudcast`), `notificationServiceExtension` (default `true`),
`automaticNotificationDelegate` (default `true`) and `apsEnvironment` (default `development`).

**Bare React Native:** in Xcode, add a Notification Service Extension target named
`BrudcastNotificationExtension` (any name but `BrudcastNotificationService`, which would make
the target's own module shadow the pod's), give it and the app the same App Group, and make its
class:

```swift
import BrudcastNotificationService

final class NotificationService: BrudcastNotificationServiceExtension {
    override var appGroupIdentifier: String? { "group.com.example.app.brudcast" }
}
```

Then add its pod to the Podfile and run `pod install`:

```ruby
target 'BrudcastNotificationExtension' do
  pod 'BrudcastNotificationService', :path => '../node_modules/@brudcast/react-native-push/ios/notification-service'
end
```

and pass the group to `initialize` as `appGroupIdentifier`, or set `BrudcastAppGroupIdentifier` in
the app's Info.plist.

## Usage

### Connect React Native Firebase

```ts
import messaging from '@react-native-firebase/messaging';

const token = await messaging().getToken();
BrudcastPush.setToken(token);
messaging().onTokenRefresh(BrudcastPush.setToken);

messaging().onMessage((message) => BrudcastPush.handleForegroundMessage(message));

messaging().setBackgroundMessageHandler(async (message) => {
  if (BrudcastPush.isBrudcastNotification(message.data)) return;
});
```

`handleForegroundMessage` shows Brudcast notifications on Android and does nothing on iOS, where
the system shows them, so call it on both platforms. It resolves `false` for messages from other
senders. In `setBackgroundMessageHandler`, which runs before the app mounts, only
`isBrudcastNotification` is useful; Brudcast notifications need nothing there.

### Ask for permission

```ts
const status = await BrudcastPush.requestPermission();
const subscription = BrudcastPush.addPermissionListener((status) => setStatus(status));
```

Android 13 and later and iOS show a prompt. `requestPermission({ provisional: true })` asks iOS for
quiet delivery without one.

### Foreground notifications

```ts
BrudcastPush.setNotificationHandler(async (notification) => (onChatScreen ? 'suppress' : 'show'));
```

The handler has two seconds to answer, after which the notification shows.

## Additional information

- **Versions.** Keep this package on the same version as `@brudcast/react-native`.
- **Documentation:** [docs.brudcast.com](https://docs.brudcast.com).
- **License:** Apache License 2.0.
