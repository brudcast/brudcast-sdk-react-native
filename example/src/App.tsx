import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { SampleBackend } from './backend';
import { SampleConfig } from './config';
import { NavigationProvider, useNavigation, type Route } from './navigation';
import { loadUser, type SampleUser } from './session';
import { AccountScreen } from './screens/Account';
import { HomeScreen } from './screens/Home';
import { InboxMessageScreen, InboxScreen } from './screens/Inbox';
import { CheckoutScreen, ProductScreen, ShopScreen } from './screens/Shop';
import { SignInScreen } from './screens/SignIn';

/**
 * The example app: it waits for the saved session, then opens Home or Sign in.
 *
 * @returns The app.
 */
export function App() {
  const [user, setUser] = useState<SampleUser | null | undefined>(undefined);
  const backend = useMemo(
    () => (SampleConfig.sampleBackendUrl ? new SampleBackend(SampleConfig.sampleBackendUrl) : null),
    []
  );

  useEffect(() => {
    void loadUser().then(setUser);
  }, []);

  if (user === undefined) {
    return (
      <View style={{ flex: 1, justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }
  const initial: Route = user ? { name: 'Home' } : { name: 'SignIn' };
  return (
    <SafeAreaProvider>
      <NavigationProvider initial={initial}>
        <Screens user={user} backend={backend} setUser={setUser} />
      </NavigationProvider>
    </SafeAreaProvider>
  );
}

/**
 * Shows the current screen.
 *
 * @param props The signed-in user, the backend and a way to change the user.
 * @returns The screen.
 */
function Screens(props: {
  user: SampleUser | null;
  backend: SampleBackend | null;
  setUser: (user: SampleUser | null) => void;
}) {
  const { route } = useNavigation();
  switch (route.name) {
    case 'SignIn':
      return <SignInScreen backend={props.backend} onSignedIn={props.setUser} />;
    case 'Home':
      return <HomeScreen user={props.user} backend={props.backend} />;
    case 'Shop':
      return <ShopScreen />;
    case 'Product':
      return <ProductScreen product={route.product} />;
    case 'Checkout':
      return <CheckoutScreen />;
    case 'Account':
      return <AccountScreen user={props.user} onSignedOut={() => props.setUser(null)} />;
    case 'Inbox':
      return <InboxScreen />;
    case 'InboxMessage':
      return <InboxMessageScreen message={route.message} />;
  }
}
