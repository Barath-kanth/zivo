import { useMockAi } from '../config.js';
import type { Task } from './receipt_types.js';

// Re-export thin task shape for receipt pillar (compat with multimodal mock).
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
  itemsFound: string[];
  missingVsList: string[];
  receiptTotalLkr: number;
  arithmeticOk: boolean;
  withinBudget: boolean;
  notes: string[];
};

function mockReceipt(input: ReceiptInput): ReceiptResult {
  const listItems = input.shoppingList
    .split(/[,\n]/)
    .map((s) => s.trim())
    .filter(Boolean);
  const found = listItems.length
    ? listItems.slice(0, Math.max(1, listItems.length - 1))
    : ['rice', 'eggs'];
  const missing = listItems.filter(
    (i) => !found.some((f) => f.toLowerCase() === i.toLowerCase()),
  );
  const receiptTotalLkr = Math.round(input.task.goodsBudgetLkr * 0.85) || 1200;
  return {
    pillar: 'B',
    mode: 'mock',
    itemsFound: found,
    missingVsList: missing,
    receiptTotalLkr,
    arithmeticOk: true,
    withinBudget: receiptTotalLkr <= input.task.goodsBudgetLkr,
    notes: [
      input.imageBytes
        ? 'Image received — wire Gemini multimodal for Cup'
        : 'Mock reconciliation (no cash to helpers)',
      'Reimburse min(receipt, goods budget)',
    ],
  };
}

export async function reconcileReceipt(input: ReceiptInput): Promise<ReceiptResult> {
  if (useMockAi || !input.imageBytes || !process.env.GCP_PROJECT_ID) {
    return mockReceipt(input);
  }
  return mockReceipt(input);
}
