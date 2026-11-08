import * as LocalAuthentication from 'expo-local-authentication';
import { Component, useCallback, useEffect, useState, type ReactNode } from 'react';
import { Share, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { formatErrors, getErrors, logError } from '../errorLog';
import { C } from '../theme';
import { FadeIn } from './anim';
import { ShieldArt } from './Illustrations';
import { Button, T } from './ui';

/** True when the phone can verify the owner (fingerprint/face or a screen lock PIN/pattern). */
export async function canUseDeviceLock(): Promise<boolean> {
  try {
    const level = await LocalAuthentication.getEnrolledLevelAsync();
    return level !== LocalAuthentication.SecurityLevel.NONE;
  } catch {
    return false;
  }
}

export async function verifyOwner(reason = 'Unlock Paisa Watch'): Promise<boolean> {
  try {
    const r = await LocalAuthentication.authenticateAsync({ promptMessage: reason, cancelLabel: 'Cancel', disableDeviceFallback: false });
    return r.success;
  } catch (e) {
    logError('lock', e);
    return false;
  }
}

/** Full-screen lock. Asks for fingerprint / face / PIN as soon as it appears. */
export function LockScreen({ onUnlock }: { onUnlock: () => void }) {
  const insets = useSafeAreaInsets();
  const [failed, setFailed] = useState(false);
  const attempt = useCallback(async () => {
    setFailed(false);
    if (await verifyOwner()) onUnlock();
    else setFailed(true);
  }, [onUnlock]);
  useEffect(() => {
    attempt();
  }, [attempt]);
  return (
    <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: C.bg, alignItems: 'center', justifyContent: 'center', padding: 32, paddingBottom: insets.bottom + 32 }}>
      <FadeIn style={{ alignItems: 'center', width: '100%' }}>
        <ShieldArt size={150} />
        <T size={24} weight="black" style={{ marginTop: 18 }}>
          Paisa Watch is locked
        </T>
        <T size={14} color={C.sub} style={{ marginTop: 6, textAlign: 'center' }}>
          {failed ? "Couldn't verify it's you. Try again." : 'Use your fingerprint, face or screen lock to open.'}
        </T>
        <Button label="Unlock" icon="lock" onPress={attempt} style={{ alignSelf: 'stretch', marginTop: 24 }} />
      </FadeIn>
    </View>
  );
}

/** Catches rendering crashes, records them, and offers a way back instead of closing the app. */
export class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: { componentStack?: string | null }) {
    logError('screen', error, info.componentStack?.split('\n').slice(0, 6).join('\n'));
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <View style={{ flex: 1, backgroundColor: C.bg, justifyContent: 'center', padding: 28 }}>
        <T size={24} weight="black">
          Something went wrong
        </T>
        <T size={14} color={C.sub} style={{ marginTop: 8 }}>
          This screen hit an error. It's been saved to the problem log on this phone. Sharing it helps get it fixed.
        </T>
        <T size={12} color={C.faint} style={{ marginTop: 12 }}>
          {this.state.error.message}
        </T>
        <Button label="Try again" icon="refresh" onPress={() => this.setState({ error: null })} />
        <Button
          label="Share problem log"
          icon="share"
          kind="ghost"
          onPress={async () => Share.share({ message: 'Paisa Watch problem log:\n\n' + formatErrors(await getErrors()) })}
        />
      </View>
    );
  }
}
