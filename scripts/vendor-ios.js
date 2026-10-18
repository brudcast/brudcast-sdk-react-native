#!/usr/bin/env node
/**
 * Copies the native iOS SDK's sources, at the version the packages pin, into each package's
 * `ios/vendor` folder, where its podspec compiles them. React Native links iOS libraries through
 * CocoaPods, and the native SDK ships through Swift Package Manager only after 0.1.0.
 *
 * Usage:
 *   node scripts/vendor-ios.js           copy from the release tag
 *   node scripts/vendor-ios.js --check   fail when the vendored files differ from the tag
 *
 * `BRUDCAST_IOS_SDK_PATH` copies from, and checks against, a local checkout instead. When the
 * checkout has the release tag at `HEAD` it counts as the release; otherwise it is recorded as
 * `local:` and `--check` fails, so unreleased native changes cannot ship.
 *
 * The push package compiles `BrudcastNotificationService` into the `BrudcastPush` module, so its
 * `import BrudcastNotificationService` lines are removed. That is the only change to the sources.
 * The extension's own copy sits in `ios/notification-service`, next to the podspec an app adds to
 * its notification service extension target.
 */
const { execFileSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.resolve(__dirname, '..');
const repository = 'https://github.com/brudcast/brudcast-sdk-ios.git';

const targets = [
  { pkg: 'react-native', modules: { Brudcast: 'ios/vendor' } },
  { pkg: 'react-native-in-app', modules: { BrudcastInApp: 'ios/vendor' } },
  {
    pkg: 'react-native-push',
    modules: {
      BrudcastPush: 'ios/vendor',
      BrudcastNotificationService: 'ios/notification-service',
    },
    mergedImports: ['BrudcastNotificationService'],
  },
];

/**
 * Reads the native version every package pins, and fails when they disagree.
 *
 * @returns {string} The version, such as `0.2.0`.
 */
function nativeVersion() {
  const versions = new Set(
    targets.map(({ pkg }) => {
      const manifest = JSON.parse(
        fs.readFileSync(path.join(root, 'packages', pkg, 'package.json'))
      );
      return manifest.brudcast.nativeVersion;
    })
  );
  if (versions.size !== 1) {
    throw new Error(`The packages pin different native versions: ${[...versions].join(', ')}`);
  }
  return [...versions][0];
}

/**
 * Finds the native SDK at a tag: the local checkout in `BRUDCAST_IOS_SDK_PATH`, or a fresh clone
 * in a temporary folder.
 *
 * @param {string} tag The tag, such as `v0.2.0`.
 * @returns {{ dir: string, commit: string, released: boolean }} The checkout, its commit, and
 *   whether it is the tagged release.
 */
function checkout(tag) {
  const local = process.env.BRUDCAST_IOS_SDK_PATH;
  if (local) {
    const dir = path.resolve(local);
    const git = (...args) =>
      execFileSync('git', ['-C', dir, ...args])
        .toString()
        .trim();
    const commit = git('rev-parse', 'HEAD');
    const clean = git('status', '--porcelain', '--', 'Sources') === '';
    const released = clean && git('tag', '--points-at', 'HEAD').split('\n').includes(tag);
    return { dir, commit, released };
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'brudcast-sdk-ios-'));
  execFileSync(
    'git',
    [
      '-c',
      'advice.detachedHead=false',
      'clone',
      '--quiet',
      '--depth',
      '1',
      '--branch',
      tag,
      repository,
      dir,
    ],
    { stdio: 'inherit' }
  );
  const commit = execFileSync('git', ['-C', dir, 'rev-parse', 'HEAD']).toString().trim();
  return { dir, commit, released: true };
}

/**
 * Lists the files under a folder, sorted, relative to it.
 *
 * @param {string} dir The folder.
 * @returns {string[]} The relative paths.
 */
function files(dir) {
  const found = [];
  const walk = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name !== '.DS_Store') found.push(path.relative(dir, full));
    }
  };
  walk(dir);
  return found.sort();
}

/**
 * Reads a source file the way it is vendored.
 *
 * @param {string} file The file.
 * @param {string[]} mergedImports The modules compiled into the same pod, whose imports go.
 * @returns {Buffer} The contents.
 */
function vendored(file, mergedImports) {
  const contents = fs.readFileSync(file);
  if (!file.endsWith('.swift') || mergedImports.length === 0) return contents;
  const lines = contents.toString('utf8').split('\n');
  const kept = lines.filter(
    (line) => !mergedImports.some((name) => line.trim() === `import ${name}`)
  );
  return Buffer.from(kept.join('\n'), 'utf8');
}

/**
 * Builds the vendored tree for every package from a native checkout.
 *
 * @param {string} source The checkout.
 * @returns {Map<string, Buffer>} The contents by path relative to the repository.
 */
function tree(source) {
  const result = new Map();
  for (const { pkg, modules, mergedImports = [] } of targets) {
    for (const [module, folder] of Object.entries(modules)) {
      const from = path.join(source, 'Sources', module);
      if (!fs.existsSync(from)) throw new Error(`${from} does not exist`);
      for (const file of files(from)) {
        const to = path.join('packages', pkg, folder, module, file);
        result.set(to, vendored(path.join(from, file), mergedImports));
      }
    }
  }
  return result;
}

/**
 * Hashes contents.
 *
 * @param {Buffer} contents The contents.
 * @returns {string} The SHA-256, in hex.
 */
function sha256(contents) {
  return crypto.createHash('sha256').update(contents).digest('hex');
}

/**
 * Lists the folders a package's vendored modules go in.
 *
 * @param {{ pkg: string, modules: Record<string, string> }} target The package.
 * @returns {string[]} The module folders, relative to the repository.
 */
function moduleFolders({ pkg, modules }) {
  return Object.entries(modules).map(([module, folder]) =>
    path.join('packages', pkg, folder, module)
  );
}

/**
 * Lists the vendored files on disk.
 *
 * @returns {string[]} Their paths relative to the repository.
 */
function onDisk() {
  return targets.flatMap((target) =>
    moduleFolders(target).flatMap((folder) => {
      const dir = path.join(root, folder);
      return fs.existsSync(dir) ? files(dir).map((file) => path.join(folder, file)) : [];
    })
  );
}

/**
 * Finds a package's vendor manifest.
 *
 * @param {string} pkg The package folder name.
 * @returns {string} The manifest's path.
 */
function manifestPath(pkg) {
  return path.join(root, 'packages', pkg, 'ios', 'vendor', 'VENDOR.json');
}

/**
 * Vendors the sources, or checks them with `--check`.
 */
function main() {
  const version = nativeVersion();
  const tag = `v${version}`;
  const check = process.argv.includes('--check');

  if (check) {
    const { dir, commit, released } = checkout(tag);
    if (!released) {
      console.error(`${dir} is not a clean checkout of brudcast-sdk-ios ${tag}.`);
      process.exit(1);
    }
    const expected = tree(dir);
    const problems = [];
    for (const [file, contents] of expected) {
      const full = path.join(root, file);
      if (!fs.existsSync(full)) problems.push(`missing ${file}`);
      else if (sha256(fs.readFileSync(full)) !== sha256(contents)) problems.push(`differs ${file}`);
    }
    for (const file of onDisk()) {
      if (!expected.has(file)) problems.push(`not in ${tag}: ${file}`);
    }
    for (const { pkg } of targets) {
      const manifest = manifestPath(pkg);
      const recorded = fs.existsSync(manifest) ? JSON.parse(fs.readFileSync(manifest)) : {};
      if (recorded.tag !== tag || recorded.commit !== commit) {
        problems.push(`${manifest} does not record ${tag} at ${commit}`);
      }
    }
    if (problems.length > 0) {
      console.error(`The vendored iOS sources do not match brudcast-sdk-ios ${tag}:`);
      problems.forEach((problem) => console.error(`  ${problem}`));
      console.error('Run `yarn vendor:ios` and commit the result.');
      process.exit(1);
    }
    console.log(`The vendored iOS sources match brudcast-sdk-ios ${tag} (${commit}).`);
    return;
  }

  const source = checkout(tag);
  const contents = tree(source.dir);
  for (const target of targets) {
    moduleFolders(target).forEach((folder) =>
      fs.rmSync(path.join(root, folder), { recursive: true, force: true })
    );
  }
  for (const [file, data] of contents) {
    const full = path.join(root, file);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, data);
  }
  for (const target of targets) {
    const base = path.join('packages', target.pkg);
    const folders = moduleFolders(target);
    const manifest = {
      repository,
      tag: source.released ? tag : `local:${tag}`,
      commit: source.commit,
      modules: target.modules,
      files: Object.fromEntries(
        [...contents]
          .filter(([file]) => folders.some((folder) => file.startsWith(`${folder}${path.sep}`)))
          .map(([file, data]) => [path.relative(base, file), sha256(data)])
      ),
    };
    fs.mkdirSync(path.dirname(manifestPath(target.pkg)), { recursive: true });
    fs.writeFileSync(manifestPath(target.pkg), `${JSON.stringify(manifest, null, 2)}\n`);
  }
  console.log(
    `Vendored ${contents.size} files from brudcast-sdk-ios ${source.released ? tag : `${source.dir} (not ${tag})`}.`
  );
}

main();
