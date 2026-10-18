# Changelog

All notable changes to `@brudcast/react-native-push` are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org) with the same version as the native SDKs it runs.

## [0.2.0] - Unreleased

### Added

- Push notifications through FCM: `BrudcastPush.setToken`, `requestPermission`,
  `getPermissionStatus`, `addPermissionListener` and a notification handler that may answer
  asynchronously within two seconds.
- `handleForegroundMessage` for messages `@react-native-firebase/messaging` delivers in the
  foreground on Android, and `isBrudcastNotification`, which needs no native code.
- Taps recorded natively with no JavaScript: on iOS through a notification center proxy that sits
  in front of the app's delegate and passes everything on.
- `BrudcastNotificationService.podspec` for a notification service extension, and an Expo config
  plugin that adds the extension, the App Group and the push entitlement.
