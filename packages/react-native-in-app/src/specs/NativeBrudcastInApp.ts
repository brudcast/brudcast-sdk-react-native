import { TurboModuleRegistry, type CodegenTypes, type TurboModule } from 'react-native';

export type NativeInAppMessage = {
  id: string;
  campaignId?: string;
  format: string;
  isTest: boolean;
  title: string;
  preview: string;
  thumbnailUrl?: string;
  isRead: boolean;
  createdAtMillis: CodegenTypes.Double;
  design: string;
};

export type NativeInboxPage = {
  messages: NativeInAppMessage[];
  unreadCount: CodegenTypes.Int32;
  hasMore: boolean;
};

export type NativeMessageRequest = {
  requestId: string;
  message: NativeInAppMessage;
};

export interface Spec extends TurboModule {
  pauseDisplay(): void;
  resumeDisplay(): void;
  sync(): void;
  setMessageHandlerEnabled(enabled: boolean): void;
  resolveMessage(requestId: string, decision: string): void;
  reportImpression(messageId: string): void;
  reportClick(messageId: string, buttonId: string): void;
  reportDismiss(messageId: string): void;
  presentInbox(title: string): void;
  listInbox(
    beforeMillis: CodegenTypes.Double | null,
    limit: CodegenTypes.Int32
  ): Promise<NativeInboxPage>;
  markRead(messageId: string): void;
  deleteMessage(messageId: string): void;
  getUnreadCount(): Promise<CodegenTypes.Int32>;

  readonly onMessageRequest: CodegenTypes.EventEmitter<NativeMessageRequest>;
  readonly onUnreadCountChange: CodegenTypes.EventEmitter<number>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('BrudcastInApp');
