const assert = require("node:assert/strict");
const { afterEach, beforeEach, describe, it } = require("node:test");
const { setPoolProvider } = require("../src/config/db");
const { app } = require("../server");

const SEED_PASSWORD_HASH =
  "$2b$10$FOfZy4YtMG3wtXHmwHbs7usVLIjWrm6wD6DB1XgCrn/eKUznPQGH2";

function createSeedDatabaseState() {
  const fields = [
    { field_id: 1, code: "NV", name: "Nội vụ" },
    { field_id: 2, code: "YT", name: "Y tế" },
    { field_id: 3, code: "GD", name: "Giáo dục" },
    { field_id: 4, code: "VHXH", name: "Văn hóa – Xã hội" },
    { field_id: 5, code: "KHCN", name: "Khoa học và Công nghệ" },
    { field_id: 6, code: "DTTG", name: "Dân tộc – Tôn giáo" },
  ];

  const roles = [
    { role_id: 1, code: "PCT", name: "Phó Chủ tịch UBND phụ trách VH – XH", role_level: "LEADER", rank_no: 1, field_id: null },
    { role_id: 2, code: "TP", name: "Trưởng phòng VH – XH", role_level: "LEADER", rank_no: 2, field_id: null },
    { role_id: 3, code: "PTP", name: "Phó Trưởng phòng VH – XH", role_level: "LEADER", rank_no: 3, field_id: null },
    { role_id: 4, code: "CV_NV", name: "Chuyên viên Nội vụ", role_level: "STAFF", rank_no: 4, field_id: 1 },
    { role_id: 5, code: "CV_YT", name: "Chuyên viên Y tế", role_level: "STAFF", rank_no: 4, field_id: 2 },
    { role_id: 6, code: "CV_GD", name: "Chuyên viên Giáo dục", role_level: "STAFF", rank_no: 4, field_id: 3 },
    { role_id: 7, code: "CV_VHXH", name: "Chuyên viên Văn hóa – Xã hội", role_level: "STAFF", rank_no: 4, field_id: 4 },
    { role_id: 8, code: "CV_KHCN", name: "Chuyên viên Khoa học & Công nghệ", role_level: "STAFF", rank_no: 4, field_id: 5 },
    { role_id: 9, code: "CV_DTTG", name: "Chuyên viên Dân tộc – Tôn giáo", role_level: "STAFF", rank_no: 4, field_id: 6 },
  ];

  const users = [
    { user_id: 1, username: "pct.vhxh", password_hash: SEED_PASSWORD_HASH, full_name: "Nguyễn Văn An", position_title: "Phó Chủ tịch UBND phụ trách VH – XH", email: "pct.vhxh@demo.local", phone: "0901000001", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 2, username: "tp.vhxh", password_hash: SEED_PASSWORD_HASH, full_name: "Trần Thị Bình", position_title: "Trưởng phòng Văn hóa – Xã hội", email: "tp.vhxh@demo.local", phone: "0901000002", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 3, username: "ptp.vhxh", password_hash: SEED_PASSWORD_HASH, full_name: "Lê Văn Cường", position_title: "Phó Trưởng phòng Văn hóa – Xã hội", email: "ptp.vhxh@demo.local", phone: "0901000003", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 4, username: "cv.noivu", password_hash: SEED_PASSWORD_HASH, full_name: "Phạm Thị Dung", position_title: "Chuyên viên Nội vụ", email: "cv.noivu@demo.local", phone: "0901000004", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 5, username: "cv.yte", password_hash: SEED_PASSWORD_HASH, full_name: "Hoàng Minh Đức", position_title: "Chuyên viên Y tế", email: "cv.yte@demo.local", phone: "0901000005", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 6, username: "cv.giaoduc", password_hash: SEED_PASSWORD_HASH, full_name: "Vũ Thu Hà", position_title: "Chuyên viên Giáo dục", email: "cv.giaoduc@demo.local", phone: "0901000006", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 7, username: "cv.vhxh", password_hash: SEED_PASSWORD_HASH, full_name: "Đỗ Quang Hùng", position_title: "Chuyên viên Văn hóa – Xã hội", email: "cv.vhxh@demo.local", phone: "0901000007", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 8, username: "cv.khcn", password_hash: SEED_PASSWORD_HASH, full_name: "Bùi Ngọc Lan", position_title: "Chuyên viên Khoa học & Công nghệ", email: "cv.khcn@demo.local", phone: "0901000008", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
    { user_id: 9, username: "cv.dttg", password_hash: SEED_PASSWORD_HASH, full_name: "Ngô Đức Minh", position_title: "Chuyên viên Dân tộc – Tôn giáo", email: "cv.dttg@demo.local", phone: "0901000009", is_active: true, is_demo_account: true, failed_login_count: 0, locked_until: null, last_login_at: null },
  ];

  const userRoles = [
    { user_id: 1, role_id: 1, is_default: true },
    { user_id: 2, role_id: 2, is_default: true },
    { user_id: 3, role_id: 3, is_default: true },
    { user_id: 4, role_id: 4, is_default: true },
    { user_id: 5, role_id: 5, is_default: true },
    { user_id: 6, role_id: 6, is_default: true },
    { user_id: 7, role_id: 7, is_default: true },
    { user_id: 8, role_id: 8, is_default: true },
    { user_id: 9, role_id: 9, is_default: true },
    { user_id: 7, role_id: 9, is_default: false },
  ];

  const delegations = [
    {
      delegation_id: 1,
      from_user_id: 2,
      to_user_id: 3,
      can_sign: true,
      can_approve_extension: true,
      can_view_confidential: false,
      valid_from: new Date(Date.now() - 86400_000),
      valid_to: new Date(Date.now() + 30 * 86400_000),
      is_active: true,
      revoked_at: null,
    },
  ];

  const systemSettings = {
    SESSION_TIMEOUT_MIN: "60",
    MAX_LOGIN_FAILED: "5",
    LOCK_MINUTES: "15",
    DEMO_MODE: "1",
  };

  const sessions = [];
  const auditLogs = [];

  function sqlThrow(number, message) {
    const err = new Error(message);
    err.number = number;
    return err;
  }

  function getActiveDelegations(userId) {
    const now = Date.now();
    return delegations.filter(
      (d) =>
        d.to_user_id === userId &&
        d.is_active &&
        d.revoked_at === null &&
        now >= d.valid_from.getTime() &&
        now < d.valid_to.getTime(),
    );
  }

  function getPermissionsFor(userId, roleId) {
    const role = roles.find((r) => r.role_id === roleId);
    const activeDels = getActiveDelegations(userId);
    const canSign = activeDels.some((d) => d.can_sign);

    const perms = [
      {
        function_code: "F01_LOGIN",
        function_name: "Đăng nhập tài khoản",
        group_code: "I",
        action: "X",
        scope: "ALL",
        requires_delegation: false,
        is_usable_now: true,
      },
      {
        function_code: "F03_SWITCH_ROLE",
        function_name: "Đổi vai trò tài khoản",
        group_code: "I",
        action: "C",
        scope: "GRANTED",
        requires_delegation: false,
        is_usable_now: true,
      },
      {
        function_code: "F04_DASHBOARD_TODAY",
        function_name: "Dashboard Hôm nay",
        group_code: "II",
        action: "X",
        scope: role?.role_level === "LEADER" ? "ALL" : "OWN",
        requires_delegation: false,
        is_usable_now: true,
      },
    ];

    if (role?.code === "PTP") {
      perms.push({
        function_code: "F08_PENDING_APPROVAL",
        function_name: "Hồ sơ chờ ký / duyệt",
        group_code: "II",
        action: "X",
        scope: "ASSIGNED",
        requires_delegation: true,
        is_usable_now: canSign,
      });
    } else if (role?.code === "TP" || role?.code === "PCT") {
      perms.push({
        function_code: "F08_PENDING_APPROVAL",
        function_name: "Hồ sơ chờ ký / duyệt",
        group_code: "II",
        action: "X",
        scope: "ASSIGNED",
        requires_delegation: false,
        is_usable_now: true,
      });
    }

    return perms;
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

          if (text.includes("SELECT 1 AS [health_check]")) {
            return { recordset: [{ health_check: 1 }] };
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

          if (text.includes("EXEC dbo.sp_write_audit")) {
            auditLogs.push({
              log_id: auditLogs.length + 1,
              user_id: params.user_id ?? null,
              active_role_id: params.role_id ?? null,
              action: params.action,
              entity_type: params.entity_type ?? null,
              entity_id: params.entity_id ?? null,
              detail: params.detail ?? null,
              ip_address: params.ip_address ?? null,
              created_at: new Date(),
            });
            return { recordset: [] };
          }

          if (text.includes("FROM dbo.users WHERE username = @username")) {
            const u = users.find((x) => x.username === params.username);
            if (!u) return { recordset: [] };
            const now = Date.now();
            const isLocked = u.locked_until && u.locked_until.getTime() > now ? 1 : 0;
            const lockExpired = u.locked_until && u.locked_until.getTime() <= now ? 1 : 0;
            return {
              recordset: [
                {
                  ...u,
                  is_currently_locked: isLocked,
                  lock_expired: lockExpired,
                },
              ],
            };
          }

          if (text.includes("UPDATE dbo.users SET failed_login_count = @failed_count")) {
            const u = users.find((x) => x.user_id === params.user_id);
            if (u) {
              u.failed_login_count = params.failed_count;
              u.locked_until = text.includes("DATEADD(MINUTE, @lock_minutes")
                ? new Date(Date.now() + params.lock_minutes * 60_000)
                : null;
            }
            return { recordset: [] };
          }

          if (text.includes("UPDATE dbo.users SET failed_login_count = 0")) {
            const u = users.find((x) => x.user_id === params.user_id);
            if (u) {
              u.failed_login_count = 0;
              u.locked_until = null;
              u.last_login_at = new Date();
            }
            return { recordset: [] };
          }

          if (text.includes("UPDATE dbo.users SET last_login_at = SYSDATETIME()")) {
            const u = users.find((x) => x.user_id === params.user_id);
            if (u) u.last_login_at = new Date();
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
              })
              .sort((a, b) => Number(b.is_default) - Number(a.is_default) || a.rank_no - b.rank_no);
            return { recordset: rows };
          }

          if (text.includes("FROM dbo.user_roles ur JOIN dbo.roles r ON r.role_id = ur.role_id WHERE ur.user_id = @user_id")) {
            const rows = userRoles
              .filter((ur) => ur.user_id === params.user_id)
              .map((ur) => {
                const r = roles.find((x) => x.role_id === ur.role_id);
                return {
                  role_id: ur.role_id,
                  is_default: ur.is_default,
                  code: r.code,
                  name: r.name,
                  rank_no: r.rank_no,
                };
              })
              .sort((a, b) => Number(b.is_default) - Number(a.is_default) || a.rank_no - b.rank_no);
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
              ip_address: params.ip_address,
              user_agent: params.user_agent,
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

          if (text.includes("UPDATE dbo.user_sessions SET revoked_at = SYSDATETIME()")) {
            const s = sessions.find(
              (x) => x.session_id.toLowerCase() === String(params.session_id).toLowerCase(),
            );
            if (s && s.revoked_at === null) {
              s.revoked_at = new Date();
              if (text.includes("last_seen_at = SYSDATETIME()")) {
                s.last_seen_at = new Date();
              }
            }
            return { recordset: [] };
          }

          if (text.includes("UPDATE dbo.user_sessions SET last_seen_at = SYSDATETIME()")) {
            const s = sessions.find(
              (x) => x.session_id.toLowerCase() === String(params.session_id).toLowerCase(),
            );
            if (!s || s.revoked_at !== null) return { recordset: [] };
            s.last_seen_at = new Date();
            s.expires_at = new Date(Date.now() + params.timeout_min * 60_000);
            return {
              recordset: [
                { last_seen_at: s.last_seen_at, expires_at: s.expires_at },
              ],
            };
          }

          if (text.includes("FROM dbo.fn_active_delegations")) {
            return { recordset: getActiveDelegations(params.user_id) };
          }

          if (text.includes("FROM dbo.fn_permissions_of")) {
            return {
              recordset: getPermissionsFor(params.user_id, params.role_id),
            };
          }

          if (text.includes("WHERE u.is_active = 1 AND u.is_demo_account = 1")) {
            const rows = [];
            for (const ur of userRoles) {
              const u = users.find((x) => x.user_id === ur.user_id);
              const r = roles.find((x) => x.role_id === ur.role_id);
              if (!u || !u.is_active || !u.is_demo_account || !r) continue;
              const f = fields.find((x) => x.field_id === r.field_id);
              rows.push({
                user_id: u.user_id,
                username: u.username,
                full_name: u.full_name,
                position_title: u.position_title,
                role_id: r.role_id,
                role_code: r.code,
                role_name: r.name,
                role_level: r.role_level,
                rank_no: r.rank_no,
                field_id: r.field_id,
                field_code: f?.code ?? null,
                field_name: f?.name ?? null,
                is_default: ur.is_default,
              });
            }
            if (text.includes("ORDER BY ur.is_default DESC")) {
              rows.sort(
                (a, b) =>
                  Number(b.is_default) - Number(a.is_default) ||
                  a.rank_no - b.rank_no ||
                  a.user_id - b.user_id,
              );
            } else {
              rows.sort(
                (a, b) =>
                  a.rank_no - b.rank_no ||
                  a.user_id - b.user_id ||
                  Number(b.is_default) - Number(a.is_default),
              );
            }
            return { recordset: rows };
          }

          if (text.includes("SELECT role_id FROM dbo.roles WHERE code = @code")) {
            const r = roles.find((x) => x.code === params.code);
            return { recordset: r ? [{ role_id: r.role_id }] : [] };
          }

          if (text.includes("EXEC dbo.sp_switch_role")) {
            const s = sessions.find(
              (x) => x.session_id.toLowerCase() === String(params.session_id).toLowerCase(),
            );
            const u = s ? users.find((x) => x.user_id === s.user_id) : null;
            if (
              !s ||
              !u ||
              !u.is_active ||
              s.revoked_at !== null ||
              s.expires_at.getTime() <= Date.now()
            ) {
              throw sqlThrow(
                50403,
                "Phiên đăng nhập không hợp lệ hoặc đã hết hạn.",
              );
            }
            const hasRole = userRoles.some(
              (ur) =>
                ur.user_id === s.user_id && ur.role_id === params.new_role_id,
            );
            if (!hasRole) {
              throw sqlThrow(
                50403,
                "Vai trò này không nằm trong danh sách được cấp cho tài khoản.",
              );
            }
            const oldRole = s.active_role_id;
            s.active_role_id = params.new_role_id;
            s.last_seen_at = new Date();
            auditLogs.push({
              log_id: auditLogs.length + 1,
              user_id: s.user_id,
              active_role_id: params.new_role_id,
              action: "SWITCH_ROLE",
              entity_type: null,
              entity_id: null,
              detail: JSON.stringify({
                from_role_id: oldRole,
                to_role_id: params.new_role_id,
              }),
              ip_address: null,
              created_at: new Date(),
            });
            return { recordset: [] };
          }

          throw new Error(`Unhandled mock SQL query: ${text}`);
        },
      };
    },
  };

  return { pool, sessions, auditLogs, users, systemSettings };
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

describe("Auth API (Task 1.2.1)", () => {
  let state;
  let testServer;
  const originalDemoModeEnv = process.env.DEMO_MODE;

  beforeEach(async () => {
    process.env.DEMO_MODE = "1";
    state = createSeedDatabaseState();
    setPoolProvider(() => state.pool);
    testServer = await startTestServer();
  });

  afterEach(async () => {
    process.env.DEMO_MODE = originalDemoModeEnv;
    setPoolProvider(null);
    if (testServer) {
      await testServer.close();
    }
  });

  it("1. Đăng nhập thành công với tài khoản mẫu (tp.vhxh / Demo@123)", async () => {
    const res = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "tp.vhxh", password: "Demo@123" }),
    });

    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.match(
      body.data.session_id,
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    );
    assert.equal(body.data.user.username, "tp.vhxh");
    assert.equal(body.data.active_role.code, "TP");
    assert.equal(body.data.is_demo_mode, false);
    assert.ok(Array.isArray(body.data.permissions));
    assert.equal(state.auditLogs.at(-1).action, "LOGIN");
  });

  it("2. Đăng nhập sai mật khẩu trả 401 UNAUTHORIZED, tăng failed_login_count và ghi audit LOGIN_FAILED", async () => {
    const res = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "tp.vhxh", password: "SaiMatKhau" }),
    });

    assert.equal(res.status, 401);
    const body = await res.json();
    assert.equal(body.success, false);
    assert.equal(body.error.code, "UNAUTHORIZED");
    assert.equal(state.users.find((u) => u.username === "tp.vhxh").failed_login_count, 1);
    assert.equal(state.auditLogs.at(-1).action, "LOGIN_FAILED");
  });

  it("3. Nhập sai quá 5 lần khóa tạm tài khoản (403 FORBIDDEN), sau đó nhập đúng vẫn bị chặn", async () => {
    for (let i = 1; i <= 4; i++) {
      const r = await fetch(`${testServer.baseUrl}/api/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: "cv.yte", password: "wrong" }),
      });
      assert.equal(r.status, 401);
    }

    const res5 = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "cv.yte", password: "wrong" }),
    });
    assert.equal(res5.status, 403);
    const body5 = await res5.json();
    assert.equal(body5.error.code, "FORBIDDEN");
    assert.equal(body5.error.sql_error, 50403);

    const resAfterLock = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "cv.yte", password: "Demo@123" }),
    });
    assert.equal(resAfterLock.status, 403);
  });

  it("4. Thiếu username hoặc password trả 400 BAD_REQUEST (sql_error: 50400)", async () => {
    const res = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "  ", password: "" }),
    });

    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.error.code, "BAD_REQUEST");
    assert.equal(body.error.sql_error, 50400);
  });

  it("5. Đăng nhập chọn vai trò không thuộc tài khoản bị chặn 403 FORBIDDEN", async () => {
    const res = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        username: "cv.yte",
        password: "Demo@123",
        role_id: 1,
      }),
    });

    assert.equal(res.status, 403);
    const body = await res.json();
    assert.equal(body.error.code, "FORBIDDEN");
    assert.equal(body.error.sql_error, 50403);
    assert.equal(state.auditLogs.at(-1).action, "ACCESS_DENIED");
  });

  it("6. Kiểm tra phiên GET /api/auth/me hợp lệ và tự khóa khi hết hạn", async () => {
    const unauth = await fetch(`${testServer.baseUrl}/api/auth/me`);
    assert.equal(unauth.status, 401);

    const loginRes = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "cv.noivu", password: "Demo@123" }),
    });
    const { data: session } = await loginRes.json();

    const meRes = await fetch(`${testServer.baseUrl}/api/auth/me`, {
      headers: { Authorization: `Bearer ${session.session_id}` },
    });
    assert.equal(meRes.status, 200);
    const meBody = await meRes.json();
    assert.equal(meBody.data.active_role.code, "CV_NV");

    // Mô phỏng phiên quá hạn 60 phút
    state.sessions[0].expires_at = new Date(Date.now() - 1000);
    const expiredRes = await fetch(`${testServer.baseUrl}/api/auth/me`, {
      headers: { Authorization: `Bearer ${session.session_id}` },
    });
    assert.equal(expiredRes.status, 401);
    assert.ok(state.sessions[0].revoked_at !== null);
  });

  it("7. Đổi vai trò: cv.vhxh đổi sang CV_DTTG được (200), cố đổi lên TP bị chặn (403)", async () => {
    const loginRes = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "cv.vhxh", password: "Demo@123" }),
    });
    const { data: session } = await loginRes.json();
    assert.equal(session.active_role.code, "CV_VHXH");
    assert.equal(session.available_roles.length, 2);

    const switchOk = await fetch(`${testServer.baseUrl}/api/auth/switch-role`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.session_id}`,
      },
      body: JSON.stringify({ role_id: 9 }),
    });
    assert.equal(switchOk.status, 200);
    const switchOkBody = await switchOk.json();
    assert.equal(switchOkBody.data.active_role.code, "CV_DTTG");
    assert.equal(state.auditLogs.at(-1).action, "SWITCH_ROLE");

    const switchFail = await fetch(`${testServer.baseUrl}/api/auth/switch-role`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.session_id}`,
      },
      body: JSON.stringify({ role_id: 2 }),
    });
    assert.equal(switchFail.status, 403);
    const switchFailBody = await switchFail.json();
    assert.equal(switchFailBody.error.code, "FORBIDDEN");
    assert.equal(switchFailBody.error.sql_error, 50403);
  });

  it("8. Chọn nhanh 9 vai trò chỉ bật khi DEMO_MODE=1 và bị chặn khi DEMO_MODE=0", async () => {
    const listRes = await fetch(`${testServer.baseUrl}/api/auth/demo-accounts`);
    assert.equal(listRes.status, 200);
    const listBody = await listRes.json();
    assert.equal(listBody.data.demo_mode, true);
    assert.equal(listBody.data.roles.length, 9);

    const quickRes = await fetch(`${testServer.baseUrl}/api/auth/demo-login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ role_code: "PCT" }),
    });
    assert.equal(quickRes.status, 200);
    const quickBody = await quickRes.json();
    assert.equal(quickBody.data.is_demo_mode, true);
    assert.equal(quickBody.data.active_role.code, "PCT");

    const switchQuickRes = await fetch(`${testServer.baseUrl}/api/auth/demo-login`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${quickBody.data.session_id}`,
      },
      body: JSON.stringify({ role_code: "PTP" }),
    });
    assert.equal(switchQuickRes.status, 200);
    assert.ok(state.sessions[0].revoked_at !== null);

    // Tắt chế độ demo
    process.env.DEMO_MODE = "0";
    const offListRes = await fetch(`${testServer.baseUrl}/api/auth/demo-accounts`);
    const offListBody = await offListRes.json();
    assert.equal(offListBody.data.demo_mode, false);
    assert.deepEqual(offListBody.data.roles, []);

    const offLoginRes = await fetch(`${testServer.baseUrl}/api/auth/demo-login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ role_code: "TP" }),
    });
    assert.equal(offLoginRes.status, 403);
  });

  it("9. Đăng xuất POST /api/auth/logout thu hồi phiên và vô hiệu hóa request tiếp theo", async () => {
    const loginRes = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "pct.vhxh", password: "Demo@123" }),
    });
    const { data: session } = await loginRes.json();

    const logoutRes = await fetch(`${testServer.baseUrl}/api/auth/logout`, {
      method: "POST",
      headers: { Authorization: `Bearer ${session.session_id}` },
    });
    assert.equal(logoutRes.status, 200);
    const logoutBody = await logoutRes.json();
    assert.equal(logoutBody.data.logged_out, true);
    assert.equal(state.auditLogs.at(-1).action, "LOGOUT");

    const meAfterLogout = await fetch(`${testServer.baseUrl}/api/auth/me`, {
      headers: { Authorization: `Bearer ${session.session_id}` },
    });
    assert.equal(meAfterLogout.status, 401);
  });

  it("10. GET /api/auth/permissions trả về danh sách quyền và ủy quyền hiện tại", async () => {
    const loginRes = await fetch(`${testServer.baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: "ptp.vhxh", password: "Demo@123" }),
    });
    const { data: session } = await loginRes.json();

    const permRes = await fetch(`${testServer.baseUrl}/api/auth/permissions`, {
      headers: { Authorization: `Bearer ${session.session_id}` },
    });
    assert.equal(permRes.status, 200);
    const permBody = await permRes.json();
    assert.equal(permBody.data.role_id, 3);
    assert.equal(permBody.data.active_delegations.length, 1);
    const approvalPerm = permBody.data.permissions.find(
      (p) => p.function_code === "F08_PENDING_APPROVAL",
    );
    assert.equal(approvalPerm.requires_delegation, true);
    assert.equal(approvalPerm.is_usable_now, true);
  });
});
