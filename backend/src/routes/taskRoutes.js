const express = require("express");
const deadlineService = require("../services/deadlineService");
const { requireAuth } = require("../middleware/authMiddleware");
const { sendSuccess } = require("../utils/apiResponse");

const router = express.Router();

function getClientIp(req) {
  const forwarded = req.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim().length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || null;
}

router.use(requireAuth);

router.get("/working-days", async (req, res, next) => {
  try {
    const data = await deadlineService.calculateWorkingDays({
      fromDate: req.query.from_date,
      toDate: req.query.to_date,
      status: req.query.status,
    });
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

async function handleGetDeadlineSettings(req, res, next) {
  try {
    const data = await deadlineService.getDeadlineSettings();
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
}

async function handleUpdateDeadlineSettings(req, res, next) {
  try {
    const body = req.body || {};
    const data = await deadlineService.updateDeadlineSettings({
      userId: req.auth.user.user_id,
      roleId: req.auth.active_role.role_id,
      roleCode: req.auth.active_role.code,
      dueSoonWorkingDays: body.due_soon_working_days,
      ipAddress: getClientIp(req),
    });
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
}

router.get("/deadline-settings", handleGetDeadlineSettings);
router.get("/settings", handleGetDeadlineSettings);
router.put("/deadline-settings", handleUpdateDeadlineSettings);
router.put("/settings", handleUpdateDeadlineSettings);

router.get("/calendar", async (req, res, next) => {
  try {
    const data = await deadlineService.getCalendarDays({
      fromDate: req.query.from_date,
      toDate: req.query.to_date,
    });
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

async function handleGetAlerts(req, res, next) {
  try {
    const result = await deadlineService.listTasksWithDeadline({
      userId: req.auth.user.user_id,
      roleId: req.auth.active_role.role_id,
      scope: req.query.scope || "visible",
      deadlineState: "ALERT",
      status: req.query.status,
      fieldId: req.query.field_id,
      keyword: req.query.keyword,
      today: req.query.today,
      page: req.query.page,
      pageSize: req.query.page_size,
    });
    return sendSuccess(
      res,
      { items: result.items, summary: result.summary },
      200,
      result.meta,
    );
  } catch (error) {
    return next(error);
  }
}

router.get("/alerts", handleGetAlerts);
router.get("/overdue", handleGetAlerts);

async function handleGenerateDeadlineNotifications(req, res, next) {
  try {
    const body = req.body || {};
    const data = await deadlineService.generateDeadlineNotifications({
      userId: req.auth.user.user_id,
      roleId: req.auth.active_role.role_id,
      today: body.today ?? req.query.today,
    });
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
}

router.post("/deadline-notifications", handleGenerateDeadlineNotifications);
router.post("/notify", handleGenerateDeadlineNotifications);

router.get("/", async (req, res, next) => {
  try {
    const result = await deadlineService.listTasksWithDeadline({
      userId: req.auth.user.user_id,
      roleId: req.auth.active_role.role_id,
      scope: req.query.scope || "mine",
      deadlineState: req.query.deadline_state,
      status: req.query.status,
      fieldId: req.query.field_id,
      keyword: req.query.keyword,
      today: req.query.today,
      page: req.query.page,
      pageSize: req.query.page_size,
    });
    return sendSuccess(
      res,
      { items: result.items, summary: result.summary },
      200,
      result.meta,
    );
  } catch (error) {
    return next(error);
  }
});

router.get("/:id", async (req, res, next) => {
  try {
    const data = await deadlineService.getTaskDeadlineDetail({
      userId: req.auth.user.user_id,
      roleId: req.auth.active_role.role_id,
      taskId: req.params.id,
      today: req.query.today,
    });
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
});

async function handleUpdateProgress(req, res, next) {
  try {
    const body = req.body || {};
    const data = await deadlineService.updateTaskProgress({
      userId: req.auth.user.user_id,
      roleId: req.auth.active_role.role_id,
      taskId: req.params.id,
      newStatus: body.new_status ?? body.status,
      progressPercent: body.progress_percent ?? body.progress,
      note: body.note ?? body.result_note,
      rowVer: body.row_ver,
      today: body.today ?? req.query.today,
    });
    return sendSuccess(res, data);
  } catch (error) {
    return next(error);
  }
}

router.patch("/:id/progress", handleUpdateProgress);
router.put("/:id/progress", handleUpdateProgress);

module.exports = router;
