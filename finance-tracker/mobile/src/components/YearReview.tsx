import * as Sharing from 'expo-sharing';
import { useEffect, useRef, useState, type ComponentRef, type ReactNode } from 'react';
import { Animated, Easing, Modal, Pressable, Share, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import { captureRef } from 'react-native-view-shot';

import { logError } from '../errorLog';
import { inr } from '../lib/analysis';
import type { YearReview } from '../lib/review';
import { C, F, catMeta } from '../theme';
import { AnimatedNumber, FadeIn, PressScale, Pulse } from './anim';
import Icon from './Icon';
import { Button, Row, T } from './ui';

const SLIDE_MS = 6500;
const GRADS = [
  ['#0F9F74', '#0E7490', '#312E81'],
  ['#7C2D12', '#9D174D', '#4C1D95'],
  ['#1E3A8A', '#0E7490', '#065F46'],
  ['#9A3412', '#B45309', '#065F46'],
  ['#065F46', '#0F766E', '#1E3A8A'],
  ['#4C1D95', '#831843', '#7C2D12'],
];
const fmtMonth = (t: number) => new Date(t).toLocaleDateString('en-IN', { month: 'short', year: 'numeric' });
const short = (n: number) => (Math.abs(n) >= 1e5 ? `₹${(n / 1e5).toFixed(1)}L` : inr(n));

function Bg({ colors, id }: { colors: readonly string[]; id: string }) {
  return (
    <Svg style={StyleSheet.absoluteFill} width="100%" height="100%" preserveAspectRatio="none">
      <Defs>
        <LinearGradient id={id} x1="0" y1="0" x2="1" y2="1">
          {colors.map((c, i) => (
            <Stop key={c + i} offset={String(i / (colors.length - 1))} stopColor={c} />
          ))}
        </LinearGradient>
      </Defs>
      <Rect width="100%" height="100%" fill={`url(#${id})`} />
    </Svg>
  );
}

const Big = ({ children }: { children: ReactNode }) => (
  <T size={40} weight="black" color="#fff" style={{ lineHeight: 48, letterSpacing: -1 }}>
    {children}
  </T>
);
const Kicker = ({ children }: { children: ReactNode }) => (
  <T size={14} weight="bold" color="rgba(255,255,255,0.75)" style={{ textTransform: 'uppercase', letterSpacing: 1.5, marginBottom: 10 }}>
    {children}
  </T>
);
const Line = ({ children }: { children: ReactNode }) => (
  <T size={17} color="rgba(255,255,255,0.9)" style={{ marginTop: 10, lineHeight: 25 }}>
    {children}
  </T>
);

function Bar({ label, value, max, index, color }: { label: string; value: number; max: number; index: number; color: string }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(v, { toValue: 1, duration: 900, delay: 250 + index * 160, easing: Easing.out(Easing.cubic), useNativeDriver: false }).start();
  }, [v, index]);
  return (
    <View style={{ marginBottom: 14 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 6 }}>
        <Row>
          <Icon name={catMeta(label).icon} size={16} color="#fff" />
          <T size={15} weight="semibold" color="#fff" style={{ marginLeft: 8 }}>
            {label}
          </T>
        </Row>
        <T size={15} weight="bold" color="#fff">
          {short(value)}
        </T>
      </Row>
      <View style={{ height: 10, borderRadius: 5, backgroundColor: 'rgba(255,255,255,0.15)' }}>
        <Animated.View style={{ height: 10, borderRadius: 5, backgroundColor: color, width: v.interpolate({ inputRange: [0, 1], outputRange: ['0%', `${(value / max) * 100}%`] }) }} />
      </View>
    </View>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ backgroundColor: 'rgba(255,255,255,0.12)', borderRadius: 18, padding: 16, marginBottom: 10 }}>
      <T size={13} color="rgba(255,255,255,0.75)">
        {label}
      </T>
      <T size={24} weight="black" color="#fff">
        {value}
      </T>
    </View>
  );
}

function slides(r: YearReview): ReactNode[] {
  const maxCat = r.topCategories[0]?.amount ?? 1;
  return [
    <FadeIn key="0">
      <Kicker>
        Your year with money · {fmtMonth(r.from)} – {fmtMonth(r.to)}
      </Kicker>
      <Big>You spent</Big>
      <AnimatedNumber value={r.spent} format={inr} duration={1600} style={{ fontFamily: F.black, fontSize: 52, color: '#fff', letterSpacing: -1.5 }} />
      <Line>across {r.payments.toLocaleString('en-IN')} payments, all tracked without typing a thing.</Line>
    </FadeIn>,
    <FadeIn key="1">
      <Kicker>Where it went</Kicker>
      <Big>Your top {Math.min(5, r.topCategories.length)}</Big>
      <View style={{ marginTop: 24 }}>
        {r.topCategories.map((c, i) => (
          <Bar key={c.category} label={c.category} value={c.amount} max={maxCat} index={i} color={catMeta(c.category).color} />
        ))}
      </View>
    </FadeIn>,
    <FadeIn key="2">
      <Kicker>Your favourites</Kicker>
      {r.mostVisited ? (
        <>
          <Big>{r.mostVisited.merchant}</Big>
          <Line>You paid them {r.mostVisited.count} times. Loyal!</Line>
        </>
      ) : null}
      <View style={{ marginTop: 24 }}>
        {r.topMerchants.slice(0, 4).map((m, i) => (
          <Row key={m.merchant} style={{ paddingVertical: 8 }}>
            <T size={22} weight="black" color="rgba(255,255,255,0.5)" style={{ width: 34 }}>
              {i + 1}
            </T>
            <T size={16} weight="semibold" color="#fff" style={{ flex: 1 }} lines={1}>
              {m.merchant}
            </T>
            <T size={16} weight="bold" color="#fff">
              {short(m.amount)}
            </T>
          </Row>
        ))}
      </View>
      {r.biggest ? <Line>Biggest single payment: {inr(r.biggest.amount)} to {r.biggest.merchant || r.biggest.category}.</Line> : null}
    </FadeIn>,
    <FadeIn key="3">
      <Kicker>Fun facts</Kicker>
      <Stat label="Food orders" value={`${r.foodOrders} · ${short(r.foodSpent)} on eating`} />
      <Stat label="Cab & auto rides" value={String(r.rides)} />
      <Stat label="Subscriptions (per year)" value={inr(r.subscriptionsYearly)} />
      <Stat label="Fees & penalties paid" value={r.feesPaid ? inr(r.feesPaid) : '₹0 🎉'} />
    </FadeIn>,
    <FadeIn key="4">
      <Kicker>What you kept</Kicker>
      <Big>{r.savingsRate != null ? `${Math.round(r.savingsRate * 100)}% saved` : 'Your savings'}</Big>
      <View style={{ marginTop: 18 }}>
        {r.income > 0 ? <Stat label="Earned" value={inr(r.income)} /> : null}
        <Stat label="Invested" value={inr(r.invested)} />
        {r.netWorthChange != null ? <Stat label="Net worth change" value={`${r.netWorthChange >= 0 ? '+' : ''}${short(r.netWorthChange)}`} /> : null}
        {r.bestMonth ? <Stat label="Thriftiest month" value={`${r.bestMonth.label} · ${short(r.bestMonth.spent)}`} /> : null}
      </View>
    </FadeIn>,
    <FadeIn key="5" style={{ alignItems: 'center' }}>
      <Kicker>Your money personality</Kicker>
      <Pulse>
        <T size={96} style={{ lineHeight: 116 }}>
          {r.personality.emoji}
        </T>
      </Pulse>
      <Big>{r.personality.name}</Big>
      <T size={17} color="rgba(255,255,255,0.9)" style={{ marginTop: 10, textAlign: 'center', lineHeight: 25 }}>
        {r.personality.line}
      </T>
    </FadeIn>,
  ];
}

/** The card that gets saved as an image when you share. */
function ShareCard({ r }: { r: YearReview }) {
  return (
    <View style={{ width: 360, padding: 28, borderRadius: 28, overflow: 'hidden' }}>
      <Bg colors={GRADS[5]} id="share" />
      <T size={13} weight="bold" color="rgba(255,255,255,0.75)" style={{ letterSpacing: 1.5 }}>
        MY YEAR WITH MONEY
      </T>
      <T size={64} style={{ marginTop: 10, lineHeight: 76 }}>
        {r.personality.emoji}
      </T>
      <T size={30} weight="black" color="#fff">
        {r.personality.name}
      </T>
      <T size={14} color="rgba(255,255,255,0.9)" style={{ marginTop: 6 }}>
        {r.personality.line}
      </T>
      <View style={{ marginTop: 18 }}>
        {r.savingsRate != null ? (
          <T size={15} weight="semibold" color="#fff">
            💰 Saved {Math.round(r.savingsRate * 100)}% of income
          </T>
        ) : null}
        {r.topCategories[0] ? (
          <T size={15} weight="semibold" color="#fff">
            🏆 Top category: {r.topCategories[0].category}
          </T>
        ) : null}
        <T size={15} weight="semibold" color="#fff">
          🍜 {r.foodOrders} food orders · 🚕 {r.rides} rides
        </T>
      </View>
      <T size={11} color="rgba(255,255,255,0.6)" style={{ marginTop: 18 }}>
        Paisa Watch · no amounts shared
      </T>
    </View>
  );
}

export function YearReviewStory({ r, visible, onClose }: { r: YearReview; visible: boolean; onClose: () => void }) {
  const insets = useSafeAreaInsets();
  const all = slides(r);
  const [i, setI] = useState(0);
  const [paused, setPaused] = useState(false);
  const progress = useRef(new Animated.Value(0)).current;
  const shareRef = useRef<ComponentRef<typeof View>>(null);

  useEffect(() => {
    if (!visible) return;
    progress.setValue(0);
    if (paused) return;
    const a = Animated.timing(progress, { toValue: 1, duration: SLIDE_MS, easing: Easing.linear, useNativeDriver: false });
    a.start(({ finished }) => {
      if (finished && i < all.length - 1) setI(i + 1);
    });
    return () => a.stop();
  }, [i, visible, paused, progress, all.length]);

  useEffect(() => {
    if (visible) setI(0);
  }, [visible]);

  const share = async () => {
    setPaused(true);
    try {
      const uri = await captureRef(shareRef, { format: 'png', quality: 1, result: 'tmpfile' });
      await Sharing.shareAsync(uri, { mimeType: 'image/png', dialogTitle: 'Share your year' });
    } catch (e) {
      logError('review-share', e);
      await Share.share({ message: `My year with money: I'm "${r.personality.name}" ${r.personality.emoji}. ${r.personality.line} (Paisa Watch)` }).catch(() => {});
    } finally {
      setPaused(false);
    }
  };

  return (
    <Modal visible={visible} animationType="fade" onRequestClose={onClose} statusBarTranslucent>
      <View style={{ flex: 1, backgroundColor: '#000' }}>
        <Bg colors={GRADS[i]} id={`s${i}`} />
        {/* off-screen card used for the shared image */}
        <View style={{ position: 'absolute', left: -1000, top: 0 }} pointerEvents="none">
          <View ref={shareRef} collapsable={false}>
            <ShareCard r={r} />
          </View>
        </View>
        <View style={{ paddingTop: insets.top + 10, paddingHorizontal: 14 }}>
          <Row style={{ gap: 5 }}>
            {all.map((_, k) => (
              <View key={k} style={{ flex: 1, height: 3.5, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.3)', overflow: 'hidden' }}>
                <Animated.View
                  style={{
                    height: '100%',
                    backgroundColor: '#fff',
                    width: k < i ? '100%' : k > i ? '0%' : progress.interpolate({ inputRange: [0, 1], outputRange: ['0%', '100%'] }),
                  }}
                />
              </View>
            ))}
          </Row>
          <Row style={{ justifyContent: 'space-between', marginTop: 12 }}>
            <T size={13} weight="bold" color="rgba(255,255,255,0.85)">
              Paisa Watch · Year in Review
            </T>
            <PressScale onPress={onClose} style={{ padding: 6 }}>
              <Icon name="x" size={22} color="#fff" />
            </PressScale>
          </Row>
        </View>
        <View style={{ flex: 1, justifyContent: 'center', paddingHorizontal: 28 }}>{all[i]}</View>
        {/* tap left / right to go back / forward; hold to pause */}
        <View style={{ position: 'absolute', left: 0, right: 0, top: insets.top + 70, bottom: 140, flexDirection: 'row' }}>
          <Pressable style={{ flex: 1 }} onPress={() => setI(Math.max(0, i - 1))} onLongPress={() => setPaused(true)} onPressOut={() => setPaused(false)} />
          <Pressable style={{ flex: 2 }} onPress={() => (i < all.length - 1 ? setI(i + 1) : onClose())} onLongPress={() => setPaused(true)} onPressOut={() => setPaused(false)} />
        </View>
        <View style={{ paddingHorizontal: 24, paddingBottom: insets.bottom + 24 }}>
          {i === all.length - 1 ? (
            <Button label="Share my year" icon="share" onPress={share} style={{ backgroundColor: '#fff' }} />
          ) : (
            <T size={12} color="rgba(255,255,255,0.6)" style={{ textAlign: 'center' }}>
              Tap to continue · hold to pause
            </T>
          )}
        </View>
      </View>
    </Modal>
  );
}

/** Entry point on Home. */
export function YearReviewCard({ r, index }: { r: YearReview; index: number }) {
  const [open, setOpen] = useState(false);
  if (r.payments < 20) return null;
  return (
    <FadeIn index={index}>
      <PressScale onPress={() => setOpen(true)}>
        <View style={{ borderRadius: 24, overflow: 'hidden', marginBottom: 12, marginTop: 6 }}>
          <Bg colors={GRADS[5]} id="entry" />
          <Row style={{ padding: 18 }}>
            <T size={40} style={{ lineHeight: 50 }}>
              {r.personality.emoji}
            </T>
            <View style={{ flex: 1, marginLeft: 14 }}>
              <T size={12} weight="bold" color="rgba(255,255,255,0.75)" style={{ letterSpacing: 1.2 }}>
                YEAR IN REVIEW
              </T>
              <T size={18} weight="black" color="#fff">
                You're {r.personality.name}
              </T>
              <T size={12.5} color="rgba(255,255,255,0.85)">
                Your last 12 months in 6 slides
              </T>
            </View>
            <Icon name="chevronRight" size={22} color="#fff" />
          </Row>
        </View>
      </PressScale>
      <YearReviewStory r={r} visible={open} onClose={() => setOpen(false)} />
    </FadeIn>
  );
}


