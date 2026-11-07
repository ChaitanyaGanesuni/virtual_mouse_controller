import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';

import { C } from './src/components/ui';
import HomeScreen from './src/screens/HomeScreen';
import InsightsScreen from './src/screens/InsightsScreen';
import InvestScreen from './src/screens/InvestScreen';
import SettingsScreen from './src/screens/SettingsScreen';
import SpendingScreen from './src/screens/SpendingScreen';
import { DataProvider, useData } from './src/store';

const TABS = [
  { key: 'home', label: 'Home', glyph: '◉' },
  { key: 'spending', label: 'Spending', glyph: '▤' },
  { key: 'insights', label: 'Leaks', glyph: '◬' },
  { key: 'invest', label: 'Invest', glyph: '↗' },
  { key: 'settings', label: 'Settings', glyph: '⚙' },
] as const;
type Tab = (typeof TABS)[number]['key'];

function Shell() {
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState<Tab>('home');
  const d = useData();
  const title = { home: 'Paisa Watch', spending: 'Spending', insights: 'Money leaks', invest: 'Investments', settings: 'Settings' }[tab];

  return (
    <View style={{ flex: 1, backgroundColor: C.bg, paddingTop: insets.top }}>
      <StatusBar style="light" />
      <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12 }}>
        <Text style={{ color: C.text, fontSize: 22, fontWeight: '800', flex: 1 }}>{title}</Text>
        {d.loading ? <ActivityIndicator color={C.accent} /> : null}
      </View>
      <View style={{ flex: 1 }}>
        {tab === 'home' && <HomeScreen go={(t) => setTab(t as Tab)} />}
        {tab === 'spending' && <SpendingScreen />}
        {tab === 'insights' && <InsightsScreen />}
        {tab === 'invest' && <InvestScreen />}
        {tab === 'settings' && <SettingsScreen />}
      </View>
      <View
        style={{
          flexDirection: 'row',
          borderTopWidth: 1,
          borderTopColor: C.border,
          backgroundColor: C.card,
          paddingBottom: insets.bottom,
        }}
      >
        {TABS.map((t) => {
          const active = t.key === tab;
          return (
            <Pressable key={t.key} onPress={() => setTab(t.key)} style={{ flex: 1, alignItems: 'center', paddingVertical: 10 }}>
              <Text style={{ color: active ? C.accent : C.sub, fontSize: 18 }}>{t.glyph}</Text>
              <Text style={{ color: active ? C.accent : C.sub, fontSize: 11, fontWeight: active ? '700' : '500', marginTop: 2 }}>
                {t.label}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <DataProvider>
        <Shell />
      </DataProvider>
    </SafeAreaProvider>
  );
}
