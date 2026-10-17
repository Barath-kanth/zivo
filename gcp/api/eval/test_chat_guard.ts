/**
 * Deterministic chat-guard cases (no Gemini).
 *   GCP_PROJECT_ID= npx tsx eval/test_chat_guard.ts
 */
import { guardChatMessage } from '../src/pillars/chat_guard.js';

const cases: Array<{ text: string; expectBlock: boolean; note: string }> = [
  { text: 'நான் வீட்டுக்கு வந்துட்டேன். பைகளை கதவுக்கு முன்னாடி வைக்கிறேன்.', expectBlock: false, note: 'Tamil coordination' },
  { text: 'මම දොර ළඟ. කරත්තේ බඩු තියන්න.', expectBlock: false, note: 'Sinhala coordination' },
  { text: 'I am at the door — please open.', expectBlock: false, note: 'English coordination' },
  { text: 'Start code is 4821', expectBlock: false, note: 'short OTP ok' },
  { text: 'Call me on 0771234567', expectBlock: true, note: 'SL mobile + call me' },
  { text: 'என் நம்பர் 077 123 4567', expectBlock: true, note: 'Tamil + SL mobile' },
  { text: 'WhatsApp me when you arrive', expectBlock: true, note: 'WhatsApp' },
  { text: 'வாட்ஸ்அப்ல மெசேஜ் பண்ணு', expectBlock: true, note: 'Tamil WhatsApp' },
  { text: 'email me at test@gmail.com', expectBlock: true, note: 'email' },
  { text: 'My number is +94 77 123 4567', expectBlock: true, note: '+94 mobile' },
  { text: 'call me', expectBlock: true, note: 'bare call me' },
  { text: 'LKR 1500 for groceries is fine', expectBlock: false, note: 'money amount ok' },
  { text: 'bring kudu tonight', expectBlock: true, note: 'drug slang kudu' },
  { text: 'thool packet near the shop', expectBlock: true, note: 'thool packet' },
  { text: 'Kolapanna pore', expectBlock: true, note: 'Tamil kill transliteration' },
  { text: 'கொலை பண்ண போறேன்', expectBlock: true, note: 'Tamil kolai' },
  { text: 'fuck you', expectBlock: true, note: 'English swear' },
  { text: 'I am at the door with the rice', expectBlock: false, note: 'normal doorstep' },
  { text: 'abin', expectBlock: true, note: 'SL drug slang abin' },
  { text: 'mairu', expectBlock: true, note: 'Tamil abuse mairu' },
  { text: '*thaaaa', expectBlock: true, note: 'star-masked elongated abuse' },
  { text: 'kolamavu iruka', expectBlock: true, note: 'drug powder slang' },
  { text: 'adichi thooku saamy', expectBlock: true, note: 'violence slang' },
  { text: 'kanja irukku', expectBlock: true, note: 'kanja variant of ganja' },
  { text: 'Please leave the bags at the door', expectBlock: false, note: 'normal coordination' },
];

let failed = 0;
for (const c of cases) {
  const r = guardChatMessage(c.text);
  const blocked = !r.ok;
  const ok = blocked === c.expectBlock;
  console.log(`${ok ? 'PASS' : 'FAIL'}  block=${blocked}  ${c.note}`);
  if (!ok) {
    failed += 1;
    console.log('   text:', c.text);
    console.log('   result:', r);
  }
}
console.log(`\n${cases.length - failed}/${cases.length} passed`);
process.exit(failed ? 1 : 0);
