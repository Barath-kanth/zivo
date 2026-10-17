import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiJson } from '../gemini.js';
import { publishImpactEvent } from '../events.js';

export type HazardLevel = 'calm' | 'watch' | 'alert' | 'emergency';

export type ResilienceStatus = {
  pillar: 'resilience';
  mode: 'live' | 'mock';
  lat: number;
  lon: number;
  hazard: HazardLevel;
  precip_mm_next_24h: number;
  flood_risk: string;
  summary: string;
  priorities: string[];
  source: string;
  checked_at: string;
};

export type TriageResult = {
  pillar: 'resilience_triage';
  mode: 'mock' | 'gemini';
  priority: 'critical' | 'high' | 'normal' | 'defer';
  score: number;
  reason: string;
  boost_urgency: boolean;
};

async function fetchOpenMeteo(lat: number, lon: number): Promise<{
  precip: number;
  floodRisk: string;
}> {
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
    `&hourly=precipitation&forecast_days=1&timezone=Asia%2FColombo`;
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`Open-Meteo ${res.status}`);
  const data = (await res.json()) as {
    hourly?: { precipitation?: number[] };
  };
  const precip = (data.hourly?.precipitation ?? []).reduce(
    (a, b) => a + (Number(b) || 0),
    0,
  );
  let floodRisk = 'low';
  if (precip >= 80) floodRisk = 'high';
  else if (precip >= 40) floodRisk = 'moderate';
  else if (precip >= 15) floodRisk = 'elevated';
  return { precip: Number(precip.toFixed(1)), floodRisk };
}

function hazardFromPrecip(precip: number): HazardLevel {
  if (precip >= 80) return 'emergency';
  if (precip >= 40) return 'alert';
  if (precip >= 15) return 'watch';
  return 'calm';
}

/**
 * One alert event per ~1 km cell, per hazard level, per hour — otherwise every client
 * poll of /resilience/status would inflate "alerts" in BigQuery and the impact card.
 */
const lastAlertAt = new Map<string, number>();
function shouldEmitAlert(lat: number, lon: number, hazard: string): boolean {
  const key = `${lat.toFixed(2)},${lon.toFixed(2)},${hazard}`;
  const now = Date.now();
  const prev = lastAlertAt.get(key) ?? 0;
  if (now - prev < 3_600_000) return false;
  lastAlertAt.set(key, now);
  return true;
}

/** Neighbourhood flood / monsoon status using Open-Meteo (Earth Engine optional later). */
export async function getResilienceStatus(input: {
  lat: number;
  lon: number;
}): Promise<ResilienceStatus> {
  const checked_at = new Date().toISOString();
  try {
    const { precip, floodRisk } = await fetchOpenMeteo(input.lat, input.lon);
    const hazard = hazardFromPrecip(precip);
    const status: ResilienceStatus = {
      pillar: 'resilience',
      mode: 'live',
      lat: input.lat,
      lon: input.lon,
      hazard,
      precip_mm_next_24h: precip,
      flood_risk: floodRisk,
      summary:
        hazard === 'calm'
          ? 'Weather looks manageable for ordinary neighbourhood help.'
          : hazard === 'watch'
            ? 'Elevated rain expected — prefer shorter outdoor errands and check on elders.'
            : hazard === 'alert'
              ? 'Heavy rain risk — prioritize elder / disability / evacuation help over groceries.'
              : 'Severe rainfall risk — treat mobility & safety tasks as critical.',
      priorities:
        hazard === 'calm'
          ? ['Ordinary chores OK', 'Keep porch lights on for neighbours']
          : [
              'Elder check-ins & hospital aid first',
              'Avoid unnecessary outdoor exposure',
              'Batch same-street trips to cut flooded-road mileage',
            ],
      source: 'Open-Meteo hourly precipitation (Asia/Colombo)',
      checked_at,
    };
    if (hazard !== 'calm' && shouldEmitAlert(input.lat, input.lon, hazard)) {
      await publishImpactEvent({
        type: 'resilience_alert',
        payload: {
          hazard,
          precip_mm_next_24h: precip,
          // ~1 km grid: enough for a community-needs map, not a home address.
          lat: Number(input.lat.toFixed(2)),
          lon: Number(input.lon.toFixed(2)),
        },
      });
    }
    return status;
  } catch (err) {
    console.warn('[resilience] Open-Meteo failed', err);
    return {
      pillar: 'resilience',
      mode: 'mock',
      lat: input.lat,
      lon: input.lon,
      hazard: 'watch',
      precip_mm_next_24h: 22,
      flood_risk: 'elevated',
      summary:
        'Live weather feed unavailable — demo watch mode: prefer elder care over grocery runs.',
      priorities: [
        'Elder / disability assistance first',
        'Defer non-urgent outdoor errands',
      ],
      source: 'fallback (Open-Meteo unreachable)',
      checked_at,
    };
  }
}

/** Gemini triage — evacuation / elder care outranks grocery during hazards. */
export async function triageTaskPriority(input: {
  title: string;
  description: string;
  category?: string;
  hazard: HazardLevel;
}): Promise<TriageResult> {
  const text = `${input.title}\n${input.description}\n${input.category ?? ''}`;
  const elder =
    /elder|grandma|grandpa|ammi|appachchi|appā|ammā|wheelchair|disabled|hospital|flood|evacuat|stranded/i.test(
      text,
    );
  const chore = /grocery|laundry|queue|clean|cook|pet/i.test(text);

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    if (input.hazard !== 'calm' && elder) {
      return {
        pillar: 'resilience_triage',
        mode: 'mock',
        priority: 'critical',
        score: 95,
        reason: 'Hazard + elder/disability keywords — prioritize immediately.',
        boost_urgency: true,
      };
    }
    if (input.hazard === 'alert' || input.hazard === 'emergency') {
      if (chore) {
        return {
          pillar: 'resilience_triage',
          mode: 'mock',
          priority: 'defer',
          score: 25,
          reason: 'Non-urgent chore during heavy rain — defer if possible.',
          boost_urgency: false,
        };
      }
    }
    return {
      pillar: 'resilience_triage',
      mode: 'mock',
      priority: 'normal',
      score: 50,
      reason: 'Ordinary priority.',
      boost_urgency: false,
    };
  }

  try {
    const g = await generateGeminiJson<{
      priority?: string;
      score?: number;
      reason?: string;
      boost_urgency?: boolean;
    }>(`You triage Zivo neighbourhood-care tasks during monsoon / flood risk in Sri Lanka.
Hazard level: ${input.hazard}
Task title: ${JSON.stringify(input.title)}
Description: ${JSON.stringify(input.description)}
Category: ${JSON.stringify(input.category ?? '')}

Priority rules:
- critical: evacuating elders, stranded disabled neighbours, hospital transport, flooding homes
- high: medicine pickup, check-ins on vulnerable people
- normal: ordinary help when hazard is calm/watch
- defer: grocery/laundry/queue when hazard is alert/emergency unless medically necessary

Return ONLY JSON:
{"priority":"critical"|"high"|"normal"|"defer","score":0-100,"reason":"...","boost_urgency":true|false}`);

    const priority =
      g.priority === 'critical' ||
      g.priority === 'high' ||
      g.priority === 'defer' ||
      g.priority === 'normal'
        ? g.priority
        : 'normal';
    return {
      pillar: 'resilience_triage',
      mode: 'gemini',
      priority,
      score: Math.max(0, Math.min(100, Number(g.score ?? 50))),
      reason: (g.reason ?? '').trim() || 'Triaged for neighbourhood safety.',
      boost_urgency: Boolean(g.boost_urgency) || priority === 'critical',
    };
  } catch (err) {
    console.error('[triageTaskPriority] failed', err);
    return {
      pillar: 'resilience_triage',
      mode: 'mock',
      priority: elder ? 'high' : 'normal',
      score: elder ? 80 : 50,
      reason: 'Fallback triage.',
      boost_urgency: elder && input.hazard !== 'calm',
    };
  }
}
