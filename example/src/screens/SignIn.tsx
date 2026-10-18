import { useState } from 'react';
import { StyleSheet, TextInput } from 'react-native';

import type { SampleBackend } from '../backend';
import { useNavigation } from '../navigation';
import { signIn, type SampleUser } from '../session';
import { Body, Button, Screen, useColors } from '../ui';

/**
 * Signs a user in through the backend, which computes the user hash, or with a pasted hash when
 * no backend is configured.
 *
 * @param props The backend, and what to do once signed in.
 * @returns The screen.
 */
export function SignInScreen(props: {
  backend: SampleBackend | null;
  onSignedIn: (user: SampleUser) => void;
}) {
  const navigation = useNavigation();
  const colors = useColors();
  const [userId, setUserId] = useState('');
  const [email, setEmail] = useState('');
  const [userHash, setUserHash] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      const trimmedEmail = email.trim() || undefined;
      const signed = props.backend
        ? await props.backend.login(userId.trim(), trimmedEmail)
        : {
            externalId: userId.trim(),
            userHash: userHash.trim(),
            email: trimmedEmail,
          };
      const user = {
        externalId: signed.externalId,
        ...(signed.email ? { email: signed.email } : {}),
      };
      await signIn(user, signed.userHash);
      props.onSignedIn(user);
      navigation.reset({ name: 'Home' });
    } catch (caught) {
      setError(String(caught));
    } finally {
      setBusy(false);
    }
  };

  const input = [styles.input, { color: colors.text, borderColor: colors.border }];
  return (
    <Screen title="Sign in">
      <Body muted>
        {props.backend
          ? `Your backend at ${props.backend.baseUrl} computes the user hash.`
          : 'No backend is configured, so paste the user hash your server computed.'}
      </Body>
      <TextInput
        style={input}
        placeholder="User id"
        value={userId}
        onChangeText={setUserId}
        autoCapitalize="none"
        testID="userId"
      />
      <TextInput
        style={input}
        placeholder="Email (optional)"
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        keyboardType="email-address"
      />
      {props.backend ? null : (
        <TextInput
          style={input}
          placeholder="User hash"
          value={userHash}
          onChangeText={setUserHash}
          autoCapitalize="none"
          testID="userHash"
        />
      )}
      {error ? <Body muted>{error}</Body> : null}
      <Button
        title="Sign in"
        onPress={submit}
        disabled={busy || userId.trim() === ''}
        testID="signIn"
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  input: {
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
  },
});
