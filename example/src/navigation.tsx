import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { BackHandler } from 'react-native';
import { Brudcast } from '@brudcast/react-native';
import type { BrudcastInAppMessage } from '@brudcast/react-native-in-app';

import type { Product } from './catalog';

/** The example's screens. The names are also the `Brudcast.screen` names. */
export type Route =
  | { name: 'SignIn' }
  | { name: 'Home' }
  | { name: 'Shop' }
  | { name: 'Product'; product: Product }
  | { name: 'Checkout' }
  | { name: 'Account' }
  | { name: 'Inbox' }
  | { name: 'InboxMessage'; message: BrudcastInAppMessage };

/**
 * The example's own deep link scheme. `brudcast-sample://shop` and the sample backend's
 * `brudcast-sample://welcome` open the shop, and `brudcast-sample://checkout` opens checkout.
 */
export const deepLinkScheme = 'brudcast-sample';

type Navigation = {
  route: Route;
  canGoBack: boolean;
  push: (route: Route) => void;
  back: () => void;
  reset: (route: Route) => void;
};

const NavigationContext = createContext<Navigation | null>(null);

let openLink: ((link: string) => boolean) | null = null;

/**
 * Opens the screen a `brudcast-sample:` link names, for the action handler, which runs outside the
 * component tree.
 *
 * @param link The link.
 * @returns Whether the link names a screen.
 */
export function openDeepLink(link: string): boolean {
  return openLink?.(link) ?? false;
}

/**
 * A small stack of screens, so the example needs no navigation library. It records a
 * `Brudcast.screen` as each screen appears, the way an app tracks its screens.
 *
 * @param props The first screen and the tree.
 * @returns The provider.
 */
export function NavigationProvider(props: { initial: Route; children: ReactNode }) {
  const [stack, setStack] = useState<Route[]>([props.initial]);
  const route = stack[stack.length - 1] ?? props.initial;

  const push = useCallback((next: Route) => setStack((current) => [...current, next]), []);
  const back = useCallback(
    () => setStack((current) => (current.length > 1 ? current.slice(0, -1) : current)),
    []
  );
  const reset = useCallback((next: Route) => setStack([next]), []);

  useEffect(() => {
    void Brudcast.screen(route.name);
  }, [route]);

  useEffect(() => {
    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      if (stack.length <= 1) return false;
      back();
      return true;
    });
    return () => subscription.remove();
  }, [stack.length, back]);

  useEffect(() => {
    openLink = (link) => {
      const host = link.replace(`${deepLinkScheme}://`, '').split(/[/?#]/)[0];
      if (host === 'shop' || host === 'welcome') push({ name: 'Shop' });
      else if (host === 'checkout') push({ name: 'Checkout' });
      else return false;
      return true;
    };
    return () => {
      openLink = null;
    };
  }, [push]);

  const value = useMemo(
    () => ({ route, canGoBack: stack.length > 1, push, back, reset }),
    [route, stack.length, push, back, reset]
  );
  return <NavigationContext.Provider value={value}>{props.children}</NavigationContext.Provider>;
}

/**
 * Reads the navigation.
 *
 * @returns The current screen and the actions.
 * @throws {Error} Outside `NavigationProvider`.
 */
export function useNavigation(): Navigation {
  const navigation = useContext(NavigationContext);
  if (!navigation) throw new Error('useNavigation needs a NavigationProvider');
  return navigation;
}
