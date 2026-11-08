import { useState } from 'react';
import { ScrollView, View } from 'react-native';

import Segmented from '../components/Segmented';
import LoansSection from './sections/LoansSection';
import TaxSection from './sections/TaxSection';

import { AnimatedNumber, FadeIn } from '../components/anim';
import { Donut } from '../components/charts';
import Icon from '../components/Icon';
import { GrowthArt } from '../components/Illustrations';
import { Card, Empty, GradientCard, InsightCard, Label, Pill, Row, Section, Stat, T } from '../components/ui';
import { inr, isInvestment } from '../lib/analysis';
import { portfolioXirr } from '../lib/investments';
import { useData } from '../store';
import { C, F, GRADIENTS } from '../theme';

const DAY = 86_400_000;
const ASSET = {
  equity: { label: 'Equity', color: C.blue },
  debt: { label: 'Debt', color: C.green },
  hybrid: { label: 'Hybrid', color: C.violet },
  gold: { label: 'Gold', color: C.amber },
};

function PortfolioContent() {
  const d = useData();
  const h = d.holdings;
  const value = h.reduce((s, x) => s + x.currentValue, 0);
  const invested = h.reduce((s, x) => s + x.invested, 0);
  const gain = value - invested;
  const xirr = portfolioXirr(h);
  const alloc = { equity: 0, debt: 0, hybrid: 0, gold: 0 };
  for (const x of h) alloc[x.assetClass] += x.currentValue;
  const allocParts = (Object.keys(alloc) as (keyof typeof alloc)[]).filter((k) => alloc[k] > 0);
  const brokerFlows = d.ledger.transactions.filter(
    (t) => isInvestment(t) && t.date >= Date.now() - 365 * DAY && /zerodha|groww|upstox|angel|dhan|5paisa|icicidirect|hdfc ?sec|nps|ppf/i.test(t.merchant + t.body),
  );

  return (
    <View>
      <FadeIn>
        <GradientCard colors={GRADIENTS.invest}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Label color="rgba(255,255,255,0.75)">Mutual funds</Label>
            {h.length ? <Pill text={`${h.length} fund${h.length > 1 ? 's' : ''}`} color="#C4B5FD" /> : null}
          </Row>
          <AnimatedNumber value={value} format={inr} style={{ fontFamily: F.black, fontSize: 36, color: '#fff', marginTop: 6 }} />
          <Row style={{ marginTop: 4 }}>
            <Icon name={gain >= 0 ? 'arrowUp' : 'arrowDown'} size={14} color={gain >= 0 ? '#6EE7B7' : '#FCA5A5'} stroke={2.6} />
            <T size={13.5} weight="semibold" color={gain >= 0 ? '#6EE7B7' : '#FCA5A5'} style={{ marginLeft: 4 }}>
              {gain >= 0 ? '+' : ''}
              {inr(gain)} ({invested > 0 ? ((gain / invested) * 100).toFixed(1) : '0'}%)
            </T>
          </Row>
          <Row style={{ marginTop: 18 }}>
            <Stat label="Invested" value={inr(invested)} color="#fff" />
            <Stat label="Yearly return (XIRR)" value={xirr == null ? '—' : `${(xirr * 100).toFixed(1)}%`} color={xirr != null && xirr < 0 ? '#FCA5A5' : '#6EE7B7'} />
          </Row>
        </GradientCard>
      </FadeIn>

      {value > 0 ? (
        <FadeIn index={1}>
          <Card>
            <Label>Asset mix</Label>
            <Row style={{ marginTop: 12 }}>
              <Donut
                size={130}
                thickness={16}
                data={allocParts.map((k) => ({ value: alloc[k], color: ASSET[k].color }))}
                center={<Icon name="pie" size={22} color={C.sub} />}
              />
              <View style={{ flex: 1, marginLeft: 18 }}>
                {allocParts.map((k) => (
                  <Row key={k} style={{ marginVertical: 5 }}>
                    <View style={{ width: 10, height: 10, borderRadius: 3, backgroundColor: ASSET[k].color }} />
                    <T size={13.5} style={{ flex: 1, marginLeft: 8 }}>
                      {ASSET[k].label}
                    </T>
                    <T size={13.5} weight="bold">
                      {Math.round((alloc[k] / value) * 100)}%
                    </T>
                  </Row>
                ))}
                <T size={11.5} color={C.faint} style={{ marginTop: 4 }}>
                  Target {d.assumptions.target.equity}/{d.assumptions.target.debt}/{d.assumptions.target.gold}
                </T>
              </View>
            </Row>
          </Card>
        </FadeIn>
      ) : null}

      {d.investInsights.length ? <Section title="How to do better" /> : null}
      {d.investInsights.map((i, k) => (
        <FadeIn key={i.id} index={2 + k}>
          <InsightCard i={i} startOpen={k === 0} />
        </FadeIn>
      ))}

      <Section title="Holdings" />
      {h.length === 0 ? (
        <Card>
          <Empty
            art={<GrowthArt size={150} />}
            title="No funds yet"
            text="Holdings appear automatically from CAMS / KFintech SMS sent after every SIP or purchase."
          />
        </Card>
      ) : null}
      {h.map((x, i) => {
        const g = x.currentValue - x.invested;
        const pct = x.invested > 0 ? (g / x.invested) * 100 : 0;
        return (
          <FadeIn key={x.scheme + x.folio} index={3 + i}>
            <Card>
              <Row style={{ alignItems: 'flex-start' }}>
                <View style={{ width: 4, alignSelf: 'stretch', borderRadius: 2, backgroundColor: ASSET[x.assetClass].color, marginRight: 12 }} />
                <View style={{ flex: 1 }}>
                  <T size={14.5} weight="semibold">
                    {x.scheme}
                  </T>
                  <Row style={{ marginTop: 6, flexWrap: 'wrap', gap: 6 }}>
                    <Pill text={ASSET[x.assetClass].label} color={ASSET[x.assetClass].color} />
                    {x.plan === 'regular' ? <Pill text="Regular plan · high fees" color={C.red} icon="alert" /> : null}
                    {x.plan === 'direct' ? <Pill text="Direct" color={C.green} icon="check" /> : null}
                  </Row>
                  <Row style={{ marginTop: 12, justifyContent: 'space-between' }}>
                    <View>
                      <T size={11} color={C.faint}>
                        Value
                      </T>
                      <T size={17} weight="black">
                        {inr(x.currentValue)}
                      </T>
                    </View>
                    <View style={{ alignItems: 'flex-end' }}>
                      <T size={11} color={C.faint}>
                        Gain
                      </T>
                      <T size={15} weight="bold" color={g >= 0 ? C.green : C.red}>
                        {g >= 0 ? '+' : ''}
                        {inr(g)} · {pct.toFixed(1)}%
                      </T>
                    </View>
                  </Row>
                  <T size={11.5} color={C.faint} style={{ marginTop: 6 }}>
                    {x.units.toFixed(3)} units · NAV ₹{x.lastNav.toFixed(2)}
                    {x.navDate ? ` (${new Date(x.navDate).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })})` : ''} · invested{' '}
                    {inr(x.invested)}
                  </T>
                </View>
              </Row>
            </Card>
          </FadeIn>
        );
      })}

      {brokerFlows.length ? (
        <FadeIn index={4 + h.length}>
          <Card>
            <Row>
              <Icon name="briefcase" size={18} color={C.indigo} />
              <T size={14} weight="semibold" style={{ marginLeft: 8 }}>
                Stocks, NPS & PPF (last 12 months)
              </T>
            </Row>
            <T size={22} weight="black" style={{ marginTop: 6 }}>
              {inr(brokerFlows.reduce((s, t) => s + t.amount, 0))}
            </T>
            <T size={12} color={C.sub}>
              Money sent in. Their market value isn't sent by SMS, so it isn't tracked here.
            </T>
          </Card>
        </FadeIn>
      ) : null}

      <T size={11} color={C.faint} style={{ marginTop: 10, lineHeight: 16 }}>
        Live NAVs from mfapi.in (AMFI). Suggestions are general, rule-based education, not personalised advice from a SEBI-registered adviser. Check exit
        loads and taxes before switching or selling.
      </T>
    </View>
  );
}

export type InvestView = 'portfolio' | 'loans' | 'tax';

export default function InvestScreen({ initial = 'portfolio' }: { initial?: InvestView }) {
  const [view, setView] = useState<InvestView>(initial);
  return (
    <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 120 }}>
      <View style={{ marginTop: -10, marginBottom: 12 }}>
        <Segmented
          value={view}
          onChange={setView}
          options={[
            { value: 'portfolio', label: 'Portfolio' },
            { value: 'loans', label: 'Loans' },
            { value: 'tax', label: 'Tax' },
          ]}
        />
      </View>
      <FadeIn key={view} from={10}>
        {view === 'portfolio' ? <PortfolioContent /> : view === 'loans' ? <LoansSection /> : <TaxSection />}
      </FadeIn>
    </ScrollView>
  );
}
