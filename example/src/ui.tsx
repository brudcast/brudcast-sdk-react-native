import type { ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View, useColorScheme } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useNavigation } from './navigation';

/** The example's accent colour, also passed to `Brudcast.initialize`. */
export const accent = '#3355FF';

/**
 * A screen with a title bar and a back button when there is a screen to go back to.
 *
 * @param props The title, the bar's extra buttons and the content.
 * @returns The screen.
 */
export function Screen(props: {
  title: string;
  actions?: ReactNode;
  children: ReactNode;
  scroll?: boolean;
}) {
  const navigation = useNavigation();
  const colors = useColors();
  const body =
    props.scroll === false ? (
      <View style={styles.body}>{props.children}</View>
    ) : (
      <ScrollView contentContainerStyle={styles.body}>{props.children}</ScrollView>
    );
  return (
    <SafeAreaView style={[styles.screen, { backgroundColor: colors.background }]}>
      <View style={styles.bar}>
        {navigation.canGoBack ? (
          <Button title="Back" kind="plain" onPress={navigation.back} />
        ) : null}
        <Text style={[styles.title, { color: colors.text }]}>{props.title}</Text>
        <View style={styles.actions}>{props.actions}</View>
      </View>
      {body}
    </SafeAreaView>
  );
}

/**
 * A button: filled for the main action, outlined for the others, plain in the title bar.
 *
 * @param props The label, the kind, the action and a test id.
 * @returns The button.
 */
export function Button(props: {
  title: string;
  onPress: () => void;
  kind?: 'filled' | 'outlined' | 'plain';
  testID?: string;
  disabled?: boolean;
}) {
  const kind = props.kind ?? 'filled';
  return (
    <Pressable
      accessibilityRole="button"
      disabled={props.disabled}
      onPress={props.onPress}
      testID={props.testID}
      style={({ pressed }) => [
        styles.button,
        kind === 'filled' && { backgroundColor: accent },
        kind === 'outlined' && { borderColor: accent, borderWidth: 1 },
        kind === 'plain' && styles.plain,
        (pressed || props.disabled) && { opacity: 0.6 },
      ]}
    >
      <Text style={[styles.buttonText, { color: kind === 'filled' ? '#FFFFFF' : accent }]}>
        {props.title}
      </Text>
    </Pressable>
  );
}

/**
 * Body text in the colour of the current appearance.
 *
 * @param props The text and an optional style.
 * @returns The text.
 */
export function Body(props: { children: ReactNode; muted?: boolean; heading?: boolean }) {
  const colors = useColors();
  return (
    <Text
      style={[
        { color: props.muted ? colors.muted : colors.text },
        props.heading ? styles.heading : styles.text,
      ]}
    >
      {props.children}
    </Text>
  );
}

/**
 * Picks colours for the device's light or dark setting.
 *
 * @returns The colours.
 */
export function useColors() {
  const dark = useColorScheme() === 'dark';
  return {
    background: dark ? '#111318' : '#FFFFFF',
    text: dark ? '#E6E8EF' : '#14161C',
    muted: dark ? '#9AA0AE' : '#5D6270',
    border: dark ? '#2A2E38' : '#E3E5EA',
  };
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    height: 52,
    gap: 8,
  },
  title: { flex: 1, fontSize: 20, fontWeight: '600' },
  actions: { flexDirection: 'row', gap: 4 },
  body: { padding: 24, gap: 12 },
  button: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 10,
    alignItems: 'center',
  },
  plain: { paddingHorizontal: 8, paddingVertical: 8 },
  buttonText: { fontSize: 16, fontWeight: '600' },
  text: { fontSize: 16, lineHeight: 22 },
  heading: { fontSize: 24, fontWeight: '600', marginBottom: 12 },
});
