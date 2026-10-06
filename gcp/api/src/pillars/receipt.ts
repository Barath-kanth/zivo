import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiMultimodalJson } from '../gemini.js';
import type { Task } from './receipt_types.js';

export type { Task } from './receipt_types.js';

export type ReceiptInput = {
  task: Task;
  shoppingList: string;
  imageBytes?: Buffer;
  mimeType?: string;
};

export type ReceiptResult = {
  pillar: 'B';
  mode: 'mock' | 'gemini';
  /** Award demo structured fields */
  items_matched: string[];
  items_missing: string[];
  price_anomalies: string[];
  total_vs_budget: {
    receipt_total_lkr: number;
    budget_lkr: number;
    delta_lkr: number;
    within_budget: boolean;
  };
  verdict: 'pass' | 'fail' | 'review';
  explanation: string;
  research_note: string;
  /** Compat aliases used by older clients */
  itemsFound: string[];
  missingVsList: string[];
  receiptTotalLkr: number;
  arithmeticOk: boolean;
  withinBudget: boolean;
  notes: string[];
};

type GeminiReceiptJson = {
  items_matched: string[];
  items_missing: string[];
  price_anomalies: string[];
  receipt_total_lkr: number;
  within_budget: boolean;
  verdict: 'pass' | 'fail' | 'review';
  explanation: string;
};

const RESEARCH =
  'ReceiptBench (ACL 2026) / CC-OCR v2: messy physical receipts break naive OCR; Zivo frames list↔receipt↔budget reconciliation as the Cup gap this multimodal verdict addresses.';

function parseList(shoppingList: string): string[] {
  return shoppingList
    .split(/[,\n;]+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function toResult(
  mode: 'mock' | 'gemini',
  g: GeminiReceiptJson,
  budget: number,
): ReceiptResult {
  const total = Number.isFinite(g.receipt_total_lkr) ? g.receipt_total_lkr : 0;
  const within =
    typeof g.within_budget === 'boolean' ? g.within_budget : total <= budget;
  const matched = g.items_matched ?? [];
  const missing = g.items_missing ?? [];
  const anomalies = g.price_anomalies ?? [];
  const verdict =
    g.verdict === 'pass' || g.verdict === 'fail' || g.verdict === 'review'
      ? g.verdict
      : within && missing.length === 0
        ? 'pass'
        : 'fail';

  return {
    pillar: 'B',
    mode,
    items_matched: matched,
    items_missing: missing,
    price_anomalies: anomalies,
    total_vs_budget: {
      receipt_total_lkr: total,
      budget_lkr: budget,
      delta_lkr: Math.round((total - budget) * 100) / 100,
      within_budget: within,
    },
    verdict,
    explanation: g.explanation || 'Receipt reconciliation complete.',
    research_note: RESEARCH,
    itemsFound: matched,
    missingVsList: missing,
    receiptTotalLkr: total,
    arithmeticOk: anomalies.length === 0,
    withinBudget: within,
    notes: [g.explanation || 'OK', ...anomalies.slice(0, 3)],
  };
}

function mockReceipt(input: ReceiptInput): ReceiptResult {
  const listItems = parseList(input.shoppingList);
  const found = listItems.length
    ? listItems.slice(0, Math.max(1, listItems.length - 1))
    : ['rice', 'eggs'];
  const missing = listItems.filter(
    (i) => !found.some((f) => f.toLowerCase() === i.toLowerCase()),
  );
  const budget = input.task.goodsBudgetLkr || 2000;
  // Demo beat: invent a subtle overcharge a human might miss
  const receiptTotalLkr = Math.round(budget * 0.92) + 47;
  const anomalies =
    missing.length || receiptTotalLkr > budget
      ? [`Line-item total drift: receipt ${receiptTotalLkr} vs budget ${budget}`]
      : ['Unit price on milk looks ~LKR 15 above typical Keells shelf'];

  return toResult('mock', {
    items_matched: found,
    items_missing: missing.length ? missing : listItems.slice(-1),
    price_anomalies: anomalies,
    receipt_total_lkr: receiptTotalLkr,
    within_budget: receiptTotalLkr <= budget,
    verdict: 'fail',
    explanation: input.imageBytes?.length
      ? 'Mock multimodal: photo received; simulated discrepancy (missing list item + total drift) — enable Gemini for live OCR reconciliation.'
      : 'Mock multimodal: no receipt photo; simulated missing item + subtle total drift for demo.',
  }, budget);
}

function buildPrompt(input: ReceiptInput): string {
  const budget = input.task.goodsBudgetLkr || 0;
  return `You are Zivo Pillar B — multimodal receipt-vs-list reconciliation for a Sri Lanka hyperlocal grocery helper marketplace.

INPUTS:
1) Photo of a real physical receipt (may be crumpled, tilted, noisy, low light).
2) Original shopping / item list from the client.
3) Goods budget in LKR.

TASK:
- Read the receipt natively (do not assume clean OCR).
- Match line items to the shopping list (fuzzy names OK: "fresh milk" ≈ "Milk 1L").
- Flag items on the list missing from the receipt.
- Flag price anomalies (odd unit prices, duplicate lines, arithmetic that does not add up).
- Compare receipt grand total vs goods budget.

Shopping list:
${JSON.stringify(input.shoppingList)}

Goods budget (LKR): ${budget}
Task title: ${JSON.stringify(input.task.title)}
Task description (may contain list context): ${JSON.stringify(input.task.description)}

Return ONLY JSON:
{
  "items_matched": string[],
  "items_missing": string[],
  "price_anomalies": string[],
  "receipt_total_lkr": number,
  "within_budget": boolean,
  "verdict": "pass" | "fail" | "review",
  "explanation": string
}

Verdict guide:
- pass: all list items matched (or justified substitutes), total within budget, no serious anomalies
- fail: missing critical items OR over budget OR clear fraud/arithmetic break
- review: ambiguous OCR / partial match needing human eyes`;
}

/** Pillar B — multimodal receipt ↔ list ↔ budget reconciliation. */
export async function reconcileReceipt(input: ReceiptInput): Promise<ReceiptResult> {
  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return mockReceipt(input);
  }

  if (!input.imageBytes?.length) {
    const fallback = mockReceipt(input);
    return {
      ...fallback,
      explanation:
        'No receipt image uploaded — ran mock discrepancy demo. Photograph a real receipt for live Gemini multimodal.',
      notes: [
        'No receipt image — mock path',
        ...fallback.notes,
      ],
    };
  }

  try {
    const g = await generateGeminiMultimodalJson<GeminiReceiptJson>({
      prompt: buildPrompt(input),
      imageBytes: input.imageBytes,
      mimeType: input.mimeType || 'image/jpeg',
    });
    return toResult('gemini', g, input.task.goodsBudgetLkr || 0);
  } catch (err) {
    const fallback = mockReceipt(input);
    return {
      ...fallback,
      mode: 'mock',
      explanation: `${fallback.explanation} Gemini unavailable: ${
        err instanceof Error ? err.message : 'error'
      }`,
      notes: [
        ...fallback.notes,
        `Gemini error: ${err instanceof Error ? err.message : 'error'}`,
      ],
    };
  }
}
