const path = require("node:path");
const dotenv = require("dotenv");
const sql = require("mssql");

dotenv.config({ path: path.resolve(__dirname, "..", "..", "..", ".env") });

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

let poolPromise;
let customPoolProvider = null;

function setPoolProvider(providerFn) {
  customPoolProvider = typeof providerFn === "function" ? providerFn : null;
  poolPromise = undefined;
}

function getPool() {
  if (customPoolProvider) {
    return Promise.resolve(customPoolProvider());
  }

  if (!poolPromise) {
    const pool = new sql.ConnectionPool(dbConfig);
    poolPromise = pool.connect().catch((error) => {
      poolPromise = undefined;
      throw error;
    });
  }

  return poolPromise;
}

module.exports = {
  sql,
  dbConfig,
  getPool,
  setPoolProvider,
};
