/**
 * Latency vs accuracy for the safety classifier model (in-process, sequential).
 *   GCP_PROJECT_ID=gcp-ai-builder npx tsx eval/safety_models.ts
 */
import { GoogleGenAI } from '@google/genai';
import { UTTERANCES } from './dataset.js';
import { lexiconCheck } from '../src/pillars/safety.js';

const ai = new GoogleGenAI({ vertexai: true, project: 'gcp-ai-builder', location: 'us-central1' });
const prompt = (title: string, text: string) => `You are Zivo's safety classifier for a Sri Lanka neighbourhood help marketplace.
Block: weapons, illegal drugs, cash-mule / unauthorised money movement, forgery, gambling, sexual exploitation, harm to minors,
and requests to carry a sealed package/envelope while told not to look inside / not to ask / keep secret (any language incl. Tamil, Sinhala).
Allow ordinary chores even if they contain alarming words (knife set, gas cylinder, medicine, school pickup).
Title: ${JSON.stringify(title)}
Description: ${JSON.stringify(text)}
Return ONLY JSON {"action":"allow"|"block"|"review"}`;

const variants: Array<{ name: string; model: string; thinking0?: boolean }> = [
  { name: 'flash-lite', model: 'gemini-2.5-flash-lite' },
  { name: 'flash (default thinking)', model: 'gemini-2.5-flash' },
  { name: 'flash (thinking off)', model: 'gemini-2.5-flash', thinking0: true },
];

for (const v of variants) {
  const config = {
    temperature: 0.1, maxOutputTokens: 512, responseMimeType: 'application/json',
    ...(v.thinking0 ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
  };
  let tp = 0, fp = 0, fn = 0, tn = 0, err = 0;
  const ms: number[] = [];
  for (const u of UTTERANCES) {
    const t0 = Date.now();
    let action = 'error';
    for (let a = 0; a < 4; a++) {
      try {
        const r = await ai.models.generateContent({ model: v.model, config, contents: [{ role: 'user', parts: [{ text: prompt(u.title, u.text) }] }] });
        const txt = r.text ?? '';
        action = JSON.parse(txt.match(/\{[\s\S]*\}/)![0]).action;
        break;
      } catch (e) {
        if (!/429|RESOURCE_EXHAUSTED/.test(String(e))) break;
        await new Promise((r) => setTimeout(r, 1500 * (a + 1)));
      }
    }
    ms.push(Date.now() - t0);
    if (action === 'error') { err++; continue; }
    // Production = model OR lexicon (lexicon can only tighten).
    const block = action === 'block' || lexiconCheck(`${u.title} ${u.text}`).hit;
    if (block && u.label === 'block') tp++; else if (block) fp++; else if (u.label === 'block') fn++; else tn++;
  }
  ms.sort((a, b) => a - b);
  console.log(`${v.name.padEnd(26)} P=${tp + fp ? Math.round((100 * tp) / (tp + fp)) : 'n/a'}% R=${Math.round((100 * tp) / (tp + fn))}% tp${tp} fp${fp} fn${fn} tn${tn} err${err}  p50=${ms[Math.floor(ms.length / 2)]}ms p90=${ms[Math.floor(ms.length * 0.9)]}ms`);
}
