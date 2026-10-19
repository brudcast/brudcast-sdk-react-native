# Releasing

The three packages are published to [npm](https://www.npmjs.com) together, with the same version
as the native SDKs they run. Pushing a `v<version>` tag runs `.github/workflows/release.yml`.

## Order

The packages pin the native SDKs exactly, so the native release comes first:

1. Release `brudcast-sdk-android` and `brudcast-sdk-ios` at the version, as their `RELEASING.md`
   files describe, and wait until the artifacts are on Maven Central and the tag is on GitHub.
2. Release these packages.

## Release

1. On a `docs/release-<version>` branch, set the version in:
   - `version` and `brudcast.nativeVersion` in each package's `package.json`, and the
     `@brudcast/react-native` peer constraint in the in-app and push packages;
   - `brudcastReactNativeVersion` in `packages/react-native/src/version.ts`;
   - the install lines in each package's `README.md`;
   - each `CHANGELOG.md`: move `Unreleased` under the version with today's date.

   Then run `yarn vendor:ios`, which copies the native iOS sources at the new tag into the packages
   and records it in each `ios/vendor/VENDOR.json`. Commit everything as `docs: release <version>`
   and merge to `main`. CI runs `yarn check:version` and `yarn check:vendor`, which fail until all
   of them agree.

2. Tag `main` with `v<version>`, such as `v0.2.0`, and push the tag:

   ```sh
   git switch main && git pull
   git tag v0.2.0 && git push origin v0.2.0
   ```

3. The workflow runs, in order:
   - **Verify**: the tag matches the version, the tagged commit is on `main`, every file names the
     version with a dated changelog, and the vendored iOS sources match the native tag;
   - **CI**: the whole of `ci.yml`, the JavaScript checks and the Android and iOS example builds;
   - **Pack**: builds and packs the three packages once, so the publish ships exactly what was
     checked;
   - **Publish to npm**: waits for approval in the `npm` environment, then publishes
     `@brudcast/react-native`, then `@brudcast/react-native-in-app` and
     `@brudcast/react-native-push`, with provenance. A version with a `-`, such as `0.3.0-beta.1`,
     goes to the `next` dist-tag instead of `latest`;
   - **Create the GitHub release**: titled with the version, with each package's changelog section
     as the notes, and marked as a prerelease for a `next` version.

To check a release without publishing, run the workflow from the **Actions** tab with **dry run**
checked. It runs everything up to the pack, and keeps the packed `.tgz` files as an artifact.

A failed publish can be rerun from the Actions tab: packages already on npm at the version are
skipped. Versions on npm cannot be replaced. A mistake needs a new version, and `npm deprecate` on
the bad one.

## Vendored iOS sources

React Native links iOS libraries through CocoaPods, and the native iOS SDK ships through Swift
Package Manager only after 0.1.0. Each package's podspec therefore compiles a copy of the native
sources, kept in `ios/vendor` (and `ios/notification-service` for the extension). Never edit them
here: change `brudcast-sdk-ios`, release it, and vendor again. The one change the script makes is
removing `import BrudcastNotificationService` from the push sources, which compile into the same
module.

`BRUDCAST_IOS_SDK_PATH=/path/to/brudcast-sdk-ios yarn vendor:ios` vendors from a local checkout for
native work in progress. The manifest then records `local:` and `yarn check:vendor` fails, so it
cannot be released by mistake.

## One-time setup

1. On npm, create the `brudcast` organization if it does not exist, so the `@brudcast` scope is
   ours.
2. In the repository settings, create the `npm` environment with required reviewers, and allow it
   to deploy from `v*` tags only.
3. npm sets up trusted publishing only on a package that already exists, so the first release
   publishes with a token:
   - on npm, create a granular access token with read and write access to the `@brudcast` scope
     and a short expiry;
   - add it to the `npm` environment as the secret `NPM_TOKEN`;
   - release as above.
4. After the first release, on npm, for each package: **Settings** → **Trusted publishing** → add
   GitHub Actions for `brudcast/brudcast-sdk-react-native` with the workflow `release.yml` and the
   environment `npm`. Then delete the `NPM_TOKEN` secret and revoke the token. From then on the
   workflow publishes with GitHub's OIDC token, so there is no stored credential.

## Conventions

- Commits follow [Conventional Commits](https://www.conventionalcommits.org). A change that breaks
  the public API gets a `!` after its type, such as `feat!:`, before 1.0 too.
- Each `CHANGELOG.md` lists what an app using that package gets. How the packages are built and
  released belongs in the pull request and in this file.
