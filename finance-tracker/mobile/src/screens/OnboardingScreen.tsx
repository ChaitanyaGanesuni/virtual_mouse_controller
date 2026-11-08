import { useRef, useState } from 'react';
import { Animated, Linking, useWindowDimensions, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { FadeIn, PressScale } from '../components/anim';
import { GrowthArt, LeakArt, SmsArt } from '../components/Illustrations';
import { Button, Row, T } from '../components/ui';
import Icon from '../components/Icon';
import { useData } from '../store';
import { C } from '../theme';

const SLIDES = [
  {
    art: SmsArt,
    title: 'Zero typing.\nEvery rupee tracked.',
    text: 'Paisa Watch reads the alerts your bank, cards, UPI and mutual funds already send you, and builds your money picture automatically.',
  },
  {
    art: LeakArt,
    title: 'Find where your\nmoney leaks',
    text: 'Hidden fees, forgotten subscriptions, delivery habits and impulse buys, each with what you could save every month.',
  },
  {
    art: GrowthArt,
    title: 'Grow what\nyou keep',
    text: 'Live mutual-fund values, real returns (XIRR) and simple steps to invest better, plus alerts before card bills are due.',
  },
];

export default function OnboardingScreen() {
  const d = useData();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const x = useRef(new Animated.Value(0)).current;
  const scroller = useRef<{ scrollTo: (o: { x: number; animated: boolean }) => void } | null>(null);
  const [page, setPage] = useState(0);
  const last = page === SLIDES.length - 1;
  const go = (p: number) => {
    scroller.current?.scrollTo({ x: p * width, animated: true });
    setPage(p);
  };

  return (
    <View style={{ flex: 1, backgroundColor: C.bg, paddingTop: insets.top, paddingBottom: insets.bottom + 12 }}>
      <Row style={{ justifyContent: 'space-between', paddingHorizontal: 20, paddingTop: 10 }}>
        <Row>
          <Icon name="shieldCheck" size={18} color={C.green} />
          <T size={13} weight="semibold" color={C.sub} style={{ marginLeft: 6 }}>
            Private · stays on your phone
          </T>
        </Row>
        {!last ? (
          <PressScale onPress={() => go(SLIDES.length - 1)} style={{ padding: 6 }}>
            <T size={14} weight="semibold" color={C.sub}>
              Skip
            </T>
          </PressScale>
        ) : null}
      </Row>

      <Animated.ScrollView
        ref={scroller as never}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { x } } }], { useNativeDriver: true })}
        scrollEventThrottle={16}
        onMomentumScrollEnd={(e) => setPage(Math.round(e.nativeEvent.contentOffset.x / width))}
      >
        {SLIDES.map((sl, i) => {
          const range = [(i - 1) * width, i * width, (i + 1) * width];
          const Art = sl.art;
          return (
            <View key={i} style={{ width, paddingHorizontal: 28, justifyContent: 'center' }}>
              <Animated.View
                style={{
                  alignItems: 'center',
                  marginBottom: 28,
                  transform: [
                    { translateX: x.interpolate({ inputRange: range, outputRange: [width * 0.35, 0, -width * 0.35] }) },
                    { scale: x.interpolate({ inputRange: range, outputRange: [0.7, 1, 0.7], extrapolate: 'clamp' }) },
                  ],
                  opacity: x.interpolate({ inputRange: range, outputRange: [0, 1, 0], extrapolate: 'clamp' }),
                }}
              >
                <Art size={Math.min(280, width * 0.72)} />
              </Animated.View>
              <T size={30} weight="black" style={{ lineHeight: 38 }}>
                {sl.title}
              </T>
              <T size={15} color={C.sub} style={{ marginTop: 14, lineHeight: 23 }}>
                {sl.text}
              </T>
            </View>
          );
        })}
      </Animated.ScrollView>

      <View style={{ paddingHorizontal: 24 }}>
        <Row style={{ justifyContent: 'center', marginBottom: 18 }}>
          {SLIDES.map((_, i) => {
            const range = [(i - 1) * width, i * width, (i + 1) * width];
            return (
              <Animated.View
                key={i}
                style={{
                  height: 8,
                  width: 26,
                  marginHorizontal: 4,
                  borderRadius: 4,
                  backgroundColor: C.green,
                  opacity: x.interpolate({ inputRange: range, outputRange: [0.25, 1, 0.25], extrapolate: 'clamp' }),
                  transform: [{ scaleX: x.interpolate({ inputRange: range, outputRange: [0.35, 1, 0.35], extrapolate: 'clamp' }) }],
                }}
              />
            );
          })}
        </Row>
        {last ? (
          <FadeIn>
            <Button label="Allow SMS & notifications" icon="message" onPress={() => d.refresh(true)} />
            {d.permission === 'denied' ? (
              <Button label="Open app settings" kind="ghost" icon="sliders" onPress={() => Linking.openSettings()} />
            ) : null}
            <Button label="Try it with sample data" kind="ghost" icon="sparkle" onPress={() => d.setDemoMode(true)} />
            <T size={11.5} color={C.faint} style={{ textAlign: 'center', marginTop: 12 }}>
              Only messages from banks and fund houses are read. Personal chats are never touched.
            </T>
          </FadeIn>
        ) : (
          <Button
            label="Next"
            iconRight="chevronRight"
            onPress={() => go(page + 1)}
          />
        )}
      </View>
    </View>
  );
}
