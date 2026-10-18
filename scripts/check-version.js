#!/usr/bin/env node
/**
 * Checks that everything naming the release version agrees: the three package.json files, the
 * TypeScript version constant, the packages' peer constraints on the core, the native version each
 * package pins, the tag the vendored iOS sources came from, the newest released section of each
 * CHANGELOG.md, and the install lines in the READMEs. The packages share one version with the
 * native SDKs they run, so a mismatch anywhere means a release would ship the wrong native code or
 * the wrong docs.
 *
 * Usage: node scripts/check-version.js [expected-version]
 *   With a version, such as the release tag without its v, also checks that everything names it
 *   and that each changelog gives its release date.
 */
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const packages = ['react-native', 'react-native-in-app', 'react-native-push'];

/**
 * Reads a file in the repository.
 *
 * @param {string} file The path relative to the repository.
 * @returns {string} The contents.
 */
function read(file) {
  return fs.readFileSync(path.join(root, file), 'utf8');
}

/**
 * Checks every file and exits non-zero on a mismatch.
 */
function main() {
  const core = JSON.parse(read('packages/react-native/package.json'));
  const given = process.argv[2];
  const expected = given ?? core.version;
  const problems = [];
  const check = (what, actual) => {
    if (actual !== expected)
      problems.push(`${what} names ${actual || 'no version'}, but the release is ${expected}`);
  };

  check(
    'packages/react-native/src/version.ts',
    /brudcastReactNativeVersion = '([^']+)'/.exec(read('packages/react-native/src/version.ts'))?.[1]
  );
  for (const name of packages) {
    const dir = `packages/${name}`;
    const manifest = JSON.parse(read(`${dir}/package.json`));
    check(`${dir}/package.json`, manifest.version);
    check(`The native SDK version in ${dir}/package.json`, manifest.brudcast?.nativeVersion);
    const vendor = JSON.parse(read(`${dir}/ios/vendor/VENDOR.json`));
    check(
      `The vendored iOS sources in ${dir}/ios/vendor/VENDOR.json`,
      vendor.tag?.replace(/^v/, '')
    );
    const changelog = read(`${dir}/CHANGELOG.md`);
    check(
      `The newest released section of ${dir}/CHANGELOG.md`,
      /^## \[(\d[^\]]*)\]/m.exec(changelog)?.[1]
    );
    if (
      given &&
      new RegExp(`^## \\[${expected.replace(/\./g, '\\.')}\\] - Unreleased`, 'm').test(changelog)
    ) {
      problems.push(`${dir}/CHANGELOG.md has no release date for ${expected}`);
    }
    const install = new RegExp(
      `(?:yarn add|npm install) [^\\n]*${manifest.name.replace('/', '\\/')}@(\\d[^\\s]*)`
    ).exec(read(`${dir}/README.md`));
    check(`The install line in ${dir}/README.md`, install?.[1]);
    if (name !== 'react-native') {
      check(
        `The @brudcast/react-native peer constraint in ${dir}/package.json`,
        manifest.peerDependencies?.['@brudcast/react-native']
      );
    }
  }

  if (problems.length > 0) {
    problems.forEach((problem) => console.error(`::error::${problem}`));
    console.error('Bump them together in the release pull request. See RELEASING.md.');
    process.exit(1);
  }
  console.log(`Every package, changelog, native pin and README names ${expected}`);
}

main();
