import {
  VOUCH_STAKE_LKR,
  VOUCH_THRESHOLD,
  WALK_RADIUS_KM,
  useMockAi,
  gcpProjectId,
} from '../config.js';
import { generateGeminiJson } from '../gemini.js';
import {
  createNeighborVouch,
  getHelperTrustCard,
  listLiveHelpersNearby,
  requiresNeighborVouch,
  type UserProfile,
} from '../store.js';

export type VouchResult = {
  pillar: 'vouching';
  mode: 'formula' | 'formula+gemini';
  stake_lkr: number;
  threshold: number;
  explanation: string;
  helper: {
    id: string;
    full_name: string;
    vouch_count: number;
    neighbor_vouched: boolean;
  };
  vouch: {
    id: string;
    voucher_name: string;
    stake_lkr: number;
  };
};

export async function vouchForNeighbor(input: {
  voucherId: string;
  helperId: string;
  note?: string;
  lat?: number;
  lon?: number;
}): Promise<VouchResult> {
  const { vouch, helper } = await createNeighborVouch({
    voucherId: input.voucherId,
    helperId: input.helperId,
    note: input.note,
    voucherLat: input.lat,
    voucherLon: input.lon,
  });

  let explanation =
    `${vouch.voucher_name} staked LKR ${vouch.stake_lkr} to vouch ${helper.full_name}` +
    ` (${helper.vouch_count ?? 0}/${VOUCH_THRESHOLD}` +
    `${helper.neighbor_vouched ? ' — Neighbor-Vouched unlocked' : ' toward inside-home unlock'}).`;
  let mode: VouchResult['mode'] = 'formula';

  if (!useMockAi && gcpProjectId && gcpProjectId !== 'your-gcp-project-id') {
    try {
      const g = await generateGeminiJson<{ explanation: string }>(
        `Explain Zivo neighbor vouching in ONE short sentence for Sri Lanka.
Helper ${helper.full_name} now has ${helper.vouch_count}/${VOUCH_THRESHOLD} vouches.
Badge unlocked: ${!!helper.neighbor_vouched}. Stake LKR ${VOUCH_STAKE_LKR}.
Return ONLY JSON: {"explanation":"..."}`,
      );
      if (g.explanation?.trim()) {
        explanation = g.explanation.trim();
        mode = 'formula+gemini';
      }
    } catch {
      /* keep */
    }
  }

  return {
    pillar: 'vouching',
    mode,
    stake_lkr: VOUCH_STAKE_LKR,
    threshold: VOUCH_THRESHOLD,
    explanation,
    helper: {
      id: helper.id,
      full_name: helper.full_name,
      vouch_count: helper.vouch_count ?? 0,
      neighbor_vouched: !!helper.neighbor_vouched,
    },
    vouch: {
      id: vouch.id,
      voucher_name: vouch.voucher_name,
      stake_lkr: vouch.stake_lkr,
    },
  };
}

export async function trustCard(helperId: string) {
  return {
    pillar: 'vouching' as const,
    ...(await getHelperTrustCard(helperId)),
  };
}

/** Live helpers annotated with vouch badge for Instant Dispatch UI. */
export async function liveHelpersWithTrust(lat: number, lon: number) {
  const live = await listLiveHelpersNearby(lat, lon, WALK_RADIUS_KM);
  const cards = await Promise.all(
    live.map(async (h) => {
      const card = await getHelperTrustCard(h.id);
      return {
        ...h,
        vouch_count: card.vouch_count,
        neighbor_vouched: card.neighbor_vouched,
        vouch_threshold: card.vouch_threshold,
      };
    }),
  );
  return {
    pillar: 'vouching' as const,
    walk_radius_km: WALK_RADIUS_KM,
    helpers: cards,
  };
}

export function assertInsideHomeAllowed(
  category: string | undefined,
  helper: Pick<UserProfile, 'neighbor_vouched' | 'full_name' | 'vouch_count'>,
) {
  if (!requiresNeighborVouch(category)) return;
  if (helper.neighbor_vouched) return;
  throw new Error(
    `${helper.full_name ?? 'Helper'} needs ${VOUCH_THRESHOLD} neighbor vouches for inside-home tasks` +
      ` (has ${helper.vouch_count ?? 0})`,
  );
}
