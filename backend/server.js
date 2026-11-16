const path = require("node:path");
const cors = require("cors");
const dotenv = require("dotenv");
const express = require("express");
const { getPool } = require("./src/config/db");
const authRoutes = require("./src/routes/authRoutes");
const {
  mapErrorToHttp,
  sendError,
  sendSuccess,
} = require("./src/utils/apiResponse");

dotenv.config({ path: path.resolve(__dirname, "..", ".env") });

const app = express();
const PORT = Number(process.env.PORT || 8080);

app.use(
  cors({
    origin: process.env.CORS_ORIGIN || "http://localhost:5173",
  }),
);
app.use(express.json());

app.get("/api/health", async (req, res) => {
  try {
    const pool = await getPool();
    await pool.request().query("SELECT 1 AS [health_check]");

    return sendSuccess(res, {
      database: "connected",
    });
  } catch (error) {
    console.error("SQL Server health check failed:", error.message);

    return sendError(
      res,
      503,
      "DATABASE_UNAVAILABLE",
      "Không thể kết nối SQL Server.",
    );
  }
});

app.use("/api/auth", authRoutes);

app.use("/api", (req, res) => {
  return sendError(
    res,
    404,
    "NOT_FOUND",
    "Không tìm thấy đường dẫn API yêu cầu.",
  );
});

app.use((error, req, res, next) => {
  if (error instanceof SyntaxError && error.status === 400 && "body" in error) {
    return sendError(
      res,
      400,
      "BAD_REQUEST",
      "Dữ liệu JSON gửi lên không hợp lệ.",
      50400,
    );
  }

  const mapped = mapErrorToHttp(error);
  if (mapped.status === 500) {
    console.error("Unhandled API error:", error);
  }

  return sendError(
    res,
    mapped.status,
    mapped.code,
    mapped.message,
    mapped.sqlError,
  );
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
  });
}

module.exports = {
  app,
  getPool,
};
