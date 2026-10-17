/**
 * Open-source profanity lexicons for chat safety:
 * - hughsie/badwords (locale CSV, severity 0–3) — block severity >= 2
 * - CMU / google-profanity-words style EN list (cmu_en.txt)
 * - LDNOOBW EN list (washyourmouthoutwithsoap lineage)
 * - regional_sl.txt — Tamil / Sinhala / SL Latin slang (always block)
 *
 * Loaded once at process start from /data next to the API package.
 */
import { existsSync, readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const MIN_SEVERITY = 2;

/** Common English tokens that appear in mild lists but are normal job chat. */
const ALLOW = new Set([
  'anal', // too many false positives in "analysis" paths; covered by compounds
  'anus',
  'ass',
  'asses',
  'balls',
  'bloody',
  'boner',
  'boob',
  'boobs',
  'breast',
  'breasts',
  'bugger',
  'bum',
  'bush',
  'butt',
  'cock', // poultry / cocktail risk — compounds still blocked via other lists
  'crap',
  'damn',
  'dick', // name Richard — compounds blocked
  'god',
  'hell',
  'homo',
  'hot',
  'jerk',
  'knob',
  'ladies',
  'muff',
  'piss',
  'poop',
  'pot',
  'prick',
  'queer',
  'screw',
  'sex',
  'sexy',
  'shit', // keep mild "oh shit" for coordination? User asked block all — remove from allow
  'slutty',
  'snatch',
  'tit',
  'tits',
  'turd',
  'wank',
  'weed', // re-add via regional drug list instead of mild EN
]);

/** Always block these even if mild EN lists allow. */
const FORCE = new Set([
  'fuck',
  'fucking',
  'fucker',
  'motherfucker',
  'cunt',
  'nigger',
  'nigga',
  'rape',
  'rapist',
  'porn',
  'nude',
  'nudes',
  'ganja',
  'kanja',
  'heroin',
  'cocaine',
  'meth',
  'shit',
  'bitch',
  'asshole',
  'dickhead',
  'whore',
  'slut',
  'bastard',
  'weed',
]);

function packageRoot(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  // dist/pillars → ../../data ; src/pillars → ../../data
  const candidates = [
    join(here, '..', '..', 'data'),
    join(here, '..', '..', '..', 'data'),
    join(process.cwd(), 'data'),
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  return candidates[0]!;
}

function addWord(set: Set<string>, raw: string) {
  const w = raw
    .trim()
    .toLowerCase()
    .normalize('NFKC')
    .replace(/^\*+/, '');
  if (!w || w.startsWith('#') || w.length < 3) return;
  if (ALLOW.has(w) && !FORCE.has(w)) return;
  set.add(w);
  // collapsed form for spaced/punctuated abuse
  const compact = w.replace(/[^a-z0-9\u0b80-\u0bff\u0d80-\u0dff]+/gi, '');
  if (compact.length >= 3) set.add(compact);
}

function loadPlainList(set: Set<string>, file: string) {
  if (!existsSync(file)) return;
  const text = readFileSync(file, 'utf8');
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    addWord(set, t);
  }
}

function loadHughsie(set: Set<string>, file: string) {
  if (!existsSync(file)) return;
  const text = readFileSync(file, 'utf8');
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    // locale,words,translation,severity — translation may contain commas
    const first = line.indexOf(',');
    const last = line.lastIndexOf(',');
    if (first < 0 || last <= first) continue;
    const severity = Number(line.slice(last + 1).trim());
    if (!Number.isFinite(severity) || severity < MIN_SEVERITY) continue;
    const mid = line.slice(first + 1, last);
    // words field is first CSV field of mid (before translation comma)
    const wordsField = mid.includes(',') ? mid.slice(0, mid.indexOf(',')) : mid;
    for (const variant of wordsField.split('/')) {
      addWord(set, variant);
    }
  }
}

function buildLexicon(): { words: Set<string>; substr: string[] } {
  const root = packageRoot();
  const set = new Set<string>();
  loadHughsie(set, join(root, 'hughsie_badwords.csv'));
  loadPlainList(set, join(root, 'cmu_en.txt'));
  loadPlainList(set, join(root, 'ldnoobw_en.txt'));
  const regional = new Set<string>();
  loadPlainList(regional, join(root, 'regional_sl.txt'));
  for (const w of regional) set.add(w);
  for (const w of FORCE) addWord(set, w);
  // Substring scan only for multi-char regional / force (not full EN — too slow / noisy)
  const substr = [...regional, ...FORCE]
    .map((w) => normalizeAbuseToken(w))
    .filter((w) => w.length >= 4);
  return { words: set, substr: [...new Set(substr)] };
}

const { words: LEXICON, substr: SUBSTR } = buildLexicon();

/** Collapse elongated vowels / stars: "o*thaaaa" → "othaa" */
export function normalizeAbuseToken(raw: string): string {
  return raw
    .toLowerCase()
    .normalize('NFKC')
    .replace(/^\*+/, '')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/(.)\1{2,}/g, '$1$1')
    .replace(/[^a-z0-9\u0b80-\u0bff\u0d80-\u0dff]+/gi, '');
}

export function lexiconSize(): number {
  return LEXICON.size;
}

/**
 * True if any token (or compact whole string) hits the lexicon.
 */
export function containsLexiconAbuse(text: string): boolean {
  const lower = text.toLowerCase().normalize('NFKC');
  const tokens = lower
    .split(/[^a-z0-9\u0b80-\u0bff\u0d80-\u0dff*]+/i)
    .filter(Boolean);
  for (const tok of tokens) {
    const n = normalizeAbuseToken(tok);
    if (n.length >= 3 && LEXICON.has(n)) return true;
    if (tok.includes('*')) {
      const stripped = normalizeAbuseToken(tok.replace(/\*/g, ''));
      if (stripped.length >= 3 && LEXICON.has(stripped)) return true;
    }
  }
  const compact = normalizeAbuseToken(lower);
  if (LEXICON.has(compact)) return true;
  for (const w of SUBSTR) {
    if (compact.includes(w)) return true;
  }
  return false;
}
