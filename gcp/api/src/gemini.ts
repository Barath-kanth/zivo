import {
  VertexAI,
  type Content,
  type FunctionDeclaration,
  type Part,
  FunctionCallingMode,
} from '@google-cloud/vertexai';
import { gcpProjectId, geminiModel } from './config.js';
import { sniffImageMime } from './image_mime.js';

/** Vertex region for Gemini (often us-central1 even if Run is asia-south1). */
export const vertexLocation =
  process.env.VERTEX_LOCATION?.trim() || 'us-central1';

let client: VertexAI | null = null;

function getVertex(): VertexAI {
  if (!client) {
    client = new VertexAI({
      project: gcpProjectId,
      location: vertexLocation,
    });
  }
  return client;
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
  const result = await model.generateContent({
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
  });
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

  const model = getVertex().getGenerativeModel({
    model: input.model?.trim() || geminiModel,
    generationConfig: {
      temperature: 0.1,
      maxOutputTokens: 2048,
      responseMimeType: 'application/json',
    },
  });
  const result = await model.generateContent({
    contents: [{ role: 'user', parts }],
  });
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
}): Promise<{ text: string; toolTrace: Array<{ name: string; args: unknown; result: unknown }> }> {
  const model = getVertex().getGenerativeModel({
    model: geminiModel,
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1024,
    },
    tools: [{ functionDeclarations: input.tools }],
    toolConfig: {
      functionCallingConfig: { mode: FunctionCallingMode.AUTO },
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
    const result = await model.generateContent({ contents });
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

    const responseParts: Part[] = [];
    for (const part of functionCalls) {
      const name = part.functionCall.name;
      const args = (part.functionCall.args ?? {}) as Record<string, unknown>;
      const toolResult = await input.handler(name, args);
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
      functionCallingConfig: { mode: FunctionCallingMode.NONE },
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
        text: 'Using the tool results above, reply with ONLY JSON: {"selected_helper_id":"...","explanation":"..."}',
      },
    ],
  });
  const final = await finalModel.generateContent({ contents });
  const finalText =
    final.response.candidates?.[0]?.content?.parts
      ?.map((p) => ('text' in p && p.text ? p.text : ''))
      .join('')
      .trim() ?? '';
  return { text: finalText, toolTrace };
}
