const crypto = require("node:crypto");
const bcrypt = require("bcryptjs");
const { getPool, sql } = require("../config/db");
const { AppError } = require("../utils/apiResponse");

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUuid(value) {
  return typeof value === "string" && UUID_REGEX.test(value.trim());
}

function normalizeIp(ipAddress) {
  if (!ipAddress || typeof ipAddress !== "string") {
    return null;
  }
  return ipAddress.trim().slice(0, 45) || null;
}

function normalizeUserAgent(userAgent) {
  if (!userAgent || typeof userAgent !== "string") {
    return null;
  }
  return userAgent.trim().slice(0, 300) || null;
}

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

async function getAuthSettings(pool) {
  const result = await pool.request().query(`
    SELECT setting_key, TRY_CAST(setting_value AS INT) AS int_value
    FROM dbo.system_settings
    WHERE setting_key IN ('SESSION_TIMEOUT_MIN', 'MAX_LOGIN_FAILED', 'LOCK_MINUTES', 'DEMO_MODE')
  `);

  const dbSettings = {};
  for (const row of result.recordset || []) {
    if (row.int_value !== null && row.int_value !== undefined) {
      dbSettings[row.setting_key] = Number(row.int_value);
    }
  }

  const envSessionTimeout = Number(process.env.SESSION_TIMEOUT_MIN);
  const sessionTimeoutMin =
    dbSettings.SESSION_TIMEOUT_MIN > 0
      ? dbSettings.SESSION_TIMEOUT_MIN
      : Number.isInteger(envSessionTimeout) && envSessionTimeout > 0
        ? envSessionTimeout
        : 60;

  const maxLoginFailed =
    dbSettings.MAX_LOGIN_FAILED > 0 ? dbSettings.MAX_LOGIN_FAILED : 5;
  const lockMinutes =
    dbSettings.LOCK_MINUTES > 0 ? dbSettings.LOCK_MINUTES : 15;

  const envDemoEnabled = String(process.env.DEMO_MODE ?? "1").trim() === "1";
  const dbDemoEnabled = (dbSettings.DEMO_MODE ?? 1) === 1;

  return {
    sessionTimeoutMin,
    maxLoginFailed,
    lockMinutes,
    isDemoModeEnabled: envDemoEnabled && dbDemoEnabled,
  };
}

async function writeAudit(
  pool,
  {
    userId = null,
    roleId = null,
    action,
    entityType = null,
    entityId = null,
    detail = null,
    ipAddress = null,
  },
) {
  try {
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
      .input("ip_address", sql.VarChar(45), normalizeIp(ipAddress))
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

function mapRoleSummary(row) {
  return {
    role_id: row.role_id,
    code: row.role_code ?? row.code,
    name: row.role_name ?? row.name,
    role_level: row.role_level,
    rank_no: row.rank_no,
    field_id: row.field_id ?? null,
    field_code: row.field_code ?? null,
    field_name: row.field_name ?? null,
    ...(row.is_default !== undefined
      ? { is_default: Boolean(row.is_default) }
      : {}),
  };
}

function mapPermission(row) {
  return {
    function_code: row.function_code,
    function_name: row.function_name,
    group_code: row.group_code,
    action: row.action,
    scope: row.scope,
    requires_delegation: Boolean(row.requires_delegation),
    is_usable_now: Boolean(row.is_usable_now),
  };
}

function mapDelegation(row) {
  return {
    delegation_id: row.delegation_id,
    from_user_id: row.from_user_id,
    can_sign: Boolean(row.can_sign),
    can_approve_extension: Boolean(row.can_approve_extension),
    can_view_confidential: Boolean(row.can_view_confidential),
    valid_from: row.valid_from,
    valid_to: row.valid_to,
  };
}

async function getSessionContext(pool, sessionId, { touch = true } = {}) {
  if (!isValidUuid(sessionId)) {
    throw new AppError(
      401,
      "UNAUTHORIZED",
      "Phiên đăng nhập không hợp lệ hoặc đã hết hạn.",
    );
  }

  const normalizedSid = sessionId.trim();

  const sessionResult = await pool
    .request()
    .input("session_id", sql.UniqueIdentifier, normalizedSid)
    .query(`
      SELECT
        s.session_id,
        s.user_id,
        s.active_role_id,
        s.is_demo_mode,
        s.created_at,
        s.last_seen_at,
        s.expires_at,
        s.revoked_at,
        CASE WHEN s.revoked_at IS NOT NULL OR s.expires_at <= SYSDATETIME() THEN 1 ELSE 0 END AS is_expired,
        u.username,
        u.full_name,
        u.position_title,
        u.email,
        u.phone,
        u.is_active,
        u.is_demo_account,
        r.code AS role_code,
        r.name AS role_name,
        r.role_level,
        r.rank_no,
        r.field_id,
        f.code AS field_code,
        f.name AS field_name
      FROM dbo.user_sessions s
      JOIN dbo.users u ON u.user_id = s.user_id
      JOIN dbo.roles r ON r.role_id = s.active_role_id
      LEFT JOIN dbo.fields f ON f.field_id = r.field_id
      WHERE s.session_id = @session_id
    `);

  const row = sessionResult.recordset?.[0];
  if (!row) {
    throw new AppError(
      401,
      "UNAUTHORIZED",
      "Phiên đăng nhập không tồn tại hoặc đã hết hạn.",
    );
  }

  if (row.revoked_at !== null || Number(row.is_expired) === 1) {
    if (row.revoked_at === null && Number(row.is_expired) === 1) {
      await pool
        .request()
        .input("session_id", sql.UniqueIdentifier, normalizedSid)
        .query(`
          UPDATE dbo.user_sessions
          SET revoked_at = SYSDATETIME()
          WHERE session_id = @session_id AND revoked_at IS NULL
        `);
    }

    throw new AppError(
      401,
      "UNAUTHORIZED",
      "Phiên đăng nhập đã hết hạn hoặc đã đăng xuất.",
    );
  }

  if (!row.is_active) {
    await pool
      .request()
      .input("session_id", sql.UniqueIdentifier, normalizedSid)
      .query(`
        UPDATE dbo.user_sessions
        SET revoked_at = SYSDATETIME()
        WHERE session_id = @session_id AND revoked_at IS NULL
      `);

    throw new AppError(
      403,
      "FORBIDDEN",
      "Tài khoản đã bị khóa hoặc ngừng hoạt động.",
      50403,
    );
  }

  const settings = await getAuthSettings(pool);
  let lastSeenAt = row.last_seen_at;
  let expiresAt = row.expires_at;

  if (touch) {
    const touchResult = await pool
      .request()
      .input("session_id", sql.UniqueIdentifier, normalizedSid)
      .input("timeout_min", sql.Int, settings.sessionTimeoutMin)
      .query(`
        UPDATE dbo.user_sessions
        SET last_seen_at = SYSDATETIME(),
            expires_at = DATEADD(MINUTE, @timeout_min, SYSDATETIME())
        OUTPUT INSERTED.last_seen_at, INSERTED.expires_at
        WHERE session_id = @session_id AND revoked_at IS NULL
      `);

    if (touchResult.recordset?.[0]) {
      lastSeenAt = touchResult.recordset[0].last_seen_at;
      expiresAt = touchResult.recordset[0].expires_at;
    }
  }

  const [rolesResult, delegationsResult, permissionsResult] = await Promise.all([
    pool
      .request()
      .input("user_id", sql.Int, row.user_id)
      .query(`
        SELECT r.role_id, r.code, r.name, r.role_level, r.rank_no, r.field_id,
               f.code AS field_code, f.name AS field_name, ur.is_default
        FROM dbo.user_roles ur
        JOIN dbo.roles r ON r.role_id = ur.role_id
        LEFT JOIN dbo.fields f ON f.field_id = r.field_id
        WHERE ur.user_id = @user_id
        ORDER BY ur.is_default DESC, r.rank_no ASC, r.role_id ASC
      `),
    pool
      .request()
      .input("user_id", sql.Int, row.user_id)
      .query(`
        SELECT delegation_id, from_user_id, can_sign, can_approve_extension,
               can_view_confidential, valid_from, valid_to
        FROM dbo.fn_active_delegations(@user_id, SYSDATETIME())
      `),
    pool
      .request()
      .input("user_id", sql.Int, row.user_id)
      .input("role_id", sql.Int, row.active_role_id)
      .query(`
        SELECT function_code, function_name, group_code, action, scope,
               requires_delegation, is_usable_now
        FROM dbo.fn_permissions_of(@user_id, @role_id)
        ORDER BY function_code, action
      `),
  ]);

  return {
    session_id: row.session_id,
    created_at: row.created_at,
    last_seen_at: lastSeenAt,
    expires_at: expiresAt,
    is_demo_mode: Boolean(row.is_demo_mode),
    demo_mode_enabled: Boolean(settings.isDemoModeEnabled),
    user: {
      user_id: row.user_id,
      username: row.username,
      full_name: row.full_name,
      position_title: row.position_title,
      email: row.email,
      phone: row.phone,
      is_demo_account: Boolean(row.is_demo_account),
    },
    active_role: mapRoleSummary({
      role_id: row.active_role_id,
      role_code: row.role_code,
      role_name: row.role_name,
      role_level: row.role_level,
      rank_no: row.rank_no,
      field_id: row.field_id,
      field_code: row.field_code,
      field_name: row.field_name,
    }),
    available_roles: (rolesResult.recordset || []).map(mapRoleSummary),
    active_delegations: (delegationsResult.recordset || []).map(mapDelegation),
    permissions: (permissionsResult.recordset || []).map(mapPermission),
  };
}

async function createSessionAndAudit(
  pool,
  { userId, roleId, isDemoMode, timeoutMin, ipAddress, userAgent, auditDetail },
) {
  const sessionId = crypto.randomUUID();
  const cleanIp = normalizeIp(ipAddress);
  const cleanUa = normalizeUserAgent(userAgent);

  await pool
    .request()
    .input("session_id", sql.UniqueIdentifier, sessionId)
    .input("user_id", sql.Int, userId)
    .input("active_role_id", sql.Int, roleId)
    .input("is_demo_mode", sql.Bit, isDemoMode ? 1 : 0)
    .input("timeout_min", sql.Int, timeoutMin)
    .input("ip_address", sql.VarChar(45), cleanIp)
    .input("user_agent", sql.NVarChar(300), cleanUa)
    .query(`
      INSERT INTO dbo.user_sessions (
        session_id, user_id, active_role_id, is_demo_mode, expires_at, ip_address, user_agent
      )
      VALUES (
        @session_id, @user_id, @active_role_id, @is_demo_mode,
        DATEADD(MINUTE, @timeout_min, SYSDATETIME()),
        @ip_address, @user_agent
      )
    `);

  await writeAudit(pool, {
    userId,
    roleId,
    action: "LOGIN",
    detail: auditDetail,
    ipAddress: cleanIp,
  });

  return getSessionContext(pool, sessionId, { touch: false });
}

async function login({
  username,
  password,
  roleId,
  roleCode,
  ipAddress,
  userAgent,
}) {
  if (
    typeof username !== "string" ||
    username.trim().length === 0 ||
    typeof password !== "string" ||
    password.length === 0
  ) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Vui lòng nhập đầy đủ tên đăng nhập và mật khẩu.",
      50400,
    );
  }

  const requestedRoleId = parsePositiveInt(roleId, "Mã vai trò");
  const requestedRoleCode =
    typeof roleCode === "string" && roleCode.trim().length > 0
      ? roleCode.trim()
      : null;

  const pool = await getPool();
  const normalizedUsername = username.trim();

  const userResult = await pool
    .request()
    .input("username", sql.VarChar(50), normalizedUsername)
    .query(`
      SELECT
        user_id,
        username,
        password_hash,
        full_name,
        is_active,
        is_demo_account,
        failed_login_count,
        locked_until,
        CASE WHEN locked_until IS NOT NULL AND locked_until > SYSDATETIME() THEN 1 ELSE 0 END AS is_currently_locked,
        CASE WHEN locked_until IS NOT NULL AND locked_until <= SYSDATETIME() THEN 1 ELSE 0 END AS lock_expired
      FROM dbo.users
      WHERE username = @username
    `);

  const user = userResult.recordset?.[0];
  if (!user) {
    await writeAudit(pool, {
      userId: null,
      roleId: null,
      action: "LOGIN_FAILED",
      detail: { username: normalizedUsername, reason: "USER_NOT_FOUND" },
      ipAddress,
    });
    throw new AppError(
      401,
      "UNAUTHORIZED",
      "Tên đăng nhập hoặc mật khẩu không đúng.",
    );
  }

  if (!user.is_active) {
    await writeAudit(pool, {
      userId: user.user_id,
      roleId: null,
      action: "LOGIN_FAILED",
      detail: { reason: "ACCOUNT_INACTIVE" },
      ipAddress,
    });
    throw new AppError(
      403,
      "FORBIDDEN",
      "Tài khoản đã bị vô hiệu hóa.",
      50403,
    );
  }

  if (Number(user.is_currently_locked) === 1) {
    await writeAudit(pool, {
      userId: user.user_id,
      roleId: null,
      action: "LOGIN_FAILED",
      detail: { reason: "ACCOUNT_LOCKED", locked_until: user.locked_until },
      ipAddress,
    });
    throw new AppError(
      403,
      "FORBIDDEN",
      "Tài khoản đang bị tạm khóa do nhập sai mật khẩu nhiều lần. Vui lòng thử lại sau.",
      50403,
    );
  }

  const settings = await getAuthSettings(pool);
  const passwordMatched = await bcrypt.compare(password, user.password_hash);

  if (!passwordMatched) {
    const baseFailed =
      Number(user.lock_expired) === 1 ? 0 : Number(user.failed_login_count || 0);
    const nextFailedCount = baseFailed + 1;

    if (nextFailedCount >= settings.maxLoginFailed) {
      await pool
        .request()
        .input("user_id", sql.Int, user.user_id)
        .input("failed_count", sql.TinyInt, Math.min(nextFailedCount, 255))
        .input("lock_minutes", sql.Int, settings.lockMinutes)
        .query(`
          UPDATE dbo.users
          SET failed_login_count = @failed_count,
              locked_until = DATEADD(MINUTE, @lock_minutes, SYSDATETIME()),
              updated_at = SYSDATETIME()
          WHERE user_id = @user_id
        `);

      await writeAudit(pool, {
        userId: user.user_id,
        roleId: null,
        action: "LOGIN_FAILED",
        detail: {
          reason: "INVALID_PASSWORD_LOCKED",
          failed_login_count: nextFailedCount,
        },
        ipAddress,
      });

      throw new AppError(
        403,
        "FORBIDDEN",
        `Bạn đã nhập sai mật khẩu quá ${settings.maxLoginFailed} lần. Tài khoản bị tạm khóa ${settings.lockMinutes} phút.`,
        50403,
      );
    }

    await pool
      .request()
      .input("user_id", sql.Int, user.user_id)
      .input("failed_count", sql.TinyInt, Math.min(nextFailedCount, 255))
      .query(`
        UPDATE dbo.users
        SET failed_login_count = @failed_count,
            locked_until = NULL,
            updated_at = SYSDATETIME()
        WHERE user_id = @user_id
      `);

    await writeAudit(pool, {
      userId: user.user_id,
      roleId: null,
      action: "LOGIN_FAILED",
      detail: {
        reason: "INVALID_PASSWORD",
        failed_login_count: nextFailedCount,
      },
      ipAddress,
    });

    throw new AppError(
      401,
      "UNAUTHORIZED",
      "Tên đăng nhập hoặc mật khẩu không đúng.",
    );
  }

  const rolesResult = await pool
    .request()
    .input("user_id", sql.Int, user.user_id)
    .query(`
      SELECT ur.role_id, ur.is_default, r.code, r.name
      FROM dbo.user_roles ur
      JOIN dbo.roles r ON r.role_id = ur.role_id
      WHERE ur.user_id = @user_id
      ORDER BY ur.is_default DESC, r.rank_no ASC, r.role_id ASC
    `);

  const userRoles = rolesResult.recordset || [];
  if (userRoles.length === 0) {
    throw new AppError(
      403,
      "FORBIDDEN",
      "Tài khoản chưa được cấp vai trò trong hệ thống.",
      50403,
    );
  }

  let selectedRole;
  if (requestedRoleId !== null || requestedRoleCode !== null) {
    selectedRole = userRoles.find((role) => {
      const idMatches =
        requestedRoleId === null || role.role_id === requestedRoleId;
      const codeMatches =
        requestedRoleCode === null ||
        role.code.toUpperCase() === requestedRoleCode.toUpperCase();
      return idMatches && codeMatches;
    });

    if (!selectedRole) {
      await writeAudit(pool, {
        userId: user.user_id,
        roleId: null,
        action: "ACCESS_DENIED",
        detail: {
          reason: "ROLE_NOT_GRANTED",
          requested_role_id: requestedRoleId,
          requested_role_code: requestedRoleCode,
        },
        ipAddress,
      });

      throw new AppError(
        403,
        "FORBIDDEN",
        "Vai trò này không nằm trong danh sách được cấp cho tài khoản.",
        50403,
      );
    }
  } else {
    selectedRole =
      userRoles.find((role) => Boolean(role.is_default)) || userRoles[0];
  }

  await pool
    .request()
    .input("user_id", sql.Int, user.user_id)
    .query(`
      UPDATE dbo.users
      SET failed_login_count = 0,
          locked_until = NULL,
          last_login_at = SYSDATETIME(),
          updated_at = SYSDATETIME()
      WHERE user_id = @user_id
    `);

  return createSessionAndAudit(pool, {
    userId: user.user_id,
    roleId: selectedRole.role_id,
    isDemoMode: false,
    timeoutMin: settings.sessionTimeoutMin,
    ipAddress,
    userAgent,
    auditDetail: { mode: "PASSWORD", role_id: selectedRole.role_id },
  });
}

async function getDemoAccounts() {
  const pool = await getPool();
  const settings = await getAuthSettings(pool);

  if (!settings.isDemoModeEnabled) {
    return {
      demo_mode: false,
      roles: [],
      accounts: [],
    };
  }

  const result = await pool.request().query(`
    SELECT u.user_id, u.username, u.full_name, u.position_title,
           r.role_id, r.code AS role_code, r.name AS role_name,
           r.role_level, r.rank_no, r.field_id,
           ur.is_default, f.code AS field_code, f.name AS field_name
    FROM dbo.users u
    JOIN dbo.user_roles ur ON ur.user_id = u.user_id
    JOIN dbo.roles r       ON r.role_id  = ur.role_id
    LEFT JOIN dbo.fields f ON f.field_id = r.field_id
    WHERE u.is_active = 1 AND u.is_demo_account = 1
    ORDER BY r.rank_no ASC, u.user_id ASC, ur.is_default DESC
  `);

  const rows = result.recordset || [];
  const accounts = rows.map((row) => ({
    user_id: row.user_id,
    username: row.username,
    full_name: row.full_name,
    position_title: row.position_title,
    role_id: row.role_id,
    role_code: row.role_code,
    role_name: row.role_name,
    role_level: row.role_level,
    rank_no: row.rank_no,
    field_id: row.field_id ?? null,
    field_code: row.field_code ?? null,
    field_name: row.field_name ?? null,
    is_default: Boolean(row.is_default),
  }));

  const roleMap = new Map();
  for (const account of accounts) {
    const existing = roleMap.get(account.role_id);
    if (!existing || (!existing.is_default && account.is_default)) {
      roleMap.set(account.role_id, account);
    }
  }

  const roles = Array.from(roleMap.values()).sort(
    (a, b) => a.rank_no - b.rank_no || a.role_id - b.role_id,
  );

  return {
    demo_mode: true,
    roles,
    accounts,
  };
}

async function demoQuickLogin({
  roleId,
  roleCode,
  userId,
  username,
  currentSessionId,
  ipAddress,
  userAgent,
}) {
  const pool = await getPool();
  const settings = await getAuthSettings(pool);

  if (!settings.isDemoModeEnabled) {
    throw new AppError(
      403,
      "FORBIDDEN",
      "Chọn nhanh 9 vai trò chỉ khả dụng trong chế độ trình diễn (DEMO_MODE=1).",
      50403,
    );
  }

  const requestedRoleId = parsePositiveInt(roleId, "Mã vai trò");
  const requestedUserId = parsePositiveInt(userId, "Mã tài khoản");
  const requestedRoleCode =
    typeof roleCode === "string" && roleCode.trim().length > 0
      ? roleCode.trim().toUpperCase()
      : null;
  const requestedUsername =
    typeof username === "string" && username.trim().length > 0
      ? username.trim()
      : null;

  if (
    requestedRoleId === null &&
    requestedRoleCode === null &&
    requestedUserId === null &&
    requestedUsername === null
  ) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Vui lòng chọn một vai trò hoặc tài khoản trình diễn.",
      50400,
    );
  }

  const rowsResult = await pool.request().query(`
    SELECT u.user_id, u.username, r.role_id, r.code AS role_code, r.rank_no, ur.is_default
    FROM dbo.users u
    JOIN dbo.user_roles ur ON ur.user_id = u.user_id
    JOIN dbo.roles r       ON r.role_id  = ur.role_id
    WHERE u.is_active = 1 AND u.is_demo_account = 1
    ORDER BY ur.is_default DESC, r.rank_no ASC, u.user_id ASC
  `);

  const demoRows = rowsResult.recordset || [];
  const hasUserFilter =
    requestedUserId !== null || requestedUsername !== null;
  const hasRoleFilter =
    requestedRoleId !== null || requestedRoleCode !== null;

  const userMatches = (row) =>
    (requestedUserId === null || row.user_id === requestedUserId) &&
    (requestedUsername === null ||
      row.username.toLowerCase() === requestedUsername.toLowerCase());

  const roleMatches = (row) =>
    (requestedRoleId === null || row.role_id === requestedRoleId) &&
    (requestedRoleCode === null ||
      row.role_code.toUpperCase() === requestedRoleCode);

  let target;
  if (hasUserFilter && hasRoleFilter) {
    const userExists = demoRows.some(userMatches);
    if (!userExists) {
      throw new AppError(
        404,
        "NOT_FOUND",
        "Không tìm thấy tài khoản trình diễn.",
        50404,
      );
    }

    target = demoRows.find((row) => userMatches(row) && roleMatches(row));
    if (!target) {
      throw new AppError(
        403,
        "FORBIDDEN",
        "Vai trò này không nằm trong danh sách được cấp cho tài khoản.",
        50403,
      );
    }
  } else if (hasRoleFilter) {
    target = demoRows.find(roleMatches);
  } else {
    target = demoRows.find(userMatches);
  }

  if (!target) {
    throw new AppError(
      404,
      "NOT_FOUND",
      "Không tìm thấy vai trò hoặc tài khoản trình diễn.",
      50404,
    );
  }

  if (isValidUuid(currentSessionId)) {
    await pool
      .request()
      .input("session_id", sql.UniqueIdentifier, currentSessionId.trim())
      .query(`
        UPDATE dbo.user_sessions
        SET revoked_at = SYSDATETIME()
        WHERE session_id = @session_id AND revoked_at IS NULL
      `);
  }

  await pool
    .request()
    .input("user_id", sql.Int, target.user_id)
    .query(`
      UPDATE dbo.users
      SET last_login_at = SYSDATETIME(),
          updated_at = SYSDATETIME()
      WHERE user_id = @user_id
    `);

  return createSessionAndAudit(pool, {
    userId: target.user_id,
    roleId: target.role_id,
    isDemoMode: true,
    timeoutMin: settings.sessionTimeoutMin,
    ipAddress,
    userAgent,
    auditDetail: {
      mode: "DEMO_ROLE_PICKER",
      role_id: target.role_id,
      role_code: target.role_code,
    },
  });
}

async function logout({ sessionId, userId, activeRoleId, ipAddress }) {
  const pool = await getPool();

  await pool
    .request()
    .input("session_id", sql.UniqueIdentifier, sessionId)
    .query(`
      UPDATE dbo.user_sessions
      SET revoked_at = SYSDATETIME(),
          last_seen_at = SYSDATETIME()
      WHERE session_id = @session_id AND revoked_at IS NULL
    `);

  await writeAudit(pool, {
    userId,
    roleId: activeRoleId,
    action: "LOGOUT",
    detail: { session_id: sessionId },
    ipAddress,
  });

  return {
    session_id: sessionId,
    logged_out: true,
  };
}

async function switchRole({ sessionId, newRoleId, roleCode }) {
  const pool = await getPool();
  let resolvedRoleId = parsePositiveInt(newRoleId, "Mã vai trò");

  if (
    resolvedRoleId === null &&
    typeof roleCode === "string" &&
    roleCode.trim().length > 0
  ) {
    const roleResult = await pool
      .request()
      .input("code", sql.VarChar(20), roleCode.trim().toUpperCase())
      .query("SELECT role_id FROM dbo.roles WHERE code = @code");

    resolvedRoleId = roleResult.recordset?.[0]?.role_id ?? null;
    if (resolvedRoleId === null) {
      throw new AppError(
        404,
        "NOT_FOUND",
        "Không tìm thấy vai trò cần chuyển đổi.",
        50404,
      );
    }
  }

  if (resolvedRoleId === null) {
    throw new AppError(
      400,
      "BAD_REQUEST",
      "Vui lòng chọn vai trò cần chuyển đổi.",
      50400,
    );
  }

  await pool
    .request()
    .input("session_id", sql.UniqueIdentifier, sessionId)
    .input("new_role_id", sql.Int, resolvedRoleId)
    .query(
      "EXEC dbo.sp_switch_role @session_id = @session_id, @new_role_id = @new_role_id",
    );

  return getSessionContext(pool, sessionId, { touch: false });
}

async function getPermissions({ userId, activeRoleId }) {
  const pool = await getPool();

  const [permissionsResult, delegationsResult] = await Promise.all([
    pool
      .request()
      .input("user_id", sql.Int, userId)
      .input("role_id", sql.Int, activeRoleId)
      .query(`
        SELECT function_code, function_name, group_code, action, scope,
               requires_delegation, is_usable_now
        FROM dbo.fn_permissions_of(@user_id, @role_id)
        ORDER BY function_code, action
      `),
    pool
      .request()
      .input("user_id", sql.Int, userId)
      .query(`
        SELECT delegation_id, from_user_id, can_sign, can_approve_extension,
               can_view_confidential, valid_from, valid_to
        FROM dbo.fn_active_delegations(@user_id, SYSDATETIME())
      `),
  ]);

  return {
    user_id: userId,
    role_id: activeRoleId,
    active_delegations: (delegationsResult.recordset || []).map(mapDelegation),
    permissions: (permissionsResult.recordset || []).map(mapPermission),
  };
}

module.exports = {
  isValidUuid,
  getAuthSettings,
  getSessionContext,
  login,
  getDemoAccounts,
  demoQuickLogin,
  logout,
  switchRole,
  getPermissions,
};
