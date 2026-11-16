const assert = require("node:assert/strict");
const { afterEach, beforeEach, describe, it } = require("node:test");
const { setPoolProvider } = require("../src/config/db");
const { app } = require("../server");

const SEED_PASSWORD_HASH =
  "$2b$10$FOfZy4YtMG3wtXHmwHbs7usVLIjWrm6wD6DB1XgCrn/eKUznPQGH2";

function addDaysIso(baseIso, deltaDays) {
  const ms = Date.parse(`${baseIso}T00:00:00Z`) + deltaDays * 86400_000;
  return new Date(ms).toISOString().slice(0, 10);
}

function buildCalendarMap(baseIso) {
  const baseYear = Number(baseIso.slice(0, 4));
  const map = new Map();
  for (let y = baseYear - 1; y <= baseYear + 1; y++) {
    const start = Date.UTC(y, 0, 1);
    const end = Date.UTC(y, 11, 31);
    for (let ms = start; ms <= end; ms += 86400_000) {
      const dt = new Date(ms);
      const iso = dt.toISOString().slice(0, 10);
      const day = dt.getUTCDay(); // 0 = Sun, 6 = Sat
      let isWorking = day !== 0 && day !== 6;
      let note = day === 6 ? "Thứ Bảy" : day === 0 ? "Chủ nhật" : null;
      if (iso.endsWith("-01-01")) {
        isWorking = false;
        note = "Tết Dương lịch";
      } else if (iso.endsWith("-04-30")) {
        isWorking = false;
        note = "Ngày Giải phóng miền Nam";
      } else if (iso.endsWith("-05-01")) {
        isWorking = false;
        note = "Quốc tế Lao động";
      } else if (iso.endsWith("-09-02")) {
        isWorking = false;
        note = "Quốc khánh";
      }
      map.set(iso, { cal_date: iso, is_working_day: isWorking, note });
    }
  }
  return map;
}

function createDeadlineMockDb(todayIso = "2026-11-16") {
  const calendarMap = buildCalendarMap(todayIso);

  const fields = [
    { field_id: 1, code: "NV", name: "Nội vụ" },
    { field_id: 2, code: "YT", name: "Y tế" },
    { field_id: 3, code: "GD", name: "Giáo dục" },
    { field_id: 4, code: "VHXH", name: "Văn hóa – Xã hội" },
  ];

  const roles = [
    { role_id: 1, code: "PCT", name: "Phó Chủ tịch UBND phụ trách VH – XH", role_level: "LEADER", rank_no: 1, field_id: null },
    { role_id: 2, code: "TP", name: "Trưởng phòng VH – XH", role_level: "LEADER", rank_no: 2, field_id: null },
    { role_id: 3, code: "PTP", name: "Phó Trưởng phòng VH – XH", role_level: "LEADER", rank_no: 3, field_id: null },
    { role_id: 5, code: "CV_YT", name: "Chuyên viên Y tế", role_level: "STAFF", rank_no: 4, field_id: 2 },
    { role_id: 6, code: "CV_GD", name: "Chuyên viên Giáo dục", role_level: "STAFF", rank_no: 4, field_id: 3 },
  ];

  const users = [
    { user_id: 1, username: "pct.vhxh", password_hash: SEED_PASSWORD_HASH, full_name: "Nguyễn Văn An", position_title: "Phó Chủ tịch UBND", email: "pct.vhxh@demo.local", phone: "0901000001", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null },
    { user_id: 2, username: "tp.vhxh", password_hash: SEED_PASSWORD_HASH, full_name: "Trần Thị Bình", position_title: "Trưởng phòng VHXH", email: "tp.vhxh@demo.local", phone: "0901000002", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null },
    { user_id: 3, username: "ptp.vhxh", password_hash: SEED_PASSWORD_HASH, full_name: "Lê Văn Cường", position_title: "Phó Trưởng phòng VHXH", email: "ptp.vhxh@demo.local", phone: "0901000003", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null },
    { user_id: 5, username: "cv.yte", password_hash: SEED_PASSWORD_HASH, full_name: "Hoàng Minh Đức", position_title: "Chuyên viên Y tế", email: "cv.yte@demo.local", phone: "0901000005", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null },
    { user_id: 6, username: "cv.giaoduc", password_hash: SEED_PASSWORD_HASH, full_name: "Vũ Thu Hà", position_title: "Chuyên viên Giáo dục", email: "cv.giaoduc@demo.local", phone: "0901000006", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null },
  ];

  const userRoles = [
    { user_id: 1, role_id: 1, is_default: true },
    { user_id: 2, role_id: 2, is_default: true },
    { user_id: 3, role_id: 3, is_default: true },
    { user_id: 5, role_id: 5, is_default: true },
    { user_id: 6, role_id: 6, is_default: true },
  ];

  const systemSettings = {
    DUE_SOON_WORKING_DAYS: "2",
    SESSION_TIMEOUT_MIN: "60",
    MAX_LOGIN_FAILED: "5",
    LOCK_MINUTES: "15",
    DEMO_MODE: "1",
  };

  function makeVer(n) {
    const b = Buffer.alloc(8);
    b.writeUInt32BE(n, 4);
    return b;
  }

  let verSeq = 10;
  // Lưu ý: 2026-11-16 là thứ Hai
  // +2 ngày (2026-11-18 Thứ Tư) -> 2 ngày làm việc (DUE_SOON với ngưỡng 2)
  // +3 ngày (2026-11-19 Thứ Năm) -> 3 ngày làm việc (ON_TRACK với ngưỡng 2, DUE_SOON nếu nâng ngưỡng lên 4)
  // -3 ngày (2026-11-13 Thứ Sáu) -> -1 ngày làm việc (OVERDUE)
  const tasks = [
    {
      task_id: 1,
      task_code: "NV000001",
      title: "Tham mưu kế hoạch phòng, chống sốt xuất huyết",
      description: "Theo CV 1520/SYT-NVY",
      field_id: 2,
      document_id: 1,
      meeting_id: null,
      parent_task_id: null,
      assigned_by: 2,
      assignee_id: 5,
      priority: "HIGH",
      start_date: addDaysIso(todayIso, -7),
      due_date: addDaysIso(todayIso, 2),
      original_due_date: addDaysIso(todayIso, 2),
      status: "IN_PROGRESS",
      progress_percent: 40,
      result_note: null,
      completed_at: null,
      created_at: new Date(),
      updated_at: null,
      row_ver: makeVer(++verSeq),
    },
    {
      task_id: 2,
      task_code: "NV000002",
      title: "Báo cáo kết quả tiêm chủng mở rộng tháng",
      description: null,
      field_id: 2,
      document_id: null,
      meeting_id: null,
      parent_task_id: null,
      assigned_by: 2,
      assignee_id: 5,
      priority: "NORMAL",
      start_date: addDaysIso(todayIso, -20),
      due_date: addDaysIso(todayIso, -3),
      original_due_date: addDaysIso(todayIso, -3),
      status: "IN_PROGRESS",
      progress_percent: 70,
      result_note: null,
      completed_at: null,
      created_at: new Date(),
      updated_at: null,
      row_ver: makeVer(++verSeq),
    },
    {
      task_id: 3,
      task_code: "NV000003",
      title: "Tổng hợp số liệu đầu năm học 2026–2027",
      description: "Theo CV 901/SGDĐT-KHTC",
      field_id: 3,
      document_id: 8,
      meeting_id: null,
      parent_task_id: null,
      assigned_by: 3,
      assignee_id: 6,
      priority: "HIGH",
      start_date: addDaysIso(todayIso, -13),
      due_date: addDaysIso(todayIso, -2),
      original_due_date: addDaysIso(todayIso, -2),
      status: "NEW",
      progress_percent: 0,
      result_note: null,
      completed_at: null,
      created_at: new Date(),
      updated_at: null,
      row_ver: makeVer(++verSeq),
    },
    {
      task_id: 4,
      task_code: "NV000004",
      title: "Kiểm tra cơ sở vật chất các trường (còn 3 ngày làm việc)",
      description: null,
      field_id: 3,
      document_id: null,
      meeting_id: null,
      parent_task_id: null,
      assigned_by: 3,
      assignee_id: 6,
      priority: "NORMAL",
      start_date: addDaysIso(todayIso, -3),
      due_date: addDaysIso(todayIso, 3),
      original_due_date: addDaysIso(todayIso, 3),
      status: "NEW",
      progress_percent: 0,
      result_note: null,
      completed_at: null,
      created_at: new Date(),
      updated_at: null,
      row_ver: makeVer(++verSeq),
    },
    {
      task_id: 5,
      task_code: "NV000005",
      title: "Báo cáo đã hoàn thành nhưng sau hạn cũ",
      description: null,
      field_id: 2,
      document_id: null,
      meeting_id: null,
      parent_task_id: null,
      assigned_by: 2,
      assignee_id: 5,
      priority: "NORMAL",
      start_date: addDaysIso(todayIso, -12),
      due_date: addDaysIso(todayIso, -5),
      original_due_date: addDaysIso(todayIso, -5),
      status: "DONE",
      progress_percent: 100,
      result_note: "Đã hoàn thành",
      completed_at: new Date(`${addDaysIso(todayIso, -4)}T10:00:00Z`),
      created_at: new Date(),
      updated_at: null,
      row_ver: makeVer(++verSeq),
    },
    {
      task_id: 6,
      task_code: "NV000006",
      title: "Kế hoạch dài hạn 2099 (chưa có lịch ngày làm việc)",
      description: null,
      field_id: 2,
      document_id: null,
      meeting_id: null,
      parent_task_id: null,
      assigned_by: 2,
      assignee_id: 5,
      priority: "LOW",
      start_date: todayIso,
      due_date: "2099-12-31",
      original_due_date: "2099-12-31",
      status: "NEW",
      progress_percent: 0,
      result_note: null,
      completed_at: null,
      created_at: new Date(),
      updated_at: null,
      row_ver: makeVer(++verSeq),
    },
  ];

  const taskUpdates = [];
  const extensionRequests = [
    {
      request_id: 1,
      task_id: 3,
      requested_by: 6,
      old_due_date: addDaysIso(todayIso, -2),
      proposed_due_date: addDaysIso(todayIso, 5),
      reason: "Còn 2 trường chưa gửi số liệu.",
      status: "PENDING",
      decided_by: null,
      decided_at: null,
      decision_note: null,
      created_at: new Date(),
    },
  ];
  const attachments = [];
  const notifications = [];
  const sessions = [];
  const auditLogs = [];

  function sqlThrow(number, message) {
    const err = new Error(message);
    err.number = number;
    return err;
  }

  function workingDaysBetween(fromIso, toIso) {
    if (!fromIso || !toIso) return null;
    if (!calendarMap.has(fromIso) || !calendarMap.has(toIso)) {
      return null;
    }
    if (toIso >= fromIso) {
      let count = 0;
      for (const [d, entry] of calendarMap.entries()) {
        if (d > fromIso && d <= toIso && entry.is_working_day) {
          count++;
        }
      }
      return count;
    }
    let count = 0;
    for (const [d, entry] of calendarMap.entries()) {
      if (d > toIso && d <= fromIso && entry.is_working_day) {
        count++;
      }
    }
    return -count;
  }

  function computeTaskDeadlines(evalDate) {
    const dueSoonDays = Number.parseInt(
      systemSettings.DUE_SOON_WORKING_DAYS ?? "2",
      10,
    );
    return tasks.map((t) => {
      const wdLeft = workingDaysBetween(evalDate, t.due_date);
      let state;
      if (t.status === "DONE" || t.status === "CANCELLED") {
        state = t.status;
      } else if (t.due_date < evalDate) {
        state = "OVERDUE";
      } else if (wdLeft !== null && wdLeft <= dueSoonDays) {
        state = "DUE_SOON";
      } else {
        state = "ON_TRACK";
      }

      const compDate = t.completed_at
        ? t.completed_at.toISOString().slice(0, 10)
        : null;
      const isDoneLate =
        t.status === "DONE" && compDate !== null && compDate > t.due_date
          ? 1
          : 0;
      const wasExtended = t.due_date > t.original_due_date ? 1 : 0;

      return {
        ...t,
        working_days_left: wdLeft,
        deadline_state: state,
        is_done_late: isDoneLate,
        was_extended: wasExtended,
      };
    });
  }

  function getVisibleTasks(userId, roleId, evalDate) {
    const role = roles.find((r) => r.role_id === roleId);
    const hasRole = userRoles.some(
      (ur) => ur.user_id === userId && ur.role_id === roleId,
    );
    const user = users.find((u) => u.user_id === userId);
    if (!user || !user.is_active || !role || !hasRole) return [];

    return computeTaskDeadlines(evalDate)
      .filter((t) => role.role_level === "LEADER" || t.assignee_id === userId)
      .map((t) => ({
        ...t,
        field_name: fields.find((f) => f.field_id === t.field_id)?.name || "",
        assignee_name:
          users.find((u) => u.user_id === t.assignee_id)?.full_name || "",
        assigned_by_name:
          users.find((u) => u.user_id === t.assigned_by)?.full_name || "",
        is_mine: t.assignee_id === userId ? 1 : 0,
      }));
  }

  const pool = {
    request() {
      const params = {};
      return {
        input(name, _type, value) {
          params[name] = value;
          return this;
        },
        async query(sqlText) {
          const text = sqlText.replace(/\s+/g, " ").trim();

          if (text.includes("UPDATE dbo.system_settings SET setting_value = @setting_value")) {
            systemSettings.DUE_SOON_WORKING_DAYS = String(params.setting_value);
            return { recordset: [] };
          }

          if (text.includes("FROM dbo.system_settings")) {
            return {
              recordset: Object.entries(systemSettings).map(
                ([setting_key, setting_value]) => ({
                  setting_key,
                  int_value: Number.parseInt(setting_value, 10),
                }),
              ),
            };
          }

          if (
            text.includes("fn_setting_int('DUE_SOON_WORKING_DAYS')") &&
            !text.includes("fn_working_days_between")
          ) {
            return {
              recordset: [
                {
                  due_soon_days: Number.parseInt(
                    systemSettings.DUE_SOON_WORKING_DAYS ?? "2",
                    10,
                  ),
                },
              ],
            };
          }

          if (text.includes("MIN(cal_date) AS min_date")) {
            const keys = Array.from(calendarMap.keys()).sort();
            return {
              recordset: [
                {
                  min_date: keys[0] ?? null,
                  max_date: keys[keys.length - 1] ?? null,
                  total_days: keys.length,
                },
              ],
            };
          }

          if (text.includes("EXEC dbo.sp_write_audit")) {
            auditLogs.push({
              log_id: auditLogs.length + 1,
              user_id: params.user_id ?? null,
              active_role_id: params.role_id ?? null,
              action: params.action,
              entity_type: params.entity_type ?? null,
              entity_id: params.entity_id ?? null,
              detail: params.detail ?? null,
              created_at: new Date(),
            });
            return { recordset: [] };
          }

          if (text.includes("FROM dbo.users WHERE username = @username")) {
            const u = users.find((x) => x.username === params.username);
            if (!u) return { recordset: [] };
            return {
              recordset: [{ ...u, is_currently_locked: 0, lock_expired: 0 }],
            };
          }

          if (text.includes("UPDATE dbo.users SET failed_login_count = 0")) {
            return { recordset: [] };
          }

          if (text.includes("FROM dbo.user_roles ur JOIN dbo.roles r ON r.role_id = ur.role_id LEFT JOIN dbo.fields f")) {
            const rows = userRoles
              .filter((ur) => ur.user_id === params.user_id)
              .map((ur) => {
                const r = roles.find((x) => x.role_id === ur.role_id);
                const f = fields.find((x) => x.field_id === r.field_id);
                return {
                  role_id: r.role_id,
                  code: r.code,
                  name: r.name,
                  role_level: r.role_level,
                  rank_no: r.rank_no,
                  field_id: r.field_id,
                  field_code: f?.code ?? null,
                  field_name: f?.name ?? null,
                  is_default: ur.is_default,
                };
              });
            return { recordset: rows };
          }

          if (text.includes("FROM dbo.user_roles ur JOIN dbo.roles r ON r.role_id = ur.role_id WHERE ur.user_id = @user_id")) {
            const rows = userRoles
              .filter((ur) => ur.user_id === params.user_id)
              .map((ur) => {
                const r = roles.find((x) => x.role_id === ur.role_id);
                return {
                  role_id: r.role_id,
                  is_default: ur.is_default,
                  code: r.code,
                  name: r.name,
                };
              });
            return { recordset: rows };
          }

          if (text.includes("INSERT INTO dbo.user_sessions")) {
            const now = new Date();
            sessions.push({
              session_id: params.session_id,
              user_id: params.user_id,
              active_role_id: params.active_role_id,
              is_demo_mode: Boolean(params.is_demo_mode),
              created_at: now,
              last_seen_at: now,
              expires_at: new Date(now.getTime() + params.timeout_min * 60_000),
              revoked_at: null,
            });
            return { recordset: [] };
          }

          if (text.includes("FROM dbo.user_sessions s JOIN dbo.users u")) {
            const s = sessions.find(
              (x) => x.session_id.toLowerCase() === String(params.session_id).toLowerCase(),
            );
            if (!s) return { recordset: [] };
            const u = users.find((x) => x.user_id === s.user_id);
            const r = roles.find((x) => x.role_id === s.active_role_id);
            const f = fields.find((x) => x.field_id === r.field_id);
            const isExpired = s.revoked_at !== null || s.expires_at.getTime() <= Date.now() ? 1 : 0;
            return {
              recordset: [
                {
                  ...s,
                  is_expired: isExpired,
                  username: u.username,
                  full_name: u.full_name,
                  position_title: u.position_title,
                  email: u.email,
                  phone: u.phone,
                  is_active: u.is_active,
                  is_demo_account: u.is_demo_account,
                  role_code: r.code,
                  role_name: r.name,
                  role_level: r.role_level,
                  rank_no: r.rank_no,
                  field_id: r.field_id,
                  field_code: f?.code ?? null,
                  field_name: f?.name ?? null,
                },
              ],
            };
          }

          if (text.includes("UPDATE dbo.user_sessions SET last_seen_at = SYSDATETIME()")) {
            const s = sessions.find(
              (x) => x.session_id.toLowerCase() === String(params.session_id).toLowerCase(),
            );
            if (!s) return { recordset: [] };
            s.last_seen_at = new Date();
            s.expires_at = new Date(Date.now() + params.timeout_min * 60_000);
            return {
              recordset: [{ last_seen_at: s.last_seen_at, expires_at: s.expires_at }],
            };
          }

          if (text.includes("FROM dbo.fn_active_delegations")) {
            return { recordset: [] };
          }

          if (text.includes("FROM dbo.fn_permissions_of")) {
            return {
              recordset: [
                {
                  function_code: "F06_MY_TASKS",
                  function_name: "Việc của tôi",
                  group_code: "II",
                  action: "X",
                  scope: "OWN",
                  requires_delegation: false,
                  is_usable_now: true,
                },
              ],
            };
          }

          if (text.includes("dbo.fn_working_days_between(@f, @to_date)")) {
            const f = params.from_date || todayIso;
            const t = params.to_date;
            return {
              recordset: [
                {
                  effective_from_date: f,
                  effective_to_date: t,
                  working_days_left: workingDaysBetween(f, t),
                  due_soon_days: Number.parseInt(
                    systemSettings.DUE_SOON_WORKING_DAYS ?? "2",
                    10,
                  ),
                  is_past_due: t < f ? 1 : 0,
                  has_from_date: calendarMap.has(f) ? 1 : 0,
                  has_to_date: calendarMap.has(t) ? 1 : 0,
                },
              ],
            };
          }

          if (text.includes("SELECT CAST(SYSDATETIME() AS DATE) AS today_date")) {
            return {
              recordset: [
                {
                  today_date: todayIso,
                  plus30_date: addDaysIso(todayIso, 30),
                },
              ],
            };
          }

          if (text.includes("FROM dbo.calendar_days WHERE cal_date BETWEEN")) {
            const rows = [];
            for (const [d, entry] of calendarMap.entries()) {
              if (d >= params.from_date && d <= params.to_date) {
                rows.push({ ...entry });
              }
            }
            rows.sort((a, b) => a.cal_date.localeCompare(b.cal_date));
            return { recordset: rows };
          }

          if (text.includes("fn_has_permission(@user_id, @role_id, 'F06_MY_TASKS', 'X')")) {
            return { recordset: [{ allowed: 1 }] };
          }

          if (text.includes("SUM(CASE WHEN deadline_state = 'OVERDUE'")) {
            const evalDate = params.today || todayIso;
            const visible = getVisibleTasks(params.user_id, params.role_id, evalDate).filter(
              (t) => !params.only_mine || t.is_mine === 1,
            );
            return {
              recordset: [
                {
                  total: visible.length,
                  overdue: visible.filter((t) => t.deadline_state === "OVERDUE").length,
                  due_soon: visible.filter((t) => t.deadline_state === "DUE_SOON").length,
                  on_track: visible.filter((t) => t.deadline_state === "ON_TRACK").length,
                  done: visible.filter((t) => t.deadline_state === "DONE").length,
                  cancelled: visible.filter((t) => t.deadline_state === "CANCELLED").length,
                },
              ],
            };
          }

          if (text.includes("FROM dbo.fn_visible_tasks(@user_id, @role_id, @t) vt") && text.includes("COUNT(*) OVER () AS total_rows")) {
            const evalDate = params.today || todayIso;
            let visible = getVisibleTasks(params.user_id, params.role_id, evalDate).filter(
              (t) => !params.only_mine || t.is_mine === 1,
            );

            if (params.status) {
              visible = visible.filter((t) => t.status === params.status);
            }
            if (params.field_id) {
              visible = visible.filter((t) => t.field_id === params.field_id);
            }
            if (params.deadline_state) {
              if (params.deadline_state === "ALERT") {
                visible = visible.filter((t) =>
                  ["OVERDUE", "DUE_SOON"].includes(t.deadline_state),
                );
              } else {
                visible = visible.filter(
                  (t) => t.deadline_state === params.deadline_state,
                );
              }
            }
            if (params.keyword) {
              const kw = params.keyword.toLowerCase();
              visible = visible.filter(
                (t) =>
                  t.task_code.toLowerCase().includes(kw) ||
                  t.title.toLowerCase().includes(kw),
              );
            }

            const order = {
              OVERDUE: 0,
              DUE_SOON: 1,
              ON_TRACK: 2,
              DONE: 3,
              CANCELLED: 4,
            };
            visible.sort(
              (a, b) =>
                order[a.deadline_state] - order[b.deadline_state] ||
                a.due_date.localeCompare(b.due_date) ||
                b.task_id - a.task_id,
            );

            const totalRows = visible.length;
            const pageSlice = visible
              .slice(params.offset, params.offset + params.page_size)
              .map((t) => ({ ...t, total_rows: totalRows }));

            return { recordset: pageSlice };
          }

          if (text.includes("JOIN dbo.tasks t ON t.task_id = vt.task_id WHERE vt.task_id = @task_id")) {
            const evalDate = params.today || todayIso;
            const visible = getVisibleTasks(params.user_id, params.role_id, evalDate);
            const found = visible.find((t) => t.task_id === params.task_id);
            return { recordset: found ? [{ ...found }] : [] };
          }

          if (text.includes("SELECT task_id FROM dbo.tasks WHERE task_id = @task_id")) {
            const found = tasks.find((t) => t.task_id === params.task_id);
            return { recordset: found ? [{ task_id: found.task_id }] : [] };
          }

          if (text.includes("FROM dbo.task_updates tu")) {
            return {
              recordset: taskUpdates.filter((u) => u.task_id === params.task_id),
            };
          }

          if (text.includes("FROM dbo.extension_requests e")) {
            return {
              recordset: extensionRequests
                .filter((e) => e.task_id === params.task_id)
                .map((e) => ({
                  ...e,
                  requested_by_name:
                    users.find((u) => u.user_id === e.requested_by)?.full_name || "",
                  decided_by_name: e.decided_by
                    ? users.find((u) => u.user_id === e.decided_by)?.full_name || ""
                    : null,
                })),
            };
          }

          if (text.includes("FROM dbo.attachments a")) {
            return {
              recordset: attachments.filter(
                (a) => a.task_id === params.task_id && !a.is_deleted,
              ),
            };
          }

          if (text.includes("EXEC dbo.sp_update_task_progress")) {
            const t = tasks.find((x) => x.task_id === params.task_id);
            if (!t) throw sqlThrow(50404, "Không tìm thấy nhiệm vụ.");
            if (t.assignee_id !== params.user_id) {
              throw sqlThrow(
                50403,
                "Chỉ người được giao mới cập nhật tiến độ nhiệm vụ.",
              );
            }
            if (["DONE", "CANCELLED"].includes(t.status)) {
              throw sqlThrow(50409, "Nhiệm vụ đã kết thúc, không thể cập nhật.");
            }
            if (params.row_ver && !params.row_ver.equals(t.row_ver)) {
              throw sqlThrow(
                50409,
                "Nhiệm vụ vừa được cập nhật bởi người khác, vui lòng tải lại.",
              );
            }
            const oldStatus = t.status;
            t.status = params.new_status;
            t.progress_percent = params.new_status === "DONE" ? 100 : params.progress;
            t.completed_at =
              params.new_status === "DONE" ? new Date(`${todayIso}T12:00:00Z`) : null;
            if (params.new_status === "DONE") {
              t.result_note = params.note;
              for (const ext of extensionRequests) {
                if (ext.task_id === t.task_id && ext.status === "PENDING") {
                  ext.status = "CANCELLED";
                  ext.decision_note = "Tự hủy do nhiệm vụ đã hoàn thành";
                }
              }
            }
            t.updated_at = new Date();
            t.row_ver = makeVer(++verSeq);
            taskUpdates.unshift({
              update_id: taskUpdates.length + 1,
              task_id: t.task_id,
              updated_by: params.user_id,
              updated_by_name:
                users.find((u) => u.user_id === params.user_id)?.full_name || "",
              old_status: oldStatus,
              new_status: t.status,
              progress_percent: t.progress_percent,
              note: params.note,
              created_at: new Date(),
            });
            return { recordset: [] };
          }

          if (text.includes("EXEC dbo.sp_generate_deadline_notifications")) {
            const evalDate = params.today || todayIso;
            const list = computeTaskDeadlines(evalDate).filter((t) =>
              ["OVERDUE", "DUE_SOON"].includes(t.deadline_state),
            );
            let created = 0;
            for (const td of list) {
              const dedupeKey = `${td.deadline_state}:TASK:${td.task_id}:${evalDate}`;
              const dup = notifications.some(
                (n) =>
                  n.recipient_id === td.assignee_id &&
                  n.dedupe_key === dedupeKey,
              );
              if (!dup) {
                notifications.push({
                  notification_id: notifications.length + 1,
                  recipient_id: td.assignee_id,
                  notif_type:
                    td.deadline_state === "OVERDUE"
                      ? "TASK_OVERDUE"
                      : "TASK_DUE_SOON",
                  entity_type: "TASK",
                  entity_id: td.task_id,
                  dedupe_key: dedupeKey,
                });
                created++;
              }
            }
            return {
              recordset: [
                {
                  effective_today: evalDate,
                  notifications_created: created,
                },
              ],
            };
          }

          throw new Error(`Unhandled mock SQL query: ${text}`);
        },
      };
    },
  };

  return { pool, tasks, notifications, systemSettings, auditLogs };
}

async function startTestServer() {
  const server = await new Promise((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const address = server.address();
  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

async function loginAs(baseUrl, username) {
  const res = await fetch(`${baseUrl}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password: "Demo@123" }),
  });
  const body = await res.json();
  return body.data.session_id;
}

describe("Deadline & Working Days API (Task 1.4.2)", () => {
  let state;
  let testServer;

  beforeEach(async () => {
    state = createDeadlineMockDb("2026-11-16");
    setPoolProvider(() => state.pool);
    testServer = await startTestServer();
  });

  afterEach(async () => {
    setPoolProvider(null);
    if (testServer) {
      await testServer.close();
    }
  });

  it("Từ chối yêu cầu nhiệm vụ khi thiếu phiên hợp lệ", async () => {
    const requests = [
      { url: "/api/tasks", method: "GET" },
      { url: "/api/tasks/1", method: "GET" },
      {
        url: "/api/tasks/1/progress",
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ new_status: "IN_PROGRESS", progress_percent: 10 }),
      },
    ];

    for (const request of requests) {
      const response = await fetch(`${testServer.baseUrl}${request.url}`, request);
      assert.equal(response.status, 401, request.url);
      const body = await response.json();
      assert.equal(body.error.code, "UNAUTHORIZED", request.url);
    }
  });

  it("1. Tính đúng ngày làm việc (bỏ qua thứ Bảy, Chủ nhật và ngày lễ) và trạng thái hạn", async () => {
    const sid = await loginAs(testServer.baseUrl, "tp.vhxh");

    // Từ thứ Sáu 2026-11-13 đến thứ Hai 2026-11-16 -> chỉ tính thứ Hai (1 ngày làm việc)
    const weekendRes = await fetch(
      `${testServer.baseUrl}/api/tasks/working-days?from_date=2026-11-13&to_date=2026-11-16`,
      { headers: { Authorization: `Bearer ${sid}` } },
    );
    assert.equal(weekendRes.status, 200);
    const weekendBody = await weekendRes.json();
    assert.equal(weekendBody.data.working_days_left, 1);
    assert.equal(weekendBody.data.calendar_covered, true);
    assert.equal(weekendBody.data.deadline_state, "DUE_SOON");

    // Từ 2026-04-29 (T4) đến 2026-05-04 (T2) -> bỏ 30/4 (T5), 1/5 (T6), 2/5 (T7), 3/5 (CN) -> còn 1 ngày làm việc (4/5)
    const holidayRes = await fetch(
      `${testServer.baseUrl}/api/tasks/working-days?from_date=2026-04-29&to_date=2026-05-04`,
      { headers: { Authorization: `Bearer ${sid}` } },
    );
    const holidayBody = await holidayRes.json();
    assert.equal(holidayBody.data.working_days_left, 1);

    // Quá hạn trả số âm và OVERDUE
    const overdueRes = await fetch(
      `${testServer.baseUrl}/api/tasks/working-days?from_date=2026-11-16&to_date=2026-11-13`,
      { headers: { Authorization: `Bearer ${sid}` } },
    );
    const overdueBody = await overdueRes.json();
    assert.equal(overdueBody.data.working_days_left, -1);
    assert.equal(overdueBody.data.deadline_state, "OVERDUE");
    assert.equal(overdueBody.data.is_overdue, true);

    // Nếu status = DONE dù due_date < today vẫn không còn quá hạn
    const doneRes = await fetch(
      `${testServer.baseUrl}/api/tasks/working-days?from_date=2026-11-16&to_date=2026-11-13&status=DONE`,
      { headers: { Authorization: `Bearer ${sid}` } },
    );
    const doneBody = await doneRes.json();
    assert.equal(doneBody.data.deadline_state, "DONE");
    assert.equal(doneBody.data.is_overdue, false);
  });

  it("2. Chưa tự suy đoán ngày nghỉ nếu không có lịch trong dbo.calendar_days", async () => {
    const sid = await loginAs(testServer.baseUrl, "cv.yte");

    const futureRes = await fetch(
      `${testServer.baseUrl}/api/tasks/working-days?from_date=2026-11-16&to_date=2099-12-31`,
      { headers: { Authorization: `Bearer ${sid}` } },
    );
    assert.equal(futureRes.status, 200);
    const futureBody = await futureRes.json();
    assert.equal(futureBody.data.working_days_left, null);
    assert.equal(futureBody.data.calendar_covered, false);
    assert.equal(futureBody.data.has_to_date, false);
    assert.equal(futureBody.data.deadline_state, "ON_TRACK");

    const calRes = await fetch(
      `${testServer.baseUrl}/api/tasks/calendar?from_date=2099-12-28&to_date=2099-12-31`,
      { headers: { Authorization: `Bearer ${sid}` } },
    );
    assert.equal(calRes.status, 200);
    const calBody = await calRes.json();
    assert.equal(calBody.data.calendar_days_found, 0);
    assert.equal(calBody.data.is_fully_covered, false);
    assert.deepEqual(calBody.data.days, []);

    // Task #6 có due_date = 2099-12-31 phải xếp ON_TRACK và calendar_covered = false
    const taskRes = await fetch(`${testServer.baseUrl}/api/tasks/6`, {
      headers: { Authorization: `Bearer ${sid}` },
    });
    assert.equal(taskRes.status, 200);
    const taskBody = await taskRes.json();
    assert.equal(taskBody.data.working_days_left, null);
    assert.equal(taskBody.data.calendar_covered, false);
    assert.equal(taskBody.data.deadline_state, "ON_TRACK");
  });

  it("3. Ngưỡng sắp hạn cấu hình được theo system_settings và phân quyền cập nhật", async () => {
    const tpSid = await loginAs(testServer.baseUrl, "tp.vhxh");
    const cvSid = await loginAs(testServer.baseUrl, "cv.yte");

    // Mặc định ngưỡng = 2 -> task #4 (còn 3 ngày làm việc) là ON_TRACK
    const beforeTask = await fetch(`${testServer.baseUrl}/api/tasks/4`, {
      headers: { Authorization: `Bearer ${tpSid}` },
    });
    const beforeBody = await beforeTask.json();
    assert.equal(beforeBody.data.working_days_left, 3);
    assert.equal(beforeBody.data.deadline_state, "ON_TRACK");

    // Chuyên viên không được sửa cấu hình -> 403
    const cvUpdate = await fetch(
      `${testServer.baseUrl}/api/tasks/deadline-settings`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${cvSid}`,
        },
        body: JSON.stringify({ due_soon_working_days: 4 }),
      },
    );
    assert.equal(cvUpdate.status, 403);

    // Giá trị không hợp lệ -> 400
    const badUpdate = await fetch(
      `${testServer.baseUrl}/api/tasks/deadline-settings`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${tpSid}`,
        },
        body: JSON.stringify({ due_soon_working_days: 0 }),
      },
    );
    assert.equal(badUpdate.status, 400);

    // Trưởng phòng đổi ngưỡng lên 4 -> task #4 tự động thành DUE_SOON
    const tpUpdate = await fetch(
      `${testServer.baseUrl}/api/tasks/deadline-settings`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${tpSid}`,
        },
        body: JSON.stringify({ due_soon_working_days: 4 }),
      },
    );
    assert.equal(tpUpdate.status, 200);
    const tpUpdateBody = await tpUpdate.json();
    assert.equal(tpUpdateBody.data.due_soon_working_days, 4);

    const afterTask = await fetch(`${testServer.baseUrl}/api/tasks/4`, {
      headers: { Authorization: `Bearer ${tpSid}` },
    });
    const afterBody = await afterTask.json();
    assert.equal(afterBody.data.deadline_state, "DUE_SOON");
    assert.equal(afterBody.data.is_due_soon, true);
  });

  it("4. Việc hoàn thành (DONE) không còn quá hạn và giảm số thẻ cảnh báo, hỗ trợ optimistic lock row_ver", async () => {
    const tpSid = await loginAs(testServer.baseUrl, "tp.vhxh");
    const cvSid = await loginAs(testServer.baseUrl, "cv.yte");

    // Trước khi hoàn thành: task #2 đang OVERDUE, task #5 đã DONE dù quá hạn vẫn là DONE
    const alertsBeforeRes = await fetch(`${testServer.baseUrl}/api/tasks/alerts`, {
      headers: { Authorization: `Bearer ${tpSid}` },
    });
    const alertsBefore = await alertsBeforeRes.json();
    const overdueCountBefore = alertsBefore.data.summary.overdue;
    assert.equal(overdueCountBefore, 2); // task #2 và #3
    assert.ok(alertsBefore.data.items.some((x) => x.task_id === 2));
    assert.ok(!alertsBefore.data.items.some((x) => x.task_id === 5));

    const detailRes = await fetch(`${testServer.baseUrl}/api/tasks/2`, {
      headers: { Authorization: `Bearer ${cvSid}` },
    });
    const detail = await detailRes.json();
    const rowVer = detail.data.row_ver;

    const doneRes = await fetch(`${testServer.baseUrl}/api/tasks/2/progress`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${cvSid}`,
      },
      body: JSON.stringify({
        new_status: "DONE",
        note: "Đã hoàn thành báo cáo tiêm chủng",
        row_ver: rowVer,
      }),
    });
    assert.equal(doneRes.status, 200);
    const doneBody = await doneRes.json();
    assert.equal(doneBody.data.status, "DONE");
    assert.equal(doneBody.data.deadline_state, "DONE");
    assert.equal(doneBody.data.is_overdue, false);
    assert.equal(doneBody.data.is_due_soon, false);
    assert.equal(doneBody.data.is_done_late, true);

    // Số lượng quá hạn giảm 1 và task #2 biến mất khỏi alerts
    const alertsAfterRes = await fetch(`${testServer.baseUrl}/api/tasks/alerts`, {
      headers: { Authorization: `Bearer ${tpSid}` },
    });
    const alertsAfter = await alertsAfterRes.json();
    assert.equal(alertsAfter.data.summary.overdue, overdueCountBefore - 1);
    assert.ok(!alertsAfter.data.items.some((x) => x.task_id === 2));

    // Cập nhật lại task đã DONE -> 409 CONFLICT
    const repeatRes = await fetch(`${testServer.baseUrl}/api/tasks/2/progress`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${cvSid}`,
      },
      body: JSON.stringify({
        new_status: "IN_PROGRESS",
        progress_percent: 50,
      }),
    });
    assert.equal(repeatRes.status, 409);
  });

  it("5. Phân quyền: Chuyên viên không xem/cập nhật được nhiệm vụ của người khác", async () => {
    const cvYtSid = await loginAs(testServer.baseUrl, "cv.yte");
    const tpSid = await loginAs(testServer.baseUrl, "tp.vhxh");

    // CV Y tế truyền scope=all cũng chỉ thấy nhiệm vụ của mình
    const cvListRes = await fetch(
      `${testServer.baseUrl}/api/tasks?scope=all`,
      { headers: { Authorization: `Bearer ${cvYtSid}` } },
    );
    const cvList = await cvListRes.json();
    assert.ok(cvList.data.items.every((t) => t.assignee_id === 5));
    assert.ok(cvList.data.items.some((t) => t.task_id === 1));

    // Chuyên viên xem được chi tiết nhiệm vụ được giao cho mình
    const ownDetail = await fetch(`${testServer.baseUrl}/api/tasks/1`, {
      headers: { Authorization: `Bearer ${cvYtSid}` },
    });
    assert.equal(ownDetail.status, 200);

    // Trưởng phòng thấy đủ cả 6 nhiệm vụ
    const tpListRes = await fetch(
      `${testServer.baseUrl}/api/tasks?scope=all`,
      { headers: { Authorization: `Bearer ${tpSid}` } },
    );
    const tpList = await tpListRes.json();
    assert.equal(tpList.meta.total_rows, 6);

    // CV Y tế xem task #3 của CV Giáo dục -> 403
    const forbiddenDetail = await fetch(`${testServer.baseUrl}/api/tasks/3`, {
      headers: { Authorization: `Bearer ${cvYtSid}` },
    });
    assert.equal(forbiddenDetail.status, 403);

    // CV Y tế cập nhật task #3 của CV Giáo dục -> 403
    const forbiddenUpdate = await fetch(
      `${testServer.baseUrl}/api/tasks/3/progress`,
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${cvYtSid}`,
        },
        body: JSON.stringify({ new_status: "IN_PROGRESS", progress_percent: 10 }),
      },
    );
    assert.equal(forbiddenUpdate.status, 403);

    // Lãnh đạo xem được nhiệm vụ nhưng không được cập nhật thay người được giao
    const leaderUpdate = await fetch(
      `${testServer.baseUrl}/api/tasks/2/progress`,
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${tpSid}`,
        },
        body: JSON.stringify({ new_status: "IN_PROGRESS", progress_percent: 50 }),
      },
    );
    assert.equal(leaderUpdate.status, 403);

    // Task không tồn tại -> 404
    const notFoundRes = await fetch(`${testServer.baseUrl}/api/tasks/9999`, {
      headers: { Authorization: `Bearer ${tpSid}` },
    });
    assert.equal(notFoundRes.status, 404);
  });

  it("Chỉ vai trò được cấp quyền mới được sinh thông báo hạn toàn phòng", async () => {
    const { generateDeadlineNotifications } = require("../src/services/deadlineService");

    for (const roleCode of ["PTP", "CV_VHXH", undefined]) {
      await assert.rejects(
        generateDeadlineNotifications({ roleCode, today: "2026-11-16" }),
        (error) => error.status === 403 && error.code === "FORBIDDEN",
      );
    }
  });

  it("6. Job sinh thông báo sắp hạn/quá hạn chạy nhiều lần trong ngày không trùng (dedupe)", async () => {
    const tpSid = await loginAs(testServer.baseUrl, "tp.vhxh");

    const run1 = await fetch(
      `${testServer.baseUrl}/api/tasks/deadline-notifications`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${tpSid}`,
        },
        body: JSON.stringify({ today: "2026-11-16" }),
      },
    );
    assert.equal(run1.status, 200);
    const body1 = await run1.json();
    assert.equal(body1.data.notifications_created, 3); // task #1 DUE_SOON, #2 OVERDUE, #3 OVERDUE

    const run2 = await fetch(
      `${testServer.baseUrl}/api/tasks/deadline-notifications`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${tpSid}`,
        },
        body: JSON.stringify({ today: "2026-11-16" }),
      },
    );
    assert.equal(run2.status, 200);
    const body2 = await run2.json();
    assert.equal(body2.data.notifications_created, 0);
  });
});
