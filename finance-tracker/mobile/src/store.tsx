import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { AppState, PermissionsAndroid, Platform, type Permission } from 'react-native';

import { canNotify, readInbox, scheduleReminders, setAlertPrefs as pushAlertPrefs, smsSupported, type AlertMode } from '../modules/sms-reader';
import { findRecurring, wasteInsights } from './lib/analysis';
import type { UserRule } from './lib/categorizer';
import { demoMessages } from './lib/demo';
import { buildHoldings, DEFAULT_ASSUMPTIONS, fetchNavs, investmentInsights, type Assumptions } from './lib/investments';
import { buildLedger, type Ledger } from './lib/ledger';
import { planReminders } from './lib/reminders';
import type { Holding, Insight, RawSms } from './lib/types';

const DAY = 86_400_000;
const HISTORY_DAYS = 400;
const K = {
  rules: 'rules.v1',
  overrides: 'overrides.v1',
  demo: 'demo.v1',
  navs: 'navs.v1',
  assumptions: 'assumptions.v1',
  alerts: 'alerts.v1',
};

type Source = 'sms' | 'demo' | 'none';
type Navs = Record<string, { nav: number; date: number }>;
export interface AlertPrefs {
  mode: AlertMode;
  largeAmount: number;
  billReminders: boolean;
}
const DEFAULT_ALERTS: AlertPrefs = { mode: 'smart', largeAmount: 5000, billReminders: true };

interface State {
  loading: boolean;
  error: string | null;
  source: Source;
  permission: 'granted' | 'denied' | 'unknown';
  notifications: boolean;
  lastSync: number | null;
  smsCount: number;
  ledger: Ledger;
  holdings: Holding[];
  waste: Insight[];
  investInsights: Insight[];
  assumptions: Assumptions;
  alertPrefs: AlertPrefs;
  demoMode: boolean;
  refresh: (full?: boolean) => Promise<void>;
  setDemoMode: (on: boolean) => Promise<void>;
  setCategory: (txnId: string, category: string, applyToMerchant: boolean) => Promise<void>;
  setAssumptions: (a: Assumptions) => Promise<void>;
  setAlertPrefs: (a: AlertPrefs) => Promise<void>;
}

const Ctx = createContext<State | null>(null);

async function load<T>(key: string, fallback: T): Promise<T> {
  try {
    const v = await AsyncStorage.getItem(key);
    return v ? ({ ...(fallback as object), ...JSON.parse(v) } as T) : fallback;
  } catch {
    return fallback;
  }
}
async function loadList<T>(key: string): Promise<T[]> {
  try {
    const v = await AsyncStorage.getItem(key);
    return v ? (JSON.parse(v) as T[]) : [];
  } catch {
    return [];
  }
}
async function loadBool(key: string): Promise<boolean> {
  try {
    return (await AsyncStorage.getItem(key)) === 'true';
  } catch {
    return false;
  }
}
const save = (key: string, v: unknown) => AsyncStorage.setItem(key, JSON.stringify(v)).catch(() => {});

/** Asks once for SMS read + receive (same Android permission group) and notifications. */
async function ensurePermissions(): Promise<{ sms: boolean; notify: boolean }> {
  if (Platform.OS !== 'android') return { sms: false, notify: false };
  const P = PermissionsAndroid.PERMISSIONS;
  const wanted: Permission[] = [P.READ_SMS, P.RECEIVE_SMS];
  if (Number(Platform.Version) >= 33) wanted.push(P.POST_NOTIFICATIONS);
  const missing: Permission[] = [];
  for (const p of wanted) if (!(await PermissionsAndroid.check(p))) missing.push(p);
  if (missing.length) await PermissionsAndroid.requestMultiple(missing);
  const sms = await PermissionsAndroid.check(P.READ_SMS);
  return { sms, notify: canNotify() };
}

const EMPTY: Ledger = { transactions: [], accounts: [], mfOrders: [], missed: [] };

export function DataProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [source, setSource] = useState<Source>('none');
  const [permission, setPermission] = useState<State['permission']>('unknown');
  const [notifications, setNotifications] = useState(false);
  const [lastSync, setLastSync] = useState<number | null>(null);
  const [smsCount, setSmsCount] = useState(0);
  const [ledger, setLedger] = useState<Ledger>(EMPTY);
  const [navs, setNavs] = useState<Navs>({});
  const [assumptions, setAssumptionsState] = useState<Assumptions>(DEFAULT_ASSUMPTIONS);
  const [alertPrefs, setAlertPrefsState] = useState<AlertPrefs>(DEFAULT_ALERTS);
  const [demoMode, setDemoModeState] = useState(false);
  const busy = useRef(false);
  // Messages already read this session, so returning to the app only reads what is new.
  const cache = useRef<Map<string, RawSms>>(new Map());

  const syncNative = useCallback((l: Ledger, prefs: AlertPrefs, src: Source) => {
    if (src !== 'sms') {
      scheduleReminders([]);
      return;
    }
    const recurring = findRecurring(l.transactions).map((r) => r.merchant.toLowerCase());
    pushAlertPrefs(prefs.mode, prefs.largeAmount, recurring);
    scheduleReminders(prefs.billReminders ? planReminders(l.accounts) : []);
  }, []);

  const refresh = useCallback(
    async (full = false, forceDemo?: boolean) => {
      if (busy.current) return;
      busy.current = true;
      setLoading(true);
      setError(null);
      try {
        const [rules, overrides, demo, cachedNavs, a, prefs] = await Promise.all([
          loadList<UserRule>(K.rules),
          load<Record<string, string>>(K.overrides, {}),
          forceDemo ?? loadBool(K.demo),
          load<Navs>(K.navs, {}),
          load<Assumptions>(K.assumptions, DEFAULT_ASSUMPTIONS),
          load<AlertPrefs>(K.alerts, DEFAULT_ALERTS),
        ]);
        setDemoModeState(demo);
        setAssumptionsState(a);
        setAlertPrefsState(prefs);
        setNavs(cachedNavs);

        let messages: RawSms[] = [];
        let src: Source = 'none';
        if (demo) {
          messages = demoMessages();
          src = 'demo';
        } else if (smsSupported) {
          const perms = await ensurePermissions();
          setPermission(perms.sms ? 'granted' : 'denied');
          setNotifications(perms.notify);
          if (perms.sms) {
            if (full) cache.current.clear();
            const newest = Math.max(0, ...[...cache.current.values()].map((m) => m.date));
            const since = cache.current.size ? newest - 10 * 60_000 : Date.now() - HISTORY_DAYS * DAY;
            for (const m of await readInbox(since)) cache.current.set(m.id, m);
            messages = [...cache.current.values()];
            src = 'sms';
          }
        }
        const l = buildLedger(messages, rules, overrides);
        setLedger(l);
        setSource(src);
        setSmsCount(messages.length);
        setLastSync(Date.now());
        syncNative(l, prefs, src);

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
    },
    [syncNative],
  );

  // Initial load, then pick up new alerts every time the app comes back to the foreground.
  useEffect(() => {
    refresh();
    const sub = AppState.addEventListener('change', (s) => {
      if (s === 'active') refresh();
    });
    return () => sub.remove();
  }, [refresh]);

  const setDemoMode = useCallback(
    async (on: boolean) => {
      await AsyncStorage.setItem(K.demo, on ? 'true' : 'false').catch(() => {});
      await refresh(true, on);
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
        const rules = (await loadList<UserRule>(K.rules)).filter((r) => r.pattern !== t.merchant.toLowerCase());
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

  const setAlertPrefs = useCallback(
    async (p: AlertPrefs) => {
      setAlertPrefsState(p);
      await save(K.alerts, p);
      syncNative(ledger, p, source);
    },
    [ledger, source, syncNative],
  );

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
    notifications,
    lastSync,
    smsCount,
    ledger,
    holdings,
    waste,
    investInsights,
    assumptions,
    alertPrefs,
    demoMode,
    refresh: (full?: boolean) => refresh(full),
    setDemoMode,
    setCategory,
    setAssumptions,
    setAlertPrefs,
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useData(): State {
  const v = useContext(Ctx);
  if (!v) throw new Error('useData outside DataProvider');
  return v;
}
