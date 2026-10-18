import settings from 'brudcast-example-config';
import { localEnvironment, type BrudcastEnvironment } from '@brudcast/react-native';

/** The example's settings, from `config/local.json` or the file `BRUDCAST_CONFIG` names. */
export const SampleConfig = {
  /** The publishable key of an in-app application in the dashboard. */
  publishableKey: settings.publishableKey ?? '',

  /** The app's own backend, which signs users in. Empty to sign in with a pasted user hash. */
  sampleBackendUrl: settings.sampleBackendUrl ?? '',

  /** The environment `environment` names: `production`, `staging`, `uat`, `development` or `local`. */
  environment: environment(settings.environment, settings.localPort),
};

/**
 * Reads the environment setting.
 *
 * @param name The environment's name.
 * @param port The port of a local in-app delivery service.
 * @returns The environment.
 */
function environment(name: string | undefined, port: number | undefined): BrudcastEnvironment {
  switch (name?.toLowerCase()) {
    case 'staging':
    case 'uat':
    case 'development':
      return name.toLowerCase() as BrudcastEnvironment;
    case 'local':
      return localEnvironment({ port: port ?? 8191 });
    default:
      return 'production';
  }
}
