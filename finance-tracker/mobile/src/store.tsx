import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { AppState, PermissionsAndroid, Platform } from 'react-native';

import { readInbox, smsSupported } from '../modules/sms-reader';
import { wasteInsights } from './lib/analysis';
import type { UserRule } from './lib/categorizer';
import { demoMessages } from './lib/demo';
import { buildHoldings, DEFAULT_ASSUMPTIONS, fetchNavs, investmentInsights, type Assumptions } from './lib/investments';
import { buildLedger, type Ledger } from './lib/ledger';
import type { Holding, Insight } from './lib/types';

const DAY = 86_400_000;
const HISTORY_DAYS = 400;
const K = { rules: 'rules.v1', overrides: 'overrides.v1', demo: 'demo.v1', navs: 'navs.v1', assumptions: 'assumptions.v1' };

type Source = 'sms' | 'demo' | 'none';
type Navs = Record<string, { nav: number; date: number }>;

interface State {
  loading: boolean;
  error: string | null;
  source: Source;
  permission: 'granted' | 'denied' | 'unknown';
  lastSync: number | null;
  smsCount: number;
  ledger: Ledger;
  holdings: Holding[];
  waste: Insight[];
  investInsights: Insight[];
  assumptions: Assumptions;
  demoMode: boolean;
  refresh: () => Promise<void>;
  setDemoMode: (on: boolean) => Promise<void>;
  setCategory: (txnId: string, category: string, applyToMerchant: boolean) => Promise<void>;
  setAssumptions: (a: Assumptions) => Promise<void>;
}

const Ctx = createContext<State | null>(null);

async function load<T>(key: string, fallback: T): Promise<T> {
  try {
    const v = await AsyncStorage.getItem(key);
    return v ? (JSON.parse(v) as T) : fallback;
  } catch {
    return fallback;
  }
}
const save = (key: string, v: unknown) => AsyncStorage.setItem(key, JSON.stringify(v)).catch(() => {});

async function ensureSmsPermission(): Promise<boolean> {
  if (Platform.OS !== 'android') return false;
  const perm = PermissionsAndroid.PERMISSIONS.READ_SMS;
  if (await PermissionsAndroid.check(perm)) return true;
  const res = await PermissionsAndroid.request(perm, {
    title: 'Read bank alert SMS',
    message:
      'Paisa Watch reads the transaction alerts your banks, card issuers and mutual-fund registrars send by SMS, ' +
      'so it can track spending, balances and investments without you typing anything. ' +
      'Everything stays on this phone; personal messages are never read.',
    buttonPositive: 'Allow',
    buttonNegative: 'Not now',
  });
  return res === PermissionsAndroid.RESULTS.GRANTED;
}

const EMPTY: Ledger = { transactions: [], accounts: [], mfOrders: [] };

export function DataProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [source, setSource] = useState<Source>('none');
  const [permission, setPermission] = useState<State['permission']>('unknown');
  const [lastSync, setLastSync] = useState<number | null>(null);
  const [smsCount, setSmsCount] = useState(0);
  const [ledger, setLedger] = useState<Ledger>(EMPTY);
  const [navs, setNavs] = useState<Navs>({});
  const [assumptions, setAssumptionsState] = useState<Assumptions>(DEFAULT_ASSUMPTIONS);
  const [demoMode, setDemoModeState] = useState(false);
  const busy = useRef(false);

  const refresh = useCallback(async (forceDemo?: boolean) => {
    if (busy.current) return;
    busy.current = true;
    setLoading(true);
    setError(null);
    try {
      const [rules, overrides, demo, cachedNavs, a] = await Promise.all([
        load<UserRule[]>(K.rules, []),
        load<Record<string, string>>(K.overrides, {}),
        forceDemo ?? load<boolean>(K.demo, false),
        load<Navs>(K.navs, {}),
        load<Assumptions>(K.assumptions, DEFAULT_ASSUMPTIONS),
      ]);
      setDemoModeState(demo);
      setAssumptionsState(a);
      setNavs(cachedNavs);

      let messages = demo ? demoMessages() : [];
      let src: Source = demo ? 'demo' : 'none';
      if (!demo && smsSupported) {
        const ok = await ensureSmsPermission();
        setPermission(ok ? 'granted' : 'denied');
        if (ok) {
          messages = await readInbox(Date.now() - HISTORY_DAYS * DAY);
          src = 'sms';
        }
      }
      const l = buildLedger(messages, rules, overrides);
      setLedger(l);
      setSource(src);
      setSmsCount(messages.length);
      setLastSync(Date.now());

      // Live NAVs for mutual funds (needs internet; falls back to NAV from the last SMS).
      const schemes = [...new Set(l.mfOrders.map((o) => o.scheme))];
      if (schemes.length) {
        fetchNavs(schemes).then((fresh) => {
          if (Object.keys(fresh).length) {
            const merged = { ...cachedNavs, ...fresh };
            setNavs(merged);
            save(K.navs, merged);
          }
        });
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      busy.current = false;
      setLoading(false);
    }
  }, []);

  // Initial load, then re-scan every time the app comes back to the foreground,
  // so new alerts show up without doing anything.
  useEffect(() => {
    refresh();
    const sub = AppState.addEventListener('change', (s) => {
      if (s === 'active') refresh();
    });
    return () => sub.remove();
  }, [refresh]);

  const setDemoMode = useCallback(
    async (on: boolean) => {
      await save(K.demo, on);
      await refresh(on);
    },
    [refresh],
  );

  const setCategory = useCallback(
    async (txnId: string, category: string, applyToMerchant: boolean) => {
      const overrides = await load<Record<string, string>>(K.overrides, {});
      overrides[txnId] = category;
      await save(K.overrides, overrides);
      const t = ledger.transactions.find((x) => x.id === txnId);
      if (applyToMerchant && t?.merchant) {
        const rules = (await load<UserRule[]>(K.rules, [])).filter((r) => r.pattern !== t.merchant.toLowerCase());
        rules.unshift({ pattern: t.merchant.toLowerCase(), category });
        await save(K.rules, rules);
      }
      await refresh();
    },
    [ledger, refresh],
  );

  const setAssumptions = useCallback(async (a: Assumptions) => {
    setAssumptionsState(a);
    await save(K.assumptions, a);
  }, []);

  const holdings = useMemo(() => buildHoldings(ledger.mfOrders, navs), [ledger, navs]);
  const waste = useMemo(() => wasteInsights(ledger.transactions), [ledger]);
  const investInsights = useMemo(
    () => investmentInsights(holdings, ledger.accounts, ledger.transactions, assumptions),
    [holdings, ledger, assumptions],
  );

  const value: State = {
    loading,
    error,
    source,
    permission,
    lastSync,
    smsCount,
    ledger,
    holdings,
    waste,
    investInsights,
    assumptions,
    demoMode,
    refresh: () => refresh(),
    setDemoMode,
    setCategory,
    setAssumptions,
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useData(): State {
  const v = useContext(Ctx);
  if (!v) throw new Error('useData outside DataProvider');
  return v;
}
