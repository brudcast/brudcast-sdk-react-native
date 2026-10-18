const fs = require('fs');
const path = require('path');
const { getDefaultConfig } = require('@react-native/metro-config');
const { withMetroConfig } = require('react-native-monorepo-config');

const root = path.resolve(__dirname, '..');

/**
 * Picks the example's settings: `config/$BRUDCAST_CONFIG.json` when that variable is set, then
 * `config/local.json`, then the committed `config/default.json`.
 *
 * @returns {string} The settings file.
 */
function exampleConfig() {
  const candidates = [
    process.env.BRUDCAST_CONFIG &&
      path.join(__dirname, 'config', `${process.env.BRUDCAST_CONFIG}.json`),
    path.join(__dirname, 'config', 'local.json'),
  ].filter(Boolean);
  return (
    candidates.find((file) => fs.existsSync(file)) ?? path.join(__dirname, 'config', 'default.json')
  );
}

/**
 * Resolves the SDK packages to their TypeScript sources, so changes show without a build, and
 * `brudcast-example-config` to the settings file.
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = withMetroConfig(getDefaultConfig(__dirname), {
  root,
  dirname: __dirname,
  conditions: ['brudcast-source'],
});

const resolveRequest = config.resolver.resolveRequest;
config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (moduleName === 'brudcast-example-config') {
    return { type: 'sourceFile', filePath: exampleConfig() };
  }
  return resolveRequest
    ? resolveRequest(context, moduleName, platform)
    : context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
