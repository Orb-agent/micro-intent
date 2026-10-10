import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import rateLimit from 'express-rate-limit';
import path from 'node:path';
import { addGoogleCalendarEvent, InputError, listGoogleConflicts, makeDemoConflicts, safeTimeZone, validateEvent } from './calendarService.js';
import { buildRoutes, deterministicSummary, summarizeWithGemini } from './agentEngine.js';

dotenv.config();

const app = express();
const PORT = Number(process.env.PORT || 3001);
const production = process.env.NODE_ENV === 'production';
const HOST = process.env.HOST || (production ? '0.0.0.0' : '127.0.0.1');
const configuredAppOrigins = (process.env.APP_ORIGIN || '').split(',').map((value) => {
  try { return new URL(value.trim()).origin; } catch { return ''; }
}).filter(Boolean);
if (production) app.set('trust proxy', 1);
app.disable('x-powered-by');
app.use((req, res, next) => {
  const origin = req.get('origin');
  if (origin && !isSameOrigin(req, origin) && !isAllowedOrigin(origin)) {
    res.status(403).json({ error: 'This origin cannot access the local backend.' });
    return;
  }
  next();
});
app.use(cors({
  origin: (origin, callback) => callback(null, !origin || isAllowedOrigin(origin)),
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type'],
}));
app.use(express.json({ limit: '32kb' }));

const planRateLimit = rateLimit({
  windowMs: 60_000,
  limit: 30,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: { error: 'Too many planning requests. Please wait a minute and try again.' },
});

app.get('/api/status', (_req, res) => {
  res.json({
    googleConfigured: Boolean(process.env.GOOGLE_CLIENT_ID),
    modelConfigured: Boolean(process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY),
  });
});

app.get('/api/config', (_req, res) => {
  res.json({ googleClientId: process.env.GOOGLE_CLIENT_ID || '' });
});

app.post('/api/plan', planRateLimit, async (req, res) => {
  try {
    const query = typeof req.body?.query === 'string' ? req.body.query.trim() : '';
    if (!query) throw new InputError('query is required.');
    if (query.length > 2000) throw new InputError('query must be 2000 characters or fewer.');
    const event = validateEvent(req.body?.event);
    const origin = typeof req.body?.origin === 'string' ? req.body.origin.trim().slice(0, 300) : '';
    const accessToken = readAccessToken(req.body?.accessToken);
    const calendarTimeZone = readCalendarTimeZone(req.body?.calendarTimeZone);
    const mode = accessToken ? 'google' : 'demo';
    const conflicts = accessToken ? await listGoogleConflicts(event, accessToken, calendarTimeZone) : makeDemoConflicts(event);
    const fallback = deterministicSummary(query, event, conflicts, mode);
    const model = await summarizeWithGemini(query, event, conflicts, fallback, mode);

    res.json({
      summary: mode === 'demo' ? `DEMO · ${model.summary}` : model.summary,
      mode,
      conflicts,
      routes: buildRoutes(event, origin),
      agents: [
        { name: 'Calendar', status: accessToken ? 'Google Calendar checked' : 'Demo calendar simulated' },
        { name: 'Transport', status: 'Route links ready' },
        { name: 'Intent', status: model.modelUsed ? 'Model summary' : 'Deterministic summary' },
      ],
      ...(model.modelUsed ? { modelUsed: model.modelUsed } : {}),
    });
  } catch (error) {
    sendError(res, error, 'Could not prepare the plan.');
  }
});

app.post('/api/calendar/add', async (req, res) => {
  try {
    const event = validateEvent(req.body?.event);
    const accessToken = readAccessToken(req.body?.accessToken);
    if (!accessToken) {
      res.json({
        mode: 'demo',
        saved: false,
        message: 'Demo mode: the event was not saved. Connect Google Calendar to add it.',
      });
      return;
    }
    const created = await addGoogleCalendarEvent(event, accessToken);
    res.json({ mode: 'google', saved: true, ...created });
  } catch (error) {
    sendError(res, error, 'Could not add the event.');
  }
});

// Old clients called these endpoints and received synthetic calendar mutations.
// Keep a clear response during migration so no caller mistakes a demo for a save.
app.all(['/api/calendar', '/api/calendar/resolve', '/api/intent', '/api/sbb/connections'], (_req, res) => {
  res.status(410).json({ error: 'This legacy endpoint is no longer available. Use POST /api/plan.' });
});

app.use('/api', (_req, res) => {
  res.status(404).json({ error: 'API endpoint not found.' });
});

if (production) {
  const frontendDirectory = path.resolve(process.cwd(), 'dist');
  app.use(express.static(frontendDirectory, {
    index: false,
    setHeaders: (res, filePath) => {
      const assetPath = `${path.sep}assets${path.sep}`;
      const isHashedAsset = filePath.includes(assetPath);
      res.setHeader('Cache-Control', isHashedAsset ? 'public, max-age=31536000, immutable' : 'no-cache');
    },
  }));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api/')) return next();
    res.setHeader('Cache-Control', 'no-cache');
    res.sendFile(path.join(frontendDirectory, 'index.html'), (error) => {
      if (error) next(error);
    });
  });
}

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found.' });
});

app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (isRequestParsingError(error)) {
    res.status(400).json({ error: 'The request body must be valid JSON.' });
    return;
  }
  const status = typeof error === 'object' && error !== null && 'status' in error && error.status === 413 ? 413 : 500;
  sendError(res, error, status === 413 ? 'The request is too large.' : 'Internal server error.', status);
});

function readAccessToken(value: unknown): string | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string' || value.length > 10_000 || /\s/.test(value)) {
    throw new InputError('accessToken must be a valid OAuth access token string.');
  }
  return value;
}

function readCalendarTimeZone(value: unknown): string | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string' || value.length > 100 || !safeTimeZone(value)) {
    throw new InputError('calendarTimeZone must be a valid IANA timezone, such as Europe/Zurich.');
  }
  return value;
}

export function isAllowedOrigin(origin: string): boolean {
  try {
    const url = new URL(origin);
    if (configuredAppOrigins.includes(url.origin)) return true;
    if (url.protocol === 'chrome-extension:' && /^[a-p]{32}$/.test(url.hostname)) return true;
    if (!['http:', 'https:'].includes(url.protocol)) return false;
    const localHost = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
    return localHost && ['3001', '5173', '4173'].includes(url.port || (url.protocol === 'https:' ? '443' : '80'));
  } catch {
    return false;
  }
}

function isSameOrigin(req: express.Request, origin: string): boolean {
  try {
    return new URL(origin).origin === `${req.protocol}://${req.get('host')}`;
  } catch {
    return false;
  }
}

function isRequestParsingError(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'type' in error && error.type === 'entity.parse.failed';
}

function sendError(res: express.Response, error: unknown, fallback: string, statusOverride?: number): void {
  if (error instanceof InputError) {
    res.status(400).json({ error: error.message });
    return;
  }
  const message = error instanceof Error ? error.message : fallback;
  // Provider failures have already been reduced to a safe message by calendarService.
  const status = statusOverride || (message.includes('Google Calendar') ? 502 : 500);
  res.status(status).json({ error: message || fallback });
}

app.listen(PORT, HOST, () => {
  console.log(`Micro Intent backend listening on http://${HOST}:${PORT}`);
});

export default app;
