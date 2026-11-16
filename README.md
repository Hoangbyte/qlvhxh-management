# Hệ thống Quản lý Phòng Văn hóa – Xã hội (QLVHXH)

Website hỗ trợ điều hành, quản lý văn bản đến/đi, giao việc, theo dõi tiến độ và báo cáo giao ban cho Phòng Văn hóa – Xã hội thuộc UBND (gồm 9 vai trò: Phó Chủ tịch UBND phụ trách VH–XH, Trưởng phòng, Phó Trưởng phòng và 6 Chuyên viên chuyên môn).

---

## 1. Yêu cầu môi trường trên máy cá nhân
Để chạy được dự án, máy tính cần cài đặt sẵn:
- **SQL Server** (bản 2019 trở lên) và **SQL Server Management Studio (SSMS)**.
- **Node.js** (bản LTS v18 hoặc v20 trở lên).
- **Git**.

---

## 2. Hướng dẫn cài đặt Cơ sở dữ liệu (Bắt buộc làm trước)
Mở SSMS, kết nối vào SQL Server của bạn và chạy lần lượt **4 file** trong thư mục `database/` theo đúng thứ tự số:

1. `database/01_schema.sql` — Tạo CSDL `QLVHXH` và 30 bảng dữ liệu.
2. `database/02_programmability.sql` — Tạo các hàm phân quyền (`fn_has_permission`), view tính hạn và Stored Procedure.
3. `database/03_seed_data.sql` — Nạp danh mục 6 lĩnh vực, 9 vai trò, 25 chức năng và dữ liệu mẫu để demo.
4. `database/04_demo_queries_and_tests.sql` — *(Tùy chọn)* Chạy kiểm tra 25 ca test CSDL để xác nhận mọi thứ hoạt động đúng (`PASS`).

### Danh sách 9 tài khoản mẫu (Mật khẩu chung: `Demo@123`)
| STT | Username | Họ và tên | Vai trò mặc định | Ghi chú |
| :---: | :--- | :--- | :--- | :--- |
| 1 | `pct.vhxh` | Nguyễn Văn An | Phó Chủ tịch UBND phụ trách VH–XH | Lãnh đạo cấp 1 |
| 2 | `tp.vhxh` | Trần Thị Bình | Trưởng phòng VH–XH | Lãnh đạo cấp 2 |
| 3 | `ptp.vhxh` | Lê Văn Cường | Phó Trưởng phòng VH–XH | Đang được TP ủy quyền ký duyệt |
| 4 | `cv.noivu` | Phạm Thị Dung | Chuyên viên Nội vụ | Đầu mối vào sổ & phát hành VB |
| 5 | `cv.yte` | Hoàng Minh Đức | Chuyên viên Y tế | Lĩnh vực Y tế |
| 6 | `cv.giaoduc` | Vũ Thu Hà | Chuyên viên Giáo dục | Lĩnh vực Giáo dục |
| 7 | `cv.vhxh` | Đỗ Quang Hùng | Chuyên viên Văn hóa – Xã hội | Kiêm nhiệm thêm vai trò `CV_DTTG` |
| 8 | `cv.khcn` | Bùi Ngọc Lan | Chuyên viên Khoa học & Công nghệ | Lĩnh vực KH&CN |
| 9 | `cv.dttg` | Ngô Đức Minh | Chuyên viên Dân tộc – Tôn giáo | Lĩnh vực Dân tộc – Tôn giáo |

---

## 3. Hướng dẫn cấu hình & chạy ứng dụng

### Bước 1: Clone dự án và tạo file cấu hình
```bash
git clone <link-repo-cua-nhom>
cd qlvhxh-management
cp .env.example .env
```
Mở file `.env` vừa tạo, sửa lại `DB_USER` và `DB_PASSWORD` khớp với tài khoản SQL Server trên máy bạn.

### Bước 2: Chạy Backend
```bash
cd backend
npm install
npm run dev
# Server chạy tại: http://localhost:8080
```

### Bước 3: Chạy Frontend
Mở một cửa sổ Terminal mới:
```bash
cd frontend
npm install
npm run dev
# Giao diện chạy tại: http://localhost:5173
```

---

## 4. Tài liệu tham chiếu cho nhóm phát triển
- Quy ước chia nhánh Git: xem `docs/GIT_WORKFLOW.md`
- Quy ước chuẩn Request/Response & mã lỗi API: xem `docs/API_CONVENTION.md`