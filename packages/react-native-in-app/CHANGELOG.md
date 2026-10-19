# Changelog

All notable changes to `@brudcast/react-native-in-app` are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org). Each release names the native SDK version it runs.

## [0.2.0] - 2026-10-19

### Added

- In-app messages drawn by the native renderer, with `BrudcastInApp.pauseDisplay`,
  `resumeDisplay`, `sync` and a message handler that may answer asynchronously within two seconds.
- Custom rendering reports: `reportImpression`, `reportClick` and `reportDismiss`.
- The inbox: `BrudcastInbox.present`, `list`, `markRead`, `delete`, the unread count, and the
  `useInbox` and `useInboxUnreadCount` hooks.
- `<BrudcastInboxMessage>`, which draws an inbox entry with the native renderer and sizes itself
  to the design.
