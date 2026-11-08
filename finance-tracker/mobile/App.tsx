import {
  Inter_400Regular,
  Inter_500Medium,
  Inter_600SemiBold,
  Inter_700Bold,
  Inter_800ExtraBold,
  useFonts,
} from '@expo-google-fonts/inter';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Animated, AppState, Easing, Platform, UIManager, View, type LayoutChangeEvent } from 'react-native';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';

import { PressScale, Pulse, tap } from './src/components/anim';
import { ErrorBoundary, LockScreen } from './src/components/guards';
import Icon, { type IconName } from './src/components/Icon';
import { T } from './src/components/ui';
import { installGlobalErrorHandler } from './src/errorLog';
import HomeScreen from './src/screens/HomeScreen';
import InsightsScreen, { type LeaksView } from './src/screens/InsightsScreen';
import InvestScreen, { type InvestView } from './src/screens/InvestScreen';
import OnboardingScreen from './src/screens/OnboardingScreen';
import SettingsScreen from './src/screens/SettingsScreen';
import SpendingScreen from './src/screens/SpendingScreen';
import { DataProvider, useData } from './src/store';
import { C, GRADIENTS } from './src/theme';
import { ScrollProvider, ThemedRoot, ThemeProvider, useTheme } from './src/themeContext';

SplashScreen.preventAutoHideAsync().catch(() => {});
SplashScreen.setOptions?.({ duration: 400, fade: true });
if (Platform.OS === 'android') UIManager.setLayoutAnimationEnabledExperimental?.(true);
installGlobalErrorHandler();

const RELOCK_AFTER_MS = 30_000;

const TABS: { key: Tab; label: string; icon: IconName; title: string }[] = [
  { key: 'home', label: 'Home', icon: 'home', title: 'Overview' },
  { key: 'spending', label: 'Spending', icon: 'pie', title: 'Spending' },
  { key: 'insights', label: 'Leaks', icon: 'droplet', title: 'Money leaks' },
  { key: 'invest', label: 'Wealth', icon: 'trend', title: 'Wealth' },
  { key: 'settings', label: 'Settings', icon: 'sliders', title: 'Settings' },
];
type Tab = 'home' | 'spending' | 'insights' | 'invest' | 'settings';

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
}

function SyncSpinner({ active }: { active: boolean }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!active) return;
    const loop = Animated.loop(Animated.timing(v, { toValue: 1, duration: 900, easing: Easing.linear, useNativeDriver: true }));
    loop.start();
    return () => {
      loop.stop();
      v.setValue(0);
    };
  }, [active, v]);
  if (!active) return null;
  return (
    <Animated.View
      style={{
        width: 34,
        height: 34,
        borderRadius: 17,
        backgroundColor: C.accentSoft,
        alignItems: 'center',
        justifyContent: 'center',
        transform: [{ rotate: v.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '360deg'] }) }],
      }}
    >
      <Icon name="refresh" size={16} color={C.accent} />
    </Animated.View>
  );
}

/** Slides the new screen in from the side you moved towards. */
function SlideIn({ dir, children }: { dir: number; children: ReactNode }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.spring(v, { toValue: 1, useNativeDriver: true, damping: 20, stiffness: 180, mass: 0.9 }).start();
  }, [v]);
  return (
    <Animated.View
      style={{
        flex: 1,
        opacity: v.interpolate({ inputRange: [0, 0.6, 1], outputRange: [0, 1, 1] }),
        transform: [{ translateX: v.interpolate({ inputRange: [0, 1], outputRange: [dir * 36, 0] }) }],
      }}
    >
      {children}
    </Animated.View>
  );
}

function TabItem({ t, active, badge, onPress }: { t: (typeof TABS)[number]; active: boolean; badge: number; onPress: () => void }) {
  const v = useRef(new Animated.Value(active ? 1 : 0)).current;
  useEffect(() => {
    Animated.spring(v, { toValue: active ? 1 : 0, useNativeDriver: true, speed: 14, bounciness: 12 }).start();
  }, [active, v]);
  return (
    <PressScale onPress={onPress} scaleTo={0.88} haptic={false} style={{ flex: 1, alignItems: 'center', paddingVertical: 4 }}>
      <Animated.View
        style={{
          transform: [
            { translateY: v.interpolate({ inputRange: [0, 1], outputRange: [3, -1] }) },
            { scale: v.interpolate({ inputRange: [0, 1], outputRange: [1, 1.14] }) },
          ],
        }}
      >
        <Icon name={t.icon} size={22} color={active ? C.accent : C.sub} stroke={active ? 2.4 : 2} />
        {badge > 0 ? (
          <Pulse style={{ position: 'absolute', top: -5, right: -10 }}>
            <View style={{ minWidth: 17, height: 17, borderRadius: 9, backgroundColor: C.red, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 3, borderWidth: 2, borderColor: C.card }}>
              <T size={9} weight="bold" color="#fff" style={{ lineHeight: 11 }}>
                {String(badge)}
              </T>
            </View>
          </Pulse>
        ) : null}
      </Animated.View>
      <Animated.View style={{ opacity: v.interpolate({ inputRange: [0, 1], outputRange: [0.7, 1] }) }}>
        <T size={10.5} weight={active ? 'bold' : 'medium'} color={active ? C.accent : C.sub} style={{ marginTop: 4 }}>
          {t.label}
        </T>
      </Animated.View>
    </PressScale>
  );
}

function TabBar({ tab, onChange, badge }: { tab: Tab; onChange: (t: Tab) => void; badge: number }) {
  const insets = useSafeAreaInsets();
  const { mode } = useTheme();
  const [w, setW] = useState(0);
  const idx = TABS.findIndex((t) => t.key === tab);
  const x = useRef(new Animated.Value(idx)).current;
  useEffect(() => {
    Animated.spring(x, { toValue: idx, useNativeDriver: true, speed: 14, bounciness: 9 }).start();
  }, [idx, x]);
  const seg = w / TABS.length;
  return (
    <View style={{ position: 'absolute', left: 14, right: 14, bottom: insets.bottom + 10 }}>
      <View
        onLayout={(e: LayoutChangeEvent) => setW(e.nativeEvent.layout.width)}
        style={{
          flexDirection: 'row',
          backgroundColor: C.glass,
          borderRadius: 28,
          paddingVertical: 9,
          borderWidth: mode === 'dark' ? 0.5 : 0,
          borderColor: C.borderHi,
          shadowColor: C.shadow,
          shadowOpacity: mode === 'dark' ? 0.55 : 0.14,
          shadowRadius: 24,
          shadowOffset: { width: 0, height: 10 },
          elevation: 18,
        }}
      >
        {w > 0 ? (
          <Animated.View
            style={{
              position: 'absolute',
              top: 7,
              bottom: 7,
              width: seg - 14,
              left: 7,
              borderRadius: 21,
              backgroundColor: C.accentSoft,
              transform: [{ translateX: x.interpolate({ inputRange: [0, TABS.length - 1], outputRange: [0, seg * (TABS.length - 1)] }) }],
            }}
          />
        ) : null}
        {TABS.map((t) => (
          <TabItem
            key={t.key}
            t={t}
            active={t.key === tab}
            badge={t.key === 'insights' ? badge : 0}
            onPress={() => {
              if (t.key !== tab) tap();
              onChange(t.key);
            }}
          />
        ))}
      </View>
    </View>
  );
}

/** Large title that shrinks and gains a divider as the page scrolls. */
function Header({ tab, scrollY, loading }: { tab: Tab; scrollY: Animated.Value; loading: boolean }) {
  const meta = TABS.find((t) => t.key === tab)!;
  const scale = scrollY.interpolate({ inputRange: [0, 90], outputRange: [1, 0.72], extrapolate: 'clamp' });
  const shift = scrollY.interpolate({ inputRange: [0, 90], outputRange: [0, -14], extrapolate: 'clamp' });
  const fade = scrollY.interpolate({ inputRange: [0, 40], outputRange: [1, 0], extrapolate: 'clamp' });
  const line = scrollY.interpolate({ inputRange: [20, 80], outputRange: [0, 1], extrapolate: 'clamp' });
  return (
    <View style={{ paddingHorizontal: 18, paddingTop: 6, height: 72, justifyContent: 'flex-end', zIndex: 2, backgroundColor: C.bg }}>
      <Animated.View style={{ opacity: fade, position: 'absolute', top: 6, left: 18 }}>
        {tab === 'home' ? (
          <T size={13} color={C.sub} weight="medium">
            {greeting()} · {new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'short' })}
          </T>
        ) : null}
      </Animated.View>
      <View style={{ flexDirection: 'row', alignItems: 'flex-end', paddingBottom: 8 }}>
        <Animated.View style={{ flex: 1, transformOrigin: 'left bottom', transform: [{ translateY: shift }, { scale }] }}>
          <T size={30} weight="black" style={{ letterSpacing: -0.8, lineHeight: 38 }}>
            {meta.title}
          </T>
        </Animated.View>
        <View style={{ marginBottom: 4 }}>
          <SyncSpinner active={loading} />
        </View>
      </View>
      <Animated.View style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 1, backgroundColor: C.border, opacity: line }} />
    </View>
  );
}

function Shell() {
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState<Tab>('home');
  const [dir, setDir] = useState(1);
  const [subView, setSubView] = useState<string | undefined>(undefined);
  const scrollY = useRef(new Animated.Value(0)).current;
  const switchTo = (t: Tab, v?: string) => {
    const from = TABS.findIndex((x) => x.key === tab);
    const to = TABS.findIndex((x) => x.key === t);
    setDir(to >= from ? 1 : -1);
    scrollY.setValue(0);
    setSubView(v);
    setTab(t);
  };
  const go = (target: string) => {
    const [t, v] = target.split(':');
    switchTo(t as Tab, v);
  };
  const d = useData();
  const highLeaks = d.waste.filter((i) => i.severity === 'high').length;

  // App lock: lock on start, and again after 30 s in the background.
  const [locked, setLocked] = useState(true);
  const [lockChecked, setLockChecked] = useState(false);
  const leftAt = useRef(0);
  useEffect(() => {
    if (d.loading && !lockChecked) return;
    if (!lockChecked) {
      setLockChecked(true);
      setLocked(d.appLock);
    }
  }, [d.loading, d.appLock, lockChecked]);
  useEffect(() => {
    const sub = AppState.addEventListener('change', (s) => {
      if (s === 'background') leftAt.current = Date.now();
      if (s === 'active' && d.appLock && leftAt.current && Date.now() - leftAt.current > RELOCK_AFTER_MS) setLocked(true);
    });
    return () => sub.remove();
  }, [d.appLock]);
  const showLock = d.appLock && locked && lockChecked;

  if (!d.loading && d.source === 'none') return <OnboardingScreen />;

  return (
    <View style={{ flex: 1, backgroundColor: C.bg, paddingTop: insets.top }}>
      {/* soft accent glow behind the header */}
      <Svg style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 260 }} width="100%" height={260} pointerEvents="none">
        <Defs>
          <LinearGradient id="topglow" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={GRADIENTS.hero[0]} stopOpacity={0.16} />
            <Stop offset="1" stopColor={C.bg} stopOpacity={0} />
          </LinearGradient>
        </Defs>
        <Rect width="100%" height={260} fill="url(#topglow)" />
      </Svg>
      <Header tab={tab} scrollY={scrollY} loading={d.loading} />
      <ScrollProvider value={scrollY}>
        <SlideIn key={tab} dir={dir}>
          {tab === 'home' && <HomeScreen go={go} />}
          {tab === 'spending' && <SpendingScreen />}
          {tab === 'insights' && <InsightsScreen initial={(subView as LeaksView) ?? 'leaks'} />}
          {tab === 'invest' && <InvestScreen initial={(subView as InvestView) ?? 'portfolio'} />}
          {tab === 'settings' && <SettingsScreen />}
        </SlideIn>
      </ScrollProvider>
      <TabBar
        tab={tab}
        onChange={(t) => switchTo(t)}
        badge={highLeaks + d.signals.length + d.failedPayments.filter((f) => f.status === 'overdue').length}
      />
      {showLock ? <LockScreen onUnlock={() => setLocked(false)} /> : null}
    </View>
  );
}

function ThemedStatusBar() {
  const { mode } = useTheme();
  return <StatusBar style={mode === 'dark' ? 'light' : 'dark'} />;
}

export default function App() {
  const [fontsLoaded, fontError] = useFonts({ Inter_400Regular, Inter_500Medium, Inter_600SemiBold, Inter_700Bold, Inter_800ExtraBold });
  const ready = fontsLoaded || fontError != null;
  useEffect(() => {
    if (ready) SplashScreen.hideAsync().catch(() => {});
  }, [ready]);
  if (!ready) return null;
  return (
    <SafeAreaProvider>
      <ThemeProvider>
        <ThemedStatusBar />
        <ErrorBoundary>
          <DataProvider>
            <ThemedRoot>
              <Shell />
            </ThemedRoot>
          </DataProvider>
        </ErrorBoundary>
      </ThemeProvider>
    </SafeAreaProvider>
  );
}
