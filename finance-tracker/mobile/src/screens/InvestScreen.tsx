import { ScrollView, Text, View } from 'react-native';

import { Big, C, Card, Empty, H, InsightCard, Label, Row, StackBar, Stat } from '../components/ui';
import { inr, isInvestment } from '../lib/analysis';
import { portfolioXirr } from '../lib/investments';
import { useData } from '../store';

const DAY = 86_400_000;

export default function InvestScreen() {
  const d = useData();
  const h = d.holdings;
  const value = h.reduce((s, x) => s + x.currentValue, 0);
  const invested = h.reduce((s, x) => s + x.invested, 0);
  const gain = value - invested;
  const xirr = portfolioXirr(h);
  const alloc = { equity: 0, debt: 0, hybrid: 0, gold: 0 };
  for (const x of h) alloc[x.assetClass] += x.currentValue;
  const otherInvest = d.ledger.transactions.filter((t) => isInvestment(t) && t.date >= Date.now() - 365 * DAY);
  const brokerFlows = otherInvest.filter((t) => /zerodha|groww|upstox|angel|dhan|5paisa|icicidirect|hdfc ?sec|nps|ppf/i.test(t.merchant + t.body));

  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <Card>
        <Label>Mutual fund portfolio</Label>
        <Big>{inr(value)}</Big>
        <Row style={{ marginTop: 12 }}>
          <Stat label="Invested" value={inr(invested)} />
          <Stat label="Gain" value={`${gain >= 0 ? '+' : ''}${inr(gain)}`} color={gain >= 0 ? C.accent : C.red} />
          <Stat label="XIRR" value={xirr == null ? '—' : `${(xirr * 100).toFixed(1)}%`} color={xirr != null && xirr >= 0 ? C.accent : C.red} />
        </Row>
        {value > 0 ? (
          <View style={{ marginTop: 16 }}>
            <StackBar
              parts={[
                { label: 'Equity', value: alloc.equity, color: C.blue },
                { label: 'Debt', value: alloc.debt, color: C.accent },
                { label: 'Hybrid', value: alloc.hybrid, color: C.violet },
                { label: 'Gold', value: alloc.gold, color: C.amber },
              ].filter((p) => p.value > 0)}
            />
          </View>
        ) : null}
      </Card>

      {d.investInsights.length ? <H>How to improve</H> : null}
      {d.investInsights.map((i) => (
        <InsightCard key={i.id} i={i} />
      ))}

      <H>Holdings</H>
      <Card>
        {h.length === 0 ? (
          <Empty text="No mutual-fund holdings found yet. They appear automatically from CAMS / KFintech allotment SMS (sent after every SIP or purchase)." />
        ) : null}
        {h.map((x) => {
          const g = x.currentValue - x.invested;
          return (
            <View key={x.scheme + x.folio} style={{ paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: C.border }}>
              <Text style={{ color: C.text, fontWeight: '600' }}>{x.scheme}</Text>
              <Text style={{ color: C.sub, fontSize: 12, marginTop: 2 }}>
                {x.units.toFixed(3)} units · NAV {x.lastNav.toFixed(2)}
                {x.navDate ? ` (${new Date(x.navDate).toLocaleDateString('en-IN')})` : ''} · {x.assetClass}
                {x.plan === 'regular' ? ' · REGULAR plan' : x.plan === 'direct' ? ' · direct' : ''}
              </Text>
              <Row style={{ justifyContent: 'space-between', marginTop: 4 }}>
                <Text style={{ color: C.sub }}>Invested {inr(x.invested)}</Text>
                <Text style={{ color: g >= 0 ? C.accent : C.red, fontWeight: '700' }}>
                  {inr(x.currentValue)} ({g >= 0 ? '+' : ''}
                  {x.invested > 0 ? ((g / x.invested) * 100).toFixed(1) : '0'}%)
                </Text>
              </Row>
            </View>
          );
        })}
      </Card>

      {brokerFlows.length ? (
        <Card>
          <Label>Other investments (last 12 months)</Label>
          <Text style={{ color: C.text, fontSize: 18, fontWeight: '700', marginTop: 4 }}>
            {inr(brokerFlows.reduce((s, t) => s + t.amount, 0))} sent to brokers / NPS / PPF
          </Text>
          <Text style={{ color: C.sub, fontSize: 12, marginTop: 4 }}>
            Stock and NPS values are not sent by SMS, so only the money you put in is tracked here.
          </Text>
        </Card>
      ) : null}

      <Text style={{ color: C.sub, fontSize: 11, marginVertical: 12, lineHeight: 16 }}>
        Live NAVs from mfapi.in (AMFI data). Suggestions are general, rule-based education, not personalised advice from a
        SEBI-registered adviser. Check exit loads and taxes before switching or selling.
      </Text>
    </ScrollView>
  );
}
