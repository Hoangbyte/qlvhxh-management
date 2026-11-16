# QUY ƯỚC CHUẨN API – HỆ THỐNG QUẢN LÝ PHÒNG VH-XH

## 1. Quy tắc đặt tên Endpoint
- Tiền tố chung: `/api`
- Dùng danh từ số nhiều, viết thường, nối bằng dấu gạch ngang (`kebab-case`):
  - Xác thực & Vai trò: `/api/auth/login`, `/api/auth/logout`, `/api/auth/switch-role`, `/api/auth/permissions`
  - Màn hình Hôm nay: `/api/dashboard/today`, `/api/dashboard/waiting-documents`
  - Công việc: `/api/tasks`, `/api/tasks/:id`, `/api/tasks/:id/progress`
  - Văn bản: `/api/documents`, `/api/documents/:id`
  - Thông báo: `/api/notifications`, `/api/notifications/:id/read`

### Health check
- `GET /api/health` chạy `SELECT 1` trên SQL Server đã cấu hình.
- Khi truy vấn thành công, trả HTTP 200:
  ```json
  {
    "success": true,
    "data": {
      "database": "connected"
    }
  }
  ```
- Khi không kết nối hoặc truy vấn thất bại, trả HTTP 503:
  ```json
  {
    "success": false,
    "error": {
      "code": "DATABASE_UNAVAILABLE",
      "message": "Không thể kết nối SQL Server."
    }
  }
  ```
- Response lỗi không bao gồm mật khẩu, chuỗi kết nối hoặc stack trace.

## 2. Xác thực phiên (Authentication)
- Sau khi đăng nhập thành công, Backend trả về `session_id` (kiểu UUID từ bảng `dbo.user_sessions`).
- Mọi request cần đăng nhập phải gửi kèm Header:
  ```http
  Authorization: Bearer <session_id>
  ```

## 3. Cấu trúc JSON trả về chuẩn

### 3.1. Khi thành công (HTTP 200 hoặc 201)
```json
{
  "success": true,
  "data": {
    "id": 1,
    "title": "Dữ liệu trả về"
  },
  "meta": {
    "page": 1,
    "page_size": 20,
    "total_rows": 45
  }
}
```
*(Trường `meta` chỉ bắt buộc với các API có phân trang).*

### 3.2. Khi có lỗi (HTTP 400 / 401 / 403 / 404 / 409 / 500 / 503)
```json
{
  "success": false,
  "error": {
    "code": "FORBIDDEN",
    "sql_error": 50403,
    "message": "Vai trò hiện tại không có quyền thực hiện thao tác này."
  }
}
```

## 4. Bảng ánh xạ mã lỗi từ SQL Server sang HTTP Status
Các Stored Procedure trong `02_programmability.sql` ném lỗi bằng lệnh `THROW 504xx`. Backend bắt lỗi và trả về đúng HTTP Status tương ứng:

| Mã lỗi SQL (`ERROR_NUMBER`) | HTTP Status | Mã `error.code` | Ý nghĩa nghiệp vụ |
| :--- | :--- | :--- | :--- |
| `50400` | `400 Bad Request` | `BAD_REQUEST` | Dữ liệu đầu vào thiếu hoặc sai định dạng (VD: trả lại không nhập lý do). |
| *(Hết hạn session)* | `401 Unauthorized` | `UNAUTHORIZED` | Chưa đăng nhập, `session_id` không tồn tại hoặc đã hết hạn 60 phút. |
| `50403` | `403 Forbidden` | `FORBIDDEN` | Không có quyền trên chức năng, vượt cấp vai trò hoặc ngoài lĩnh vực. |
| `50404` | `404 Not Found` | `NOT_FOUND` | Không tìm thấy nhiệm vụ, văn bản hoặc sổ văn bản. |
| `50409` | `409 Conflict` | `CONFLICT` | Xung đột trạng thái (đã xử lý rồi, trùng số sổ, hoặc lỗi `row_ver`). |
| Các lỗi khác | `500 Internal Server Error` | `INTERNAL_ERROR` | Lỗi hệ thống / kết nối CSDL (không trả chi tiết lỗi hệ thống ra UI). |