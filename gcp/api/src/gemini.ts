import {
  GoogleGenAI,
  FunctionCallingConfigMode,
  type Content,
  type FunctionDeclaration,
  type Part,
} from '@google/genai';
import { gcpProjectId, geminiModel } from './config.js';
import { sniffImageMime } from './image_mime.js';

/** Vertex region for Gemini (often us-central1 even if Run is asia-south1). */
export const vertexLocation = process.env.VERTEX_LOCATION?.trim() || 'us-central1';

/**
 * Multi-region Vertex routing. Gemini quota is per model *per region*, and a new project's
 * per-minute quota is small (a single 429 in us-central1 used to stall a user for minutes).
 * Calls are spread round-robin over healthy regions; a region that returns 429/503 is put on a
 * short cool-down and the SAME request is immediately retried in the next region.
 * Override with VERTEX_LOCATIONS="us-central1,us-east4,…" (e.g. one region for data residency).
 */
const DEFAULT_REGIONS = ['us-central1', 'us-east4', 'us-east1', 'europe-west1'];
const REGIONS: string[] = (
  process.env.VERTEX_LOCATIONS
    ? process.env.VERTEX_LOCATIONS.split(',').map((r) => r.trim()).filter(Boolean)
    : [...new Set([process.env.VERTEX_LOCATION?.trim() || 'us-central1', ...DEFAULT_REGIONS])]
).slice(0, 6);
const COOLDOWN_MS = Number(process.env.VERTEX_COOLDOWN_MS ?? 20000);
const regionClients = new Map<string, GoogleGenAI>();
const coolingUntil = new Map<string, number>();
let rr = 0;

/** Google Gen AI SDK (`@google/genai`) in Vertex AI mode — the supported successor of `@google-cloud/vertexai`. */
function clientFor(region: string): GoogleGenAI {
  let c = regionClients.get(region);
  if (!c) {
    c = new GoogleGenAI({ vertexai: true, project: gcpProjectId, location: region });
    regionClients.set(region, c);
  }
  return c;
}

/** Regions to try for one request: healthy ones first (rotated), cooling ones last. */
function regionOrder(): string[] {
  const now = Date.now();
  const start = rr++ % REGIONS.length;
  const rotated = [...REGIONS.slice(start), ...REGIONS.slice(0, start)];
  const healthy = rotated.filter((r) => (coolingUntil.get(r) ?? 0) <= now);
  const cooling = rotated.filter((r) => (coolingUntil.get(r) ?? 0) > now);
  return [...healthy, ...cooling];
}

const QUOTA_ERR = /\b(429|503)\b|RESOURCE_EXHAUSTED|UNAVAILABLE/i;

type ModelConfig = {
  model: string;
  generationConfig?: Record<string, unknown>;
  tools?: Array<{ functionDeclarations: FunctionDeclaration[] }>;
  toolConfig?: { functionCallingConfig: { mode: FunctionCallingConfigMode } };
  systemInstruction?: { role?: string; parts: Array<{ text: string }> };
};
type GenResult = { response: { candidates?: Array<{ content?: { parts?: Part[] } }> } };

/**
 * Thin adapter over `ai.models.generateContent` that keeps the call shape the pillars use
 * (`getGenerativeModel(cfg).generateContent({contents})`) and adds region failover inside.
 */
function getVertex() {
  return {
    getGenerativeModel(cfg: ModelConfig) {
      return {
        async generateContent(req: { contents: Content[] }): Promise<GenResult> {
          let lastErr: unknown;
          for (const region of regionOrder()) {
            try {
              const out = await clientFor(region).models.generateContent({
                model: cfg.model,
                contents: req.contents,
                config: {
                  ...(cfg.generationConfig ?? {}),
                  ...(cfg.tools ? { tools: cfg.tools } : {}),
                  ...(cfg.toolConfig ? { toolConfig: cfg.toolConfig } : {}),
                  ...(cfg.systemInstruction
                    ? { systemInstruction: cfg.systemInstruction.parts.map((p) => p.text).join('\n') }
                    : {}),
                },
              });
              if (process.env.GEMINI_TRACE) console.log(`[gemini] ${region}`);
              return { response: { candidates: out.candidates } };
            } catch (err) {
              lastErr = err;
              const msg = err instanceof Error ? err.message : String(err);
              if (!QUOTA_ERR.test(msg)) throw err; // real error: do not hide it behind a failover
              coolingUntil.set(region, Date.now() + COOLDOWN_MS);
              console.warn(`[gemini] ${region} quota/unavailable — failing over`);
            }
          }
          throw lastErr;
        },
      };
    },
  };
}

/**
 * Vertex returns 429 RESOURCE_EXHAUSTED / 503 under burst load (new projects have
 * small per-minute quotas). Retry with exponential backoff + jitter so a brief
 * spike degrades to "a bit slower" instead of silently falling back to mock output.
 */
export async function withRetry<T>(fn: () => Promise<T>, attempts = 4): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const msg = err instanceof Error ? err.message : String(err);
      const transient = /\b(429|503|500)\b|RESOURCE_EXHAUSTED|UNAVAILABLE|ECONNRESET|ETIMEDOUT|fetch failed/i.test(msg);
      if (!transient || i === attempts - 1) throw err;
      const wait = 700 * 2 ** i + Math.random() * 400;
      await new Promise((r) => setTimeout(r, wait));
    }
  }
  throw lastErr;
}

export async function generateGeminiText(prompt: string): Promise<string> {
  const model = getVertex().getGenerativeModel({
    model: geminiModel,
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1024,
      responseMimeType: 'application/json',
    },
  });
  const result = await withRetry(() =>
    model.generateContent({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
    }),
  );
  const text =
    result.response.candidates?.[0]?.content?.parts
      ?.map((p) => ('text' in p ? p.text : ''))
      .join('') ?? '';
  return text.trim();
}

export async function generateGeminiJson<T>(prompt: string): Promise<T> {
  const raw = await generateGeminiText(prompt);
  const cleaned = raw
    .replace(/^```json\s*/i, '')
    .replace(/```$/i, '')
    .replace(/[\u0000-\u001F]+/g, ' ')
    .trim();
  return JSON.parse(cleaned) as T;
}

export async function generateGeminiMultimodalJson<T>(input: {
  prompt: string;
  imageBytes?: Buffer;
  mimeType?: string;
  /** Optional model override (e.g. vision fallback). */
  model?: string;
  /** 2.5-flash "thinking" tokens; 0 = off (≈3× faster for short classification calls). */
  thinkingBudget?: number;
}): Promise<T> {
  const parts: Array<
    { text: string } | { inlineData: { data: string; mimeType: string } }
  > = [];
  // Media first — multimodal models ground better when vision/audio leads.
  // Vertex rejects application/octet-stream for images; sniff images only.
  if (input.imageBytes?.length) {
    const declared = input.mimeType?.trim() || '';
    const mimeType = declared.startsWith('audio/')
      ? declared
      : sniffImageMime(input.imageBytes, input.mimeType);
    parts.push({
      inlineData: {
        data: input.imageBytes.toString('base64'),
        mimeType,
      },
    });
  }
  parts.push({ text: input.prompt });

  const build = (name: string) =>
    getVertex().getGenerativeModel({
      model: name,
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 2048,
        responseMimeType: 'application/json',
        // Only 2.5-flash accepts a zero budget; flash-lite ignores thinking by default.
        ...(input.thinkingBudget !== undefined && name.includes('2.5-flash') && !name.includes('lite')
          ? { thinkingConfig: { thinkingBudget: input.thinkingBudget } }
          : {}),
      } as Record<string, unknown>,
    });
  const primary = input.model?.trim() || geminiModel;
  let result;
  try {
    // Fewer retries on the bigger model when a cheaper one can take over:
    // each Gemini model has its own per-minute quota bucket.
    result = await withRetry(
      () => build(primary).generateContent({ contents: [{ role: 'user', parts }] }),
      primary === geminiModel ? 4 : 2,
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (primary === geminiModel || !/\b(429|503)\b|RESOURCE_EXHAUSTED|UNAVAILABLE/i.test(msg)) {
      throw err;
    }
    console.warn(`[gemini] ${primary} exhausted, falling back to ${geminiModel}`);
    result = await withRetry(() =>
      build(geminiModel).generateContent({ contents: [{ role: 'user', parts }] }),
    );
  }
  const text =
    result.response.candidates?.[0]?.content?.parts
      ?.map((p) => ('text' in p ? p.text : ''))
      .join('') ?? '';
  if (!text.trim()) {
    throw new Error('Gemini returned an empty vision response');
  }
  const cleaned = text
    .replace(/^```json\s*/i, '')
    .replace(/^```\s*/i, '')
    .replace(/```$/i, '')
    .trim();
  const brace = cleaned.match(/\{[\s\S]*\}/);
  const jsonText = brace?.[0] ?? cleaned;
  try {
    return JSON.parse(jsonText) as T;
  } catch (err) {
    throw new Error(
      `Gemini vision JSON parse failed: ${
        err instanceof Error ? err.message : 'error'
      } · snippet=${jsonText.slice(0, 180)}`,
    );
  }
}

function parseLooseJson<T>(text: string): T {
  const cleaned = text
    .replace(/^```json\s*/i, '')
    .replace(/^```\s*/i, '')
    .replace(/```$/i, '')
    .trim();
  const brace = cleaned.match(/\{[\s\S]*\}/);
  return JSON.parse(brace?.[0] ?? cleaned) as T;
}

/**
 * Latency-first Gemini JSON call. Each Gemini model has its own per-minute quota bucket and
 * Vertex can stall for a minute or more under 429s, so instead of "retry the same model with
 * back-off" this races models: start `models[0]`; if it has not answered after `hedgeMs` (or fails
 * at once) start the next one in parallel; first valid JSON wins; hard `timeoutMs` ceiling.
 */
export async function generateGeminiRace<T>(input: {
  prompt: string;
  media?: Buffer;
  mimeType?: string;
  models: string[];
  hedgeMs?: number;
  timeoutMs?: number;
  thinkingBudget?: number;
  maxOutputTokens?: number;
}): Promise<{ value: T; model: string; ms: number }> {
  const started = Date.now();
  const hedgeMs = input.hedgeMs ?? 4500;
  const timeoutMs = input.timeoutMs ?? 20000;
  const parts: Part[] = [];
  if (input.media?.length) {
    const declared = input.mimeType?.trim() || '';
    parts.push({
      inlineData: {
        data: input.media.toString('base64'),
        mimeType: declared.startsWith('audio/')
          ? declared
          : sniffImageMime(input.media, input.mimeType),
      },
    });
  }
  parts.push({ text: input.prompt });

  const attempt = async (name: string): Promise<{ value: T; model: string; ms: number }> => {
    const model = getVertex().getGenerativeModel({
      model: name,
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: input.maxOutputTokens ?? 2048,
        responseMimeType: 'application/json',
        ...(input.thinkingBudget !== undefined && name.includes('2.5-flash') && !name.includes('lite')
          ? { thinkingConfig: { thinkingBudget: input.thinkingBudget } }
          : {}),
      } as Record<string, unknown>,
    });
    // One quick retry only; the race provides the real redundancy.
    const result = await withRetry(
      () => model.generateContent({ contents: [{ role: 'user', parts }] }),
      2,
    );
    const text =
      result.response.candidates?.[0]?.content?.parts
        ?.map((p) => ('text' in p ? p.text : ''))
        .join('') ?? '';
    if (!text.trim()) throw new Error(`${name}: empty response`);
    return { value: parseLooseJson<T>(text), model: name, ms: Date.now() - started };
  };

  return new Promise((resolve, reject) => {
    let launched = 0;
    let failed = 0;
    let done = false;
    const errors: string[] = [];
    const timers: NodeJS.Timeout[] = [];
    const finish = (fn: () => void) => {
      if (done) return;
      done = true;
      timers.forEach(clearTimeout);
      fn();
    };
    const launch = () => {
      if (done || launched >= input.models.length) return;
      const name = input.models[launched++];
      attempt(name).then(
        (r) => finish(() => resolve(r)),
        (err) => {
          errors.push(`${name}: ${err instanceof Error ? err.message.slice(0, 120) : err}`);
          failed += 1;
          if (failed >= input.models.length) {
            finish(() => reject(new Error(errors.join(' | '))));
          } else {
            launch(); // fail fast to the next model instead of waiting for the hedge timer
          }
        },
      );
      if (launched < input.models.length) timers.push(setTimeout(launch, hedgeMs));
    };
    timers.push(
      setTimeout(
        () => finish(() => reject(new Error(`Gemini timed out after ${timeoutMs} ms (${errors.join(' | ') || 'no error'})`))),
        timeoutMs,
      ),
    );
    launch();
  });
}

export type ToolHandler = (
  name: string,
  args: Record<string, unknown>,
) => Promise<unknown> | unknown;

/** Multi-turn Gemini function-calling loop over deterministic tools. */
export async function generateWithTools(input: {
  systemPrompt: string;
  userPrompt: string;
  tools: FunctionDeclaration[];
  handler: ToolHandler;
  maxTurns?: number;
  /** Override the forced final turn prompt (default is match-helper JSON). */
  finalPrompt?: string;
}): Promise<{ text: string; toolTrace: Array<{ name: string; args: unknown; result: unknown }> }> {
  const model = getVertex().getGenerativeModel({
    model: geminiModel,
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1024,
    },
    tools: [{ functionDeclarations: input.tools }],
    toolConfig: {
      functionCallingConfig: { mode: FunctionCallingConfigMode.AUTO },
    },
    systemInstruction: {
      role: 'system',
      parts: [{ text: input.systemPrompt }],
    },
  });

  const contents: Content[] = [
    { role: 'user', parts: [{ text: input.userPrompt }] },
  ];
  const toolTrace: Array<{ name: string; args: unknown; result: unknown }> = [];
  const maxTurns = input.maxTurns ?? 6;

  for (let turn = 0; turn < maxTurns; turn++) {
    const turnStart = Date.now();
    const result = await withRetry(() => model.generateContent({ contents }));
    if (process.env.GEMINI_TRACE) console.log(`[gemini] tool-loop turn ${turn} model ${Date.now() - turnStart} ms`);
    const candidate = result.response.candidates?.[0];
    const parts = candidate?.content?.parts ?? [];
    const functionCalls = parts.filter(
      (p): p is Part & { functionCall: { name: string; args?: object } } =>
        Boolean(p.functionCall?.name),
    );

    if (!functionCalls.length) {
      const text = parts
        .map((p) => ('text' in p && p.text ? p.text : ''))
        .join('')
        .trim();
      return { text, toolTrace };
    }

    contents.push({ role: 'model', parts });

    // Gemini may emit several independent calls in one turn — run them concurrently.
    const executed = await Promise.all(
      functionCalls.map(async (part) => {
        const name = part.functionCall.name;
        const args = (part.functionCall.args ?? {}) as Record<string, unknown>;
        const toolStart = Date.now();
        const toolResult = await input.handler(name, args);
        if (process.env.GEMINI_TRACE) console.log(`[gemini] tool ${name} ${Date.now() - toolStart} ms`);
        return { name, args, toolResult };
      }),
    );
    const responseParts: Part[] = [];
    for (const { name, args, toolResult } of executed) {
      toolTrace.push({ name, args, result: toolResult });
      responseParts.push({
        functionResponse: {
          name,
          response: { result: toolResult },
        },
      });
    }
    contents.push({ role: 'user', parts: responseParts });
  }

  // Force a final natural-language/JSON answer without more tool calls.
  const finalModel = getVertex().getGenerativeModel({
    model: geminiModel,
    generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
    toolConfig: {
      functionCallingConfig: { mode: FunctionCallingConfigMode.NONE },
    },
    systemInstruction: {
      role: 'system',
      parts: [{ text: input.systemPrompt }],
    },
  });
  contents.push({
    role: 'user',
    parts: [
      {
        text:
          input.finalPrompt?.trim() ||
          'Using the tool results above, reply with ONLY JSON: {"selected_helper_id":"...","explanation":"..."}',
      },
    ],
  });
  const final = await withRetry(() => finalModel.generateContent({ contents }));
  const finalText =
    final.response.candidates?.[0]?.content?.parts
      ?.map((p) => ('text' in p && p.text ? p.text : ''))
      .join('')
      .trim() ?? '';
  return { text: finalText, toolTrace };
}

/** Regions this instance spreads Gemini calls over (for /health). */
export const vertexRegionList = (): string[] => [...REGIONS];
