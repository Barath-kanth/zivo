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
  createSession,
  createTask,
  getTask,
  getUser,
  issuePhoneOtp,
  listClientTasks,
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

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8_000_000 } });
const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));
seedDemo();

function requireUser(req: express.Request): string {
  const id = userIdFromAuthHeader(req.header('authorization') ?? undefined);
  if (!id) throw new Error('Unauthorized');
  return id;
}

app.get('/', (_req, res) => {
  res.type('html').send(`<!doctype html><html><body style="font-family:system-ui;padding:2rem">
  <h1>Zivo GCP API</h1>
  <p>Cloud Run backend for Flutter Zivo · <a href="/health">/health</a></p>
  </body></html>`);
});

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'zivo-gcp-api',
    feePercent: PLATFORM_FEE_PERCENT,
    stack: 'google-cloud',
  });
});

app.post('/auth/otp/request', (req, res) => {
  const body = z.object({ phone: z.string().min(8) }).safeParse(req.body);
  if (!body.success) return res.status(400).json({ error: body.error.flatten() });
  const code = issuePhoneOtp(body.data.phone);
  res.json({
    ok: true,
    // Cup demo: return code when USE_MOCK_AI / local (no SMS vendor)
    issuedCode: process.env.EXPOSE_OTP === 'false' ? undefined : code,
    message: 'OTP issued via GCP API (no TextBee/Supabase)',
  });
});

app.post('/auth/otp/verify', (req, res) => {
  try {
    const body = z
      .object({ phone: z.string(), token: z.string().min(4) })
      .parse(req.body);
    const user = verifyPhoneOtp(body.phone, body.token);
    const accessToken = createSession(user.id);
    res.json({ accessToken, user: publicProfile(user) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'OTP failed' });
  }
});

app.post('/auth/signup', (req, res) => {
  try {
    const body = z
      .object({
        email: z.string().email(),
        password: z.string().min(6),
        full_name: z.string().min(1),
      })
      .parse(req.body);
    const user = signUpEmail(body);
    const accessToken = createSession(user.id);
    res.status(201).json({ accessToken, user: publicProfile(user) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Signup failed' });
  }
});

app.post('/auth/signin', (req, res) => {
  try {
    const body = z
      .object({ email: z.string().email(), password: z.string() })
      .parse(req.body);
    const user = signInEmail(body.email, body.password);
    const accessToken = createSession(user.id);
    res.json({ accessToken, user: publicProfile(user) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Sign-in failed' });
  }
});

app.get('/me', (req, res) => {
  try {
    const id = requireUser(req);
    const user = getUser(id);
    if (!user) return res.status(404).json({ error: 'Not found' });
    res.json({ user: publicProfile(user) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.patch('/me', (req, res) => {
  try {
    const id = requireUser(req);
    const user = getUser(id);
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
    res.json({ user: upsertUser(next) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.post('/me/helper', (req, res) => {
  try {
    const id = requireUser(req);
    const active = z.object({ active: z.boolean() }).parse(req.body).active;
    res.json({ user: publicProfile(setHelperActive(id, active)) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Failed' });
  }
});

app.post('/wallet/topup', (req, res) => {
  try {
    const id = requireUser(req);
    const amount = z.object({ amount: z.number().positive() }).parse(req.body).amount;
    res.json({ user: publicProfile(topUp(id, amount)) });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Top-up failed' });
  }
});

app.get('/wallet/ledger', (req, res) => {
  try {
    const id = requireUser(req);
    res.json({ entries: listLedger(id) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.get('/helpers', (_req, res) => {
  res.json({
    helpers: listUsers().filter((u) => u.is_helper_active && u.kyc_status === 'verified'),
  });
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
    const userId = requireUser(req);
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
        location_address: z.string().optional(),
        location_label: z.string().optional(),
      })
      .parse(req.body);

    const safety = await checkTaskSafety({
      title: body.title,
      description: body.description,
    });
    if (!safety.allowed) {
      return res.status(422).json({ error: 'Task blocked by safety policy', safety });
    }

    const task = createTask({ ...body, client_id: userId });
    res.status(201).json({ task, safety });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Create failed' });
  }
});

app.get('/tasks/mine', (req, res) => {
  try {
    const id = requireUser(req);
    res.json({ tasks: listClientTasks(id) });
  } catch (e) {
    res.status(401).json({ error: e instanceof Error ? e.message : 'Unauthorized' });
  }
});

app.get('/tasks/open', (req, res) => {
  const lat = Number(req.query.lat ?? 6.9271);
  const lng = Number(req.query.lng ?? 79.8612);
  res.json({ tasks: listOpenTasks(lat, lng) });
});

app.get('/tasks/:id', (req, res) => {
  const task = getTask(String(req.params.id));
  if (!task) return res.status(404).json({ error: 'Not found' });
  res.json({ task });
});

app.post('/tasks/:id/accept', (req, res) => {
  try {
    const helperId = requireUser(req);
    const task = acceptTask(String(req.params.id), helperId);
    res.json({ task });
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Accept failed' });
  }
});

app.post('/tasks/:id/match', async (req, res) => {
  const task = getTask(String(req.params.id));
  if (!task) return res.status(404).json({ error: 'Not found' });
  res.json(await matchHelpers(task));
});

app.post('/tasks/:id/receipt', upload.single('receipt'), async (req, res) => {
  const task = getTask(String(req.params.id));
  if (!task) return res.status(404).json({ error: 'Not found' });
  const shoppingList = String(req.body.shoppingList ?? '');
  res.json(
    await reconcileReceipt({
      task: {
        id: task.id,
        title: task.title,
        description: task.description,
        category: task.category === 'groceryRun' ? 'grocery' : 'labor',
        laborFeeLkr: task.total_amount,
        goodsBudgetLkr: task.goods_budget,
        lat: task.lat,
        lng: task.lon,
        requiredSkill: 'none',
        clientId: task.client_id,
        status: 'open',
        escrow: {
          laborHoldLkr: task.total_amount,
          goodsHoldLkr: task.goods_budget,
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

app.post('/tasks/:id/complete', (req, res) => {
  try {
    const body = z
      .object({
        confirm_code: z.string().min(4),
        receipt_total_lkr: z.number().nonnegative().default(0),
      })
      .parse(req.body);
    res.json(completeTask(String(req.params.id), body));
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : 'Complete failed' });
  }
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  console.log(
    `zivo-gcp-api :${port} USE_MOCK_AI=${process.env.USE_MOCK_AI ?? 'true'}`,
  );
});
