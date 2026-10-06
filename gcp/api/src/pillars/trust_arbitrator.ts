import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiJson } from '../gemini.js';
import {
  getTask,
  getUser,
  listChatMessagesInternal,
  listVouchesForHelper,
  saveTrustReview,
  type TaskRow,
  type TrustReview,
} from '../store.js';

export type TrustVerdict = 'continue' | 'hold_escrow' | 'escalate';

export type TrustArbitratorResult = {
  pillar: 'trust_arbitrator';
  mode: 'mock' | 'gemini';
  verdict: TrustVerdict;
  confidence: number;
  /** Plain language for client + helper — no model brand names. */
  summary: string;
  /** What evidence drove the call (demo-friendly). */
  evidence_used: string[];
  concerns: string[];
  recommended_actions: string[];
  review: TrustReview;
};

type GeminiVerdict = {
  verdict: TrustVerdict;
  confidence: number;
  summary: string;
  concerns: string[];
  recommended_actions: string[];
  evidence_used: string[];
};

function buildTimeline(task: TaskRow): string[] {
  const lines = [
    `created ${task.created_at}`,
    `status ${task.status}`,
  ];
  if (task.helper_id) lines.push(`helper_assigned ${task.helper_id}`);
  if (task.deadline_at) lines.push(`deadline ${task.deadline_at}`);
  if (task.trust_hold) {
    lines.push(`trust_hold active: ${task.trust_hold_reason ?? 'yes'}`);
  }
  return lines;
}

function mockVerdict(input: {
  task: TaskRow;
  chatBodies: string[];
  receiptNote?: string;
}): GeminiVerdict {
  const chat = input.chatBodies.join(' ').toLowerCase();
  const offApp =
    /whatsapp|telegram|call me|cash outside|meet offline|no otp/i.test(chat);
  const receiptBad =
    !!input.receiptNote &&
    /mismatch|missing|discrepan|over.?budget|fraud/i.test(input.receiptNote);

  if (offApp && receiptBad) {
    return {
      verdict: 'escalate',
      confidence: 0.9,
      summary:
        'Chat suggests moving off-app and receipt evidence looks inconsistent — escalate for human review and keep escrow locked.',
      concerns: ['off_app_coordination', 'receipt_inconsistency'],
      recommended_actions: [
        'Keep escrow held',
        'Ask both parties to stay in Zivo chat',
        'Request clearer receipt photo',
      ],
      evidence_used: ['chat_transcript', 'receipt_signal', 'status_timeline'],
    };
  }
  if (offApp || receiptBad) {
    return {
      verdict: 'hold_escrow',
      confidence: 0.82,
      summary: offApp
        ? 'Chat shows an attempt to leave in-app coordination — hold escrow until both parties confirm the job on Zivo.'
        : 'Purchase proof looks inconsistent with the shopping list — hold escrow until clarified.',
      concerns: offApp ? ['off_app_coordination'] : ['receipt_inconsistency'],
      recommended_actions: [
        'Do not release End OTP yet',
        'Continue only in Zivo chat',
        'Re-upload receipt if needed',
      ],
      evidence_used: ['chat_transcript', 'receipt_signal', 'status_timeline'],
    };
  }
  return {
    verdict: 'continue',
    confidence: 0.78,
    summary:
      'No material trust risk in chat, timeline, or purchase signals — safe to continue the job on-platform.',
    concerns: [],
    recommended_actions: ['Continue in-app chat', 'Complete with OTPs as usual'],
    evidence_used: ['chat_transcript', 'status_timeline', 'vouch_context'],
  };
}

/**
 * Cup-unique: Gemini arbitrates a live job using the evidence pack
 * (chat + timeline + vouch + optional receipt note) — not a generic dispute form.
 */
export async function runTrustArbitrator(input: {
  taskId: string;
  requesterId: string;
  reason?: string;
  /** Optional last Pillar B explanation / verdict text. */
  receipt_note?: string;
}): Promise<TrustArbitratorResult> {
  const task = await getTask(input.taskId);
  if (!task) throw new Error('Task not found');
  if (task.client_id !== input.requesterId && task.helper_id !== input.requesterId) {
    throw new Error('Only the client or assigned helper can run a trust review');
  }
  if (!task.helper_id) {
    throw new Error('Trust review needs a matched helper');
  }

  const messages = await listChatMessagesInternal(input.taskId);
  const chatBodies = messages
    .filter((m) => m.sender_role !== 'system')
    .map((m) => `[${m.sender_role}] ${m.body}`);
  const vouches = await listVouchesForHelper(task.helper_id);
  const helper = await getUser(task.helper_id);
  const client = await getUser(task.client_id);
  const timeline = buildTimeline(task);

  const evidencePack = {
    task: {
      id: task.id,
      title: task.title,
      description: task.description.slice(0, 800),
      category: task.category,
      status: task.status,
      total_amount: task.total_amount,
      goods_budget: task.goods_budget,
      requires_purchase_proof: task.requires_purchase_proof,
      trust_hold: !!task.trust_hold,
    },
    parties: {
      client_name: client?.full_name ?? 'client',
      helper_name: helper?.full_name ?? 'helper',
      helper_vouch_count: helper?.vouch_count ?? vouches.length,
      helper_neighbor_vouched: !!helper?.neighbor_vouched,
      helper_rating: helper?.rating_as_helper ?? null,
    },
    timeline,
    chat_transcript: chatBodies.slice(-40),
    requester_reason: input.reason ?? '',
    receipt_note: input.receipt_note ?? '',
  };

  let mode: TrustArbitratorResult['mode'] = 'mock';
  let g: GeminiVerdict = mockVerdict({
    task,
    chatBodies,
    receiptNote: input.receipt_note,
  });

  if (!useMockAi && gcpProjectId && gcpProjectId !== 'your-gcp-project-id') {
    try {
      g = await generateGeminiJson<GeminiVerdict>(
        `You are Zivo's Trust Arbitrator for a Sri Lanka neighborhood help marketplace.
You are NOT a chatbot and NOT a generic dispute form. You must decide from the EVIDENCE PACK only.

Competitors (Airtasker/TaskRabbit) have human tickets — you produce an on-platform AI verdict that can HOLD ESCROW.

Rules:
- Prefer hold_escrow when chat shows off-app contact / cash outside escrow / "skip OTP".
- Prefer escalate when receipt signals + chat both look adversarial.
- Prefer continue when evidence is ordinary neighborhood help.
- Never mention model names. Write for both client and helper.
- confidence 0..1.

EVIDENCE PACK:
${JSON.stringify(evidencePack)}

Return ONLY JSON:
{
  "verdict": "continue"|"hold_escrow"|"escalate",
  "confidence": number,
  "summary": "2 sentences plain language",
  "concerns": string[],
  "recommended_actions": string[],
  "evidence_used": string[]
}`,
      );
      if (
        g.verdict !== 'continue' &&
        g.verdict !== 'hold_escrow' &&
        g.verdict !== 'escalate'
      ) {
        g.verdict = 'hold_escrow';
      }
      mode = 'gemini';
    } catch {
      /* mock still protects escrow */
    }
  }

  const now = new Date().toISOString();
  const review: TrustReview = {
    id: `tr_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
    task_id: task.id,
    requester_id: input.requesterId,
    verdict: g.verdict,
    confidence: Math.max(0, Math.min(1, Number(g.confidence) || 0.7)),
    summary: (g.summary || 'Trust review complete')
      .replace(/\bgemini\b/gi, 'fair trust review')
      .slice(0, 800),
    concerns: g.concerns ?? [],
    recommended_actions: g.recommended_actions ?? [],
    evidence_used: g.evidence_used ?? ['chat_transcript', 'status_timeline'],
    created_at: now,
    mode,
  };

  await saveTrustReview(review, {
    applyHold: g.verdict === 'hold_escrow' || g.verdict === 'escalate',
    escalate: g.verdict === 'escalate',
    reason: review.summary,
  });

  return {
    pillar: 'trust_arbitrator',
    mode,
    verdict: g.verdict,
    confidence: review.confidence,
    summary: review.summary,
    evidence_used: review.evidence_used,
    concerns: review.concerns,
    recommended_actions: review.recommended_actions,
    review,
  };
}
