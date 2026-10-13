import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiMultimodalJson } from '../gemini.js';
import { sniffImageMime } from '../image_mime.js';

/** Valid Flutter `TaskCategory.name` values. */
export const PHOTO_SUGGEST_CATEGORIES = [
  'queueStanding',
  'laundry',
  'groceryRun',
  'homeCleaning',
  'homeCooking',
  'movingHelp',
  'tutoring',
  'techHelp',
  'petCare',
  'tailoring',
  'driver',
  'errandRun',
  'gardening',
  'documentWork',
  'hospitalCompanion',
  'babysitting',
  'elderCare',
  'eventHelp',
  'photography',
  'homeRepair',
  'other',
] as const;

export type PhotoSuggestCategory = (typeof PHOTO_SUGGEST_CATEGORIES)[number];

export type PhotoSuggestQuestion = {
  id: string;
  prompt: string;
  /** Hint for the describe form — not a pricing field schema. */
  hint?: string;
};

export type PhotoSuggestResult = {
  pillar: 'photo_suggest';
  mode: 'mock' | 'gemini';
  category: PhotoSuggestCategory;
  category_label: string;
  confidence: number;
  title: string;
  description: string;
  /** Short questions the client should confirm before posting. */
  questions: PhotoSuggestQuestion[];
  /** What the model thinks it saw (user-facing). */
  seen: string[];
  explanation: string;
};

type GeminiPhotoJson = {
  category?: string;
  category_label?: string;
  confidence?: number;
  title?: string;
  description?: string;
  questions?: Array<{ id?: string; prompt?: string; hint?: string }>;
  seen?: string[];
  explanation?: string;
};

const LABELS: Record<PhotoSuggestCategory, string> = {
  queueStanding: 'Queue Standing',
  laundry: 'Laundry',
  groceryRun: 'Grocery Run',
  homeCleaning: 'Home Cleaning',
  homeCooking: 'Home Cooking',
  movingHelp: 'Moving Help',
  tutoring: 'Tutoring',
  techHelp: 'Tech Help',
  petCare: 'Pet Care',
  tailoring: 'Tailoring',
  driver: 'Driver',
  errandRun: 'Errand Run',
  gardening: 'Gardening',
  documentWork: 'Document Help',
  hospitalCompanion: 'Hospital Aid',
  babysitting: 'Babysitting',
  elderCare: 'Elder Care',
  eventHelp: 'Event Help',
  photography: 'Photography',
  homeRepair: 'Home Repair',
  other: 'Other',
};

function normalizeCategory(raw?: string): PhotoSuggestCategory {
  const v = (raw || '').trim();
  if ((PHOTO_SUGGEST_CATEGORIES as readonly string[]).includes(v)) {
    return v as PhotoSuggestCategory;
  }
  const lower = v.toLowerCase();
  const hit = PHOTO_SUGGEST_CATEGORIES.find(
    (c) => c.toLowerCase() === lower || LABELS[c].toLowerCase() === lower,
  );
  return hit ?? 'other';
}

function mockFromScene(hint?: string): PhotoSuggestResult {
  const h = (hint || '').toLowerCase();
  if (/list|grocery|shop|receipt|market/.test(h)) {
    return {
      pillar: 'photo_suggest',
      mode: 'mock',
      category: 'groceryRun',
      category_label: LABELS.groceryRun,
      confidence: 0.72,
      title: 'Buy items from my shopping list',
      description:
        'Please buy the groceries shown in my photo from a nearby supermarket. Stick to the listed items, choose reasonable brands, and keep the receipt for escrow reimbursement.',
      questions: [
        {
          id: 'store_pref',
          prompt: 'Any preferred shop or brand limits?',
          hint: 'e.g. Cargills / Keells, local brands only',
        },
        {
          id: 'subs',
          prompt: 'OK to substitute if an item is out of stock?',
        },
        {
          id: 'budget',
          prompt: 'What is the max goods budget in LKR?',
        },
      ],
      seen: ['Handwritten or printed shopping list', 'Grocery items'],
      explanation:
        'Looks like a shopping list — drafted a grocery run. Confirm store preference and budget before posting.',
    };
  }
  if (/pipe|leak|socket|broken|repair|tap|wire|hinge/.test(h)) {
    return {
      pillar: 'photo_suggest',
      mode: 'mock',
      category: 'homeRepair',
      category_label: LABELS.homeRepair,
      confidence: 0.7,
      title: 'Fix a broken household fitting',
      description:
        'Please repair the broken fitting shown in the photo. Bring basic tools if needed, explain the fix before starting, and leave the area tidy when done.',
      questions: [
        { id: 'access', prompt: 'Is the area accessible now?' },
        { id: 'parts', prompt: 'Should the helper buy replacement parts?' },
        { id: 'urgency', prompt: 'How urgent is this — today or this week?' },
      ],
      seen: ['Damaged fitting or fixture'],
      explanation:
        'Looks like a repair job — drafted home repair. Confirm access and parts before posting.',
    };
  }
  // Default stage demo: messy room → cleaning
  return {
    pillar: 'photo_suggest',
    mode: 'mock',
    category: 'homeCleaning',
    category_label: LABELS.homeCleaning,
    confidence: 0.78,
    title: 'Deep-clean this messy room',
    description:
      'Please deep-clean the room shown in the photo — sweep or mop floors, clear clutter surfaces, wipe dust, and tidy visible mess. Bring basic cleaning supplies unless I note that they are already at home.',
    questions: [
      {
        id: 'rooms',
        prompt: 'Is this one room only, or include adjoining spaces?',
      },
      {
        id: 'supplies',
        prompt: 'Are cleaning supplies already at home?',
      },
      {
        id: 'duration',
        prompt: 'About how long should the helper plan for?',
        hint: 'e.g. 1–2 hours',
      },
    ],
    seen: ['Cluttered or messy room', 'Household items on surfaces'],
    explanation:
      'Looks like a messy space that needs cleaning — drafted a home cleaning task. Confirm scope and supplies before posting.',
  };
}

function coerce(g: GeminiPhotoJson, mode: 'mock' | 'gemini'): PhotoSuggestResult {
  const category = normalizeCategory(g.category);
  const questions = (g.questions ?? [])
    .map((q, i) => ({
      id: (q.id || `q${i + 1}`).toString().slice(0, 40),
      prompt: (q.prompt || '').toString().trim(),
      hint: q.hint?.toString().trim() || undefined,
    }))
    .filter((q) => q.prompt.length > 0)
    .slice(0, 5);

  const title = (g.title || '').trim() || `Help with ${LABELS[category].toLowerCase()}`;
  let description = (g.description || '').trim();
  if (description.length < 40) {
    description =
      mockFromScene(category).description;
  }

  return {
    pillar: 'photo_suggest',
    mode,
    category,
    category_label: g.category_label?.trim() || LABELS[category],
    confidence: Math.max(0, Math.min(1, Number(g.confidence ?? 0.7))),
    title: title.slice(0, 80),
    description: description.slice(0, 1200),
    questions: questions.length
      ? questions
      : mockFromScene(category).questions,
    seen: (g.seen ?? []).map(String).filter(Boolean).slice(0, 6),
    explanation:
      (g.explanation || '').trim() ||
      `Suggested ${LABELS[category]} from your photo — review and edit before posting.`,
  };
}

function buildPrompt(): string {
  return `You are Zivo — a Sri Lanka hyperlocal help marketplace.
A client photographed a problem (messy room, broken fitting, shopping list, etc.).
Suggest ONE task category and draft a ready-to-post task they can confirm.

Allowed category values (exact camelCase):
${PHOTO_SUGGEST_CATEGORIES.join(', ')}

Return ONLY JSON:
{
  "category": "homeCleaning",
  "category_label": "Home Cleaning",
  "confidence": 0.0-1.0,
  "title": "short task title",
  "description": "clear 2-4 sentence brief for a helper (min ~40 chars)",
  "questions": [
    {"id":"rooms","prompt":"question the client should answer","hint":"optional hint"}
  ],
  "seen": ["what you see in the photo"],
  "explanation": "one short sentence why this category/draft"
}

Rules:
- Prefer practical household categories (homeCleaning, homeRepair, groceryRun, laundry, movingHelp, errandRun).
- Do not invent unsafe or illegal work.
- Questions must be relevant to THIS photo only (max 4).
- Description must be editable English the client can post as-is.`;
}

/** Photo → category + draft task + relevant confirm questions. */
export async function suggestFromPhoto(input: {
  imageBytes?: Buffer;
  mimeType?: string;
  hint?: string;
}): Promise<PhotoSuggestResult> {
  // Explicit mock-only path (local / Cup offline). Never pretend this is live vision.
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    const mock = mockFromScene(input.hint);
    return {
      ...mock,
      explanation: `${mock.explanation} (mock AI — set USE_MOCK_AI=false for live Gemini vision)`,
    };
  }

  if (!input.imageBytes?.length) {
    throw new Error('photo file required for live AI suggestion');
  }

  const prompt = buildPrompt();
  const mimeType = sniffImageMime(input.imageBytes, input.mimeType);
  // Prefer a vision-capable Flash model. Lite often lacks multimodal access.
  const primary =
    process.env.PHOTO_SUGGEST_MODEL?.trim() ||
    process.env.GEMINI_VISION_MODEL?.trim() ||
    'gemini-2.5-flash';
  const fallbackModel =
    process.env.GEMINI_MODEL?.trim() || 'gemini-2.5-flash-lite';

  const models = [...new Set([primary, fallbackModel].filter(Boolean))];
  let lastErr: unknown;
  for (const model of models) {
    try {
      const g = await generateGeminiMultimodalJson<GeminiPhotoJson>({
        prompt,
        imageBytes: input.imageBytes,
        mimeType,
        model,
      });
      const out = coerce(g, 'gemini');
      return models[0] === model
        ? out
        : {
            ...out,
            explanation: `${out.explanation} (via ${model})`,
          };
    } catch (err) {
      lastErr = err;
      console.error('[photo_suggest] vision failed', model, err);
    }
  }
  throw new Error(
    `Photo AI failed: ${
      lastErr instanceof Error ? lastErr.message : 'unknown error'
    }`,
  );
}
