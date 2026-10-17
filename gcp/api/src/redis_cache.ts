/**
 * Hot-path task cache for near-instant client reads after helper writes
 * (e.g. completion proof). Uses in-process memory always, plus Redis when
 * REDIS_URL is set (Memorystore / Upstash / any Redis 6+).
 */
import { createClient, type RedisClientType } from 'redis';

type CacheEntry = { payload: string; at: number };

const mem = new Map<string, CacheEntry>();
const MEM_TTL_MS = 45_000;
const REDIS_TTL_SEC = 60;

let redis: RedisClientType | null = null;
let redisTried = false;

async function ensureRedis(): Promise<RedisClientType | null> {
  if (redisTried) return redis;
  redisTried = true;
  const url = process.env.REDIS_URL?.trim();
  if (!url) return null;
  try {
    const client = createClient({ url });
    client.on('error', () => {
      /* avoid unhandled; fall back to memory */
    });
    await client.connect();
    redis = client as RedisClientType;
    console.log('[cache] Redis connected');
    return redis;
  } catch (e) {
    console.warn('[cache] Redis unavailable, using memory only:', e);
    redis = null;
    return null;
  }
}

function key(taskId: string) {
  return `zivo:task:${taskId}`;
}

export async function cacheTaskSnapshot(
  taskId: string,
  task: Record<string, unknown>,
): Promise<void> {
  const payload = JSON.stringify(task);
  mem.set(taskId, { payload, at: Date.now() });
  const client = await ensureRedis();
  if (!client) return;
  try {
    await client.setEx(key(taskId), REDIS_TTL_SEC, payload);
    await client.publish(`zivo:task-events:${taskId}`, 'updated');
  } catch {
    /* memory still valid */
  }
}

export async function readCachedTaskSnapshot(
  taskId: string,
): Promise<Record<string, unknown> | null> {
  const local = mem.get(taskId);
  if (local && Date.now() - local.at < MEM_TTL_MS) {
    try {
      return JSON.parse(local.payload) as Record<string, unknown>;
    } catch {
      mem.delete(taskId);
    }
  }
  const client = await ensureRedis();
  if (!client) return null;
  try {
    const raw = await client.get(key(taskId));
    if (!raw) return null;
    mem.set(taskId, { payload: raw, at: Date.now() });
    return JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export async function invalidateTaskSnapshot(taskId: string): Promise<void> {
  mem.delete(taskId);
  const client = await ensureRedis();
  if (!client) return;
  try {
    await client.del(key(taskId));
  } catch {
    /* ignore */
  }
}

export function cacheStats() {
  return {
    memoryEntries: mem.size,
    redis: Boolean(redis),
    redisUrlConfigured: Boolean(process.env.REDIS_URL?.trim()),
  };
}
