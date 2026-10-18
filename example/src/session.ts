import AsyncStorage from '@react-native-async-storage/async-storage';
import { Brudcast } from '@brudcast/react-native';

const key = 'sample.session';

/** The signed-in user, kept across launches the way an app keeps its login. */
export type SampleUser = {
  externalId: string;
  email?: string;
};

/**
 * Loads the saved user. The SDK keeps its own identity too, so a relaunch needs no new `identify`.
 *
 * @returns The user, or null when signed out.
 */
export async function loadUser(): Promise<SampleUser | null> {
  const saved = await AsyncStorage.getItem(key);
  return saved ? (JSON.parse(saved) as SampleUser) : null;
}

/**
 * Signs a user in: identifies them to Brudcast with the hash the backend computed.
 *
 * @param user The user.
 * @param userHash `hex(HMAC-SHA256(identitySecret, externalId))`, from the backend.
 */
export async function signIn(user: SampleUser, userHash: string): Promise<void> {
  await Brudcast.identify(user.externalId, {
    userHash,
    ...(user.email ? { traits: { email: user.email } } : {}),
  });
  await AsyncStorage.setItem(key, JSON.stringify(user));
}

/**
 * Signs the user out: Brudcast forgets them, and their push token stops reaching them here.
 */
export async function signOut(): Promise<void> {
  await Brudcast.reset();
  await AsyncStorage.removeItem(key);
}
