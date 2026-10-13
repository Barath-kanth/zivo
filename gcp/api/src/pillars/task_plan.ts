import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiJson } from '../gemini.js';
import { PHOTO_SUGGEST_CATEGORIES } from './photo_suggest.js';

export type PlanTaskDraft = {
  title: string;
  category: string;
  description: string;
  estimated_hours: number;
  goods_budget: number;
};

export type TaskPlanResult = {
  pillar: 'task_plan';
  mode: 'mock' | 'gemini';
  problem: string;
  bundle_title: string;
  explanation: string;
  tasks: PlanTaskDraft[];
};

const ALLOWED = new Set<string>(PHOTO_SUGGEST_CATEGORIES);

function mockPlan(problem: string, categoryHint?: string): TaskPlanResult {
  const p = problem.toLowerCase();
  const isMoving =
    /mov|shift|pack|furniture|house|apartment|flat/.test(p) ||
    categoryHint === 'movingHelp';
  const isParty = /party|event|birthday|wedding/.test(p);
  const isClean = /clean|mess|spring/.test(p);

  if (isMoving) {
    return {
      pillar: 'task_plan',
      mode: 'mock',
      problem,
      bundle_title: 'Moving help bundle',
      explanation:
        'One moving day often needs pack, load, and a quick clean — posted as linked tasks with one checkout.',
      tasks: [
        {
          title: 'Pack boxes and label rooms',
          category: 'movingHelp',
          description:
            'Pack fragile and everyday items into boxes, label by room, and stage near the exit. About 2 hours.',
          estimated_hours: 2,
          goods_budget: 0,
        },
        {
          title: 'Load and unload furniture',
          category: 'movingHelp',
          description:
            'Carry furniture and boxes to the vehicle and into the new place. Stairs possible. About 2 hours.',
          estimated_hours: 2,
          goods_budget: 0,
        },
        {
          title: 'Quick clean after move-out',
          category: 'homeCleaning',
          description:
            'Sweep and mop the emptied rooms so the old place is left tidy. About 1 hour.',
          estimated_hours: 1,
          goods_budget: 0,
        },
      ],
    };
  }

  if (isParty) {
    return {
      pillar: 'task_plan',
      mode: 'mock',
      problem,
      bundle_title: 'Event help bundle',
      explanation: 'Setup, serving, and cleanup split into separate helper jobs.',
      tasks: [
        {
          title: 'Set up tables and decorations',
          category: 'eventHelp',
          description:
            'Arrange seating, decorations and serving stations before guests arrive. About 1.5 hours.',
          estimated_hours: 1.5,
          goods_budget: 0,
        },
        {
          title: 'Buy party supplies',
          category: 'groceryRun',
          description:
            'Buy listed snacks, drinks and disposables from a nearby shop. Keep receipt for escrow. About 1 hour.',
          estimated_hours: 1,
          goods_budget: 5000,
        },
        {
          title: 'Clean up after the event',
          category: 'homeCleaning',
          description:
            'Clear trash, wipe surfaces and pack leftover decorations. About 1 hour.',
          estimated_hours: 1,
          goods_budget: 0,
        },
      ],
    };
  }

  if (isClean) {
    return {
      pillar: 'task_plan',
      mode: 'mock',
      problem,
      bundle_title: 'Home clean-up bundle',
      explanation: 'Split deep clean into room-focused tasks so helpers can parallelize.',
      tasks: [
        {
          title: 'Deep clean kitchen',
          category: 'homeCleaning',
          description:
            'Clean counters, sink, stove and floor. Supplies available at home. About 1.5 hours.',
          estimated_hours: 1.5,
          goods_budget: 0,
        },
        {
          title: 'Deep clean bathrooms',
          category: 'homeCleaning',
          description:
            'Scrub bathroom fixtures and floors. About 1 hour.',
          estimated_hours: 1,
          goods_budget: 0,
        },
      ],
    };
  }

  const cat =
    categoryHint && ALLOWED.has(categoryHint) ? categoryHint : 'errandRun';
  return {
    pillar: 'task_plan',
    mode: 'mock',
    problem,
    bundle_title: 'Related help bundle',
    explanation:
      'Broke your problem into a few short nearby tasks you can post together.',
    tasks: [
      {
        title: problem.trim().slice(0, 60) || 'Main help needed',
        category: cat,
        description:
          `${problem.trim()} Please complete this as the primary request. About 1 hour.`,
        estimated_hours: 1,
        goods_budget: cat === 'groceryRun' ? 2500 : 0,
      },
      {
        title: 'Follow-up support nearby',
        category: 'errandRun',
        description:
          'Related follow-up errand connected to the main request. Confirm details in chat. About 45 minutes.',
        estimated_hours: 0.75,
        goods_budget: 0,
      },
    ],
  };
}

function coerceTasks(raw: unknown[]): PlanTaskDraft[] {
  const out: PlanTaskDraft[] = [];
  for (const item of raw.slice(0, 6)) {
    if (!item || typeof item !== 'object') continue;
    const t = item as Record<string, unknown>;
    const category =
      typeof t.category === 'string' && ALLOWED.has(t.category)
        ? t.category
        : 'errandRun';
    const title = String(t.title ?? 'Help nearby').trim().slice(0, 80);
    const description = String(t.description ?? '')
      .trim()
      .slice(0, 800);
    if (description.length < 20) continue;
    const hours = Number(t.estimated_hours);
    const goods = Number(t.goods_budget);
    out.push({
      title: title || 'Help nearby',
      category,
      description,
      estimated_hours: Number.isFinite(hours)
        ? Math.min(6, Math.max(0.5, hours))
        : 1,
      goods_budget: Number.isFinite(goods)
        ? Math.min(50000, Math.max(0, goods))
        : 0,
    });
  }
  return out;
}

/** One problem → several related task drafts (Gemini). */
export async function planTaskBundle(input: {
  problem: string;
  category_hint?: string;
  lang?: string;
}): Promise<TaskPlanResult> {
  const problem = input.problem.trim();
  if (problem.length < 12) {
    throw new Error('Describe the full problem (at least 12 characters)');
  }

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return mockPlan(problem, input.category_hint);
  }

  const g = await generateGeminiJson<{
    bundle_title?: string;
    explanation?: string;
    tasks?: unknown[];
  }>(
    `You plan neighborhood-help tasks for Zivo (Sri Lanka).
Split ONE real-world problem into 2–5 short, bookable helper tasks.
Each task must be independently completable by a local helper.
Categories must be one of: ${[...ALLOWED].join('|')}
Return ONLY JSON:
{"bundle_title":"...","explanation":"1 sentence","tasks":[{"title":"...","category":"...","description":"2-4 sentences","estimated_hours":1,"goods_budget":0}]}
Rules: no illegal work; goods_budget only for grocery/errand shopping; keep practical.
Problem: ${JSON.stringify(problem)}
Category hint: ${JSON.stringify(input.category_hint ?? '')}`,
  );

  const tasks = coerceTasks(Array.isArray(g.tasks) ? g.tasks : []);
  if (tasks.length < 2) {
    return mockPlan(problem, input.category_hint);
  }

  return {
    pillar: 'task_plan',
    mode: 'gemini',
    problem,
    bundle_title: (g.bundle_title ?? 'Help bundle').trim().slice(0, 80),
    explanation: (g.explanation ?? 'Split into related tasks.').trim().slice(0, 240),
    tasks,
  };
}
