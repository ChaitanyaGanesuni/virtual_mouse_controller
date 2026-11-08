import * as Haptics from 'expo-haptics';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Animated, Easing, Pressable, StyleSheet, Text, View, type StyleProp, type TextStyle, type ViewStyle } from 'react-native';

export const tap = () => Haptics.selectionAsync().catch(() => {});
export const thump = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});

/** Fades and slides children up when they mount. Use `delay` (or `index`) to stagger lists. */
export function FadeIn({
  children,
  delay,
  index = 0,
  from = 18,
  style,
}: {
  children: ReactNode;
  delay?: number;
  index?: number;
  from?: number;
  style?: StyleProp<ViewStyle>;
}) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(v, {
      toValue: 1,
      duration: 480,
      delay: delay ?? Math.min(index, 10) * 70,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    }).start();
  }, [v, delay, index]);
  return (
    <Animated.View
      style={[
        style,
        { opacity: v, transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [from, 0] }) }] },
      ]}
    >
      {children}
    </Animated.View>
  );
}

/** Pressable that springs down slightly and gives a light haptic tick. */
export function PressScale({
  children,
  onPress,
  onLongPress,
  style,
  scaleTo = 0.97,
  haptic = true,
  disabled,
}: {
  children: ReactNode;
  onPress?: () => void;
  onLongPress?: () => void;
  style?: StyleProp<ViewStyle>;
  scaleTo?: number;
  haptic?: boolean;
  disabled?: boolean;
}) {
  const s = useRef(new Animated.Value(1)).current;
  const to = (v: number) => Animated.spring(s, { toValue: v, useNativeDriver: true, speed: 40, bounciness: 6 }).start();
  // Layout props that decide how much room the control gets must sit on the outer Pressable.
  const flat = StyleSheet.flatten(style) ?? {};
  const outer: ViewStyle = { flex: flat.flex, alignSelf: flat.alignSelf, flexGrow: flat.flexGrow, flexBasis: flat.flexBasis };
  return (
    <Pressable
      style={outer}
      disabled={disabled}
      onPressIn={() => to(scaleTo)}
      onPressOut={() => to(1)}
      onLongPress={onLongPress}
      onPress={() => {
        if (haptic) tap();
        onPress?.();
      }}
    >
      <Animated.View style={[style, { transform: [{ scale: s }] }]}>{children}</Animated.View>
    </Pressable>
  );
}

/** Counts up (or down) to `value` whenever it changes. */
export function AnimatedNumber({
  value,
  format,
  style,
  duration = 900,
}: {
  value: number;
  format: (n: number) => string;
  style?: StyleProp<TextStyle>;
  duration?: number;
}) {
  const anim = useRef(new Animated.Value(0)).current;
  const [shown, setShown] = useState(0);
  useEffect(() => {
    const id = anim.addListener(({ value: v }) => setShown(v));
    Animated.timing(anim, { toValue: value, duration, easing: Easing.out(Easing.exp), useNativeDriver: false }).start();
    return () => anim.removeListener(id);
  }, [anim, value, duration]);
  return <Text style={style}>{format(shown)}</Text>;
}

/** Grey placeholder block with a moving sheen, shown while the first scan runs. */
export function Skeleton({ height, width = '100%', radius = 14, style }: {
  height: number;
  width?: number | `${number}%`;
  radius?: number;
  style?: StyleProp<ViewStyle>;
}) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(v, { toValue: 1, duration: 1200, easing: Easing.inOut(Easing.ease), useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [v]);
  return (
    <View style={[{ height, width, borderRadius: radius, backgroundColor: '#151F2D', overflow: 'hidden' }, style]}>
      <Animated.View
        style={{
          position: 'absolute',
          top: 0,
          bottom: 0,
          width: 120,
          backgroundColor: 'rgba(255,255,255,0.05)',
          transform: [{ translateX: v.interpolate({ inputRange: [0, 1], outputRange: [-140, 420] }) }, { skewX: '-20deg' }],
        }}
      />
    </View>
  );
}

/** Gentle infinite pulse, for "live" dots and attention badges. */
export function Pulse({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(v, { toValue: 1, duration: 900, useNativeDriver: true }),
        Animated.timing(v, { toValue: 0, duration: 900, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [v]);
  return (
    <Animated.View style={[style, { opacity: v.interpolate({ inputRange: [0, 1], outputRange: [0.55, 1] }) }]}>{children}</Animated.View>
  );
}
