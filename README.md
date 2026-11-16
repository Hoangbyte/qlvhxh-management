# Hệ thống Quản lý Phòng Văn hóa – Xã hội (QLVHXH)

Website hỗ trợ điều hành, quản lý văn bản đến/đi, giao việc, theo dõi tiến độ và báo cáo giao ban cho Phòng Văn hóa – Xã hội thuộc UBND.

## 1. Yêu cầu môi trường

- Windows PowerShell, Git và SQL Server 2019 trở lên (dùng SQL Server phát triển).
- Node.js **20.19.0 trở lên** (Vite 7 yêu cầu Node.js 20.19+ hoặc 22.12+).
- SQL Server Management Studio (SSMS) để thiết lập cơ sở dữ liệu.

## 2. Lấy mã nguồn

Chạy các lệnh sau trong PowerShell:

```powershell
git clone https://github.com/Hoangbyte/qlvhxh-management.git
Set-Location .\qlvhxh-management
Copy-Item .env.example .env
notepad .env
```

Backend đọc `.env` ở thư mục gốc, gồm `PORT`, `CORS_ORIGIN`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_ENCRYPT` và `DB_TRUST_SERVER_CERTIFICATE`. Sửa `DB_USER` và `DB_PASSWORD` theo tài khoản SQL Server phát triển của bạn; cập nhật các biến khác nếu cấu hình khác mặc định. Không commit file `.env`.

## 3. Thiết lập cơ sở dữ liệu

Trong SSMS, kết nối tới SQL Server phát triển rồi mở và thực thi lần lượt:

1. `database/01_schema.sql` — tạo CSDL `QLVHXH` nếu chưa có và tạo lại các bảng.
2. `database/02_programmability.sql` — tạo các thành phần programmability của CSDL.
3. `database/03_seed_data.sql` — nạp dữ liệu khởi tạo và dữ liệu mẫu.

**Lưu ý:** `01_schema.sql` xóa các bảng cũ trong `QLVHXH` trước khi tạo lại. Việc này làm mất dữ liệu đang có trong các bảng đó; chỉ chạy trên CSDL phát triển sau khi đã xác nhận dữ liệu có thể bị xóa.

Sau khi chạy ba script trên, có thể chạy `database/04_demo_queries_and_tests.sql` riêng để kiểm tra các truy vấn và ca kiểm thử. Không chạy script 04 thay cho các bước tạo schema, programmability và seed.

## 4. Cài đặt và chạy ứng dụng

Hai lockfile được lưu trong `backend/` và `frontend/`; cài dependency bằng `npm ci`.
Mở hai cửa sổ PowerShell tại thư mục gốc của repository.

Backend:

```powershell
Set-Location .\backend
npm ci
npm run dev
```

Server chạy tại `http://localhost:8080`. `.env` được đọc từ thư mục gốc repository kể cả khi chạy lệnh trong `backend/`.

Frontend, trong cửa sổ thứ hai:

```powershell
Set-Location .\frontend
npm ci
npm run dev
```

Mở `http://localhost:5173`. Trang tự kiểm tra API khi mở; nút **Kiểm tra kết nối** chạy lại phép kiểm tra. Mặc định frontend gọi `http://localhost:8080`; nếu cần đổi địa chỉ, đặt `VITE_API_BASE_URL` trong `frontend/.env.local` rồi khởi động lại Vite.

Kiểm tra API trực tiếp trong PowerShell:

```powershell
curl.exe -i http://localhost:8080/api/health
```

HTTP 200 xác nhận backend truy vấn được SQL Server. Nếu SQL Server không kết nối hoặc truy vấn thất bại, API trả HTTP 503; response không chứa thông tin kết nối hoặc stack trace.

## 5. Tài liệu tham chiếu

- Quy ước chia nhánh Git: `docs/GIT_WORKFLOW.md`.
- Quy ước Request/Response và mã lỗi API: `docs/API_CONVENTION.md`.
