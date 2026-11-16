/* =====================================================================
   File   : 03_seed_data.sql – Dữ liệu danh mục + dữ liệu giả lập để demo
   - 9 tài khoản mẫu ứng với 9 vai trò. Mật khẩu demo: Demo@123
     (CSDL chỉ lưu chuỗi băm bcrypt, không lưu mật khẩu gốc).
   - Ngày tháng tính TƯƠNG ĐỐI theo ngày chạy script (hôm nay ± n ngày) để màn hình
     Hôm nay lúc nào cũng có việc quá hạn / sắp hạn khi demo.
   - Chỉ chạy NGAY SAU 01_schema.sql + 02_programmability.sql (bảng phải rỗng).
   ===================================================================== */
USE QLVHXH;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM dbo.users)
    THROW 50000, N'CSDL đã có dữ liệu. Hãy chạy lại 01_schema.sql và 02_programmability.sql trước khi nạp dữ liệu mẫu.', 1;

BEGIN TRAN;

DECLARE @now   DATETIME2(0) = SYSDATETIME();
DECLARE @today DATE         = CAST(@now AS DATE);
DECLARE @t0    DATETIME2(0) = CAST(@today AS DATETIME2(0));   -- 00:00 hôm nay
DECLARE @y     SMALLINT     = YEAR(@today);
DECLARE @pwd   VARCHAR(255) = '$2b$10$FOfZy4YtMG3wtXHmwHbs7usVLIjWrm6wD6DB1XgCrn/eKUznPQGH2';  -- bcrypt('Demo@123')

/* ---------- 1. Lĩnh vực, vai trò ---------- */
SET IDENTITY_INSERT dbo.fields ON;
INSERT INTO dbo.fields (field_id, code, name) VALUES
 (1, 'NV',   N'Nội vụ'),
 (2, 'YT',   N'Y tế'),
 (3, 'GD',   N'Giáo dục'),
 (4, 'VHXH', N'Văn hóa – Xã hội'),
 (5, 'KHCN', N'Khoa học và Công nghệ'),
 (6, 'DTTG', N'Dân tộc – Tôn giáo');
SET IDENTITY_INSERT dbo.fields OFF;

SET IDENTITY_INSERT dbo.roles ON;
INSERT INTO dbo.roles (role_id, code, name, role_level, rank_no, field_id) VALUES
 (1, 'PCT',     N'Phó Chủ tịch UBND phụ trách VH – XH', 'LEADER', 1, NULL),
 (2, 'TP',      N'Trưởng phòng VH – XH',                'LEADER', 2, NULL),
 (3, 'PTP',     N'Phó Trưởng phòng VH – XH',            'LEADER', 3, NULL),
 (4, 'CV_NV',   N'Chuyên viên Nội vụ',                  'STAFF',  4, 1),
 (5, 'CV_YT',   N'Chuyên viên Y tế',                    'STAFF',  4, 2),
 (6, 'CV_GD',   N'Chuyên viên Giáo dục',                'STAFF',  4, 3),
 (7, 'CV_VHXH', N'Chuyên viên Văn hóa – Xã hội',        'STAFF',  4, 4),
 (8, 'CV_KHCN', N'Chuyên viên Khoa học & Công nghệ',    'STAFF',  4, 5),
 (9, 'CV_DTTG', N'Chuyên viên Dân tộc – Tôn giáo',      'STAFF',  4, 6);
SET IDENTITY_INSERT dbo.roles OFF;

/* ---------- 2. Danh mục 25 chức năng (đúng thứ tự ma trận) ---------- */
SET IDENTITY_INSERT dbo.app_functions ON;
INSERT INTO dbo.app_functions (function_id, code, name, group_code, group_name, sort_no) VALUES
 ( 1, 'F01_LOGIN',             N'Đăng nhập tài khoản',              'I',   N'Đăng nhập & vai trò', 1),
 ( 2, 'F02_DEMO_ROLE_PICKER',  N'Chọn nhanh 9 vai trò (demo)',      'I',   N'Đăng nhập & vai trò', 2),
 ( 3, 'F03_SWITCH_ROLE',       N'Đổi vai trò tài khoản',            'I',   N'Đăng nhập & vai trò', 3),
 ( 4, 'F04_DASHBOARD_TODAY',   N'Dashboard Hôm nay',                'II',  N'Hôm nay & công việc cá nhân', 4),
 ( 5, 'F05_NOTIFICATIONS',     N'Thông báo hệ thống',               'II',  N'Hôm nay & công việc cá nhân', 5),
 ( 6, 'F06_MY_TASKS',          N'Việc của tôi',                     'II',  N'Hôm nay & công việc cá nhân', 6),
 ( 7, 'F07_PENDING_HANDLING',  N'Hồ sơ chờ xử lý',                  'II',  N'Hôm nay & công việc cá nhân', 7),
 ( 8, 'F08_PENDING_APPROVAL',  N'Hồ sơ chờ ký / duyệt',             'II',  N'Hôm nay & công việc cá nhân', 8),
 ( 9, 'F09_INCOMING_REGISTER', N'Văn bản đến: vào sổ',              'III', N'Văn bản & hồ sơ', 9),
 (10, 'F10_DOCUMENT_SEARCH',   N'Sổ tra cứu văn bản',               'III', N'Văn bản & hồ sơ', 10),
 (11, 'F11_CONFIDENTIAL_FILE', N'Xem & tải tệp văn bản mật',        'III', N'Văn bản & hồ sơ', 11),
 (12, 'F12_DIRECT_DOCUMENT',   N'Chỉ đạo / chuyển văn bản',         'III', N'Văn bản & hồ sơ', 12),
 (13, 'F13_DRAFT_CREATE',      N'Soạn dự thảo văn bản đi',          'III', N'Văn bản & hồ sơ', 13),
 (14, 'F14_DRAFT_SUBMIT',      N'Trình ký dự thảo',                 'III', N'Văn bản & hồ sơ', 14),
 (15, 'F15_DRAFT_APPROVE',     N'Phê duyệt / trả lại dự thảo',      'III', N'Văn bản & hồ sơ', 15),
 (16, 'F16_DOCUMENT_ISSUE',    N'Phát hành văn bản đi',             'III', N'Văn bản & hồ sơ', 16),
 (17, 'F17_TASK_ASSIGN',       N'Giao việc / phân công',            'IV',  N'Điều hành & báo cáo', 17),
 (18, 'F18_EXTENSION_REQUEST', N'Đề xuất xin gia hạn',              'IV',  N'Điều hành & báo cáo', 18),
 (19, 'F19_EXTENSION_DECIDE',  N'Phê duyệt / từ chối gia hạn',      'IV',  N'Điều hành & báo cáo', 19),
 (20, 'F20_PROGRESS_TRACKING', N'Theo dõi tiến độ toàn phòng',      'IV',  N'Điều hành & báo cáo', 20),
 (21, 'F21_BRIEFING_REPORT',   N'Tổng hợp & in báo cáo giao ban',   'IV',  N'Điều hành & báo cáo', 21),
 (22, 'F22_MEETING',           N'Quản lý lịch họp lãnh đạo',        'IV',  N'Điều hành & báo cáo', 22),
 (23, 'F23_QUICK_ASK',         N'Ô Hỏi tình hình (tra cứu nhanh)',  'IV',  N'Điều hành & báo cáo', 23),
 (24, 'F24_DELEGATION_TOGGLE', N'Bật / tắt ủy quyền ký duyệt',      'V',   N'Hệ thống & bảo mật', 24),
 (25, 'F25_AUDIT_LOG',         N'Xem nhật ký thao tác',             'V',   N'Hệ thống & bảo mật', 25);
SET IDENTITY_INSERT dbo.app_functions OFF;

/* ---------- 3. Ma trận quyền (chép từ file Ma-trận-vai-trò-chức-năng.docx) ----------
   role_group: ALL = 9 vai trò | LEAD = PCT, TP, PTP | CV = 6 chuyên viên | CV_NV = riêng CV Nội vụ
               hoặc mã vai trò cụ thể (PCT, TP, PTP)                                           */
DECLARE @m TABLE (fcode VARCHAR(40), rgroup VARCHAR(10), action CHAR(1), scope VARCHAR(10), deleg BIT, note NVARCHAR(300));
INSERT INTO @m VALUES
 ('F01_LOGIN',             'ALL',   'X', 'ALL',      0, N'Mật khẩu mã hóa, có phiên, báo lỗi khi nhập sai'),
 ('F02_DEMO_ROLE_PICKER',  'ALL',   'X', 'ALL',      0, N'Chỉ bật khi system_settings.DEMO_MODE = 1'),
 ('F03_SWITCH_ROLE',       'ALL',   'C', 'GRANTED',  0, N'Ký hiệu U: chỉ đổi trong danh sách user_roles; CV không đổi lên lãnh đạo'),
 ('F04_DASHBOARD_TODAY',   'LEAD',  'X', 'ALL',      0, N'Lãnh đạo xem số liệu cả phòng'),
 ('F04_DASHBOARD_TODAY',   'CV',    'X', 'OWN',      0, N'Chuyên viên chỉ xem số việc của mình'),
 ('F05_NOTIFICATIONS',     'ALL',   'X', 'OWN',      0, NULL),
 ('F06_MY_TASKS',          'ALL',   'X', 'OWN',      0, N'Việc giao đích danh'),
 ('F06_MY_TASKS',          'ALL',   'C', 'OWN',      0, N'Cập nhật Đang làm / Hoàn thành'),
 ('F07_PENDING_HANDLING',  'ALL',   'X', 'OWN',      0, NULL),
 ('F07_PENDING_HANDLING',  'ALL',   'C', 'OWN',      0, NULL),
 ('F08_PENDING_APPROVAL',  'PCT',   'X', 'ASSIGNED', 0, NULL),
 ('F08_PENDING_APPROVAL',  'TP',    'X', 'ASSIGNED', 0, NULL),
 ('F08_PENDING_APPROVAL',  'PTP',   'X', 'ASSIGNED', 1, N'PTP chỉ thấy khi có ủy quyền'),
 ('F09_INCOMING_REGISTER', 'PCT',   'X', 'ALL',      0, NULL),
 ('F09_INCOMING_REGISTER', 'TP',    'X', 'ALL',      0, NULL),
 ('F09_INCOMING_REGISTER', 'TP',    'C', 'ALL',      0, NULL),
 ('F09_INCOMING_REGISTER', 'PTP',   'X', 'ALL',      0, NULL),
 ('F09_INCOMING_REGISTER', 'CV_NV', 'S', 'ALL',      0, N'CV Nội vụ là đầu mối vào sổ'),
 ('F09_INCOMING_REGISTER', 'CV_NV', 'C', 'ALL',      0, NULL),
 ('F10_DOCUMENT_SEARCH',   'LEAD',  'X', 'ALL',      0, NULL),
 ('F10_DOCUMENT_SEARCH',   'CV',    'X', 'FIELD',    0, N'CV tra cứu theo lĩnh vực mình'),
 ('F11_CONFIDENTIAL_FILE', 'PCT',   'X', 'ALL',      0, NULL),
 ('F11_CONFIDENTIAL_FILE', 'TP',    'X', 'ALL',      0, NULL),
 ('F11_CONFIDENTIAL_FILE', 'PTP',   'X', 'ALL',      1, N'Cần ủy quyền can_view_confidential'),
 ('F11_CONFIDENTIAL_FILE', 'CV',    'X', 'ASSIGNED', 0, N'Chỉ CV được giao trực tiếp'),
 ('F12_DIRECT_DOCUMENT',   'PCT',   'G', 'ALL',      0, N'PCT chỉ đạo xuống phòng'),
 ('F12_DIRECT_DOCUMENT',   'TP',    'G', 'ALL',      0, N'TP giao chuyên viên'),
 ('F12_DIRECT_DOCUMENT',   'PTP',   'G', 'FIELD',    0, N'PTP giao trong mảng phụ trách (leader_fields)'),
 ('F13_DRAFT_CREATE',      'TP',    'S', 'ALL',      0, NULL),
 ('F13_DRAFT_CREATE',      'PTP',   'S', 'FIELD',    0, NULL),
 ('F13_DRAFT_CREATE',      'CV',    'S', 'FIELD',    0, N'Soạn theo lĩnh vực'),
 ('F14_DRAFT_SUBMIT',      'TP',    'S', 'OWN',      0, NULL),
 ('F14_DRAFT_SUBMIT',      'PTP',   'S', 'OWN',      0, NULL),
 ('F14_DRAFT_SUBMIT',      'CV',    'S', 'OWN',      0, NULL),
 ('F15_DRAFT_APPROVE',     'PCT',   'D', 'ASSIGNED', 0, NULL),
 ('F15_DRAFT_APPROVE',     'TP',    'D', 'ASSIGNED', 0, NULL),
 ('F15_DRAFT_APPROVE',     'PTP',   'D', 'ASSIGNED', 1, N'Duyệt thay khi có ủy quyền'),
 ('F16_DOCUMENT_ISSUE',    'PCT',   'D', 'ALL',      0, NULL),
 ('F16_DOCUMENT_ISSUE',    'TP',    'D', 'ALL',      0, NULL),
 ('F16_DOCUMENT_ISSUE',    'PTP',   'D', 'ALL',      1, NULL),
 ('F16_DOCUMENT_ISSUE',    'CV_NV', 'C', 'ALL',      0, N'CV Nội vụ bấm phát hành để cấp số'),
 ('F17_TASK_ASSIGN',       'PCT',   'G', 'ALL',      0, NULL),
 ('F17_TASK_ASSIGN',       'TP',    'G', 'ALL',      0, NULL),
 ('F17_TASK_ASSIGN',       'PTP',   'G', 'FIELD',    0, NULL),
 ('F18_EXTENSION_REQUEST', 'CV',    'S', 'OWN',      0, N'Bắt buộc nhập lý do'),
 ('F19_EXTENSION_DECIDE',  'PCT',   'D', 'ASSIGNED', 0, N'Nhiệm vụ do PCT giao'),
 ('F19_EXTENSION_DECIDE',  'TP',    'D', 'ALL',      0, NULL),
 ('F19_EXTENSION_DECIDE',  'PTP',   'D', 'ALL',      1, NULL),
 ('F20_PROGRESS_TRACKING', 'LEAD',  'X', 'ALL',      0, NULL),
 ('F20_PROGRESS_TRACKING', 'CV',    'X', 'OWN',      0, N'Chỉ tiến độ cá nhân'),
 ('F21_BRIEFING_REPORT',   'PCT',   'X', 'ALL',      0, NULL),
 ('F21_BRIEFING_REPORT',   'TP',    'S', 'ALL',      0, NULL),
 ('F21_BRIEFING_REPORT',   'TP',    'C', 'ALL',      0, NULL),
 ('F21_BRIEFING_REPORT',   'PTP',   'X', 'ALL',      0, NULL),
 ('F22_MEETING',           'PCT',   'X', 'ALL',      0, NULL),
 ('F22_MEETING',           'PCT',   'G', 'ALL',      0, NULL),
 ('F22_MEETING',           'TP',    'S', 'ALL',      0, NULL),
 ('F22_MEETING',           'TP',    'C', 'ALL',      0, NULL),
 ('F22_MEETING',           'PTP',   'S', 'ALL',      0, NULL),
 ('F22_MEETING',           'PTP',   'C', 'ALL',      0, NULL),
 ('F22_MEETING',           'CV',    'X', 'RELATED',  0, N'CV xem cuộc họp mình tham gia'),
 ('F23_QUICK_ASK',         'LEAD',  'X', 'ALL',      0, NULL),
 ('F23_QUICK_ASK',         'CV',    'X', 'OWN',      0, NULL),
 ('F24_DELEGATION_TOGGLE', 'PCT',   'X', 'ALL',      0, NULL),
 ('F24_DELEGATION_TOGGLE', 'TP',    'S', 'OWN',      0, NULL),
 ('F24_DELEGATION_TOGGLE', 'TP',    'C', 'OWN',      0, NULL),
 ('F24_DELEGATION_TOGGLE', 'PTP',   'X', 'OWN',      0, NULL),
 ('F25_AUDIT_LOG',         'PCT',   'X', 'ALL',      0, NULL),
 ('F25_AUDIT_LOG',         'TP',    'X', 'ALL',      0, NULL);

INSERT INTO dbo.role_permissions (role_id, function_id, action, scope, requires_delegation, note)
SELECT r.role_id, f.function_id, m.action, m.scope, m.deleg, m.note
FROM @m m
JOIN dbo.app_functions f ON f.code = m.fcode
JOIN dbo.roles r ON
       m.rgroup = 'ALL'
    OR (m.rgroup = 'LEAD' AND r.role_level = 'LEADER')
    OR (m.rgroup = 'CV'   AND r.role_level = 'STAFF')
    OR (m.rgroup = r.code);

/* ---------- 4. 9 tài khoản mẫu ---------- */
SET IDENTITY_INSERT dbo.users ON;
INSERT INTO dbo.users (user_id, username, password_hash, full_name, position_title, email, phone, is_demo_account) VALUES
 (1, 'pct.vhxh',   @pwd, N'Nguyễn Văn An',    N'Phó Chủ tịch UBND phụ trách VH – XH', 'pct.vhxh@demo.local',   '0901000001', 1),
 (2, 'tp.vhxh',    @pwd, N'Trần Thị Bình',    N'Trưởng phòng Văn hóa – Xã hội',       'tp.vhxh@demo.local',    '0901000002', 1),
 (3, 'ptp.vhxh',   @pwd, N'Lê Văn Cường',     N'Phó Trưởng phòng Văn hóa – Xã hội',   'ptp.vhxh@demo.local',   '0901000003', 1),
 (4, 'cv.noivu',   @pwd, N'Phạm Thị Dung',    N'Chuyên viên Nội vụ',                  'cv.noivu@demo.local',   '0901000004', 1),
 (5, 'cv.yte',     @pwd, N'Hoàng Minh Đức',   N'Chuyên viên Y tế',                    'cv.yte@demo.local',     '0901000005', 1),
 (6, 'cv.giaoduc', @pwd, N'Vũ Thu Hà',        N'Chuyên viên Giáo dục',                'cv.giaoduc@demo.local', '0901000006', 1),
 (7, 'cv.vhxh',    @pwd, N'Đỗ Quang Hùng',    N'Chuyên viên Văn hóa – Xã hội',        'cv.vhxh@demo.local',    '0901000007', 1),
 (8, 'cv.khcn',    @pwd, N'Bùi Ngọc Lan',     N'Chuyên viên Khoa học & Công nghệ',    'cv.khcn@demo.local',    '0901000008', 1),
 (9, 'cv.dttg',    @pwd, N'Ngô Đức Minh',     N'Chuyên viên Dân tộc – Tôn giáo',      'cv.dttg@demo.local',    '0901000009', 1);
SET IDENTITY_INSERT dbo.users OFF;

INSERT INTO dbo.user_roles (user_id, role_id, is_default, granted_by) VALUES
 (1, 1, 1, NULL), (2, 2, 1, NULL), (3, 3, 1, 2), (4, 4, 1, 2), (5, 5, 1, 2),
 (6, 6, 1, 2), (7, 7, 1, 2), (8, 8, 1, 2), (9, 9, 1, 2),
 (7, 9, 0, 2);   -- CV VHXH kiêm nhiệm thêm vai trò CV Dân tộc – Tôn giáo -> demo "đổi vai trò"

-- Phó Trưởng phòng phụ trách mảng Y tế, Giáo dục, KHCN
INSERT INTO dbo.leader_fields (user_id, field_id) VALUES (3, 2), (3, 3), (3, 5);

-- Trưởng phòng đang bật ủy quyền ký duyệt + duyệt gia hạn cho Phó Trưởng phòng (không gồm văn bản mật)
SET IDENTITY_INSERT dbo.delegations ON;
INSERT INTO dbo.delegations (delegation_id, from_user_id, to_user_id, can_sign, can_approve_extension,
                             can_view_confidential, valid_from, valid_to, is_active, reason, created_at)
VALUES (1, 2, 3, 1, 1, 0, DATEADD(DAY, -5, @t0), DATEADD(DAY, 30, @t0), 1,
        N'Trưởng phòng đi học lớp bồi dưỡng, ủy quyền xử lý công việc', DATEADD(DAY, -5, @t0));
SET IDENTITY_INSERT dbo.delegations OFF;

/* ---------- 5. Lịch làm việc, tham số ---------- */
DECLARE @yy INT = @y - 1;
WHILE @yy <= @y + 1
BEGIN
    EXEC dbo.sp_generate_calendar @yy;
    -- Ngày lễ dương lịch cố định. Tết Nguyên đán, Giỗ Tổ, nghỉ bù/làm bù: quản trị viên nhập
    -- theo thông báo chính thức hằng năm (hệ thống không tự suy đoán).
    UPDATE dbo.calendar_days SET is_working_day = 0, note = N'Tết Dương lịch'      WHERE cal_date = DATEFROMPARTS(@yy, 1, 1);
    UPDATE dbo.calendar_days SET is_working_day = 0, note = N'Ngày Giải phóng miền Nam' WHERE cal_date = DATEFROMPARTS(@yy, 4, 30);
    UPDATE dbo.calendar_days SET is_working_day = 0, note = N'Quốc tế Lao động'    WHERE cal_date = DATEFROMPARTS(@yy, 5, 1);
    UPDATE dbo.calendar_days SET is_working_day = 0, note = N'Quốc khánh'          WHERE cal_date = DATEFROMPARTS(@yy, 9, 2);
    SET @yy = @yy + 1;
END;

INSERT INTO dbo.system_settings (setting_key, setting_value, description) VALUES
 ('DUE_SOON_WORKING_DAYS', N'2',   N'Còn <= N ngày làm việc thì tính là sắp hạn'),
 ('SESSION_TIMEOUT_MIN',   N'60',  N'Phiên đăng nhập hết hạn sau N phút không thao tác'),
 ('MAX_LOGIN_FAILED',      N'5',   N'Nhập sai N lần thì khóa tạm'),
 ('LOCK_MINUTES',          N'15',  N'Thời gian khóa tạm (phút)'),
 ('MAX_FILE_SIZE_MB',      N'20',  N'Dung lượng tối đa một tệp đính kèm'),
 ('ALLOWED_FILE_EXT',      N'pdf,doc,docx,xls,xlsx,jpg,jpeg,png,zip', N'Đuôi tệp được phép tải lên'),
 ('DEMO_MODE',             N'1',   N'1 = bật thanh chọn nhanh 9 vai trò (chỉ khi trình diễn)'),
 ('DEPARTMENT_SYMBOL',     N'VHXH',N'Ký hiệu đơn vị ghép vào số ký hiệu văn bản đi');

/* ---------- 6. Danh mục văn bản ---------- */
SET IDENTITY_INSERT dbo.organizations ON;
INSERT INTO dbo.organizations (org_id, name, short_name, org_type) VALUES
 (1,  N'Ủy ban nhân dân tỉnh',                   N'UBND tỉnh',  'EXTERNAL'),
 (2,  N'Sở Y tế',                                N'SYT',        'EXTERNAL'),
 (3,  N'Sở Giáo dục và Đào tạo',                 N'SGDĐT',      'EXTERNAL'),
 (4,  N'Sở Văn hóa, Thể thao và Du lịch',        N'SVHTTDL',    'EXTERNAL'),
 (5,  N'Sở Khoa học và Công nghệ',               N'SKHCN',      'EXTERNAL'),
 (6,  N'Sở Dân tộc và Tôn giáo',                 N'SDTTG',      'EXTERNAL'),
 (7,  N'Sở Nội vụ',                              N'SNV',        'EXTERNAL'),
 (8,  N'Trạm Y tế xã',                           N'TYT',        'EXTERNAL'),
 (9,  N'Trường THCS trên địa bàn xã',            N'THCS',       'EXTERNAL'),
 (10, N'Văn phòng HĐND và UBND xã',              N'VP',         'INTERNAL');
SET IDENTITY_INSERT dbo.organizations OFF;

SET IDENTITY_INSERT dbo.document_types ON;
INSERT INTO dbo.document_types (doc_type_id, code, name, abbreviation) VALUES
 (1, 'CV',  N'Công văn',   N'UBND'),
 (2, 'QD',  N'Quyết định', N'QĐ'),
 (3, 'TB',  N'Thông báo',  N'TB'),
 (4, 'BC',  N'Báo cáo',    N'BC'),
 (5, 'KH',  N'Kế hoạch',   N'KH'),
 (6, 'TTR', N'Tờ trình',   N'TTr'),
 (7, 'GM',  N'Giấy mời',   N'GM');
SET IDENTITY_INSERT dbo.document_types OFF;

SET IDENTITY_INSERT dbo.document_books ON;
INSERT INTO dbo.document_books (book_id, code, name, direction, book_year, last_number) VALUES
 (1, 'SDEN', CONCAT(N'Sổ đăng ký văn bản đến năm ', @y), 'IN',  @y, 7),
 (2, 'SDI',  CONCAT(N'Sổ đăng ký văn bản đi năm ', @y),  'OUT', @y, 1);
SET IDENTITY_INSERT dbo.document_books OFF;

/* ---------- 7. Văn bản đến (1–8) và văn bản đi (9–14) ---------- */
SET IDENTITY_INSERT dbo.documents ON;
INSERT INTO dbo.documents (document_id, direction, book_id, book_number, symbol, doc_type_id, summary, field_id,
            issuing_org_id, issued_date, received_at, signer_name, signed_by, security_level, urgency, status,
            due_date, current_version_no, issued_at, issued_by, created_by, created_at) VALUES
 (1, 'IN', 1, 3, N'1520/SYT-NVY', 1, N'V/v tăng cường công tác phòng, chống bệnh sốt xuất huyết', 2,
     2, DATEADD(DAY, -9, @today), DATEADD(HOUR, 9, DATEADD(DAY, -8, @t0)), N'Phó Giám đốc Sở', NULL, 'NORMAL', 'NORMAL', 'PROCESSING',
     DATEADD(DAY, 2, @today), 0, NULL, NULL, 4, DATEADD(HOUR, 9, DATEADD(DAY, -8, @t0))),
 (2, 'IN', 1, 4, N'845/SGDĐT-GDTrH', 5, N'Kế hoạch tổ chức kỳ thi chọn học sinh giỏi năm học 2026–2027', 3,
     3, DATEADD(DAY, -6, @today), DATEADD(HOUR, 10, DATEADD(DAY, -5, @t0)), N'Giám đốc Sở', NULL, 'NORMAL', 'NORMAL', 'WAIT_DIRECTION',
     DATEADD(DAY, 7, @today), 0, NULL, NULL, 4, DATEADD(HOUR, 10, DATEADD(DAY, -5, @t0))),
 (3, 'IN', 1, 6, N'312/UBND-KGVX', 1, N'V/v tổ chức Ngày hội Đại đoàn kết toàn dân tộc năm 2026', 4,
     1, DATEADD(DAY, -4, @today), DATEADD(HOUR, 8, DATEADD(DAY, -3, @t0)), N'Phó Chủ tịch UBND tỉnh', NULL, 'NORMAL', 'URGENT', 'WAIT_DIRECTION',
     DATEADD(DAY, 3, @today), 0, NULL, NULL, 4, DATEADD(HOUR, 8, DATEADD(DAY, -3, @t0))),
 (4, 'IN', 1, 7, N'77/TB-SKHCN', 3, N'Thông báo đăng ký đề tài khoa học cấp cơ sở năm 2027', 5,
     5, DATEADD(DAY, -3, @today), DATEADD(HOUR, 14, DATEADD(DAY, -2, @t0)), N'Phó Giám đốc Sở', NULL, 'NORMAL', 'NORMAL', 'REGISTERED',
     DATEADD(DAY, 10, @today), 0, NULL, NULL, 4, DATEADD(HOUR, 14, DATEADD(DAY, -2, @t0))),
 (5, 'IN', 1, 1, N'205/SDTTG-TG', 1, N'V/v báo cáo tình hình hoạt động tín ngưỡng, tôn giáo quý III', 6,
     6, DATEADD(DAY, -20, @today), DATEADD(HOUR, 9, DATEADD(DAY, -19, @t0)), N'Giám đốc Sở', NULL, 'NORMAL', 'NORMAL', 'COMPLETED',
     DATEADD(DAY, -15, @today), 0, NULL, NULL, 4, DATEADD(HOUR, 9, DATEADD(DAY, -19, @t0))),
 (6, 'IN', 1, 5, N'58/SNV-CCVC', 1, N'V/v rà soát, bổ sung quy hoạch cán bộ giai đoạn 2026–2031', 1,
     7, DATEADD(DAY, -5, @today), DATEADD(HOUR, 15, DATEADD(DAY, -4, @t0)), N'Giám đốc Sở', NULL, 'CONFIDENTIAL', 'NORMAL', 'PROCESSING',
     DATEADD(DAY, 3, @today), 0, NULL, NULL, 4, DATEADD(HOUR, 15, DATEADD(DAY, -4, @t0))),
 (7, 'IN', NULL, NULL, N'1602/GM-SYT', 7, N'Giấy mời dự hội nghị triển khai tiêm chủng mở rộng', 2,
     2, DATEADD(DAY, -1, @today), DATEADD(MINUTE, -30, @now), N'Phó Giám đốc Sở', NULL, 'NORMAL', 'URGENT', 'RECEIVED',
     NULL, 0, NULL, NULL, 4, DATEADD(MINUTE, -30, @now)),
 (8, 'IN', 1, 2, N'901/SGDĐT-KHTC', 1, N'V/v báo cáo số liệu đầu năm học 2026–2027', 3,
     3, DATEADD(DAY, -15, @today), DATEADD(HOUR, 9, DATEADD(DAY, -14, @t0)), N'Phó Giám đốc Sở', NULL, 'NORMAL', 'NORMAL', 'PROCESSING',
     DATEADD(DAY, -2, @today), 0, NULL, NULL, 4, DATEADD(HOUR, 9, DATEADD(DAY, -14, @t0))),
 (9,  'OUT', NULL, NULL, NULL, 5, N'Kế hoạch tuyên truyền phòng, chống sốt xuất huyết trên địa bàn xã', 2,
      NULL, NULL, NULL, NULL, NULL, 'NORMAL', 'NORMAL', 'DRAFT',
      NULL, 1, NULL, NULL, 5, DATEADD(HOUR, 10, DATEADD(DAY, -1, @t0))),
 (10, 'OUT', NULL, NULL, NULL, 4, N'Báo cáo kết quả chuẩn bị kỳ thi chọn học sinh giỏi', 3,
      NULL, NULL, NULL, NULL, NULL, 'NORMAL', 'NORMAL', 'PENDING_APPROVAL',
      NULL, 1, NULL, NULL, 6, DATEADD(HOUR, 9, DATEADD(DAY, -2, @t0))),
 (11, 'OUT', NULL, NULL, NULL, 5, N'Kế hoạch tổ chức Ngày hội Đại đoàn kết toàn dân tộc tại các thôn', 4,
      NULL, NULL, NULL, NULL, NULL, 'NORMAL', 'URGENT', 'RETURNED',
      NULL, 1, NULL, NULL, 7, DATEADD(HOUR, 8, DATEADD(DAY, -2, @t0))),
 (12, 'OUT', NULL, NULL, NULL, 6, N'Tờ trình đề nghị công nhận sáng kiến cấp cơ sở năm 2026', 5,
      NULL, NULL, NULL, NULL, NULL, 'NORMAL', 'NORMAL', 'PENDING_APPROVAL',
      NULL, 1, NULL, NULL, 8, DATEADD(HOUR, 9, DATEADD(DAY, -3, @t0))),
 (13, 'OUT', NULL, NULL, NULL, 1, N'V/v cử cán bộ tham gia lớp bồi dưỡng nghiệp vụ văn thư, lưu trữ', 1,
      NULL, NULL, NULL, NULL, 3, 'NORMAL', 'NORMAL', 'APPROVED',
      NULL, 1, NULL, NULL, 4, DATEADD(HOUR, 9, DATEADD(DAY, -2, @t0))),
 (14, 'OUT', 2, 1, N'1/UBND-VHXH', 1, N'V/v báo cáo tình hình hoạt động tín ngưỡng, tôn giáo quý III năm 2026', 6,
      NULL, DATEADD(DAY, -15, @today), NULL, NULL, 2, 'NORMAL', 'NORMAL', 'ISSUED',
      NULL, 1, DATEADD(HOUR, 15, DATEADD(DAY, -15, @t0)), 4, 9, DATEADD(HOUR, 9, DATEADD(DAY, -17, @t0)));
SET IDENTITY_INSERT dbo.documents OFF;

SET IDENTITY_INSERT dbo.document_versions ON;
INSERT INTO dbo.document_versions (version_id, document_id, version_no, change_note, created_by, created_at) VALUES
 (1,  9, 1, N'Dự thảo lần 1', 5, DATEADD(HOUR, 10, DATEADD(DAY, -1, @t0))),
 (2, 10, 1, N'Dự thảo lần 1', 6, DATEADD(HOUR,  9, DATEADD(DAY, -2, @t0))),
 (3, 11, 1, N'Dự thảo lần 1', 7, DATEADD(HOUR,  8, DATEADD(DAY, -2, @t0))),
 (4, 12, 1, N'Dự thảo lần 1', 8, DATEADD(HOUR,  9, DATEADD(DAY, -3, @t0))),
 (5, 13, 1, N'Dự thảo lần 1', 4, DATEADD(HOUR,  9, DATEADD(DAY, -2, @t0))),
 (6, 14, 1, N'Dự thảo lần 1', 9, DATEADD(HOUR,  9, DATEADD(DAY, -17, @t0)));
SET IDENTITY_INSERT dbo.document_versions OFF;

INSERT INTO dbo.document_recipients (document_id, org_id, user_id, note, sent_at) VALUES
 (14, 6,    NULL, NULL,                      DATEADD(HOUR, 15, DATEADD(DAY, -15, @t0))),
 (14, 1,    NULL, N'Để báo cáo',             DATEADD(HOUR, 15, DATEADD(DAY, -15, @t0))),
 (14, NULL, NULL, N'Lưu: VT, VHXH',          NULL);

-- Luân chuyển văn bản đến
SET IDENTITY_INSERT dbo.document_handlings ON;
INSERT INTO dbo.document_handlings (handling_id, document_id, parent_handling_id, from_user_id, to_user_id,
            handling_type, instruction, due_date, status, created_at, done_at) VALUES
 ( 1, 1, NULL, 4, 2, 'DIRECTION', NULL, NULL, 'DONE', DATEADD(HOUR, 10, DATEADD(DAY, -8, @t0)), DATEADD(HOUR, 8, DATEADD(DAY, -7, @t0))),
 ( 2, 1, 1,    2, 5, 'MAIN', N'Giao CV Y tế tham mưu kế hoạch triển khai, báo cáo trước hạn.', DATEADD(DAY, 2, @today), 'PENDING', DATEADD(HOUR, 8, DATEADD(DAY, -7, @t0)), NULL),
 ( 3, 2, NULL, 4, 2, 'DIRECTION', NULL, NULL, 'PENDING', DATEADD(HOUR, 11, DATEADD(DAY, -5, @t0)), NULL),
 ( 4, 3, NULL, 4, 1, 'DIRECTION', N'Văn bản khẩn của UBND tỉnh, kính trình PCT cho ý kiến.', NULL, 'PENDING', DATEADD(HOUR, 9, DATEADD(DAY, -3, @t0)), NULL),
 ( 5, 5, NULL, 4, 2, 'DIRECTION', NULL, NULL, 'DONE', DATEADD(HOUR, 10, DATEADD(DAY, -19, @t0)), DATEADD(HOUR, 8, DATEADD(DAY, -18, @t0))),
 ( 6, 5, 5,    2, 9, 'MAIN', N'CV DTTG tổng hợp, dự thảo báo cáo.', DATEADD(DAY, -15, @today), 'DONE', DATEADD(HOUR, 8, DATEADD(DAY, -18, @t0)), DATEADD(HOUR, 15, DATEADD(DAY, -15, @t0))),
 ( 7, 6, NULL, 4, 2, 'DIRECTION', NULL, NULL, 'DONE', DATEADD(HOUR, 16, DATEADD(DAY, -4, @t0)), DATEADD(HOUR, 8, DATEADD(DAY, -3, @t0))),
 ( 8, 6, 7,    2, 4, 'MAIN', N'Văn bản MẬT – CV Nội vụ trực tiếp xử lý, không sao chụp.', DATEADD(DAY, 3, @today), 'PENDING', DATEADD(HOUR, 8, DATEADD(DAY, -3, @t0)), NULL),
 ( 9, 8, NULL, 4, 2, 'DIRECTION', NULL, NULL, 'DONE', DATEADD(HOUR, 10, DATEADD(DAY, -14, @t0)), DATEADD(HOUR, 8, DATEADD(DAY, -13, @t0))),
 (10, 8, 9,    2, 3, 'DIRECTION', N'Chuyển PTP chỉ đạo theo mảng Giáo dục.', NULL, 'DONE', DATEADD(HOUR, 8, DATEADD(DAY, -13, @t0)), DATEADD(HOUR, 14, DATEADD(DAY, -13, @t0))),
 (11, 8, 10,   3, 6, 'MAIN', N'CV Giáo dục tổng hợp số liệu từ các trường.', DATEADD(DAY, -2, @today), 'PENDING', DATEADD(HOUR, 14, DATEADD(DAY, -13, @t0)), NULL),
 (12, 1, 1,    2, 8, 'INFO', N'CV KHCN nắm thông tin để phối hợp tuyên truyền trên cổng thông tin.', NULL, 'PENDING', DATEADD(HOUR, 8, DATEADD(DAY, -7, @t0)), NULL);
SET IDENTITY_INSERT dbo.document_handlings OFF;

INSERT INTO dbo.document_access_grants (document_id, user_id, granted_by, granted_at)
VALUES (6, 4, 2, DATEADD(HOUR, 8, DATEADD(DAY, -3, @t0)));

-- Trình ký
SET IDENTITY_INSERT dbo.approval_requests ON;
INSERT INTO dbo.approval_requests (approval_id, document_id, version_id, step_no, submitted_by, submitted_at,
            approver_id, status, decided_by, decided_at, decision_note, via_delegation_id) VALUES
 (1, 10, 2, 1, 6, DATEADD(HOUR, 15, DATEADD(DAY, -1, @t0)), 2, 'PENDING',   NULL, NULL, NULL, NULL),
 (2, 11, 3, 1, 7, DATEADD(HOUR, 14, DATEADD(DAY, -2, @t0)), 2, 'RETURNED',  2, DATEADD(HOUR, 9, DATEADD(DAY, -1, @t0)),
     N'Bổ sung dự toán kinh phí và phân công cụ thể cho từng thôn.', NULL),
 (3, 12, 4, 1, 8, DATEADD(HOUR, 10, DATEADD(DAY, -3, @t0)), 2, 'FORWARDED', 2, DATEADD(HOUR, 16, DATEADD(DAY, -1, @t0)),
     N'Phòng đã thẩm định, kính trình PCT xem xét.', NULL),
 (4, 12, 4, 2, 2, DATEADD(HOUR, 16, DATEADD(DAY, -1, @t0)), 1, 'PENDING',   NULL, NULL, NULL, NULL),
 (5, 13, 5, 1, 4, DATEADD(HOUR, 10, DATEADD(DAY, -2, @t0)), 2, 'APPROVED',  3, DATEADD(HOUR, 11, DATEADD(DAY, -1, @t0)),
     N'Duyệt thay theo ủy quyền của Trưởng phòng.', 1),
 (6, 14, 6, 1, 9, DATEADD(HOUR, 10, DATEADD(DAY, -17, @t0)), 2, 'APPROVED', 2, DATEADD(HOUR, 9, DATEADD(DAY, -16, @t0)), NULL, NULL);
SET IDENTITY_INSERT dbo.approval_requests OFF;

/* ---------- 8. Lịch họp ---------- */
SET IDENTITY_INSERT dbo.meetings ON;
INSERT INTO dbo.meetings (meeting_id, title, content, location, start_at, end_at, chaired_by, created_by, status, created_at) VALUES
 (1, N'Giao ban tuần Phòng Văn hóa – Xã hội', N'Rà soát nhiệm vụ quá hạn, văn bản chờ chỉ đạo; phân công tuần tới.',
     N'Phòng họp số 2 – UBND xã', DATEADD(HOUR, 8, DATEADD(DAY, 1, @t0)), DATEADD(HOUR, 10, DATEADD(DAY, 1, @t0)), 2, 2, 'SCHEDULED', DATEADD(DAY, -2, @t0)),
 (2, N'Họp bàn tổ chức Ngày hội Đại đoàn kết toàn dân tộc', N'Thống nhất kế hoạch, kinh phí và phân công các thôn.',
     N'Phòng họp UBND xã', DATEADD(HOUR, 14, DATEADD(DAY, 3, @t0)), DATEADD(HOUR, 16, DATEADD(DAY, 3, @t0)), 1, 2, 'SCHEDULED', DATEADD(DAY, -1, @t0)),
 (3, N'Giao ban tháng Phòng Văn hóa – Xã hội', N'Đánh giá kết quả tháng trước, triển khai nhiệm vụ tháng.',
     N'Phòng họp số 2 – UBND xã', DATEADD(HOUR, 8, DATEADD(DAY, -7, @t0)), DATEADD(HOUR, 11, DATEADD(DAY, -7, @t0)), 2, 2, 'DONE', DATEADD(DAY, -10, @t0));
SET IDENTITY_INSERT dbo.meetings OFF;

INSERT INTO dbo.meeting_participants (meeting_id, user_id, participant_role, attendance) VALUES
 (1, 2, 'CHAIR', 'ACCEPTED'), (1, 3, 'MEMBER', 'ACCEPTED'), (1, 4, 'SECRETARY', 'ACCEPTED'),
 (1, 5, 'MEMBER', 'INVITED'), (1, 6, 'MEMBER', 'INVITED'), (1, 7, 'MEMBER', 'INVITED'),
 (1, 8, 'MEMBER', 'INVITED'), (1, 9, 'MEMBER', 'INVITED'),
 (2, 1, 'CHAIR', 'ACCEPTED'), (2, 2, 'MEMBER', 'ACCEPTED'), (2, 3, 'MEMBER', 'INVITED'), (2, 7, 'MEMBER', 'INVITED'),
 (3, 2, 'CHAIR', 'ATTENDED'), (3, 3, 'MEMBER', 'ATTENDED'), (3, 4, 'SECRETARY', 'ATTENDED'),
 (3, 5, 'MEMBER', 'ATTENDED'), (3, 6, 'MEMBER', 'ATTENDED'), (3, 7, 'MEMBER', 'ATTENDED'),
 (3, 8, 'MEMBER', 'ABSENT'),   (3, 9, 'MEMBER', 'ATTENDED');

/* ---------- 9. Nhiệm vụ (16 việc, đủ các trạng thái hạn) ---------- */
SET IDENTITY_INSERT dbo.tasks ON;
INSERT INTO dbo.tasks (task_id, title, description, field_id, document_id, meeting_id, parent_task_id, assigned_by, assignee_id,
            priority, start_date, due_date, original_due_date, status, progress_percent, result_note, completed_at, created_at) VALUES
 ( 1, N'Tham mưu kế hoạch phòng, chống sốt xuất huyết', N'Theo CV 1520/SYT-NVY', 2, 1, NULL, NULL, 2, 5,
      'HIGH',   DATEADD(DAY, -7, @today), DATEADD(DAY, 2, @today),  DATEADD(DAY, 2, @today),  'IN_PROGRESS', 40, NULL, NULL, DATEADD(DAY, -7, @t0)),
 ( 2, N'Báo cáo kết quả tiêm chủng mở rộng tháng', NULL, 2, NULL, NULL, NULL, 2, 5,
      'NORMAL', DATEADD(DAY, -20, @today), DATEADD(DAY, -3, @today), DATEADD(DAY, -3, @today), 'IN_PROGRESS', 70, NULL, NULL, DATEADD(DAY, -20, @t0)),
 ( 3, N'Tổng hợp số liệu đầu năm học 2026–2027', N'Theo CV 901/SGDĐT-KHTC', 3, 8, NULL, NULL, 3, 6,
      'HIGH',   DATEADD(DAY, -13, @today), DATEADD(DAY, -2, @today), DATEADD(DAY, -2, @today), 'NEW', 0, NULL, NULL, DATEADD(DAY, -13, @t0)),
 ( 4, N'Kiểm tra cơ sở vật chất các trường trước mùa mưa bão', NULL, 3, NULL, NULL, NULL, 3, 6,
      'NORMAL', DATEADD(DAY, -3, @today), DATEADD(DAY, 10, @today), DATEADD(DAY, 10, @today), 'NEW', 0, NULL, NULL, DATEADD(DAY, -3, @t0)),
 ( 5, N'Chuẩn bị nội dung Ngày hội Đại đoàn kết ở các thôn', NULL, 4, NULL, NULL, NULL, 2, 7,
      'URGENT', DATEADD(DAY, -2, @today), DATEADD(DAY, 1, @today),  DATEADD(DAY, 1, @today),  'IN_PROGRESS', 30, NULL, NULL, DATEADD(DAY, -2, @t0)),
 ( 6, N'Báo cáo công tác gia đình và phòng, chống bạo lực gia đình', NULL, 4, NULL, NULL, NULL, 2, 7,
      'NORMAL', DATEADD(DAY, -12, @today), DATEADD(DAY, -1, @today), DATEADD(DAY, -1, @today), 'DONE', 100, N'Đã gửi báo cáo', DATEADD(HOUR, 16, DATEADD(DAY, -2, @t0)), DATEADD(DAY, -12, @t0)),
 ( 7, N'Rà soát hồ sơ sáng kiến cấp cơ sở', NULL, 5, NULL, NULL, NULL, 3, 8,
      'NORMAL', DATEADD(DAY, -10, @today), DATEADD(DAY, 7, @today), DATEADD(DAY, 2, @today), 'IN_PROGRESS', 50, NULL, NULL, DATEADD(DAY, -10, @t0)),
 ( 8, N'Báo cáo tiến độ chuyển đổi số tháng', NULL, 5, NULL, NULL, NULL, 2, 8,
      'NORMAL', DATEADD(DAY, -25, @today), DATEADD(DAY, -6, @today), DATEADD(DAY, -6, @today), 'DONE', 100, N'Nộp trễ do chờ số liệu', DATEADD(HOUR, 10, DATEADD(DAY, -4, @t0)), DATEADD(DAY, -25, @t0)),
 ( 9, N'Thống kê cơ sở tín ngưỡng trên địa bàn', NULL, 6, NULL, NULL, NULL, 2, 9,
      'NORMAL', DATEADD(DAY, -9, @today), DATEADD(DAY, -1, @today), DATEADD(DAY, -1, @today), 'IN_PROGRESS', 60, NULL, NULL, DATEADD(DAY, -9, @t0)),
 (10, N'Chuẩn bị gặp mặt người có uy tín trong đồng bào dân tộc', NULL, 6, NULL, NULL, NULL, 2, 9,
      'NORMAL', DATEADD(DAY, -1, @today), DATEADD(DAY, 4, @today),  DATEADD(DAY, 4, @today),  'NEW', 0, NULL, NULL, DATEADD(DAY, -1, @t0)),
 (11, N'Xử lý văn bản rà soát quy hoạch cán bộ (MẬT)', N'Theo CV 58/SNV-CCVC', 1, 6, NULL, NULL, 2, 4,
      'HIGH',   DATEADD(DAY, -3, @today), DATEADD(DAY, 3, @today),  DATEADD(DAY, 3, @today),  'IN_PROGRESS', 20, NULL, NULL, DATEADD(DAY, -3, @t0)),
 (12, N'Rà soát hồ sơ đề nghị khen thưởng cuối năm', NULL, 1, NULL, NULL, NULL, 2, 4,
      'NORMAL', DATEADD(DAY, -6, @today), @today,                   @today,                   'NEW', 0, NULL, NULL, DATEADD(DAY, -6, @t0)),
 (13, N'Chuẩn bị nội dung giao ban tuần', N'Theo kết luận giao ban tháng', 1, NULL, 3, NULL, 2, 3,
      'NORMAL', DATEADD(DAY, -2, @today), DATEADD(DAY, 5, @today),  DATEADD(DAY, 5, @today),  'NEW', 0, NULL, NULL, DATEADD(DAY, -2, @t0)),
 (14, N'Báo cáo tình hình văn hóa – xã hội quý IV', NULL, 4, NULL, NULL, NULL, 1, 2,
      'HIGH',   DATEADD(DAY, -5, @today), DATEADD(DAY, 8, @today),  DATEADD(DAY, 8, @today),  'IN_PROGRESS', 25, NULL, NULL, DATEADD(DAY, -5, @t0)),
 (15, N'Khảo sát nhu cầu khám sức khỏe người cao tuổi', N'Đã gộp vào nhiệm vụ 1', 2, NULL, NULL, NULL, 2, 5,
      'LOW',    DATEADD(DAY, -10, @today), DATEADD(DAY, 5, @today), DATEADD(DAY, 5, @today),  'CANCELLED', 0, NULL, NULL, DATEADD(DAY, -10, @t0)),
 (16, N'Tổng hợp danh sách học sinh có hoàn cảnh khó khăn', NULL, 3, NULL, NULL, NULL, 3, 6,
      'NORMAL', DATEADD(DAY, -18, @today), DATEADD(DAY, -3, @today), DATEADD(DAY, -3, @today), 'DONE', 100, N'Hoàn thành', DATEADD(HOUR, 15, DATEADD(DAY, -5, @t0)), DATEADD(DAY, -18, @t0));
SET IDENTITY_INSERT dbo.tasks OFF;

INSERT INTO dbo.task_updates (task_id, updated_by, old_status, new_status, progress_percent, note, created_at) VALUES
 (1, 5, 'NEW', 'IN_PROGRESS', 40, N'Đã xây dựng khung kế hoạch',     DATEADD(DAY, -2, @t0)),
 (2, 5, 'NEW', 'IN_PROGRESS', 70, N'Chờ số liệu Trạm Y tế',          DATEADD(DAY, -4, @t0)),
 (5, 7, 'NEW', 'IN_PROGRESS', 30, N'Đã làm việc với 3/8 thôn',       DATEADD(DAY, -1, @t0)),
 (6, 7, 'IN_PROGRESS', 'DONE', 100, N'Đã gửi báo cáo',               DATEADD(HOUR, 16, DATEADD(DAY, -2, @t0))),
 (8, 8, 'IN_PROGRESS', 'DONE', 100, N'Nộp trễ do chờ số liệu',       DATEADD(HOUR, 10, DATEADD(DAY, -4, @t0))),
 (9, 9, 'NEW', 'IN_PROGRESS', 60, NULL,                              DATEADD(DAY, -3, @t0)),
 (16, 6, 'IN_PROGRESS', 'DONE', 100, N'Hoàn thành',                  DATEADD(HOUR, 15, DATEADD(DAY, -5, @t0)));

SET IDENTITY_INSERT dbo.extension_requests ON;
INSERT INTO dbo.extension_requests (request_id, task_id, requested_by, old_due_date, proposed_due_date, reason,
            status, decided_by, decided_at, decision_note, via_delegation_id, created_at) VALUES
 (1, 3, 6, DATEADD(DAY, -2, @today), DATEADD(DAY, 5, @today),
     N'Còn 2 trường chưa gửi số liệu, đề nghị gia hạn để tổng hợp đầy đủ.', 'PENDING', NULL, NULL, NULL, NULL, DATEADD(HOUR, 9, DATEADD(DAY, -1, @t0))),
 (2, 7, 8, DATEADD(DAY, 2, @today), DATEADD(DAY, 7, @today),
     N'Số lượng hồ sơ sáng kiến tăng gấp đôi so với dự kiến.', 'APPROVED', 3, DATEADD(HOUR, 10, DATEADD(DAY, -2, @t0)), N'Đồng ý', 1, DATEADD(HOUR, 8, DATEADD(DAY, -3, @t0))),
 (3, 9, 9, DATEADD(DAY, -1, @today), DATEADD(DAY, 3, @today),
     N'Một số cơ sở chưa cung cấp hồ sơ.', 'REJECTED', 2, DATEADD(HOUR, 14, DATEADD(DAY, -1, @t0)),
     N'Đề nghị hoàn thành đúng hạn để kịp tổng hợp báo cáo quý.', NULL, DATEADD(HOUR, 9, DATEADD(DAY, -2, @t0)));
SET IDENTITY_INSERT dbo.extension_requests OFF;

/* ---------- 10. Tệp đính kèm (metadata; tệp thật nằm trong thư mục lưu trữ của backend) ---------- */
INSERT INTO dbo.attachments (document_id, version_id, task_id, meeting_id, original_name, stored_name, storage_path,
            mime_type, file_ext, size_bytes, uploaded_by, uploaded_at) VALUES
 (1,  NULL, NULL, NULL, N'1520_SYT_phong_chong_SXH.pdf', 'a1f0c2d4-0001-4b6e-9a01-000000000001', N'storage/docs/a1f0c2d4-0001-4b6e-9a01-000000000001',
      'application/pdf', 'pdf', 482113, 4, DATEADD(HOUR, 9, DATEADD(DAY, -8, @t0))),
 (6,  NULL, NULL, NULL, N'58_SNV_quy_hoach_can_bo.pdf', 'a1f0c2d4-0002-4b6e-9a01-000000000002', N'storage/secret/a1f0c2d4-0002-4b6e-9a01-000000000002',
      'application/pdf', 'pdf', 1048576, 4, DATEADD(HOUR, 15, DATEADD(DAY, -4, @t0))),
 (10, 2,    NULL, NULL, N'BC_HSG_du_thao_v1.docx', 'a1f0c2d4-0003-4b6e-9a01-000000000003', N'storage/drafts/a1f0c2d4-0003-4b6e-9a01-000000000003',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx', 35210, 6, DATEADD(HOUR, 9, DATEADD(DAY, -2, @t0))),
 (11, 3,    NULL, NULL, N'KH_Ngay_hoi_DDK_v1.docx', 'a1f0c2d4-0004-4b6e-9a01-000000000004', N'storage/drafts/a1f0c2d4-0004-4b6e-9a01-000000000004',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx', 41877, 7, DATEADD(HOUR, 8, DATEADD(DAY, -2, @t0))),
 (NULL, NULL, 6, NULL, N'BC_cong_tac_gia_dinh.docx', 'a1f0c2d4-0005-4b6e-9a01-000000000005', N'storage/tasks/a1f0c2d4-0005-4b6e-9a01-000000000005',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx', 28904, 7, DATEADD(HOUR, 16, DATEADD(DAY, -2, @t0))),
 (NULL, NULL, NULL, 3, N'Bien_ban_giao_ban_thang.pdf', 'a1f0c2d4-0006-4b6e-9a01-000000000006', N'storage/meetings/a1f0c2d4-0006-4b6e-9a01-000000000006',
      'application/pdf', 'pdf', 220431, 4, DATEADD(HOUR, 11, DATEADD(DAY, -7, @t0)));

/* ---------- 11. Thông báo ---------- */
INSERT INTO dbo.notifications (recipient_id, notif_type, title, message, entity_type, entity_id, is_read, read_at, created_at) VALUES
 (1, 'DOC_DIRECTED',        N'Có văn bản cần cho ý kiến chỉ đạo', N'312/UBND-KGVX – Ngày hội Đại đoàn kết', 'DOCUMENT', 3, 0, NULL, DATEADD(HOUR, 9, DATEADD(DAY, -3, @t0))),
 (1, 'APPROVAL_PENDING',    N'Có dự thảo trình lên chờ bạn duyệt', N'Tờ trình công nhận sáng kiến', 'APPROVAL', 4, 0, NULL, DATEADD(HOUR, 16, DATEADD(DAY, -1, @t0))),
 (2, 'APPROVAL_PENDING',    N'Có dự thảo chờ bạn duyệt ký', N'Báo cáo chuẩn bị kỳ thi HSG', 'APPROVAL', 1, 0, NULL, DATEADD(HOUR, 15, DATEADD(DAY, -1, @t0))),
 (2, 'DOC_DIRECTED',        N'Có văn bản cần cho ý kiến chỉ đạo', N'845/SGDĐT-GDTrH', 'DOCUMENT', 2, 1, DATEADD(DAY, -4, @t0), DATEADD(HOUR, 11, DATEADD(DAY, -5, @t0))),
 (3, 'DELEGATION',          N'Bạn được ủy quyền ký duyệt', N'Từ Trưởng phòng, thời hạn 30 ngày', 'DELEGATION', NULL, 1, DATEADD(DAY, -5, @t0), DATEADD(DAY, -5, @t0)),
 (3, 'APPROVAL_PENDING',    N'Có dự thảo chờ duyệt (theo ủy quyền)', N'Báo cáo chuẩn bị kỳ thi HSG', 'APPROVAL', 1, 0, NULL, DATEADD(HOUR, 15, DATEADD(DAY, -1, @t0))),
 (3, 'EXTENSION_REQUESTED', N'Có đề xuất xin gia hạn nhiệm vụ', N'NV000003 – Tổng hợp số liệu đầu năm học', 'EXTENSION', 1, 0, NULL, DATEADD(HOUR, 9, DATEADD(DAY, -1, @t0))),
 (4, 'DOC_HANDLING',        N'Bạn được giao xử lý một văn bản', N'58/SNV-CCVC (MẬT)', 'DOCUMENT', 6, 1, DATEADD(DAY, -3, @t0), DATEADD(HOUR, 8, DATEADD(DAY, -3, @t0))),
 (4, 'SYSTEM',              N'Có văn bản đến chưa vào sổ', N'1602/GM-SYT – Giấy mời hội nghị tiêm chủng', 'DOCUMENT', 7, 0, NULL, DATEADD(MINUTE, -30, @now)),
 (4, 'TASK_DUE_SOON',       N'Nhiệm vụ sắp đến hạn', N'NV000012 – Rà soát hồ sơ khen thưởng (hạn hôm nay)', 'TASK', 12, 0, NULL, @t0),
 (5, 'TASK_ASSIGNED',       N'Bạn được giao nhiệm vụ mới', N'NV000001 – Kế hoạch phòng, chống SXH', 'TASK', 1, 1, DATEADD(DAY, -7, @t0), DATEADD(DAY, -7, @t0)),
 (5, 'DOC_HANDLING',        N'Bạn được giao xử lý một văn bản', N'1520/SYT-NVY', 'DOCUMENT', 1, 0, NULL, DATEADD(HOUR, 8, DATEADD(DAY, -7, @t0))),
 (5, 'TASK_OVERDUE',        N'Nhiệm vụ đã quá hạn', N'NV000002 – Báo cáo tiêm chủng mở rộng', 'TASK', 2, 0, NULL, @t0),
 (6, 'TASK_OVERDUE',        N'Nhiệm vụ đã quá hạn', N'NV000003 – Tổng hợp số liệu đầu năm học', 'TASK', 3, 0, NULL, @t0),
 (6, 'DOC_HANDLING',        N'Bạn được giao xử lý một văn bản', N'901/SGDĐT-KHTC', 'DOCUMENT', 8, 1, DATEADD(DAY, -12, @t0), DATEADD(HOUR, 14, DATEADD(DAY, -13, @t0))),
 (7, 'DOC_RETURNED',        N'Dự thảo bị trả lại', N'Bổ sung dự toán kinh phí và phân công cụ thể cho từng thôn.', 'DOCUMENT', 11, 0, NULL, DATEADD(HOUR, 9, DATEADD(DAY, -1, @t0))),
 (8, 'EXTENSION_DECIDED',   N'Kết quả đề xuất gia hạn', N'Đồng ý gia hạn', 'EXTENSION', 2, 1, DATEADD(DAY, -2, @t0), DATEADD(HOUR, 10, DATEADD(DAY, -2, @t0))),
 (9, 'EXTENSION_DECIDED',   N'Kết quả đề xuất gia hạn', N'Từ chối: Đề nghị hoàn thành đúng hạn để kịp tổng hợp báo cáo quý.', 'EXTENSION', 3, 0, NULL, DATEADD(HOUR, 14, DATEADD(DAY, -1, @t0))),
 (9, 'TASK_OVERDUE',        N'Nhiệm vụ đã quá hạn', N'NV000009 – Thống kê cơ sở tín ngưỡng', 'TASK', 9, 0, NULL, @t0);

/* ---------- 12. Nhật ký thao tác mẫu ---------- */
INSERT INTO dbo.audit_logs (user_id, active_role_id, action, entity_type, entity_id, detail, ip_address, created_at) VALUES
 (2, 2, 'DELEGATE_ON', 'DELEGATION', 1,  N'{"to_user_id":3,"days":30}', '10.0.0.12', DATEADD(DAY, -5, @t0)),
 (4, 4, 'REGISTER',    'DOCUMENT',   1,  N'{"book_id":1,"book_number":3}', '10.0.0.14', DATEADD(HOUR, 9, DATEADD(DAY, -8, @t0))),
 (2, 2, 'DIRECT',      'DOCUMENT',   1,  N'{"to_user_id":5,"type":"MAIN"}', '10.0.0.12', DATEADD(HOUR, 8, DATEADD(DAY, -7, @t0))),
 (2, 2, 'RETURN',      'DOCUMENT',   11, N'{"reason":"Bổ sung dự toán kinh phí và phân công cụ thể cho từng thôn."}', '10.0.0.12', DATEADD(HOUR, 9, DATEADD(DAY, -1, @t0))),
 (3, 3, 'APPROVE',     'DOCUMENT',   13, N'{"via_delegation_id":1}', '10.0.0.13', DATEADD(HOUR, 11, DATEADD(DAY, -1, @t0))),
 (2, 2, 'FORWARD',     'DOCUMENT',   12, N'{"to_user_id":1}', '10.0.0.12', DATEADD(HOUR, 16, DATEADD(DAY, -1, @t0))),
 (4, 4, 'ISSUE',       'DOCUMENT',   14, N'{"book_id":2,"book_number":1}', '10.0.0.14', DATEADD(HOUR, 15, DATEADD(DAY, -15, @t0))),
 (3, 3, 'EXT_APPROVE', 'TASK',       7,  N'{"request_id":2,"via_delegation_id":1}', '10.0.0.13', DATEADD(HOUR, 10, DATEADD(DAY, -2, @t0))),
 (2, 2, 'EXT_REJECT',  'TASK',       9,  N'{"request_id":3}', '10.0.0.12', DATEADD(HOUR, 14, DATEADD(DAY, -1, @t0))),
 (7, 7, 'UPDATE_PROGRESS', 'TASK',   6,  N'{"old":"IN_PROGRESS","new":"DONE","progress":100}', '10.0.0.17', DATEADD(HOUR, 16, DATEADD(DAY, -2, @t0)));

COMMIT;

PRINT N'03_seed_data.sql: đã nạp dữ liệu mẫu (9 tài khoản, 14 văn bản, 16 nhiệm vụ, 3 cuộc họp).';
GO
