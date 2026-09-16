import { useMockAi } from '../config.js';

export type SafetyInput = {
  title: string;
  description: string;
  languageHint?: 'en' | 'si' | 'mixed';
};

export type SafetyResult = {
  allowed: boolean;
  risk: 'low' | 'medium' | 'high';
  reasons: string[];
  languageDetected: string;
  pillar: 'A';
  mode: 'mock' | 'gemini';
};

const BLOCK_PATTERNS = [
  /weapon|gun|කඩුව|තුවක්කු/i,
  /drug|heroin|කොකේන්|ගංජා/i,
  /cash.?mule|money.?mule|මුදල් ගෙනයන්න/i,
  /fake.?id|forged/i,
];

function mockSafety(input: SafetyInput): SafetyResult {
  const text = `${input.title}\n${input.description}`;
  const hits = BLOCK_PATTERNS.filter((p) => p.test(text));
  const hasSinhala = /[\u0D80-\u0DFF]/.test(text);
  return {
    allowed: hits.length === 0,
    risk: hits.length ? 'high' : hasSinhala ? 'medium' : 'low',
    reasons: hits.length
      ? ['Matched prohibited policy patterns', ...hits.map((p) => p.source)]
      : hasSinhala
        ? [
            'Sinhala/mixed text: apply localized few-shot safety (EN refusal ≠ SI refusal)',
            'Mock path — set USE_MOCK_AI=false + GCP_PROJECT_ID for Vertex Gemini',
          ]
        : ['No prohibited patterns detected'],
    languageDetected: hasSinhala ? 'si/mixed' : input.languageHint ?? 'en',
    pillar: 'A',
    mode: 'mock',
  };
}

/** Pillar A — vernacular safety before task create. */
export async function checkTaskSafety(input: SafetyInput): Promise<SafetyResult> {
  if (useMockAi || !process.env.GCP_PROJECT_ID) {
    return mockSafety(input);
  }

  // Vertex Gemini wiring lands next; keep deterministic mock fallback for local.
  return mockSafety(input);
}
