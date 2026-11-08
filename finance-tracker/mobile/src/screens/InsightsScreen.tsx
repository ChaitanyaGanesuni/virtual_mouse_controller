import { useState } from 'react';
import Segmented from '../components/Segmented';
import { PriceChangesSection } from '../components/bills';
import GuardSection from './sections/GuardSection';
import SubscriptionsSection from './sections/SubscriptionsSection';
import { LayoutAnimation, ScrollView, View } from 'react-native';

import { AnimatedNumber, FadeIn } from '../components/anim';
import { CheckArt, LeakArt } from '../components/Illustrations';
import { Card, CategoryBubble, Chip, Empty, GradientCard, InsightCard, Label, Row, Section, T } from '../components/ui';
import { findRecurring, inr, totalMonthlySaving } from '../lib/analysis';
import type { Severity } from '../lib/types';
import { useData } from '../store';
import { C, F, GRADIENTS, SEVERITY } from '../theme';

function LeaksContent() {
  const d = useData();
  const [filter, setFilter] = useState<Severity | 'all'>('all');
  const saving = totalMonthlySaving(d.waste);
  const lost = d.waste.filter((i) => i.severity === 'high').reduce((s, i) => s + (i.amount ?? 0), 0);
  const recurring = findRecurring(d.ledger.transactions);
  const recurringTotal = recurring.reduce((s, r) => s + r.monthlyCost, 0);
  const shown = d.waste.filter((i) => filter === 'all' || i.severity === filter);
  const counts = { high: 0, medium: 0, low: 0 };
  for (const i of d.waste) counts[i.severity]++;

  return (
    <View>
      <FadeIn>
        <GradientCard colors={d.waste.length ? GRADIENTS.warn : GRADIENTS.save}>
          <Row>
            <View style={{ flex: 1 }}>
              <Label color="rgba(255,255,255,0.75)">Avoidable spending</Label>
              <Row style={{ alignItems: 'flex-end' }}>
                <AnimatedNumber value={saving} format={inr} style={{ fontFamily: F.black, fontSize: 34, color: '#fff', marginTop: 4 }} />
                <T size={14} color="rgba(255,255,255,0.8)" weight="semibold" style={{ marginLeft: 4, marginBottom: 6 }}>
                  /mo
                </T>
              </Row>
              <T size={12.5} color="rgba(255,255,255,0.8)">
                {inr(saving * 12)} a year{lost > 0 ? ` · ${inr(lost)} lost to fees & penalties` : ''}
              </T>
            </View>
            <View style={{ marginRight: -20, marginTop: -10 }}>
              <LeakArt size={110} />
            </View>
          </Row>
        </GradientCard>
      </FadeIn>

      <PriceChangesSection />

      {d.waste.length ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginHorizontal: -16, marginBottom: 6 }} contentContainerStyle={{ paddingHorizontal: 16 }}>
          <Chip label={`All ${d.waste.length}`} active={filter === 'all'} onPress={() => { LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut); setFilter('all'); }} />
          {(['high', 'medium', 'low'] as const).map((sv) =>
            counts[sv] ? (
              <Chip
                key={sv}
                icon={SEVERITY[sv].icon}
                label={`${SEVERITY[sv].label} ${counts[sv]}`}
                active={filter === sv}
                onPress={() => {
                  LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
                  setFilter(sv);
                }}
              />
            ) : null,
          )}
        </ScrollView>
      ) : (
        <Card>
          <Empty art={<CheckArt />} title="No leaks found" text="Nothing in the last 90 days looks wasteful. Nice work!" />
        </Card>
      )}

      {shown.map((i, k) => (
        <FadeIn key={i.id} index={k}>
          <InsightCard i={i} startOpen={k === 0} />
        </FadeIn>
      ))}

      <Section title="Recurring payments" />
      <FadeIn index={shown.length + 1}>
        <Card>
          {recurring.length === 0 ? (
            <Empty title="None detected yet" text="Payments show up here once they repeat at least twice." />
          ) : (
            <>
              <Row style={{ justifyContent: 'space-between', marginBottom: 6 }}>
                <T size={13} color={C.sub}>
                  {recurring.length} active
                </T>
                <T size={13} weight="bold">
                  {inr(recurringTotal)}/mo · {inr(recurringTotal * 12)}/yr
                </T>
              </Row>
              {recurring.map((r) => (
                <Row key={r.merchant + r.periodDays} style={{ paddingVertical: 10 }}>
                  <CategoryBubble category={r.category} size={38} />
                  <View style={{ flex: 1, marginLeft: 12 }}>
                    <T size={14} weight="semibold" lines={1}>
                      {r.merchant}
                    </T>
                    <T size={12} color={C.sub}>
                      {r.category} · every {r.periodDays === 30 ? 'month' : r.periodDays === 365 ? 'year' : r.periodDays === 7 ? 'week' : `${r.periodDays} days`} · last{' '}
                      {new Date(r.lastCharged).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}
                    </T>
                  </View>
                  <View style={{ alignItems: 'flex-end' }}>
                    <T size={14} weight="bold">
                      {inr(r.amount)}
                    </T>
                    <T size={11} color={C.faint}>
                      {inr(r.monthlyCost * 12)}/yr
                    </T>
                  </View>
                </Row>
              ))}
            </>
          )}
        </Card>
      </FadeIn>
    </View>
  );
}

export type LeaksView = 'leaks' | 'subs' | 'guard';

export default function InsightsScreen({ initial = 'leaks' }: { initial?: LeaksView }) {
  const d = useData();
  const [view, setView] = useState<LeaksView>(initial);
  const alerts = d.signals.length + d.failedPayments.filter((f) => f.status !== 'refunded').length;
  return (
    <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 120 }}>
      <View style={{ marginTop: -10, marginBottom: 12 }}>
        <Segmented
          value={view}
          onChange={setView}
          options={[
            { value: 'leaks', label: 'Leaks' },
            { value: 'subs', label: 'Subscriptions' },
            { value: 'guard', label: alerts ? `Protection · ${alerts}` : 'Protection' },
          ]}
        />
      </View>
      <FadeIn key={view} from={10}>
        {view === 'leaks' ? <LeaksContent /> : view === 'subs' ? <SubscriptionsSection /> : <GuardSection />}
      </FadeIn>
    </ScrollView>
  );
}
