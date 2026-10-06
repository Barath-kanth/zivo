import { useMockAi } from '../config.js';
import { DISPATCH_RADIUS_KM, helpersForMatch, type TaskRow } from '../store.js';

export type MatchResult = {
  pillar: 'C';
  mode: 'mock' | 'gemini';
  radiusKm: number;
  candidates: Array<{
    helperId: string;
    name: string;
    distanceKm: number;
    verified: boolean;
    score: number;
    reasons: string[];
  }>;
  explanation: string;
};

/** Pillar C — deterministic tools + ranking (Gemini rationale later). */
export async function matchHelpers(task: TaskRow): Promise<MatchResult> {
  const nearby = await helpersForMatch(task);
  const scored = nearby
    .map(({ helper, distanceKm }) => {
      const reasons: string[] = ['Verified identity', `${distanceKm.toFixed(2)} km`];
      let score = 100 - distanceKm * 8;
      score += helper.rating_as_helper * 5;
      if (helper.helper_skills.length) {
        reasons.push(`Skills: ${helper.helper_skills.join(', ')}`);
        score += 10;
      }
      return {
        helperId: helper.id,
        name: helper.full_name,
        distanceKm: Number(distanceKm.toFixed(2)),
        verified: helper.kyc_status === 'verified',
        score: Math.round(score),
        reasons,
      };
    })
    .sort((a, b) => b.score - a.score);

  return {
    pillar: 'C',
    mode: useMockAi ? 'mock' : 'gemini',
    radiusKm: DISPATCH_RADIUS_KM,
    candidates: scored,
    explanation:
      'Constraint matching: KYC + radius + skills. Gemini adds NL rationale when USE_MOCK_AI=false.',
  };
}
