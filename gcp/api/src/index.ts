import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import multer from 'multer';
import { z } from 'zod';
import { checkTaskSafety } from './pillars/safety.js';
import { reconcileReceipt } from './pillars/receipt.js';
import { matchHelpers } from './pillars/match.js';
import { instantDispatch } from './pillars/dispatch.js';
import { quoteMicroPrice } from './pillars/pricing.js';
import { generatePricingFields } from './pillars/pricing_fields.js';
import { runTrustArbitrator } from './pillars/trust_arbitrator.js';
import {
  helperStreetRoute,
  joinStreetBatch,
  listStreetBatches,
} from './pillars/batching.js';
import {
  liveHelpersWithTrust,
  trustCard,
  vouchForNeighbor,
} from './pillars/vouch.js';
import {
  acceptTask,
  appendSystemChatMessage,
  completeTask,
  startTask,
  createSession,
  createTask,
  dbMode,
  getTask,
  getUser,
  issuePhoneOtp,
  listClientTasks,
  listHelperActiveTasks,
  listLedger,
  listLiveHelpersNearby,
  listOpenTasks,
  listTaskChat,
  listTrustReviews,
  listUsers,
  publicProfile,
  seedDemo,
  sendTaskChatMessage,
  setHelperActive,
  setHelperPresence,
  signInEmail,
  signUpEmail,
  topUp,
  userIdFromAuthHeader,
  upsertUser,
  verifyPhoneOtp,
  PLATFORM_FEE_PERCENT,
} from './store.js';
import {
  BATCH_RADIUS_KM,
  BATCH_WINDOW_SEC,
  INFLATION_INDEX,
  MIN_DESCRIPTION_CHARS,
  VOUCH_STAKE_LKR,
  VOUCH_THRESHOLD,
  WALK_RADIUS_KM,
} from './config.js';
import { uploadTaskPhoto, uploadsConfigured } from './uploads.js';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8_000_000 } });
const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

async function requireUser(req: express.Request): Promise<string> {
  const id = await userIdFromAuthHeader(req.header('authorization') ?? undefined);
  if (!id) throw new Error('Unauthorized');
  return id;
}

app.get('/', (_req, res) => {
  res.type('html').send(`<!doctype html><html><body style="font-family:system-ui;padding:2rem">
  <h1>Zivo GCP API</h1>
  <p>Cloud Run + Firestore (free tier) · <a href="/health">/health</a></p>
  </body></html>`);
});

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'zivo-gcp-api',
    feePercent: PLATFORM_FEE_PERCENT,
    stack: 'google-cloud',
    db: dbMode(),
    mockAi: (process.env.USE_MOCK_AI ?? 'true').toLowerCase() !== 'false',
    uploads: uploadsConfigured(),
    geminiModel: process.env.GEMINI_MODEL ?? 'gemini-2.5-flash-lite',
    vertexLocation: process.env.VERTEX_LOCATION ?? 'us-central1',
  });
});

app.post('/auth/otp/request', async (req, res) => {
  const body = z.object({ phone: z.string().min(8) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ error: body.error.flatten() });
  const code = await issuePhoneOtp(body.data.phone);
  res.json({
    ok: true,
    issuedCode: process.env.EXPOSE_OTP === 'false' ? undefined : code,
    message: 'OTP issued via GCP API (no SMS vendor)',
  });
});

app.post('/auth/otp/verify', async (req, res) => {
  try {
    const body = z
      .object({ phone: z.string(), token: z.string().min(4) })
      .parse(req.body);
    const user = await verifyPhoneOtp(body.phone, body.token);
    const accessToken = await createSession(user.id);
    res.json({ accessToken, user: publicProfile(user) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'OTP failed' });
  }
});

app.post('/auth/signup', async (req, res) => {
  try {
    const body = z
      .object({
        email: z.string().email(),
        password: z.string().min(6),
        full_name: z.string().min(1),
      })
      .parse(req.body);
    const user = await signUpEmail(body);
    const accessToken = await createSession(user.id);
    res.status(201).json({ accessToken, user: publicProfile(user) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Signup failed' });
  }
});

app.post('/auth/signin', async (req, res) => {
  try {
    const body = z
      .object({ email: z.string().email(), password: z.string() })
      .parse(req.body);
    const user = await signInEmail(body.email, body.password);
    const accessToken = await createSession(user.id);
    res.json({ accessToken, user: publicProfile(user) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Sign-in failed' });
  }
});

app.get('/me', async (req, res) => {
  try {
    const id = await requireUser(req);
    const user = await getUser(id);
    if (!user) return res.status(404).json({ error: 'Not found' });
    res.json({ user: publicProfile(user) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.patch('/me', async (req, res) => {
  try {
    const id = await requireUser(req);
    const user = await getUser(id);
    if (!user) return res.status(404).json({ error: 'Not found' });
    const patch = req.body as Record<string, unknown>;
    const next = {
      ...user,
      ...(patch.full_name != null ? { full_name: String(patch.full_name) } : {}),
      ...(patch.helper_bio != null ? { helper_bio: String(patch.helper_bio) } : {}),
      ...(patch.home_address != null ? { home_address: String(patch.home_address) } : {}),
      ...(patch.role_intent != null ? { role_intent: String(patch.role_intent) } : {}),
      ...(patch.kyc_status != null ? { kyc_status: String(patch.kyc_status) } : {}),
      ...(patch.nic_number != null ? { nic_number: String(patch.nic_number) } : {}),
      ...(patch.guidelines_accepted_at != null
        ? { guidelines_accepted_at: String(patch.guidelines_accepted_at) }
        : {}),
      ...(Array.isArray(patch.helper_skills)
        ? { helper_skills: patch.helper_skills.map(String) }
        : {}),
    };
    res.json({ user: await upsertUser(next) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.post('/me/helper', async (req, res) => {
  try {
    const id = await requireUser(req);
    const active = z.object({ active: z.boolean() }).parse(req.body).active;
    res.json({ user: publicProfile(await setHelperActive(id, active)) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Failed' });
  }
});

/** Pillar 1 — porch light: Available + lat/lon for walkable dispatch. */
app.post('/me/presence', async (req, res) => {
  try {
    const id = await requireUser(req);
    const body = z
      .object({
        available: z.boolean(),
        lat: z.number().optional(),
        lon: z.number().optional(),
      })
      .parse(req.body);
    res.json({ user: publicProfile(await setHelperPresence(id, body)) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Presence failed' });
  }
});

app.get('/helpers/live', async (req, res) => {
  try {
    const lat = Number(req.query.lat ?? 6.9271);
    const lon = Number(req.query.lon ?? req.query.lng ?? 79.8612);
    res.json(await liveHelpersWithTrust(lat, lon));
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'List failed' });
  }
});

/** Pillar 4 — Neighbor vouch (staked social capital). */
app.post('/vouch', async (req, res) => {
  try {
    const voucherId = await requireUser(req);
    const body = z
      .object({
        helper_id: z.string().min(1),
        note: z.string().optional(),
        lat: z.number().optional(),
        lon: z.number().optional(),
      })
      .parse(req.body);
    const result = await vouchForNeighbor({
      voucherId,
      helperId: body.helper_id,
      note: body.note,
      lat: body.lat ?? 6.9271,
      lon: body.lon ?? 79.8612,
    });
    res.status(201).json(result);
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Vouch failed' });
  }
});

app.get('/helpers/:id/trust', async (req, res) => {
  try {
    res.json(await trustCard(req.params.id));
  } catch (e) {
    res.status(404).json({ error: e instanceof Error ? e.message : 'Not found' });
  }
});

app.get('/vouch/meta', (_req, res) => {
  res.json({
    pillar: 'vouching',
    threshold: VOUCH_THRESHOLD,
    stake_lkr: VOUCH_STAKE_LKR,
    unlocks: 'inside_home',
    categories: [
      'homeCleaning',
      'homeCooking',
      'babysitting',
      'elderCare',
      'laundry',
    ],
  });
});

app.post('/wallet/topup', async (req, res) => {
  try {
    const id = await requireUser(req);
    const amount = z.object({ amount: z.number().positive() }).parse(req.body).amount;
    res.json({ user: publicProfile(await topUp(id, amount)) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Top-up failed' });
  }
});

app.get('/wallet/ledger', async (req, res) => {
  try {
    const id = await requireUser(req);
    res.json({ entries: await listLedger(id) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.get('/helpers', async (_req, res) => {
  const users = await listUsers();
  res.json({
    helpers: users.filter((u) => u.is_helper_active && u.kyc_status === 'verified'),
  });
});

/** Task photos for any category — stored in GCS (free-tier bucket). */
app.post('/uploads/photo', upload.single('photo'), async (req, res) => {
  try {
    const userId = await requireUser(req);
    if (!req.file?.buffer?.length) {
      return res.status(400).json({ error: 'photo file required' });
    }
    if (!uploadsConfigured()) {
      return res.status(503).json({ error: 'Uploads not configured on this environment' });
    }
    const result = await uploadTaskPhoto({
      bytes: req.file.buffer,
      contentType: req.file.mimetype,
      userId,
    });
    res.status(201).json(result);
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Upload failed' });
  }
});

app.post('/tasks/safety-check', async (req, res) => {
  const body = z
    .object({
      title: z.string().min(1),
      description: z.string().default(''),
      languageHint: z.enum(['en', 'si', 'mixed']).optional(),
    })
    .safeParse(req.body);
  if (!body.success) return res.status(400).json({ error: body.error.flatten() });
  // Background-only: never expose classifier internals / model brands to clients.
  const s = await checkTaskSafety(body.data);
  res.json({
    allowed: s.allowed,
    action: s.action,
    reasoning: s.reasoning,
  });
});

/** Pillar 2 — fair floor (client may boost only; never undercut). */
app.post('/tasks/price-quote', async (req, res) => {
  try {
    const body = z
      .object({
        title: z.string().optional(),
        description: z
          .string()
          .trim()
          .min(
            MIN_DESCRIPTION_CHARS,
            `Description mandatory (min ${MIN_DESCRIPTION_CHARS} chars)`,
          ),
        category: z.string().optional(),
        lat: z.number(),
        lon: z.number(),
        dest_lat: z.number().optional(),
        dest_lon: z.number().optional(),
        travel_km: z.number().nonnegative().max(40).optional(),
        duration_minutes: z.number().positive().max(180).optional(),
        urgency: z.enum(['normal', 'soon', 'urgent']).default('normal'),
        deadline_at: z.string().min(8).optional(),
        context_fields: z
          .record(
            z.string(),
            z.union([z.string(), z.number(), z.boolean(), z.null()]),
          )
          .optional(),
        client_boost_lkr: z.number().nonnegative().max(20000).optional(),
      })
      .parse(req.body);
    res.json(await quoteMicroPrice(body));
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Quote failed' });
  }
});

/** Dynamic pricing questionnaire for this task (no model brands in copy). */
app.post('/tasks/pricing-fields', async (req, res) => {
  try {
    const body = z
      .object({
        title: z.string().default(''),
        description: z
          .string()
          .trim()
          .min(
            MIN_DESCRIPTION_CHARS,
            `Description mandatory (min ${MIN_DESCRIPTION_CHARS} chars)`,
          ),
        category: z.string().min(1),
      })
      .parse(req.body);
    res.json(await generatePricingFields(body));
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Fields failed' });
  }
});

app.get('/pricing/meta', (_req, res) => {
  res.json({
    pillar: 'pricing',
    inflation_index: INFLATION_INDEX,
    min_description_chars: MIN_DESCRIPTION_CHARS,
    client_may_undercut: false,
    client_may_boost: true,
    policy:
      'Dynamic questions per task; fair floor from your answers. Accept or tip only — never undercut helpers.',
    dynamic_fields: true,
  });
});

/** Pillar 3 — Open street batches near lat/lon (piggyback window). */
app.get('/batches/nearby', async (req, res) => {
  try {
    const lat = Number(req.query.lat);
    const lon = Number(req.query.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return res.status(400).json({ error: 'lat and lon required' });
    }
    res.json({
      ...(await listStreetBatches(lat, lon)),
      batch_radius_km: BATCH_RADIUS_KM,
      window_sec: BATCH_WINDOW_SEC,
    });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'List failed' });
  }
});

/** Pillar 3 — Neighbor joins an open street batch (discounted micro). */
app.post('/batches/join', async (req, res) => {
  try {
    const clientId = await requireUser(req);
    const body = z
      .object({
        batch_id: z.string().min(1),
        title: z.string().min(1),
        description: z
          .string()
          .trim()
          .min(MIN_DESCRIPTION_CHARS, `Description mandatory (min ${MIN_DESCRIPTION_CHARS} chars)`),
        category: z.string().default('errandRun'),
        lat: z.number(),
        lon: z.number(),
        duration_minutes: z.number().positive().max(20).default(10),
        urgency: z.enum(['normal', 'soon', 'urgent']).default('soon'),
      })
      .parse(req.body);

    const safety = await checkTaskSafety({
      title: body.title,
      description: body.description,
    });
    if (!safety.allowed) {
      return res.status(422).json({ error: 'Blocked by safety policy', safety });
    }

    const result = await joinStreetBatch({
      clientId,
      batchId: body.batch_id,
      title: body.title,
      description: body.description,
      category: body.category,
      lat: body.lat,
      lon: body.lon,
      duration_minutes: body.duration_minutes,
      urgency: body.urgency,
    });
    res.status(201).json(result);
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Join failed' });
  }
});

/** Pillar 3 — Helper sees stacked stops on their street. */
app.get('/me/batch-route', async (req, res) => {
  try {
    const helperId = await requireUser(req);
    res.json(await helperStreetRoute(helperId));
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Route failed' });
  }
});

/** Pillar 1 — Instant Dispatch (AI pick among Available helpers ≤ walk radius). */
app.post('/tasks/dispatch', async (req, res) => {
  try {
    const clientId = await requireUser(req);
    const body = z
      .object({
        title: z.string().min(1),
        description: z
          .string()
          .trim()
          .min(MIN_DESCRIPTION_CHARS, `Description mandatory (min ${MIN_DESCRIPTION_CHARS} chars)`),
        category: z.string().default('errandRun'),
        lat: z.number(),
        lon: z.number(),
        dest_lat: z.number().optional(),
        dest_lon: z.number().optional(),
        travel_km: z.number().nonnegative().max(40).optional(),
        duration_minutes: z.number().positive().max(180).default(15),
        urgency: z.enum(['normal', 'soon', 'urgent']).default('urgent'),
        /** Tip above Gemini floor only. */
        client_boost_lkr: z.number().nonnegative().max(20000).optional(),
        /** Rejected if below Gemini floor. */
        labor_lkr: z.number().positive().optional(),
      })
      .parse(req.body);

    const safety = await checkTaskSafety({
      title: body.title,
      description: body.description,
    });
    if (!safety.allowed) {
      return res.status(422).json({ error: 'Blocked by safety policy', safety });
    }

    const result = await instantDispatch({
      clientId,
      title: body.title,
      description: body.description,
      category: body.category,
      lat: body.lat,
      lon: body.lon,
      dest_lat: body.dest_lat,
      dest_lon: body.dest_lon,
      travel_km: body.travel_km,
      duration_minutes: body.duration_minutes,
      urgency: body.urgency,
      client_boost_lkr: body.client_boost_lkr,
      labor_lkr: body.labor_lkr,
    });
    if (!result.task) {
      return res.status(409).json({
        error: 'No Available helper within walk radius — ask a neighbor to turn porch light ON',
        ...result,
      });
    }
    res.status(201).json(result);
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Dispatch failed' });
  }
});

app.post('/tasks', async (req, res) => {
  try {
    const userId = await requireUser(req);
    const body = z
      .object({
        title: z.string().min(1),
        description: z
          .string()
          .trim()
          .min(
            MIN_DESCRIPTION_CHARS,
            `Description mandatory (min ${MIN_DESCRIPTION_CHARS} chars)`,
          ),
        category: z.string(),
        estimated_hours: z.number().positive().max(12).optional(),
        /** Ignored for labor floor — fair pricing sets pay. */
        hourly_rate: z.number().positive().optional(),
        goods_budget: z.number().nonnegative().default(0),
        lat: z.number(),
        lon: z.number(),
        dest_lat: z.number().optional(),
        dest_lon: z.number().optional(),
        travel_km: z.number().nonnegative().max(40).optional(),
        difficulty: z.enum(['easy', 'moderate', 'hard', 'expert']).optional(),
        physical_effort: z.enum(['none', 'light', 'medium', 'heavy']).optional(),
        deadline_at: z.string().min(8).optional(),
        context_fields: z
          .record(
            z.string(),
            z.union([z.string(), z.number(), z.boolean(), z.null()]),
          )
          .optional(),
        urgency: z.enum(['normal', 'soon', 'urgent']).default('normal'),
        client_boost_lkr: z.number().nonnegative().max(20000).optional(),
        location_address: z.string().nullish(),
        location_label: z.string().nullish(),
        photo_urls: z.array(z.string().min(8)).max(5).nullish(),
        photo_paths: z.array(z.string().min(3)).max(5).nullish(),
      })
      .parse(req.body);

    const safety = await checkTaskSafety({
      title: body.title,
      description: body.description,
    });
    if (!safety.allowed) {
      return res.status(422).json({
        error:
          safety.reasoning ||
          'This request doesn’t meet community safety guidelines',
      });
    }

    const ctx = { ...(body.context_fields ?? {}) };
    const deadlineFromCtx =
      typeof ctx.deadline_at === 'string' ? ctx.deadline_at : undefined;
    const deadlineAt = body.deadline_at ?? deadlineFromCtx;
    if (!deadlineAt) {
      return res.status(400).json({ error: 'Complete-before deadline is required' });
    }

    const pricing = await quoteMicroPrice({
      title: body.title,
      description: body.description,
      category: body.category,
      lat: body.lat,
      lon: body.lon,
      dest_lat: body.dest_lat,
      dest_lon: body.dest_lon,
      travel_km: body.travel_km,
      duration_minutes: body.estimated_hours
        ? Math.round(body.estimated_hours * 60)
        : undefined,
      urgency: body.urgency,
      difficulty: body.difficulty,
      physical_effort: body.physical_effort,
      deadline_at: deadlineAt,
      context_fields: ctx,
      client_boost_lkr: body.client_boost_lkr,
    });

    const labor = pricing.labor_lkr;
    const hours = Math.max(0.25, pricing.duration_hours);
    const hourly = Math.round(labor / hours);

    const enrichedDescription =
      body.description +
      `\n\n[Fair price LKR ${labor}` +
      (pricing.client_boost_lkr > 0 ? ` including tip ${pricing.client_boost_lkr}` : '') +
      ` · deadline ${deadlineAt}` +
      (pricing.delivery ? ' · delivery' : '') +
      `]` +
      `\n${pricing.explanation}` +
      `\nContext: ${JSON.stringify(ctx)}`;

    const task = await createTask({
      client_id: userId,
      title: body.title,
      description: enrichedDescription,
      category: body.category,
      estimated_hours: hours,
      hourly_rate: hourly,
      goods_budget: body.goods_budget,
      lat: body.lat,
      lon: body.lon,
      location_address: body.location_address ?? undefined,
      location_label: body.location_label ?? undefined,
      photo_urls: body.photo_urls ?? undefined,
      photo_paths: body.photo_paths ?? undefined,
      deadline_at: deadlineAt,
      difficulty: pricing.difficulty,
      physical_effort: pricing.physical_effort,
    });
    // Do not expose internal safety/RAG payload to clients.
    res.status(201).json({
      task,
      pricing: {
        labor_lkr: pricing.labor_lkr,
        gemini_labor_lkr: pricing.gemini_labor_lkr,
        client_boost_lkr: pricing.client_boost_lkr,
        explanation: pricing.explanation,
        duration_hours: pricing.duration_hours,
        policy: pricing.policy,
        non_negotiable: true,
        client_may_undercut: false,
      },
    });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Create failed' });
  }
});

app.get('/tasks/mine', async (req, res) => {
  try {
    const id = await requireUser(req);
    res.json({ tasks: await listClientTasks(id) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.get('/tasks/helper/active', async (req, res) => {
  try {
    const id = await requireUser(req);
    res.json({ tasks: await listHelperActiveTasks(id) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.get('/tasks/open', async (req, res) => {
  const lat = Number(req.query.lat ?? 6.9271);
  const lng = Number(req.query.lng ?? 79.8612);
  res.json({ tasks: await listOpenTasks(lat, lng) });
});

app.get('/tasks/:id', async (req, res) => {
  const task = await getTask(String(req.params.id));
  if (!task) return res.status(404).json({ error: 'Not found' });
  res.json({ task });
});

app.post('/tasks/:id/accept', async (req, res) => {
  try {
    const helperId = await requireUser(req);
    const task = await acceptTask(String(req.params.id), helperId);
    res.json({ task });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Accept failed' });
  }
});

/** In-app task chat (client ↔ assigned helper). Messages are persisted. */
app.get('/tasks/:id/chat', async (req, res) => {
  try {
    const userId = await requireUser(req);
    const after = typeof req.query.after === 'string' ? req.query.after : undefined;
    res.json(await listTaskChat(String(req.params.id), userId, after));
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Chat failed';
    const code = msg.includes('Only the client') ? 403 : 400;
    res.status(code).json({ error: msg });
  }
});

app.post('/tasks/:id/chat', async (req, res) => {
  try {
    const userId = await requireUser(req);
    const body = z
      .object({ body: z.string().trim().min(1).max(2000) })
      .parse(req.body);
    const taskId = String(req.params.id);
    const task = await getTask(taskId);
    if (!task) return res.status(404).json({ error: 'Task not found' });

    // Cup-unique: vernacular safety on every message (not just task create).
    const safety = await checkTaskSafety({
      title: `chat:${task.title}`,
      description: body.body,
    });
    if (!safety.allowed || safety.action === 'block') {
      try {
        await appendSystemChatMessage(
          taskId,
          'Message blocked by community safety — keep coordination ordinary and on-platform.',
        );
      } catch {
        /* ignore */
      }
      return res.status(422).json({
        error:
          safety.reasoning ||
          'That message doesn’t meet community safety guidelines',
        blocked: true,
        safety: {
          allowed: false,
          action: safety.action ?? 'block',
          reasoning: safety.reasoning,
        },
      });
    }

    const message = await sendTaskChatMessage({
      taskId,
      senderId: userId,
      body: body.body,
    });
    res.status(201).json({
      message,
      safety: {
        allowed: true,
        action: safety.action ?? 'allow',
      },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Send failed';
    const code = msg.includes('Only the client') ? 403 : 400;
    res.status(code).json({ error: msg });
  }
});

/** Cup-unique: Gemini Trust Arbitrator over chat + timeline + vouch (+ receipt note). */
app.post('/tasks/:id/trust-review', async (req, res) => {
  try {
    const userId = await requireUser(req);
    const body = z
      .object({
        reason: z.string().max(500).optional(),
        receipt_note: z.string().max(1000).optional(),
      })
      .parse(req.body ?? {});
    const result = await runTrustArbitrator({
      taskId: String(req.params.id),
      requesterId: userId,
      reason: body.reason,
      receipt_note: body.receipt_note,
    });
    res.json(result);
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Trust review failed';
    const code = msg.includes('Only the client') ? 403 : 400;
    res.status(code).json({ error: msg });
  }
});

app.get('/tasks/:id/trust-reviews', async (req, res) => {
  try {
    const userId = await requireUser(req);
    const task = await getTask(String(req.params.id));
    if (!task) return res.status(404).json({ error: 'Not found' });
    if (task.client_id !== userId && task.helper_id !== userId) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    res.json({
      reviews: await listTrustReviews(String(req.params.id)),
      trust_hold: !!task.trust_hold,
      trust_hold_reason: task.trust_hold_reason,
    });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Failed' });
  }
});

app.post('/tasks/:id/match', async (req, res) => {
  const task = await getTask(String(req.params.id));
  if (!task) return res.status(404).json({ error: 'Not found' });
  res.json(await matchHelpers(task));
});

app.post('/tasks/:id/start', async (req, res) => {
  try {
    await requireUser(req);
    const body = z.object({ start_otp: z.string().min(4).max(8) }).parse(req.body);
    const task = await startTask(String(req.params.id), body.start_otp);
    res.json({ task });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Start failed' });
  }
});

app.post('/tasks/:id/receipt', upload.single('receipt'), async (req, res) => {
  const task = await getTask(String(req.params.id));
  if (!task) return res.status(404).json({ error: 'Not found' });
  const shoppingList = String(
    req.body.shoppingList ?? req.body.shopping_list ?? task.description ?? '',
  );
  const budgetOverride = Number(req.body.budget_lkr ?? req.body.budgetLkr);
  const goodsBudgetLkr = Number.isFinite(budgetOverride) && budgetOverride > 0
    ? budgetOverride
    : task.goods_budget;
  res.json(
    await reconcileReceipt({
      task: {
        id: task.id,
        title: task.title,
        description: task.description,
        category: task.category === 'groceryRun' ? 'grocery' : 'labor',
        laborFeeLkr: task.total_amount,
        goodsBudgetLkr,
        lat: task.lat,
        lng: task.lon,
        requiredSkill: 'none',
        clientId: task.client_id,
        status: 'open',
        escrow: {
          laborHoldLkr: task.total_amount,
          goodsHoldLkr: goodsBudgetLkr,
          status: 'held',
        },
        confirmCode: task.confirm_code ?? '0000',
        createdAt: task.created_at,
      },
      shoppingList,
      imageBytes: req.file?.buffer,
      mimeType: req.file?.mimetype,
    }),
  );
});

app.post('/tasks/:id/complete', async (req, res) => {
  try {
    const body = z
      .object({
        confirm_code: z.string().min(4),
        receipt_total_lkr: z.number().nonnegative().default(0),
      })
      .parse(req.body);
    res.json(await completeTask(String(req.params.id), body));
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Complete failed' });
  }
});

const port = Number(process.env.PORT || 8080);

seedDemo()
  .then(() => {
    app.listen(port, () => {
      console.log(
        `zivo-gcp-api :${port} db=${dbMode()} USE_MOCK_AI=${process.env.USE_MOCK_AI ?? 'true'}`,
      );
    });
  })
  .catch((err) => {
    console.error('Firestore seed failed', err);
    process.exit(1);
  });
