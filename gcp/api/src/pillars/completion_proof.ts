import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiJson } from '../gemini.js';

export type ChecklistResult = {
  checklist: string[];
  mode: 'mock' | 'gemini';
};

const CATEGORY_DEFAULTS: Record<string, string[]> = {
  homeCleaning: [
    'Before photo of the area',
    'After photo of the cleaned area',
    'Trash / supplies put away',
  ],
  homeRepair: [
    'Before photo of the issue',
    'After photo showing the fix',
    'Tools cleared from the space',
  ],
  laundry: [
    'Before photo of clothes / load',
    'After photo of folded / hung items',
    'Detergent / machine left tidy',
  ],
  movingHelp: [
    'Before photo of items to move',
    'After photo at destination',
    'Pathway left clear',
  ],
  groceryRun: [
    'Till receipt photo',
    'Bag / goods photo',
    'Items match the shopping list',
  ],
  errandRun: [
    'Proof of pickup / drop-off',
    'After photo at destination',
    'Hand-off confirmed with client',
  ],
  queueStanding: [
    'Photo at the venue / queue',
    'Ticket or confirmation photo',
    'Client notified when done',
  ],
};

function mockChecklist(category: string, title: string): string[] {
  const base =
    CATEGORY_DEFAULTS[category] ??
    ([
      'Before photo',
      'After photo',
      'Work area left tidy',
    ] as string[]);
  if (title.trim()) {
    return [...base.slice(0, 2), `Done: ${title.trim().slice(0, 48)}`];
  }
  return base.slice(0, 4);
}

/** Short completion checklist for any job (grocery keeps receipt as step 1). */
export async function buildCompletionChecklist(input: {
  title: string;
  description: string;
  category: string;
  goodsBudget?: number;
}): Promise<ChecklistResult> {
  if (input.goodsBudget && input.goodsBudget > 0) {
    return {
      mode: 'mock',
      checklist: CATEGORY_DEFAULTS.groceryRun!,
    };
  }

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return {
      mode: 'mock',
      checklist: mockChecklist(input.category, input.title),
    };
  }

  try {
    const g = await generateGeminiJson<{ checklist: string[] }>(
      `You write a short completion checklist for a neighborhood helper job in Sri Lanka.
Return ONLY JSON: {"checklist":["...","..."]} with 3 to 5 short actionable items (photos / outcomes).
No brand names. No cash handoff. Category=${JSON.stringify(input.category)}
Title=${JSON.stringify(input.title)}
Description=${JSON.stringify(input.description.slice(0, 400))}`,
    );
    const list = (g.checklist ?? [])
      .map((s) => String(s).trim())
      .filter(Boolean)
      .slice(0, 5);
    if (list.length >= 2) {
      return { mode: 'gemini', checklist: list };
    }
  } catch {
    /* fall through */
  }
  return {
    mode: 'mock',
    checklist: mockChecklist(input.category, input.title),
  };
}
