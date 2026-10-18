import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  View,
} from 'react-native';
import {
  BrudcastInboxMessage,
  useInbox,
  type BrudcastInAppMessage,
} from '@brudcast/react-native-in-app';

import { useNavigation } from '../navigation';
import { Body, Button, Screen, accent, useColors } from '../ui';

/**
 * The inbox built in React Native with `useInbox`: plain rows from each entry's title and preview,
 * paging at the end of the list, pull to refresh, and a delete button on each row.
 *
 * @returns The screen.
 */
export function InboxScreen() {
  const navigation = useNavigation();
  const colors = useColors();
  const inbox = useInbox({ pageSize: 20 });

  const row = ({ item }: { item: BrudcastInAppMessage }) => (
    <Pressable
      onPress={() => {
        void inbox.markRead(item);
        navigation.push({ name: 'InboxMessage', message: item });
      }}
      style={[styles.row, { borderColor: colors.border }]}
      testID={`entry-${item.id}`}
    >
      <View style={[styles.dot, { backgroundColor: item.isRead ? 'transparent' : accent }]} />
      <View style={styles.texts}>
        <Body>{item.title}</Body>
        <Body muted>{item.preview}</Body>
      </View>
      <Button kind="plain" title="Delete" onPress={() => void inbox.remove(item)} />
    </Pressable>
  );

  return (
    <Screen title={inbox.unreadCount > 0 ? `Inbox (${inbox.unreadCount})` : 'Inbox'} scroll={false}>
      {inbox.error ? <Body muted>The inbox did not load: {inbox.error.message}</Body> : null}
      <FlatList
        data={inbox.messages}
        keyExtractor={(item) => item.id}
        renderItem={row}
        onEndReached={() => void inbox.loadMore()}
        refreshControl={
          <RefreshControl
            refreshing={inbox.isLoading && inbox.messages.length === 0}
            onRefresh={inbox.refresh}
          />
        }
        ListEmptyComponent={inbox.isLoading ? undefined : <Body muted>Nothing here yet.</Body>}
        ListFooterComponent={
          inbox.isLoading && inbox.messages.length > 0 ? <ActivityIndicator /> : undefined
        }
      />
    </Screen>
  );
}

/**
 * One entry, drawn by the native renderer with its buttons working.
 *
 * @param props The entry.
 * @returns The screen.
 */
export function InboxMessageScreen(props: { message: BrudcastInAppMessage }) {
  return (
    <Screen title={props.message.title}>
      <BrudcastInboxMessage message={props.message} testID="inboxMessage" />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: 12,
  },
  dot: { width: 8, height: 8, borderRadius: 4 },
  texts: { flex: 1 },
});
