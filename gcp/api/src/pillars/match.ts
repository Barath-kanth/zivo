import { Type as FunctionDeclarationSchemaType, type FunctionDeclaration } from '@google/genai';
import { useMockAi, gcpProjectId } from '../config.js';
import { generateWithTools } from '../gemini.js';
import { accessCardFor } from './abilities.js';
import {
  DISPATCH_RADIUS_KM,
  computeTrustTier,
  helpersForMatch,
  listDisputesForHelper,
  type TaskRow,
  type UserProfile,
} from '../store.js';

export type MatchCandidate = {
  helperId: string;
  name: string;
  distanceKm: number;
  verified: boolean;
  score: number;
  reasons: string[];
  trust_tier?: string;
  dispute_count?: number;
  /** Disclosed-only. Informational — never part of `score`. */
  access?: { abilities: string[]; note?: string };
};

export type MatchResult = {
  pillar: 'C';
  mode: 'mock' | 'gemini';
  radiusKm: number;
  candidates: MatchCandidate[];
  selected_helper_id?: string;
  selected_helper_name?: string;
  nearest_helper_id?: string;
  nearest_deprioritized?: boolean;
  explanation: string;
  tool_trace?: Array<{ name: string; args: unknown; result: unknown }>;
  research_note: string;
};

const RESEARCH =
  'Domain-Grounded Tool Orchestration + live Firestore trust/dispute tools (no hardcoded helper tiers).';

type Nearby = Awaited<ReturnType<typeof helpersForMatch>>;

async function trustFor(helper: UserProfile): Promise<'gold' | 'silver' | 'bronze'> {
  return computeTrustTier(helper);
}

async function scoreDeterministic(nearby: Nearby): Promise<MatchCandidate[]> {
  const out: MatchCandidate[] = [];
  for (const { helper, distanceKm } of nearby) {
    const disputes = await listDisputesForHelper(helper.id);
    const tier = await trustFor(helper);
    const reasons: string[] = [
      'Verified identity',
      `${distanceKm.toFixed(2)} km`,
      `Trust tier: ${tier} (from vouches/rating/jobs)`,
    ];
    // Ability is shown (if the helper disclosed it) but NEVER affects the score.
    const access = accessCardFor(helper);
    if (access) {
      reasons.push(`Access note: ${access.abilities.join(', ')}${access.note ? ` — “${access.note}”` : ''}`);
    }
    let score = 100 - distanceKm * 8;
    score += helper.rating_as_helper * 5;
    if (helper.helper_skills.length) {
      reasons.push(`Skills: ${helper.helper_skills.join(', ')}`);
      score += 10;
    }
    if (tier === 'gold') score += 15;
    if (tier === 'bronze') score -= 20;
    if (disputes.length) {
      reasons.push(`${disputes.length} dispute(s) on record — deprioritize`);
      score -= disputes.length * 25;
    }
    out.push({
      helperId: helper.id,
      name: helper.full_name,
      distanceKm: Number(distanceKm.toFixed(2)),
      verified: helper.kyc_status === 'verified',
      score: Math.round(score),
      reasons,
      trust_tier: tier,
      dispute_count: disputes.length,
      ...(access ? { access } : {}),
    });
  }
  return out.sort((a, b) => b.score - a.score);
}

async function mockMatch(task: TaskRow, nearby: Nearby): Promise<MatchResult> {
  const candidates = await scoreDeterministic(nearby);
  const nearest = [...candidates].sort((a, b) => a.distanceKm - b.distanceKm)[0];
  const selected = candidates[0];
  const nearestDep =
    Boolean(nearest && selected && nearest.helperId !== selected.helperId);

  return {
    pillar: 'C',
    mode: 'mock',
    radiusKm: DISPATCH_RADIUS_KM,
    candidates,
    selected_helper_id: selected?.helperId,
    selected_helper_name: selected?.name,
    nearest_helper_id: nearest?.helperId,
    nearest_deprioritized: nearestDep,
    explanation: nearestDep
      ? `Nearest helper ${nearest!.name} (${nearest!.distanceKm} km) deprioritized due to dispute history / bronze trust; selected ${selected!.name} with cleaner constraint fit.`
      : selected
        ? `Selected ${selected.name} under KYC + radius + live trust constraints.`
        : 'No verified helpers in radius.',
    research_note: RESEARCH,
    tool_trace: [
      { name: 'get_nearby_helpers', args: {}, result: 'live' },
      {
        name: 'get_dispute_history',
        args: { helper_id: nearest?.helperId },
        result: 'firestore',
      },
      {
        name: 'get_helper_trust_tier',
        args: { helper_id: nearest?.helperId },
        result: 'computed',
      },
    ],
  };
}

function buildTools(): FunctionDeclaration[] {
  return [
    {
      name: 'get_nearby_helpers',
      description:
        'Return verified helpers within dispatch radius with distance_km (deterministic geo).',
      parameters: {
        type: FunctionDeclarationSchemaType.OBJECT,
        properties: {
          radius_km: {
            type: FunctionDeclarationSchemaType.NUMBER,
            description: 'Optional radius override in km',
          },
        },
      },
    },
    {
      name: 'get_helper_trust_tier',
      description:
        'Return live trust tier for a helper id (gold|silver|bronze) from vouches/rating/jobs.',
      parameters: {
        type: FunctionDeclarationSchemaType.OBJECT,
        properties: {
          helper_id: { type: FunctionDeclarationSchemaType.STRING },
        },
        required: ['helper_id'],
      },
    },
    {
      name: 'get_dispute_history',
      description: 'Return dispute records for a helper id from Firestore tasks.',
      parameters: {
        type: FunctionDeclarationSchemaType.OBJECT,
        properties: {
          helper_id: { type: FunctionDeclarationSchemaType.STRING },
        },
        required: ['helper_id'],
      },
    },
  ];
}

function parseSelection(
  text: string,
  candidates: MatchCandidate[],
): { id?: string; explanation: string } {
  const cleaned = text.replace(/^```json\s*/i, '').replace(/```$/i, '').trim();
  const brace = cleaned.match(/\{[\s\S]*\}/);
  const tryParse = brace?.[0] ?? cleaned;
  try {
    const j = JSON.parse(tryParse) as {
      selected_helper_id?: string;
      explanation?: string;
    };
    return {
      id: j.selected_helper_id,
      explanation: (j.explanation || '').trim() || 'Constraint match complete.',
    };
  } catch {
    const hit = candidates.find((c) => text.includes(c.helperId));
    return {
      id: hit?.helperId,
      explanation: cleaned.slice(0, 400) || 'Gemini match complete.',
    };
  }
}

/** Pillar C — agentic constraint-based matching with function calling. */
export async function matchHelpers(task: TaskRow): Promise<MatchResult> {
  const nearby = await helpersForMatch(task);

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return mockMatch(task, nearby);
  }

  const nearbyPayload = await Promise.all(
    nearby.map(async ({ helper, distanceKm }) => ({
      helper_id: helper.id,
      name: helper.full_name,
      distance_km: Number(distanceKm.toFixed(2)),
      skills: helper.helper_skills,
      rating: helper.rating_as_helper,
      verified: helper.kyc_status === 'verified',
      trust_tier: await trustFor(helper),
    })),
  );

  const handler = async (name: string, args: Record<string, unknown>) => {
    if (name === 'get_nearby_helpers') {
      return { radius_km: DISPATCH_RADIUS_KM, helpers: nearbyPayload };
    }
    if (name === 'get_helper_trust_tier') {
      const id = String(args.helper_id ?? '');
      const row = nearby.find((n) => n.helper.id === id)?.helper;
      return {
        helper_id: id,
        trust_tier: row ? await trustFor(row) : 'silver',
      };
    }
    if (name === 'get_dispute_history') {
      const id = String(args.helper_id ?? '');
      return {
        helper_id: id,
        disputes: await listDisputesForHelper(id),
      };
    }
    return { error: `unknown tool ${name}` };
  };

  try {
    const { text, toolTrace } = await generateWithTools({
      systemPrompt: `You are Zivo Pillar C — agentic constraint-based helper matching for Sri Lanka hyperlocal care.

You MUST call the deterministic tools (do not invent distances, trust tiers, or disputes):
1) get_nearby_helpers
2) get_helper_trust_tier for each serious candidate
3) get_dispute_history for each serious candidate

Policy:
- Prefer verified helpers inside radius.
- Deprioritize helpers with recent disputes even if they are nearest.
- Prefer gold trust over bronze when constraints conflict.
- After tools, reply with ONLY JSON:
{"selected_helper_id":"...","explanation":"natural language why nearest was or was not chosen"}`,
      userPrompt: `Match a helper for task ${task.id}:
title=${JSON.stringify(task.title)}
category=${task.category}
location=(${task.lat},${task.lon})
goods_budget=${task.goods_budget}
Call tools, then pick one helper.`,
      tools: buildTools(),
      handler,
      maxTurns: 8,
    });

    const scored = await scoreDeterministic(nearby);
    const nearest = [...scored].sort((a, b) => a.distanceKm - b.distanceKm)[0];
    const { id, explanation: parsedExplanation } = parseSelection(text, scored);
    const selected =
      scored.find((c) => c.helperId === id) ?? scored[0];

    const candidates = selected
      ? [selected, ...scored.filter((c) => c.helperId !== selected.helperId)]
      : scored;

    const nearestDep = Boolean(
      nearest && selected && nearest.helperId !== selected.helperId,
    );
    const explanation =
      parsedExplanation &&
      parsedExplanation !== 'Gemini match complete.' &&
      parsedExplanation !== 'Constraint match complete.'
        ? parsedExplanation
        : nearestDep
          ? `Nearest helper ${nearest!.name} (${nearest!.distanceKm} km, ${nearest!.trust_tier}, ${nearest!.dispute_count} dispute(s)) was deprioritized. Selected ${selected!.name} (${selected!.distanceKm} km, ${selected!.trust_tier}) after tool-grounded constraint reasoning.`
          : selected
            ? `Selected ${selected.name} using get_nearby_helpers + live trust/dispute tools.`
            : 'No verified helpers in radius.';

    return {
      pillar: 'C',
      mode: 'gemini',
      radiusKm: DISPATCH_RADIUS_KM,
      candidates,
      selected_helper_id: selected?.helperId,
      selected_helper_name: selected?.name,
      nearest_helper_id: nearest?.helperId,
      nearest_deprioritized: nearestDep,
      explanation,
      tool_trace: toolTrace,
      research_note: RESEARCH,
    };
  } catch (err) {
    console.error('[matchHelpers] gemini tools failed', err);
    return mockMatch(task, nearby);
  }
}
