import { useMemo, useState } from 'react';
import { ScrollView, View, type LayoutChangeEvent } from 'react-native';

import { inr, isSpend } from '../lib/analysis';
import { budgetStatus, suggestBudgets } from '../lib/budgets';
import type { Forecast } from '../lib/forecast';
import type { WorthPoint } from '../lib/history';
import type { Transaction } from '../lib/types';
import type { BudgetPrefs } from '../store';
import { C, F, catMeta } from '../theme';
import { AnimatedNumber, FadeIn, PressScale } from './anim';
import { LineChart, Progress, Ring } from './charts';
import Icon from './Icon';
import { Button, Card, CategoryBubble, Label, Pill, Row, Section, Sheet, T } from './ui';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const short = (n: number) => {
  const a = Math.abs(n);
  const sign = n < 0 ? '−' : '';
  return a >= 1e7 ? `${sign}₹${(a / 1e7).toFixed(1)}Cr` : a >= 1e5 ? `${sign}₹${(a / 1e5).toFixed(1)}L` : a >= 1e3 ? `${sign}₹${(a / 1e3).toFixed(0)}k` : `${sign}${inr(a)}`;
};

// ---------------------------------------------------------------- forecast

export function ForecastCard({ f, index }: { f: Forecast; index: number }) {
  const end = new Date(f.monthEnd).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  const base = Math.max(f.expectedIncome, f.projectedSpend, 1);
  const positive = f.leftAtMonthEnd >= 0;
  return (
    <FadeIn index={index}>
      <Card>
        <Row style={{ justifyContent: 'space-between' }}>
          <Label>Forecast to {end}</Label>
          <Pill text={`${f.daysLeft} days left`} color={C.blue} icon="calendar" />
        </Row>
        <Row style={{ alignItems: 'flex-end', marginTop: 6 }}>
          <AnimatedNumber value={f.projectedSpend} format={inr} style={{ fontFamily: F.black, fontSize: 28, color: C.text }} />
          <T size={13} color={C.sub} style={{ marginLeft: 6, marginBottom: 5 }}>
            likely spend
          </T>
        </Row>
        {/* spent so far + projected rest, against expected income */}
        <View style={{ height: 12, borderRadius: 6, backgroundColor: C.cardHi, flexDirection: 'row', overflow: 'hidden', marginTop: 10 }}>
          <View style={{ width: `${(f.spentSoFar / base) * 100}%`, backgroundColor: C.green }} />
          <View style={{ width: `${(Math.max(0, f.projectedSpend - f.spentSoFar) / base) * 100}%`, backgroundColor: C.green + '55' }} />
        </View>
        <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
          <T size={11.5} color={C.sub}>
            {inr(f.spentSoFar)} spent
          </T>
          <T size={11.5} color={C.sub}>
            ~{inr(f.dailyRate)}/day everyday spending
          </T>
        </Row>
        {f.expectedIncome > 0 ? (
          <Row style={{ marginTop: 14, padding: 12, borderRadius: 14, backgroundColor: (positive ? C.green : C.red) + '14' }}>
            <Icon name={positive ? 'wallet' : 'alert'} size={20} color={positive ? C.green : C.red} />
            <T size={13.5} weight="semibold" color={positive ? C.green : C.red} style={{ marginLeft: 10, flex: 1 }}>
              {positive
                ? `You'll have about ${inr(f.leftAtMonthEnd)} left after spending and investing`
                : `On this pace you'll overspend by ${inr(-f.leftAtMonthEnd)}`}
            </T>
          </Row>
        ) : null}
        {f.upcoming.length ? (
          <View style={{ marginTop: 12 }}>
            <T size={12} weight="semibold" color={C.sub} style={{ marginBottom: 4 }}>
              STILL TO COME THIS MONTH
            </T>
            {f.upcoming.slice(0, 4).map((u) => (
              <Row key={u.merchant + u.date} style={{ paddingVertical: 6 }}>
                <CategoryBubble category={u.category} size={30} />
                <T size={13.5} style={{ flex: 1, marginLeft: 10 }} lines={1}>
                  {u.merchant}
                </T>
                <T size={12} color={C.sub} style={{ marginRight: 10 }}>
                  {new Date(u.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}
                </T>
                <T size={13.5} weight="bold">
                  {inr(u.amount)}
                </T>
              </Row>
            ))}
          </View>
        ) : null}
      </Card>
    </FadeIn>
  );
}

// ---------------------------------------------------------------- budgets

export function BudgetsCard({
  txns,
  budgets,
  onSave,
  index,
}: {
  txns: Transaction[];
  budgets: BudgetPrefs;
  onSave: (b: BudgetPrefs) => void;
  index: number;
}) {
  const [editing, setEditing] = useState(false);
  const status = budgetStatus(txns, budgets.categories);
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  const totalSpent = txns.filter((t) => isSpend(t) && t.date >= start).reduce((s, t) => s + t.amount, 0);
  const has = status.length > 0 || budgets.total > 0;

  return (
    <>
      <Section title="Budgets" action={has ? 'Edit' : undefined} onAction={() => setEditing(true)} />
      <FadeIn index={index}>
        {!has ? (
          <Card>
            <Row style={{ alignItems: 'flex-start' }}>
              <View style={{ width: 46, height: 46, borderRadius: 16, backgroundColor: C.green + '22', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="pie" size={22} color={C.green} />
              </View>
              <View style={{ flex: 1, marginLeft: 12 }}>
                <T size={15} weight="bold">
                  Set monthly budgets
                </T>
                <T size={13} color={C.sub}>
                  Get an alert at 80% and 100%. Suggestions are based on your last 3 months, trimmed a little on the fun stuff.
                </T>
              </View>
            </Row>
            <Button
              label="Use smart suggestions"
              icon="sparkle"
              onPress={() => {
                const cats = suggestBudgets(txns);
                const total = Math.ceil((Object.values(cats).reduce((s, v) => s + v, 0) * 1.1) / 1000) * 1000;
                onSave({ categories: cats, total });
              }}
            />
            <Button label="Set my own" kind="ghost" icon="sliders" onPress={() => setEditing(true)} />
          </Card>
        ) : (
          <Card>
            {budgets.total > 0 ? (
              <View style={{ marginBottom: status.length ? 16 : 0 }}>
                <Row style={{ justifyContent: 'space-between', marginBottom: 6 }}>
                  <T size={14} weight="semibold">
                    Monthly limit
                  </T>
                  <T size={13} color={C.sub}>
                    {inr(totalSpent)} / {inr(budgets.total)}
                  </T>
                </Row>
                <Progress value={totalSpent / budgets.total} color={totalSpent >= budgets.total ? C.red : totalSpent >= budgets.total * 0.8 ? C.amber : C.green} height={10} />
                <T size={11.5} color={C.faint} style={{ marginTop: 4 }}>
                  Alerts arrive the moment a payment crosses 80% or 100%.
                </T>
              </View>
            ) : null}
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginHorizontal: -6 }}>
              {status.map((b) => {
                const left = b.limit - b.spent;
                return (
                  <PressScale key={b.category} onPress={() => setEditing(true)} style={{ width: 92, alignItems: 'center', marginHorizontal: 6 }}>
                    <Ring pct={b.pct} size={66}>
                      <Icon name={catMeta(b.category).icon} size={22} color={catMeta(b.category).color} />
                    </Ring>
                    <T size={12} weight="semibold" lines={1} style={{ marginTop: 6 }}>
                      {b.category}
                    </T>
                    <T size={11.5} color={left < 0 ? C.red : C.sub}>
                      {left < 0 ? `${inr(-left)} over` : `${inr(left)} left`}
                    </T>
                  </PressScale>
                );
              })}
            </ScrollView>
          </Card>
        )}
      </FadeIn>
      <BudgetEditor visible={editing} onClose={() => setEditing(false)} txns={txns} budgets={budgets} onSave={onSave} />
    </>
  );
}

function Step({ value, step, onChange }: { value: number; step: number; onChange: (v: number) => void }) {
  const b = (label: string, v: number) => (
    <PressScale
      onPress={() => onChange(Math.max(0, v))}
      style={{ width: 32, height: 32, borderRadius: 11, backgroundColor: C.cardHi, alignItems: 'center', justifyContent: 'center' }}
    >
      <T size={18} weight="bold" color={C.accent}>
        {label}
      </T>
    </PressScale>
  );
  return (
    <Row>
      {b('−', value - step)}
      <T size={13.5} weight="bold" style={{ minWidth: 76, textAlign: 'center' }}>
        {value > 0 ? inr(value) : 'Off'}
      </T>
      {b('+', value + step)}
    </Row>
  );
}

function BudgetEditor({
  visible,
  onClose,
  txns,
  budgets,
  onSave,
}: {
  visible: boolean;
  onClose: () => void;
  txns: Transaction[];
  budgets: BudgetPrefs;
  onSave: (b: BudgetPrefs) => void;
}) {
  const suggested = useMemo(() => suggestBudgets(txns), [txns]);
  const [draft, setDraft] = useState<BudgetPrefs>(budgets);
  const [opened, setOpened] = useState(false);
  if (visible && !opened) {
    setOpened(true);
    setDraft(budgets);
  }
  if (!visible && opened) setOpened(false);
  const cats = [...new Set([...Object.keys(suggested), ...Object.keys(draft.categories)])].sort(
    (a, b) => (suggested[b] ?? draft.categories[b] ?? 0) - (suggested[a] ?? draft.categories[a] ?? 0),
  );
  return (
    <Sheet visible={visible} onClose={onClose} title="Monthly budgets">
      <ScrollView>
        <Row style={{ paddingVertical: 10, borderBottomWidth: 0.5, borderBottomColor: C.border }}>
          <View style={{ flex: 1 }}>
            <T size={14.5} weight="bold">
              Overall limit
            </T>
            <T size={12} color={C.sub}>
              Real-time alerts at 80% and 100%
            </T>
          </View>
          <Step value={draft.total} step={draft.total >= 50000 ? 5000 : 1000} onChange={(total) => setDraft({ ...draft, total })} />
        </Row>
        {cats.map((c) => (
          <Row key={c} style={{ paddingVertical: 9 }}>
            <CategoryBubble category={c} size={34} />
            <View style={{ flex: 1, marginLeft: 10 }}>
              <T size={14} weight="semibold" lines={1}>
                {c}
              </T>
              {suggested[c] ? (
                <T size={11.5} color={C.faint}>
                  suggested {inr(suggested[c])}
                </T>
              ) : null}
            </View>
            <Step
              value={draft.categories[c] ?? 0}
              step={500}
              onChange={(v) => {
                const categories = { ...draft.categories };
                if (v > 0) categories[c] = v;
                else delete categories[c];
                setDraft({ ...draft, categories });
              }}
            />
          </Row>
        ))}
        <Row style={{ gap: 10 }}>
          <Button
            label="Suggestions"
            icon="sparkle"
            kind="ghost"
            style={{ flex: 1 }}
            onPress={() =>
              setDraft({
                categories: suggested,
                total: Math.ceil((Object.values(suggested).reduce((s, v) => s + v, 0) * 1.1) / 1000) * 1000,
              })
            }
          />
          <Button
            label="Save"
            icon="check"
            style={{ flex: 1 }}
            onPress={() => {
              onSave(draft);
              onClose();
            }}
          />
        </Row>
        <PressScale onPress={() => setDraft({ categories: {}, total: 0 })} style={{ alignSelf: 'center', padding: 12 }}>
          <T size={13} color={C.red} weight="semibold">
            Turn off all budgets
          </T>
        </PressScale>
      </ScrollView>
    </Sheet>
  );
}

// ---------------------------------------------------------------- net worth trend

export function NetWorthTrend({ points, index }: { points: WorthPoint[]; index: number }) {
  const [w, setW] = useState(0);
  if (points.length < 2) return null;
  const first = points[0];
  const last = points[points.length - 1];
  const delta = last.net - first.net;
  const pct = first.net !== 0 ? (delta / Math.abs(first.net)) * 100 : 0;
  const m = (t: number) => MONTHS[new Date(t).getMonth()];
  return (
    <>
      <Section title="Net worth trend" />
      <FadeIn index={index}>
        <Card>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Label>Since {m(first.date)} {new Date(first.date).getFullYear()}</Label>
              <T size={22} weight="black" color={delta >= 0 ? C.green : C.red} style={{ marginTop: 2 }}>
                {delta >= 0 ? '+' : ''}
                {short(delta)}
              </T>
            </View>
            {Number.isFinite(pct) && first.net > 0 ? (
              <Pill text={`${pct >= 0 ? '+' : ''}${pct.toFixed(0)}%`} color={delta >= 0 ? C.green : C.red} icon={delta >= 0 ? 'arrowUp' : 'arrowDown'} />
            ) : null}
          </Row>
          <View style={{ marginTop: 14, marginHorizontal: -6 }} onLayout={(e: LayoutChangeEvent) => setW(e.nativeEvent.layout.width)}>
            <LineChart values={points.map((p) => p.net)} width={w} height={130} color={delta >= 0 ? C.green : C.red} />
          </View>
          <Row style={{ justifyContent: 'space-between', marginTop: 4 }}>
            {points.map((p, i) =>
              i % Math.ceil(points.length / 6) === 0 || i === points.length - 1 ? (
                <T key={p.date} size={10.5} color={i === points.length - 1 ? C.text : C.faint}>
                  {i === points.length - 1 ? 'Now' : m(p.date)}
                </T>
              ) : null,
            )}
          </Row>
          <T size={11.5} color={C.faint} style={{ marginTop: 8 }}>
            Rebuilt from balances in your bank SMS, card statements and fund purchases at each month end.
          </T>
        </Card>
      </FadeIn>
    </>
  );
}
