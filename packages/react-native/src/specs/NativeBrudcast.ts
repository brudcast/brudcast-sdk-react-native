import { TurboModuleRegistry, type CodegenTypes, type TurboModule } from 'react-native';

export type NativeEnvironment = {
  kind: string;
  androidHost?: string;
  port?: CodegenTypes.Int32;
  baseUrl?: string;
};

export type NativeOptions = {
  environment: NativeEnvironment;
  logLevel: string;
  appearance: string;
  accentColor?: CodegenTypes.Double;
  modules: string[];
  appGroupIdentifier?: string;
  wrapperVersion: string;
};

export type NativeTraits = {
  email?: string;
  phone?: string;
  firstName?: string;
  lastName?: string;
  language?: string;
  timezone?: string;
};

export type NativeActionRequest = {
  requestId: string;
  kind: string;
  value: string;
  opensInApp: boolean;
  source: string;
  messageId: string;
  buttonId?: string;
  verified: boolean;
};

export interface Spec extends TurboModule {
  initialize(publishableKey: string, options: NativeOptions): void;
  identify(externalId: string, userHash: string | null, traits: NativeTraits): void;
  reset(): void;
  track(name: string, properties: CodegenTypes.UnsafeObject): void;
  screen(name: string, properties: CodegenTypes.UnsafeObject): void;
  setOptedOut(optedOut: boolean): void;
  setTrackingEnabled(enabled: boolean): void;
  flush(): void;
  setActionHandlerEnabled(enabled: boolean): void;
  resolveAction(requestId: string, result: string): void;
  getDeviceId(): Promise<string | null>;

  readonly onActionRequest: CodegenTypes.EventEmitter<NativeActionRequest>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Brudcast');
