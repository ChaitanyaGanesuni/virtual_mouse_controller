import { Linking, RefreshControl, ScrollView, Text, View } from 'react-native';

import { BarRow, Big, Button, C, Card, Empty, H, InsightCard, Label, Row, Stat } from '../components/ui';
import { inr, monthlySummary } from '../lib/analysis';
import { useData } from '../store';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export default function HomeScreen({ go }: { go: (tab: string) => void }) {
  const d = useData();
  const { accounts, transactions } = d.ledger;
  const cash = accounts.filter((a) => a.kind === 'bank').reduce((s, a) => s + (a.balance ?? 0), 0);
  const cardDue = accounts.filter((a) => a.kind === 'credit_card').reduce((s, a) => s + (a.balance ?? 0), 0);
  const invested = d.holdings.reduce((s, h) => s + h.currentValue, 0);
  const net = cash + invested - cardDue;
  const months = monthlySummary(transactions);
  const thisMonth = months[months.length - 1];
  const maxSpend = Math.max(...months.map((m) => m.spend), 1);
  const saving = d.waste.reduce((s, i) => s + (i.monthlySaving ?? 0), 0);

  if (!d.loading && d.source === 'none') {
    return (
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <Card>
          <H>Welcome to Paisa Watch</H>
          <Text style={{ color: C.sub, lineHeight: 21 }}>
            This app builds your spending, balances and investments automatically from the alert SMS your banks, credit
            cards and mutual-fund registrars (CAMS / KFintech) already send you. Nothing is typed in and nothing leaves
            your phone.
            {'\n\n'}
            {d.permission === 'denied'
              ? 'SMS access was declined. Allow it to get started, or explore with sample data.'
              : 'Allow SMS access to get started. Also allow notifications to get alerts for bank charges, big payments and card bills as they happen.'}
          </Text>
          <Button label="Allow SMS access & scan" onPress={() => d.refresh(true)} />
          {d.permission === 'denied' ? (
            <Button label="Open app settings" kind="ghost" onPress={() => Linking.openSettings()} />
          ) : null}
          <Button label="Explore with sample data" kind="ghost" onPress={() => d.setDemoMode(true)} />
        </Card>
      </ScrollView>
    );
  }

  return (
    <ScrollView
      contentContainerStyle={{ padding: 16 }}
      refreshControl={<RefreshControl refreshing={d.loading} onRefresh={() => d.refresh()} tintColor={C.accent} />}
    >
      {d.demoMode ? (
        <Text style={{ color: C.amber, marginBottom: 10 }}>Showing sample data. Turn off in Settings.</Text>
      ) : null}
      <Card>
        <Label>Net worth</Label>
        <Big>{inr(net)}</Big>
        <Row style={{ marginTop: 14 }}>
          <Stat label="Bank" value={inr(cash)} />
          <Stat label="Investments" value={inr(invested)} />
          <Stat label="Card dues" value={inr(cardDue)} color={cardDue ? C.red : undefined} />
        </Row>
      </Card>

      <Card>
        <Label>This month</Label>
        <Row style={{ marginTop: 8 }}>
          <Stat label="Spent" value={inr(thisMonth.spend)} />
          <Stat label="Income" value={inr(thisMonth.income)} color={C.accent} />
          <Stat label="Invested" value={inr(thisMonth.invested)} color={C.blue} />
        </Row>
      </Card>

      {saving > 0 ? (
        <Card style={{ backgroundColor: '#13261E', borderColor: '#1F4A36' }}>
          <Label>You could save</Label>
          <Big color={C.accent}>{inr(saving)}/month</Big>
          <Text style={{ color: C.sub, marginTop: 4 }}>
            {d.waste.length} issue(s) found in the last 90 days · {inr(saving * 12)} a year
          </Text>
          <Button label="See where money is leaking" onPress={() => go('insights')} />
        </Card>
      ) : null}

      <H>Accounts</H>
      <Card>
        {accounts.length === 0 ? <Empty text="No accounts detected yet." /> : null}
        {accounts.map((a) => (
          <Row key={a.key} style={{ justifyContent: 'space-between', paddingVertical: 8 }}>
            <View style={{ flex: 1 }}>
              <Text style={{ color: C.text, fontWeight: '600' }}>
                {a.institution} {a.kind === 'credit_card' ? 'Credit Card' : 'A/c'} ••{a.last4 || '??'}
              </Text>
              <Text style={{ color: C.sub, fontSize: 12 }}>
                {a.asOf ? `updated ${new Date(a.asOf).toLocaleDateString('en-IN')}` : 'balance not reported in SMS'}
                {a.kind === 'credit_card' && a.dueDate != null && (a.balance ?? 0) > 0
                  ? ` · pay by ${new Date(a.dueDate).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}`
                  : ''}
                {a.kind === 'credit_card' && a.statementDue != null && (a.balance ?? 0) === 0 ? ' · last bill paid ✓' : ''}
                {a.kind === 'credit_card' && a.availableLimit != null ? ` · limit left ${inr(a.availableLimit)}` : ''}
              </Text>
            </View>
            <Text style={{ color: a.kind === 'credit_card' && (a.balance ?? 0) > 0 ? C.red : C.text, fontWeight: '700' }}>
              {a.balance == null ? '—' : (a.kind === 'credit_card' ? 'Due ' : '') + inr(a.balance)}
            </Text>
          </Row>
        ))}
      </Card>

      <H>Spending, last 6 months</H>
      <Card>
        {months.map((m) => (
          <BarRow
            key={m.month}
            label={`${MONTHS[parseInt(m.month.slice(5), 10) - 1]} ${m.month.slice(0, 4)}`}
            value={m.spend}
            max={maxSpend}
            color={m.spend > m.income && m.income > 0 ? C.red : C.blue}
          />
        ))}
      </Card>

      {d.waste.length ? (
        <>
          <H>Top issues</H>
          {d.waste.slice(0, 2).map((i) => (
            <InsightCard key={i.id} i={i} onPress={() => go('insights')} />
          ))}
        </>
      ) : null}

      <Text style={{ color: C.sub, fontSize: 12, textAlign: 'center', marginVertical: 12 }}>
        {d.smsCount} alerts scanned · {transactions.length} transactions
        {d.lastSync ? ` · ${new Date(d.lastSync).toLocaleTimeString('en-IN')}` : ''}
      </Text>
    </ScrollView>
  );
}
