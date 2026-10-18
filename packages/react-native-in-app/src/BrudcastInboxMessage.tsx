import { useCallback, useState } from 'react';
import type { NativeSyntheticEvent, StyleProp, ViewStyle } from 'react-native';

import type { BrudcastInAppMessage } from './models';
import BrudcastInboxMessageView, {
  type ContentHeightChangeEvent,
} from './specs/BrudcastInboxMessageNativeComponent';

/** The props of `BrudcastInboxMessage`. */
export type BrudcastInboxMessageProps = {
  readonly message: BrudcastInAppMessage;
  readonly expand?: boolean;
  readonly style?: StyleProp<ViewStyle>;
  readonly onContentHeightChange?: (height: number) => void;
  readonly testID?: string;
};

/**
 * Draws an inbox entry with the native renderer, exactly as the SDK draws messages, with its
 * buttons working. It takes the width it is given and sizes its height to the design, so it can
 * sit in a scroll view; pass `expand` to fill the space given instead, scrolling inside when the
 * design is taller. A design this SDK version cannot draw shows nothing.
 *
 * The message must come from `BrudcastInbox.list` or `useInbox`, which hand it to the renderer.
 * Each one runs the renderer, so prefer plain rows built from `title`, `preview` and
 * `thumbnailUrl` for a long list, and this for a detail screen.
 *
 * @param props The message, whether to fill the space given, and an optional style and height
 *   callback.
 * @returns The view.
 */
export function BrudcastInboxMessage(props: BrudcastInboxMessageProps) {
  const { message, expand = false, style, onContentHeightChange, testID } = props;
  const [height, setHeight] = useState<number | null>(null);
  const changed = useCallback(
    (event: NativeSyntheticEvent<ContentHeightChangeEvent>) => {
      const next = event.nativeEvent.height;
      setHeight(next);
      onContentHeightChange?.(next);
    },
    [onContentHeightChange]
  );
  return (
    <BrudcastInboxMessageView
      messageId={message.id}
      onContentHeightChange={changed}
      style={[expand ? { flex: 1 } : { height: height ?? 1 }, style]}
      testID={testID}
    />
  );
}
