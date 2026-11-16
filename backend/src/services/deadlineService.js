const { getPool, sql } = require("../config/db");
const { AppError } = require("../utils/apiResponse");

const ISO_DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const VALID_TASK_STATUSES = new Set(["NEW", "IN_PROGRESS", "DONE", "CANCELLED"]);
const VALID_DEADLINE_STATES = new Set([
  "OVERDUE",
  "DUE_SOON",
  "ON_TRACK",
  "DONE",
  "CANCELLED",
  "ALERT",
]);
const DEADLINE_MANAGER_ROLES = new Set(["PCT", "TP"]);

function parsePositiveInt(value, fieldLabel) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new AppError(400, "BAD_REQUEST", `${fieldLabel} không hợp lệ.`, 50400);
  }
  return parsed;
}

function parseIsoDate(value, fieldLabel) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string" || !ISO_DATE_REGEX.test(value.trim())) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      `${fieldLabel} phải theo định dạng YYYY-MM-DD.`,
      50400,
    );
  }

  const trimmed = value.trim();
  const [year, month, day] = trimmed.split("-").map(Number);
  const utc = new Date(Date.UTC(year, month - 1, day));
  if (
    utc.getUTCFullYear() !== year ||
    utc.getUTCMonth() + 1 !== month ||
    utc.getUTCDate() !== day
  ) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      `${fieldLabel} không phải ngày hợp lệ.`,
      50400,
    );
  }

  return trimmed;
}

function formatDateOnly(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value === "string") {
    const match = value.match(/^(\d{4}-\d{2}-\d{2})/);
    if (match) {
      return match[1];
    }
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  return String(value);
}

function bufferToHex(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (Buffer.isBuffer(value)) {
    return `0x${value.toString("hex").toUpperCase()}`;
  }
  if (typeof value === "string") {
    return value.startsWith("0x") ? value : `0x${value}`;
  }
  return null;
}

function hexToBuffer(value) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (Buffer.isBuffer(value)) {
    if (value.length !== 8) {
      throw new AppError(
        400,
        "BAD_REQUEST",
        "Mã phiên bản dữ liệu (row_ver) không hợp lệ.",
        50400,
      );
    }
    return value;
  }
  if (typeof value !== "string") {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Mã phiên bản dữ liệu (row_ver) không hợp lệ.",
      50400,
    );
  }

  const cleaned = value.trim().replace(/^0x/i, "");
  if (!/^[0-9a-f]{16}$/i.test(cleaned)) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Mã phiên bản dữ liệu (row_ver) không hợp lệ.",
      50400,
    );
  }
  return Buffer.from(cleaned, "hex");
}

function buildDeadlineLabel(deadlineState, workingDaysLeft, isDoneLate) {
  switch (deadlineState) {
    case "DONE":
      return isDoneLate ? "Hoàn thành trễ hạn" : "Đã hoàn thành";
    case "CANCELLED":
      return "Đã hủy";
    case "OVERDUE":
      return workingDaysLeft !== null
        ? `Quá hạn ${Math.abs(workingDaysLeft)} ngày làm việc`
        : "Quá hạn";
    case "DUE_SOON":
      return workingDaysLeft === 0
        ? "Hạn hôm nay"
        : `Sắp đến hạn (còn ${workingDaysLeft} ngày làm việc)`;
    case "ON_TRACK":
    default:
      return workingDaysLeft !== null
        ? `Còn ${workingDaysLeft} ngày làm việc`
        : "Trong hạn (chưa có lịch ngày làm việc)";
  }
}

function enrichTaskRow(row, dueSoonDays) {
  const workingDaysLeft =
    row.working_days_left === null || row.working_days_left === undefined
      ? null
      : Number(row.working_days_left);
  const calendarCovered = workingDaysLeft !== null;
  const isDoneLate = Boolean(row.is_done_late);

  return {
    task_id: row.task_id,
    task_code: row.task_code,
    title: row.title,
    ...(row.description !== undefined ? { description: row.description } : {}),
    field_id: row.field_id,
    field_name: row.field_name,
    document_id: row.document_id ?? null,
    meeting_id: row.meeting_id ?? null,
    ...(row.parent_task_id !== undefined
      ? { parent_task_id: row.parent_task_id ?? null }
      : {}),
    assigned_by: row.assigned_by,
    assigned_by_name: row.assigned_by_name,
    assignee_id: row.assignee_id,
    assignee_name: row.assignee_name,
    is_mine: Boolean(row.is_mine),
    priority: row.priority,
    status: row.status,
    progress_percent: Number(row.progress_percent),
    start_date: formatDateOnly(row.start_date),
    due_date: formatDateOnly(row.due_date),
    original_due_date: formatDateOnly(row.original_due_date),
    completed_at: row.completed_at ?? null,
    ...(row.result_note !== undefined
      ? { result_note: row.result_note ?? null }
      : {}),
    ...(row.created_at !== undefined ? { created_at: row.created_at } : {}),
    ...(row.updated_at !== undefined
      ? { updated_at: row.updated_at ?? null }
      : {}),
    ...(row.row_ver !== undefined ? { row_ver: bufferToHex(row.row_ver) } : {}),
    working_days_left: workingDaysLeft,
    calendar_covered: calendarCovered,
    deadline_state: row.deadline_state,
    deadline_label: buildDeadlineLabel(
      row.deadline_state,
      workingDaysLeft,
      isDoneLate,
    ),
    is_overdue: row.deadline_state === "OVERDUE",
    is_due_soon: row.deadline_state === "DUE_SOON",
    is_done_late: isDoneLate,
    was_extended: Boolean(row.was_extended),
    due_soon_threshold_days: dueSoonDays,
  };
}

async function fetchDueSoonDays(pool) {
  const result = await pool.request().query(`
    SELECT ISNULL(dbo.fn_setting_int('DUE_SOON_WORKING_DAYS'), 2) AS due_soon_days
  `);
  const val = result.recordset?.[0]?.due_soon_days;
  return val !== undefined && val !== null ? Number(val) : 2;
}

async function writeTaskAudit(pool, { userId, roleId, action, entityType, entityId, detail, ipAddress }) {
  try {
    const cleanIp =
      typeof ipAddress === "string" && ipAddress.trim().length > 0
        ? ipAddress.trim().slice(0, 45)
        : null;
    const detailJson =
      detail === null || detail === undefined
        ? null
        : typeof detail === "string"
          ? detail
          : JSON.stringify(detail);

    await pool
      .request()
      .input("user_id", sql.Int, userId)
      .input("role_id", sql.Int, roleId)
      .input("action", sql.VarChar(20), action)
      .input("entity_type", sql.VarChar(12), entityType)
      .input("entity_id", sql.Int, entityId)
      .input("detail", sql.NVarChar(sql.MAX), detailJson)
      .input("ip_address", sql.VarChar(45), cleanIp)
      .query(`
        EXEC dbo.sp_write_audit
          @user_id = @user_id,
          @role_id = @role_id,
          @action = @action,
          @entity_type = @entity_type,
          @entity_id = @entity_id,
          @detail = @detail,
          @ip_address = @ip_address
      `);
  } catch (error) {
    console.error("Failed to write audit log:", error.message);
  }
}

async function getDeadlineSettings() {
  const pool = await getPool();
  const [dueSoonDays, coverageResult] = await Promise.all([
    fetchDueSoonDays(pool),
    pool.request().query(`
      SELECT
        MIN(cal_date) AS min_date,
        MAX(cal_date) AS max_date,
        COUNT(*) AS total_days
      FROM dbo.calendar_days
    `),
  ]);

  const cov = coverageResult.recordset?.[0] || {};
  return {
    due_soon_working_days: dueSoonDays,
    calendar_coverage: {
      min_date: formatDateOnly(cov.min_date),
      max_date: formatDateOnly(cov.max_date),
      total_days: Number(cov.total_days || 0),
    },
  };
}

async function updateDeadlineSettings({
  userId,
  roleId,
  roleCode,
  dueSoonWorkingDays,
  ipAddress,
}) {
  if (!DEADLINE_MANAGER_ROLES.has(roleCode)) {
    throw new AppError(
      403,
      "FORBIDDEN",
      "Chỉ Lãnh đạo (Phó Chủ tịch, Trưởng phòng) mới được thay đổi cấu hình ngưỡng sắp hạn.",
      50403,
    );
  }

  const parsedDays = Number(dueSoonWorkingDays);
  if (!Number.isInteger(parsedDays) || parsedDays < 1 || parsedDays > 30) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Ngưỡng sắp hạn phải là số nguyên từ 1 đến 30 ngày làm việc.",
      50400,
    );
  }

  const pool = await getPool();
  const previousDays = await fetchDueSoonDays(pool);

  await pool
    .request()
    .input("setting_value", sql.NVarChar(200), String(parsedDays))
    .query(`
      IF EXISTS (SELECT 1 FROM dbo.system_settings WHERE setting_key = 'DUE_SOON_WORKING_DAYS')
        UPDATE dbo.system_settings
        SET setting_value = @setting_value,
            updated_at = SYSDATETIME()
        WHERE setting_key = 'DUE_SOON_WORKING_DAYS';
      ELSE
        INSERT INTO dbo.system_settings (setting_key, setting_value, description)
        VALUES ('DUE_SOON_WORKING_DAYS', @setting_value, N'Còn <= N ngày làm việc thì tính là sắp hạn');
    `);

  await writeTaskAudit(pool, {
    userId,
    roleId,
    action: "UPDATE",
    entityType: null,
    entityId: null,
    detail: {
      setting_key: "DUE_SOON_WORKING_DAYS",
      old_value: previousDays,
      new_value: parsedDays,
    },
    ipAddress,
  });

  return getDeadlineSettings();
}

async function calculateWorkingDays({
  fromDate,
  toDate,
  status = "IN_PROGRESS",
}) {
  const effectiveTo = parseIsoDate(toDate, "Ngày hạn (to_date)");
  if (!effectiveTo) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Vui lòng cung cấp ngày hạn (to_date).",
      50400,
    );
  }

  const effectiveFrom = parseIsoDate(fromDate, "Ngày bắt đầu (from_date)");
  const normalizedStatus =
    typeof status === "string" && status.trim().length > 0
      ? status.trim().toUpperCase()
      : "IN_PROGRESS";

  if (!VALID_TASK_STATUSES.has(normalizedStatus)) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Trạng thái nhiệm vụ không hợp lệ.",
      50400,
    );
  }

  const pool = await getPool();
  const result = await pool
    .request()
    .input("from_date", sql.Date, effectiveFrom)
    .input("to_date", sql.Date, effectiveTo)
    .query(`
      DECLARE @f DATE = ISNULL(@from_date, CAST(SYSDATETIME() AS DATE));
      SELECT
        @f AS effective_from_date,
        @to_date AS effective_to_date,
        dbo.fn_working_days_between(@f, @to_date) AS working_days_left,
        ISNULL(dbo.fn_setting_int('DUE_SOON_WORKING_DAYS'), 2) AS due_soon_days,
        CASE WHEN @to_date < @f THEN 1 ELSE 0 END AS is_past_due,
        CASE WHEN EXISTS (SELECT 1 FROM dbo.calendar_days WHERE cal_date = @f) THEN 1 ELSE 0 END AS has_from_date,
        CASE WHEN EXISTS (SELECT 1 FROM dbo.calendar_days WHERE cal_date = @to_date) THEN 1 ELSE 0 END AS has_to_date;
    `);

  const row = result.recordset?.[0];
  const workingDaysLeft =
    row.working_days_left === null || row.working_days_left === undefined
      ? null
      : Number(row.working_days_left);
  const dueSoonDays = Number(row.due_soon_days ?? 2);
  const calendarCovered = workingDaysLeft !== null;

  let deadlineState;
  if (normalizedStatus === "DONE" || normalizedStatus === "CANCELLED") {
    deadlineState = normalizedStatus;
  } else if (Number(row.is_past_due) === 1) {
    deadlineState = "OVERDUE";
  } else if (calendarCovered && workingDaysLeft <= dueSoonDays) {
    deadlineState = "DUE_SOON";
  } else {
    deadlineState = "ON_TRACK";
  }

  return {
    from_date: formatDateOnly(row.effective_from_date),
    to_date: formatDateOnly(row.effective_to_date),
    status: normalizedStatus,
    working_days_left: workingDaysLeft,
    calendar_covered: calendarCovered,
    has_from_date: Boolean(row.has_from_date),
    has_to_date: Boolean(row.has_to_date),
    due_soon_working_days: dueSoonDays,
    deadline_state: deadlineState,
    deadline_label: buildDeadlineLabel(deadlineState, workingDaysLeft, false),
    is_overdue: deadlineState === "OVERDUE",
    is_due_soon: deadlineState === "DUE_SOON",
  };
}

async function getCalendarDays({ fromDate, toDate }) {
  const pool = await getPool();
  let effectiveFrom = parseIsoDate(fromDate, "Ngày bắt đầu (from_date)");
  let effectiveTo = parseIsoDate(toDate, "Ngày kết thúc (to_date)");

  if (!effectiveFrom || !effectiveTo) {
    const todayResult = await pool.request().query(`
      SELECT
        CAST(SYSDATETIME() AS DATE) AS today_date,
        DATEADD(DAY, 30, CAST(SYSDATETIME() AS DATE)) AS plus30_date
    `);
    const todayRow = todayResult.recordset?.[0];
    if (!effectiveFrom) {
      effectiveFrom = formatDateOnly(todayRow.today_date);
    }
    if (!effectiveTo) {
      effectiveTo = formatDateOnly(
        new Date(
          new Date(`${effectiveFrom}T00:00:00Z`).getTime() + 30 * 86400_000,
        ),
      );
    }
  }

  const fromMs = Date.parse(`${effectiveFrom}T00:00:00Z`);
  const toMs = Date.parse(`${effectiveTo}T00:00:00Z`);
  if (fromMs > toMs) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Ngày bắt đầu phải nhỏ hơn hoặc bằng ngày kết thúc.",
      50400,
    );
  }

  const requestedDaysCount = Math.round((toMs - fromMs) / 86400_000) + 1;
  if (requestedDaysCount > 366) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Khoảng thời gian tra cứu lịch làm việc tối đa 366 ngày.",
      50400,
    );
  }

  const result = await pool
    .request()
    .input("from_date", sql.Date, effectiveFrom)
    .input("to_date", sql.Date, effectiveTo)
    .query(`
      SELECT cal_date, is_working_day, note
      FROM dbo.calendar_days
      WHERE cal_date BETWEEN @from_date AND @to_date
      ORDER BY cal_date ASC
    `);

  const rows = result.recordset || [];
  return {
    from_date: effectiveFrom,
    to_date: effectiveTo,
    requested_days_count: requestedDaysCount,
    calendar_days_found: rows.length,
    is_fully_covered: rows.length === requestedDaysCount,
    days: rows.map((row) => ({
      cal_date: formatDateOnly(row.cal_date),
      is_working_day: Boolean(row.is_working_day),
      note: row.note ?? null,
    })),
  };
}

async function listTasksWithDeadline({
  userId,
  roleId,
  scope = "mine",
  deadlineState,
  status,
  fieldId,
  keyword,
  today,
  page = 1,
  pageSize = 20,
}) {
  const effectiveToday = parseIsoDate(today, "Ngày mốc (today)");
  const normalizedScope =
    typeof scope === "string" && scope.trim().length > 0
      ? scope.trim().toLowerCase()
      : "mine";

  if (!["mine", "all", "visible"].includes(normalizedScope)) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Phạm vi lọc (scope) không hợp lệ.",
      50400,
    );
  }

  const normalizedDeadlineState =
    typeof deadlineState === "string" && deadlineState.trim().length > 0
      ? deadlineState.trim().toUpperCase()
      : null;

  if (
    normalizedDeadlineState !== null &&
    !VALID_DEADLINE_STATES.has(normalizedDeadlineState)
  ) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Trạng thái hạn (deadline_state) không hợp lệ.",
      50400,
    );
  }

  const normalizedStatus =
    typeof status === "string" && status.trim().length > 0
      ? status.trim().toUpperCase()
      : null;

  if (normalizedStatus !== null && !VALID_TASK_STATUSES.has(normalizedStatus)) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Trạng thái nhiệm vụ (status) không hợp lệ.",
      50400,
    );
  }

  const parsedFieldId = parsePositiveInt(fieldId, "Mã lĩnh vực");
  const parsedPage = parsePositiveInt(page, "Trang") ?? 1;
  const parsedPageSize = parsePositiveInt(pageSize, "Kích thước trang") ?? 20;
  const clampedPageSize = Math.min(Math.max(parsedPageSize, 1), 100);
  const trimmedKeyword =
    typeof keyword === "string" && keyword.trim().length > 0
      ? keyword.trim()
      : null;

  const pool = await getPool();
  const permCheck = await pool
    .request()
    .input("user_id", sql.Int, userId)
    .input("role_id", sql.Int, roleId)
    .query(`
      SELECT dbo.fn_has_permission(@user_id, @role_id, 'F06_MY_TASKS', 'X') AS allowed
    `);

  if (!permCheck.recordset?.[0]?.allowed) {
    throw new AppError(
      403,
      "FORBIDDEN",
      "Vai trò hiện tại không có quyền xem danh sách nhiệm vụ.",
      50403,
    );
  }

  const onlyMine = normalizedScope === "mine" ? 1 : 0;

  const [dueSoonDays, summaryResult, listResult] = await Promise.all([
    fetchDueSoonDays(pool),
    pool
      .request()
      .input("user_id", sql.Int, userId)
      .input("role_id", sql.Int, roleId)
      .input("today", sql.Date, effectiveToday)
      .input("only_mine", sql.Bit, onlyMine)
      .query(`
        DECLARE @t DATE = ISNULL(@today, CAST(SYSDATETIME() AS DATE));
        SELECT
          COUNT(*) AS total,
          SUM(CASE WHEN deadline_state = 'OVERDUE' THEN 1 ELSE 0 END) AS overdue,
          SUM(CASE WHEN deadline_state = 'DUE_SOON' THEN 1 ELSE 0 END) AS due_soon,
          SUM(CASE WHEN deadline_state = 'ON_TRACK' THEN 1 ELSE 0 END) AS on_track,
          SUM(CASE WHEN deadline_state = 'DONE' THEN 1 ELSE 0 END) AS done,
          SUM(CASE WHEN deadline_state = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled
        FROM dbo.fn_visible_tasks(@user_id, @role_id, @t)
        WHERE (@only_mine = 0 OR is_mine = 1);
      `),
    pool
      .request()
      .input("user_id", sql.Int, userId)
      .input("role_id", sql.Int, roleId)
      .input("today", sql.Date, effectiveToday)
      .input("only_mine", sql.Bit, onlyMine)
      .input("deadline_state", sql.VarChar(20), normalizedDeadlineState)
      .input("status", sql.VarChar(12), normalizedStatus)
      .input("field_id", sql.Int, parsedFieldId)
      .input("keyword", sql.NVarChar(200), trimmedKeyword)
      .input("offset", sql.Int, (parsedPage - 1) * clampedPageSize)
      .input("page_size", sql.Int, clampedPageSize)
      .query(`
        DECLARE @t DATE = ISNULL(@today, CAST(SYSDATETIME() AS DATE));
        SELECT
          vt.*,
          COUNT(*) OVER () AS total_rows
        FROM dbo.fn_visible_tasks(@user_id, @role_id, @t) vt
        WHERE (@only_mine = 0 OR vt.is_mine = 1)
          AND (@status IS NULL OR vt.status = @status)
          AND (@field_id IS NULL OR vt.field_id = @field_id)
          AND (
            @deadline_state IS NULL
            OR (@deadline_state = 'ALERT' AND vt.deadline_state IN ('OVERDUE', 'DUE_SOON'))
            OR vt.deadline_state = @deadline_state
          )
          AND (
            @keyword IS NULL
            OR vt.task_code LIKE N'%' + @keyword + N'%'
            OR vt.title LIKE N'%' + @keyword + N'%'
          )
        ORDER BY
          CASE vt.deadline_state
            WHEN 'OVERDUE' THEN 0
            WHEN 'DUE_SOON' THEN 1
            WHEN 'ON_TRACK' THEN 2
            WHEN 'DONE' THEN 3
            ELSE 4
          END,
          vt.due_date ASC,
          vt.task_id DESC
        OFFSET @offset ROWS FETCH NEXT @page_size ROWS ONLY;
      `),
  ]);

  const rows = listResult.recordset || [];
  const totalRows = rows.length > 0 ? Number(rows[0].total_rows) : 0;
  const s = summaryResult.recordset?.[0] || {};

  return {
    items: rows.map((row) => enrichTaskRow(row, dueSoonDays)),
    summary: {
      total: Number(s.total || 0),
      overdue: Number(s.overdue || 0),
      due_soon: Number(s.due_soon || 0),
      on_track: Number(s.on_track || 0),
      done: Number(s.done || 0),
      cancelled: Number(s.cancelled || 0),
      due_soon_working_days: dueSoonDays,
    },
    meta: {
      page: parsedPage,
      page_size: clampedPageSize,
      total_rows: totalRows,
    },
  };
}

async function getTaskDeadlineDetail({ userId, roleId, taskId, today }) {
  const parsedTaskId = parsePositiveInt(taskId, "Mã nhiệm vụ");
  if (!parsedTaskId) {
    throw new AppError(400, "BAD_REQUEST", "Mã nhiệm vụ không hợp lệ.", 50400);
  }
  const effectiveToday = parseIsoDate(today, "Ngày mốc (today)");

  const pool = await getPool();
  const [dueSoonDays, taskResult] = await Promise.all([
    fetchDueSoonDays(pool),
    pool
      .request()
      .input("user_id", sql.Int, userId)
      .input("role_id", sql.Int, roleId)
      .input("task_id", sql.Int, parsedTaskId)
      .input("today", sql.Date, effectiveToday)
      .query(`
        DECLARE @t DATE = ISNULL(@today, CAST(SYSDATETIME() AS DATE));
        SELECT
          vt.*,
          t.description,
          t.parent_task_id,
          t.result_note,
          t.created_at,
          t.updated_at,
          t.row_ver
        FROM dbo.fn_visible_tasks(@user_id, @role_id, @t) vt
        JOIN dbo.tasks t ON t.task_id = vt.task_id
        WHERE vt.task_id = @task_id;
      `),
  ]);

  const row = taskResult.recordset?.[0];
  if (!row) {
    const existsResult = await pool
      .request()
      .input("task_id", sql.Int, parsedTaskId)
      .query("SELECT task_id FROM dbo.tasks WHERE task_id = @task_id");

    if (!existsResult.recordset?.[0]) {
      throw new AppError(404, "NOT_FOUND", "Không tìm thấy nhiệm vụ.", 50404);
    }

    throw new AppError(
      403,
      "FORBIDDEN",
      "Bạn không có quyền xem chi tiết nhiệm vụ này.",
      50403,
    );
  }

  const [updatesResult, extensionsResult, attachmentsResult] = await Promise.all([
    pool
      .request()
      .input("task_id", sql.Int, parsedTaskId)
      .query(`
        SELECT tu.update_id, tu.task_id, tu.updated_by, u.full_name AS updated_by_name,
               tu.old_status, tu.new_status, tu.progress_percent, tu.note, tu.created_at
        FROM dbo.task_updates tu
        JOIN dbo.users u ON u.user_id = tu.updated_by
        WHERE tu.task_id = @task_id
        ORDER BY tu.created_at DESC, tu.update_id DESC
      `),
    pool
      .request()
      .input("task_id", sql.Int, parsedTaskId)
      .query(`
        SELECT e.request_id, e.task_id, e.requested_by, ur.full_name AS requested_by_name,
               e.old_due_date, e.proposed_due_date, e.reason, e.status,
               e.decided_by, ud.full_name AS decided_by_name, e.decided_at,
               e.decision_note, e.created_at
        FROM dbo.extension_requests e
        JOIN dbo.users ur ON ur.user_id = e.requested_by
        LEFT JOIN dbo.users ud ON ud.user_id = e.decided_by
        WHERE e.task_id = @task_id
        ORDER BY e.created_at DESC, e.request_id DESC
      `),
    pool
      .request()
      .input("task_id", sql.Int, parsedTaskId)
      .query(`
        SELECT a.attachment_id, a.original_name, a.mime_type, a.file_ext,
               a.size_bytes, a.uploaded_by, u.full_name AS uploaded_by_name, a.uploaded_at
        FROM dbo.attachments a
        JOIN dbo.users u ON u.user_id = a.uploaded_by
        WHERE a.task_id = @task_id AND a.is_deleted = 0
        ORDER BY a.uploaded_at DESC, a.attachment_id DESC
      `),
  ]);

  return {
    ...enrichTaskRow(row, dueSoonDays),
    updates: updatesResult.recordset || [],
    extension_requests: (extensionsResult.recordset || []).map((ext) => ({
      ...ext,
      old_due_date: formatDateOnly(ext.old_due_date),
      proposed_due_date: formatDateOnly(ext.proposed_due_date),
    })),
    attachments: attachmentsResult.recordset || [],
  };
}

async function updateTaskProgress({
  userId,
  roleId,
  taskId,
  newStatus,
  progressPercent,
  note,
  rowVer,
  today,
}) {
  const parsedTaskId = parsePositiveInt(taskId, "Mã nhiệm vụ");
  if (!parsedTaskId) {
    throw new AppError(400, "BAD_REQUEST", "Mã nhiệm vụ không hợp lệ.", 50400);
  }

  if (typeof newStatus !== "string" || newStatus.trim().length === 0) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Vui lòng chọn trạng thái mới (IN_PROGRESS hoặc DONE).",
      50400,
    );
  }

  const normalizedStatus = newStatus.trim().toUpperCase();
  if (!["IN_PROGRESS", "DONE"].includes(normalizedStatus)) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Trạng thái mới không hợp lệ (chỉ Đang làm hoặc Hoàn thành).",
      50400,
    );
  }

  let effectiveProgress;
  if (normalizedStatus === "DONE") {
    effectiveProgress = 100;
  } else {
    if (
      progressPercent === undefined ||
      progressPercent === null ||
      progressPercent === ""
    ) {
      throw new AppError(
        400,
        "BAD_REQUEST",
        "Vui lòng nhập phần trăm tiến độ (0–99).",
        50400,
      );
    }
    const parsedProgress = Number(progressPercent);
    if (
      !Number.isInteger(parsedProgress) ||
      parsedProgress < 0 ||
      parsedProgress > 100
    ) {
      throw new AppError(
        400,
        "BAD_REQUEST",
        "Tiến độ phải là số nguyên trong khoảng 0–100%.",
        50400,
      );
    }
    if (parsedProgress === 100) {
      throw new AppError(
        400,
        "BAD_REQUEST",
        "Tiến độ 100% thì chọn trạng thái Hoàn thành.",
        50400,
      );
    }
    effectiveProgress = parsedProgress;
  }

  const rowVerBuffer = hexToBuffer(rowVer);
  const cleanNote =
    typeof note === "string" && note.trim().length > 0
      ? note.trim().slice(0, 1000)
      : null;

  const pool = await getPool();
  await pool
    .request()
    .input("user_id", sql.Int, userId)
    .input("role_id", sql.Int, roleId)
    .input("task_id", sql.Int, parsedTaskId)
    .input("new_status", sql.VarChar(12), normalizedStatus)
    .input("progress", sql.TinyInt, effectiveProgress)
    .input("note", sql.NVarChar(1000), cleanNote)
    .input("row_ver", sql.VarBinary(8), rowVerBuffer)
    .query(`
      EXEC dbo.sp_update_task_progress
        @user_id = @user_id,
        @role_id = @role_id,
        @task_id = @task_id,
        @new_status = @new_status,
        @progress = @progress,
        @note = @note,
        @row_ver = @row_ver
    `);

  return getTaskDeadlineDetail({
    userId,
    roleId,
    taskId: parsedTaskId,
    today,
  });
}

async function generateDeadlineNotifications({ roleCode, today }) {
  if (!DEADLINE_MANAGER_ROLES.has(roleCode)) {
    throw new AppError(
      403,
      "FORBIDDEN",
      "Chỉ Phó Chủ tịch hoặc Trưởng phòng mới được sinh thông báo hạn toàn phòng.",
      50403,
    );
  }

  const effectiveToday = parseIsoDate(today, "Ngày mốc (today)");
  const pool = await getPool();

  const result = await pool
    .request()
    .input("today", sql.Date, effectiveToday)
    .query(`
      DECLARE @t DATE = ISNULL(@today, CAST(SYSDATETIME() AS DATE));
      DECLARE @tbl TABLE (notifications_created INT);
      INSERT INTO @tbl (notifications_created)
      EXEC dbo.sp_generate_deadline_notifications @today = @t;
      SELECT @t AS effective_today, ISNULL((SELECT TOP (1) notifications_created FROM @tbl), 0) AS notifications_created;
    `);

  const row = result.recordset?.[0] || {};
  return {
    today: formatDateOnly(row.effective_today) || effectiveToday,
    notifications_created: Number(row.notifications_created || 0),
  };
}

module.exports = {
  getDeadlineSettings,
  updateDeadlineSettings,
  calculateWorkingDays,
  getCalendarDays,
  listTasksWithDeadline,
  getTaskDeadlineDetail,
  updateTaskProgress,
  generateDeadlineNotifications,
};
