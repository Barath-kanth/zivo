export const PLATFORM_FEE_PERCENT = 10;
export const DISPATCH_RADIUS_KM = Number(process.env.DISPATCH_RADIUS_KM ?? '80');
export const CURRENCY = 'LKR';
export const MARKET = 'Sri Lanka';

export const gcpProjectId = process.env.GCP_PROJECT_ID ?? '';
export const gcpLocation = process.env.GCP_LOCATION ?? 'asia-south1';
export const geminiModel =
  process.env.GEMINI_MODEL ?? 'gemini-2.5-flash-lite';

/** When true, Pillars use mocks (no Vertex spend). Set false for Gemini. */
export const useMockAi =
  (process.env.USE_MOCK_AI ?? 'true').toLowerCase() !== 'false';
