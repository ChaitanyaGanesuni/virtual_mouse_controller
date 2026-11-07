import { ScrollView, Text } from 'react-native';

import { Big, C, Card, Empty, H, InsightCard, Label, Row } from '../components/ui';
import { findRecurring, inr } from '../lib/analysis';
import { useData } from '../store';

export default function InsightsScreen() {
  const d = useData();
  const saving = d.waste.reduce((s, i) => s + (i.monthlySaving ?? 0), 0);
  const recurring = findRecurring(d.ledger.transactions);
  const recurringTotal = recurring.reduce((s, r) => s + r.monthlyCost, 0);

  return (
    <ScrollView contentContainerStyle={{ padding: 16 }}>
      <Card>
        <Label>Estimated avoidable spending</Label>
        <Big color={C.accent}>{inr(saving)}/month</Big>
        <Text style={{ color: C.sub, marginTop: 4 }}>
          Based on your last 90 days. Red = money lost outright, amber = habits worth trimming, blue = worth a look.
        </Text>
      </Card>

      {d.waste.length === 0 ? <Empty text="No obvious waste found. Nice work." /> : null}
      {d.waste.map((i) => (
        <InsightCard key={i.id} i={i} />
      ))}

      <H>All recurring payments</H>
      <Card>
        {recurring.length === 0 ? <Empty text="No recurring payments detected yet (needs 2+ charges)." /> : null}
        {recurring.map((r) => (
          <Row key={r.merchant + r.periodDays} style={{ justifyContent: 'space-between', paddingVertical: 8 }}>
            <Text style={{ color: C.text, flex: 1 }} numberOfLines={1}>
              {r.merchant}
              <Text style={{ color: C.sub, fontSize: 12 }}>
                {'  '}
                {r.category} · every {r.periodDays === 30 ? 'month' : r.periodDays === 365 ? 'year' : `${r.periodDays}d`}
              </Text>
            </Text>
            <Text style={{ color: C.text, fontWeight: '600' }}>{inr(r.amount)}</Text>
          </Row>
        ))}
        {recurring.length ? (
          <Text style={{ color: C.sub, marginTop: 8 }}>
            Total ≈ {inr(recurringTotal)}/month · {inr(recurringTotal * 12)}/year
          </Text>
        ) : null}
      </Card>
    </ScrollView>
  );
}
