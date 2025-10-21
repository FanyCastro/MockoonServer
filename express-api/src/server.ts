import express from 'express';

const app = express();
const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;

// Middleware to parse JSON
app.use(express.json());

app.get('/status', (_req, res) => {
  res.json({
    status: 'ok',
    message: '🚀 Service running smoothly',
    timestamp: new Date().toISOString(),
  });
});

app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));
    