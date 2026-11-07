import { Linking, Pressable, ScrollView, Switch, Text, View } from 'react-native';

import { Button, C, Card, H, Label, Row } from '../components/ui';
import type { Assumptions } from '../lib/investments';
import { useData } from '../store';

function Stepper({ label, value, step, min, max, fmt, onChange }: {
  label: string;
  value: number;
  step: number;
  min: number;
  max: number;
  fmt: (v: number) => string;
  onChange: (v: number) => void;
}) {
  const btn = (txt: string, v: number) => (
    <Pressable
      onPress={() => onChange(Math.min(max, Math.max(min, Math.round(v * 1000) / 1000)))}
      style={{ width: 34, height: 34, borderRadius: 17, borderWidth: 1, borderColor: C.border, alignItems: 'center', justifyContent: 'center' }}
    >
      <Text style={{ color: C.text, fontSize: 18 }}>{txt}</Text>
    </Pressable>
  );
  return (
    <Row style={{ justifyContent: 'space-between', paddingVertical: 8 }}>
      <Text style={{ color: C.text, flex: 1 }}>{label}</Text>
      {btn('−', value - step)}
      <Text style={{ color: C.text, width: 70, textAlign: 'center', fontWeight: '700' }}>{fmt(value)}</Text>
      {btn('+', value + step)}
    </Row>
  );
}

export default function SettingsScreen() {
  const d = useData();
  const a = d.assumptions;
  const set = (patch: Partial<Assumptions>) => d.setAssumptions({ ...a, ...patch });
  const setEquity = (eq: number) => {
    const rest = 100 - eq;
    const gold = Math.min(a.target.gold, rest);
    set({ target: { equity: eq, debt: rest - gold, gold } });
  };

  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <H>Data</H>
      <Card>
        <Row style={{ justifyContent: 'space-between' }}>
          <Label>Source</Label>
          <Text style={{ color: C.text }}>
            {d.source === 'sms' ? 'Bank alert SMS (automatic)' : d.source === 'demo' ? 'Sample data' : 'Not connected'}
          </Text>
        </Row>
        <Row style={{ justifyContent: 'space-between', marginTop: 8 }}>
          <Label>SMS permission</Label>
          <Text style={{ color: d.permission === 'granted' ? C.accent : C.amber }}>{d.permission}</Text>
        </Row>
        <Row style={{ justifyContent: 'space-between', marginTop: 8 }}>
          <Label>Last scan</Label>
          <Text style={{ color: C.text }}>{d.lastSync ? new Date(d.lastSync).toLocaleString('en-IN') : '—'}</Text>
        </Row>
        {d.error ? <Text style={{ color: C.red, marginTop: 8 }}>{d.error}</Text> : null}
        <Button label={d.loading ? 'Scanning…' : 'Re-scan now'} onPress={d.refresh} />
        {d.permission === 'denied' ? (
          <Button label="Open app settings to allow SMS" kind="ghost" onPress={() => Linking.openSettings()} />
        ) : null}
        <Row style={{ justifyContent: 'space-between', marginTop: 14 }}>
          <Text style={{ color: C.text }}>Use sample data</Text>
          <Switch value={d.demoMode} onValueChange={d.setDemoMode} thumbColor={d.demoMode ? C.accent : undefined} />
        </Row>
      </Card>

      <H>Investment goals</H>
      <Card>
        <Stepper label="Emergency fund (months of spend)" value={a.emergencyFundMonths} step={1} min={1} max={24} fmt={(v) => `${v} mo`} onChange={(v) => set({ emergencyFundMonths: v })} />
        <Stepper label="Target equity" value={a.target.equity} step={5} min={0} max={100} fmt={(v) => `${v}%`} onChange={setEquity} />
        <Stepper
          label="Target gold"
          value={a.target.gold}
          step={5}
          min={0}
          max={100 - a.target.equity}
          fmt={(v) => `${v}%`}
          onChange={(v) => set({ target: { ...a.target, gold: v, debt: 100 - a.target.equity - v } })}
        />
        <Text style={{ color: C.sub, fontSize: 12 }}>Debt target: {a.target.debt}% (the rest)</Text>
        <Stepper label="Savings a/c interest" value={a.savingsRate} step={0.005} min={0} max={0.1} fmt={(v) => `${(v * 100).toFixed(1)}%`} onChange={(v) => set({ savingsRate: v })} />
        <Stepper label="Liquid fund yield" value={a.liquidFundRate} step={0.005} min={0} max={0.12} fmt={(v) => `${(v * 100).toFixed(1)}%`} onChange={(v) => set({ liquidFundRate: v })} />
      </Card>

      <H>Privacy</H>
      <Card>
        <View>
          <Text style={{ color: C.sub, lineHeight: 20 }}>
            • Only SMS from business sender IDs (like AX-HDFCBK) are read. Messages from people are skipped inside the native
            code and never reach the app.{'\n'}• Everything is processed and stored on this phone. There is no account, server or
            analytics.{'\n'}• The only network call is fetching public mutual-fund NAVs from mfapi.in (scheme names only).{'\n'}•
            New alerts are picked up automatically every time you open the app.
          </Text>
        </View>
      </Card>
    </ScrollView>
  );
}
