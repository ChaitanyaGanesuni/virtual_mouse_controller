import { useEffect, useRef, useState, type ReactNode } from 'react';
import {
  Animated,
  Easing,
  LayoutAnimation,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  View,
  type StyleProp,
  type TextStyle,
  type ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';

import { inr } from '../lib/analysis';
import type { Insight } from '../lib/types';
import { C, F, R, catMeta, severity, theme } from '../theme';
import { PressScale } from './anim';
import Icon, { type IconName } from './Icon';

export { C };

// ---------------------------------------------------------------- typography

export function T({
  children,
  size = 14,
  weight = 'regular',
  color = C.text,
  style,
  lines,
}: {
  children: ReactNode;
  size?: number;
  weight?: keyof typeof F;
  color?: string;
  style?: StyleProp<TextStyle>;
  lines?: number;
}) {
  return (
    <Text numberOfLines={lines} style={[{ fontFamily: F[weight], fontSize: size, color, lineHeight: Math.round(size * 1.4) }, style]}>
      {children}
    </Text>
  );
}

export const Label = ({ children, color = C.sub }: { children: ReactNode; color?: string }) => (
  <Text style={{ fontFamily: F.semibold, fontSize: 11, letterSpacing: 1.1, textTransform: 'uppercase', color }}>{children}</Text>
);

// ---------------------------------------------------------------- surfaces

export function Card({ children, style, pad = 18 }: { children: ReactNode; style?: StyleProp<ViewStyle>; pad?: number }) {
  return <View style={[s.card, { padding: pad }, style]}>{children}</View>;
}

/** Card with a diagonal gradient background and a soft glow orb. */
export function GradientCard({
  colors,
  children,
  style,
  shine,
}: {
  colors: readonly string[];
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
  /** A soft light sweep that crosses the card every few seconds. */
  shine?: boolean;
}) {
  const id = useRef(`g${Math.random().toString(36).slice(2, 8)}`).current;
  const sweep = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!shine) return;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.delay(1400),
        Animated.timing(sweep, { toValue: 1, duration: 1500, easing: Easing.inOut(Easing.cubic), useNativeDriver: true }),
        Animated.timing(sweep, { toValue: 0, duration: 0, useNativeDriver: true }),
        Animated.delay(4200),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [shine, sweep]);
  return (
    <View style={[{ borderRadius: R.xl, overflow: 'hidden', marginBottom: 14 }, style]}>
      <Svg style={StyleSheet.absoluteFill} width="100%" height="100%" preserveAspectRatio="none">
        <Defs>
          <LinearGradient id={id} x1="0" y1="0" x2="1" y2="1">
            {colors.map((c, i) => (
              <Stop key={c + i} offset={String(i / Math.max(1, colors.length - 1))} stopColor={c} />
            ))}
          </LinearGradient>
        </Defs>
        <Rect width="100%" height="100%" fill={`url(#${id})`} />
      </Svg>
      <View style={s.orb} />
      <View style={[s.orb, { right: undefined, left: -60, top: undefined, bottom: -90, opacity: 0.06 }]} />
      {shine ? (
        <Animated.View
          pointerEvents="none"
          style={{
            position: 'absolute',
            top: -40,
            bottom: -40,
            width: 90,
            backgroundColor: 'rgba(255,255,255,0.14)',
            transform: [{ translateX: sweep.interpolate({ inputRange: [0, 1], outputRange: [-160, 520] }) }, { rotate: '18deg' }],
          }}
        />
      ) : null}
      <View style={{ padding: 20 }}>{children}</View>
    </View>
  );
}

export function Section({ title, action, onAction }: { title: string; action?: string; onAction?: () => void }) {
  return (
    <View style={s.section}>
      <T size={17} weight="bold">
        {title}
      </T>
      {action ? (
        <PressScale onPress={onAction} style={{ flexDirection: 'row', alignItems: 'center' }}>
          <T size={13} weight="semibold" color={C.accent}>
            {action}
          </T>
          <Icon name="chevronRight" size={16} color={C.accent} />
        </PressScale>
      ) : null}
    </View>
  );
}

export const Row = ({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) => (
  <View style={[{ flexDirection: 'row', alignItems: 'center' }, style]}>{children}</View>
);

export const Divider = () => <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: C.border, marginVertical: 4 }} />;

// ---------------------------------------------------------------- small parts

export function IconBubble({ icon, color, size = 40 }: { icon: IconName; color: string; size?: number }) {
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2.6,
        backgroundColor: color + '22',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Icon name={icon} size={size * 0.5} color={color} />
    </View>
  );
}

export const CategoryBubble = ({ category, size = 40 }: { category: string; size?: number }) => {
  const m = catMeta(category);
  return <IconBubble icon={m.icon} color={m.color} size={size} />;
};

export function Pill({ text, color, icon }: { text: string; color: string; icon?: IconName }) {
  return (
    <View style={[s.pill, { backgroundColor: color + '1F' }]}>
      {icon ? <Icon name={icon} size={12} color={color} stroke={2.4} /> : null}
      <Text style={{ color, fontFamily: F.semibold, fontSize: 11, marginLeft: icon ? 4 : 0 }}>{text}</Text>
    </View>
  );
}

export function Chip({ label, active, onPress, icon }: { label: string; active?: boolean; onPress: () => void; icon?: IconName }) {
  return (
    <PressScale onPress={onPress} style={[s.chip, active ? s.chipOn : null]}>
      {icon ? <Icon name={icon} size={14} color={active ? C.onAccent : C.sub} /> : null}
      <Text style={{ color: active ? C.onAccent : C.text, fontFamily: F.semibold, fontSize: 13, marginLeft: icon ? 6 : 0 }}>{label}</Text>
    </PressScale>
  );
}

export function Button({
  label,
  onPress,
  kind = 'primary',
  icon,
  iconRight,
  style,
}: {
  label: string;
  onPress: () => void;
  kind?: 'primary' | 'ghost' | 'danger';
  icon?: IconName;
  iconRight?: IconName;
  style?: StyleProp<ViewStyle>;
}) {
  const primary = kind === 'primary';
  const fg = primary ? C.onAccent : kind === 'danger' ? C.red : C.text;
  return (
    <PressScale onPress={onPress} style={[s.btn, primary ? s.btnPrimary : s.btnGhost, style]}>
      {icon ? <Icon name={icon} size={18} color={fg} /> : null}
      <Text style={{ color: fg, fontFamily: F.bold, fontSize: 15, marginLeft: icon ? 8 : 0, marginRight: iconRight ? 6 : 0 }}>{label}</Text>
      {iconRight ? <Icon name={iconRight} size={18} color={fg} /> : null}
    </PressScale>
  );
}

export function Stat({ label, value, color, icon }: { label: string; value: ReactNode; color?: string; icon?: IconName }) {
  return (
    <View style={{ flex: 1 }}>
      <Row style={{ marginBottom: 4 }}>
        {icon ? <Icon name={icon} size={12} color={color ?? C.sub} stroke={2.4} /> : null}
        <Text style={{ fontFamily: F.medium, fontSize: 12, color: 'rgba(238,242,248,0.7)', marginLeft: icon ? 4 : 0 }}>{label}</Text>
      </Row>
      {typeof value === 'string' ? (
        <T size={16} weight="bold" color={color ?? C.text}>
          {value}
        </T>
      ) : (
        value
      )}
    </View>
  );
}

export function Empty({ title, text, art }: { title: string; text: string; art?: ReactNode }) {
  return (
    <View style={{ alignItems: 'center', paddingVertical: 26, paddingHorizontal: 12 }}>
      {art}
      <T size={16} weight="bold" style={{ marginTop: art ? 14 : 0, textAlign: 'center' }}>
        {title}
      </T>
      <T size={13} color={C.sub} style={{ textAlign: 'center', marginTop: 6 }}>
        {text}
      </T>
    </View>
  );
}

// ---------------------------------------------------------------- insight card

export function InsightCard({ i, startOpen = false }: { i: Insight; startOpen?: boolean }) {
  const [open, setOpen] = useState(startOpen);
  const sev = severity()[i.severity];
  const rot = useRef(new Animated.Value(startOpen ? 1 : 0)).current;
  const toggle = () => {
    LayoutAnimation.configureNext(LayoutAnimation.create(260, 'easeInEaseOut', 'opacity'));
    Animated.timing(rot, { toValue: open ? 0 : 1, duration: 220, useNativeDriver: true }).start();
    setOpen(!open);
  };
  return (
    <PressScale onPress={toggle} scaleTo={0.985} style={[s.card, { padding: 16 }]}>
      <Row style={{ alignItems: 'flex-start' }}>
        <IconBubble icon={sev.icon} color={sev.color} size={42} />
        <View style={{ flex: 1, marginLeft: 12 }}>
          <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
            <Pill text={sev.label} color={sev.color} />
            <Animated.View style={{ transform: [{ rotate: rot.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '180deg'] }) }] }}>
              <Icon name="chevronDown" size={18} color={C.sub} />
            </Animated.View>
          </Row>
          <T size={15} weight="bold">
            {i.title}
          </T>
          {i.monthlySaving ? (
            <Row style={{ marginTop: 8 }}>
              <Icon name="sparkle" size={14} color={C.green} fill={C.green} />
              <T size={13} weight="semibold" color={C.green} style={{ marginLeft: 6 }}>
                Save ≈ {inr(i.monthlySaving)}/month
              </T>
            </Row>
          ) : null}
          {open ? (
            <T size={13.5} color={C.sub} style={{ marginTop: 10, lineHeight: 21 }}>
              {i.detail}
            </T>
          ) : null}
        </View>
      </Row>
    </PressScale>
  );
}

// ---------------------------------------------------------------- bottom sheet

export function Sheet({ visible, onClose, children, title }: { visible: boolean; onClose: () => void; children: ReactNode; title?: string }) {
  const insets = useSafeAreaInsets();
  const v = useRef(new Animated.Value(0)).current;
  const [mounted, setMounted] = useState(visible);
  useEffect(() => {
    if (visible) {
      setMounted(true);
      Animated.spring(v, { toValue: 1, useNativeDriver: true, damping: 18, stiffness: 160, mass: 0.8 }).start();
    } else {
      Animated.timing(v, { toValue: 0, duration: 200, easing: Easing.in(Easing.cubic), useNativeDriver: true }).start(() => setMounted(false));
    }
  }, [visible, v]);
  if (!mounted) return null;
  return (
    <Modal transparent visible statusBarTranslucent onRequestClose={onClose} animationType="none">
      <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(0,0,0,0.6)', opacity: v }]}>
        <Pressable style={{ flex: 1 }} onPress={onClose} />
      </Animated.View>
      <Animated.View
        style={[
          s.sheet,
          { paddingBottom: insets.bottom + 16 },
          { transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [600, 0] }) }] },
        ]}
      >
        <View style={s.grabber} />
        {title ? (
          <T size={18} weight="bold" style={{ marginBottom: 12 }}>
            {title}
          </T>
        ) : null}
        {children}
      </Animated.View>
    </Modal>
  );
}

// ---------------------------------------------------------------- styles

const makeStyles = () => {
  const light = theme.mode === 'light';
  return StyleSheet.create({
  card: {
    backgroundColor: C.card,
    borderRadius: R.lg,
    marginBottom: 12,
    borderWidth: light ? 0 : StyleSheet.hairlineWidth,
    borderColor: C.border,
    shadowColor: C.shadow,
    shadowOpacity: light ? 0.07 : 0,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 4 },
    elevation: light ? 2 : 0,
  },
  orb: {
    position: 'absolute',
    right: -50,
    top: -70,
    width: 200,
    height: 200,
    borderRadius: 100,
    backgroundColor: '#FFFFFF',
    opacity: 0.08,
  },
  section: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 14, marginBottom: 10 },
  pill: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 3, borderRadius: R.pill, alignSelf: 'flex-start' },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: R.pill,
    backgroundColor: C.card,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: C.borderHi,
    marginRight: 8,
    marginBottom: 8,
  },
  chipOn: { backgroundColor: C.accent, borderColor: C.accent },
  btn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', borderRadius: R.md, paddingVertical: 15, marginTop: 10 },
  btnPrimary: {
    backgroundColor: C.accent,
    shadowColor: C.accent,
    shadowOpacity: light ? 0.35 : 0.3,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 4,
  },
  btnGhost: { backgroundColor: C.cardHi, borderWidth: light ? 0 : StyleSheet.hairlineWidth, borderColor: C.borderHi },
  sheet: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    maxHeight: '85%',
    backgroundColor: C.bg2,
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    paddingHorizontal: 20,
    paddingTop: 10,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: C.borderHi,
  },
  grabber: { alignSelf: 'center', width: 40, height: 5, borderRadius: 3, backgroundColor: C.borderHi, marginBottom: 14 },
});
};

/** Shared styles; rebuilt by `rebuildStyles()` when the theme changes. */
export let s = makeStyles();
export function rebuildStyles(): void {
  s = makeStyles();
}

