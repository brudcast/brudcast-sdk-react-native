# Brudcast React Native example

A small app built the way a customer's app would be, with each SDK call where a real app puts it:
identify at sign-in, reset at sign-out, a screen view as each screen appears, events as the user
shops, and message buttons that open the app's own screens. It uses the packages in this
repository through Metro, so changes to their TypeScript show up on reload. It is a bare React
Native 0.86 app on the New Architecture, with the template's `MainActivity` and `AppDelegate`
unchanged: the SDK needs no native code in the app.

## Run it

1. Copy `config/local.json.example` to `config/local.json` (ignored by git) and set the publishable
   key of an in-app application in the dashboard:

   ```json
   {
     "publishableKey": "bpk_...",
     "environment": "local",
     "localPort": 8191,
     "sampleBackendUrl": "http://10.0.2.2:4000"
   }
   ```

2. Install the pods and run it, from the repository root:

   ```sh
   (cd example/ios && RCT_USE_RN_DEP=1 RCT_USE_PREBUILT_RNCORE=1 pod install)
   yarn example start
   yarn example ios
   yarn example android
   ```

`environment` picks `production`, `staging`, `uat`, `development` or `local`. `local` talks to
`brudcast-in-app-delivery-service` on port `localPort` (8191) of the development machine:
`10.0.2.2` from the Android emulator, `localhost` from the iOS simulator. Another settings file is
picked with `BRUDCAST_CONFIG=staging yarn example start`, which reads `config/staging.json`;
`config/staging.json.example` is a starting point.

## Sign in like a real app

With `sampleBackendUrl` set, sign-in goes through your backend: it computes the user hash with the
identity secret, the app passes it to `Brudcast.identify`, and **Send me a welcome** on Home has the
backend send the user an in-app message through the Brudcast API. The identity secret and the API
key stay on the backend. Without it, sign-in takes a pasted user hash instead.

The backend needs `POST /login` (`{ "userId", "email" }` in, `{ "externalId", "userHash", "email" }`
out) and `POST /welcome` (`{ "externalId" }`).
[brudcast-sample-backend](https://github.com/brudcast/brudcast-sample-backend) implements both.

## The app

```
Sign in ──▶ Home ┬ Shop ──▶ Product ──▶ Checkout
                 ├ Inbox ──▶ Message
                 └ Account ──▶ Sign out ──▶ Sign in
```

| Where        | What the SDK does                                                                                   |
| ------------ | --------------------------------------------------------------------------------------------------- |
| `index.js`   | `setActionHandler`, then `initialize` with both modules, before the first render                    |
| Sign in      | `Brudcast.identify` with the hash from the backend                                                  |
| Every screen | `Brudcast.screen` as it appears: `SignIn`, `Home`, `Shop`, `Product`, `Checkout`, ...               |
| Home         | The inbox with its unread count from `useInboxUnreadCount`, the native inbox, **Send me a welcome** |
| Product      | Tracks `product_viewed` with `product` and `price`; **Buy now** tracks `checkout_started`           |
| Checkout     | `pauseDisplay` while open and `resumeDisplay` on leaving; **Pay** tracks `order_completed`          |
| Inbox        | `useInbox`: plain rows, paging, pull to refresh, mark read and delete                               |
| Message      | `<BrudcastInboxMessage>`, the entry drawn by the native renderer                                    |
| Account      | The device id, push permission, the actions messages asked for, and `Brudcast.reset` on sign-out    |

A campaign button set to the deep link `brudcast-sample://shop` or `brudcast-sample://checkout`, or
the welcome message's `brudcast-sample://welcome`,
opens that screen through the action handler; anything else gets the SDK's default.

Push needs a Firebase project, so the example does not include React Native Firebase. To try push,
add `@react-native-firebase/app` and `@react-native-firebase/messaging` with your
`google-services.json` and `GoogleService-Info.plist` (both ignored by git), and wire them as the
push package's README shows.

## End-to-end test

`e2e/welcome.yaml` is a [Maestro](https://maestro.mobile.dev) flow over the whole app, against a
real backend: sign in through the sample backend, receive the welcome message over the live
connection, follow its button through the action handler to the shop, open the entry from the
inbox in `<BrudcastInboxMessage>`, check out, and sign out. It needs the local stack running (the
in-app delivery service on 8191 and the sample backend on 4000), `config/local.json` set as above,
Metro, and one booted emulator or simulator with the example installed. Pass a user id that has not
been used, so the inbox starts empty:

```sh
adb reverse tcp:4000 tcp:4000   # Android only: the backend URL is localhost
maestro test -e EXTERNAL_ID=rn-e2e-$(date +%s) e2e/welcome.yaml
```

On Android, `config/local.json` can name `http://localhost:4000` as the backend for both platforms
once `adb reverse` forwards the port; the SDK itself reaches the in-app service on `10.0.2.2`.
