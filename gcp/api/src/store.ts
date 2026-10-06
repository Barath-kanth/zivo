import { randomUUID } from 'crypto';
import { Firestore, FieldValue } from '@google-cloud/firestore';
import {
  DISPATCH_RADIUS_KM,
  PLATFORM_FEE_PERCENT,
  gcpProjectId,
} from './config.js';
import { refreshPhotoUrls } from './uploads.js';

export type Skill = 'none' | 'driving' | 'care' | 'tutoring';

export type UserProfile = {
  id: string;
  full_name: string;
  avatar_url?: string;
  phone?: string;
  phone_verified_at?: string;
  email?: string;
  email_verified_at?: string;
  is_helper_active: boolean;
  helper_bio?: string;
  helper_skills: string[];
  rating_as_client: number;
  rating_as_helper: number;
  total_tasks_posted: number;
  total_tasks_helped: number;
  wallet_balance: number;
  escrow_balance: number;
  helper_earnings: number;
  kyc_status: string;
  kyc_rejection_reason?: string;
  nic_number?: string;
  home_address?: string;
  role_intent: string;
  guidelines_accepted_at?: string;
  password_hash?: string;
};

export type TaskRow = {
  id: string;
  title: string;
  description: string;
  category: string;
  status: string;
  client_id: string;
  helper_id?: string;
  estimated_hours: number;
  hourly_rate: number;
  total_amount: number;
  goods_budget: number;
  requires_purchase_proof: boolean;
  lat: number;
  lon: number;
  location_address?: string;
  location_label?: string;
  start_otp?: string;
  end_otp?: string;
  confirm_code?: string;
  created_at: string;
  photo_urls?: string[];
  photo_paths?: string[];
  helper?: { full_name: string; avatar_url?: string; rating_as_helper: number };
};

export type LedgerEntry = {
  id: string;
  user_id: string;
  task_id?: string;
  entry_type: string;
  amount: number;
  balance_after: number;
  description: string;
  created_at: string;
};

type Session = { token: string; userId: string; expiresAt: number };
type OtpRecord = { code: string; phone: string; expiresAt: number };

/** Free-tier Firestore (Native). No Cloud SQL. */
const useMemory =
  (process.env.USE_MEMORY_STORE ?? 'false').toLowerCase() === 'true' ||
  !gcpProjectId ||
  gcpProjectId === 'your-gcp-project-id';

let db: Firestore | null = null;
function firestore(): Firestore {
  if (!db) {
    db = new Firestore({
      projectId: gcpProjectId,
      ignoreUndefinedProperties: true,
    });
  }
  return db;
}

// In-memory fallback for local-only runs without GCP credentials.
const memUsers = new Map<string, UserProfile>();
const memTasks = new Map<string, TaskRow>();
const memLedger: LedgerEntry[] = [];
const memSessions = new Map<string, Session>();
const memOtps = new Map<string, OtpRecord>();

export function dbMode(): 'firestore' | 'memory' {
  return useMemory ? 'memory' : 'firestore';
}

function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const la1 = (a.lat * Math.PI) / 180;
  const la2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(la1) * Math.cos(la2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function otpDocId(phone: string) {
  return phone.replace(/[^\d+]/g, '').replace(/\+/g, 'p');
}

function stripPassword(u: UserProfile) {
  const { password_hash: _, ...rest } = u;
  return rest;
}

async function saveUser(u: UserProfile) {
  if (useMemory) {
    memUsers.set(u.id, u);
    return;
  }
  await firestore().collection('users').doc(u.id).set(u, { merge: true });
}

async function loadUser(id: string): Promise<UserProfile | undefined> {
  if (useMemory) return memUsers.get(id);
  const snap = await firestore().collection('users').doc(id).get();
  return snap.exists ? (snap.data() as UserProfile) : undefined;
}

async function allUsers(): Promise<UserProfile[]> {
  if (useMemory) return [...memUsers.values()];
  const snap = await firestore().collection('users').get();
  return snap.docs.map((d) => d.data() as UserProfile);
}

async function saveTask(t: TaskRow) {
  if (useMemory) {
    memTasks.set(t.id, t);
    return;
  }
  await firestore().collection('tasks').doc(t.id).set(t, { merge: true });
}

async function loadTask(id: string): Promise<TaskRow | undefined> {
  let task: TaskRow | undefined;
  if (useMemory) {
    task = memTasks.get(id);
  } else {
    const snap = await firestore().collection('tasks').doc(id).get();
    task = snap.exists ? (snap.data() as TaskRow) : undefined;
  }
  if (!task) return undefined;
  if (task.photo_paths?.length) {
    task = { ...task, photo_urls: await refreshPhotoUrls(task.photo_paths) };
  }
  return task;
}

async function allTasks(): Promise<TaskRow[]> {
  let rows: TaskRow[];
  if (useMemory) {
    rows = [...memTasks.values()];
  } else {
    const snap = await firestore().collection('tasks').get();
    rows = snap.docs.map((d) => d.data() as TaskRow);
  }
  return Promise.all(
    rows.map(async (t) =>
      t.photo_paths?.length
        ? { ...t, photo_urls: await refreshPhotoUrls(t.photo_paths) }
        : t,
    ),
  );
}

export async function seedDemo() {
  if (useMemory) {
    if (memUsers.size) return;
  } else {
    const meta = await firestore().collection('meta').doc('seed').get();
    if (meta.exists) return;
  }

  const demoHelpers: Array<Partial<UserProfile> & { id: string; full_name: string }> = [
    {
      id: 'h1',
      full_name: 'Nimal (verified)',
      is_helper_active: true,
      kyc_status: 'verified',
      helper_skills: ['driving'],
      guidelines_accepted_at: new Date().toISOString(),
      wallet_balance: 5000,
    },
    {
      id: 'h2',
      full_name: 'Sajith (unverified)',
      is_helper_active: false,
      kyc_status: 'unverified',
      helper_skills: [],
      wallet_balance: 0,
    },
    {
      id: 'h3',
      full_name: 'Fathima (care)',
      is_helper_active: true,
      kyc_status: 'verified',
      helper_skills: ['care'],
      guidelines_accepted_at: new Date().toISOString(),
      wallet_balance: 2000,
    },
  ];

  for (const h of demoHelpers) {
    await saveUser({
      id: h.id,
      full_name: h.full_name,
      is_helper_active: h.is_helper_active ?? false,
      helper_skills: h.helper_skills ?? [],
      rating_as_client: 5,
      rating_as_helper: 4.8,
      total_tasks_posted: 0,
      total_tasks_helped: 3,
      wallet_balance: h.wallet_balance ?? 0,
      escrow_balance: 0,
      helper_earnings: 1200,
      kyc_status: h.kyc_status ?? 'unverified',
      role_intent: 'helper',
      guidelines_accepted_at: h.guidelines_accepted_at,
      phone: `+9477${h.id.replace(/\D/g, '').padEnd(7, '0').slice(0, 7)}`,
      phone_verified_at: new Date().toISOString(),
    });
  }

  if (!useMemory) {
    await firestore().collection('meta').doc('seed').set({
      at: FieldValue.serverTimestamp(),
      note: 'Zivo free-tier Firestore seed',
    });
  }
}

export async function createSession(userId: string): Promise<string> {
  const token = randomUUID();
  const session: Session = {
    token,
    userId,
    expiresAt: Date.now() + 7 * 24 * 3600_000,
  };
  if (useMemory) {
    memSessions.set(token, session);
  } else {
    await firestore().collection('sessions').doc(token).set(session);
  }
  return token;
}

export async function userIdFromAuthHeader(header?: string): Promise<string | null> {
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice(7);
  if (useMemory) {
    const s = memSessions.get(token);
    if (!s || s.expiresAt < Date.now()) return null;
    return s.userId;
  }
  const snap = await firestore().collection('sessions').doc(token).get();
  if (!snap.exists) return null;
  const s = snap.data() as Session;
  if (s.expiresAt < Date.now()) return null;
  return s.userId;
}

export async function getUser(id: string) {
  return loadUser(id);
}

export async function listUsers() {
  return (await allUsers()).map(stripPassword);
}

export async function upsertUser(profile: UserProfile) {
  await saveUser(profile);
  return stripPassword(profile);
}

export function publicProfile(u: UserProfile) {
  return stripPassword(u);
}

export async function issuePhoneOtp(phone: string): Promise<string> {
  const code = String(Math.floor(100000 + Math.random() * 900000));
  const rec: OtpRecord = { code, phone, expiresAt: Date.now() + 10 * 60_000 };
  if (useMemory) {
    memOtps.set(phone, rec);
  } else {
    await firestore().collection('otps').doc(otpDocId(phone)).set(rec);
  }
  return code;
}

export async function verifyPhoneOtp(phone: string, token: string): Promise<UserProfile> {
  let rec: OtpRecord | undefined;
  if (useMemory) {
    rec = memOtps.get(phone);
    if (rec) memOtps.delete(phone);
  } else {
    const ref = firestore().collection('otps').doc(otpDocId(phone));
    const snap = await ref.get();
    rec = snap.exists ? (snap.data() as OtpRecord) : undefined;
    if (snap.exists) await ref.delete();
  }
  if (!rec || rec.expiresAt < Date.now() || rec.code !== token) {
    throw new Error('Invalid or expired OTP');
  }

  const users = await allUsers();
  let user = users.find((u) => u.phone === phone);
  if (!user) {
    const id = randomUUID();
    user = {
      id,
      full_name: '',
      phone,
      phone_verified_at: new Date().toISOString(),
      is_helper_active: false,
      helper_skills: [],
      rating_as_client: 5,
      rating_as_helper: 5,
      total_tasks_posted: 0,
      total_tasks_helped: 0,
      wallet_balance: 10000,
      escrow_balance: 0,
      helper_earnings: 0,
      kyc_status: 'verified',
      role_intent: 'client',
      guidelines_accepted_at: new Date().toISOString(),
    };
  } else {
    user = { ...user, phone_verified_at: new Date().toISOString() };
  }
  await saveUser(user);
  return user;
}

export async function signUpEmail(input: {
  email: string;
  password: string;
  full_name: string;
}): Promise<UserProfile> {
  const users = await allUsers();
  if (users.find((u) => u.email === input.email)) {
    throw new Error('Email already registered');
  }
  const id = randomUUID();
  const user: UserProfile = {
    id,
    full_name: input.full_name,
    email: input.email,
    email_verified_at: new Date().toISOString(),
    password_hash: input.password,
    is_helper_active: false,
    helper_skills: [],
    rating_as_client: 5,
    rating_as_helper: 5,
    total_tasks_posted: 0,
    total_tasks_helped: 0,
    wallet_balance: 10000,
    escrow_balance: 0,
    helper_earnings: 0,
    kyc_status: 'verified',
    role_intent: 'client',
    guidelines_accepted_at: new Date().toISOString(),
  };
  await saveUser(user);
  return user;
}

export async function signInEmail(email: string, password: string): Promise<UserProfile> {
  const users = await allUsers();
  const user = users.find((u) => u.email === email);
  if (!user || user.password_hash !== password) {
    throw new Error('Invalid email or password');
  }
  return user;
}

export async function createTask(input: {
  client_id: string;
  title: string;
  description: string;
  category: string;
  estimated_hours: number;
  hourly_rate: number;
  goods_budget: number;
  lat: number;
  lon: number;
  location_address?: string;
  location_label?: string;
  photo_urls?: string[];
  photo_paths?: string[];
}): Promise<TaskRow> {
  const client = await loadUser(input.client_id);
  if (!client) throw new Error('Client not found');
  if (client.kyc_status !== 'verified') {
    throw new Error('KYC verification required to post tasks');
  }
  const total = input.estimated_hours * input.hourly_rate;
  const hold = total + input.goods_budget;
  if (client.wallet_balance < hold) {
    throw new Error('Insufficient wallet balance for escrow hold');
  }
  client.wallet_balance -= hold;
  client.escrow_balance += hold;
  client.total_tasks_posted += 1;
  await saveUser(client);

  const id = `task_${Date.now()}`;
  const confirm = String(Math.floor(1000 + Math.random() * 9000));
  const startOtp = String(Math.floor(1000 + Math.random() * 9000));
  const endOtp = String(Math.floor(1000 + Math.random() * 9000));
  const row: TaskRow = {
    id,
    title: input.title,
    description: input.description,
    category: input.category,
    status: 'open',
    client_id: input.client_id,
    estimated_hours: input.estimated_hours,
    hourly_rate: input.hourly_rate,
    total_amount: total,
    goods_budget: input.goods_budget,
    requires_purchase_proof: input.goods_budget > 0,
    lat: input.lat,
    lon: input.lon,
    location_address: input.location_address,
    location_label: input.location_label,
    start_otp: startOtp,
    end_otp: endOtp,
    confirm_code: confirm,
    created_at: new Date().toISOString(),
    photo_urls: input.photo_urls?.filter(Boolean).slice(0, 5) ?? [],
    photo_paths: input.photo_paths?.filter(Boolean).slice(0, 5) ?? [],
  };
  await saveTask(row);
  await addLedger(client.id, id, 'escrow_hold', -hold, client.wallet_balance, 'Escrow hold');
  return row;
}

export async function getTask(id: string) {
  return loadTask(id);
}

export async function listClientTasks(clientId: string) {
  return (await allTasks())
    .filter((t) => t.client_id === clientId)
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

/** Matched / in-progress jobs for a helper (Active tab). */
export async function listHelperActiveTasks(helperId: string) {
  return (await allTasks())
    .filter(
      (t) =>
        t.helper_id === helperId &&
        (t.status === 'matched' || t.status === 'in_progress'),
    )
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export async function listOpenTasks(helperLat: number, helperLng: number) {
  return (await allTasks())
    .filter((t) => t.status === 'open')
    .map((t) => ({
      ...t,
      distance_km: haversineKm(
        { lat: helperLat, lng: helperLng },
        { lat: t.lat, lng: t.lon },
      ),
    }))
    .filter((t) => t.distance_km <= DISPATCH_RADIUS_KM)
    .sort((a, b) => a.distance_km - b.distance_km);
}

export async function acceptTask(taskId: string, helperId: string) {
  const task = await loadTask(taskId);
  const helper = await loadUser(helperId);
  if (!task) throw new Error('Task not found');
  if (!helper) throw new Error('Helper not found');
  if (helper.kyc_status !== 'verified') throw new Error('Helper must be KYC verified');
  // Auto-activate helper mode if they are already verified (UI toggle may lag).
  if (!helper.is_helper_active) {
    helper.is_helper_active = true;
    await saveUser(helper);
  }
  if (task.status !== 'open') throw new Error('Task not open');
  task.status = 'matched';
  task.helper_id = helperId;
  task.helper = {
    full_name: helper.full_name,
    avatar_url: helper.avatar_url,
    rating_as_helper: helper.rating_as_helper,
  };
  await saveTask(task);
  return task;
}

/** Helper enters Start OTP → job becomes in_progress; client then reveals End OTP. */
export async function startTask(taskId: string, startOtp: string) {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (task.status !== 'matched') {
    throw new Error(
      task.status === 'in_progress'
        ? 'Job already started'
        : `Cannot start from status ${task.status}`,
    );
  }
  if (!task.start_otp || startOtp !== task.start_otp) {
    throw new Error('Invalid Start OTP');
  }
  task.status = 'in_progress';
  await saveTask(task);
  return task;
}

export async function completeTask(
  taskId: string,
  input: { confirm_code: string; receipt_total_lkr: number },
) {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (task.status !== 'in_progress' && task.status !== 'matched') {
    throw new Error(`Cannot complete from status ${task.status}`);
  }
  if (input.confirm_code !== task.confirm_code && input.confirm_code !== task.end_otp) {
    throw new Error('Invalid End OTP — ask the client for the End code (not Start)');
  }
  const client = await loadUser(task.client_id);
  if (!client) throw new Error('Client missing');
  const labor = task.total_amount;
  const goods = Math.min(input.receipt_total_lkr, task.goods_budget);
  const unused = task.goods_budget - goods;
  const fee = (labor * PLATFORM_FEE_PERCENT) / 100;
  const helperPay = labor - fee;

  client.escrow_balance -= labor + task.goods_budget;
  client.wallet_balance += unused;
  await saveUser(client);

  if (task.helper_id) {
    const helper = await loadUser(task.helper_id);
    if (helper) {
      helper.wallet_balance += helperPay + goods;
      helper.helper_earnings += helperPay + goods;
      helper.total_tasks_helped += 1;
      await saveUser(helper);
      await addLedger(
        helper.id,
        taskId,
        'release',
        helperPay + goods,
        helper.wallet_balance,
        'Escrow release',
      );
    }
  }
  await addLedger(client.id, taskId, 'release', unused, client.wallet_balance, 'Unused goods returned');
  task.status = 'completed';
  await saveTask(task);
  return {
    task,
    ledger: {
      helperLabor: helperPay,
      platformFee: fee,
      goodsReimburse: goods,
      unusedGoodsReturnedToClient: unused,
      rule: 'No physical cash to helpers for goods',
    },
  };
}

export async function topUp(userId: string, amount: number) {
  const u = await loadUser(userId);
  if (!u) throw new Error('User not found');
  u.wallet_balance += amount;
  await saveUser(u);
  await addLedger(userId, undefined, 'topup', amount, u.wallet_balance, 'Wallet top-up (GCP demo)');
  return u;
}

export async function setHelperActive(userId: string, active: boolean) {
  const u = await loadUser(userId);
  if (!u) throw new Error('User not found');
  if (active && u.kyc_status !== 'verified') {
    throw new Error('KYC verification required for helper mode');
  }
  if (active && !u.guidelines_accepted_at) {
    u.guidelines_accepted_at = new Date().toISOString();
  }
  u.is_helper_active = active;
  await saveUser(u);
  return u;
}

async function addLedger(
  userId: string,
  taskId: string | undefined,
  entryType: string,
  amount: number,
  balanceAfter: number,
  description: string,
) {
  const entry: LedgerEntry = {
    id: randomUUID(),
    user_id: userId,
    task_id: taskId,
    entry_type: entryType,
    amount,
    balance_after: balanceAfter,
    description,
    created_at: new Date().toISOString(),
  };
  if (useMemory) {
    memLedger.push(entry);
  } else {
    await firestore().collection('ledger').doc(entry.id).set(entry);
  }
}

export async function listLedger(userId: string) {
  if (useMemory) {
    return memLedger
      .filter((e) => e.user_id === userId)
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
  }
  const snap = await firestore()
    .collection('ledger')
    .where('user_id', '==', userId)
    .get();
  return snap.docs
    .map((d) => d.data() as LedgerEntry)
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

/** Deterministic demo offsets so nearest ≠ best under dispute constraints. */
const HELPER_GEO_OFFSET: Record<string, { dLat: number; dLng: number }> = {
  h1: { dLat: 0.0018, dLng: 0.0004 }, // ~0.2 km — nearest
  h3: { dLat: 0.012, dLng: -0.004 }, // ~1.4 km — farther, clean history
};

export async function helpersForMatch(task: TaskRow) {
  return (await allUsers())
    .filter((u) => u.is_helper_active && u.kyc_status === 'verified')
    .map((u) => {
      const off = HELPER_GEO_OFFSET[u.id] ?? { dLat: 0.02, dLng: 0.01 };
      const distanceKm = haversineKm(
        { lat: task.lat, lng: task.lon },
        { lat: task.lat + off.dLat, lng: task.lon + off.dLng },
      );
      return { helper: u, distanceKm };
    })
    .filter((x) => x.distanceKm <= DISPATCH_RADIUS_KM);
}

export { haversineKm, DISPATCH_RADIUS_KM, PLATFORM_FEE_PERCENT };
