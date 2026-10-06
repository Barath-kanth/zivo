export const PLATFORM_FEE_PERCENT = 10;
export const DISPATCH_RADIUS_KM = Number(process.env.DISPATCH_RADIUS_KM ?? '80');
/** Walkable instant-dispatch radius (Hyper-Local Micro-Utility). */
export const WALK_RADIUS_KM = Number(process.env.WALK_RADIUS_KM ?? '0.5');
/** Same-street piggyback radius after a helper is on-block. */
export const BATCH_RADIUS_KM = Number(process.env.BATCH_RADIUS_KM ?? '0.15');
/** Seconds neighbors can join a street batch after anchor dispatch. */
export const BATCH_WINDOW_SEC = Number(process.env.BATCH_WINDOW_SEC ?? '180');
/** Discount vs solo micro-price when piggybacking (0.3 = 30% off). */
export const BATCH_DISCOUNT = Number(process.env.BATCH_DISCOUNT ?? '0.3');
/** Neighbor vouches required to unlock inside-home tasks. */
export const VOUCH_THRESHOLD = Number(process.env.VOUCH_THRESHOLD ?? '3');
/** Soft stake deducted from voucher wallet when they vouch (demo LKR). */
export const VOUCH_STAKE_LKR = Number(process.env.VOUCH_STAKE_LKR ?? '200');
/**
 * Sri Lanka micro-task inflation index vs 2024 baseline (1.0 = no uplift).
 * Tune via env — protects helper real wages; clients cannot undercut.
 */
export const INFLATION_INDEX = Number(process.env.INFLATION_INDEX ?? '1.12');
/** LKR paid per km of helper travel (pickup → destination). */
export const TRAVEL_LKR_PER_KM = Number(process.env.TRAVEL_LKR_PER_KM ?? '80');
/** Minimum description length for a priced task. */
export const MIN_DESCRIPTION_CHARS = Number(process.env.MIN_DESCRIPTION_CHARS ?? '20');
export const CURRENCY = 'LKR';
export const MARKET = 'Sri Lanka';

export const gcpProjectId = process.env.GCP_PROJECT_ID ?? '';
export const gcpLocation = process.env.GCP_LOCATION ?? 'asia-south1';
export const geminiModel =
  process.env.GEMINI_MODEL ?? 'gemini-2.5-flash-lite';

/** When true, Pillars use mocks (no Vertex spend). Set false for Gemini. */
export const useMockAi =
  (process.env.USE_MOCK_AI ?? 'true').toLowerCase() !== 'false';
