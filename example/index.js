import { AppRegistry } from 'react-native';
import { Brudcast } from '@brudcast/react-native';
import { BrudcastInApp } from '@brudcast/react-native-in-app';
import { BrudcastPush } from '@brudcast/react-native-push';

import { handleAction } from './src/actions';
import { App } from './src/App';
import { SampleConfig } from './src/config';
import { accent } from './src/ui';
import { name as appName } from './app.json';

/**
 * Starts the SDK the way an app should: the action handler first, so a push tap that launched the
 * app reaches it, then `initialize` once, before the first render.
 */
function startBrudcast() {
  void Brudcast.setActionHandler(handleAction);
  if (!SampleConfig.publishableKey) {
    console.warn('Set publishableKey in example/config/local.json to start the SDK');
    return;
  }
  void Brudcast.initialize(SampleConfig.publishableKey, {
    environment: SampleConfig.environment,
    logLevel: 'debug',
    accentColor: accent,
    modules: [BrudcastInApp.module, BrudcastPush.module],
  });
}

startBrudcast();
AppRegistry.registerComponent(appName, () => App);
