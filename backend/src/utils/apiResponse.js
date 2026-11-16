class AppError extends Error {
  constructor(status, code, message, sqlError) {
    super(message);
    this.name = "AppError";
    this.status = status;
    this.code = code;
    if (sqlError !== undefined) {
      this.sqlError = sqlError;
    }
  }
}

function sendSuccess(res, data, status = 200, meta = undefined) {
  const payload = {
    success: true,
    data,
  };

  if (meta !== undefined) {
    payload.meta = meta;
  }

  return res.status(status).json(payload);
}

function sendError(res, status, code, message, sqlError = undefined) {
  const errorBody = {
    code,
    message,
  };

  if (sqlError !== undefined) {
    errorBody.sql_error = sqlError;
  }

  return res.status(status).json({
    success: false,
    error: errorBody,
  });
}

const DB_CONNECTION_ERROR_CODES = new Set([
  "ESOCKET",
  "ECONNREFUSED",
  "ELOGIN",
  "ETIMEOUT",
  "EINSTLOOKUP",
  "ENOTOPEN",
]);

function extractSqlErrorNumber(error) {
  if (!error || typeof error !== "object") {
    return undefined;
  }
  return (
    error.number ??
    error.originalError?.info?.number ??
    error.precedingErrors?.[0]?.number
  );
}

function mapErrorToHttp(error) {
  if (error instanceof AppError) {
    return {
      status: error.status,
      code: error.code,
      message: error.message,
      sqlError: error.sqlError,
    };
  }

  const sqlNumber = extractSqlErrorNumber(error);

  if (sqlNumber === 50400) {
    return {
      status: 400,
      code: "BAD_REQUEST",
      sqlError: 50400,
      message: error.message || "Dữ liệu đầu vào không hợp lệ.",
    };
  }

  if (sqlNumber === 50403) {
    return {
      status: 403,
      code: "FORBIDDEN",
      sqlError: 50403,
      message:
        error.message || "Vai trò hiện tại không có quyền thực hiện thao tác này.",
    };
  }

  if (sqlNumber === 50404) {
    return {
      status: 404,
      code: "NOT_FOUND",
      sqlError: 50404,
      message: error.message || "Không tìm thấy dữ liệu yêu cầu.",
    };
  }

  if (
    sqlNumber === 50409 ||
    sqlNumber === 2601 ||
    sqlNumber === 2627 ||
    sqlNumber === 547
  ) {
    return {
      status: 409,
      code: "CONFLICT",
      sqlError: sqlNumber,
      message:
        sqlNumber === 50409
          ? error.message || "Xung đột trạng thái dữ liệu."
          : "Dữ liệu bị xung đột hoặc vi phạm ràng buộc.",
    };
  }

  if (DB_CONNECTION_ERROR_CODES.has(error?.code)) {
    return {
      status: 503,
      code: "DATABASE_UNAVAILABLE",
      message: "Không thể kết nối SQL Server.",
    };
  }

  return {
    status: 500,
    code: "INTERNAL_ERROR",
    message: "Đã xảy ra lỗi hệ thống. Vui lòng thử lại sau.",
  };
}

module.exports = {
  AppError,
  sendSuccess,
  sendError,
  mapErrorToHttp,
};
