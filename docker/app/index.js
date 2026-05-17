const express = require("express");
const client = require("prom-client");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 3000;

// ── Prometheus Registry ──────────────────────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register });

// Custom metrics
const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

const httpRequestTotal = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status_code"],
});

const activeConnections = new client.Gauge({
  name: "active_connections",
  help: "Number of active connections",
});

const cpuUsage = new client.Gauge({
  name: "app_cpu_usage_percent",
  help: "Current CPU usage percentage",
});

const memoryUsage = new client.Gauge({
  name: "app_memory_usage_bytes",
  help: "Current memory usage in bytes",
});

register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);
register.registerMetric(activeConnections);
register.registerMetric(cpuUsage);
register.registerMetric(memoryUsage);

// ── Middleware ───────────────────────────────────────────────────────────────
app.use(express.json());

// Track active connections
let connections = 0;
app.use((req, res, next) => {
  connections++;
  activeConnections.set(connections);
  res.on("finish", () => {
    connections = Math.max(0, connections - 1);
    activeConnections.set(connections);
  });
  next();
});

// Request duration + counter middleware
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on("finish", () => {
    const labels = { method: req.method, route: req.path, status_code: res.statusCode };
    end(labels);
    httpRequestTotal.inc(labels);
  });
  next();
});

// System metrics refresh every 5 s
setInterval(() => {
  const cpus = os.cpus();
  const total = cpus.reduce((acc, c) => {
    const t = Object.values(c.times).reduce((s, v) => s + v, 0);
    return { idle: acc.idle + c.times.idle, total: acc.total + t };
  }, { idle: 0, total: 0 });
  cpuUsage.set(((1 - total.idle / total.total) * 100));

  const used = process.memoryUsage();
  memoryUsage.set(used.heapUsed);
}, 5000);

// ── Routes ───────────────────────────────────────────────────────────────────
app.get("/", (req, res) => {
  res.json({
    service: "CloudSentinel App",
    status: "running",
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

app.get("/health", (req, res) => {
  const mem = process.memoryUsage();
  res.json({
    status: "healthy",
    uptime: process.uptime(),
    memory: {
      heapUsed: `${(mem.heapUsed / 1024 / 1024).toFixed(2)} MB`,
      heapTotal: `${(mem.heapTotal / 1024 / 1024).toFixed(2)} MB`,
    },
    cpu: os.cpus().length + " cores",
    hostname: os.hostname(),
  });
});

// Simulate variable load for demo
app.get("/load", async (req, res) => {
  const intensity = parseInt(req.query.intensity) || 1e6;
  let sum = 0;
  for (let i = 0; i < intensity; i++) sum += Math.sqrt(i);
  res.json({ result: sum, intensity });
});

// Prometheus scrape endpoint
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

app.listen(PORT, () => {
  console.log(`[CloudSentinel] App running on port ${PORT}`);
  console.log(`[CloudSentinel] Metrics available at /metrics`);
});
