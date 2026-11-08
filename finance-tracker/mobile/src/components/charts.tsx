import { useEffect, useRef, type ReactNode } from 'react';
import { Animated, Easing, Text, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Stop } from 'react-native-svg';

import { C, F } from '../theme';

const AnimatedCircle = Animated.createAnimatedComponent(Circle);
const AnimatedPath = Animated.createAnimatedComponent(Path);

function useProgress(deps: unknown[], duration = 1100, delay = 150) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    v.setValue(0);
    Animated.timing(v, { toValue: 1, duration, delay, easing: Easing.out(Easing.cubic), useNativeDriver: false }).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return v;
}

/** Donut whose segments sweep in one after another. */
export function Donut({
  data,
  size = 180,
  thickness = 18,
  center,
}: {
  data: { value: number; color: string }[];
  size?: number;
  thickness?: number;
  center?: ReactNode;
}) {
  const total = data.reduce((s, d) => s + d.value, 0) || 1;
  const r = (size - thickness) / 2;
  const circ = 2 * Math.PI * r;
  const gap = data.length > 1 ? 3 : 0;
  const p = useProgress([total, data.length]);
  let acc = 0;
  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      <Svg width={size} height={size} style={{ position: 'absolute', transform: [{ rotate: '-90deg' }] }}>
        <Circle cx={size / 2} cy={size / 2} r={r} stroke={C.cardHi} strokeWidth={thickness} fill="none" />
        {data.map((d, i) => {
          const start = acc / total;
          acc += d.value;
          const end = acc / total;
          const len = Math.max(0, (end - start) * circ - gap);
          const offset = p.interpolate({
            inputRange: [0, Math.max(start, 0.0001), Math.max(end, 0.0002), 1],
            outputRange: [len, len, 0, 0],
            extrapolate: 'clamp',
          });
          return (
            <AnimatedCircle
              key={i}
              cx={size / 2}
              cy={size / 2}
              r={r}
              stroke={d.color}
              strokeWidth={thickness}
              strokeLinecap="butt"
              fill="none"
              strokeDasharray={`${len} ${circ}`}
              strokeDashoffset={offset}
              rotation={start * 360}
              origin={`${size / 2}, ${size / 2}`}
            />
          );
        })}
      </Svg>
      {center}
    </View>
  );
}

/** Half-circle gauge for the 0–100 health score. */
export function Gauge({ value, size = 220, color }: { value: number; size?: number; color: string }) {
  const stroke = 16;
  const r = (size - stroke) / 2;
  const cx = size / 2;
  const cy = size / 2;
  const arc = `M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}`;
  const len = Math.PI * r;
  const p = useProgress([value], 1400, 250);
  const offset = p.interpolate({ inputRange: [0, 1], outputRange: [len, len * (1 - Math.max(0, Math.min(100, value)) / 100)] });
  return (
    <Svg width={size} height={size / 2 + stroke / 2}>
      <Defs>
        <LinearGradient id="g" x1="0" y1="0" x2="1" y2="0">
          <Stop offset="0" stopColor={C.red} />
          <Stop offset="0.5" stopColor={C.amber} />
          <Stop offset="1" stopColor={C.green} />
        </LinearGradient>
      </Defs>
      <Path d={arc} stroke={C.cardHi} strokeWidth={stroke} fill="none" strokeLinecap="round" />
      <AnimatedPath
        d={arc}
        stroke={color === 'gradient' ? 'url(#g)' : color}
        strokeWidth={stroke}
        fill="none"
        strokeLinecap="round"
        strokeDasharray={`${len} ${len}`}
        strokeDashoffset={offset}
      />
    </Svg>
  );
}

/** Vertical bars that grow from the bottom, staggered. */
export function Bars({
  data,
  height = 140,
}: {
  data: { label: string; value: number; color: string; highlight?: boolean; note?: string }[];
  height?: number;
}) {
  const max = Math.max(...data.map((d) => d.value), 1);
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-end', height: height + 40, gap: 10 }}>
      {data.map((d, i) => (
        <Bar key={d.label} d={d} h={(d.value / max) * height} index={i} />
      ))}
    </View>
  );
}

function Bar({ d, h, index }: { d: { label: string; value: number; color: string; highlight?: boolean; note?: string }; h: number; index: number }) {
  const v = useProgress([h], 800, 120 + index * 80);
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'flex-end' }}>
      {d.note ? (
        <Text style={{ color: d.highlight ? C.text : C.faint, fontFamily: F.semibold, fontSize: 10, marginBottom: 4 }}>{d.note}</Text>
      ) : null}
      <Animated.View
        style={{
          width: '72%',
          height: v.interpolate({ inputRange: [0, 1], outputRange: [2, Math.max(4, h)] }),
          borderRadius: 8,
          backgroundColor: d.color,
          opacity: d.highlight ? 1 : 0.55,
        }}
      />
      <Text style={{ color: d.highlight ? C.text : C.sub, fontFamily: d.highlight ? F.bold : F.medium, fontSize: 11, marginTop: 6 }}>
        {d.label}
      </Text>
    </View>
  );
}

/** Horizontal progress bar that fills on mount. */
export function Progress({ value, color, height = 8, delay = 0 }: { value: number; color: string; height?: number; delay?: number }) {
  const pct = Math.max(0, Math.min(1, value));
  const v = useProgress([pct], 900, 150 + delay);
  return (
    <View style={{ height, backgroundColor: C.cardHi, borderRadius: height, overflow: 'hidden' }}>
      <Animated.View
        style={{
          height: '100%',
          borderRadius: height,
          backgroundColor: color,
          width: v.interpolate({ inputRange: [0, 1], outputRange: ['0%', `${Math.max(pct * 100, 1.5)}%`] }),
        }}
      />
    </View>
  );
}

/** Circular progress ring (budgets). Turns amber past 80% and red past 100%. */
export function Ring({ pct, size = 64, stroke = 7, children }: { pct: number; size?: number; stroke?: number; children?: ReactNode }) {
  const r = (size - stroke) / 2;
  const circ = 2 * Math.PI * r;
  const shown = Math.max(0, Math.min(1, pct));
  const color = pct >= 1 ? C.red : pct >= 0.8 ? C.amber : C.green;
  const p = useProgress([shown], 1000, 200);
  const offset = p.interpolate({ inputRange: [0, 1], outputRange: [circ, circ * (1 - shown)] });
  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      <Svg width={size} height={size} style={{ position: 'absolute', transform: [{ rotate: '-90deg' }] }}>
        <Circle cx={size / 2} cy={size / 2} r={r} stroke={C.cardHi} strokeWidth={stroke} fill="none" />
        <AnimatedCircle
          cx={size / 2}
          cy={size / 2}
          r={r}
          stroke={color}
          strokeWidth={stroke}
          strokeLinecap="round"
          fill="none"
          strokeDasharray={`${circ} ${circ}`}
          strokeDashoffset={offset}
        />
      </Svg>
      {children}
    </View>
  );
}

/** Smooth area chart whose line draws in from the left, with a dot on the latest value. */
export function LineChart({
  values,
  width,
  height = 120,
  color = C.green,
}: {
  values: number[];
  width: number;
  height?: number;
  color?: string;
}) {
  const p = useProgress([values.join(',')], 1300, 200);
  if (values.length < 2 || width <= 0) return <View style={{ height }} />;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || Math.abs(max) || 1;
  const pad = 8;
  const pts = values.map((v, i) => [
    pad + (i / (values.length - 1)) * (width - pad * 2),
    pad + (1 - (v - min) / span) * (height - pad * 2),
  ]);
  // Catmull-Rom → cubic Bézier for a smooth curve through every point.
  let d = `M ${pts[0][0]} ${pts[0][1]}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] ?? pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] ?? p2;
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    d += ` C ${c1[0]} ${c1[1]}, ${c2[0]} ${c2[1]}, ${p2[0]} ${p2[1]}`;
  }
  const area = `${d} L ${pts[pts.length - 1][0]} ${height} L ${pts[0][0]} ${height} Z`;
  const len = width * 2.5; // generous upper bound on the curve length
  const last = pts[pts.length - 1];
  return (
    <Svg width={width} height={height}>
      <Defs>
        <LinearGradient id="area" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor={color} stopOpacity="0.35" />
          <Stop offset="1" stopColor={color} stopOpacity="0" />
        </LinearGradient>
      </Defs>
      <AnimatedPath d={area} fill="url(#area)" opacity={p} />
      <AnimatedPath
        d={d}
        stroke={color}
        strokeWidth={3}
        fill="none"
        strokeLinecap="round"
        strokeDasharray={`${len} ${len}`}
        strokeDashoffset={p.interpolate({ inputRange: [0, 1], outputRange: [len, 0] })}
      />
      <AnimatedCircle cx={last[0]} cy={last[1]} r={5} fill={color} stroke={C.card} strokeWidth={2.5} opacity={p} />
    </Svg>
  );
}
