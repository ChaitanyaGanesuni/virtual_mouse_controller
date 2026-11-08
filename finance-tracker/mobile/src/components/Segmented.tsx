import { useEffect, useRef, useState } from 'react';
import { Animated, View, type LayoutChangeEvent } from 'react-native';

import { C } from '../theme';
import { PressScale } from './anim';
import { T } from './ui';

/** Three-way segmented control with a sliding thumb. */
export default function Segmented<V extends string>({ options, value, onChange }: { options: { value: V; label: string }[]; value: V; onChange: (v: V) => void }) {
  const [w, setW] = useState(0);
  const idx = Math.max(0, options.findIndex((o) => o.value === value));
  const x = useRef(new Animated.Value(idx)).current;
  useEffect(() => {
    Animated.spring(x, { toValue: idx, useNativeDriver: true, speed: 18, bounciness: 6 }).start();
  }, [idx, x]);
  const seg = w / options.length;
  return (
    <View
      onLayout={(e: LayoutChangeEvent) => setW(e.nativeEvent.layout.width)}
      style={{ flexDirection: 'row', backgroundColor: C.bg2, borderRadius: 14, padding: 4, marginTop: 10 }}
    >
      {w > 0 ? (
        <Animated.View
          style={{
            position: 'absolute',
            top: 4,
            bottom: 4,
            left: 4,
            width: seg - 8 / options.length,
            borderRadius: 11,
            backgroundColor: C.green,
            transform: [{ translateX: x.interpolate({ inputRange: [0, options.length - 1], outputRange: [0, seg * (options.length - 1) - 8 / options.length * (options.length - 1)] }) }],
          }}
        />
      ) : null}
      {options.map((o) => (
        <PressScale key={o.value} haptic onPress={() => onChange(o.value)} style={{ flex: 1, paddingVertical: 9, alignItems: 'center' }}>
          <T size={13} weight="bold" color={o.value === value ? '#04261B' : C.sub}>
            {o.label}
          </T>
        </PressScale>
      ))}
    </View>
  );
}

