export const PLATFORM_FEE_PERCENT = 10;
export const DISPATCH_RADIUS_KM = 5;
export const CURRENCY = 'LKR';
export const MARKET = 'Sri Lanka';

export const useMockAi =
  (process.env.USE_MOCK_AI ?? 'true').toLowerCase() !== 'false';

export const gcpProjectId = process.env.GCP_PROJECT_ID ?? '';
export const gcpLocation = process.env.GCP_LOCATION ?? 'asia-south1';
export const geminiModel =
  process.env.GEMINI_MODEL ?? 'gemini-2.0-flash-001';
