import { codegenNativeComponent, type CodegenTypes, type ViewProps } from 'react-native';

export type ContentHeightChangeEvent = Readonly<{
  height: CodegenTypes.Double;
}>;

export interface NativeProps extends ViewProps {
  messageId: string;
  onContentHeightChange?: CodegenTypes.DirectEventHandler<ContentHeightChangeEvent>;
}

export default codegenNativeComponent<NativeProps>('BrudcastInboxMessageView');
