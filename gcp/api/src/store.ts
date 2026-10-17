import { randomUUID } from 'crypto';
import { Firestore, FieldValue } from '@google-cloud/firestore';
import {
  DISPATCH_RADIUS_KM,
  PLATFORM_FEE_PERCENT,
  VOUCH_STAKE_LKR,
  VOUCH_THRESHOLD,
  WALK_RADIUS_KM,
  gcpProjectId,
} from './config.js';
import { refreshPhotoUrls } from './uploads.js';
import { accessCardFor } from './pillars/abilities.js';
import {
  cacheTaskSnapshot,
  readCachedTaskSnapshot,
} from './redis_cache.js';

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
  /** Porch-light presence for instant walkable dispatch. */
  presence_available?: boolean;
  presence_lat?: number;
  presence_lon?: number;
  presence_at?: string;
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
  /** Home pin for neighbor-vouch locality checks. */
  home_lat?: number;
  home_lon?: number;
  /** Count of active neighbor vouches received (Pillar 4). */
  vouch_count?: number;
  /** True when vouch_count ≥ VOUCH_THRESHOLD — unlocks inside-home work. */
  neighbor_vouched?: boolean;
  role_intent: string;
  guidelines_accepted_at?: string;
  password_hash?: string;
  preferred_lang?: 'en' | 'si' | 'ta';
  /** Opt-in ability profile (visual|hearing|speech|mobility|cognitive). Private unless disclose_access. */
  abilities?: string[];
  /** Helper chose to tell clients, so they can hire or decline knowingly. */
  disclose_access?: boolean;
  /** Helper's own words to clients. */
  access_note?: string;
};

export type VouchRow = {
  id: string;
  helper_id: string;
  voucher_id: string;
  voucher_name: string;
  stake_lkr: number;
  note?: string;
  created_at: string;
  status: 'active' | 'revoked';
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
  goods_spent?: number;
  requires_purchase_proof: boolean;
  /** Labor jobs need before/after style proof; grocery also uses purchase proof. */
  requires_completion_proof?: boolean;
  completion_checklist?: string[];
  proof_submitted_at?: string;
  proof_photo_urls?: string[];
  proof_photo_paths?: string[];
  proof_checked_items?: string[];
  proof_note?: string;
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
  helper?: {
    full_name: string;
    avatar_url?: string;
    rating_as_helper: number;
    /** Only present when the helper opted to disclose. */
    access?: { abilities: string[]; note?: string };
  };
  /** Helpers the client declined after seeing their access card (cannot re-accept). */
  declined_helper_ids?: string[];
  /** Entrance access audit (stairs/ramp/door) for helpers. */
  access_audit?: Record<string, unknown>;
  /** Street-batch linkage (Pillar 3). */
  batch_id?: string;
  batch_anchor?: boolean;
  batch_discount_pct?: number;
  /** Complete-before deadline (ISO). */
  deadline_at?: string;
  difficulty?: string;
  physical_effort?: string;
  /** Set by Trust Arbitrator — blocks escrow release until cleared. */
  trust_hold?: boolean;
  trust_hold_reason?: string;
  last_trust_review_id?: string;
  disputed_at?: string;
  dispute_reason?: string;
  /** Client-facing "Explain my match" copy. */
  match_explanation?: string;
  match_reasons?: string[];
  match_mode?: 'mock' | 'gemini' | 'dispatch' | 'manual';
  /** One problem → several tasks (bundle checkout). */
  bundle_id?: string;
  bundle_title?: string;
  /** Family Assist — book on behalf of someone else. */
  booked_for_user_id?: string;
  booked_for_name?: string;
  /** Shared live link for family watchers. */
  share_token?: string;
  watcher_ids?: string[];
};

/** Persisted Gemini trust verdict over job evidence (Cup differentiator). */
export type TrustReview = {
  id: string;
  task_id: string;
  requester_id: string;
  verdict: 'continue' | 'hold_escrow' | 'escalate';
  confidence: number;
  summary: string;
  concerns: string[];
  recommended_actions: string[];
  evidence_used: string[];
  created_at: string;
  mode: 'mock' | 'gemini';
};

export type BatchWindow = {
  id: string;
  anchor_task_id: string;
  helper_id: string;
  helper_name: string;
  lat: number;
  lon: number;
  street_label: string;
  opened_at: string;
  expires_at: string;
  status: 'open' | 'closed';
  member_task_ids: string[];
  max_members: number;
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

/** In-app task chat — client ↔ helper only; persisted for dispute/audit. */
export type ChatMessage = {
  id: string;
  task_id: string;
  sender_id: string;
  sender_role: 'client' | 'helper' | 'system';
  body: string;
  /** Exact text the sender typed (never overwritten by translation). */
  body_original?: string;
  source_lang?: 'en' | 'si' | 'ta';
  translations?: Partial<Record<'en' | 'si' | 'ta', string>>;
  /** Viewer-facing body — always the sender's original language. */
  display_body?: string;
  /** Optional translation into the viewer's lang (tap to reveal). */
  translation_body?: string;
  translated?: boolean;
  /** True when the sender used voice → transcript (same safety path as text). */
  via_voice?: boolean;
  created_at: string;
};

export type ChatThread = {
  task_id: string;
  client_id: string;
  helper_id: string;
  created_at: string;
  last_message_at?: string;
  last_preview?: string;
  message_count: number;
  /** WhatsApp-style read cursors — unread badge for the other party. */
  client_last_read_at?: string;
  helper_last_read_at?: string;
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
const memBatches = new Map<string, BatchWindow>();
const memVouches = new Map<string, VouchRow>();
const memLedger: LedgerEntry[] = [];
const memSessions = new Map<string, Session>();
const memOtps = new Map<string, OtpRecord>();
const memChatThreads = new Map<string, ChatThread>();
const memChatMessages = new Map<string, ChatMessage[]>();
const memTrustReviews = new Map<string, TrustReview[]>();

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
  } else {
    await firestore().collection('tasks').doc(t.id).set(t, { merge: true });
  }
  // Hot cache so clients see proof / OTP updates in ~1–2s without waiting on
  // a cold Firestore round-trip (Redis when REDIS_URL is set, else memory).
  void cacheTaskSnapshot(t.id, t as unknown as Record<string, unknown>);
}

/** Persist an access-audit result on a task (client booker only — enforced in route). */
export async function attachTaskAccessAudit(
  taskId: string,
  audit: Record<string, unknown>,
): Promise<TaskRow> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  task.access_audit = audit;
  await saveTask(task);
  return (await loadTask(taskId))!;
}

async function withFreshPhotoUrls(task: TaskRow): Promise<TaskRow> {
  let next = task;
  if (task.photo_paths?.length) {
    next = { ...next, photo_urls: await refreshPhotoUrls(task.photo_paths) };
  }
  if (task.proof_photo_paths?.length) {
    next = {
      ...next,
      proof_photo_urls: await refreshPhotoUrls(task.proof_photo_paths),
    };
  }
  return next;
}

async function loadTask(id: string): Promise<TaskRow | undefined> {
  const cached = await readCachedTaskSnapshot(id);
  if (cached && typeof cached.id === 'string') {
    return withFreshPhotoUrls(cached as unknown as TaskRow);
  }
  let task: TaskRow | undefined;
  if (useMemory) {
    task = memTasks.get(id);
  } else {
    const snap = await firestore().collection('tasks').doc(id).get();
    task = snap.exists ? (snap.data() as TaskRow) : undefined;
  }
  if (!task) return undefined;
  const fresh = await withFreshPhotoUrls(task);
  void cacheTaskSnapshot(fresh.id, fresh as unknown as Record<string, unknown>);
  return fresh;
}

async function allTasks(): Promise<TaskRow[]> {
  let rows: TaskRow[];
  if (useMemory) {
    rows = [...memTasks.values()];
  } else {
    const snap = await firestore().collection('tasks').get();
    rows = snap.docs.map((d) => d.data() as TaskRow);
  }
  return Promise.all(rows.map((t) => withFreshPhotoUrls(t)));
}

function scrubDemoDisplayName(name: string): string {
  return name
    .replace(/\s*\((verified|unverified|care)\)/gi, '')
    .trim();
}

async function ensureDemoHelperPresence() {
  for (const [id, dLat, dLon, cleanName] of [
    ['h1', 0.001, 0.0005, 'Nimal'],
    ['h3', 0.003, -0.001, 'Fathima'],
  ] as const) {
    const u = await loadUser(id);
    if (!u || u.kyc_status !== 'verified') continue;
    if (!(u.presence_available && u.presence_lat != null)) {
      u.is_helper_active = true;
      u.presence_available = true;
      u.presence_lat = 6.9271 + dLat;
      u.presence_lon = 79.8612 + dLon;
      u.presence_at = new Date().toISOString();
    }
    // Drop leftover "(verified)" style suffixes from earlier demo seeds.
    const scrubbed = scrubDemoDisplayName(u.full_name || cleanName);
    if (scrubbed && scrubbed !== u.full_name) {
      u.full_name = scrubbed || cleanName;
    }
    // Demo: Fathima is Neighbor-Vouched (inside-home unlocked); Nimal is not.
    if (id === 'h3') {
      u.vouch_count = Math.max(u.vouch_count ?? 0, VOUCH_THRESHOLD);
      u.neighbor_vouched = true;
      u.home_lat = u.presence_lat;
      u.home_lon = u.presence_lon;
    } else if (id === 'h1' && u.neighbor_vouched == null) {
      u.vouch_count = u.vouch_count ?? 1;
      u.neighbor_vouched = false;
    }
    await saveUser(u);
  }
}

export async function seedDemo() {
  if (useMemory) {
    if (memUsers.size) {
      await ensureDemoHelperPresence();
      return;
    }
  } else {
    const meta = await firestore().collection('meta').doc('seed').get();
    if (meta.exists) {
      await ensureDemoHelperPresence();
      return;
    }
  }

  const demoHelpers: Array<Partial<UserProfile> & { id: string; full_name: string }> = [
    {
      id: 'h1',
      full_name: 'Nimal',
      is_helper_active: true,
      kyc_status: 'verified',
      helper_skills: ['driving'],
      guidelines_accepted_at: new Date().toISOString(),
      wallet_balance: 5000,
    },
    {
      id: 'h2',
      full_name: 'Sajith',
      is_helper_active: false,
      kyc_status: 'unverified',
      helper_skills: [],
      wallet_balance: 0,
    },
    {
      id: 'h3',
      full_name: 'Fathima',
      is_helper_active: true,
      kyc_status: 'verified',
      helper_skills: ['care'],
      guidelines_accepted_at: new Date().toISOString(),
      wallet_balance: 2000,
    },
  ];

  for (const h of demoHelpers) {
    const live = h.is_helper_active === true;
    const isH3 = h.id === 'h3';
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
      // Demo porch lights near Colombo Fort for Instant Dispatch demos.
      presence_available: live,
      presence_lat: live ? 6.9271 + (h.id === 'h1' ? 0.001 : 0.003) : undefined,
      presence_lon: live ? 79.8612 + (h.id === 'h1' ? 0.0005 : -0.001) : undefined,
      presence_at: live ? new Date().toISOString() : undefined,
      home_lat: live ? 6.9271 + (h.id === 'h1' ? 0.001 : 0.003) : undefined,
      home_lon: live ? 79.8612 + (h.id === 'h1' ? 0.0005 : -0.001) : undefined,
      vouch_count: isH3 ? VOUCH_THRESHOLD : 1,
      neighbor_vouched: isH3,
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
  deadline_at?: string;
  difficulty?: string;
  physical_effort?: string;
  bundle_id?: string;
  bundle_title?: string;
  booked_for_user_id?: string;
  booked_for_name?: string;
  /** Skip wallet hold when caller already reserved funds (bundle). */
  skip_escrow?: boolean;
}): Promise<TaskRow> {
  const client = await loadUser(input.client_id);
  if (!client) throw new Error('Client not found');
  if (client.kyc_status !== 'verified') {
    throw new Error('KYC verification required to post tasks');
  }
  const total = input.estimated_hours * input.hourly_rate;
  const hold = total + input.goods_budget;
  if (!input.skip_escrow) {
    if (client.wallet_balance < hold) {
      throw new Error('Insufficient wallet balance for escrow hold');
    }
    client.wallet_balance -= hold;
    client.escrow_balance += hold;
    client.total_tasks_posted += 1;
    await saveUser(client);
  } else {
    client.total_tasks_posted += 1;
    await saveUser(client);
  }

  const id = `task_${Date.now()}_${Math.floor(Math.random() * 900 + 100)}`;
  const confirm = String(Math.floor(1000 + Math.random() * 9000));
  const startOtp = String(Math.floor(1000 + Math.random() * 9000));
  const endOtp = String(Math.floor(1000 + Math.random() * 9000));
  const { buildCompletionChecklist } = await import('./pillars/completion_proof.js');
  const checklist = await buildCompletionChecklist({
    title: input.title,
    description: input.description,
    category: input.category,
    goodsBudget: input.goods_budget,
  });

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
    requires_completion_proof: true,
    completion_checklist: checklist.checklist,
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
    deadline_at: input.deadline_at,
    difficulty: input.difficulty,
    physical_effort: input.physical_effort,
    bundle_id: input.bundle_id,
    bundle_title: input.bundle_title,
    booked_for_user_id: input.booked_for_user_id,
    booked_for_name: input.booked_for_name,
    watcher_ids: [],
  };
  await saveTask(row);
  if (!input.skip_escrow) {
    await addLedger(
      client.id,
      id,
      'escrow_hold',
      -hold,
      client.wallet_balance,
      'Escrow hold',
    );
  }
  return row;
}

/** Checkout several planned tasks as one escrow bundle. */
export async function createTaskBundle(input: {
  client_id: string;
  bundle_title: string;
  lat: number;
  lon: number;
  location_address?: string;
  location_label?: string;
  deadline_at: string;
  booked_for_user_id?: string;
  booked_for_name?: string;
  tasks: Array<{
    title: string;
    description: string;
    category: string;
    estimated_hours: number;
    hourly_rate: number;
    goods_budget: number;
  }>;
}): Promise<{ bundle_id: string; bundle_title: string; tasks: TaskRow[]; total_hold_lkr: number }> {
  if (!input.tasks.length) throw new Error('Select at least one task');
  if (input.tasks.length > 6) throw new Error('Bundle max is 6 tasks');

  const client = await loadUser(input.client_id);
  if (!client) throw new Error('Client not found');
  if (client.kyc_status !== 'verified') {
    throw new Error('KYC verification required to post tasks');
  }

  let totalHold = 0;
  for (const t of input.tasks) {
    totalHold += t.estimated_hours * t.hourly_rate + (t.goods_budget || 0);
  }
  if (client.wallet_balance < totalHold) {
    throw new Error(
      `Insufficient wallet for bundle escrow (need LKR ${Math.round(totalHold)})`,
    );
  }

  client.wallet_balance -= totalHold;
  client.escrow_balance += totalHold;
  await saveUser(client);

  const bundleId = `bundle_${Date.now()}`;
  const created: TaskRow[] = [];
  for (const t of input.tasks) {
    const labor = t.estimated_hours * t.hourly_rate;
    const row = await createTask({
      client_id: input.client_id,
      title: t.title,
      description: t.description,
      category: t.category,
      estimated_hours: t.estimated_hours,
      hourly_rate: t.hourly_rate,
      goods_budget: t.goods_budget || 0,
      lat: input.lat,
      lon: input.lon,
      location_address: input.location_address,
      location_label: input.location_label,
      deadline_at: input.deadline_at,
      bundle_id: bundleId,
      bundle_title: input.bundle_title,
      booked_for_user_id: input.booked_for_user_id,
      booked_for_name: input.booked_for_name,
      skip_escrow: true,
    });
    // Fix total_amount to match quoted labor (createTask recomputes hours*rate).
    row.total_amount = labor;
    await saveTask(row);
    created.push(row);
  }

  await addLedger(
    client.id,
    bundleId,
    'escrow_hold',
    -totalHold,
    client.wallet_balance,
    `Bundle escrow · ${input.bundle_title}`,
  );

  return {
    bundle_id: bundleId,
    bundle_title: input.bundle_title,
    tasks: created,
    total_hold_lkr: Math.round(totalHold),
  };
}

/** Enable Family Assist shared live link for a task the user owns. */
export async function enableTaskShare(
  taskId: string,
  requesterId: string,
): Promise<{ share_token: string; task: TaskRow }> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (task.client_id !== requesterId) {
    throw new Error('Only the booker can share live updates');
  }
  if (!task.share_token) {
    task.share_token = `live_${taskId.replace(/[^a-zA-Z0-9]/g, '').slice(-10)}_${Math.floor(
      Math.random() * 9000 + 1000,
    )}`;
    await saveTask(task);
  }
  return { share_token: task.share_token, task };
}

/** Public (token) live snapshot for family — no OTP secrets. */
export async function getSharedLive(token: string): Promise<{
  title: string;
  status: string;
  status_label: string;
  booked_for_name?: string;
  helper_name?: string;
  bundle_title?: string;
  updated_hint: string;
  share_token: string;
}> {
  const all = await allTasks();
  const task = all.find((t) => t.share_token === token);
  if (!task) throw new Error('Shared link not found or expired');

  const statusLabel: Record<string, string> = {
    open: 'Looking for a helper',
    matched: 'Helper matched — on the way',
    in_progress: 'Helper arrived / job in progress',
    completed: 'Completed',
    cancelled: 'Cancelled',
    disputed: 'Under review',
  };

  let hint = 'We will update this page when status changes.';
  if (task.status === 'matched') {
    hint = 'A helper is coming. Stay available at the location.';
  } else if (task.status === 'in_progress') {
    hint = 'Helper has started. You can ask the booker for the end code when done.';
  } else if (task.status === 'completed') {
    hint = 'Job finished and escrow released.';
  }

  return {
    title: task.title,
    status: task.status,
    status_label: statusLabel[task.status] ?? task.status,
    booked_for_name: task.booked_for_name,
    helper_name: task.helper?.full_name,
    bundle_title: task.bundle_title,
    updated_hint: hint,
    share_token: token,
  };
}

/** Add signed-in family member as watcher (also gets task in /me/watching). */
export async function watchTask(
  taskId: string,
  watcherId: string,
): Promise<TaskRow> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  const watchers = new Set(task.watcher_ids ?? []);
  watchers.add(watcherId);
  task.watcher_ids = [...watchers];
  if (!task.share_token) {
    const enabled = await enableTaskShare(taskId, task.client_id);
    return enabled.task;
  }
  await saveTask(task);
  return task;
}

export async function listWatchingTasks(userId: string): Promise<TaskRow[]> {
  return (await allTasks())
    .filter((t) => (t.watcher_ids ?? []).includes(userId))
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export async function listBundleTasks(bundleId: string): Promise<TaskRow[]> {
  return (await allTasks())
    .filter((t) => t.bundle_id === bundleId)
    .sort((a, b) => a.created_at.localeCompare(b.created_at));
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

export async function listOpenTasks(
  helperLat: number,
  helperLng: number,
  /** When set, hide tasks posted by this user (cannot help on your own job). */
  excludeClientId?: string,
) {
  const ranked = (await allTasks())
    .filter((t) => t.status === 'open')
    .filter((t) => !excludeClientId || t.client_id !== excludeClientId)
    .map((t) => ({
      ...t,
      distance_km: haversineKm(
        { lat: helperLat, lng: helperLng },
        { lat: t.lat, lng: t.lon },
      ),
    }))
    .filter((t) => t.distance_km <= DISPATCH_RADIUS_KM)
    .sort((a, b) => a.distance_km - b.distance_km);

  // Collapse near-identical open jobs (same client + same title) so the feed
  // stays elegant — keep the nearest / newest of each group.
  const seen = new Set<string>();
  const deduped: typeof ranked = [];
  for (const t of ranked) {
    const key = `${t.client_id}::${(t.title ?? '').trim().toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(t);
  }
  return deduped;
}

export async function acceptTask(taskId: string, helperId: string) {
  const task = await loadTask(taskId);
  const helper = await loadUser(helperId);
  if (!task) throw new Error('Task not found');
  if (!helper) throw new Error('Helper not found');
  if (task.client_id === helperId) {
    throw new Error('Cannot accept your own task — switch accounts or wait for another helper');
  }
  if (helper.kyc_status !== 'verified') throw new Error('Helper must be KYC verified');
  // Auto-activate helper mode if they are already verified (UI toggle may lag).
  if (!helper.is_helper_active) {
    helper.is_helper_active = true;
    await saveUser(helper);
  }
  if (task.status !== 'open') throw new Error('Task not open');
  if (task.declined_helper_ids?.includes(helperId)) {
    throw new Error('The client chose someone else for this job');
  }
  const access = accessCardFor(helper);
  task.status = 'matched';
  task.helper_id = helperId;
  task.helper = {
    full_name: helper.full_name,
    avatar_url: helper.avatar_url,
    rating_as_helper: helper.rating_as_helper,
    ...(access ? { access } : {}),
  };
  await saveTask(task);
  try {
    await ensureTaskChat(task.id);
    const helperName = helper.full_name?.trim() || 'A helper';
    await appendSystemChatMessage(
      task.id,
      `${helperName} accepted your job. Open Active Requests and tap “Send Start OTP in chat” when you’re ready — no need to read it aloud.`,
    );
    if (access) {
      await appendSystemChatMessage(
        task.id,
        `${helperName} shared an access note: they work with ${access.abilities.join(', ')} support from Zivo tools${access.note ? ` — “${access.note}”` : ''}. You can keep them, or choose someone else before the job starts (your money stays in escrow).`,
      );
    }
  } catch {
    /* chat is best-effort at match */
  }
  return task;
}


/**
 * Client declines the matched helper before the job starts: task reopens, escrow stays held,
 * that helper cannot re-accept. (Consent point for helpers who disclosed an access note.)
 */
export async function declineMatchedHelper(taskId: string, clientId: string, reason?: string) {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (task.client_id !== clientId) throw new Error('Only the booker can choose another helper');
  if (task.status !== 'matched' || !task.helper_id) {
    throw new Error('You can only choose someone else before the job has started');
  }
  const declined = new Set(task.declined_helper_ids ?? []);
  declined.add(task.helper_id);
  task.declined_helper_ids = [...declined];
  task.status = 'open';
  task.helper_id = undefined;
  task.helper = undefined;
  await saveTask(task);
  try {
    await appendSystemChatMessage(
      task.id,
      `The booker chose to look for someone else${reason ? ` (${reason.slice(0, 80)})` : ''}. The job is open again; your money is still held safely.`,
    );
  } catch {
    /* best-effort */
  }
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
  try {
    await appendSystemChatMessage(
      task.id,
      'Job started. When the work looks good, the client can tap “Send End OTP in chat” from Active Requests to finish and release escrow.',
    );
  } catch {
    /* best-effort */
  }
  return task;
}

/** Helper submits completion proof (photos + checklist). Grocery may also attach receipt verdict. */
export async function submitCompletionProof(input: {
  taskId: string;
  helperId: string;
  checkedItems: string[];
  photoUrls?: string[];
  photoPaths?: string[];
  note?: string;
  receiptTotalLkr?: number;
}): Promise<TaskRow> {
  const task = await loadTask(input.taskId);
  if (!task) throw new Error('Task not found');
  if (task.helper_id !== input.helperId) {
    throw new Error('Only the assigned helper can submit proof');
  }
  if (task.status !== 'in_progress' && task.status !== 'matched') {
    throw new Error('Proof only after the job is matched or in progress');
  }
  const checklist = task.completion_checklist ?? [];
  const checked = input.checkedItems.map((s) => s.trim()).filter(Boolean);
  if (checklist.length > 0 && checked.length === 0) {
    throw new Error('Check at least one completion item');
  }
  task.proof_checked_items = checked;
  task.proof_photo_urls = (input.photoUrls ?? []).slice(0, 3);
  task.proof_photo_paths = (input.photoPaths ?? []).slice(0, 3);
  task.proof_note = input.note?.trim().slice(0, 400) || undefined;
  task.proof_submitted_at = new Date().toISOString();
  if (
    typeof input.receiptTotalLkr === 'number' &&
    Number.isFinite(input.receiptTotalLkr) &&
    input.receiptTotalLkr >= 0
  ) {
    task.goods_spent = Math.min(input.receiptTotalLkr, task.goods_budget);
  }
  await saveTask(task);
  try {
    await appendSystemChatMessage(
      task.id,
      `Completion proof submitted (${checked.length} checklist item(s)${
        task.proof_photo_urls?.length
          ? `, ${task.proof_photo_urls.length} photo(s)`
          : ''
      }). Client can review before End OTP.`,
    );
  } catch {
    /* optional */
  }
  return task;
}

export async function completeTask(
  taskId: string,
  input: { confirm_code: string; receipt_total_lkr: number },
) {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (task.trust_hold) {
    throw new Error(
      `Escrow held by Trust Arbitrator — ${task.trust_hold_reason ?? 'resolve the trust review first'}`,
    );
  }
  if (task.status !== 'in_progress' && task.status !== 'matched') {
    throw new Error(`Cannot complete from status ${task.status}`);
  }
  const needsProof =
    task.requires_completion_proof !== false || task.requires_purchase_proof;
  if (needsProof && !task.proof_submitted_at) {
    throw new Error(
      'Helper must submit completion proof (photos + checklist) before End OTP',
    );
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
  if (!active) {
    u.presence_available = false;
  }
  await saveUser(u);
  return u;
}

/** Helper toggles Available + shares live coords (≤500m dispatch). */
export async function setHelperPresence(
  userId: string,
  input: { available: boolean; lat?: number; lon?: number },
) {
  const u = await loadUser(userId);
  if (!u) throw new Error('User not found');
  if (input.available) {
    if (u.kyc_status !== 'verified') {
      throw new Error('KYC verification required for presence');
    }
    if (!u.is_helper_active) {
      u.is_helper_active = true;
    }
    if (input.lat == null || input.lon == null) {
      throw new Error('lat/lon required when available=true');
    }
    u.presence_available = true;
    u.presence_lat = input.lat;
    u.presence_lon = input.lon;
    u.presence_at = new Date().toISOString();
  } else {
    u.presence_available = false;
    u.presence_at = new Date().toISOString();
  }
  await saveUser(u);
  return u;
}

export type LiveHelper = {
  id: string;
  full_name: string;
  distance_km: number;
  rating_as_helper: number;
  presence_at?: string;
  /** Live porch coordinates for the map (only when presence is on). */
  lat: number;
  lon: number;
};

/** Helpers with porch light ON inside walk radius. */
export async function listLiveHelpersNearby(
  lat: number,
  lon: number,
  radiusKm: number,
): Promise<LiveHelper[]> {
  const r = radiusKm > 0 ? radiusKm : WALK_RADIUS_KM;
  return (await allUsers())
    .filter(
      (u) =>
        u.is_helper_active &&
        u.kyc_status === 'verified' &&
        u.presence_available &&
        u.presence_lat != null &&
        u.presence_lon != null,
    )
    .map((u) => ({
      id: u.id,
      full_name: u.full_name,
      distance_km: haversineKm(
        { lat, lng: lon },
        { lat: u.presence_lat!, lng: u.presence_lon! },
      ),
      rating_as_helper: u.rating_as_helper,
      presence_at: u.presence_at,
      lat: u.presence_lat!,
      lon: u.presence_lon!,
    }))
    .filter((h) => h.distance_km <= r)
    .sort((a, b) => a.distance_km - b.distance_km);
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

async function saveBatch(b: BatchWindow) {
  if (useMemory) {
    memBatches.set(b.id, b);
    return;
  }
  await firestore().collection('batches').doc(b.id).set(b, { merge: true });
}

async function loadBatch(id: string): Promise<BatchWindow | undefined> {
  if (useMemory) return memBatches.get(id);
  const snap = await firestore().collection('batches').doc(id).get();
  return snap.exists ? (snap.data() as BatchWindow) : undefined;
}

async function allBatches(): Promise<BatchWindow[]> {
  if (useMemory) return [...memBatches.values()];
  const snap = await firestore().collection('batches').get();
  return snap.docs.map((d) => d.data() as BatchWindow);
}

export async function getBatch(id: string) {
  return loadBatch(id);
}

/** Open a short same-street piggyback window after Instant Dispatch. */
export async function openBatchWindow(input: {
  anchor_task_id: string;
  helper_id: string;
  helper_name: string;
  lat: number;
  lon: number;
  street_label?: string;
  window_sec: number;
  max_members?: number;
}): Promise<BatchWindow> {
  const now = Date.now();
  const id = `batch_${now}`;
  const win: BatchWindow = {
    id,
    anchor_task_id: input.anchor_task_id,
    helper_id: input.helper_id,
    helper_name: input.helper_name,
    lat: input.lat,
    lon: input.lon,
    street_label: input.street_label ?? 'Your street',
    opened_at: new Date(now).toISOString(),
    expires_at: new Date(now + input.window_sec * 1000).toISOString(),
    status: 'open',
    member_task_ids: [input.anchor_task_id],
    max_members: input.max_members ?? 4,
  };
  await saveBatch(win);

  const anchor = await loadTask(input.anchor_task_id);
  if (anchor) {
    anchor.batch_id = id;
    anchor.batch_anchor = true;
    await saveTask(anchor);
  }
  return win;
}

async function expireStaleBatches(): Promise<void> {
  const now = Date.now();
  for (const b of await allBatches()) {
    if (b.status !== 'open') continue;
    if (new Date(b.expires_at).getTime() <= now) {
      b.status = 'closed';
      await saveBatch(b);
    }
  }
}

export async function listOpenBatchesNearby(
  lat: number,
  lon: number,
  radiusKm: number,
): Promise<Array<BatchWindow & { distance_km: number; seconds_left: number }>> {
  await expireStaleBatches();
  const now = Date.now();
  return (await allBatches())
    .filter((b) => b.status === 'open' && new Date(b.expires_at).getTime() > now)
    .map((b) => ({
      ...b,
      distance_km: haversineKm({ lat, lng: lon }, { lat: b.lat, lng: b.lon }),
      seconds_left: Math.max(
        0,
        Math.round((new Date(b.expires_at).getTime() - now) / 1000),
      ),
    }))
    .filter((b) => b.distance_km <= radiusKm)
    .sort((a, b) => a.distance_km - b.distance_km);
}

const DEMO_BATCH_ID = 'batch_demo_colombo';
const DEMO_BATCH_WINDOW_SEC = 600;

/**
 * Keep a joinable street-batch window near the caller for Cup demos when
 * nobody has Instant-Dispatched recently (otherwise home looks empty).
 */
export async function ensureDemoStreetBatch(
  lat: number,
  lon: number,
): Promise<BatchWindow> {
  const now = Date.now();
  const existing = await loadBatch(DEMO_BATCH_ID);
  const helper =
    (await loadUser('h1')) ??
    (await loadUser('h3')) ??
    (await listLiveHelpersNearby(lat, lon, 5))[0];
  const helperId = helper?.id ?? 'h1';
  const helperName =
    (helper?.full_name || 'Nimal').replace(/\s*\((verified|unverified|care)\)/gi, '').trim() ||
    'Nimal';

  if (
    existing &&
    existing.status === 'open' &&
    new Date(existing.expires_at).getTime() > now + 30_000
  ) {
    // Keep pin near the querying client so radius filter always hits.
    existing.lat = lat;
    existing.lon = lon;
    existing.helper_id = helperId;
    existing.helper_name = helperName;
    await saveBatch(existing);
    return existing;
  }

  const win: BatchWindow = {
    id: DEMO_BATCH_ID,
    anchor_task_id: existing?.anchor_task_id ?? `demo_anchor_${DEMO_BATCH_ID}`,
    helper_id: helperId,
    helper_name: helperName,
    lat,
    lon,
    street_label: 'Your block · demo piggyback',
    opened_at: new Date(now).toISOString(),
    expires_at: new Date(now + DEMO_BATCH_WINDOW_SEC * 1000).toISOString(),
    status: 'open',
    member_task_ids: existing?.member_task_ids?.length
      ? existing.member_task_ids
      : [`demo_anchor_${DEMO_BATCH_ID}`],
    max_members: 4,
  };
  await saveBatch(win);
  return win;
}

/** Client or helper freezes escrow and marks the job disputed. */
export async function openTaskDispute(input: {
  taskId: string;
  userId: string;
  reason: string;
}): Promise<TaskRow> {
  const task = await loadTask(input.taskId);
  if (!task) throw new Error('Task not found');
  if (task.client_id !== input.userId && task.helper_id !== input.userId) {
    throw new Error('Only the client or helper can open a dispute');
  }
  if (task.status === 'completed' || task.status === 'cancelled') {
    throw new Error('Cannot dispute a finished job');
  }
  if (task.status === 'disputed') {
    return task;
  }
  const reason = input.reason.trim().slice(0, 500);
  if (reason.length < 8) {
    throw new Error('Please describe the issue (at least 8 characters)');
  }
  task.status = 'disputed';
  task.disputed_at = new Date().toISOString();
  task.dispute_reason = reason;
  task.trust_hold = true;
  task.trust_hold_reason = reason;
  await saveTask(task);
  try {
    await appendSystemChatMessage(
      task.id,
      `Dispute opened — escrow frozen. ${reason}`,
    );
  } catch {
    /* chat optional */
  }
  return task;
}

export async function appendBatchMember(
  batchId: string,
  taskId: string,
): Promise<BatchWindow> {
  const b = await loadBatch(batchId);
  if (!b) throw new Error('Batch not found');
  if (b.status !== 'open') throw new Error('Batch window closed');
  if (new Date(b.expires_at).getTime() <= Date.now()) {
    b.status = 'closed';
    await saveBatch(b);
    throw new Error('Batch window expired');
  }
  if (b.member_task_ids.length >= b.max_members) {
    throw new Error('Street batch is full');
  }
  if (!b.member_task_ids.includes(taskId)) {
    b.member_task_ids.push(taskId);
  }
  if (b.member_task_ids.length >= b.max_members) {
    b.status = 'closed';
  }
  await saveBatch(b);
  return b;
}

export async function patchTask(
  taskId: string,
  patch: Partial<TaskRow>,
): Promise<TaskRow> {
  const t = await loadTask(taskId);
  if (!t) throw new Error('Task not found');
  Object.assign(t, patch);
  await saveTask(t);
  return t;
}

/** Client cancels before End OTP — refunds escrow hold to wallet. */
export async function cancelClientTask(
  taskId: string,
  clientId: string,
  reason?: string,
): Promise<TaskRow> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (task.client_id !== clientId) {
    throw new Error('Only the task owner can cancel');
  }
  if (task.status === 'completed' || task.status === 'cancelled') {
    throw new Error('Task is already finished');
  }
  if (task.status === 'in_progress' && task.proof_submitted_at) {
    throw new Error(
      'Proof already submitted — use Dispute or finish with End OTP',
    );
  }
  const hold = (task.total_amount ?? 0) + (task.goods_budget ?? 0);
  const client = await loadUser(clientId);
  if (client && hold > 0) {
    client.escrow_balance = Math.max(0, (client.escrow_balance ?? 0) - hold);
    client.wallet_balance = (client.wallet_balance ?? 0) + hold;
    await saveUser(client);
  }
  task.status = 'cancelled';
  if (reason?.trim()) task.dispute_reason = reason.trim().slice(0, 400);
  await saveTask(task);
  return task;
}

/** Client edits title/description while still open (before Start OTP). */
export async function editClientTask(
  taskId: string,
  clientId: string,
  input: { title?: string; description?: string },
): Promise<TaskRow> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (task.client_id !== clientId) {
    throw new Error('Only the task owner can edit');
  }
  if (task.status !== 'open' && task.status !== 'matched') {
    throw new Error('Can only edit before the job starts');
  }
  if (input.title?.trim()) task.title = input.title.trim().slice(0, 120);
  if (input.description?.trim()) {
    task.description = input.description.trim().slice(0, 2000);
  }
  await saveTask(task);
  return task;
}

export async function listHelperBatchRoute(helperId: string) {
  await expireStaleBatches();
  const tasks = await listHelperActiveTasks(helperId);
  const batchIds = [
    ...new Set(tasks.map((t) => t.batch_id).filter(Boolean) as string[]),
  ];
  const batches = (
    await Promise.all(batchIds.map((id) => loadBatch(id)))
  ).filter(Boolean) as BatchWindow[];
  return {
    active_tasks: tasks.filter((t) => t.batch_id),
    batches,
  };
}

async function saveVouch(v: VouchRow) {
  if (useMemory) {
    memVouches.set(v.id, v);
    return;
  }
  await firestore().collection('vouches').doc(v.id).set(v, { merge: true });
}

async function allVouches(): Promise<VouchRow[]> {
  if (useMemory) return [...memVouches.values()];
  const snap = await firestore().collection('vouches').get();
  return snap.docs.map((d) => d.data() as VouchRow);
}

export async function listVouchesForHelper(helperId: string) {
  return (await allVouches())
    .filter((v) => v.helper_id === helperId && v.status === 'active')
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

async function refreshHelperVouchBadge(helperId: string) {
  const helper = await loadUser(helperId);
  if (!helper) return;
  const count = (await listVouchesForHelper(helperId)).length;
  helper.vouch_count = count;
  helper.neighbor_vouched = count >= VOUCH_THRESHOLD;
  await saveUser(helper);
  return helper;
}

/** Neighbor stakes LKR to vouch a helper on their block. */
export async function createNeighborVouch(input: {
  voucherId: string;
  helperId: string;
  note?: string;
  voucherLat?: number;
  voucherLon?: number;
}): Promise<{ vouch: VouchRow; helper: UserProfile }> {
  if (input.voucherId === input.helperId) {
    throw new Error('Cannot vouch for yourself');
  }
  const voucher = await loadUser(input.voucherId);
  const helper = await loadUser(input.helperId);
  if (!voucher || !helper) throw new Error('User not found');
  if (voucher.kyc_status !== 'verified') {
    throw new Error('Only verified neighbors can vouch');
  }
  if (!helper.is_helper_active || helper.kyc_status !== 'verified') {
    throw new Error('Can only vouch verified active helpers');
  }

  const existing = (await listVouchesForHelper(input.helperId)).find(
    (v) => v.voucher_id === input.voucherId,
  );
  if (existing) throw new Error('You already vouched for this helper');

  const hLat = helper.presence_lat ?? helper.home_lat ?? 6.9271;
  const hLon = helper.presence_lon ?? helper.home_lon ?? 79.8612;
  const vLat = input.voucherLat ?? voucher.home_lat ?? voucher.presence_lat;
  const vLon = input.voucherLon ?? voucher.home_lon ?? voucher.presence_lon;
  if (vLat == null || vLon == null) {
    throw new Error('Share your location to vouch a neighbor');
  }
  const dist = haversineKm(
    { lat: vLat, lng: vLon },
    { lat: hLat, lng: hLon },
  );
  if (dist > WALK_RADIUS_KM) {
    throw new Error(
      `Voucher must live/be within ${WALK_RADIUS_KM} km of the helper (same walk bubble)`,
    );
  }

  const stake = VOUCH_STAKE_LKR;
  if (voucher.wallet_balance < stake) {
    throw new Error(`Need LKR ${stake} stake in wallet to vouch`);
  }
  voucher.wallet_balance -= stake;
  voucher.escrow_balance += stake;
  await saveUser(voucher);

  const vouch: VouchRow = {
    id: `vouch_${Date.now()}`,
    helper_id: input.helperId,
    voucher_id: input.voucherId,
    voucher_name: voucher.full_name,
    stake_lkr: stake,
    note: input.note,
    created_at: new Date().toISOString(),
    status: 'active',
  };
  await saveVouch(vouch);
  await addLedger(
    voucher.id,
    undefined,
    'vouch_stake',
    -stake,
    voucher.wallet_balance,
    `Neighbor vouch stake for ${helper.full_name}`,
  );

  const updated = (await refreshHelperVouchBadge(input.helperId))!;
  return { vouch, helper: updated };
}

export async function getHelperTrustCard(helperId: string) {
  const helper = await loadUser(helperId);
  if (!helper) throw new Error('Helper not found');
  const vouches = await listVouchesForHelper(helperId);
  const count = Math.max(helper.vouch_count ?? 0, vouches.length);
  const badged =
    !!helper.neighbor_vouched || count >= VOUCH_THRESHOLD;
  return {
    helper_id: helperId,
    full_name: helper.full_name,
    vouch_count: count,
    vouch_threshold: VOUCH_THRESHOLD,
    neighbor_vouched: badged,
    unlocks: 'inside_home',
    vouches: vouches.map((v) => ({
      id: v.id,
      voucher_name: v.voucher_name,
      stake_lkr: v.stake_lkr,
      created_at: v.created_at,
      note: v.note,
    })),
  };
}

/** Categories that require Neighbor-Vouched badge. */
export const INSIDE_HOME_CATEGORIES = new Set([
  'homeCleaning',
  'homeCooking',
  'babysitting',
  'elderCare',
  'laundry',
]);

export function requiresNeighborVouch(category?: string) {
  return !!category && INSIDE_HOME_CATEGORIES.has(category);
}

/** Deterministic demo offsets so nearest ≠ best under dispute constraints. */
const HELPER_GEO_OFFSET: Record<string, { dLat: number; dLng: number }> = {
  h1: { dLat: 0.0018, dLng: 0.0004 }, // ~0.2 km — nearest
  h3: { dLat: 0.012, dLng: -0.004 }, // ~1.4 km — farther, clean history
};

/** Live dispute rows for match tools (not invented by the model). */
export async function listDisputesForHelper(helperId: string): Promise<
  Array<{ id: string; reason: string; status: string; daysAgo: number }>
> {
  const tasks = useMemory
    ? [...memTasks.values()]
    : (await firestore().collection('tasks').get()).docs.map((d) => d.data() as TaskRow);
  const now = Date.now();
  return tasks
    .filter(
      (t) =>
        t.helper_id === helperId &&
        (t.status === 'disputed' || Boolean((t as TaskRow & { disputed_at?: string }).disputed_at)),
    )
    .map((t) => {
      const row = t as TaskRow & {
        disputed_at?: string;
        dispute_reason?: string;
        trust_hold_reason?: string;
      };
      const at = Date.parse(row.disputed_at ?? t.created_at);
      const daysAgo = Number.isFinite(at)
        ? Math.max(0, Math.round((now - at) / 86_400_000))
        : 0;
      return {
        id: t.id,
        reason: (row.dispute_reason ?? row.trust_hold_reason ?? 'Dispute').slice(0, 160),
        status: t.status === 'disputed' ? 'open' : 'resolved',
        daysAgo,
      };
    });
}

/** Deterministic trust tier from vouches / rating / jobs — never from ability. */
export function computeTrustTier(
  helper: UserProfile,
): 'gold' | 'silver' | 'bronze' {
  const vouches = helper.vouch_count ?? 0;
  const rating = helper.rating_as_helper ?? 0;
  const helped = helper.total_tasks_helped ?? 0;
  if (
    helper.neighbor_vouched ||
    (vouches >= VOUCH_THRESHOLD && rating >= 4.6 && helped >= 3)
  ) {
    return 'gold';
  }
  if (rating < 3.8 || (helped === 0 && vouches === 0)) {
    return 'bronze';
  }
  return 'silver';
}

export async function helpersForMatch(task: TaskRow) {
  return (await allUsers())
    .filter(
      (u) =>
        u.id !== task.client_id &&
        u.is_helper_active &&
        u.kyc_status === 'verified',
    )
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

/** Attach client-readable match explanation onto a task (best-effort). */
export async function attachMatchExplanation(
  task: TaskRow,
  opts: {
    explanation: string;
    reasons?: string[];
    mode?: TaskRow['match_mode'];
  },
): Promise<TaskRow> {
  // Never persist Vertex / HTTP error dumps for client UI.
  let explanation = opts.explanation.slice(0, 1200);
  const leak = explanation.search(
    /Gemini tools unavailable|VertexAI\.|RESOURCE_EXHAUSTED|"error":\s*\{/i,
  );
  if (leak >= 0) explanation = explanation.slice(0, leak).trim();
  if (!explanation) {
    explanation = 'Matched using skills, distance, availability and trust.';
  }
  task.match_explanation = explanation;
  if (opts.reasons?.length) task.match_reasons = opts.reasons.slice(0, 8);
  if (opts.mode) task.match_mode = opts.mode;
  await saveTask(task);
  return task;
}

function assertChatParticipant(task: TaskRow, userId: string): 'client' | 'helper' {
  if (task.client_id === userId) return 'client';
  if (task.helper_id === userId) return 'helper';
  throw new Error('Only the client and assigned helper can use this chat');
}

/** Keep coordination on-platform — redact phone numbers / off-app contact. */
function sanitizeChatBody(raw: string): string {
  // Soft cleanup only — phones/apps are hard-blocked earlier by guardChatMessage.
  return raw.trim().slice(0, 2000);
}

async function saveChatThread(t: ChatThread) {
  if (useMemory) {
    memChatThreads.set(t.task_id, t);
    return;
  }
  await firestore().collection('chats').doc(t.task_id).set(t, { merge: true });
}

async function loadChatThread(taskId: string): Promise<ChatThread | null> {
  if (useMemory) return memChatThreads.get(taskId) ?? null;
  const snap = await firestore().collection('chats').doc(taskId).get();
  return snap.exists ? (snap.data() as ChatThread) : null;
}

/** Open (or return) the task chat once a helper is assigned. */
export async function ensureTaskChat(taskId: string): Promise<ChatThread> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  if (!task.helper_id) {
    throw new Error('Chat opens after a helper is matched');
  }
  const existing = await loadChatThread(taskId);
  if (existing) return existing;

  const now = new Date().toISOString();
  const thread: ChatThread = {
    task_id: taskId,
    client_id: task.client_id,
    helper_id: task.helper_id,
    created_at: now,
    message_count: 0,
  };
  await saveChatThread(thread);

  const welcome: ChatMessage = {
    id: `msg_${Date.now()}_sys`,
    task_id: taskId,
    sender_id: 'system',
    sender_role: 'system',
    body:
      'In-app chat only — every message is safety-checked and saved as evidence. Don’t share phone numbers or move off Zivo.',
    created_at: now,
  };
  if (useMemory) {
    memChatMessages.set(taskId, [welcome]);
  } else {
    await firestore()
      .collection('chats')
      .doc(taskId)
      .collection('messages')
      .doc(welcome.id)
      .set(welcome);
  }
  thread.message_count = 1;
  thread.last_message_at = now;
  thread.last_preview = welcome.body.slice(0, 120);
  await saveChatThread(thread);
  return thread;
}

/** Internal read for Trust Arbitrator (no auth — caller must authorize). */
export async function listChatMessagesInternal(
  taskId: string,
): Promise<ChatMessage[]> {
  if (useMemory) return [...(memChatMessages.get(taskId) ?? [])];
  const snap = await firestore()
    .collection('chats')
    .doc(taskId)
    .collection('messages')
    .orderBy('created_at', 'asc')
    .limit(200)
    .get();
  return snap.docs.map((d) => d.data() as ChatMessage);
}

function chatUnreadFor(thread: ChatThread, messages: ChatMessage[], userId: string): number {
  const isClient = thread.client_id === userId;
  const cursor = isClient ? thread.client_last_read_at : thread.helper_last_read_at;
  return messages.filter((m) => {
    if (m.sender_id === userId) return false;
    if (!cursor) return true;
    return m.created_at > cursor;
  }).length;
}

export async function listTaskChat(
  taskId: string,
  userId: string,
  afterIso?: string,
  lang: 'en' | 'si' | 'ta' = 'en',
): Promise<{
  thread: ChatThread;
  messages: ChatMessage[];
  unread_count: number;
}> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  assertChatParticipant(task, userId);
  const thread = await ensureTaskChat(taskId);

  let messages = await listChatMessagesInternal(taskId);
  const unread_count = chatUnreadFor(thread, messages, userId);
  if (afterIso) {
    messages = messages.filter((m) => m.created_at > afterIso);
  }

  messages = messages.map((m) => {
    const original = (m.body_original ?? m.body)?.toString() ?? '';
    const translated = m.translations?.[lang]?.trim();
    const hasAlt =
      Boolean(translated) &&
      Boolean(m.source_lang) &&
      m.source_lang !== lang &&
      translated !== original;
    // Always show the sender's original language first; tap reveals translation.
    return {
      ...m,
      body: original || m.body,
      body_original: original || m.body_original,
      display_body: original || translated || m.body,
      translation_body: hasAlt ? translated : undefined,
      translated: hasAlt,
    };
  });

  return { thread, messages, unread_count };
}

/** Mark the thread read for this participant (clears WhatsApp-style badge). */
export async function markTaskChatRead(
  taskId: string,
  userId: string,
): Promise<{ unread_count: number }> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  assertChatParticipant(task, userId);
  const thread = await ensureTaskChat(taskId);
  const now = new Date().toISOString();
  if (thread.client_id === userId) {
    thread.client_last_read_at = now;
  } else {
    thread.helper_last_read_at = now;
  }
  await saveChatThread(thread);
  return { unread_count: 0 };
}

/** Lightweight unread count for badge polling (client + helper). */
export async function getTaskChatUnread(
  taskId: string,
  userId: string,
): Promise<{ unread_count: number }> {
  const task = await loadTask(taskId);
  if (!task) throw new Error('Task not found');
  assertChatParticipant(task, userId);
  const thread = await ensureTaskChat(taskId);
  const messages = await listChatMessagesInternal(taskId);
  return { unread_count: chatUnreadFor(thread, messages, userId) };
}

export async function appendSystemChatMessage(
  taskId: string,
  body: string,
): Promise<ChatMessage> {
  await ensureTaskChat(taskId);
  const now = new Date().toISOString();
  const msg: ChatMessage = {
    id: `msg_${Date.now()}_sys`,
    task_id: taskId,
    sender_id: 'system',
    sender_role: 'system',
    body: body.slice(0, 2000),
    created_at: now,
  };
  if (useMemory) {
    const list = memChatMessages.get(taskId) ?? [];
    list.push(msg);
    memChatMessages.set(taskId, list);
  } else {
    await firestore()
      .collection('chats')
      .doc(taskId)
      .collection('messages')
      .doc(msg.id)
      .set(msg);
  }
  const thread = (await loadChatThread(taskId))!;
  thread.last_message_at = now;
  thread.last_preview = body.slice(0, 120);
  thread.message_count = (thread.message_count ?? 0) + 1;
  await saveChatThread(thread);
  return msg;
}

export async function sendTaskChatMessage(input: {
  taskId: string;
  senderId: string;
  body: string;
  body_original?: string;
  source_lang?: 'en' | 'si' | 'ta';
  translations?: Partial<Record<'en' | 'si' | 'ta', string>>;
  via_voice?: boolean;
}): Promise<ChatMessage> {
  const task = await loadTask(input.taskId);
  if (!task) throw new Error('Task not found');
  const role = assertChatParticipant(task, input.senderId);
  if (!['matched', 'in_progress'].includes(task.status)) {
    throw new Error('Chat is closed for this job');
  }
  const body = sanitizeChatBody(input.body);
  if (!body) throw new Error('Message cannot be empty');

  await ensureTaskChat(input.taskId);
  const now = new Date().toISOString();
  const msg: ChatMessage = {
    id: `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    task_id: input.taskId,
    sender_id: input.senderId,
    sender_role: role,
    body: input.body_original?.trim() || body,
    body_original: input.body_original?.trim() || body,
    ...(input.source_lang ? { source_lang: input.source_lang } : {}),
    ...(input.translations ? { translations: input.translations } : {}),
    ...(input.via_voice ? { via_voice: true } : {}),
    created_at: now,
  };

  if (useMemory) {
    const list = memChatMessages.get(input.taskId) ?? [];
    list.push(msg);
    memChatMessages.set(input.taskId, list);
  } else {
    await firestore()
      .collection('chats')
      .doc(input.taskId)
      .collection('messages')
      .doc(msg.id)
      .set(msg);
  }

  const thread = (await loadChatThread(input.taskId))!;
  thread.last_message_at = now;
  thread.last_preview = body.slice(0, 120);
  thread.message_count = (thread.message_count ?? 0) + 1;
  await saveChatThread(thread);
  return msg;
}

export async function saveTrustReview(
  review: TrustReview,
  opts: { applyHold: boolean; escalate: boolean; reason: string },
): Promise<void> {
  if (useMemory) {
    const list = memTrustReviews.get(review.task_id) ?? [];
    list.push(review);
    memTrustReviews.set(review.task_id, list);
  } else {
    await firestore()
      .collection('trust_reviews')
      .doc(review.id)
      .set(review);
    await firestore()
      .collection('tasks')
      .doc(review.task_id)
      .collection('trust_reviews')
      .doc(review.id)
      .set(review);
  }

  const task = await loadTask(review.task_id);
  if (!task) return;
  task.last_trust_review_id = review.id;
  if (opts.applyHold) {
    task.trust_hold = true;
    task.trust_hold_reason = opts.reason.slice(0, 400);
  } else if (review.verdict === 'continue') {
    task.trust_hold = false;
    task.trust_hold_reason = undefined;
  }
  if (opts.escalate) {
    task.status = 'disputed';
  }
  await saveTask(task);

  const label =
    review.verdict === 'continue'
      ? 'Trust review: continue'
      : review.verdict === 'hold_escrow'
        ? 'Trust review: escrow held'
        : 'Trust review: escalated';
  try {
    await appendSystemChatMessage(
      review.task_id,
      `${label} — ${review.summary}`,
    );
  } catch {
    /* chat may not exist yet */
  }
}

export async function listTrustReviews(taskId: string): Promise<TrustReview[]> {
  if (useMemory) {
    return [...(memTrustReviews.get(taskId) ?? [])].sort((a, b) =>
      b.created_at.localeCompare(a.created_at),
    );
  }
  const snap = await firestore()
    .collection('tasks')
    .doc(taskId)
    .collection('trust_reviews')
    .orderBy('created_at', 'desc')
    .limit(20)
    .get();
  return snap.docs.map((d) => d.data() as TrustReview);
}

export { haversineKm, DISPATCH_RADIUS_KM, PLATFORM_FEE_PERCENT };
