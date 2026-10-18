import { useState } from 'react';
import { BrudcastInApp, useInboxUnreadCount } from '@brudcast/react-native-in-app';

import type { SampleBackend } from '../backend';
import { useNavigation } from '../navigation';
import type { SampleUser } from '../session';
import { Body, Button, Screen } from '../ui';

/**
 * The landing screen: the inbox with its unread count, the shop, and a welcome message sent
 * through the backend.
 *
 * @param props The signed-in user and the backend.
 * @returns The screen.
 */
export function HomeScreen(props: { user: SampleUser | null; backend: SampleBackend | null }) {
  const navigation = useNavigation();
  const unread = useInboxUnreadCount();
  const [status, setStatus] = useState<string | null>(null);

  const sendWelcome = async () => {
    if (!props.backend || !props.user) return;
    try {
      await props.backend.sendWelcome(props.user.externalId);
      setStatus('Welcome sent; it shows in a moment');
    } catch (error) {
      setStatus(String(error));
    }
  };

  return (
    <Screen
      title="Home"
      actions={
        <>
          <Button
            kind="plain"
            title={unread > 0 ? `Inbox (${unread})` : 'Inbox'}
            onPress={() => navigation.push({ name: 'Inbox' })}
            testID="inbox"
          />
          <Button
            kind="plain"
            title="Account"
            onPress={() => navigation.push({ name: 'Account' })}
          />
        </>
      }
    >
      <Body heading>Hello{props.user?.email ? `, ${props.user.email}` : ''}</Body>
      <Button title="Shop" onPress={() => navigation.push({ name: 'Shop' })} testID="shop" />
      <Button
        kind="outlined"
        title="Open the native inbox"
        onPress={() => BrudcastInApp.inbox.present({ title: 'Inbox' })}
      />
      {props.backend ? (
        <Button kind="outlined" title="Send me a welcome" onPress={sendWelcome} />
      ) : null}
      {status ? <Body muted>{status}</Body> : null}
    </Screen>
  );
}
