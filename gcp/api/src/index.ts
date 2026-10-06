import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import multer from 'multer';
import { z } from 'zod';
import { checkTaskSafety } from './pillars/safety.js';
import { reconcileReceipt } from './pillars/receipt.js';
import { matchHelpers } from './pillars/match.js';
import {
  acceptTask,
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
  listOpenTasks,
  listUsers,
  publicProfile,
  seedDemo,
  setHelperActive,
  signInEmail,
  signUpEmail,
  topUp,
  userIdFromAuthHeader,
  upsertUser,
  verifyPhoneOtp,
  PLATFORM_FEE_PERCENT,
} from './store.js';
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
  res.json(await checkTaskSafety(body.data));
});

app.post('/tasks', async (req, res) => {
  try {
    const userId = await requireUser(req);
    const body = z
      .object({
        title: z.string().min(1),
        description: z.string().default(''),
        category: z.string(),
        estimated_hours: z.number().positive(),
        hourly_rate: z.number().positive(),
        goods_budget: z.number().nonnegative().default(0),
        lat: z.number(),
        lon: z.number(),
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
      return res.status(422).json({ error: 'Task blocked by safety policy', safety });
    }

    const task = await createTask({
      ...body,
      client_id: userId,
      location_address: body.location_address ?? undefined,
      location_label: body.location_label ?? undefined,
      photo_urls: body.photo_urls ?? undefined,
      photo_paths: body.photo_paths ?? undefined,
    });
    res.status(201).json({ task, safety });
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
