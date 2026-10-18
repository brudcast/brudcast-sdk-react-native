const fs = require('fs');
const path = require('path');

const plugins = loadConfigPlugins();
const {
  createRunOncePlugin,
  withDangerousMod,
  withEntitlementsPlist,
  withInfoPlist,
  withXcodeProject,
} = plugins;

const pkg = require('../package.json');

const extensionName = 'BrudcastNotificationExtension';
const podName = 'BrudcastNotificationService';
const extensionFiles = {
  source: 'NotificationService.swift',
  plist: `${extensionName}-Info.plist`,
  entitlements: `${extensionName}.entitlements`,
};

/**
 * Loads Expo's config plugin helpers, from `expo` in an Expo app and from `@expo/config-plugins`
 * otherwise.
 *
 * @returns {typeof import('@expo/config-plugins')} The helpers.
 */
function loadConfigPlugins() {
  try {
    return require('expo/config-plugins');
  } catch {
    return require('@expo/config-plugins');
  }
}

/**
 * Sets up Brudcast push in an Expo app's native projects, so `expo prebuild` needs no hand edits:
 * the App Group shared with the notification service extension, the push entitlement, and the
 * extension itself, a `BrudcastNotificationExtension` target, which attaches notification images and records `push_received`. Taps are
 * recorded by the package's notification center proxy with no setup.
 *
 * @param {import('@expo/config-plugins').ExpoConfig} config The app config.
 * @param {{
 *   appGroupIdentifier?: string,
 *   notificationServiceExtension?: boolean,
 *   automaticNotificationDelegate?: boolean,
 *   apsEnvironment?: 'development' | 'production',
 * }} [props] The App Group, `group.<bundle id>.brudcast` by default; whether to add the extension,
 *   true by default; whether the proxy installs itself, true by default; and the APNs
 *   environment, `development` by default.
 * @returns {import('@expo/config-plugins').ExpoConfig} The config with the mods added.
 */
function withBrudcastPush(config, props = {}) {
  const bundleIdentifier = config.ios?.bundleIdentifier;
  if (!bundleIdentifier) {
    throw new Error('@brudcast/react-native-push needs ios.bundleIdentifier in the app config.');
  }
  const options = {
    appGroupIdentifier: props.appGroupIdentifier ?? `group.${bundleIdentifier}.brudcast`,
    notificationServiceExtension: props.notificationServiceExtension ?? true,
    automaticNotificationDelegate: props.automaticNotificationDelegate ?? true,
    apsEnvironment: props.apsEnvironment ?? 'development',
    bundleIdentifier,
  };

  config = withAppEntitlements(config, options);
  config = withAppInfoPlist(config, options);
  if (options.notificationServiceExtension) {
    config = withExtensionFiles(config, options);
    config = withExtensionTarget(config, options);
    config = withExtensionPod(config);
    config = withExtensionCredentials(config, options);
  }
  return config;
}

/**
 * Adds the push entitlement and the App Group to the app.
 *
 * @param {object} config The app config.
 * @param {object} options The resolved options.
 * @returns {object} The config.
 */
function withAppEntitlements(config, options) {
  return withEntitlementsPlist(config, (mod) => {
    mod.modResults['aps-environment'] = mod.modResults['aps-environment'] ?? options.apsEnvironment;
    const groups = new Set(mod.modResults['com.apple.security.application-groups'] ?? []);
    groups.add(options.appGroupIdentifier);
    mod.modResults['com.apple.security.application-groups'] = [...groups];
    return mod;
  });
}

/**
 * Tells the SDK the App Group, so `Brudcast.initialize` needs no `appGroupIdentifier`, and whether
 * the notification center proxy installs itself.
 *
 * @param {object} config The app config.
 * @param {object} options The resolved options.
 * @returns {object} The config.
 */
function withAppInfoPlist(config, options) {
  return withInfoPlist(config, (mod) => {
    mod.modResults.BrudcastAppGroupIdentifier = options.appGroupIdentifier;
    mod.modResults.BrudcastAutomaticNotificationDelegate = options.automaticNotificationDelegate;
    return mod;
  });
}

/**
 * Writes the extension's source, Info.plist and entitlements into `ios/BrudcastNotificationExtension`.
 *
 * @param {object} config The app config.
 * @param {object} options The resolved options.
 * @returns {object} The config.
 */
function withExtensionFiles(config, options) {
  return withDangerousMod(config, [
    'ios',
    async (mod) => {
      const dir = path.join(mod.modRequest.platformProjectRoot, extensionName);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(
        path.join(dir, extensionFiles.source),
        extensionSource(options.appGroupIdentifier)
      );
      fs.writeFileSync(path.join(dir, extensionFiles.plist), extensionInfoPlist());
      fs.writeFileSync(
        path.join(dir, extensionFiles.entitlements),
        extensionEntitlements(options.appGroupIdentifier)
      );
      return mod;
    },
  ]);
}

/**
 * Adds the extension target to the Xcode project, embedded in the app.
 *
 * @param {object} config The app config.
 * @param {object} options The resolved options.
 * @returns {object} The config.
 */
function withExtensionTarget(config, options) {
  return withXcodeProject(config, (mod) => {
    const project = mod.modResults;
    if (project.pbxTargetByName(extensionName)) return mod;

    const objects = project.hash.project.objects;
    objects.PBXTargetDependency = objects.PBXTargetDependency ?? {};
    objects.PBXContainerItemProxy = objects.PBXContainerItemProxy ?? {};

    const group = project.addPbxGroup(Object.values(extensionFiles), extensionName, extensionName);
    const mainGroup = project.getFirstProject().firstProject.mainGroup;
    project.addToPbxGroup(group.uuid, mainGroup);

    const target = project.addTarget(
      extensionName,
      'app_extension',
      extensionName,
      `${options.bundleIdentifier}.${extensionName}`
    );
    project.addBuildPhase([extensionFiles.source], 'PBXSourcesBuildPhase', 'Sources', target.uuid);
    project.addBuildPhase([], 'PBXResourcesBuildPhase', 'Resources', target.uuid);
    project.addBuildPhase([], 'PBXFrameworksBuildPhase', 'Frameworks', target.uuid);

    const appSettings = appBuildSettings(project);
    const configurations = project.pbxXCBuildConfigurationSection();
    for (const key of Object.keys(configurations)) {
      const settings = configurations[key].buildSettings;
      if (!settings || settings.PRODUCT_NAME !== `"${extensionName}"`) continue;
      settings.CODE_SIGN_ENTITLEMENTS = `${extensionName}/${extensionFiles.entitlements}`;
      settings.CODE_SIGN_STYLE = 'Automatic';
      settings.CURRENT_PROJECT_VERSION = appSettings.CURRENT_PROJECT_VERSION ?? '1';
      settings.MARKETING_VERSION = appSettings.MARKETING_VERSION ?? '1.0';
      settings.IPHONEOS_DEPLOYMENT_TARGET = appSettings.IPHONEOS_DEPLOYMENT_TARGET ?? '15.1';
      settings.SWIFT_VERSION = '5.0';
      settings.TARGETED_DEVICE_FAMILY = appSettings.TARGETED_DEVICE_FAMILY ?? '"1,2"';
      if (appSettings.DEVELOPMENT_TEAM) settings.DEVELOPMENT_TEAM = appSettings.DEVELOPMENT_TEAM;
    }
    return mod;
  });
}

/**
 * Adds the extension's pod to the Podfile. The target is not named after the pod: a target named
 * `BrudcastNotificationService` would be a module of that name, and its
 * `import BrudcastNotificationService` would import itself.
 *
 * @param {object} config The app config.
 * @returns {object} The config.
 */
function withExtensionPod(config) {
  return withDangerousMod(config, [
    'ios',
    async (mod) => {
      const podfile = path.join(mod.modRequest.platformProjectRoot, 'Podfile');
      const contents = fs.readFileSync(podfile, 'utf8');
      if (contents.includes(`target '${extensionName}'`)) return mod;
      const podspecDir = path.join(
        path.dirname(require.resolve(`${pkg.name}/package.json`)),
        'ios',
        'notification-service'
      );
      const relative = path.relative(mod.modRequest.platformProjectRoot, podspecDir);
      fs.writeFileSync(
        podfile,
        `${contents.trimEnd()}\n\ntarget '${extensionName}' do\n  pod '${podName}', :path => '${relative}'\nend\n`
      );
      return mod;
    },
  ]);
}

/**
 * Tells EAS Build to sign the extension along with the app.
 *
 * @param {object} config The app config.
 * @param {object} options The resolved options.
 * @returns {object} The config.
 */
function withExtensionCredentials(config, options) {
  config.extra = config.extra ?? {};
  config.extra.eas = config.extra.eas ?? {};
  config.extra.eas.build = config.extra.eas.build ?? {};
  config.extra.eas.build.experimental = config.extra.eas.build.experimental ?? {};
  const ios = (config.extra.eas.build.experimental.ios =
    config.extra.eas.build.experimental.ios ?? {});
  ios.appExtensions = ios.appExtensions ?? [];
  if (!ios.appExtensions.some((extension) => extension.targetName === extensionName)) {
    ios.appExtensions.push({
      targetName: extensionName,
      bundleIdentifier: `${options.bundleIdentifier}.${extensionName}`,
      entitlements: { 'com.apple.security.application-groups': [options.appGroupIdentifier] },
    });
  }
  return config;
}

/**
 * Reads the app target's build settings, which the extension copies.
 *
 * @param {object} project The Xcode project.
 * @returns {Record<string, string>} The settings of the app's first build configuration.
 */
function appBuildSettings(project) {
  const target = project.getFirstTarget().firstTarget;
  const list = project.pbxXCConfigurationList()[target.buildConfigurationList];
  const first = list?.buildConfigurations?.[0]?.value;
  return (first && project.pbxXCBuildConfigurationSection()[first]?.buildSettings) ?? {};
}

/**
 * Writes the extension's principal class.
 *
 * @param {string} appGroupIdentifier The App Group shared with the app.
 * @returns {string} The Swift source.
 */
function extensionSource(appGroupIdentifier) {
  return `import BrudcastNotificationService

/// Generated by @brudcast/react-native-push. Attaches notification images and records
/// push_received for the app to send.
final class NotificationService: BrudcastNotificationServiceExtension {
    override var appGroupIdentifier: String? {
        "${appGroupIdentifier}"
    }
}
`;
}

/**
 * Writes the extension's Info.plist.
 *
 * @returns {string} The plist.
 */
function extensionInfoPlist() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>$(DEVELOPMENT_LANGUAGE)</string>
  <key>CFBundleDisplayName</key>
  <string>${extensionName}</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.usernotifications.service</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).NotificationService</string>
  </dict>
</dict>
</plist>
`;
}

/**
 * Writes the extension's entitlements.
 *
 * @param {string} appGroupIdentifier The App Group shared with the app.
 * @returns {string} The plist.
 */
function extensionEntitlements(appGroupIdentifier) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>${appGroupIdentifier}</string>
  </array>
</dict>
</plist>
`;
}

module.exports = createRunOncePlugin(withBrudcastPush, pkg.name, pkg.version);
module.exports.extensionName = extensionName;
