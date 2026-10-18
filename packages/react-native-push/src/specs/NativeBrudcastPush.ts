import { TurboModuleRegistry, type CodegenTypes, type TurboModule } from 'react-native';

export type NativePushNotification = {
  messageId: string;
  campaignId?: string;
  applicationId?: string;
  title?: string;
  body?: string;
  imageUrl?: string;
  clickUrl?: string;
  data: CodegenTypes.UnsafeObject;
};

export type NativeNotificationRequest = {
  requestId: string;
  notification: NativePushNotification;
};

export interface Spec extends TurboModule {
  setToken(token: string): void;
  requestPermission(provisional: boolean): Promise<string>;
  getPermissionStatus(): Promise<string>;
  setNotificationHandlerEnabled(enabled: boolean): void;
  resolveNotification(requestId: string, decision: string): void;
  handleForegroundMessage(
    data: CodegenTypes.UnsafeObject,
    title: string | null,
    body: string | null,
    imageUrl: string | null
  ): Promise<boolean>;

  readonly onNotificationRequest: CodegenTypes.EventEmitter<NativeNotificationRequest>;
  readonly onPermissionChange: CodegenTypes.EventEmitter<string>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('BrudcastPush');
