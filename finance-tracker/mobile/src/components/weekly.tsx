import { useState } from 'react';
import { TextInput, View } from 'react-native';

import { inr } from '../lib/analysis';
import type { Digest } from '../lib/digest';
import type { Goal, GoalProgress } from '../lib/goals';
import { useData } from '../store';
import { C, F, catMeta } from '../theme';
import { FadeIn, PressScale } from './anim';
import { Ring } from './charts';
import Icon, { type IconName } from './Icon';
import { Button, Card, Chip, Label, Pill, Row, Section, Sheet, T } from './ui';

const fmt = (t: number) => new Date(t).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });

// ---------------------------------------------------------------- protection banner

export function GuardBanner({ go }: { go: (t: string) => void }) {
  const d = useData();
  const overdue = d.failedPayments.filter((f) => f.status === 'overdue');
  const waiting = d.failedPayments.filter((f) => f.status === 'waiting');
  const n = d.signals.length + overdue.length;
  if (!n && !waiting.length) return null;
  const urgent = n > 0;
  const text = urgent
    ? [d.signals.length ? `${d.signals.length} unusual payment${d.signals.length > 1 ? 's' : ''}` : '', overdue.length ? `${overdue.length} overdue refund${overdue.length > 1 ? 's' : ''}` : '']
        .filter(Boolean)
        .join(' · ')
    : `${inr(waiting.reduce((s, f) => s + f.amount, 0))} from a failed payment is on its way back`;
  return (
    <FadeIn>
      <PressScale onPress={() => go('insights:guard')}>
        <Row style={{ backgroundColor: (urgent ? C.red : C.blue) + '1A', borderRadius: 16, padding: 14, marginBottom: 12, borderWidth: 0.5, borderColor: (urgent ? C.red : C.blue) + '55' }}>
          <Icon name={urgent ? 'shield' : 'calendar'} size={22} color={urgent ? C.red : C.blue} />
          <View style={{ flex: 1, marginLeft: 12 }}>
            <T size={14} weight="bold" color={urgent ? C.red : C.blue}>
              {urgent ? 'Check your recent payments' : 'Refund being tracked'}
            </T>
            <T size={12.5} color={C.sub}>
              {text}
            </T>
          </View>
          <Icon name="chevronRight" size={20} color={C.sub} />
        </Row>
      </PressScale>
    </FadeIn>
  );
}

// ---------------------------------------------------------------- weekly digest

export function DigestCard({ dg, index }: { dg: Digest; index: number }) {
  const up = dg.change != null && dg.change > 0.05;
  return (
    <>
      <Section title="This week" />
      <FadeIn index={index}>
        <Card>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Label>Last 7 days</Label>
              <T size={24} weight="black" style={{ marginTop: 2 }}>
                {inr(dg.spent)}
              </T>
            </View>
            {dg.change != null ? (
              <Pill text={`Everyday ${dg.change >= 0 ? '+' : ''}${Math.round(dg.change * 100)}% vs last week`} color={up ? C.red : C.green} icon={dg.change >= 0 ? 'arrowUp' : 'arrowDown'} />
            ) : null}
          </Row>
          <View style={{ marginTop: 10 }}>
            {dg.topCategory ? (
              <Row style={{ paddingVertical: 5 }}>
                <Icon name={catMeta(dg.topCategory.category).icon} size={16} color={catMeta(dg.topCategory.category).color} />
                <T size={13} color={C.sub} style={{ marginLeft: 8, flex: 1 }}>
                  Most on {dg.topCategory.category}
                </T>
                <T size={13} weight="semibold">
                  {inr(dg.topCategory.amount)}
                </T>
              </Row>
            ) : null}
            {dg.biggest ? (
              <Row style={{ paddingVertical: 5 }}>
                <Icon name="arrowUp" size={16} color={C.orange} />
                <T size={13} color={C.sub} style={{ marginLeft: 8, flex: 1 }} lines={1}>
                  Biggest: {dg.biggest.merchant || dg.biggest.category}
                </T>
                <T size={13} weight="semibold">
                  {inr(dg.biggest.amount)}
                </T>
              </Row>
            ) : null}
            {dg.dueSoon.map((b) => (
              <Row key={b.name + b.date} style={{ paddingVertical: 5 }}>
                <Icon name="calendar" size={16} color={C.blue} />
                <T size={13} color={C.sub} style={{ marginLeft: 8, flex: 1 }} lines={1}>
                  Due {fmt(b.date)}: {b.name}
                </T>
                <T size={13} weight="semibold">
                  {inr(b.amount)}
                </T>
              </Row>
            ))}
            {dg.tip ? (
              <Row style={{ marginTop: 8, backgroundColor: C.green + '14', padding: 10, borderRadius: 12 }}>
                <Icon name="sparkle" size={14} color={C.green} fill={C.green} />
                <T size={12.5} color={C.green} style={{ marginLeft: 8, flex: 1 }}>
                  Tip: {dg.tip}
                </T>
              </Row>
            ) : null}
          </View>
        </Card>
      </FadeIn>
    </>
  );
}

// ---------------------------------------------------------------- goals

const GOAL_ICONS: { icon: Goal['icon']; label: string }[] = [
  { icon: 'shield', label: 'Emergency' },
  { icon: 'plane', label: 'Trip' },
  { icon: 'home', label: 'Home' },
  { icon: 'car', label: 'Vehicle' },
  { icon: 'book', label: 'Education' },
  { icon: 'heart', label: 'Wedding' },
  { icon: 'gift', label: 'Gadget' },
  { icon: 'sparkle', label: 'Other' },
];

export function GoalsCard({ index }: { index: number }) {
  const d = useData();
  const [adding, setAdding] = useState(false);
  const netNow = d.history.length ? d.history[d.history.length - 1].net : 0;
  return (
    <>
      <Section title="Goals" action={d.goals.length ? 'Add' : undefined} onAction={() => setAdding(true)} />
      <FadeIn index={index}>
        {d.goals.length === 0 ? (
          <Card>
            <Row style={{ alignItems: 'flex-start' }}>
              <View style={{ width: 46, height: 46, borderRadius: 16, backgroundColor: C.violet + '22', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="sparkle" size={22} color={C.violet} />
              </View>
              <View style={{ flex: 1, marginLeft: 12 }}>
                <T size={15} weight="bold">
                  Save for something
                </T>
                <T size={13} color={C.sub}>
                  Set a target and date. Progress fills up as your net worth grows, and we'll tell you if you're on track.
                </T>
              </View>
            </Row>
            <Button label="Add a goal" icon="sparkle" onPress={() => setAdding(true)} />
          </Card>
        ) : (
          d.goals.map((p) => <GoalRow key={p.goal.id} p={p} onRemove={() => d.setExtra('goals', d.extras.goals.filter((g) => g.id !== p.goal.id))} />)
        )}
      </FadeIn>
      <GoalEditor
        visible={adding}
        onClose={() => setAdding(false)}
        onSave={(g) => d.setExtra('goals', [...d.extras.goals, { ...g, id: String(Date.now()), createdAt: Date.now(), startNet: netNow }])}
      />
    </>
  );
}

function GoalRow({ p, onRemove }: { p: GoalProgress; onRemove: () => void }) {
  const [confirm, setConfirm] = useState(false);
  return (
    <Card>
      <Row>
        <Ring pct={p.pct} size={60} stroke={6}>
          <Icon name={p.goal.icon as IconName} size={20} color={p.done ? C.green : C.violet} />
        </Ring>
        <View style={{ flex: 1, marginLeft: 14 }}>
          <Row style={{ justifyContent: 'space-between' }}>
            <T size={15} weight="bold" lines={1} style={{ flex: 1 }}>
              {p.goal.name}
            </T>
            <Pill text={p.done ? 'Done 🎉' : p.onTrack ? 'On track' : 'Behind'} color={p.done || p.onTrack ? C.green : C.amber} />
          </Row>
          <T size={13} color={C.sub}>
            {inr(p.saved)} of {inr(p.goal.target)} · by {new Date(p.goal.by).toLocaleDateString('en-IN', { month: 'short', year: 'numeric' })}
          </T>
          {!p.done ? (
            <T size={12} color={p.onTrack ? C.faint : C.amber}>
              Needs {inr(p.needPerMonth)}/month for {Math.max(1, Math.round(p.monthsLeft))} more month{Math.round(p.monthsLeft) === 1 ? '' : 's'}
            </T>
          ) : null}
        </View>
        <PressScale onPress={() => (confirm ? onRemove() : setConfirm(true))} style={{ padding: 6 }}>
          <Icon name={confirm ? 'check' : 'x'} size={16} color={confirm ? C.red : C.faint} />
        </PressScale>
      </Row>
    </Card>
  );
}

function GoalEditor({ visible, onClose, onSave }: { visible: boolean; onClose: () => void; onSave: (g: Pick<Goal, 'name' | 'target' | 'by' | 'icon'>) => void }) {
  const [icon, setIcon] = useState<Goal['icon']>('plane');
  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [months, setMonths] = useState(12);
  const target = parseInt(amount.replace(/[^\d]/g, ''), 10) || 0;
  const label = GOAL_ICONS.find((g) => g.icon === icon)!.label;
  const input = { color: C.text, fontFamily: F.semibold, fontSize: 16, backgroundColor: C.card, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 11, marginTop: 6, borderWidth: 0.5, borderColor: C.border } as const;
  return (
    <Sheet visible={visible} onClose={onClose} title="New goal">
      <View>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
          {GOAL_ICONS.map((g) => (
            <Chip key={g.icon} label={g.label} icon={g.icon as IconName} active={g.icon === icon} onPress={() => setIcon(g.icon)} />
          ))}
        </View>
        <Label>Name</Label>
        <TextInput value={name} onChangeText={setName} placeholder={`${label} fund`} placeholderTextColor={C.faint} style={input} />
        <View style={{ height: 12 }} />
        <Label>Target amount (₹)</Label>
        <TextInput value={amount} onChangeText={setAmount} keyboardType="number-pad" placeholder="e.g. 60000" placeholderTextColor={C.faint} style={input} />
        <View style={{ height: 12 }} />
        <Label>By when</Label>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 8 }}>
          {[3, 6, 12, 24, 36, 60].map((m) => (
            <Chip key={m} label={m < 12 ? `${m} months` : `${m / 12} year${m > 12 ? 's' : ''}`} active={m === months} onPress={() => setMonths(m)} />
          ))}
        </View>
        {target > 0 ? (
          <T size={13} color={C.green} weight="semibold" style={{ marginTop: 4 }}>
            About {inr(target / months)} a month
          </T>
        ) : null}
        <Button
          label="Add goal"
          icon="check"
          onPress={() => {
            if (target <= 0) return;
            onSave({ name: name.trim() || `${label} fund`, target, by: Date.now() + months * 30.44 * 86_400_000, icon });
            setName('');
            setAmount('');
            onClose();
          }}
        />
      </View>
    </Sheet>
  );
}
