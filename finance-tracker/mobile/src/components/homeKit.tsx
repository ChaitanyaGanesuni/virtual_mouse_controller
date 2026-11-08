import { useEffect, useRef, useState } from 'react';
import { Animated, Easing, LayoutAnimation, ScrollView, useWindowDimensions, View, type LayoutChangeEvent } from 'react-native';
import Svg, { Path } from 'react-native-svg';

import { inr } from '../lib/analysis';
import { budgetStatus } from '../lib/budgets';
import type { Forecast } from '../lib/forecast';
import type { Health } from '../lib/health';
import { useData } from '../store';
import { C, F, GRADIENTS } from '../theme';
import { AnimatedNumber, FadeIn, PressScale } from './anim';
import { Gauge, LineChart, Progress, Ring } from './charts';
import Icon, { type IconName } from './Icon';
import { Card, CategoryBubble, GradientCard, Label, Pill, Row, Section, Sheet, Stat, T } from './ui';

const short = (n: number) => {
  const a = Math.abs(n);
  const sg = n < 0 ? '−' : '';
  return a >= 1e7 ? `${sg}₹${(a / 1e7).toFixed(2)}Cr` : a >= 1e5 ? `${sg}₹${(a / 1e5).toFixed(1)}L` : a >= 1e3 ? `${sg}₹${(a / 1e3).toFixed(1)}k` : `${sg}${inr(a)}`;
};
const AnimatedPath = Animated.createAnimatedComponent(Path);

// ---------------------------------------------------------------- check mark that draws itself

export function CheckDraw({ size = 56, color = C.green }: { size?: number; color?: string }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(v, { toValue: 1, duration: 700, delay: 200, easing: Easing.out(Easing.cubic), useNativeDriver: false }).start();
  }, [v]);
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: color + '22', alignItems: 'center', justifyContent: 'center' }}>
      <Svg width={size * 0.55} height={size * 0.55} viewBox="0 0 24 24">
        <AnimatedPath
          d="M4 12.5l5 5L20 6.5"
          stroke={color}
          strokeWidth={3}
          fill="none"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeDasharray="26 26"
          strokeDashoffset={v.interpolate({ inputRange: [0, 1], outputRange: [26, 0] })}
        />
      </Svg>
    </View>
  );
}

// ---------------------------------------------------------------- hero

export function HeroCard({ net, cash, invested, dues }: { net: number; cash: number; invested: number; dues: number }) {
  const d = useData();
  const [w, setW] = useState(0);
  const pts = d.history.map((p) => p.net);
  const prev = pts.length >= 2 ? pts[pts.length - 2] : null;
  const delta = prev != null ? net - prev : null;
  return (
    <FadeIn index={0}>
      <GradientCard colors={GRADIENTS.hero} shine>
        <Row style={{ justifyContent: 'space-between' }}>
          <Label color="rgba(255,255,255,0.78)">Net worth</Label>
          {delta != null && Number.isFinite(delta) ? (
            <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: 'rgba(255,255,255,0.16)', paddingHorizontal: 9, paddingVertical: 4, borderRadius: 99 }}>
              <Icon name={delta >= 0 ? 'arrowUp' : 'arrowDown'} size={12} color="#fff" stroke={2.6} />
              <T size={11.5} weight="bold" color="#fff" style={{ marginLeft: 4 }}>
                {short(Math.abs(delta))} this month
              </T>
            </View>
          ) : null}
        </Row>
        <AnimatedNumber value={net} format={inr} style={{ fontFamily: F.black, fontSize: 40, color: '#fff', marginTop: 6, letterSpacing: -1 }} />
        <View style={{ marginHorizontal: -8, marginTop: 4 }} onLayout={(e: LayoutChangeEvent) => setW(e.nativeEvent.layout.width)}>
          {pts.length >= 3 ? <LineChart values={pts} width={w} height={58} color="#FFFFFF" /> : null}
        </View>
        <Row style={{ marginTop: 10, backgroundColor: 'rgba(0,0,0,0.14)', borderRadius: 16, padding: 12 }}>
          <Stat label="Bank" icon="bank" value={short(cash)} color="#fff" />
          <Stat label="Invested" icon="trend" value={short(invested)} color="#fff" />
          <Stat label="Card dues" icon="card" value={short(dues)} color={dues > 0 ? '#FECACA' : '#fff'} />
        </Row>
      </GradientCard>
    </FadeIn>
  );
}

// ---------------------------------------------------------------- quick tiles

function Tile({
  icon,
  color,
  label,
  value,
  caption,
  onPress,
  index,
  ring,
}: {
  icon: IconName;
  color: string;
  label: string;
  value: number;
  caption: string;
  onPress: () => void;
  index: number;
  ring?: number;
}) {
  return (
    <FadeIn index={index} style={{ width: '48.5%', marginBottom: 10 }}>
      <PressScale onPress={onPress} scaleTo={0.96}>
        <Card style={{ marginBottom: 0, padding: 14, minHeight: 118 }} pad={14}>
          <Row style={{ justifyContent: 'space-between' }}>
            {ring != null ? (
              <Ring pct={ring} size={34} stroke={4} color={color}>
                <Icon name={icon} size={14} color={color} />
              </Ring>
            ) : (
              <View style={{ width: 34, height: 34, borderRadius: 12, backgroundColor: color + '22', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name={icon} size={17} color={color} />
              </View>
            )}
            <Icon name="chevronRight" size={16} color={C.faint} />
          </Row>
          <T size={12} color={C.sub} weight="medium" style={{ marginTop: 10 }}>
            {label}
          </T>
          <AnimatedNumber value={value} format={label === 'Money health' ? (n) => `${Math.round(n)}/100` : short} style={{ fontFamily: F.black, fontSize: 21, color: C.text, marginTop: 1 }} />
          <T size={11} color={C.faint} lines={1}>
            {caption}
          </T>
        </Card>
      </PressScale>
    </FadeIn>
  );
}

export function QuickTiles({
  health,
  spent,
  vsLast,
  saving,
  forecast,
  go,
  onHealth,
}: {
  health: Health | null;
  spent: number;
  vsLast: number | null;
  saving: number;
  forecast: Forecast;
  go: (t: string) => void;
  onHealth: () => void;
}) {
  const hc = !health ? C.sub : health.score >= 80 ? C.green : health.score >= 60 ? C.teal : health.score >= 40 ? C.amber : C.red;
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' }}>
      {health ? (
        <Tile index={1} icon="heart" color={hc} ring={health.score / 100} label="Money health" value={health.score} caption={health.grade} onPress={onHealth} />
      ) : null}
      <Tile
        index={2}
        icon="pie"
        color={C.blue}
        label="Spent this month"
        value={spent}
        caption={vsLast != null && Number.isFinite(vsLast) ? `${vsLast >= 0 ? '+' : ''}${Math.round(vsLast * 100)}% vs last month` : 'so far'}
        onPress={() => go('spending')}
      />
      <Tile index={3} icon="sparkle" color={C.green} label="You could save" value={saving} caption={`${short(saving * 12)} a year`} onPress={() => go('insights')} />
      <Tile
        index={4}
        icon="wallet"
        color={forecast.leftAtMonthEnd >= 0 ? C.teal : C.red}
        label="Left by month end"
        value={Math.max(0, forecast.leftAtMonthEnd)}
        caption={forecast.leftAtMonthEnd >= 0 ? `after ~${short(forecast.projectedSpend)} spend` : `over by ${short(-forecast.leftAtMonthEnd)}`}
        onPress={() => go('spending')}
      />
    </View>
  );
}

// ---------------------------------------------------------------- health sheet

export function HealthSheet({ health, visible, onClose }: { health: Health; visible: boolean; onClose: () => void }) {
  const hc = health.score >= 80 ? C.green : health.score >= 60 ? C.teal : health.score >= 40 ? C.amber : C.red;
  return (
    <Sheet visible={visible} onClose={onClose} title="Money health">
      <ScrollView>
        <View style={{ alignItems: 'center' }}>
          <Gauge value={health.score} color="gradient" size={240} />
          <View style={{ position: 'absolute', bottom: 0, alignItems: 'center' }}>
            <AnimatedNumber value={health.score} format={(n) => String(Math.round(n))} style={{ fontFamily: F.black, fontSize: 46, color: hc }} />
            <Pill text={health.grade} color={hc} />
          </View>
        </View>
        {health.partial ? (
          <T size={12} color={C.amber} style={{ textAlign: 'center', marginTop: 8 }}>
            {health.partial}
          </T>
        ) : null}
        <View style={{ marginTop: 18 }}>
          {health.parts.map((p, i) => (
            <View key={p.key} style={{ marginBottom: 14 }}>
              <Row style={{ justifyContent: 'space-between', marginBottom: 6 }}>
                <T size={14} weight="semibold">
                  {p.label}
                </T>
                <T size={12.5} color={C.sub}>
                  {p.unknown ? 'not scored' : `${p.score}/${p.max}`}
                </T>
              </Row>
              <Progress value={p.unknown ? 0 : p.score / p.max} color={p.score / p.max > 0.66 ? C.green : p.score / p.max > 0.33 ? C.amber : C.red} delay={i * 90} />
              <T size={12} color={C.sub} style={{ marginTop: 4 }}>
                {p.note}
              </T>
            </View>
          ))}
        </View>
      </ScrollView>
    </Sheet>
  );
}

// ---------------------------------------------------------------- attention feed

interface Attention {
  id: string;
  tone: 'red' | 'amber' | 'blue';
  icon: IconName;
  title: string;
  text: string;
  cta: string;
  to: string;
}

function useAttention(): Attention[] {
  const d = useData();
  const out: Attention[] = [];
  for (const s of d.signals.slice(0, 3)) out.push({ id: s.id, tone: 'red', icon: 'shield', title: s.title, text: s.detail, cta: 'Review', to: 'insights:guard' });
  for (const f of d.failedPayments.filter((x) => x.status === 'overdue'))
    out.push({ id: f.id, tone: 'red', icon: 'alert', title: `Refund overdue: ${inr(f.amount)}`, text: `Your ${f.institution} payment failed and hasn't come back. The bank owes ₹100/day.`, cta: 'What to do', to: 'insights:guard' });
  for (const b of d.bills.filter((x) => x.state === 'overdue'))
    out.push({ id: b.id, tone: 'red', icon: 'calendar', title: `${b.biller} bill overdue`, text: `${inr(b.amount)} was due ${b.dueDate ? new Date(b.dueDate).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' }) : 'recently'}. Pay to avoid penalties.`, cta: 'See bills', to: 'home' });
  for (const st of budgetStatus(d.ledger.transactions, d.budgets.categories).filter((x) => x.pct >= 0.8).slice(0, 2))
    out.push({ id: `bud-${st.category}`, tone: st.pct >= 1 ? 'red' : 'amber', icon: 'pie', title: `${st.category} budget ${st.pct >= 1 ? 'used up' : `at ${Math.round(st.pct * 100)}%`}`, text: `${inr(st.spent)} of ${inr(st.limit)} this month.`, cta: 'Spending', to: 'spending' });
  const soon = Date.now() + 3 * 86_400_000;
  for (const b of d.bills.filter((x) => x.state === 'due' && x.dueDate && x.dueDate <= soon))
    out.push({ id: b.id, tone: 'amber', icon: 'calendar', title: `${b.biller} ${b.kind === 'insurance' ? 'premium' : 'bill'} due soon`, text: `${inr(b.amount)} due ${new Date(b.dueDate!).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}.`, cta: 'See bills', to: 'home' });
  for (const e of d.expiries.filter((x) => x.daysLeft <= 2))
    out.push({ id: `exp-${e.service}`, tone: 'amber', icon: 'send', title: `${e.service} plan ends ${e.daysLeft <= 0 ? 'today' : e.daysLeft === 1 ? 'tomorrow' : `in ${e.daysLeft} days`}`, text: 'Recharge in time to stay connected.', cta: 'Got it', to: 'home' });
  for (const a of d.fastagLow) out.push({ id: `tag-${a.key}`, tone: 'amber', icon: 'car', title: `FASTag low: ${inr(a.balance ?? 0)}`, text: 'Recharge before your next trip to avoid double toll.', cta: 'Got it', to: 'home' });
  for (const c of d.changes.slice(0, 2))
    out.push({ id: c.id, tone: 'amber', icon: 'trend', title: c.kind === 'price-rise' ? `${c.name} costs more` : `${c.name} bill unusually high`, text: `${inr(c.from)} → ${inr(c.to)} (+${Math.round(c.pct * 100)}%).`, cta: 'Look', to: 'insights' });
  for (const f of d.failedPayments.filter((x) => x.status === 'waiting'))
    out.push({ id: f.id, tone: 'blue', icon: 'undo', title: `${inr(f.amount)} refund on the way`, text: `From a failed ${f.mode} payment; due by ${new Date(f.dueBy).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}.`, cta: 'Track', to: 'insights:guard' });
  return out;
}

export function AttentionFeed({ go }: { go: (t: string) => void }) {
  const items = useAttention();
  const { width } = useWindowDimensions();
  const cardW = width - 32 - 28;
  const x = useRef(new Animated.Value(0)).current;
  if (!items.length) {
    return (
      <FadeIn index={5}>
        <Card>
          <Row>
            <CheckDraw size={46} />
            <View style={{ flex: 1, marginLeft: 12 }}>
              <T size={15} weight="bold">
                Nothing needs you right now
              </T>
              <T size={12.5} color={C.sub}>
                No unusual payments, overdue bills or refunds. We'll flag anything new.
              </T>
            </View>
          </Row>
        </Card>
      </FadeIn>
    );
  }
  const toneColor = { red: C.red, amber: C.amber, blue: C.blue };
  return (
    <>
      <Section title={`Needs your attention · ${items.length}`} />
      <Animated.ScrollView
        horizontal
        decelerationRate="fast"
        snapToInterval={cardW + 10}
        showsHorizontalScrollIndicator={false}
        style={{ marginHorizontal: -16 }}
        contentContainerStyle={{ paddingHorizontal: 16 }}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { x } } }], { useNativeDriver: true })}
        scrollEventThrottle={16}
      >
        {items.map((a, i) => {
          const col = toneColor[a.tone];
          const range = [(i - 1) * (cardW + 10), i * (cardW + 10), (i + 1) * (cardW + 10)];
          return (
            <Animated.View
              key={a.id}
              style={{
                width: cardW,
                marginRight: 10,
                transform: [{ scale: x.interpolate({ inputRange: range, outputRange: [0.94, 1, 0.94], extrapolate: 'clamp' }) }],
                opacity: x.interpolate({ inputRange: range, outputRange: [0.7, 1, 0.7], extrapolate: 'clamp' }),
              }}
            >
              <FadeIn index={i}>
                <Card style={{ borderLeftWidth: 4, borderLeftColor: col, marginBottom: 0, minHeight: 132 }}>
                  <Row style={{ alignItems: 'flex-start' }}>
                    <View style={{ width: 38, height: 38, borderRadius: 13, backgroundColor: col + '22', alignItems: 'center', justifyContent: 'center' }}>
                      <Icon name={a.icon} size={19} color={col} />
                    </View>
                    <View style={{ flex: 1, marginLeft: 12 }}>
                      <T size={14.5} weight="bold" lines={2}>
                        {a.title}
                      </T>
                      <T size={12.5} color={C.sub} lines={2} style={{ marginTop: 3 }}>
                        {a.text}
                      </T>
                    </View>
                  </Row>
                  <PressScale
                    onPress={() => go(a.to)}
                    style={{ alignSelf: 'flex-start', marginTop: 12, marginLeft: 50, paddingHorizontal: 14, paddingVertical: 7, borderRadius: 99, backgroundColor: col + '1F' }}
                  >
                    <T size={12.5} weight="bold" color={col}>
                      {a.cta} →
                    </T>
                  </PressScale>
                </Card>
              </FadeIn>
            </Animated.View>
          );
        })}
      </Animated.ScrollView>
      {items.length > 1 ? (
        <Row style={{ justifyContent: 'center', marginTop: 10, marginBottom: 2 }}>
          {items.map((a, i) => {
            const range = [(i - 1) * (cardW + 10), i * (cardW + 10), (i + 1) * (cardW + 10)];
            return (
              <Animated.View
                key={a.id}
                style={{
                  width: 14,
                  height: 6,
                  borderRadius: 3,
                  marginHorizontal: 3,
                  backgroundColor: C.accent,
                  opacity: x.interpolate({ inputRange: range, outputRange: [0.25, 1, 0.25], extrapolate: 'clamp' }),
                  transform: [{ scaleX: x.interpolate({ inputRange: range, outputRange: [0.45, 1, 0.45], extrapolate: 'clamp' }) }],
                }}
              />
            );
          })}
        </Row>
      ) : null}
    </>
  );
}

// ---------------------------------------------------------------- this month + forecast

export function MonthCard({ f, vsLast, index }: { f: Forecast; vsLast: number | null; index: number }) {
  const [open, setOpen] = useState(false);
  const base = Math.max(f.expectedIncome, f.projectedSpend, 1);
  const positive = f.leftAtMonthEnd >= 0;
  const monthName = new Date().toLocaleDateString('en-IN', { month: 'long' });
  const endLabel = new Date(f.monthEnd).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  return (
    <>
      <Section title={`${monthName} at a glance`} />
      <FadeIn index={index}>
        <Card>
          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <View>
              <Label>Spent so far</Label>
              <AnimatedNumber value={f.spentSoFar} format={inr} style={{ fontFamily: F.black, fontSize: 30, color: C.text, marginTop: 2 }} />
            </View>
            {vsLast != null && Number.isFinite(vsLast) ? (
              <Pill text={`${vsLast > 0 ? '+' : ''}${Math.round(vsLast * 100)}% vs last month`} color={vsLast > 0.05 ? C.red : C.green} icon={vsLast > 0 ? 'arrowUp' : 'arrowDown'} />
            ) : null}
          </Row>
          <View style={{ height: 14, borderRadius: 7, backgroundColor: C.cardHi, flexDirection: 'row', overflow: 'hidden', marginTop: 14 }}>
            <View style={{ width: `${(f.spentSoFar / base) * 100}%`, backgroundColor: C.accent }} />
            <View style={{ width: `${(Math.max(0, f.projectedSpend - f.spentSoFar) / base) * 100}%`, backgroundColor: C.accent + '55' }} />
          </View>
          <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
            <Row>
              <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: C.accent, marginRight: 5 }} />
              <T size={11.5} color={C.sub}>
                Spent
              </T>
              <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: C.accent + '55', marginLeft: 12, marginRight: 5 }} />
              <T size={11.5} color={C.sub}>
                Likely by {endLabel}
              </T>
            </Row>
            <T size={11.5} color={C.sub}>
              {f.expectedIncome > 0 ? `of ${short(f.expectedIncome)}` : ''}
            </T>
          </Row>
          <Row style={{ marginTop: 14, padding: 12, borderRadius: 16, backgroundColor: (positive ? C.green : C.red) + '14' }}>
            <Icon name={positive ? 'wallet' : 'alert'} size={20} color={positive ? C.green : C.red} />
            <View style={{ flex: 1, marginLeft: 10 }}>
              <T size={13.5} weight="bold" color={positive ? C.green : C.red}>
                {f.expectedIncome <= 0
                  ? `Likely ${inr(f.projectedSpend)} by ${endLabel}`
                  : positive
                    ? `About ${inr(f.leftAtMonthEnd)} left on ${endLabel}`
                    : `Heading ${inr(-f.leftAtMonthEnd)} over this month`}
              </T>
              <T size={11.5} color={C.sub}>
                ~{inr(f.dailyRate)}/day everyday spending · {f.daysLeft} days to go
              </T>
            </View>
          </Row>
          {f.upcoming.length ? (
            <>
              <PressScale
                onPress={() => {
                  LayoutAnimation.configureNext(LayoutAnimation.create(240, 'easeInEaseOut', 'opacity'));
                  setOpen(!open);
                }}
                style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12 }}
              >
                <T size={12.5} weight="semibold" color={C.accent} style={{ flex: 1 }}>
                  {open ? 'Hide' : 'Show'} {f.upcoming.length} payment{f.upcoming.length > 1 ? 's' : ''} still to come ({short(f.upcoming.reduce((s, u) => s + u.amount, 0))})
                </T>
                <Icon name={open ? 'chevronDown' : 'chevronRight'} size={16} color={C.accent} />
              </PressScale>
              {open
                ? f.upcoming.map((u) => (
                    <Row key={u.merchant + u.date} style={{ paddingVertical: 7 }}>
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
                  ))
                : null}
            </>
          ) : null}
        </Card>
      </FadeIn>
    </>
  );
}
