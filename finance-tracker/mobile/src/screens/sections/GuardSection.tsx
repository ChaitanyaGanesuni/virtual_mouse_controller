import { Linking, View } from 'react-native';

import { FadeIn, PressScale } from '../../components/anim';
import Icon, { type IconName } from '../../components/Icon';
import { CheckArt, ShieldArt } from '../../components/Illustrations';
import { Card, Empty, IconBubble, Pill, Row, Section, T } from '../../components/ui';
import { inr } from '../../lib/analysis';
import { CYBERCRIME_HELPLINE, type FailedPayment, type Signal } from '../../lib/guard';
import { useData } from '../../store';
import { C } from '../../theme';

const KIND: Record<Signal['kind'], { icon: IconName; color: string }> = {
  duplicate: { icon: 'repeat', color: C.amber },
  'new-merchant': { icon: 'eye', color: C.blue },
  foreign: { icon: 'plane', color: C.red },
  'odd-hour': { icon: 'alert', color: C.orange },
};

const fmtDate = (t: number) => new Date(t).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
const call = (n: string) => Linking.openURL(`tel:${n}`).catch(() => {});

function ActionChip({ label, icon, color, onPress }: { label: string; icon: IconName; color: string; onPress: () => void }) {
  return (
    <PressScale onPress={onPress} style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 8, borderRadius: 12, backgroundColor: color + '1A', marginRight: 8, marginTop: 10 }}>
      <Icon name={icon} size={14} color={color} />
      <T size={12.5} weight="semibold" color={color} style={{ marginLeft: 6 }}>
        {label}
      </T>
    </PressScale>
  );
}

function SignalCard({ s, onDismiss, index }: { s: Signal; onDismiss: () => void; index: number }) {
  const k = KIND[s.kind];
  return (
    <FadeIn index={index}>
      <Card>
        <Row style={{ alignItems: 'flex-start' }}>
          <IconBubble icon={k.icon} color={k.color} size={42} />
          <View style={{ flex: 1, marginLeft: 12 }}>
            <T size={15} weight="bold">
              {s.title}
            </T>
            <T size={12} color={C.faint}>
              {fmtDate(s.date)} · {new Date(s.date).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' })}
            </T>
            <T size={13} color={C.sub} style={{ marginTop: 6 }}>
              {s.detail}
            </T>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
              {s.helpline ? <ActionChip label="Call bank" icon="bell" color={C.red} onPress={() => call(s.helpline!)} /> : null}
              {s.kind === 'foreign' || s.kind === 'odd-hour' ? (
                <ActionChip label={`Report fraud (${CYBERCRIME_HELPLINE})`} icon="shield" color={C.amber} onPress={() => call(CYBERCRIME_HELPLINE)} />
              ) : null}
              <ActionChip label="It was me" icon="check" color={C.green} onPress={onDismiss} />
            </View>
          </View>
        </Row>
      </Card>
    </FadeIn>
  );
}

const STATUS = {
  refunded: { label: 'Refunded', color: C.green, icon: 'check' as IconName },
  waiting: { label: 'Waiting for refund', color: C.amber, icon: 'calendar' as IconName },
  overdue: { label: 'Refund overdue', color: C.red, icon: 'alert' as IconName },
};

function FailedCard({ f, index }: { f: FailedPayment; index: number }) {
  const st = STATUS[f.status];
  return (
    <FadeIn index={index}>
      <Card>
        <Row style={{ justifyContent: 'space-between' }}>
          <Pill text={st.label} color={st.color} icon={st.icon} />
          <T size={12} color={C.faint}>
            {fmtDate(f.date)} · {f.mode}
          </T>
        </Row>
        <T size={20} weight="black" style={{ marginTop: 8 }}>
          {inr(f.amount)}
        </T>
        <T size={12.5} color={C.sub}>
          {f.institution} ••{f.last4 || '??'} · {f.rule}
        </T>
        {f.status === 'refunded' ? (
          <T size={12.5} color={C.green} style={{ marginTop: 6 }}>
            Came back on {fmtDate(f.refundedAt!)}
            {f.compensation > 0 ? `, late. The bank owed you about ${inr(f.compensation)} in compensation.` : ', on time.'}
          </T>
        ) : f.status === 'waiting' ? (
          <T size={12.5} color={C.sub} style={{ marginTop: 6 }}>
            Should be back by {fmtDate(f.dueBy)}. Nothing to do yet; we'll tell you if it's late.
          </T>
        ) : (
          <>
            <T size={12.5} color={C.red} style={{ marginTop: 6 }}>
              Past the deadline ({fmtDate(f.dueBy)}). Complain to your bank: they owe ₹100/day, about {inr(f.compensation)} so far.
              No answer in 30 days? Escalate to the RBI Ombudsman (cms.rbi.org.in).
            </T>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
              {f.helpline ? <ActionChip label="Call bank" icon="bell" color={C.red} onPress={() => call(f.helpline!)} /> : null}
              <ActionChip label="RBI complaint portal" icon="shield" color={C.blue} onPress={() => Linking.openURL('https://cms.rbi.org.in').catch(() => {})} />
            </View>
          </>
        )}
      </Card>
    </FadeIn>
  );
}

export default function GuardSection() {
  const d = useData();
  const open = d.failedPayments.filter((f) => f.status !== 'refunded');
  const done = d.failedPayments.filter((f) => f.status === 'refunded').slice(0, 5);
  const allClear = d.signals.length === 0 && open.length === 0;
  return (
    <View>
      <FadeIn>
        <Card>
          <Row>
            <ShieldArt size={74} />
            <View style={{ flex: 1, marginLeft: 12 }}>
              <T size={16} weight="bold">
                {allClear ? 'All clear' : `${d.signals.length + open.length} thing${d.signals.length + open.length > 1 ? 's' : ''} to check`}
              </T>
              <T size={12.5} color={C.sub}>
                Watching for double charges, big first-time payments, foreign and late-night card use, and failed payments that owe you a refund.
              </T>
            </View>
          </Row>
        </Card>
      </FadeIn>

      {d.signals.length ? <Section title="Unusual activity" /> : null}
      {d.signals.map((s, i) => (
        <SignalCard key={s.id} s={s} index={i} onDismiss={() => d.setExtra('guardDismissed', [...d.extras.guardDismissed, s.id])} />
      ))}

      <Section title="Failed payments" />
      {open.length === 0 && done.length === 0 ? (
        <Card>
          <Empty art={<CheckArt size={80} />} title="No failed payments" text="If money is debited but a payment fails, we'll track the refund against RBI deadlines." />
        </Card>
      ) : null}
      {[...open, ...done].map((f, i) => (
        <FailedCard key={f.id} f={f} index={i} />
      ))}

      <PressScale onPress={() => call(CYBERCRIME_HELPLINE)} style={{ marginTop: 6 }}>
        <Row style={{ backgroundColor: C.red + '14', borderRadius: 16, padding: 14 }}>
          <Icon name="shield" size={20} color={C.red} />
          <T size={13} color={C.red} weight="semibold" style={{ flex: 1, marginLeft: 10 }}>
            Lost money to online fraud? Call {CYBERCRIME_HELPLINE} (National Cybercrime Helpline) within hours. The sooner, the better the chance of freezing it.
          </T>
        </Row>
      </PressScale>
    </View>
  );
}
