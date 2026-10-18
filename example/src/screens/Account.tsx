import { useEffect, useState } from 'react';
import { Brudcast } from '@brudcast/react-native';
import { BrudcastPush, type BrudcastPushPermission } from '@brudcast/react-native-push';

import { actionLog } from '../actions';
import { useNavigation } from '../navigation';
import { signOut, type SampleUser } from '../session';
import { Body, Button, Screen } from '../ui';

/**
 * The account: the device id, push permission, the actions messages asked for, and sign-out.
 *
 * @param props The signed-in user, and what to do once signed out.
 * @returns The screen.
 */
export function AccountScreen(props: { user: SampleUser | null; onSignedOut: () => void }) {
  const navigation = useNavigation();
  const [deviceId, setDeviceId] = useState<string | null>(null);
  const [permission, setPermission] = useState<BrudcastPushPermission>('notDetermined');

  useEffect(() => {
    void Brudcast.getDeviceId().then(setDeviceId);
    void BrudcastPush.getPermissionStatus().then(setPermission);
    const subscription = BrudcastPush.addPermissionListener(setPermission);
    return () => subscription.remove();
  }, []);

  return (
    <Screen title="Account">
      <Body>Signed in as {props.user?.externalId ?? 'nobody'}</Body>
      <Body muted>Device {deviceId ?? 'not started'}</Body>
      <Body muted>Push permission: {permission}</Body>
      {permission === 'notDetermined' ? (
        <Button
          kind="outlined"
          title="Allow notifications"
          onPress={async () => setPermission(await BrudcastPush.requestPermission())}
        />
      ) : null}
      <Body heading>Actions</Body>
      {actionLog.entries().length === 0 ? (
        <Body muted>No message has asked for anything yet.</Body>
      ) : null}
      {actionLog.entries().map((entry) => (
        <Body key={entry.at.toISOString()} muted>
          {entry.at.toLocaleTimeString()} {entry.action.source.origin} {entry.action.kind}{' '}
          {entry.action.value}
        </Body>
      ))}
      <Button
        title="Sign out"
        onPress={async () => {
          await signOut();
          props.onSignedOut();
          navigation.reset({ name: 'SignIn' });
        }}
        testID="signOut"
      />
    </Screen>
  );
}
