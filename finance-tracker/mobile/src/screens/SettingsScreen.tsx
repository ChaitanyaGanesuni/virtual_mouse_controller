import { useEffect, useState, type ReactNode } from 'react';
import { Linking, ScrollView, Share, Switch, View } from 'react-native';

import { FadeIn, PressScale, tap } from '../components/anim';
import { canUseDeviceLock, verifyOwner } from '../components/guards';
import Segmented from '../components/Segmented';
import { exportBackup, importBackup } from '../backup';
import { clearErrors, formatErrors, getErrors, logError, type LoggedError } from '../errorLog';
import Icon, { type IconName } from '../components/Icon';
import { ShieldArt } from '../components/Illustrations';
import { Button, Card, IconBubble, Label, Pill, Row, Section, Sheet, T } from '../components/ui';
import { inr } from '../lib/analysis';
import type { Assumptions } from '../lib/investments';
import { maskSms } from '../lib/smsParser';
import type { AlertPrefs } from '../store';
import { useData } from '../store';
import { C, F } from '../theme';

function SettingRow({ icon, color, title, sub, right, last }: {
  icon: IconName;
  color: string;
  title: string;
  sub?: string;
  right?: ReactNode;
  last?: boolean;
}) {
  return (
    <Row style={{ paddingVertical: 12, borderBottomWidth: last ? 0 : 0.5, borderBottomColor: C.border }}>
      <IconBubble icon={icon} color={color} size={36} />
      <View style={{ flex: 1, marginLeft: 12, marginRight: 8 }}>
        <T size={14.5} weight="semibold">
          {title}
        </T>
        {sub ? (
          <T size={12} color={C.sub}>
            {sub}
          </T>
        ) : null}
      </View>
      {right}
    </Row>
  );
}

function Stepper({ value, step, min, max, fmt, onChange }: {
  value: number;
  step: number;
  min: number;
  max: number;
  fmt: (v: number) => string;
  onChange: (v: number) => void;
}) {
  const btn = (icon: string, v: number) => (
    <PressScale
      onPress={() => onChange(Math.min(max, Math.max(min, Math.round(v * 1000) / 1000)))}
      style={{ width: 32, height: 32, borderRadius: 11, backgroundColor: C.cardHi, alignItems: 'center', justifyContent: 'center' }}
    >
      <T size={18} weight="bold" color={C.green}>
        {icon}
      </T>
    </PressScale>
  );
  return (
    <Row>
      {btn('−', value - step)}
      <T size={14} weight="bold" style={{ minWidth: 64, textAlign: 'center' }}>
        {fmt(value)}
      </T>
      {btn('+', value + step)}
    </Row>
  );
}

const sw = { trackColor: { false: C.cardHi, true: C.greenDeep }, thumbColor: '#fff' } as const;

export default function SettingsScreen() {
  const d = useData();
  const a = d.assumptions;
  const al = d.alertPrefs;
  const [showMissed, setShowMissed] = useState(false);
  const [errors, setErrors] = useState<LoggedError[]>([]);
  const [lockMsg, setLockMsg] = useState<string | null>(null);
  const [backupMsg, setBackupMsg] = useState<string | null>(null);
  useEffect(() => {
    getErrors().then(setErrors);
  }, [d.lastSync]);
  const toggleLock = async (on: boolean) => {
    tap();
    setLockMsg(null);
    if (on) {
      if (!(await canUseDeviceLock())) {
        setLockMsg('Set up a fingerprint, face unlock or screen-lock PIN on your phone first.');
        return;
      }
      if (!(await verifyOwner('Confirm to turn on app lock'))) return;
    }
    d.setAppLock(on);
  };
  const missed = d.ledger.missed;
  const setAl = (p: Partial<AlertPrefs>) => d.setAlertPrefs({ ...al, ...p });
  const set = (patch: Partial<Assumptions>) => d.setAssumptions({ ...a, ...patch });
  const setEquity = (eq: number) => {
    const rest = 100 - eq;
    const gold = Math.min(a.target.gold, rest);
    set({ target: { equity: eq, debt: rest - gold, gold } });
  };
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

  return (
    <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 120 }}>
      <FadeIn index={0}>
        <Card>
          <Row>
            <View style={{ width: 52, height: 52, borderRadius: 18, backgroundColor: C.green + '22', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name={d.source === 'sms' ? 'message' : d.source === 'demo' ? 'sparkle' : 'lock'} size={26} color={C.green} />
            </View>
            <View style={{ flex: 1, marginLeft: 14 }}>
              <T size={16} weight="bold">
                {d.source === 'sms' ? 'Reading bank alerts' : d.source === 'demo' ? 'Sample data' : 'Not connected'}
              </T>
              <T size={12.5} color={C.sub}>
                {d.smsCount} messages · last scan {d.lastSync ? new Date(d.lastSync).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' }) : '—'}
              </T>
            </View>
            <Pill
              text={d.source === 'demo' ? 'Demo' : d.permission === 'granted' ? 'Allowed' : d.permission === 'denied' ? 'Blocked' : 'Checking'}
              color={d.source === 'demo' ? C.amber : d.permission === 'granted' ? C.green : C.amber}
            />
          </Row>
          {d.error ? (
            <T size={12.5} color={C.red} style={{ marginTop: 10 }}>
              {d.error}
            </T>
          ) : null}
          <Button label={d.loading ? 'Scanning…' : 'Re-scan everything'} icon="refresh" kind="ghost" onPress={() => d.refresh(true)} />
          {d.permission === 'denied' ? <Button label="Allow SMS in app settings" icon="sliders" onPress={() => Linking.openSettings()} /> : null}
          <View style={{ marginTop: 6 }}>
            <SettingRow
              icon="sparkle"
              color={C.amber}
              title="Use sample data"
              sub="Explore the app with realistic demo transactions"
              last
              right={<Switch value={d.demoMode} onValueChange={(v) => { tap(); d.setDemoMode(v); }} {...sw} />}
            />
          </View>
        </Card>
      </FadeIn>

      <Section title="Alerts & reminders" />
      <FadeIn index={1}>
        <Card>
          {!d.notifications && d.source === 'sms' ? (
            <Row style={{ backgroundColor: C.amber + '1A', borderRadius: 12, padding: 10, marginBottom: 10 }}>
              <Icon name="bell" size={16} color={C.amber} />
              <T size={12.5} color={C.amber} style={{ flex: 1, marginLeft: 8 }}>
                Notifications are off, so alerts can't be shown.
              </T>
              <PressScale onPress={() => Linking.openSettings()}>
                <T size={12.5} weight="bold" color={C.amber}>
                  Turn on
                </T>
              </PressScale>
            </Row>
          ) : null}
          <Label>When a bank SMS arrives</Label>
          <Segmented
            value={al.mode}
            onChange={(mode) => setAl({ mode })}
            options={[
              { value: 'smart', label: 'Important' },
              { value: 'all', label: 'Everything' },
              { value: 'off', label: 'Off' },
            ]}
          />
          <T size={12} color={C.sub} style={{ marginTop: 8, marginBottom: 4 }}>
            {al.mode === 'smart'
              ? 'Fees & penalties, card bills, subscription charges, and big payments.'
              : al.mode === 'all'
                ? 'A notification for every debit and credit.'
                : 'No transaction notifications.'}
          </T>
          <SettingRow
            icon="bolt"
            color={C.orange}
            title="Big payment alert"
            sub="Notify for payments above"
            right={<Stepper value={al.largeAmount} step={al.largeAmount >= 10000 ? 5000 : 1000} min={1000} max={100000} fmt={inr} onChange={(v) => setAl({ largeAmount: v })} />}
          />
          <SettingRow
            icon="calendar"
            color={C.blue}
            title="Card bill reminders"
            sub="3 days before, day before, due day"
            right={<Switch value={al.billReminders} onValueChange={(v) => { tap(); setAl({ billReminders: v }); }} {...sw} />}
          />
          <SettingRow
            icon="message"
            color={C.violet}
            title="Weekly check-in"
            sub="Sunday 7 pm: your week, bills ahead, one tip"
            last
            right={<Switch value={d.extras.digest} onValueChange={(v) => { tap(); d.setExtra('digest', v); }} {...sw} />}
          />
        </Card>
      </FadeIn>

      <Section title="Unread alerts" />
      <FadeIn index={2}>
        <Card>
          <Row>
            <IconBubble icon={missed.length ? 'eye' : 'check'} color={missed.length ? C.amber : C.green} size={40} />
            <T size={13.5} color={C.sub} style={{ flex: 1, marginLeft: 12 }}>
              {missed.length
                ? `${missed.length} bank message${missed.length > 1 ? 's' : ''} looked like transactions but couldn't be read, so they're not in your totals.`
                : 'Every bank alert in your inbox was understood.'}
            </T>
          </Row>
          {missed.length ? (
            <Row style={{ gap: 10 }}>
              <Button label="Review" icon="eye" kind="ghost" style={{ flex: 1 }} onPress={() => setShowMissed(true)} />
              <Button label="Share" icon="share" style={{ flex: 1 }} onPress={shareMissed} />
            </Row>
          ) : null}
        </Card>
      </FadeIn>

      <Section title="Investment goals" />
      <FadeIn index={3}>
        <Card>
          <SettingRow icon="shield" color={C.teal} title="Emergency fund" sub="Months of spending to keep in bank" right={<Stepper value={a.emergencyFundMonths} step={1} min={1} max={24} fmt={(v) => `${v} mo`} onChange={(v) => set({ emergencyFundMonths: v })} />} />
          <SettingRow icon="trend" color={C.blue} title="Target equity" right={<Stepper value={a.target.equity} step={5} min={0} max={100} fmt={(v) => `${v}%`} onChange={setEquity} />} />
          <SettingRow
            icon="sparkle"
            color={C.amber}
            title="Target gold"
            sub={`Debt gets the rest: ${a.target.debt}%`}
            right={<Stepper value={a.target.gold} step={5} min={0} max={100 - a.target.equity} fmt={(v) => `${v}%`} onChange={(v) => set({ target: { ...a.target, gold: v, debt: 100 - a.target.equity - v } })} />}
          />
          <SettingRow icon="bank" color={C.sub} title="Savings a/c interest" right={<Stepper value={a.savingsRate} step={0.005} min={0} max={0.1} fmt={(v) => `${(v * 100).toFixed(1)}%`} onChange={(v) => set({ savingsRate: v })} />} />
          <SettingRow icon="percent" color={C.green} title="Liquid fund yield" last right={<Stepper value={a.liquidFundRate} step={0.005} min={0} max={0.12} fmt={(v) => `${(v * 100).toFixed(1)}%`} onChange={(v) => set({ liquidFundRate: v })} />} />
        </Card>
      </FadeIn>

      <Section title="Security" />
      <FadeIn index={4}>
        <Card>
          <SettingRow
            icon="lock"
            color={C.violet}
            title="App lock"
            sub="Fingerprint, face or PIN when opening, and after 30 s away"
            right={<Switch value={d.appLock} onValueChange={toggleLock} {...sw} />}
          />
          <SettingRow
            icon="eye"
            color={C.teal}
            title="Hide in recent apps"
            sub={d.appLock ? 'Blank preview in the app switcher; also blocks screenshots' : 'Works together with app lock'}
            last
            right={<Switch disabled={!d.appLock} value={d.appLock && d.extras.secure} onValueChange={(v) => { tap(); d.setExtra('secure', v); }} {...sw} />}
          />
          {lockMsg ? (
            <T size={12.5} color={C.amber} style={{ marginTop: 6 }}>
              {lockMsg}
            </T>
          ) : null}
        </Card>
      </FadeIn>

      <Section title="Backup & restore" />
      <FadeIn index={4}>
        <Card>
          <T size={13} color={C.sub}>
            Saves your category fixes, budgets, goals, subscriptions and settings to a file you keep (Google Drive, email…).
            Transactions aren't in it: they're rebuilt from SMS on the new phone.
          </T>
          <Row style={{ gap: 10 }}>
            <Button
              label="Back up"
              icon="share"
              style={{ flex: 1 }}
              onPress={async () => {
                setBackupMsg(null);
                try {
                  await exportBackup();
                } catch (e) {
                  logError('backup', e);
                  setBackupMsg("Couldn't create the backup on this device.");
                }
              }}
            />
            <Button
              label="Restore"
              icon="undo"
              kind="ghost"
              style={{ flex: 1 }}
              onPress={async () => {
                setBackupMsg(null);
                try {
                  const n = await importBackup();
                  if (n == null) return;
                  await d.reloadAll();
                  setBackupMsg(`Restored ${n} settings.`);
                } catch (e) {
                  setBackupMsg(e instanceof Error ? e.message : String(e));
                }
              }}
            />
          </Row>
          {backupMsg ? (
            <T size={12.5} color={backupMsg.startsWith('Restored') ? C.green : C.amber} style={{ marginTop: 8 }}>
              {backupMsg}
            </T>
          ) : null}
        </Card>
      </FadeIn>

      <Section title="Problem log" />
      <FadeIn index={4}>
        <Card>
          <Row>
            <IconBubble icon={errors.length ? 'alert' : 'check'} color={errors.length ? C.amber : C.green} size={40} />
            <T size={13.5} color={C.sub} style={{ flex: 1, marginLeft: 12 }}>
              {errors.length
                ? `${errors.length} problem${errors.length > 1 ? 's' : ''} recorded on this phone (last: ${new Date(errors[0].at).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}). Sharing the log helps get them fixed.`
                : 'No problems recorded. If something ever breaks, details are saved here (on this phone only).'}
            </T>
          </Row>
          {errors.length ? (
            <Row style={{ gap: 10 }}>
              <Button
                label="Clear"
                icon="x"
                kind="ghost"
                style={{ flex: 1 }}
                onPress={async () => {
                  await clearErrors();
                  setErrors([]);
                }}
              />
              <Button
                label="Share"
                icon="share"
                style={{ flex: 1 }}
                onPress={() => Share.share({ title: 'Paisa Watch problem log', message: 'Paisa Watch problem log (numbers masked):\n\n' + formatErrors(errors) })}
              />
            </Row>
          ) : null}
        </Card>
      </FadeIn>

      <Section title="Privacy" />
      <FadeIn index={4}>
        <Card>
          <Row style={{ alignItems: 'flex-start' }}>
            <ShieldArt size={84} />
            <View style={{ flex: 1, marginLeft: 12 }}>
              {[
                'Only bank & fund-house senders (like AX-HDFCBK) are read. Personal chats never reach the app.',
                'Everything stays on this phone: no account, no server, no analytics.',
                'The only network call fetches public mutual-fund prices.',
                'Sharing unread alerts masks account and reference numbers.',
              ].map((t) => (
                <Row key={t} style={{ alignItems: 'flex-start', marginBottom: 8 }}>
                  <Icon name="check" size={14} color={C.green} stroke={3} />
                  <T size={12.5} color={C.sub} style={{ flex: 1, marginLeft: 8 }}>
                    {t}
                  </T>
                </Row>
              ))}
            </View>
          </Row>
        </Card>
      </FadeIn>

      <T size={11} color={C.faint} style={{ textAlign: 'center', marginTop: 8, fontFamily: F.medium }}>
        Paisa Watch 4.0
      </T>

      <Sheet visible={showMissed} onClose={() => setShowMissed(false)} title={`Unread alerts (${missed.length})`}>
        <ScrollView>
          {missed.slice(0, 100).map((m) => (
            <View key={m.id} style={{ backgroundColor: C.card, borderRadius: 14, padding: 12, marginBottom: 8 }}>
              <T size={11.5} color={C.faint}>
                {m.address} · {new Date(m.date).toLocaleDateString('en-IN')}
              </T>
              <T size={13} style={{ marginTop: 4 }}>
                {maskSms(m.body)}
              </T>
            </View>
          ))}
          <Button label="Share all (numbers masked)" icon="share" onPress={shareMissed} />
        </ScrollView>
      </Sheet>
    </ScrollView>
  );
}
