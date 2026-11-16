const express = require("express");
const authService = require("../services/authService");
const {
  extractBearerToken,
  requireAuth,
} = require("../middleware/authMiddleware");
const { sendSuccess } = require("../utils/apiResponse");

const router = express.Router();

function getClientIp(req) {
  const forwarded = req.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim().length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || null;
}

async function handleGetDemoAccounts(req, res, next) {
  try {
    const data = await authService.getDemoAccounts();
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
}

router.get("/demo-accounts", handleGetDemoAccounts);
router.get("/demo-roles", handleGetDemoAccounts);

router.post("/login", async (req, res, next) => {
  try {
    const body = req.body || {};
    const data = await authService.login({
      username: body.username,
      password: body.password,
      roleId: body.role_id,
      roleCode: body.role_code,
      ipAddress: getClientIp(req),
      userAgent: req.headers?.["user-agent"] || null,
    });

    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

router.post("/demo-login", async (req, res, next) => {
  try {
    const body = req.body || {};
    const data = await authService.demoQuickLogin({
      roleId: body.role_id,
      roleCode: body.role_code,
      userId: body.user_id,
      username: body.username,
      currentSessionId: extractBearerToken(req),
      ipAddress: getClientIp(req),
      userAgent: req.headers?.["user-agent"] || null,
    });

    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

async function handleGetSession(req, res) {
  return sendSuccess(res, req.auth);
}

router.get("/me", requireAuth, handleGetSession);
router.get("/session", requireAuth, handleGetSession);

router.post("/logout", requireAuth, async (req, res, next) => {
  try {
    const data = await authService.logout({
      sessionId: req.auth.session_id,
      userId: req.auth.user.user_id,
      activeRoleId: req.auth.active_role.role_id,
      ipAddress: getClientIp(req),
    });

    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

router.post("/switch-role", requireAuth, async (req, res, next) => {
  try {
    const body = req.body || {};
    const data = await authService.switchRole({
      sessionId: req.auth.session_id,
      newRoleId: body.role_id ?? body.new_role_id,
      roleCode: body.role_code,
    });

    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

router.get("/permissions", requireAuth, async (req, res, next) => {
  try {
    const data = await authService.getPermissions({
      userId: req.auth.user.user_id,
      activeRoleId: req.auth.active_role.role_id,
    });

    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

module.exports = router;
