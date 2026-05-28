import express from 'express';
import cors from 'cors';
import { config, validateConfig } from './config/index.js';
import authRoutes from './routes/auth/index.js';
import emailRoutes from './routes/email/index.js';
import contactsRoutes from './routes/contacts/index.js';
import compressRoutes from './routes/compress/index.js';
import streakRoutes from './routes/streak.js';
import themeRoutes from './routes/theme.js';
import chatRoutes from './routes/chat.js';
import subscriptionsRoutes from './routes/subscriptions.js';
import quotaRoutes from './routes/quota.js';
import progressRoutes from './routes/progress.js';
import cleanupTaskRoutes from './routes/cleanup-task.js';

// Catch silent crashes
process.on('uncaughtException', (err) => {
  console.error('UNCAUGHT EXCEPTION:', err);
});
process.on('unhandledRejection', (reason) => {
  console.error('UNHANDLED REJECTION:', reason);
});

// Validate environment variables
validateConfig();

const app = express();

// Middleware — allow all origins since iOS apps don't send CORS headers
// and we need flexibility for simulator + real device testing
app.use(cors({
  origin: true,
  credentials: true
}));
app.use(express.json({ limit: '50mb' }));

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/auth', authRoutes);
app.use('/email', emailRoutes);
app.use('/contacts', contactsRoutes);
app.use('/compress', compressRoutes);
app.use('/streak', streakRoutes);
app.use('/theme', themeRoutes);
app.use('/chats', chatRoutes);
app.use('/subscriptions', subscriptionsRoutes);
app.use('/quota', quotaRoutes);
app.use('/progress', progressRoutes);
app.use('/cleanup-task', cleanupTaskRoutes);

// Error handler
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
const host = process.env.RAILWAY_ENVIRONMENT ? '0.0.0.0' : 'localhost';
console.log(`PORT=${process.env.PORT}, RAILWAY_ENVIRONMENT=${process.env.RAILWAY_ENVIRONMENT}`);
app.listen(config.port, host, () => {
  console.log(`BeeClean Backend running on http://${host}:${config.port}`);
  console.log(`Google Auth callback: ${config.google.redirectUri}`);
});
