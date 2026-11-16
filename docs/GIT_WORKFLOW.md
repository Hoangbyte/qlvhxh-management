# QUY ƯỚC LÀM VIỆC VỚI GIT – DỰ ÁN QLVHXH

## 1. Cấu trúc nhánh (Branch)
- `main`: Nhánh ổn định dùng để demo và nộp bài cuối mỗi Sprint. **Cấm push trực tiếp lên `main`.**
- `develop`: Nhánh tích hợp chung của cả nhóm. Mọi tính năng làm xong đều gộp (Merge) vào đây trước.
- Nhánh tính năng cá nhân: Đặt tên theo cú pháp `<loại>/<mã-WBS>-<tên-ngắn-không-dấu>`:
  - `feat/1.2.1-login-api` (Kiên)
  - `feat/1.2.2-login-ui` (Hưng)
  - `feat/1.2.3-rbac-middleware` (Hoàng)
  - `feat/1.3.2-today-api` (Minh)
  - `feat/1.4.3-my-tasks-ui` (Lâm)
  - `test/1.5.1-test-cases` (Hiếu)

## 2. Quy trình 4 bước mỗi khi làm một task mới
1. Cập nhật code mới nhất từ `develop`:
   ```bash
   git checkout develop
   git pull origin develop
   ```
2. Tạo nhánh riêng cho task của mình:
   ```bash
   git checkout -b feat/1.2.3-rbac-middleware
   ```
3. Code xong thì commit rõ ràng (ghi mã WBS ở đầu):
   ```bash
   git add .
   git commit -m "[1.2.3] Them middleware kiem tra quyen va API doi vai tro"
   git push origin feat/1.2.3-rbac-middleware
   ```
4. Lên GitHub tạo **Pull Request (PR)** từ nhánh của bạn vào `develop`, gắn tên người review (Hoàng hoặc Hải) để kiểm tra trước khi Merge.