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
import * as SystemUI from 'expo-system-ui';
import { useEffect, useRef, useState } from 'react';
import { Animated, AppState, Easing, Platform, UIManager, View, type LayoutChangeEvent } from 'react-native';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';

import { FadeIn, PressScale, Pulse } from './src/components/anim';
import { ErrorBoundary, LockScreen } from './src/components/guards';
import { installGlobalErrorHandler } from './src/errorLog';
import Icon, { type IconName } from './src/components/Icon';
import { T } from './src/components/ui';
import HomeScreen from './src/screens/HomeScreen';
import InsightsScreen, { type LeaksView } from './src/screens/InsightsScreen';
import InvestScreen, { type InvestView } from './src/screens/InvestScreen';
import OnboardingScreen from './src/screens/OnboardingScreen';
import SettingsScreen from './src/screens/SettingsScreen';
import SpendingScreen from './src/screens/SpendingScreen';
import { DataProvider, useData } from './src/store';
import { C } from './src/theme';

SplashScreen.preventAutoHideAsync().catch(() => {});
SplashScreen.setOptions?.({ duration: 400, fade: true });
SystemUI.setBackgroundColorAsync(C.bg).catch(() => {});
if (Platform.OS === 'android') UIManager.setLayoutAnimationEnabledExperimental?.(true);
installGlobalErrorHandler();

const RELOCK_AFTER_MS = 30_000;

const TABS: { key: Tab; label: string; icon: IconName; title: string }[] = [
  { key: 'home', label: 'Home', icon: 'home', title: 'Overview' },
  { key: 'spending', label: 'Spending', icon: 'pie', title: 'Spending' },
  { key: 'insights', label: 'Leaks', icon: 'droplet', title: 'Money leaks' },
  { key: 'invest', label: 'Invest', icon: 'trend', title: 'Investments' },
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
    <Animated.View style={{ transform: [{ rotate: v.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '360deg'] }) }] }}>
      <Icon name="refresh" size={18} color={C.green} />
    </Animated.View>
  );
}

function TabBar({ tab, onChange, badge }: { tab: Tab; onChange: (t: Tab) => void; badge: number }) {
  const insets = useSafeAreaInsets();
  const [w, setW] = useState(0);
  const idx = TABS.findIndex((t) => t.key === tab);
  const x = useRef(new Animated.Value(idx)).current;
  useEffect(() => {
    Animated.spring(x, { toValue: idx, useNativeDriver: true, speed: 16, bounciness: 8 }).start();
  }, [idx, x]);
  const seg = w / TABS.length;
  return (
    <View style={{ position: 'absolute', left: 14, right: 14, bottom: insets.bottom + 10 }}>
      <View
        onLayout={(e: LayoutChangeEvent) => setW(e.nativeEvent.layout.width)}
        style={{
          flexDirection: 'row',
          backgroundColor: 'rgba(18,26,38,0.97)',
          borderRadius: 26,
          paddingVertical: 8,
          borderWidth: 0.5,
          borderColor: C.borderHi,
          shadowColor: '#000',
          shadowOpacity: 0.5,
          shadowRadius: 20,
          shadowOffset: { width: 0, height: 8 },
          elevation: 18,
        }}
      >
        {w > 0 ? (
          <Animated.View
            style={{
              position: 'absolute',
              top: 6,
              bottom: 6,
              width: seg - 12,
              left: 6,
              borderRadius: 20,
              backgroundColor: C.green + '1F',
              transform: [{ translateX: x.interpolate({ inputRange: [0, TABS.length - 1], outputRange: [0, seg * (TABS.length - 1)] }) }],
            }}
          />
        ) : null}
        {TABS.map((t) => {
          const active = t.key === tab;
          return (
            <PressScale key={t.key} onPress={() => onChange(t.key)} scaleTo={0.9} style={{ flex: 1, alignItems: 'center', paddingVertical: 4 }}>
              <View>
                <Icon name={t.icon} size={22} color={active ? C.green : C.sub} stroke={active ? 2.4 : 2} />
                {t.key === 'insights' && badge > 0 ? (
                  <Pulse style={{ position: 'absolute', top: -4, right: -9 }}>
                    <View style={{ minWidth: 16, height: 16, borderRadius: 8, backgroundColor: C.red, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 3 }}>
                      <T size={9.5} weight="bold" color="#fff" style={{ lineHeight: 12 }}>
                        {String(badge)}
                      </T>
                    </View>
                  </Pulse>
                ) : null}
              </View>
              <T size={10.5} weight={active ? 'bold' : 'medium'} color={active ? C.green : C.sub} style={{ marginTop: 3 }}>
                {t.label}
              </T>
            </PressScale>
          );
        })}
      </View>
    </View>
  );
}

function Shell() {
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState<Tab>('home');
  const [subView, setSubView] = useState<string | undefined>(undefined);
  const go = (target: string) => {
    const [t, v] = target.split(':');
    setSubView(v);
    setTab(t as Tab);
  };
  const d = useData();
  const meta = TABS.find((t) => t.key === tab)!;
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
      <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 18, paddingTop: 8, paddingBottom: 6 }}>
        <View style={{ flex: 1 }}>
          {tab === 'home' ? (
            <T size={13} color={C.sub} weight="medium">
              {greeting()} · {new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'short' })}
            </T>
          ) : null}
          <FadeIn key={tab} from={6}>
            <T size={28} weight="black" style={{ letterSpacing: -0.6, lineHeight: 36 }}>
              {meta.title}
            </T>
          </FadeIn>
        </View>
        <SyncSpinner active={d.loading} />
      </View>
      <FadeIn key={tab} from={14} style={{ flex: 1 }}>
        {tab === 'home' && <HomeScreen go={go} />}
        {tab === 'spending' && <SpendingScreen />}
        {tab === 'insights' && <InsightsScreen initial={(subView as LeaksView) ?? 'leaks'} />}
        {tab === 'invest' && <InvestScreen initial={(subView as InvestView) ?? 'portfolio'} />}
        {tab === 'settings' && <SettingsScreen />}
      </FadeIn>
      <TabBar
        tab={tab}
        onChange={(t) => {
          setSubView(undefined);
          setTab(t);
        }}
        badge={highLeaks + d.signals.length + d.failedPayments.filter((f) => f.status === 'overdue').length}
      />
      {showLock ? <LockScreen onUnlock={() => setLocked(false)} /> : null}
    </View>
  );
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
      <StatusBar style="light" />
      <ErrorBoundary>
        <DataProvider>
          <Shell />
        </DataProvider>
      </ErrorBoundary>
    </SafeAreaProvider>
  );
}
