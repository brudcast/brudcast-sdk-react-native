const pkg = require('./package.json');

/**
 * The core package needs no native setup in an Expo app, so its config plugin changes nothing. It
 * exists so `plugins: ['@brudcast/react-native']` is valid; push setup is in
 * `@brudcast/react-native-push`'s plugin.
 *
 * @param {object} config The app config.
 * @returns {object} The config, unchanged.
 */
function withBrudcast(config) {
  return config;
}

let createRunOncePlugin;
try {
  ({ createRunOncePlugin } = require('expo/config-plugins'));
} catch {
  ({ createRunOncePlugin } = require('@expo/config-plugins'));
}

module.exports = createRunOncePlugin(withBrudcast, pkg.name, pkg.version);
