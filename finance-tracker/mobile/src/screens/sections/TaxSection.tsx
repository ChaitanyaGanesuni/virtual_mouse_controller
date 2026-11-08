import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import { useState } from 'react';
import { TextInput, View } from 'react-native';

import { FadeIn } from '../../components/anim';
import { Progress } from '../../components/charts';
import Icon from '../../components/Icon';
import Segmented from '../../components/Segmented';
import { Button, Card, Label, Pill, Row, Section, Sheet, T } from '../../components/ui';
import { logError } from '../../errorLog';
import { inr } from '../../lib/analysis';
import { rentReceiptsHtml, type RentProfile } from '../../lib/rent';
import { financialYear, LTCG_EXEMPTION } from '../../lib/tax';
import { useData } from '../../store';
import { C, F } from '../../theme';

function Field({ label, value, onChange, placeholder, caps }: { label: string; value: string; onChange: (v: string) => void; placeholder?: string; caps?: boolean }) {
  return (
    <View style={{ marginBottom: 12 }}>
      <Label>{label}</Label>
      <TextInput
        value={value}
        onChangeText={onChange}
        placeholder={placeholder}
        placeholderTextColor={C.faint}
        autoCapitalize={caps ? 'characters' : 'words'}
        style={{ color: C.text, fontFamily: F.medium, fontSize: 15, backgroundColor: C.card, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 10, marginTop: 6, borderWidth: 0.5, borderColor: C.border }}
      />
    </View>
  );
}

export default function TaxSection() {
  const d = useData();
  const fy = financialYear();
  const regime = d.extras.tax.regime;
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<RentProfile>(d.extras.rentProfile);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const rent = d.rentMonths;
  const rentTotal = rent.reduce((s, m) => s + m.amount, 0);
  const g = d.gains;
  const oldRegime = regime === 'old';

  const makePdf = async () => {
    setBusy(true);
    setMsg(null);
    try {
      const { uri } = await Print.printToFileAsync({ html: rentReceiptsHtml(d.extras.rentProfile, rent) });
      await Sharing.shareAsync(uri, { mimeType: 'application/pdf', dialogTitle: `Rent receipts ${fy.label}` });
    } catch (e) {
      logError('rent-pdf', e);
      setMsg("Couldn't create the PDF on this device.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <View>
      <FadeIn>
        <Card>
          <Row style={{ justifyContent: 'space-between' }}>
            <Label>{fy.label} · your tax regime</Label>
            <Pill text={`ends 31 Mar ${new Date(fy.end).getFullYear()}`} color={C.blue} icon="calendar" />
          </Row>
          <Segmented
            value={regime}
            onChange={(r) => d.setExtra('tax', { regime: r })}
            options={[
              { value: 'new', label: 'New (default)' },
              { value: 'old', label: 'Old' },
            ]}
          />
          <T size={12.5} color={C.sub} style={{ marginTop: 8 }}>
            {oldRegime
              ? 'Old regime: the deductions below cut your taxable income. Filling the gaps before 31 March can save up to 30% of the amount (plus cess) at the top slab.'
              : "New regime: 80C, 80D, 80TTA and HRA don't reduce your tax (only your employer's NPS contribution does). The figures below are still useful if you're deciding which regime to pick."}
          </T>
        </Card>
      </FadeIn>

      <Section title="Deductions so far" />
      {d.deductions.map((grp, i) => {
        const room = Math.max(0, grp.limit - grp.total);
        return (
          <FadeIn key={grp.section} index={i}>
            <Card style={!oldRegime ? { opacity: 0.75 } : undefined}>
              <Row style={{ justifyContent: 'space-between', marginBottom: 6 }}>
                <T size={14.5} weight="bold">
                  {grp.title}
                </T>
                <T size={13} color={C.sub}>
                  {inr(grp.claimed)} / {inr(grp.limit)}
                </T>
              </Row>
              <Progress value={grp.total / grp.limit} color={grp.total >= grp.limit ? C.green : C.amber} delay={i * 80} />
              {grp.items.map((it) => (
                <Row key={it.label} style={{ justifyContent: 'space-between', marginTop: 8 }}>
                  <T size={13} color={C.sub}>
                    {it.label}
                  </T>
                  <T size={13} weight="semibold">
                    {inr(it.amount)}
                  </T>
                </Row>
              ))}
              {grp.items.length === 0 ? (
                <T size={12.5} color={C.faint} style={{ marginTop: 8 }}>
                  Nothing found in your SMS for this yet.
                </T>
              ) : null}
              {oldRegime && room > 0 ? (
                <T size={12.5} color={C.green} weight="semibold" style={{ marginTop: 8 }}>
                  {inr(room)} of room left: could save up to {inr(room * 0.312)} in tax at the 30% slab.
                </T>
              ) : null}
              <T size={11.5} color={C.faint} style={{ marginTop: 6 }}>
                {grp.hint}
              </T>
            </Card>
          </FadeIn>
        );
      })}

      <Section title="Tax-free gains" />
      <FadeIn index={5}>
        <Card>
          <Label>Long-term equity gains you can still book tax-free</Label>
          <T size={26} weight="black" color={g.harvestable > 0 ? C.green : C.text} style={{ marginTop: 4 }}>
            {inr(g.harvestable)}
          </T>
          <T size={12.5} color={C.sub}>
            Up to {inr(LTCG_EXEMPTION)} of long-term gains on equity funds is tax-free each year. Selling and re-buying ("harvesting") resets your cost so this
            year's allowance isn't wasted. Watch for exit loads.
          </T>
          <View style={{ marginTop: 12 }}>
            {[
              ['Already booked this year (long-term)', g.realisedLongTerm],
              ['Already booked this year (short-term)', g.realisedShortTerm],
              ['Unbooked long-term gains (held > 1 yr)', g.unrealisedLongTerm],
              ['Unbooked short-term gains (taxed 20% if sold)', g.unrealisedShortTerm],
            ].map(([l, v]) => (
              <Row key={l as string} style={{ justifyContent: 'space-between', paddingVertical: 5 }}>
                <T size={12.5} color={C.sub} style={{ flex: 1 }}>
                  {l}
                </T>
                <T size={13} weight="semibold">
                  {inr(v as number)}
                </T>
              </Row>
            ))}
          </View>
          {g.maturingSoon.length ? (
            <T size={12.5} color={C.amber} style={{ marginTop: 8 }}>
              Wait before selling: {g.maturingSoon.length} purchase(s) turn long-term soon (first on{' '}
              {new Date(g.maturingSoon[0].date).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}), when the tax drops from 20% to 12.5%.
            </T>
          ) : null}
        </Card>
      </FadeIn>

      <Section title="Rent receipts (HRA)" />
      <FadeIn index={6}>
        <Card>
          <Row>
            <View style={{ width: 46, height: 46, borderRadius: 16, backgroundColor: C.indigo + '22', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="home" size={22} color={C.indigo} />
            </View>
            <View style={{ flex: 1, marginLeft: 12 }}>
              <T size={15} weight="bold">
                {rent.length ? `${inr(rentTotal)} rent in ${rent.length} month${rent.length > 1 ? 's' : ''}` : 'No rent payments found'}
              </T>
              <T size={12.5} color={C.sub}>
                {rent.length ? `Found from your bank alerts for ${fy.label}.` : 'Payments categorised as Rent & Housing show up here.'}
              </T>
            </View>
          </Row>
          {rent.map((m) => (
            <Row key={m.month} style={{ justifyContent: 'space-between', paddingVertical: 5 }}>
              <T size={13} color={C.sub}>
                {m.label}
              </T>
              <T size={13} weight="semibold">
                {inr(m.amount)}
              </T>
            </Row>
          ))}
          {rentTotal > 100_000 && !d.extras.rentProfile.landlordPan ? (
            <T size={12} color={C.amber} style={{ marginTop: 6 }}>
              Annual rent is above ₹1,00,000, so your employer needs your landlord's PAN.
            </T>
          ) : null}
          {rent.length ? (
            <Row style={{ gap: 10 }}>
              <Button
                label="Your details"
                icon="sliders"
                kind="ghost"
                style={{ flex: 1 }}
                onPress={() => {
                  setDraft({ ...d.extras.rentProfile, landlord: d.extras.rentProfile.landlord || rent[0].landlord });
                  setEditing(true);
                }}
              />
              <Button label={busy ? 'Making PDF…' : 'Receipts PDF'} icon="share" style={{ flex: 1 }} onPress={makePdf} />
            </Row>
          ) : null}
          {msg ? (
            <T size={12} color={C.red} style={{ marginTop: 6 }}>
              {msg}
            </T>
          ) : null}
        </Card>
      </FadeIn>

      <T size={11} color={C.faint} style={{ marginTop: 6, lineHeight: 16 }}>
        Estimates from your SMS for planning only, not tax advice. Limits as of FY 2025-26; confirm with a tax professional before filing.
      </T>

      <Sheet visible={editing} onClose={() => setEditing(false)} title="Details for rent receipts">
        <View>
          <T size={12.5} color={C.sub} style={{ marginBottom: 12 }}>
            Only needed on the receipts. Saved on this phone.
          </T>
          <Field label="Your name (tenant)" value={draft.tenant} onChange={(tenant) => setDraft({ ...draft, tenant })} />
          <Field label="Landlord's name" value={draft.landlord} onChange={(landlord) => setDraft({ ...draft, landlord })} />
          <Field label="Landlord's PAN (if rent > ₹1L/yr)" value={draft.landlordPan} onChange={(landlordPan) => setDraft({ ...draft, landlordPan: landlordPan.toUpperCase() })} caps />
          <Field label="Rented property address" value={draft.address} onChange={(address) => setDraft({ ...draft, address })} />
          <Button
            label="Save"
            icon="check"
            onPress={() => {
              d.setExtra('rentProfile', draft);
              setEditing(false);
            }}
          />
        </View>
      </Sheet>
    </View>
  );
}
