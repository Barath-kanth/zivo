import { randomUUID } from 'crypto';
import { DISPATCH_RADIUS_KM, PLATFORM_FEE_PERCENT } from './config.js';

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

const users = new Map<string, UserProfile>();
const tasks = new Map<string, TaskRow>();
const ledger: LedgerEntry[] = [];
const sessions = new Map<string, Session>();
const otps = new Map<string, OtpRecord>();

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

export function seedDemo() {
  if (users.size) return;
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
    users.set(h.id, {
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
}

export function createSession(userId: string): string {
  const token = randomUUID();
  sessions.set(token, {
    token,
    userId,
    expiresAt: Date.now() + 7 * 24 * 3600_000,
  });
  return token;
}

export function userIdFromAuthHeader(header?: string): string | null {
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice(7);
  const s = sessions.get(token);
  if (!s || s.expiresAt < Date.now()) return null;
  return s.userId;
}

export function getUser(id: string) {
  return users.get(id);
}

export function listUsers() {
  return [...users.values()].map((u) => {
    const { password_hash: _, ...rest } = u;
    return rest;
  });
}

export function upsertUser(profile: UserProfile) {
  users.set(profile.id, profile);
  const { password_hash: _, ...rest } = profile;
  return rest;
}

export function publicProfile(u: UserProfile) {
  const { password_hash: _, ...rest } = u;
  return rest;
}

export function issuePhoneOtp(phone: string): string {
  const code = String(Math.floor(100000 + Math.random() * 900000));
  otps.set(phone, { code, phone, expiresAt: Date.now() + 10 * 60_000 });
  return code;
}

export function verifyPhoneOtp(phone: string, token: string): UserProfile {
  const rec = otps.get(phone);
  if (!rec || rec.expiresAt < Date.now() || rec.code !== token) {
    throw new Error('Invalid or expired OTP');
  }
  otps.delete(phone);
  let user = [...users.values()].find((u) => u.phone === phone);
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
    users.set(id, user);
  } else {
    user.phone_verified_at = new Date().toISOString();
    users.set(user.id, user);
  }
  return user;
}

export function signUpEmail(input: {
  email: string;
  password: string;
  full_name: string;
}): UserProfile {
  const existing = [...users.values()].find((u) => u.email === input.email);
  if (existing) throw new Error('Email already registered');
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
  users.set(id, user);
  return user;
}

export function signInEmail(email: string, password: string): UserProfile {
  const user = [...users.values()].find((u) => u.email === email);
  if (!user || user.password_hash !== password) {
    throw new Error('Invalid email or password');
  }
  return user;
}

export function createTask(input: {
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
}): TaskRow {
  const client = users.get(input.client_id);
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
  users.set(client.id, client);

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
  };
  tasks.set(id, row);
  addLedger(client.id, id, 'escrow_hold', -hold, client.wallet_balance, 'Escrow hold');
  return row;
}

export function getTask(id: string) {
  return tasks.get(id);
}

export function listClientTasks(clientId: string) {
  return [...tasks.values()]
    .filter((t) => t.client_id === clientId)
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export function listOpenTasks(helperLat: number, helperLng: number) {
  return [...tasks.values()]
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

export function acceptTask(taskId: string, helperId: string) {
  const task = tasks.get(taskId);
  const helper = users.get(helperId);
  if (!task) throw new Error('Task not found');
  if (!helper) throw new Error('Helper not found');
  if (helper.kyc_status !== 'verified') throw new Error('Helper must be KYC verified');
  if (!helper.is_helper_active) throw new Error('Activate helper mode first');
  if (task.status !== 'open') throw new Error('Task not open');
  task.status = 'matched';
  task.helper_id = helperId;
  task.helper = {
    full_name: helper.full_name,
    avatar_url: helper.avatar_url,
    rating_as_helper: helper.rating_as_helper,
  };
  tasks.set(taskId, task);
  return task;
}

export function completeTask(
  taskId: string,
  input: { confirm_code: string; receipt_total_lkr: number },
) {
  const task = tasks.get(taskId);
  if (!task) throw new Error('Task not found');
  if (input.confirm_code !== task.confirm_code && input.confirm_code !== task.end_otp) {
    throw new Error('Invalid confirm / End OTP');
  }
  const client = users.get(task.client_id);
  if (!client) throw new Error('Client missing');
  const labor = task.total_amount;
  const goods = Math.min(input.receipt_total_lkr, task.goods_budget);
  const unused = task.goods_budget - goods;
  const fee = (labor * PLATFORM_FEE_PERCENT) / 100;
  const helperPay = labor - fee;

  client.escrow_balance -= labor + task.goods_budget;
  client.wallet_balance += unused;
  users.set(client.id, client);

  if (task.helper_id) {
    const helper = users.get(task.helper_id);
    if (helper) {
      helper.wallet_balance += helperPay + goods;
      helper.helper_earnings += helperPay + goods;
      helper.total_tasks_helped += 1;
      users.set(helper.id, helper);
      addLedger(helper.id, taskId, 'release', helperPay + goods, helper.wallet_balance, 'Escrow release');
    }
  }
  addLedger(client.id, taskId, 'release', unused, client.wallet_balance, 'Unused goods returned');
  task.status = 'completed';
  tasks.set(taskId, task);
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

export function topUp(userId: string, amount: number) {
  const u = users.get(userId);
  if (!u) throw new Error('User not found');
  u.wallet_balance += amount;
  users.set(userId, u);
  addLedger(userId, undefined, 'topup', amount, u.wallet_balance, 'Wallet top-up (GCP demo)');
  return u;
}

export function setHelperActive(userId: string, active: boolean) {
  const u = users.get(userId);
  if (!u) throw new Error('User not found');
  if (active && u.kyc_status !== 'verified') {
    throw new Error('KYC verification required for helper mode');
  }
  if (active && !u.guidelines_accepted_at) {
    u.guidelines_accepted_at = new Date().toISOString();
  }
  u.is_helper_active = active;
  users.set(userId, u);
  return u;
}

function addLedger(
  userId: string,
  taskId: string | undefined,
  entryType: string,
  amount: number,
  balanceAfter: number,
  description: string,
) {
  ledger.push({
    id: randomUUID(),
    user_id: userId,
    task_id: taskId,
    entry_type: entryType,
    amount,
    balance_after: balanceAfter,
    description,
    created_at: new Date().toISOString(),
  });
}

export function listLedger(userId: string) {
  return ledger
    .filter((e) => e.user_id === userId)
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export function helpersForMatch(task: TaskRow) {
  return [...users.values()]
    .filter((u) => u.is_helper_active && u.kyc_status === 'verified')
    .map((u) => ({
      helper: u,
      distanceKm: haversineKm(
        { lat: task.lat, lng: task.lon },
        { lat: 6.9271, lng: 79.8612 },
      ),
    }))
    .filter((x) => x.distanceKm <= DISPATCH_RADIUS_KM);
}

export { haversineKm, DISPATCH_RADIUS_KM, PLATFORM_FEE_PERCENT };
