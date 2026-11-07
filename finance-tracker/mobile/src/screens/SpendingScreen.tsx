import { useMemo, useState } from 'react';
import { FlatList, Modal, Pressable, ScrollView, Text, View } from 'react-native';

import { BarRow, Button, C, Card, Chip, Empty, H, Label, PALETTE, Row } from '../components/ui';
import { byCategory, byMerchant, inr, isSpend, monthKey } from '../lib/analysis';
import { ALL_CATEGORIES } from '../lib/categorizer';
import type { Transaction } from '../lib/types';
import { useData } from '../store';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export default function SpendingScreen() {
  const d = useData();
  const txns = d.ledger.transactions;
  const monthKeys = useMemo(() => {
    const now = new Date();
    return Array.from({ length: 6 }, (_, i) => monthKey(new Date(now.getFullYear(), now.getMonth() - i, 1).getTime()));
  }, []);
  const [month, setMonth] = useState(monthKeys[0]);
  const [cat, setCat] = useState<string | null>(null);
  const [editing, setEditing] = useState<Transaction | null>(null);

  const inMonth = useMemo(() => txns.filter((t) => monthKey(t.date) === month), [txns, month]);
  const cats = byCategory(inMonth);
  const total = cats.reduce((s, c) => s + c.amount, 0);
  const merchants = byMerchant(cat ? inMonth.filter((t) => t.category === cat) : inMonth, 5);
  const list = cat ? inMonth.filter((t) => t.category === cat) : inMonth;

  const header = (
    <View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginBottom: 8 }}>
        {monthKeys.map((m) => (
          <Chip
            key={m}
            label={`${MONTHS[parseInt(m.slice(5), 10) - 1]} ${m.slice(2, 4)}`}
            active={m === month}
            onPress={() => {
              setMonth(m);
              setCat(null);
            }}
          />
        ))}
      </ScrollView>
      <Card>
        <Label>Spent in {MONTHS[parseInt(month.slice(5), 10) - 1]}</Label>
        <Text style={{ color: C.text, fontSize: 26, fontWeight: '800', marginVertical: 6 }}>{inr(total)}</Text>
        {cats.length === 0 ? <Empty text="No spending found for this month." /> : null}
        {cats.map((c, i) => (
          <BarRow
            key={c.category}
            label={`${c.category} · ${c.count}`}
            value={c.amount}
            max={cats[0].amount}
            right={`${inr(c.amount)} · ${Math.round((c.amount / total) * 100)}%`}
            color={PALETTE[i % PALETTE.length]}
            active={cat === c.category}
            onPress={() => setCat(cat === c.category ? null : c.category)}
          />
        ))}
        <Text style={{ color: C.sub, fontSize: 12, marginTop: 6 }}>Tap a category to filter.</Text>
      </Card>
      {merchants.length ? (
        <Card>
          <Label>Top merchants{cat ? ` in ${cat}` : ''}</Label>
          {merchants.map((m) => (
            <Row key={m.merchant} style={{ justifyContent: 'space-between', paddingVertical: 6 }}>
              <Text style={{ color: C.text, flex: 1 }} numberOfLines={1}>
                {m.merchant} <Text style={{ color: C.sub }}>×{m.count}</Text>
              </Text>
              <Text style={{ color: C.text, fontWeight: '600' }}>{inr(m.amount)}</Text>
            </Row>
          ))}
        </Card>
      ) : null}
      <H>Transactions{cat ? ` · ${cat}` : ''}</H>
    </View>
  );

  return (
    <>
      <FlatList
        data={list}
        keyExtractor={(t) => t.id}
        ListHeaderComponent={header}
        contentContainerStyle={{ padding: 16 }}
        renderItem={({ item: t }) => (
          <Pressable onPress={() => setEditing(t)}>
            <Row style={{ paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: C.border }}>
              <View style={{ flex: 1, marginRight: 8 }}>
                <Text style={{ color: C.text, fontWeight: '600' }} numberOfLines={1}>
                  {t.merchant || t.category}
                </Text>
                <Text style={{ color: C.sub, fontSize: 12 }}>
                  {new Date(t.date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })} · {t.category} · {t.mode} ·{' '}
                  {t.institution} ••{t.last4}
                </Text>
              </View>
              <Text
                style={{
                  color: t.direction === 'credit' ? C.accent : isSpend(t) ? C.text : C.sub,
                  fontWeight: '700',
                }}
              >
                {t.direction === 'credit' ? '+' : '−'}
                {inr(t.amount)}
              </Text>
            </Row>
          </Pressable>
        )}
      />
      <Modal visible={editing != null} transparent animationType="slide" onRequestClose={() => setEditing(null)}>
        <View style={{ flex: 1, justifyContent: 'flex-end', backgroundColor: '#000a' }}>
          <View style={{ backgroundColor: C.card, padding: 16, borderTopLeftRadius: 16, borderTopRightRadius: 16, maxHeight: '80%' }}>
            {editing ? (
              <>
                <Text style={{ color: C.text, fontWeight: '700', fontSize: 16 }}>
                  {editing.merchant || 'Transaction'} · {inr(editing.amount)}
                </Text>
                <Text style={{ color: C.sub, fontSize: 12, marginVertical: 8 }}>{editing.body}</Text>
                <Label>Change category (applies to all from this merchant)</Label>
                <ScrollView style={{ marginTop: 8 }}>
                  <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
                    {ALL_CATEGORIES.map((c) => (
                      <Chip
                        key={c}
                        label={c}
                        active={c === editing.category}
                        onPress={() => {
                          d.setCategory(editing.id, c, true);
                          setEditing(null);
                        }}
                      />
                    ))}
                  </View>
                </ScrollView>
                <Button label="Close" kind="ghost" onPress={() => setEditing(null)} />
              </>
            ) : null}
          </View>
        </View>
      </Modal>
    </>
  );
}
