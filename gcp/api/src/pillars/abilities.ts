/**
 * Ability-aware work: Zivo treats disability as a *design input for the job*, never as a score penalty.
 *
 * - Helpers (or clients) opt in to an ability profile. It is private by default.
 * - A helper may choose to tell clients ("disclose_access") so the client can hire or decline knowingly.
 * - Matching ranks on trust / distance / disputes only — ability NEVER changes a score (see match.ts).
 * - `abilityFit` is a transparent lookup table, not a model: it tells a helper which parts of a job
 *   are fine, adaptable with a Zivo tool, or safety-critical. It never blocks; the helper decides.
 * - `adaptBrief` (Gemini) rewrites a job into a step-by-step brief that names the Zivo tool to use at
 *   each step for *that* helper's abilities, in their language.
 */
import { gcpProjectId, useMockAi } from '../config.js';
import { generateGeminiRace } from '../gemini.js';
import type { TaskRow, UserProfile } from '../store.js';

export const ABILITY_KEYS = ['visual', 'hearing', 'speech', 'mobility', 'cognitive'] as const;
export type AbilityKey = (typeof ABILITY_KEYS)[number];

export function cleanAbilities(raw: unknown): AbilityKey[] {
  if (!Array.isArray(raw)) return [];
  return [...new Set(raw.map(String))].filter((k): k is AbilityKey =>
    (ABILITY_KEYS as readonly string[]).includes(k),
  );
}

export type AccessCard = { abilities: AbilityKey[]; note?: string };

/** What a client may see: only when the helper chose to disclose. */
export function accessCardFor(u: Pick<UserProfile, 'abilities' | 'disclose_access' | 'access_note'>): AccessCard | undefined {
  const abilities = cleanAbilities(u.abilities);
  if (!u.disclose_access || !abilities.length) return undefined;
  const note = u.access_note?.trim().slice(0, 240);
  return { abilities, ...(note ? { note } : {}) };
}

/** 0 = not needed · 1 = can be adapted with a Zivo tool or a small change · 2 = safety-critical */
type Demand = { visual: 0 | 1 | 2; hearing: 0 | 1 | 2; speech: 0 | 1 | 2; mobility: 0 | 1 | 2; cognitive: 0 | 1 | 2 };
const D = (visual: Demand['visual'], hearing: Demand['hearing'], speech: Demand['speech'], mobility: Demand['mobility'], cognitive: Demand['cognitive']): Demand => ({
  visual, hearing, speech, mobility, cognitive,
});

const DEMANDS: Record<string, Demand> = {
  queueStanding: D(0, 0, 1, 1, 0),
  laundry: D(0, 0, 0, 1, 0),
  groceryRun: D(1, 0, 0, 1, 1),
  homeCleaning: D(1, 0, 0, 1, 0),
  homeCooking: D(1, 0, 0, 0, 0),
  movingHelp: D(0, 0, 0, 2, 0),
  tutoring: D(0, 1, 1, 0, 0),
  techHelp: D(1, 0, 0, 0, 1),
  petCare: D(1, 0, 0, 1, 0),
  tailoring: D(1, 0, 0, 0, 0),
  driver: D(2, 1, 0, 0, 0),
  errandRun: D(1, 0, 1, 1, 1),
  gardening: D(0, 0, 0, 1, 0),
  documentWork: D(1, 0, 0, 0, 2),
  hospitalCompanion: D(1, 1, 1, 1, 0),
  babysitting: D(1, 1, 0, 1, 0),
  elderCare: D(1, 1, 1, 1, 0),
  eventHelp: D(0, 1, 1, 0, 0),
  photography: D(1, 0, 0, 0, 0),
  homeRepair: D(1, 0, 0, 1, 0),
  other: D(0, 0, 0, 0, 0),
  // Remote / seated: no travel, little or no mobility / vision demand.
  phoneCheckIn: D(0, 1, 1, 0, 0),
  readingAloud: D(0, 0, 1, 0, 1),
  remoteTutoring: D(0, 1, 1, 0, 0),
  // Sighted-assist micro-job: a sighted neighbour does a 60 s video check.
  sightedAssist: D(1, 0, 0, 0, 0),
};

export type FitLevel = 'great' | 'adaptable' | 'heads_up';
export type AbilityFit = {
  level: FitLevel;
  /** One entry per ability the helper has that this job touches. `tip` is an i18n key suffix. */
  concerns: Array<{ ability: AbilityKey; severity: 1 | 2; tip: string; tool: 'eyes' | 'doorstep' | 'say' | 'easyread' | 'none' }>;
};

const TOOL: Record<AbilityKey, AbilityFit['concerns'][number]['tool']> = {
  visual: 'eyes',
  hearing: 'doorstep',
  speech: 'say',
  mobility: 'none',
  cognitive: 'easyread',
};

export function abilityFit(task: Pick<TaskRow, 'category'>, abilities: AbilityKey[]): AbilityFit {
  const demand = DEMANDS[task.category] ?? DEMANDS.other;
  const concerns: AbilityFit['concerns'] = [];
  for (const a of abilities) {
    const sev = demand[a];
    if (sev > 0) {
      concerns.push({
        ability: a,
        severity: sev as 1 | 2,
        tip: sev === 2 ? `${a}.critical` : a,
        tool: sev === 2 ? 'none' : TOOL[a],
      });
    }
  }
  const level: FitLevel = concerns.some((c) => c.severity === 2)
    ? 'heads_up'
    : concerns.length
      ? 'adaptable'
      : 'great';
  return { level, concerns };
}

const LANG_NAME: Record<string, string> = { en: 'English', ta: 'Tamil', si: 'Sinhala' };
const ABILITY_WORDS: Record<AbilityKey, string> = {
  visual: 'blind or low vision (works by voice and sound; uses Zivo Eyes camera descriptions)',
  hearing: 'deaf or hard of hearing (works by text and visual cues; uses Doorstep Talk live captions)',
  speech: 'has difficulty speaking (uses typed text, phrase cards and read-aloud)',
  mobility: 'limited mobility (avoid long standing, stairs, heavy lifting)',
  cognitive: 'prefers plain, short, step-by-step language',
};

export type BriefStep = { text: string; tool: 'eyes' | 'doorstep' | 'say' | 'easyread' | 'none' };
export type AdaptBrief = {
  pillar: 'ability_brief';
  mode: 'mock' | 'gemini';
  lang: string;
  steps: BriefStep[];
  heads_up?: string;
  fit: AbilityFit;
  model?: string;
  latency_ms?: number;
};

function fallbackBrief(task: TaskRow, fit: AbilityFit, lang: string): AdaptBrief {
  const tools = new Set(fit.concerns.map((c) => c.tool));
  const steps: BriefStep[] = [
    { text: `Job: ${task.title}`, tool: 'none' },
    ...(tools.has('doorstep') ? [{ text: 'At the door, open Doorstep Talk so the client’s words appear as large text.', tool: 'doorstep' as const }] : []),
    ...(tools.has('say') ? [{ text: 'Use a phrase card or type a reply and let Zivo speak it.', tool: 'say' as const }] : []),
    ...(tools.has('eyes') ? [{ text: 'Use Zivo Eyes to read labels, check items against the list, and read the receipt aloud.', tool: 'eyes' as const }] : []),
    { text: 'Finish with the End code the client gives you, then upload the completion photo.', tool: 'none' },
  ];
  return { pillar: 'ability_brief', mode: 'mock', lang, steps, fit };
}

/** Personal, tool-aware job brief for one helper. Falls back to a deterministic brief. */
export async function adaptBrief(input: {
  task: TaskRow;
  abilities: AbilityKey[];
  lang?: string;
}): Promise<AdaptBrief> {
  const lang = input.lang && LANG_NAME[input.lang] ? input.lang : 'en';
  const fit = abilityFit(input.task, input.abilities);
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id' || !input.abilities.length) {
    return fallbackBrief(input.task, fit, lang);
  }
  const prompt = `You write a short personal job brief for a Zivo helper in Sri Lanka.
Helper profile: ${input.abilities.map((a) => ABILITY_WORDS[a]).join('; ')}.
Zivo tools the helper can use: "eyes" (camera: describe scene, read text aloud, check an item against a list, read receipt), "doorstep" (live captions of what the client says + translation), "say" (phrase cards and type-to-speak), "easyread" (plain-language rewrite), "none".
Write ${LANG_NAME[lang]} only. 3-6 numbered-style steps, each one short sentence a screen reader can read aloud. For each step name the best tool or "none".
Rules: never suggest handling cash (goods are paid from escrow); never suggest skipping the Start/End code; do not make medical or safety judgements from a photo — say "ask the client or a person" when unsure; do not assume the helper cannot do the job — adapt it; add "heads_up" ONLY if a part of the job is genuinely unsafe for this profile (e.g. driving for a blind helper), otherwise "".
Return ONLY JSON: {"steps":[{"text":"...","tool":"eyes|doorstep|say|easyread|none"}],"heads_up":"..."}
Job: ${JSON.stringify({ title: input.task.title, category: input.task.category, description: input.task.description.slice(0, 600), goods_budget: input.task.goods_budget })}`;
  try {
    const { value: g, model, ms } = await generateGeminiRace<{ steps?: Array<{ text?: string; tool?: string }>; heads_up?: string }>({
      prompt,
      models: [process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash-lite', 'gemini-2.5-flash'],
      thinkingBudget: 0,
      hedgeMs: 3500,
      timeoutMs: 14000,
      maxOutputTokens: 700,
    });
    const tools = new Set(['eyes', 'doorstep', 'say', 'easyread', 'none']);
    const steps: BriefStep[] = (g.steps ?? [])
      .map((s) => ({
        text: String(s.text ?? '').trim().slice(0, 220),
        tool: (tools.has(String(s.tool)) ? s.tool : 'none') as BriefStep['tool'],
      }))
      .filter((s) => s.text)
      .slice(0, 6);
    if (steps.length < 2) return fallbackBrief(input.task, fit, lang);
    const heads = String(g.heads_up ?? '').trim().slice(0, 240);
    return { pillar: 'ability_brief', mode: 'gemini', lang, steps, ...(heads ? { heads_up: heads } : {}), fit, model, latency_ms: ms };
  } catch (err) {
    console.warn('[adaptBrief] gemini failed, deterministic brief', err instanceof Error ? err.message : err);
    return fallbackBrief(input.task, fit, lang);
  }
}

/* ── Zivo Eyes (blind / low-vision helpers) ─────────────────────────────── */

export type EyesMode = 'describe' | 'read' | 'match';
export type EyesResult = {
  pillar: 'zivo_eyes';
  mode: 'mock' | 'gemini';
  eyes_mode: EyesMode;
  /** Short, spoken-friendly answer in the requested language. */
  spoken: string;
  /** For `match`: one verdict per list item. */
  matches?: Array<{ item: string; verdict: 'yes' | 'no' | 'unsure'; note: string }>;
  /** Anything the model could not verify (expiry dates, allergens, medicine strength…). */
  cautions: string[];
  model?: string;
  latency_ms?: number;
};

export async function zivoEyes(input: {
  image?: Buffer;
  mimeType?: string;
  mode: EyesMode;
  lang?: string;
  items?: string[];
  hint?: string;
}): Promise<EyesResult> {
  const lang = input.lang && LANG_NAME[input.lang] ? input.lang : 'en';
  const items = (input.items ?? []).map((s) => String(s).trim()).filter(Boolean).slice(0, 15);
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return {
      pillar: 'zivo_eyes',
      mode: 'mock',
      eyes_mode: input.mode,
      spoken: 'Mock mode: I would describe or read what the camera sees here.',
      cautions: ['Mock AI is on — this is not a real reading.'],
    };
  }
  if (!input.image?.length) throw new Error('photo required');

  const task =
    input.mode === 'read'
      ? 'Read ALL visible text in the image aloud-friendly, in reading order (labels, prices, dates, receipt lines). Group it simply. Say what kind of thing it is first.'
      : input.mode === 'match'
        ? `The helper must buy / find these items: ${JSON.stringify(items)}. For each item say whether the object(s) in the photo are that item: "yes" (clearly matches name, brand/size if given), "no" (clearly something else), or "unsure" (cannot tell, partly hidden, text unreadable). Also read the brand, size/weight and any expiry date you can see.`
        : 'Describe the scene for a blind person in 2-4 short sentences: what is in front of them, where things are (left/right/centre, near/far), anything that could be a hazard. Be concrete, no filler.';
  const prompt = `You are "Zivo Eyes", a careful assistant for a blind or low-vision person doing a neighbourhood-help job.
${task}
Write the answer in ${LANG_NAME[lang]} (keep product names as printed). Be brief: it will be read aloud.
Honesty rules: if text is blurry or cut off, say so and tell them how to retake the photo (closer, more light, hold steady). NEVER guess an expiry date, medicine name/strength, allergen or ingredient — say you are not sure and to ask a person. Do not identify people.
Return ONLY JSON: {"spoken":"...","matches":[{"item":"...","verdict":"yes|no|unsure","note":"..."}],"cautions":["..."]}
Use "matches":[] unless mode is match. Context: ${JSON.stringify(input.hint ?? '')}`;

  const { value: g, model, ms } = await generateGeminiRace<{
    spoken?: string;
    matches?: Array<{ item?: string; verdict?: string; note?: string }>;
    cautions?: string[];
  }>({
    prompt,
    media: input.image,
    mimeType: input.mimeType,
    models: [process.env.GEMINI_VISION_MODEL?.trim() || 'gemini-2.5-flash', process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash-lite'],
    thinkingBudget: 0,
    hedgeMs: 5000,
    timeoutMs: 20000,
    maxOutputTokens: 900,
  });
  const verdicts = new Set(['yes', 'no', 'unsure']);
  return {
    pillar: 'zivo_eyes',
    mode: 'gemini',
    eyes_mode: input.mode,
    spoken: String(g.spoken ?? '').trim().slice(0, 900) || 'I could not make this out. Try again closer and in better light.',
    matches:
      input.mode === 'match'
        ? (g.matches ?? []).slice(0, 15).map((m) => ({
            item: String(m.item ?? '').slice(0, 80),
            verdict: (verdicts.has(String(m.verdict)) ? m.verdict : 'unsure') as 'yes' | 'no' | 'unsure',
            note: String(m.note ?? '').slice(0, 200),
          }))
        : undefined,
    cautions: (g.cautions ?? []).map((c) => String(c).slice(0, 160)).slice(0, 4),
    model,
    latency_ms: ms,
  };
}

/* ── Doorstep Talk (deaf / hard-of-hearing helpers) ─────────────────────── */

export type DoorstepResult = {
  pillar: 'doorstep_talk';
  mode: 'mock' | 'gemini';
  heard: string;
  heard_lang: string;
  /** `heard` translated to the reader's language (same text if already that language). */
  for_reader: string;
  /** One short sentence if it is a question/request, so the UI can offer quick replies. */
  intent: 'question' | 'instruction' | 'greeting' | 'other';
  model?: string;
  latency_ms?: number;
};

export async function doorstepTalk(input: {
  audio?: Buffer;
  mimeType?: string;
  readerLang?: string;
}): Promise<DoorstepResult> {
  const lang = input.readerLang && LANG_NAME[input.readerLang] ? input.readerLang : 'en';
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return { pillar: 'doorstep_talk', mode: 'mock', heard: 'Please put the bags in the kitchen.', heard_lang: 'en', for_reader: 'Please put the bags in the kitchen.', intent: 'instruction' };
  }
  if (!input.audio?.length) throw new Error('audio required');
  const mime = input.mimeType?.startsWith('audio/') ? input.mimeType : 'audio/webm';
  const prompt = `You caption a face-to-face conversation for a deaf person at a doorstep in Sri Lanka.
Listen to the audio (Tamil, Sinhala, English or mixed). Return what was said, faithfully (do not summarise, keep numbers and names), and the same meaning in ${LANG_NAME[lang]} for the reader (identical text if already ${LANG_NAME[lang]}). If the audio is silence/noise, return empty strings.
Return ONLY JSON: {"heard":"...","heard_lang":"en|ta|si|other","for_reader":"...","intent":"question|instruction|greeting|other"}`;
  const { value: g, model, ms } = await generateGeminiRace<{ heard?: string; heard_lang?: string; for_reader?: string; intent?: string }>({
    prompt,
    media: input.audio,
    mimeType: mime,
    models: [process.env.VOICE_SUGGEST_MODEL?.trim() || 'gemini-2.5-flash', process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash-lite'],
    thinkingBudget: 0,
    hedgeMs: 4000,
    timeoutMs: 15000,
    maxOutputTokens: 500,
  });
  const intents = new Set(['question', 'instruction', 'greeting', 'other']);
  const heard = String(g.heard ?? '').trim().slice(0, 600);
  return {
    pillar: 'doorstep_talk',
    mode: 'gemini',
    heard,
    heard_lang: String(g.heard_lang ?? 'other').slice(0, 8),
    for_reader: String(g.for_reader ?? heard).trim().slice(0, 600),
    intent: (intents.has(String(g.intent)) ? g.intent : 'other') as DoorstepResult['intent'],
    model,
    latency_ms: ms,
  };
}

/* ── Access audit (entrance photo → mobility / access note for helpers) ── */

export type AccessAudit = {
  pillar: 'access_audit';
  mode: 'mock' | 'gemini';
  /** Short spoken-friendly summary in the requested language. */
  spoken: string;
  stairs: number | null;
  ramp: 'yes' | 'no' | 'unsure';
  door: 'wide' | 'narrow' | 'unsure';
  surface: 'flat' | 'uneven' | 'unsure';
  lighting: 'good' | 'dim' | 'unsure';
  wheelchair: 'yes' | 'no' | 'unsure';
  cautions: string[];
  model?: string;
  latency_ms?: number;
};

export async function accessAudit(input: {
  image?: Buffer;
  mimeType?: string;
  lang?: string;
  hint?: string;
}): Promise<AccessAudit> {
  const lang = input.lang && LANG_NAME[input.lang] ? input.lang : 'en';
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return {
      pillar: 'access_audit',
      mode: 'mock',
      spoken: 'Mock: 3 steps, no ramp, narrow door — wheelchair helpers may need help at the entrance.',
      stairs: 3,
      ramp: 'no',
      door: 'narrow',
      surface: 'flat',
      lighting: 'good',
      wheelchair: 'no',
      cautions: ['Mock AI — not a real reading.'],
    };
  }
  if (!input.image?.length) throw new Error('photo required');

  const prompt = `You are Zivo Access Audit. A client photographed the entrance / approach to a home where a helper will arrive.
Describe ONLY what is visible for ACCESS and MOBILITY. Write the spoken summary in ${LANG_NAME[lang]}, brief (1-3 sentences), concrete.
Rules: NEVER invent stairs/ramp/door width you cannot see. Prefer "unsure" and say how to retake (stand back, include the full door and steps). Do not identify people. Do not guess building codes.
Return ONLY JSON:
{"spoken":"...","stairs":number|null,"ramp":"yes|no|unsure","door":"wide|narrow|unsure","surface":"flat|uneven|unsure","lighting":"good|dim|unsure","wheelchair":"yes|no|unsure","cautions":["..."]}
Context: ${JSON.stringify(input.hint ?? '')}`;

  const { value: g, model, ms } = await generateGeminiRace<{
    spoken?: string;
    stairs?: number | null;
    ramp?: string;
    door?: string;
    surface?: string;
    lighting?: string;
    wheelchair?: string;
    cautions?: string[];
  }>({
    prompt,
    media: input.image,
    mimeType: input.mimeType,
    models: [process.env.GEMINI_VISION_MODEL?.trim() || 'gemini-2.5-flash', process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash-lite'],
    thinkingBudget: 0,
    hedgeMs: 5000,
    timeoutMs: 20000,
    maxOutputTokens: 700,
  });

  const yn = new Set(['yes', 'no', 'unsure']);
  const doorOk = new Set(['wide', 'narrow', 'unsure']);
  const surfaceOk = new Set(['flat', 'uneven', 'unsure']);
  const lightOk = new Set(['good', 'dim', 'unsure']);
  const stairs =
    typeof g.stairs === 'number' && Number.isFinite(g.stairs) && g.stairs >= 0
      ? Math.min(40, Math.round(g.stairs))
      : null;

  return {
    pillar: 'access_audit',
    mode: 'gemini',
    spoken:
      String(g.spoken ?? '').trim().slice(0, 500) ||
      'I could not see the entrance clearly. Stand further back so the door and any steps are in the photo.',
    stairs,
    ramp: (yn.has(String(g.ramp)) ? g.ramp : 'unsure') as AccessAudit['ramp'],
    door: (doorOk.has(String(g.door)) ? g.door : 'unsure') as AccessAudit['door'],
    surface: (surfaceOk.has(String(g.surface)) ? g.surface : 'unsure') as AccessAudit['surface'],
    lighting: (lightOk.has(String(g.lighting)) ? g.lighting : 'unsure') as AccessAudit['lighting'],
    wheelchair: (yn.has(String(g.wheelchair)) ? g.wheelchair : 'unsure') as AccessAudit['wheelchair'],
    cautions: (g.cautions ?? []).map((c) => String(c).slice(0, 160)).slice(0, 4),
    model,
    latency_ms: ms,
  };
}
