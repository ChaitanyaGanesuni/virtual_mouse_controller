import { useState } from 'react';
import { Linking, Modal, Pressable, ScrollView, Share, Switch, Text, View } from 'react-native';

import { Button, C, Card, Chip, H, Label, Row } from '../components/ui';
import { inr } from '../lib/analysis';
import { maskSms } from '../lib/smsParser';
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
  const al = d.alertPrefs;
  const [showMissed, setShowMissed] = useState(false);
  const missed = d.ledger.missed;
  const shareMissed = () =>
    Share.share({
      title: 'Paisa Watch: unread bank alerts',
      message:
        'Bank alerts Paisa Watch could not read (numbers masked):\n\n' +
        missed
          .slice(0, 30)
          .map((m) => `[${m.address}] ${maskSms(m.body)}`)
          .join('\n\n'),
    });
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
        <Button label={d.loading ? 'Scanning…' : 'Re-scan everything'} onPress={() => d.refresh(true)} />
        {d.permission === 'denied' ? (
          <Button label="Open app settings to allow SMS" kind="ghost" onPress={() => Linking.openSettings()} />
        ) : null}
        <Row style={{ justifyContent: 'space-between', marginTop: 14 }}>
          <Text style={{ color: C.text }}>Use sample data</Text>
          <Switch value={d.demoMode} onValueChange={d.setDemoMode} thumbColor={d.demoMode ? C.accent : undefined} />
        </Row>
      </Card>

      <H>Alerts & reminders</H>
      <Card>
        {!d.notifications && d.source === 'sms' ? (
          <>
            <Text style={{ color: C.amber, marginBottom: 6 }}>Notifications are off for Paisa Watch, so alerts can't be shown.</Text>
            <Button label="Turn on notifications" kind="ghost" onPress={() => Linking.openSettings()} />
          </>
        ) : null}
        <Label>Notify me when a bank SMS arrives</Label>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 8 }}>
          <Chip label="Important only" active={al.mode === 'smart'} onPress={() => d.setAlertPrefs({ ...al, mode: 'smart' })} />
          <Chip label="Every transaction" active={al.mode === 'all'} onPress={() => d.setAlertPrefs({ ...al, mode: 'all' })} />
          <Chip label="Off" active={al.mode === 'off'} onPress={() => d.setAlertPrefs({ ...al, mode: 'off' })} />
        </View>
        <Text style={{ color: C.sub, fontSize: 12, lineHeight: 18 }}>
          Important = bank charges & penalties, card bills, recurring subscription charges, and anything over the amount below.
        </Text>
        <Stepper
          label="Alert for payments over"
          value={al.largeAmount}
          step={al.largeAmount >= 10000 ? 5000 : 1000}
          min={1000}
          max={100000}
          fmt={(v) => inr(v)}
          onChange={(v) => d.setAlertPrefs({ ...al, largeAmount: v })}
        />
        <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
          <Text style={{ color: C.text, flex: 1 }}>Card bill reminders (3 days before, day before, due day)</Text>
          <Switch value={al.billReminders} onValueChange={(v) => d.setAlertPrefs({ ...al, billReminders: v })} />
        </Row>
      </Card>

      <H>Alerts the app couldn't read</H>
      <Card>
        <Text style={{ color: C.sub, lineHeight: 20 }}>
          {missed.length
            ? `${missed.length} bank message(s) look like transactions but weren't understood, so they're missing from your totals.`
            : 'None. Every bank alert in your inbox was understood.'}
        </Text>
        {missed.length ? (
          <>
            <Button label="Review them" kind="ghost" onPress={() => setShowMissed(true)} />
            <Button label="Share (numbers masked) to get them supported" onPress={shareMissed} />
          </>
        ) : null}
      </Card>

      <Modal visible={showMissed} animationType="slide" onRequestClose={() => setShowMissed(false)}>
        <View style={{ flex: 1, backgroundColor: C.bg, padding: 16, paddingTop: 40 }}>
          <H>Unread alerts ({missed.length})</H>
          <ScrollView style={{ flex: 1 }}>
            {missed.slice(0, 100).map((m) => (
              <Card key={m.id}>
                <Text style={{ color: C.sub, fontSize: 12 }}>
                  {m.address} · {new Date(m.date).toLocaleDateString('en-IN')}
                </Text>
                <Text style={{ color: C.text, marginTop: 4 }}>{maskSms(m.body)}</Text>
              </Card>
            ))}
          </ScrollView>
          <Button label="Close" kind="ghost" onPress={() => setShowMissed(false)} />
        </View>
      </Modal>

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
            New alerts are picked up every time you open the app, and important ones arrive as notifications even when it's
            closed.{'\n'}• "Share" sends only the unread alerts you choose, with long numbers masked.
          </Text>
        </View>
      </Card>
    </ScrollView>
  );
}
