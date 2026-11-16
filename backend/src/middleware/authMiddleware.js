const { getPool } = require("../config/db");
const { getSessionContext } = require("../services/authService");
const { AppError } = require("../utils/apiResponse");

function extractBearerToken(req) {
  const authHeader = req.headers?.authorization;
  if (typeof authHeader !== "string") {
    return null;
  }

  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return null;
  }

  const token = match[1].trim();
  return token.length > 0 ? token : null;
}

async function requireAuth(req, res, next) {
  try {
    const token = extractBearerToken(req);
    if (!token) {
      throw new AppError(401, "UNAUTHORIZED", "Vui lòng đăng nhập để tiếp tục.");
    }

    const pool = await getPool();
    req.auth = await getSessionContext(pool, token, { touch: true });
    return next();
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  extractBearerToken,
  requireAuth,
};
