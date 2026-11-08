import { useMemo, useState } from 'react';
import { Animated, LayoutAnimation, ScrollView, SectionList, TextInput, View } from 'react-native';
import { useScreenScroll } from '../themeContext';

import { AnimatedNumber, FadeIn, PressScale } from '../components/anim';
import { Donut } from '../components/charts';
import Icon from '../components/Icon';
import { Card, CategoryBubble, Chip, Empty, Label, Pill, Row, Section, Sheet, T } from '../components/ui';
import { byCategory, byMerchant, inr, isSpend, monthKey } from '../lib/analysis';
import { ALL_CATEGORIES } from '../lib/categorizer';
import type { Transaction } from '../lib/types';
import { useData } from '../store';
import { C, F, catMeta } from '../theme';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const dayLabel = (ms: number) => {
  const d = new Date(ms);
  const today = new Date();
  const y = new Date(Date.now() - 86_400_000);
  if (d.toDateString() === today.toDateString()) return 'Today';
  if (d.toDateString() === y.toDateString()) return 'Yesterday';
  return d.toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' });
};

function TxnRow({ t, onPress }: { t: Transaction; onPress: () => void }) {
  const credit = t.direction === 'credit';
  const counted = isSpend(t);
  return (
    <PressScale onPress={onPress} scaleTo={0.98} style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 11 }}>
      <CategoryBubble category={t.category} size={42} />
      <View style={{ flex: 1, marginLeft: 12, marginRight: 8 }}>
        <T size={15} weight="semibold" lines={1}>
          {t.merchant || t.category}
        </T>
        <T size={12} color={C.sub} lines={1}>
          {t.category} · {t.mode} · {t.institution} ••{t.last4}
        </T>
      </View>
      <View style={{ alignItems: 'flex-end' }}>
        <T size={15} weight="bold" color={credit ? C.green : counted ? C.text : C.sub}>
          {credit ? '+' : '−'}
          {inr(t.amount)}
        </T>
        <T size={11} color={C.faint}>
          {new Date(t.date).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' })}
        </T>
      </View>
    </PressScale>
  );
}

const AnimatedSectionList = Animated.createAnimatedComponent(SectionList<Transaction, { title: string; total: number }>);

export default function SpendingScreen() {
  const d = useData();
  const scroll = useScreenScroll();
  const txns = d.ledger.transactions;
  const monthKeys = useMemo(() => {
    const now = new Date();
    return Array.from({ length: 6 }, (_, i) => monthKey(new Date(now.getFullYear(), now.getMonth() - i, 1).getTime()));
  }, []);
  const [month, setMonth] = useState(monthKeys[0]);
  const [cat, setCat] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState<Transaction | null>(null);

  const inMonth = useMemo(() => txns.filter((t) => monthKey(t.date) === month), [txns, month]);
  const cats = byCategory(inMonth);
  const total = cats.reduce((s, c) => s + c.amount, 0);
  const merchants = byMerchant(cat ? inMonth.filter((t) => t.category === cat) : inMonth, 5);
  const q = query.trim().toLowerCase();
  const list = inMonth.filter(
    (t) => (!cat || t.category === cat) && (!q || `${t.merchant} ${t.category} ${t.body}`.toLowerCase().includes(q)),
  );
  const sections = useMemo(() => {
    const m = new Map<string, Transaction[]>();
    for (const t of list) {
      const k = dayLabel(t.date);
      m.set(k, [...(m.get(k) ?? []), t]);
    }
    return [...m.entries()].map(([title, data]) => ({
      title,
      data,
      total: data.filter(isSpend).reduce((s, t) => s + t.amount, 0),
    }));
  }, [list]);

  const pick = (c: string | null) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setCat(c);
  };

  const header = (
    <View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginHorizontal: -16, marginBottom: 6 }} contentContainerStyle={{ paddingHorizontal: 16 }}>
        {monthKeys.map((m) => (
          <Chip
            key={m}
            label={`${MONTHS[parseInt(m.slice(5), 10) - 1]} ${m.slice(2, 4)}`}
            active={m === month}
            onPress={() => {
              setMonth(m);
              pick(null);
            }}
          />
        ))}
      </ScrollView>

      <FadeIn key={month}>
        <Card>
          {cats.length === 0 ? (
            <Empty title="Nothing spent" text="No spending found for this month yet." />
          ) : (
            <>
              <View style={{ alignItems: 'center', marginBottom: 14 }}>
                <Donut
                  size={200}
                  thickness={20}
                  data={cats.map((c) => ({ value: c.amount, color: catMeta(c.category).color }))}
                  center={
                    <View style={{ alignItems: 'center' }}>
                      <Label>{cat ?? 'Spent'}</Label>
                      <AnimatedNumber
                        value={cat ? cats.find((c) => c.category === cat)?.amount ?? 0 : total}
                        format={inr}
                        style={{ fontFamily: F.black, fontSize: 24, color: C.text, marginTop: 2 }}
                      />
                      <T size={11} color={C.sub}>
                        {cat ? `${Math.round(((cats.find((c) => c.category === cat)?.amount ?? 0) / total) * 100)}% of month` : `${inMonth.filter(isSpend).length} payments`}
                      </T>
                    </View>
                  }
                />
              </View>
              {cats.map((c, i) => {
                const m = catMeta(c.category);
                const active = cat === c.category;
                return (
                  <FadeIn key={c.category} index={i}>
                    <PressScale
                      onPress={() => pick(active ? null : c.category)}
                      scaleTo={0.98}
                      style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingVertical: 8,
                        paddingHorizontal: 8,
                        marginHorizontal: -8,
                        borderRadius: 14,
                        backgroundColor: active ? m.color + '1A' : 'transparent',
                      }}
                    >
                      <CategoryBubble category={c.category} size={34} />
                      <View style={{ flex: 1, marginLeft: 10 }}>
                        <Row style={{ justifyContent: 'space-between' }}>
                          <T size={14} weight="semibold" lines={1} style={{ flex: 1 }}>
                            {c.category}
                          </T>
                          <T size={14} weight="bold">
                            {inr(c.amount)}
                          </T>
                        </Row>
                        <Row style={{ marginTop: 5 }}>
                          <View style={{ flex: 1, height: 5, backgroundColor: C.cardHi, borderRadius: 3, marginRight: 8 }}>
                            <View style={{ width: `${(c.amount / cats[0].amount) * 100}%`, height: 5, backgroundColor: m.color, borderRadius: 3 }} />
                          </View>
                          <T size={11} color={C.sub}>
                            {Math.round((c.amount / total) * 100)}% · {c.count}
                          </T>
                        </Row>
                      </View>
                    </PressScale>
                  </FadeIn>
                );
              })}
            </>
          )}
        </Card>
      </FadeIn>

      {merchants.length ? (
        <>
          <Section title={cat ? `Top in ${cat}` : 'Top merchants'} />
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginHorizontal: -16 }} contentContainerStyle={{ paddingHorizontal: 16 }}>
            {merchants.map((m, i) => (
              <FadeIn key={m.merchant} index={i}>
                <View style={{ width: 130, backgroundColor: C.card, borderRadius: 18, padding: 14, marginRight: 10, borderWidth: 0.5, borderColor: C.border }}>
                  <View style={{ width: 34, height: 34, borderRadius: 12, backgroundColor: C.cardHi, alignItems: 'center', justifyContent: 'center' }}>
                    <T size={15} weight="black" color={C.green}>
                      {(m.merchant[0] ?? '?').toUpperCase()}
                    </T>
                  </View>
                  <T size={13} weight="semibold" lines={1} style={{ marginTop: 10 }}>
                    {m.merchant}
                  </T>
                  <T size={15} weight="black">
                    {inr(m.amount)}
                  </T>
                  <T size={11} color={C.sub}>
                    {m.count} payment{m.count > 1 ? 's' : ''}
                  </T>
                </View>
              </FadeIn>
            ))}
          </ScrollView>
        </>
      ) : null}

      <Section title={cat ? `${cat}` : 'Transactions'} />
      <Row style={{ backgroundColor: C.card, borderRadius: 14, paddingHorizontal: 12, marginBottom: 6, borderWidth: 0.5, borderColor: C.border }}>
        <Icon name="search" size={18} color={C.sub} />
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search merchant, category, amount…"
          placeholderTextColor={C.faint}
          style={{ flex: 1, color: C.text, fontFamily: F.medium, fontSize: 14, paddingVertical: 11, marginLeft: 8 }}
        />
        {query ? (
          <PressScale onPress={() => setQuery('')}>
            <Icon name="x" size={18} color={C.sub} />
          </PressScale>
        ) : null}
      </Row>
      {cat ? (
        <PressScale onPress={() => pick(null)} style={{ alignSelf: 'flex-start', marginBottom: 6 }}>
          <Pill text={`Filtered: ${cat}  ✕`} color={catMeta(cat).color} />
        </PressScale>
      ) : null}
    </View>
  );

  return (
    <>
      <AnimatedSectionList
        {...scroll}
        sections={sections}
        keyExtractor={(t) => t.id}
        ListHeaderComponent={header}
        contentContainerStyle={{ padding: 16, paddingBottom: 120 }}
        stickySectionHeadersEnabled={false}
        ListEmptyComponent={<Empty title="No transactions" text={q ? 'Nothing matches your search.' : 'Nothing here for this month.'} />}
        renderSectionHeader={({ section }) => (
          <Row style={{ justifyContent: 'space-between', marginTop: 14, marginBottom: 2 }}>
            <T size={12} weight="semibold" color={C.sub}>
              {section.title.toUpperCase()}
            </T>
            {section.total > 0 ? (
              <T size={12} color={C.faint}>
                {inr(section.total)}
              </T>
            ) : null}
          </Row>
        )}
        renderItem={({ item }) => <TxnRow t={item} onPress={() => setEditing(item)} />}
      />

      <Sheet visible={editing != null} onClose={() => setEditing(null)} title="Transaction">
        {editing ? (
          <ScrollView>
            <Row style={{ marginBottom: 12 }}>
              <CategoryBubble category={editing.category} size={48} />
              <View style={{ marginLeft: 12, flex: 1 }}>
                <T size={17} weight="bold" lines={1}>
                  {editing.merchant || editing.category}
                </T>
                <T size={22} weight="black" color={editing.direction === 'credit' ? C.green : C.text}>
                  {editing.direction === 'credit' ? '+' : '−'}
                  {inr(editing.amount)}
                </T>
              </View>
            </Row>
            <View style={{ backgroundColor: C.card, borderRadius: 14, padding: 12, marginBottom: 14 }}>
              <T size={11} color={C.faint} style={{ marginBottom: 4 }}>
                {new Date(editing.date).toLocaleString('en-IN')} · original SMS
              </T>
              <T size={12.5} color={C.sub}>
                {editing.body}
              </T>
            </View>
            <Label>Category · applies to every payment to this merchant</Label>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 10 }}>
              {ALL_CATEGORIES.map((c) => (
                <Chip
                  key={c}
                  label={c}
                  icon={catMeta(c).icon}
                  active={c === editing.category}
                  onPress={() => {
                    d.setCategory(editing.id, c, true);
                    setEditing(null);
                  }}
                />
              ))}
            </View>
          </ScrollView>
        ) : null}
      </Sheet>
    </>
  );
}
