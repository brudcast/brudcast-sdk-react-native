import { act, renderHook, waitFor } from '@testing-library/react-native';

jest.mock('../../../react-native/src/specs/NativeBrudcast', () => ({
  __esModule: true,
  default: { onActionRequest: () => ({ remove() {} }) },
}));

jest.mock('../specs/NativeBrudcastInApp', () => ({
  __esModule: true,
  default: {},
}));

jest.mock('../specs/BrudcastInboxMessageNativeComponent', () => ({
  __esModule: true,
  default: 'BrudcastInboxMessageView',
}));

import {
  BrudcastInbox,
  BrudcastInboxError,
  useInbox,
  useInboxUnreadCount,
  type BrudcastInAppMessage,
  type BrudcastInboxPage,
} from '../index';

/**
 * Creates an inbox entry.
 *
 * @param id The entry's id.
 * @param minutes Its age in minutes, which orders the inbox.
 * @returns The entry.
 */
function entry(id: string, minutes: number): BrudcastInAppMessage {
  return {
    id,
    format: 'inboxOnly',
    isTest: false,
    title: id,
    preview: '',
    isRead: false,
    createdAt: new Date(Date.UTC(2026, 9, 18, 12, 0) - minutes * 60_000),
    design: '{}',
  };
}

/**
 * Creates a fake inbox that answers `list` from a queue of pages.
 *
 * @param pages The pages, or errors, `list` answers with in order.
 * @returns The fake, with its mocks.
 */
function fakeInbox(pages: (BrudcastInboxPage | Error)[]) {
  let unread = 0;
  const listeners = new Set<(count: number) => void>();
  const inbox = {
    ...BrudcastInbox,
    list: jest.fn(async () => {
      const next = pages.shift();
      if (!next) throw new Error('no page queued');
      if (next instanceof Error) throw next;
      return next;
    }),
    markRead: jest.fn(async () => {}),
    delete: jest.fn(async () => {}),
    present: jest.fn(async () => {}),
    getUnreadCount: () => unread,
    addUnreadCountListener: (listener: (count: number) => void) => {
      listeners.add(listener);
      return { remove: () => listeners.delete(listener) };
    },
  };
  const setUnread = (count: number) => {
    unread = count;
    listeners.forEach((listener) => listener(count));
  };
  return { inbox: inbox as typeof BrudcastInbox, mocks: inbox, setUnread };
}

it('follows the unread count', () => {
  const { inbox, setUnread } = fakeInbox([]);
  const { result } = renderHook(() => useInboxUnreadCount(inbox));
  expect(result.current).toBe(0);

  act(() => setUnread(7));

  expect(result.current).toBe(7);
});

it('loads the first page on mount', async () => {
  const { inbox, mocks } = fakeInbox([
    { messages: [entry('a', 1), entry('b', 2)], unreadCount: 2, hasMore: true },
  ]);

  const { result } = renderHook(() => useInbox({ inbox, pageSize: 2 }));
  expect(result.current.isLoading).toBe(true);

  await waitFor(() => expect(result.current.isLoading).toBe(false));
  expect(result.current.messages.map((message) => message.id)).toEqual(['a', 'b']);
  expect(result.current.hasMore).toBe(true);
  expect(mocks.list).toHaveBeenCalledWith({ before: undefined, limit: 2 });
});

it('loads older pages from the last entry and skips ones already shown', async () => {
  const { inbox, mocks } = fakeInbox([
    { messages: [entry('a', 1), entry('b', 2)], unreadCount: 3, hasMore: true },
    { messages: [entry('b', 2), entry('c', 3)], unreadCount: 3, hasMore: false },
  ]);
  const { result } = renderHook(() => useInbox({ inbox, pageSize: 2 }));
  await waitFor(() => expect(result.current.isLoading).toBe(false));

  await act(() => result.current.loadMore());

  expect(mocks.list).toHaveBeenLastCalledWith({ before: entry('b', 2).createdAt, limit: 2 });
  expect(result.current.messages.map((message) => message.id)).toEqual(['a', 'b', 'c']);
  expect(result.current.hasMore).toBe(false);

  await act(() => result.current.loadMore());
  expect(mocks.list).toHaveBeenCalledTimes(2);
});

it('keeps the entries and reports the error when a page fails', async () => {
  const { inbox } = fakeInbox([
    { messages: [entry('a', 1)], unreadCount: 1, hasMore: true },
    new BrudcastInboxError('network', 'offline'),
  ]);
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  const { result } = renderHook(() => useInbox({ inbox }));
  await waitFor(() => expect(result.current.isLoading).toBe(false));

  await act(() => result.current.loadMore());

  expect(result.current.error).toMatchObject({ code: 'network' });
  expect(result.current.messages.map((message) => message.id)).toEqual(['a']);
});

it('replaces the list on refresh', async () => {
  const { inbox } = fakeInbox([
    { messages: [entry('a', 1)], unreadCount: 1, hasMore: false },
    { messages: [entry('z', 0), entry('a', 1)], unreadCount: 2, hasMore: false },
  ]);
  const { result } = renderHook(() => useInbox({ inbox }));
  await waitFor(() => expect(result.current.isLoading).toBe(false));

  await act(() => result.current.refresh());

  expect(result.current.messages.map((message) => message.id)).toEqual(['z', 'a']);
});

it('marks read and removes at once, and tells the service', async () => {
  const { inbox, mocks } = fakeInbox([
    { messages: [entry('a', 1), entry('b', 2)], unreadCount: 2, hasMore: false },
  ]);
  const { result } = renderHook(() => useInbox({ inbox }));
  await waitFor(() => expect(result.current.isLoading).toBe(false));
  const [first, second] = result.current.messages;

  await act(() => result.current.markRead(first!));
  await act(() => result.current.markRead(result.current.messages[0]!));
  await act(() => result.current.remove(second!));

  expect(result.current.messages).toHaveLength(1);
  expect(result.current.messages[0]).toMatchObject({ id: 'a', isRead: true });
  expect(mocks.markRead).toHaveBeenCalledTimes(1);
  expect(mocks.delete).toHaveBeenCalledWith('b');
});
