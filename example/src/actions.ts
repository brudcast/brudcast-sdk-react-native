import type { BrudcastAction, BrudcastActionResult } from '@brudcast/react-native';

import { deepLinkScheme, openDeepLink } from './navigation';

const entries: { at: Date; action: BrudcastAction }[] = [];

/** The actions messages asked for, newest first, shown on the account screen. */
export const actionLog = {
  /**
   * Lists the recorded actions.
   *
   * @returns The actions with when they arrived, newest first.
   */
  entries() {
    return entries;
  },
};

/**
 * Records every action in the log, and routes the example's own `brudcast-sample:` links to its
 * screens. Everything else gets the SDK's default.
 *
 * @param action The action a message asked for.
 * @returns `handled` for the example's own links, `useDefault` otherwise.
 */
export function handleAction(action: BrudcastAction): BrudcastActionResult {
  entries.unshift({ at: new Date(), action });
  const isOwnLink = action.kind === 'deeplink' && action.value.startsWith(`${deepLinkScheme}:`);
  if (!isOwnLink) return 'useDefault';
  return openDeepLink(action.value) ? 'handled' : 'useDefault';
}
