import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View, type ViewStyle } from 'react-native';

import type { Insight } from '../lib/types';
import { inr } from '../lib/analysis';

export const C = {
  bg: '#0E1116',
  card: '#171B22',
  cardAlt: '#1F242D',
  border: '#272D38',
  text: '#E8ECF2',
  sub: '#8B95A5',
  accent: '#3DDC97',
  red: '#FF6B6B',
  amber: '#F5B841',
  blue: '#5AA9FF',
  violet: '#A78BFA',
};

export const PALETTE = ['#5AA9FF', '#3DDC97', '#F5B841', '#FF6B6B', '#A78BFA', '#4FD1C5', '#F687B3', '#9AE6B4', '#FBD38D', '#90CDF4'];

export function Card({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  return <View style={[s.card, style]}>{children}</View>;
}

export function H({ children }: { children: ReactNode }) {
  return <Text style={s.h}>{children}</Text>;
}

export function Label({ children }: { children: ReactNode }) {
  return <Text style={s.label}>{children}</Text>;
}

export function Big({ children, color }: { children: ReactNode; color?: string }) {
  return <Text style={[s.big, color ? { color } : null]}>{children}</Text>;
}

export function Row({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  return <View style={[s.row, style]}>{children}</View>;
}

export function Stat({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <View style={{ flex: 1 }}>
      <Label>{label}</Label>
      <Text style={[s.stat, color ? { color } : null]}>{value}</Text>
    </View>
  );
}

/** Horizontal bar with label and value. */
export function BarRow({
  label,
  value,
  max,
  color = C.blue,
  right,
  onPress,
  active,
}: {
  label: string;
  value: number;
  max: number;
  color?: string;
  right?: string;
  onPress?: () => void;
  active?: boolean;
}) {
  const pct = max > 0 ? Math.max(2, (value / max) * 100) : 0;
  return (
    <Pressable onPress={onPress} style={[s.barRow, active ? { backgroundColor: C.cardAlt } : null]}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
        <Text style={s.barLabel} numberOfLines={1}>
          {label}
        </Text>
        <Text style={s.barValue}>{right ?? inr(value)}</Text>
      </Row>
      <View style={s.track}>
        <View style={[s.fill, { width: `${pct}%`, backgroundColor: color }]} />
      </View>
    </Pressable>
  );
}

/** One stacked bar showing shares, plus legend. */
export function StackBar({ parts }: { parts: { label: string; value: number; color: string }[] }) {
  const total = parts.reduce((x, p) => x + p.value, 0) || 1;
  return (
    <View>
      <View style={[s.track, { height: 14, flexDirection: 'row', overflow: 'hidden' }]}>
        {parts.map((p) => (
          <View key={p.label} style={{ width: `${(p.value / total) * 100}%`, backgroundColor: p.color }} />
        ))}
      </View>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 8 }}>
        {parts.map((p) => (
          <Row key={p.label} style={{ marginRight: 14, marginBottom: 4 }}>
            <View style={{ width: 10, height: 10, borderRadius: 2, backgroundColor: p.color, marginRight: 6 }} />
            <Text style={{ color: C.sub, fontSize: 12 }}>
              {p.label} {Math.round((p.value / total) * 100)}%
            </Text>
          </Row>
        ))}
      </View>
    </View>
  );
}

const sevColor = { high: C.red, medium: C.amber, low: C.blue };

export function InsightCard({ i, onPress }: { i: Insight; onPress?: () => void }) {
  return (
    <Pressable onPress={onPress}>
      <Card style={{ borderLeftWidth: 4, borderLeftColor: sevColor[i.severity] }}>
        <Text style={s.insTitle}>{i.title}</Text>
        <Text style={s.insDetail}>{i.detail}</Text>
        {i.monthlySaving ? (
          <Text style={s.save}>Potential saving ≈ {inr(i.monthlySaving)}/month</Text>
        ) : null}
      </Card>
    </Pressable>
  );
}

export function Chip({ label, active, onPress }: { label: string; active?: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[s.chip, active ? { backgroundColor: C.accent, borderColor: C.accent } : null]}>
      <Text style={{ color: active ? C.bg : C.text, fontSize: 13, fontWeight: '600' }}>{label}</Text>
    </Pressable>
  );
}

export function Button({ label, onPress, kind = 'primary' }: { label: string; onPress: () => void; kind?: 'primary' | 'ghost' }) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [s.btn, kind === 'ghost' ? s.btnGhost : null, pressed ? { opacity: 0.7 } : null]}
    >
      <Text style={{ color: kind === 'ghost' ? C.text : C.bg, fontWeight: '700' }}>{label}</Text>
    </Pressable>
  );
}

export function Empty({ text }: { text: string }) {
  return <Text style={{ color: C.sub, textAlign: 'center', marginVertical: 24, lineHeight: 20 }}>{text}</Text>;
}

export const s = StyleSheet.create({
  card: { backgroundColor: C.card, borderRadius: 14, padding: 16, marginBottom: 12, borderWidth: 1, borderColor: C.border },
  h: { color: C.text, fontSize: 18, fontWeight: '700', marginTop: 8, marginBottom: 10 },
  label: { color: C.sub, fontSize: 12, textTransform: 'uppercase', letterSpacing: 0.6 },
  big: { color: C.text, fontSize: 30, fontWeight: '800', marginTop: 4 },
  stat: { color: C.text, fontSize: 17, fontWeight: '700', marginTop: 2 },
  row: { flexDirection: 'row', alignItems: 'center' },
  barRow: { paddingVertical: 6, paddingHorizontal: 4, borderRadius: 8 },
  barLabel: { color: C.text, fontSize: 14, flex: 1, marginRight: 8 },
  barValue: { color: C.text, fontSize: 14, fontWeight: '600' },
  track: { height: 8, backgroundColor: C.cardAlt, borderRadius: 6 },
  fill: { height: '100%', borderRadius: 6 },
  insTitle: { color: C.text, fontSize: 16, fontWeight: '700', marginBottom: 6 },
  insDetail: { color: C.sub, fontSize: 14, lineHeight: 20 },
  save: { color: C.accent, fontSize: 14, fontWeight: '700', marginTop: 10 },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: C.border,
    marginRight: 8,
    marginBottom: 8,
  },
  btn: { backgroundColor: C.accent, borderRadius: 10, paddingVertical: 12, alignItems: 'center', marginTop: 8 },
  btnGhost: { backgroundColor: 'transparent', borderWidth: 1, borderColor: C.border },
});
