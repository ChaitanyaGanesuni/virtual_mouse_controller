import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SystemUI from 'expo-system-ui';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Animated, useColorScheme } from 'react-native';

import { rebuildStyles } from './components/ui';
import { applyTheme, C, type Accent, type Mode } from './theme';

export type ModePref = 'system' | Mode;
export interface ThemePrefs {
  mode: ModePref;
  accent: Accent;
}
const KEY = 'theme.v1';
const DEFAULT: ThemePrefs = { mode: 'system', accent: 'emerald' };

interface ThemeState {
  prefs: ThemePrefs;
  mode: Mode;
  setPrefs: (p: ThemePrefs) => void;
}

const Ctx = createContext<ThemeState>({ prefs: DEFAULT, mode: 'dark', setPrefs: () => {} });
export const useTheme = () => useContext(Ctx);

/**
 * Applies the chosen theme before anything renders and re-mounts the app when it changes,
 * so every screen draws with the new colours.
 */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const system = useColorScheme();
  const [prefs, setPrefsState] = useState<ThemePrefs | null>(null);

  useEffect(() => {
    AsyncStorage.getItem(KEY)
      .then((v) => setPrefsState(v ? { ...DEFAULT, ...JSON.parse(v) } : DEFAULT))
      .catch(() => setPrefsState(DEFAULT));
  }, []);

  const p = prefs ?? DEFAULT;
  const mode: Mode = p.mode === 'system' ? (system === 'light' ? 'light' : 'dark') : p.mode;

  // Apply synchronously during render so children read the right tokens on this pass.
  const applied = useRef('');
  const sig = `${mode}|${p.accent}`;
  if (applied.current !== sig) {
    applyTheme(mode, p.accent);
    rebuildStyles();
    applied.current = sig;
  }
  useEffect(() => {
    SystemUI.setBackgroundColorAsync(C.bg).catch(() => {});
  }, [sig]);

  const setPrefs = useCallback((next: ThemePrefs) => {
    setPrefsState(next);
    AsyncStorage.setItem(KEY, JSON.stringify(next)).catch(() => {});
  }, []);

  const value = useMemo(() => ({ prefs: p, mode, setPrefs }), [p, mode, setPrefs]);
  if (!prefs) return null;
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

/** Re-mounts (and cross-fades) the screens below it when the theme changes; data providers stay above it. */
export function ThemedRoot({ children }: { children: ReactNode }) {
  const { prefs, mode } = useTheme();
  return <ThemeFade key={`${mode}|${prefs.accent}`}>{children}</ThemeFade>;
}

/** Cross-fades the app in after a theme change. */
function ThemeFade({ children }: { children: ReactNode }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(v, { toValue: 1, duration: 320, useNativeDriver: true }).start();
  }, [v]);
  return <Animated.View style={{ flex: 1, opacity: v, backgroundColor: C.bg }}>{children}</Animated.View>;
}

// ---------------------------------------------------------------- scroll position for the collapsing header

const ScrollCtx = createContext<Animated.Value>(new Animated.Value(0));
export const ScrollProvider = ScrollCtx.Provider;

/** Spread into an Animated.ScrollView / list so the shell's large title can shrink as you scroll. */
export function useScreenScroll() {
  const y = useContext(ScrollCtx);
  return useMemo(
    () => ({
      onScroll: Animated.event([{ nativeEvent: { contentOffset: { y } } }], { useNativeDriver: true }),
      scrollEventThrottle: 16,
    }),
    [y],
  );
}
