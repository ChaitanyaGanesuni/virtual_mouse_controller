import { useState } from 'react';
import { Linking, View } from 'react-native';

import { AnimatedNumber, FadeIn, PressScale } from '../../components/anim';
import Icon from '../../components/Icon';
import { Button, Card, CategoryBubble, Empty, Label, Pill, Row, Section, Sheet, T } from '../../components/ui';
import { inr } from '../../lib/analysis';
import { GENERIC_STEPS, type SubStatus, type SubscriptionView } from '../../lib/subscriptions';
import { useData } from '../../store';
import { C, F } from '../../theme';

const fmt = (t: number) => new Date(t).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
const every = (d: number) => (d === 30 ? 'month' : d === 365 ? 'year' : d === 7 ? 'week' : `${d} days`);

export default function SubscriptionsSection() {
  const d = useData();
  const [open, setOpen] = useState<SubscriptionView | null>(null);
  const subs = d.subscriptions;
  const active = subs.filter((s) => s.status !== 'cancelled' || s.chargedAfterCancel);
  const yearly = active.reduce((s, x) => s + x.yearlyCost, 0);
  const unreviewed = subs.filter((s) => s.status === 'unreviewed').length;
  const reviewDue = unreviewed > 0 || Date.now() - d.extras.subsReviewedAt > 30 * 86_400_000;

  const setStatus = async (s: SubscriptionView, status: SubStatus) => {
    await d.setExtra('subs', { ...d.extras.subs, [s.id]: { status, at: Date.now() } });
    if (subs.every((x) => x.id === s.id || (d.extras.subs[x.id]?.status ?? 'unreviewed') !== 'unreviewed')) {
      await d.setExtra('subsReviewedAt', Date.now());
    }
  };

  return (
    <View>
      <FadeIn>
        <Card>
          <Label>You pay for subscriptions</Label>
          <Row style={{ alignItems: 'flex-end', marginTop: 4 }}>
            <AnimatedNumber value={yearly} format={inr} style={{ fontFamily: F.black, fontSize: 30, color: C.text }} />
            <T size={14} color={C.sub} weight="semibold" style={{ marginLeft: 4, marginBottom: 5 }}>
              /year
            </T>
          </Row>
          <T size={12.5} color={C.sub}>
            {active.length} active · about {inr(yearly / 12)} a month
          </T>
          {reviewDue && subs.length ? (
            <Row style={{ marginTop: 12, backgroundColor: C.amber + '1A', padding: 10, borderRadius: 12 }}>
              <Icon name="eye" size={16} color={C.amber} />
              <T size={12.5} color={C.amber} style={{ flex: 1, marginLeft: 8 }}>
                {unreviewed ? `${unreviewed} to review. For each one: still using it?` : 'Monthly check: still using all of these?'}
              </T>
            </Row>
          ) : null}
        </Card>
      </FadeIn>

      {subs.length === 0 ? (
        <Card>
          <Empty title="No subscriptions found" text="Payments that repeat monthly or yearly will show up here." />
        </Card>
      ) : null}

      {subs.some((s) => s.chargedAfterCancel) ? <Section title="Charged after you cancelled" /> : null}
      {subs.map((s, i) => (
        <FadeIn key={s.id} index={i}>
          <Card style={s.chargedAfterCancel ? { borderColor: C.red } : undefined}>
            <Row>
              <CategoryBubble category={s.category} size={42} />
              <View style={{ flex: 1, marginLeft: 12 }}>
                <T size={15} weight="bold" lines={1}>
                  {s.service?.name ?? s.merchant}
                </T>
                <T size={12} color={C.sub}>
                  {inr(s.amount)} every {every(s.periodDays)} · {inr(s.yearlyCost)}/yr
                </T>
              </View>
              {s.status === 'keep' ? <Pill text="Keeping" color={C.green} icon="check" /> : null}
              {s.status === 'cancelled' && !s.chargedAfterCancel ? <Pill text="Cancelled" color={C.sub} icon="x" /> : null}
            </Row>
            {s.chargedAfterCancel ? (
              <T size={12.5} color={C.red} style={{ marginTop: 8 }}>
                You marked this cancelled on {fmt(d.extras.subs[s.id].at)}, but it was charged again. Check the mandate is revoked and ask for a refund.
              </T>
            ) : s.status !== 'cancelled' ? (
              <T size={12} color={C.faint} style={{ marginTop: 6 }}>
                Last charged {fmt(s.lastCharged)} · next around {fmt(s.nextDue)}
              </T>
            ) : null}
            <Row style={{ marginTop: 10, gap: 8 }}>
              {s.status === 'unreviewed' ? (
                <PressScale onPress={() => setStatus(s, 'keep')} style={{ flex: 1, paddingVertical: 10, borderRadius: 12, backgroundColor: C.green + '1A', alignItems: 'center' }}>
                  <T size={13} weight="bold" color={C.green}>
                    Still using it
                  </T>
                </PressScale>
              ) : null}
              <PressScale onPress={() => setOpen(s)} style={{ flex: 1, paddingVertical: 10, borderRadius: 12, backgroundColor: C.cardHi, alignItems: 'center' }}>
                <T size={13} weight="bold">
                  {s.status === 'cancelled' ? 'Cancel steps' : 'How to cancel'}
                </T>
              </PressScale>
            </Row>
          </Card>
        </FadeIn>
      ))}

      <Sheet visible={open != null} onClose={() => setOpen(null)} title={open ? `Cancel ${open.service?.name ?? open.merchant}` : ''}>
        {open ? (
          <View>
            <T size={13} color={C.sub} style={{ marginBottom: 12 }}>
              Saves {inr(open.yearlyCost)} a year.
            </T>
            {(open.service?.steps ?? []).concat(GENERIC_STEPS).map((st, i) => (
              <Row key={i} style={{ alignItems: 'flex-start', marginBottom: 10 }}>
                <View style={{ width: 22, height: 22, borderRadius: 11, backgroundColor: C.green + '22', alignItems: 'center', justifyContent: 'center', marginRight: 10 }}>
                  <T size={11} weight="bold" color={C.green}>
                    {i + 1}
                  </T>
                </View>
                <T size={13.5} style={{ flex: 1 }}>
                  {st}
                </T>
              </Row>
            ))}
            {open.service?.url ? <Button label="Open cancel page" icon="send" kind="ghost" onPress={() => Linking.openURL(open.service!.url!).catch(() => {})} /> : null}
            <Button
              label="I've cancelled it"
              icon="check"
              onPress={() => {
                setStatus(open, 'cancelled');
                setOpen(null);
              }}
            />
            <T size={11.5} color={C.faint} style={{ textAlign: 'center', marginTop: 8 }}>
              We'll warn you if it's charged again after today.
            </T>
          </View>
        ) : null}
      </Sheet>
    </View>
  );
}
