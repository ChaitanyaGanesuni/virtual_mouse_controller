import { useState } from 'react';
import { TextInput, View } from 'react-native';

import { AnimatedNumber, FadeIn, PressScale } from '../../components/anim';
import Icon, { type IconName } from '../../components/Icon';
import { Button, Card, Chip, Empty, Label, Pill, Row, Section, Sheet, T } from '../../components/ui';
import { inr } from '../../lib/analysis';
import { DEFAULT_RATE, prepayImpact, type Loan } from '../../lib/loans';
import { useData } from '../../store';
import { C, F } from '../../theme';

const ICON: Record<Loan['type'], IconName> = {
  home: 'home',
  car: 'car',
  personal: 'wallet',
  education: 'book',
  gold: 'sparkle',
  consumer: 'bag',
  other: 'bank',
};
const yrs = (months: number) => {
  const total = Math.round(months);
  const y = Math.floor(total / 12);
  const m = total % 12;
  if (!y) return `${m} month${m === 1 ? '' : 's'}`;
  return `${y} yr${y > 1 ? 's' : ''}${m ? ` ${m} mo` : ''}`;
};

function Prepay({ loan }: { loan: Loan }) {
  const [x, setX] = useState(loan.outstanding ? Math.min(100_000, Math.round(loan.outstanding * 0.1 / 10_000) * 10_000 || 50_000) : 50_000);
  if (loan.outstanding == null) return null;
  const imp = prepayImpact(loan.outstanding, loan.rate, loan.emi, x);
  const options = [25_000, 50_000, 100_000, 200_000, 500_000].filter((v) => v < loan.outstanding!);
  return (
    <View style={{ marginTop: 14, backgroundColor: C.bg2, borderRadius: 16, padding: 14 }}>
      <Label>If you prepay</Label>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 8 }}>
        {options.map((v) => (
          <Chip key={v} label={inr(v)} active={v === x} onPress={() => setX(v)} />
        ))}
      </View>
      <Row style={{ marginTop: 4 }}>
        <View style={{ flex: 1 }}>
          <T size={11.5} color={C.sub}>
            Interest saved
          </T>
          <AnimatedNumber value={imp.interestSaved} format={inr} duration={600} style={{ fontFamily: F.black, fontSize: 20, color: C.green }} />
        </View>
        <View style={{ flex: 1 }}>
          <T size={11.5} color={C.sub}>
            Done sooner by
          </T>
          <T size={20} weight="black" color={C.green}>
            {yrs(imp.monthsSaved)}
          </T>
        </View>
      </Row>
      <T size={11.5} color={C.faint} style={{ marginTop: 6 }}>
        Same EMI, shorter loan. Usually the better choice. Check prepayment charges (none on floating-rate home loans).
      </T>
    </View>
  );
}

function LoanEditor({ loan, onClose }: { loan: Loan | null; onClose: () => void }) {
  const d = useData();
  const cur = loan ? d.extras.loans[loan.id] ?? {} : {};
  const [rate, setRate] = useState(loan ? (cur.rate ?? loan.rate) * 100 : 9);
  const [os, setOs] = useState(cur.outstanding ? String(Math.round(cur.outstanding)) : '');
  const input = { color: C.text, fontFamily: F.semibold, fontSize: 16, backgroundColor: C.card, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 11, marginTop: 6, borderWidth: 0.5, borderColor: C.border } as const;
  if (!loan) return null;
  return (
    <Sheet visible onClose={onClose} title={loan.name}>
      <View>
        <Label>Interest rate (per year)</Label>
        <Row style={{ marginTop: 8 }}>
          <PressScale onPress={() => setRate(Math.max(1, Math.round((rate - 0.25) * 100) / 100))} style={{ width: 40, height: 40, borderRadius: 12, backgroundColor: C.cardHi, alignItems: 'center', justifyContent: 'center' }}>
            <T size={20} weight="bold" color={C.accent}>
              −
            </T>
          </PressScale>
          <T size={22} weight="black" style={{ minWidth: 100, textAlign: 'center' }}>
            {rate.toFixed(2)}%
          </T>
          <PressScale onPress={() => setRate(Math.min(40, Math.round((rate + 0.25) * 100) / 100))} style={{ width: 40, height: 40, borderRadius: 12, backgroundColor: C.cardHi, alignItems: 'center', justifyContent: 'center' }}>
            <T size={20} weight="bold" color={C.accent}>
              +
            </T>
          </PressScale>
        </Row>
        <T size={11.5} color={C.faint} style={{ marginTop: 4 }}>
          Typical {loan.type} loan: {(DEFAULT_RATE[loan.type] * 100).toFixed(1)}%. Your loan statement has the exact rate.
        </T>
        <View style={{ height: 14 }} />
        <Label>Outstanding today (optional)</Label>
        <TextInput value={os} onChangeText={setOs} keyboardType="number-pad" placeholder={loan.outstanding ? String(Math.round(loan.outstanding)) : 'From your loan statement'} placeholderTextColor={C.faint} style={input} />
        <T size={11.5} color={C.faint} style={{ marginTop: 4 }}>
          {loan.outstandingSource === 'sms' ? 'Found in your lender\'s SMS. Only change it if it\'s wrong.' : 'Not in your SMS. Enter it once and we keep it up to date with each EMI.'}
        </T>
        <Button
          label="Save"
          icon="check"
          onPress={() => {
            const amount = parseInt(os.replace(/[^\d]/g, ''), 10);
            d.setExtra('loans', {
              ...d.extras.loans,
              [loan.id]: { rate: rate / 100, ...(amount > 0 ? { outstanding: amount, asOf: Date.now() } : cur.outstanding ? { outstanding: cur.outstanding, asOf: cur.asOf } : {}) },
            });
            onClose();
          }}
        />
      </View>
    </Sheet>
  );
}

export default function LoansSection() {
  const d = useData();
  const [editing, setEditing] = useState<Loan | null>(null);
  const loans = d.loans;
  const totalEmi = loans.reduce((s, l) => s + l.emi, 0);
  const totalOs = loans.reduce((s, l) => s + (l.outstanding ?? 0), 0);
  return (
    <View>
      {loans.length === 0 ? (
        <Card>
          <Empty title="No loans found" text="EMIs debited from your account (home, car, personal, consumer loans) show up here automatically." />
        </Card>
      ) : (
        <FadeIn>
          <Card>
            <Label>Your loans</Label>
            <Row style={{ marginTop: 8 }}>
              <View style={{ flex: 1 }}>
                <T size={12} color={C.sub}>
                  EMIs per month
                </T>
                <T size={22} weight="black">
                  {inr(totalEmi)}
                </T>
              </View>
              {totalOs > 0 ? (
                <View style={{ flex: 1 }}>
                  <T size={12} color={C.sub}>
                    Still to repay
                  </T>
                  <T size={22} weight="black" color={C.red}>
                    {inr(totalOs)}
                  </T>
                </View>
              ) : null}
            </Row>
          </Card>
        </FadeIn>
      )}

      {loans.map((l, i) => {
        return (
          <FadeIn key={l.id} index={i + 1}>
            <Card>
              <Row>
                <View style={{ width: 44, height: 44, borderRadius: 14, backgroundColor: C.indigo + '22', alignItems: 'center', justifyContent: 'center' }}>
                  <Icon name={ICON[l.type]} size={22} color={C.indigo} />
                </View>
                <View style={{ flex: 1, marginLeft: 12 }}>
                  <T size={15} weight="bold" lines={1}>
                    {l.name}
                  </T>
                  <T size={12} color={C.sub}>
                    {inr(l.emi)}/month · {l.emisPaid} EMIs seen · {(l.rate * 100).toFixed(2)}%{l.rateIsDefault ? ' (typical)' : ''}
                  </T>
                </View>
                <PressScale onPress={() => setEditing(l)} style={{ padding: 8 }}>
                  <Icon name="sliders" size={18} color={C.sub} />
                </PressScale>
              </Row>
              {l.outstanding != null ? (
                <>
                  <Row style={{ marginTop: 12 }}>
                    <View style={{ flex: 1 }}>
                      <T size={11.5} color={C.sub}>
                        Outstanding
                      </T>
                      <T size={17} weight="black">
                        {inr(l.outstanding)}
                      </T>
                    </View>
                    <View style={{ flex: 1 }}>
                      <T size={11.5} color={C.sub}>
                        Interest still ahead
                      </T>
                      <T size={17} weight="black" color={C.red}>
                        {l.interestLeft != null ? inr(l.interestLeft) : '—'}
                      </T>
                    </View>
                  </Row>
                  {l.monthsLeft != null ? (
                    <View style={{ marginTop: 8 }}>
                      <T size={12} color={C.sub}>
                        {l.monthsLeft != null ? `${yrs(l.monthsLeft)} to go` : ''}
                        {l.payoffDate ? ` · debt-free by ${new Date(l.payoffDate).toLocaleDateString('en-IN', { month: 'short', year: 'numeric' })}` : ''}
                      </T>
                    </View>
                  ) : null}
                  {l.monthsLeft == null ? (
                    <Pill text="EMI doesn't cover interest at this rate: check the rate" color={C.amber} icon="alert" />
                  ) : null}
                  <Prepay loan={l} />
                </>
              ) : (
                <PressScale onPress={() => setEditing(l)} style={{ marginTop: 12, backgroundColor: C.amber + '14', borderRadius: 12, padding: 12 }}>
                  <T size={12.5} color={C.amber}>
                    Outstanding amount isn't in your SMS. Tap to add it once from your loan statement to see interest left and the prepayment calculator.
                  </T>
                </PressScale>
              )}
            </Card>
          </FadeIn>
        );
      })}
      {editing ? <LoanEditor key={editing.id} loan={editing} onClose={() => setEditing(null)} /> : null}
      {loans.length ? (
        <>
          <Section title="Good to know" />
          <Card>
            <T size={12.5} color={C.sub}>
              Clear the most expensive debt first: credit cards (~40%) and personal loans before home loans. Prepaying a home loan at 8.5% beats most
              debt funds after tax, but keep your emergency fund intact.
            </T>
          </Card>
        </>
      ) : null}
    </View>
  );
}
