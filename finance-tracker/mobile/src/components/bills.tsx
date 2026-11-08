import { View } from 'react-native';

import { inr } from '../lib/analysis';
import { BILL_ICON } from '../lib/bills';
import type { PriceChange } from '../lib/anomalies';
import { useData } from '../store';
import { C, catMeta } from '../theme';
import { FadeIn, PressScale } from './anim';
import Icon from './Icon';
import { Card, IconBubble, Pill, Row, Section, T } from './ui';

const fmt = (t: number) => new Date(t).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
const days = (t: number) => {
  const n = Math.ceil((t - Date.now()) / 86_400_000);
  return n < 0 ? `${-n}d overdue` : n === 0 ? 'today' : n === 1 ? 'tomorrow' : `in ${n} days`;
};

/** Bills due, prepaid plans expiring and low FASTag balances, all from SMS. */
export function BillsCard({ index }: { index: number }) {
  const d = useData();
  const open = d.bills.filter((b) => b.state !== 'paid');
  const paid = d.bills.filter((b) => b.state === 'paid');
  const soonPlans = d.expiries.filter((e) => e.daysLeft <= 10);
  if (!d.bills.length && !soonPlans.length && !d.fastagLow.length) return null;
  const total = open.reduce((s, b) => s + b.amount, 0);
  return (
    <>
      <Section title="Bills & renewals" />
      <FadeIn index={index}>
        <Card>
          {open.length ? (
            <T size={13} color={C.sub} style={{ marginBottom: 4 }}>
              {inr(total)} due across {open.length} bill{open.length > 1 ? 's' : ''}. We'll remind you 2 days before.
            </T>
          ) : (
            <Row style={{ marginBottom: 4 }}>
              <Icon name="check" size={16} color={C.green} />
              <T size={13} color={C.green} weight="semibold" style={{ marginLeft: 6 }}>
                All known bills are paid
              </T>
            </Row>
          )}
          {open.map((b) => (
            <Row key={b.id} style={{ paddingVertical: 9 }}>
              <IconBubble icon={BILL_ICON[b.kind]} color={b.state === 'overdue' ? C.red : C.blue} size={38} />
              <View style={{ flex: 1, marginLeft: 12 }}>
                <T size={14} weight="semibold">
                  {b.kind === 'insurance' ? `${b.biller} premium` : `${b.biller} ${b.kind === 'other' ? 'bill' : b.kind}`}
                </T>
                <T size={12} color={b.state === 'overdue' ? C.red : C.sub}>
                  {b.dueDate ? `Due ${fmt(b.dueDate)} · ${days(b.dueDate)}` : 'Due date not in SMS'}
                </T>
              </View>
              <T size={14} weight="bold">
                {inr(b.amount)}
              </T>
            </Row>
          ))}
          {soonPlans.map((e) => (
            <Row key={e.service} style={{ paddingVertical: 9 }}>
              <IconBubble icon="send" color={e.daysLeft <= 2 ? C.amber : C.teal} size={38} />
              <View style={{ flex: 1, marginLeft: 12 }}>
                <T size={14} weight="semibold">
                  {e.service} prepaid plan
                </T>
                <T size={12} color={e.daysLeft <= 2 ? C.amber : C.sub}>
                  Expires {fmt(e.expiresOn)} · {days(e.expiresOn)}
                </T>
              </View>
              <Pill text="Recharge" color={e.daysLeft <= 2 ? C.amber : C.teal} />
            </Row>
          ))}
          {d.fastagLow.map((a) => (
            <Row key={a.key} style={{ paddingVertical: 9 }}>
              <IconBubble icon="car" color={C.amber} size={38} />
              <View style={{ flex: 1, marginLeft: 12 }}>
                <T size={14} weight="semibold">
                  FASTag balance low
                </T>
                <T size={12} color={C.amber}>
                  {a.institution} · recharge to avoid double toll
                </T>
              </View>
              <T size={14} weight="bold" color={C.amber}>
                {inr(a.balance ?? 0)}
              </T>
            </Row>
          ))}
          {paid.slice(0, 3).map((b) => (
            <Row key={b.id} style={{ paddingVertical: 6, opacity: 0.6 }}>
              <Icon name="check" size={14} color={C.green} />
              <T size={12.5} color={C.sub} style={{ flex: 1, marginLeft: 8 }}>
                {b.biller} {inr(b.amount)} paid {b.paidOn ? fmt(b.paidOn) : ''}
              </T>
            </Row>
          ))}
        </Card>
      </FadeIn>
    </>
  );
}

/** Price rises on subscriptions and bills well above usual. */
export function PriceChangesSection() {
  const d = useData();
  if (!d.changes.length) return null;
  return (
    <>
      <Section title="Price changes" />
      {d.changes.map((c: PriceChange, i) => {
        const rise = c.kind === 'price-rise';
        const m = catMeta(c.category);
        return (
          <FadeIn key={c.id} index={i}>
            <Card style={{ borderLeftWidth: 4, borderLeftColor: C.amber }}>
              <Row style={{ alignItems: 'flex-start' }}>
                <IconBubble icon={rise ? 'trend' : m.icon} color={C.amber} size={42} />
                <View style={{ flex: 1, marginLeft: 12 }}>
                  <T size={15} weight="bold">
                    {rise ? `${c.name} costs more now` : `${c.name} bill is ${Math.round(c.pct * 100)}% higher`}
                  </T>
                  <Row style={{ marginTop: 6 }}>
                    <T size={14} color={C.sub} style={{ textDecorationLine: 'line-through' }}>
                      {inr(c.from)}
                    </T>
                    <Icon name="chevronRight" size={16} color={C.sub} />
                    <T size={15} weight="black" color={C.amber}>
                      {inr(c.to)}
                    </T>
                    <Pill text={`+${Math.round(c.pct * 100)}%`} color={C.amber} />
                  </Row>
                  <T size={12.5} color={C.sub} style={{ marginTop: 6 }}>
                    {rise
                      ? `That's ${inr(c.impact)} more a year. Check if a cheaper plan (annual, mobile-only, family share) works for you.`
                      : `${inr(c.impact)} above your usual. Check the reading, or look for something left running.`}
                  </T>
                  <PressScale
                    onPress={() => d.setExtra('changesSeen', [...d.extras.changesSeen, c.id])}
                    style={{ alignSelf: 'flex-start', marginTop: 10, paddingHorizontal: 12, paddingVertical: 7, borderRadius: 10, backgroundColor: C.cardHi }}
                  >
                    <T size={12.5} weight="semibold">
                      Got it
                    </T>
                  </PressScale>
                </View>
              </Row>
            </Card>
          </FadeIn>
        );
      })}
    </>
  );
}
