# @brudcast/react-native-in-app

[![npm](https://img.shields.io/npm/v/@brudcast/react-native-in-app.svg)](https://www.npmjs.com/package/@brudcast/react-native-in-app)
[![CI](https://github.com/brudcast/brudcast-sdk-react-native/actions/workflows/ci.yml/badge.svg)](https://github.com/brudcast/brudcast-sdk-react-native/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://github.com/brudcast/brudcast-sdk-react-native/blob/main/LICENSE)

In-app messaging for the [Brudcast React Native SDK](https://www.npmjs.com/package/@brudcast/react-native).
Messages are drawn natively, over any screen, by the same renderer native apps use.

## Features

- Modals, banners and full-screen messages, triggered by events, screens and segments, offline too.
- Hold messages back during checkout or a video, and decide per message whether it shows.
- Draw messages yourself and report impressions, clicks and dismissals.
- The inbox: the native inbox screen, or your own built with `useInbox`, and a live unread count.
- `<BrudcastInboxMessage>`, an inbox entry drawn by the native renderer with its buttons working.

## Getting started

```sh
yarn add @brudcast/react-native@0.2.1 @brudcast/react-native-in-app@0.2.1
cd ios && pod install
```

Set up [`@brudcast/react-native`](https://www.npmjs.com/package/@brudcast/react-native#getting-started),
then add the module when you initialise:

```ts
import { BrudcastInApp, BrudcastMessageDecision } from '@brudcast/react-native-in-app';

Brudcast.initialize('bpk_...', { modules: [BrudcastInApp.module] });
```

Importing the package also adds `Brudcast.inApp`, the same object as `BrudcastInApp`.

## Usage

### Control display

```ts
BrudcastInApp.pauseDisplay();
BrudcastInApp.resumeDisplay();

BrudcastInApp.setMessageHandler(async (message) => {
  if (isRecording) return BrudcastMessageDecision.Defer;
  return BrudcastMessageDecision.Show;
});
```

The handler answers `Show`, `Suppress` (not for this trigger), `Defer` (wait for the next trigger)
or `Custom` (draw it yourself) within two seconds, after which the message shows. The strings
`'show'`, `'suppress'`, `'defer'` and `'custom'` work too. For `Custom`,
report what happened with `reportImpression(id)`, `reportClick(id, buttonId)` and
`reportDismiss(id)`; `designDocument(message)` decodes the design.

### The inbox

```ts
BrudcastInApp.inbox.present({ title: 'Inbox' });

function InboxBadge() {
  const unread = useInboxUnreadCount();
  return unread > 0 ? <Badge count={unread} /> : null;
}

function Inbox() {
  const inbox = useInbox({ pageSize: 20 });
  return (
    <FlatList
      data={inbox.messages}
      keyExtractor={(message) => message.id}
      renderItem={({ item }) => <Row message={item} onPress={() => inbox.markRead(item)} />}
      onEndReached={inbox.loadMore}
      refreshing={inbox.isLoading}
      onRefresh={inbox.refresh}
    />
  );
}
```

`useInbox` loads the first page on mount and keeps `messages`, `hasMore`, `isLoading`, `error` and
`unreadCount`. `markRead` and `remove` update the list at once and tell the service on every
device. Without hooks, `BrudcastInbox.list({ before, limit })` returns a page and throws a
`BrudcastInboxError` when it cannot load one.

### Draw an entry natively

```tsx
<BrudcastInboxMessage message={message} />
```

It takes the width it is given and sizes its height to the design. Pass `expand` to fill the space
instead. The message must come from `list` or `useInbox`. Each one runs the renderer, so build
long lists from `title`, `preview` and `thumbnailUrl`, and use it for the detail screen.

## Additional information

- **Versions.** Keep this package on the same version as `@brudcast/react-native`.
- **Documentation:** [docs.brudcast.com](https://docs.brudcast.com).
- **License:** Apache License 2.0.
