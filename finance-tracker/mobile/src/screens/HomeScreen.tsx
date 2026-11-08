import { useState } from 'react';
import { Animated, LayoutAnimation, RefreshControl, ScrollView, View } from 'react-native';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import { useScreenScroll } from '../themeContext';

import { AnimatedNumber, FadeIn, PressScale, Skeleton } from '../components/anim';
import { Bars, Gauge, Progress } from '../components/charts';
import Icon from '../components/Icon';
import { Card, GradientCard, InsightCard, Label, Pill, Row, Section, Stat, T } from '../components/ui';
import { inr, isSpend, monthlySummary, totalMonthlySaving } from '../lib/analysis';
import { monthForecast } from '../lib/forecast';
import { moneyHealth } from '../lib/health';
import { BudgetsCard, NetWorthTrend } from '../components/planning';
import { DigestCard, GoalsCard } from '../components/weekly';
import { AttentionFeed, HealthSheet, HeroCard, MonthCard, QuickTiles } from '../components/homeKit';
import { BillsCard } from '../components/bills';
import { YearReviewCard } from '../components/YearReview';
import type { Account } from '../lib/types';
import { useData } from '../store';
import { C, F, GRADIENTS } from '../theme';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const short = (n: number) =>
  n >= 1e7 ? `₹${(n / 1e7).toFixed(1)}Cr` : n >= 1e5 ? `₹${(n / 1e5).toFixed(1)}L` : n >= 1e3 ? `₹${(n / 1e3).toFixed(0)}k` : inr(n);

const CARD_GRADIENTS: Record<Account['kind'], readonly string[]> = {
  wallet: ['#78350F', '#422006'],
  bank: ['#1E3A5F', '#0F2742'],
  credit_card: ['#3B1D5E', '#1E1B4B'],
};

function AccountCard({ a, index }: { a: Account; index: number }) {
  const card = a.kind === 'credit_card';
  const owed = card && (a.balance ?? 0) > 0;
  const grad = CARD_GRADIENTS[a.kind];
  return (
    <FadeIn index={index} from={10}>
      <View style={{ width: 210, height: 128, borderRadius: 20, overflow: 'hidden', marginRight: 12 }}>
        <Svg width="100%" height="100%" style={{ position: 'absolute' }}>
          <Defs>
            <LinearGradient id={`ac${index}`} x1="0" y1="0" x2="1" y2="1">
              <Stop offset="0" stopColor={grad[0]} />
              <Stop offset="1" stopColor={grad[1]} />
            </LinearGradient>
          </Defs>
          <Rect width="100%" height="100%" fill={`url(#ac${index})`} />
        </Svg>
        <View style={{ position: 'absolute', right: -30, top: -40, width: 120, height: 120, borderRadius: 60, backgroundColor: '#fff', opacity: 0.06 }} />
        <View style={{ flex: 1, padding: 16, justifyContent: 'space-between' }}>
          <Row style={{ justifyContent: 'space-between' }}>
            <T size={13} weight="semibold" lines={1} style={{ flex: 1 }}>
              {a.institution}
            </T>
            <Icon name={card ? 'card' : a.kind === 'wallet' ? 'car' : 'bank'} size={18} color="rgba(255,255,255,0.7)" />
          </Row>
          <View>
            <T size={11} color="rgba(255,255,255,0.6)">
              {a.kind === 'wallet' ? 'FASTag balance' : `${card ? (owed ? 'Bill due' : 'Card') : 'Available'} ••${a.last4 || '??'}`}
            </T>
            <T size={20} weight="black" color={owed ? '#FCA5A5' : C.text}>
              {a.balance == null ? '—' : inr(a.balance)}
            </T>
            <T size={11} color="rgba(255,255,255,0.6)" lines={1}>
              {card && owed && a.dueDate
                ? `Pay by ${new Date(a.dueDate).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}`
                : card && a.statementDue != null
                  ? 'Last bill paid ✓'
                  : a.asOf
                    ? `Updated ${new Date(a.asOf).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}`
                    : 'Balance not in SMS'}
            </T>
          </View>
        </View>
      </View>
    </FadeIn>
  );
}

export default function HomeScreen({ go }: { go: (tab: string) => void }) {
  const d = useData();
  const scroll = useScreenScroll();
  const [showHealth, setShowHealth] = useState(false);
  const { accounts, transactions } = d.ledger;
  const cash = accounts.filter((a) => a.kind === 'bank').reduce((s, a) => s + (a.balance ?? 0), 0);
  const cardDue = accounts.filter((a) => a.kind === 'credit_card').reduce((s, a) => s + (a.balance ?? 0), 0);
  const invested = d.holdings.reduce((s, h) => s + h.currentValue, 0);
  const net = cash + invested - cardDue;
  const months = monthlySummary(transactions);
  const now = months[months.length - 1];
  const prev = months[months.length - 2];
  const saving = totalMonthlySaving(d.waste);
  const health = moneyHealth(transactions, accounts, d.holdings);
  const forecast = monthForecast(transactions);
  const history = d.history;
  const healthColor = !health ? C.sub : health.score >= 80 ? C.green : health.score >= 60 ? C.teal : health.score >= 40 ? C.amber : C.red;
  // Compare with last month up to the same day, so early-month rent doesn't look like a spike.
  const today = new Date();
  const prevStart = new Date(today.getFullYear(), today.getMonth() - 1, 1).getTime();
  const prevSameDay = new Date(today.getFullYear(), today.getMonth() - 1, today.getDate(), 23, 59).getTime();
  const prevToDate = transactions.filter((t) => isSpend(t) && t.date >= prevStart && t.date <= prevSameDay).reduce((s, t) => s + t.amount, 0);
  const vsLast = prev && prevToDate > 0 ? now.spend / prevToDate - 1 : null;

  if (d.loading && !transactions.length) {
    return (
      <View style={{ padding: 16 }}>
        <Skeleton height={190} radius={28} style={{ marginBottom: 14 }} />
        <Skeleton height={150} radius={22} style={{ marginBottom: 14 }} />
        <Skeleton height={110} radius={22} style={{ marginBottom: 14 }} />
        <Skeleton height={128} radius={20} width="60%" />
      </View>
    );
  }

  return (
    <Animated.ScrollView
      {...scroll}
      contentContainerStyle={{ padding: 16, paddingBottom: 120 }}
      refreshControl={<RefreshControl refreshing={d.loading} onRefresh={() => d.refresh()} tintColor={C.accent} colors={[C.accent]} progressBackgroundColor={C.card} />}
    >
      {d.demoMode ? (
        <FadeIn>
          <Row style={{ alignSelf: 'flex-start', backgroundColor: C.amber + '1A', paddingHorizontal: 12, paddingVertical: 6, borderRadius: 99, marginBottom: 12 }}>
            <Icon name="sparkle" size={13} color={C.amber} />
            <T size={12} color={C.amber} weight="semibold" style={{ marginLeft: 6 }}>
              Sample data · switch off in Settings
            </T>
          </Row>
        </FadeIn>
      ) : null}

      <HeroCard net={net} cash={cash} invested={invested} dues={cardDue} />
      <QuickTiles health={health} spent={now.spend} vsLast={vsLast} saving={saving} forecast={forecast} go={go} onHealth={() => setShowHealth(true)} />
      <AttentionFeed go={go} />
      <MonthCard f={forecast} vsLast={vsLast} index={6} />
      <BillsCard index={6} />
      <BudgetsCard txns={transactions} budgets={d.budgets} onSave={d.setBudgets} index={6} />

      {accounts.length ? (
        <>
          <Section title="Accounts" />
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginHorizontal: -16 }} contentContainerStyle={{ paddingHorizontal: 16 }}>
            {accounts.map((a, i) => (
              <AccountCard key={a.key} a={a} index={i} />
            ))}
          </ScrollView>
        </>
      ) : null}

      <GoalsCard index={7} />
      <NetWorthTrend points={history} index={7} />
      <DigestCard dg={d.digest} index={7} />

      <Section title="Last 6 months" action="Details" onAction={() => go('spending')} />
      <FadeIn index={4}>
        <Card>
          <Bars
            data={months.map((m, i) => ({
              label: MONTHS[parseInt(m.month.slice(5), 10) - 1],
              value: m.spend,
              note: short(m.spend),
              highlight: i === months.length - 1,
              color: m.income > 0 && m.spend > m.income ? C.red : C.accent,
            }))}
          />
        </Card>
      </FadeIn>

      <YearReviewCard r={d.review} index={5} />

      {d.waste.length ? (
        <>
          <Section title="Top money leaks" action="See all" onAction={() => go('insights')} />
          {d.waste.slice(0, 2).map((i, k) => (
            <FadeIn key={i.id} index={5 + k}>
              <InsightCard i={i} />
            </FadeIn>
          ))}
        </>
      ) : null}

      <Row style={{ justifyContent: 'center', marginTop: 10 }}>
        <Icon name="shieldCheck" size={14} color={C.faint} />
        <T size={11.5} color={C.faint} style={{ marginLeft: 6 }}>
          {d.smsCount} alerts read on this phone · {transactions.length} transactions
          {d.lastSync ? ` · ${new Date(d.lastSync).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' })}` : ''}
        </T>
      </Row>
      {health ? <HealthSheet health={health} visible={showHealth} onClose={() => setShowHealth(false)} /> : null}
    </Animated.ScrollView>
  );
}
