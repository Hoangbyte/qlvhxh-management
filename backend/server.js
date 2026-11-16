const path = require("node:path");
const cors = require("cors");
const dotenv = require("dotenv");
const express = require("express");
const sql = require("mssql");

dotenv.config({ path: path.resolve(__dirname, "..", ".env") });

const app = express();
const PORT = Number(process.env.PORT || 8080);
const dbConfig = {
  server: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 1433),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  connectionTimeout: 5000,
  requestTimeout: 5000,
  options: {
    encrypt: process.env.DB_ENCRYPT === "true",
    trustServerCertificate:
      process.env.DB_TRUST_SERVER_CERTIFICATE === "true",
  },
};

app.use(
  cors({
    origin: process.env.CORS_ORIGIN || "http://localhost:5173",
  }),
);

let poolPromise;

function getPool() {
  if (!poolPromise) {
    const pool = new sql.ConnectionPool(dbConfig);
    poolPromise = pool.connect().catch((error) => {
      poolPromise = undefined;
      throw error;
    });
  }

  return poolPromise;
}

app.get("/api/health", async (req, res) => {
  try {
    const pool = await getPool();
    await pool.request().query("SELECT 1 AS [health_check]");

    return res.status(200).json({
      success: true,
      data: {
        database: "connected",
      },
    });
  } catch (error) {
    console.error("SQL Server health check failed:", error.message);

    return res.status(503).json({
      success: false,
      error: {
        code: "DATABASE_UNAVAILABLE",
        message: "Không thể kết nối SQL Server.",
      },
    });
  }
});

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
