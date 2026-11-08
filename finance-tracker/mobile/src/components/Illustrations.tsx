import Svg, { Circle, Defs, G, LinearGradient, Path, RadialGradient, Rect, Stop, Text as SvgText } from 'react-native-svg';

import { C } from '../theme';

function Glow({ id, color }: { id: string; color: string }) {
  return (
    <RadialGradient id={id} cx="50%" cy="50%" r="50%">
      <Stop offset="0" stopColor={color} stopOpacity="0.45" />
      <Stop offset="1" stopColor={color} stopOpacity="0" />
    </RadialGradient>
  );
}

/** Phone receiving bank SMS that turn into tracked transactions. */
export function SmsArt({ size = 240 }: { size?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 240 240">
      <Defs>
        <Glow id="glow1" color={C.green} />
        <LinearGradient id="phone" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#1C2A3F" />
          <Stop offset="1" stopColor="#111A27" />
        </LinearGradient>
        <LinearGradient id="bub" x1="0" y1="0" x2="1" y2="0">
          <Stop offset="0" stopColor={C.green} />
          <Stop offset="1" stopColor={C.teal} />
        </LinearGradient>
      </Defs>
      <Circle cx="120" cy="120" r="115" fill="url(#glow1)" />
      <Rect x="70" y="28" width="100" height="184" rx="18" fill="url(#phone)" stroke="#2C3D57" strokeWidth="2" />
      <Rect x="104" y="36" width="32" height="6" rx="3" fill="#2C3D57" />
      {/* incoming SMS bubbles */}
      <Rect x="80" y="56" width="70" height="26" rx="10" fill="#22324A" />
      <Rect x="88" y="64" width="40" height="4" rx="2" fill="#5A6B85" />
      <Rect x="88" y="72" width="26" height="4" rx="2" fill="#5A6B85" />
      <Rect x="80" y="90" width="62" height="26" rx="10" fill="#22324A" />
      <Rect x="88" y="98" width="34" height="4" rx="2" fill="#5A6B85" />
      <Rect x="88" y="106" width="44" height="4" rx="2" fill="#5A6B85" />
      {/* parsed result card */}
      <G>
        <Rect x="80" y="128" width="80" height="62" rx="12" fill="#0E1622" stroke={C.green} strokeWidth="1.5" />
        <Circle cx="96" cy="146" r="9" fill={C.orange} opacity="0.25" />
        <Path d="M92 146h8M96 142v8" stroke={C.orange} strokeWidth="2" strokeLinecap="round" />
        <Rect x="110" y="141" width="38" height="4" rx="2" fill="#8A97AB" />
        <Rect x="110" y="149" width="24" height="4" rx="2" fill="#5A6B85" />
        <Rect x="88" y="166" width="64" height="7" rx="3.5" fill="#1E2A3C" />
        <Rect x="88" y="166" width="42" height="7" rx="3.5" fill="url(#bub)" />
        <Rect x="88" y="178" width="30" height="4" rx="2" fill="#5A6B85" />
      </G>
      {/* floating rupee coins */}
      <G>
        <Circle cx="190" cy="70" r="20" fill={C.amber} />
        <Circle cx="190" cy="70" r="15" fill="none" stroke="#B45309" strokeWidth="1.5" opacity="0.5" />
        <SvgText x="190" y="77" fontSize="20" fontWeight="bold" fill="#78350F" textAnchor="middle">
          ₹
        </SvgText>
      </G>
      <G>
        <Circle cx="48" cy="160" r="15" fill={C.green} />
        <Path d="M41 160l5 5 9-10" stroke="#064E3B" strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      </G>
      <Circle cx="200" cy="170" r="5" fill={C.violet} />
      <Circle cx="40" cy="80" r="4" fill={C.blue} />
    </Svg>
  );
}

/** Wallet with coins leaking out: "find where money leaks". */
export function LeakArt({ size = 240 }: { size?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 240 240">
      <Defs>
        <Glow id="glow2" color={C.orange} />
        <LinearGradient id="wallet" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#7C3AED" />
          <Stop offset="1" stopColor="#4338CA" />
        </LinearGradient>
      </Defs>
      <Circle cx="120" cy="120" r="115" fill="url(#glow2)" />
      <Rect x="44" y="70" width="140" height="96" rx="18" fill="url(#wallet)" />
      <Rect x="44" y="70" width="140" height="22" rx="11" fill="#A78BFA" opacity="0.35" />
      <Rect x="140" y="104" width="56" height="34" rx="12" fill="#312E81" />
      <Circle cx="158" cy="121" r="6" fill={C.amber} />
      {/* leak */}
      <Path d="M86 166c0 10-8 14-8 22a8 8 0 0 0 16 0c0-8-8-12-8-22z" fill={C.blue} opacity="0.9" />
      <G>
        <Circle cx="118" cy="196" r="12" fill={C.amber} />
        <SvgText x="118" y="201" fontSize="13" fontWeight="bold" fill="#78350F" textAnchor="middle">
          ₹
        </SvgText>
      </G>
      <G>
        <Circle cx="146" cy="214" r="9" fill={C.amber} opacity="0.8" />
        <SvgText x="146" y="218" fontSize="10" fontWeight="bold" fill="#78350F" textAnchor="middle">
          ₹
        </SvgText>
      </G>
      {/* magnifier */}
      <Circle cx="178" cy="62" r="24" fill="none" stroke={C.text} strokeWidth="6" />
      <Circle cx="178" cy="62" r="20" fill={C.green} opacity="0.15" />
      <Path d="M195 79l18 18" stroke={C.text} strokeWidth="8" strokeLinecap="round" />
      <Path d="M168 62l7 7 12-13" stroke={C.green} strokeWidth="4" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  );
}

/** Rising bars and an arrow: "grow your investments". */
export function GrowthArt({ size = 240 }: { size?: number }) {
  const bars = [46, 70, 62, 98, 128];
  return (
    <Svg width={size} height={size} viewBox="0 0 240 240">
      <Defs>
        <Glow id="glow3" color={C.indigo} />
        <LinearGradient id="bar" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor={C.green} />
          <Stop offset="1" stopColor={C.teal} stopOpacity="0.4" />
        </LinearGradient>
      </Defs>
      <Circle cx="120" cy="120" r="115" fill="url(#glow3)" />
      {bars.map((h, i) => (
        <Rect key={i} x={46 + i * 32} y={190 - h} width="22" height={h} rx="7" fill="url(#bar)" opacity={0.55 + i * 0.1} />
      ))}
      <Path d="M44 150 L92 118 L124 128 L190 62" stroke={C.amber} strokeWidth="5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <Path d="M170 60 L192 60 L192 82" stroke={C.amber} strokeWidth="5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <Rect x="36" y="194" width="170" height="3" rx="1.5" fill="#2C3D57" />
    </Svg>
  );
}

/** Shield with a lock: privacy. */
export function ShieldArt({ size = 120 }: { size?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 120 120">
      <Defs>
        <Glow id="glow4" color={C.teal} />
        <LinearGradient id="sh" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor={C.green} />
          <Stop offset="1" stopColor="#0E7490" />
        </LinearGradient>
      </Defs>
      <Circle cx="60" cy="60" r="58" fill="url(#glow4)" />
      <Path d="M60 16l34 12v26c0 24-16 40-34 48-18-8-34-24-34-48V28z" fill="url(#sh)" />
      <Rect x="46" y="56" width="28" height="22" rx="5" fill="#04261B" />
      <Path d="M51 56v-6a9 9 0 0 1 18 0v6" stroke="#04261B" strokeWidth="5" fill="none" />
      <Circle cx="60" cy="66" r="3" fill={C.green} />
    </Svg>
  );
}

/** Small "all clear" art for empty states. */
export function CheckArt({ size = 96 }: { size?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 96 96">
      <Defs>
        <Glow id="glow5" color={C.green} />
      </Defs>
      <Circle cx="48" cy="48" r="46" fill="url(#glow5)" />
      <Circle cx="48" cy="48" r="26" fill={C.green} />
      <Path d="M36 48l8 8 16-17" stroke="#04261B" strokeWidth="5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  );
}
