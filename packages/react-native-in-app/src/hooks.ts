import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { BrudcastLog } from '@brudcast/react-native/module';

import { BrudcastInbox } from './inApp';
import { BrudcastInboxError, markedRead, type BrudcastInAppMessage } from './models';

/** What `useInbox` returns. */
export type BrudcastInboxState = {
  readonly messages: readonly BrudcastInAppMessage[];
  readonly hasMore: boolean;
  readonly isLoading: boolean;
  readonly error: BrudcastInboxError | null;
  readonly unreadCount: number;
  readonly refresh: () => Promise<void>;
  readonly loadMore: () => Promise<void>;
  readonly markRead: (message: BrudcastInAppMessage) => Promise<void>;
  readonly remove: (message: BrudcastInAppMessage) => Promise<void>;
};

type Inbox = typeof BrudcastInbox;

type Loaded = {
  messages: readonly BrudcastInAppMessage[];
  hasMore: boolean;
  isLoading: boolean;
  error: BrudcastInboxError | null;
};

/**
 * Follows the inbox's unread count, for a badge.
 *
 * @param inbox The inbox to follow; the SDK's own by default, a fake in tests.
 * @returns The number of unread entries in the whole inbox.
 */
export function useInboxUnreadCount(inbox: Inbox = BrudcastInbox): number {
  const subscribe = useCallback(
    (notify: () => void) => {
      const subscription = inbox.addUnreadCountListener(notify);
      return () => subscription.remove();
    },
    [inbox]
  );
  return useSyncExternalStore(subscribe, inbox.getUnreadCount);
}

/**
 * Pages through the inbox and follows its unread count, for an inbox screen built in React
 * Native. The first page loads on mount. Call `loadMore` when the list nears its end, from a
 * `FlatList`'s `onEndReached`, and `refresh` on pull to refresh. `markRead` and `remove` update the
 * list at once and tell the service, which the native SDK retries until it is reached.
 *
 * @param options `pageSize` is how many entries each page holds, up to 100, 20 by default.
 *   `inbox` replaces the SDK's inbox in tests.
 * @returns The loaded entries, the loading state and the actions.
 */
export function useInbox(options: { pageSize?: number; inbox?: Inbox } = {}): BrudcastInboxState {
  const inbox = options.inbox ?? BrudcastInbox;
  const pageSize = options.pageSize ?? 20;
  const unreadCount = useInboxUnreadCount(inbox);
  const [state, setState] = useState<Loaded>({
    messages: [],
    hasMore: true,
    isLoading: true,
    error: null,
  });
  const current = useRef(state);
  current.current = state;
  const generation = useRef(0);
  const mounted = useRef(true);

  const update = useCallback((next: (previous: Loaded) => Loaded) => {
    if (!mounted.current) return;
    setState((previous) => {
      const value = next(previous);
      current.current = value;
      return value;
    });
  }, []);

  const load = useCallback(
    async (before: Date | undefined) => {
      const ticket = ++generation.current;
      update((previous) => ({ ...previous, isLoading: true }));
      try {
        const page = await inbox.list({ before, limit: pageSize });
        if (ticket !== generation.current) return;
        update((previous) => {
          const known = new Set(before ? previous.messages.map((entry) => entry.id) : []);
          const fresh = page.messages.filter((entry) => !known.has(entry.id));
          return {
            messages: before ? [...previous.messages, ...fresh] : fresh,
            hasMore: page.hasMore,
            isLoading: false,
            error: null,
          };
        });
      } catch (error) {
        if (ticket !== generation.current) return;
        const failure =
          error instanceof BrudcastInboxError
            ? error
            : new BrudcastInboxError('inbox_failed', String(error));
        BrudcastLog.warning(`The inbox failed to load: ${failure.code}: ${failure.message}`);
        update((previous) => ({ ...previous, isLoading: false, error: failure }));
      }
    },
    [inbox, pageSize, update]
  );

  const refresh = useCallback(() => load(undefined), [load]);

  const loadMore = useCallback(async () => {
    const { isLoading, hasMore, messages } = current.current;
    const last = messages[messages.length - 1];
    if (isLoading || !hasMore || !last) return;
    await load(last.createdAt);
  }, [load]);

  const markRead = useCallback(
    async (message: BrudcastInAppMessage) => {
      const entry = current.current.messages.find((candidate) => candidate.id === message.id);
      if (!entry || entry.isRead) return;
      update((previous) => ({
        ...previous,
        messages: previous.messages.map((candidate) =>
          candidate.id === message.id ? markedRead(candidate) : candidate
        ),
      }));
      await inbox.markRead(message.id);
    },
    [inbox, update]
  );

  const remove = useCallback(
    async (message: BrudcastInAppMessage) => {
      if (!current.current.messages.some((candidate) => candidate.id === message.id)) return;
      update((previous) => ({
        ...previous,
        messages: previous.messages.filter((candidate) => candidate.id !== message.id),
      }));
      await inbox.delete(message.id);
    },
    [inbox, update]
  );

  useEffect(() => {
    mounted.current = true;
    void load(undefined);
    return () => {
      mounted.current = false;
    };
  }, [load]);

  return {
    messages: state.messages,
    hasMore: state.hasMore,
    isLoading: state.isLoading,
    error: state.error,
    unreadCount,
    refresh,
    loadMore,
    markRead,
    remove,
  };
}
