/* =====================================================================
   HỆ THỐNG QUẢN LÝ PHÒNG VĂN HÓA – XÃ HỘI (VHXH)
   File   : 01_schema.sql  – Tạo CSDL, bảng, khóa, ràng buộc, chỉ mục

   Quy ước đặt tên:
     - Bảng, cột: tiếng Anh, snake_case, số nhiều cho bảng (users, tasks...)
     - PK_<bảng>, FK_<bảng>_<bảng tham chiếu>, UQ_, CK_, DF_, IX_, UX_ (unique index)
     - Giá trị trạng thái (enum) lưu dạng mã VARCHAR in hoa, ràng buộc bằng CHECK.
       Bảng ý nghĩa tiếng Việt của từng mã có trong tài liệu thiết kế.
   ===================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- bắt buộc để tạo filtered index
GO

IF DB_ID(N'QLVHXH') IS NULL
    CREATE DATABASE QLVHXH COLLATE Vietnamese_CI_AS;
GO
USE QLVHXH;
GO

/* ---------------------------------------------------------------------
   0. XÓA BẢNG CŨ (để chạy lại script nhiều lần trong lúc phát triển)
   Thứ tự xóa ngược với thứ tự phụ thuộc khóa ngoại.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.briefing_report_lines;
DROP TABLE IF EXISTS dbo.briefing_reports;
DROP TABLE IF EXISTS dbo.audit_logs;
DROP TABLE IF EXISTS dbo.notifications;
DROP TABLE IF EXISTS dbo.extension_requests;
DROP TABLE IF EXISTS dbo.task_updates;
DROP TABLE IF EXISTS dbo.attachments;
DROP TABLE IF EXISTS dbo.tasks;
DROP TABLE IF EXISTS dbo.meeting_participants;
DROP TABLE IF EXISTS dbo.meetings;
DROP TABLE IF EXISTS dbo.approval_requests;
DROP TABLE IF EXISTS dbo.document_access_grants;
DROP TABLE IF EXISTS dbo.document_handlings;
DROP TABLE IF EXISTS dbo.document_recipients;
DROP TABLE IF EXISTS dbo.document_versions;
DROP TABLE IF EXISTS dbo.documents;
DROP TABLE IF EXISTS dbo.document_books;
DROP TABLE IF EXISTS dbo.document_types;
DROP TABLE IF EXISTS dbo.organizations;
DROP TABLE IF EXISTS dbo.system_settings;
DROP TABLE IF EXISTS dbo.calendar_days;
DROP TABLE IF EXISTS dbo.delegations;
DROP TABLE IF EXISTS dbo.user_sessions;
DROP TABLE IF EXISTS dbo.leader_fields;
DROP TABLE IF EXISTS dbo.user_roles;
DROP TABLE IF EXISTS dbo.users;
DROP TABLE IF EXISTS dbo.role_permissions;
DROP TABLE IF EXISTS dbo.app_functions;
DROP TABLE IF EXISTS dbo.roles;
DROP TABLE IF EXISTS dbo.fields;
GO

/* =====================================================================
   NHÓM A. DANH MỤC, NGƯỜI DÙNG, VAI TRÒ, PHÂN QUYỀN  (task 1.1.3)
   ===================================================================== */

-- A1. Lĩnh vực chuyên môn (6 lĩnh vực của 6 chuyên viên)
CREATE TABLE dbo.fields (
    field_id    INT IDENTITY(1,1) NOT NULL,
    code        VARCHAR(10)   NOT NULL,          -- NV, YT, GD, VHXH, KHCN, DTTG
    name        NVARCHAR(100) NOT NULL,
    is_active   BIT NOT NULL CONSTRAINT DF_fields_is_active DEFAULT (1),
    CONSTRAINT PK_fields PRIMARY KEY (field_id),
    CONSTRAINT UQ_fields_code UNIQUE (code)
);

-- A2. Vai trò nghiệp vụ (9 vai trò). rank_no nhỏ = cấp cao hơn.
CREATE TABLE dbo.roles (
    role_id     INT IDENTITY(1,1) NOT NULL,
    code        VARCHAR(20)   NOT NULL,          -- PCT, TP, PTP, CV_NV, CV_YT ...
    name        NVARCHAR(100) NOT NULL,
    role_level  VARCHAR(10)   NOT NULL,          -- LEADER | STAFF
    rank_no     TINYINT       NOT NULL,          -- 1 PCT, 2 TP, 3 PTP, 4 chuyên viên
    field_id    INT NULL,                        -- chỉ chuyên viên mới gắn lĩnh vực
    CONSTRAINT PK_roles PRIMARY KEY (role_id),
    CONSTRAINT UQ_roles_code UNIQUE (code),
    CONSTRAINT FK_roles_fields FOREIGN KEY (field_id) REFERENCES dbo.fields(field_id),
    CONSTRAINT CK_roles_level CHECK (role_level IN ('LEADER','STAFF')),
    CONSTRAINT CK_roles_field CHECK (
        (role_level = 'STAFF'  AND field_id IS NOT NULL) OR
        (role_level = 'LEADER' AND field_id IS NULL))
);

-- A3. Danh mục chức năng (25 dòng của ma trận vai trò – chức năng)
CREATE TABLE dbo.app_functions (
    function_id   INT IDENTITY(1,1) NOT NULL,
    code          VARCHAR(40)   NOT NULL,        -- F01_LOGIN, F08_PENDING_APPROVAL ...
    name          NVARCHAR(150) NOT NULL,
    group_code    VARCHAR(5)    NOT NULL,        -- I..V theo ma trận
    group_name    NVARCHAR(100) NOT NULL,
    sort_no       INT NOT NULL,
    CONSTRAINT PK_app_functions PRIMARY KEY (function_id),
    CONSTRAINT UQ_app_functions_code UNIQUE (code)
);

-- A4. Ma trận quyền: vai trò x chức năng x hành động
--     action: X xem | S soạn/khởi tạo | C cập nhật | G giao/chỉ đạo | D duyệt/quyết định
--     Ký hiệu "U" trong ma trận = requires_delegation = 1 (chỉ dùng được khi có ủy quyền còn hiệu lực)
--     scope : ALL toàn phòng | FIELD theo lĩnh vực | OWN của bản thân
--             ASSIGNED được giao trực tiếp | RELATED có liên quan | GRANTED trong danh sách được cấp
CREATE TABLE dbo.role_permissions (
    role_id              INT NOT NULL,
    function_id          INT NOT NULL,
    action               CHAR(1) NOT NULL,
    scope                VARCHAR(10) NOT NULL CONSTRAINT DF_role_permissions_scope DEFAULT ('ALL'),
    requires_delegation  BIT NOT NULL CONSTRAINT DF_role_permissions_deleg DEFAULT (0),
    note                 NVARCHAR(300) NULL,
    CONSTRAINT PK_role_permissions PRIMARY KEY (role_id, function_id, action),
    CONSTRAINT FK_role_permissions_roles     FOREIGN KEY (role_id)     REFERENCES dbo.roles(role_id),
    CONSTRAINT FK_role_permissions_functions FOREIGN KEY (function_id) REFERENCES dbo.app_functions(function_id),
    CONSTRAINT CK_role_permissions_action CHECK (action IN ('X','S','C','G','D')),
    CONSTRAINT CK_role_permissions_scope  CHECK (scope IN ('ALL','FIELD','OWN','ASSIGNED','RELATED','GRANTED'))
);

-- A5. Tài khoản người dùng
CREATE TABLE dbo.users (
    user_id             INT IDENTITY(1,1) NOT NULL,
    username            VARCHAR(50)   NOT NULL,
    password_hash       VARCHAR(255)  NOT NULL,     -- bcrypt, KHÔNG lưu mật khẩu gốc
    full_name           NVARCHAR(100) NOT NULL,
    position_title      NVARCHAR(150) NULL,         -- chức danh hiển thị
    email               VARCHAR(150)  NULL,
    phone               VARCHAR(20)   NULL,
    is_active           BIT NOT NULL CONSTRAINT DF_users_is_active DEFAULT (1),
    is_demo_account     BIT NOT NULL CONSTRAINT DF_users_is_demo DEFAULT (0),
    failed_login_count  TINYINT NOT NULL CONSTRAINT DF_users_failed DEFAULT (0),
    locked_until        DATETIME2(0) NULL,          -- khóa tạm khi nhập sai nhiều lần
    last_login_at       DATETIME2(0) NULL,
    created_at          DATETIME2(0) NOT NULL CONSTRAINT DF_users_created DEFAULT (SYSDATETIME()),
    updated_at          DATETIME2(0) NULL,
    CONSTRAINT PK_users PRIMARY KEY (user_id),
    CONSTRAINT UQ_users_username UNIQUE (username)
);
CREATE UNIQUE INDEX UX_users_email ON dbo.users(email) WHERE email IS NOT NULL;

-- A6. Một người có thể giữ nhiều vai trò (kiêm nhiệm) -> bảng N-N
CREATE TABLE dbo.user_roles (
    user_id     INT NOT NULL,
    role_id     INT NOT NULL,
    is_default  BIT NOT NULL CONSTRAINT DF_user_roles_default DEFAULT (0),  -- vai trò mở khi đăng nhập
    granted_by  INT NULL,
    granted_at  DATETIME2(0) NOT NULL CONSTRAINT DF_user_roles_granted DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_user_roles PRIMARY KEY (user_id, role_id),
    CONSTRAINT FK_user_roles_users   FOREIGN KEY (user_id)    REFERENCES dbo.users(user_id),
    CONSTRAINT FK_user_roles_roles   FOREIGN KEY (role_id)    REFERENCES dbo.roles(role_id),
    CONSTRAINT FK_user_roles_granter FOREIGN KEY (granted_by) REFERENCES dbo.users(user_id)
);
-- mỗi người chỉ có đúng 1 vai trò mặc định
CREATE UNIQUE INDEX UX_user_roles_one_default ON dbo.user_roles(user_id) WHERE is_default = 1;

-- A7. Lĩnh vực Phó Trưởng phòng / lãnh đạo được phân công phụ trách ("mảng phụ trách")
CREATE TABLE dbo.leader_fields (
    user_id   INT NOT NULL,
    field_id  INT NOT NULL,
    CONSTRAINT PK_leader_fields PRIMARY KEY (user_id, field_id),
    CONSTRAINT FK_leader_fields_users  FOREIGN KEY (user_id)  REFERENCES dbo.users(user_id),
    CONSTRAINT FK_leader_fields_fields FOREIGN KEY (field_id) REFERENCES dbo.fields(field_id)
);

-- A8. Phiên đăng nhập. active_role_id phải thuộc danh sách vai trò được cấp:
--     ràng buộc bằng FK kép (user_id, active_role_id) -> user_roles.
CREATE TABLE dbo.user_sessions (
    session_id      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_user_sessions_id DEFAULT (NEWID()),
    user_id         INT NOT NULL,
    active_role_id  INT NOT NULL,
    is_demo_mode    BIT NOT NULL CONSTRAINT DF_user_sessions_demo DEFAULT (0),
    created_at      DATETIME2(0) NOT NULL CONSTRAINT DF_user_sessions_created DEFAULT (SYSDATETIME()),
    last_seen_at    DATETIME2(0) NOT NULL CONSTRAINT DF_user_sessions_seen DEFAULT (SYSDATETIME()),
    expires_at      DATETIME2(0) NOT NULL,
    revoked_at      DATETIME2(0) NULL,            -- đăng xuất / bị thu hồi
    ip_address      VARCHAR(45)  NULL,
    user_agent      NVARCHAR(300) NULL,
    CONSTRAINT PK_user_sessions PRIMARY KEY (session_id),
    CONSTRAINT FK_user_sessions_user_roles FOREIGN KEY (user_id, active_role_id)
        REFERENCES dbo.user_roles(user_id, role_id),
    CONSTRAINT CK_user_sessions_expiry CHECK (expires_at > created_at)
);
CREATE INDEX IX_user_sessions_user ON dbo.user_sessions(user_id, expires_at);

-- A9. Ủy quyền (Trưởng phòng bật/tắt cho Phó Trưởng phòng).
--     is_active = "is_delegated" trong ma trận; chỉ có hiệu lực khi now trong [valid_from, valid_to].
CREATE TABLE dbo.delegations (
    delegation_id           INT IDENTITY(1,1) NOT NULL,
    from_user_id            INT NOT NULL,       -- người ủy quyền (Trưởng phòng)
    to_user_id              INT NOT NULL,       -- người được ủy quyền (Phó Trưởng phòng)
    can_sign                BIT NOT NULL CONSTRAINT DF_delegations_sign DEFAULT (1),  -- duyệt/ký, phát hành
    can_approve_extension   BIT NOT NULL CONSTRAINT DF_delegations_ext  DEFAULT (1),  -- duyệt gia hạn
    can_view_confidential   BIT NOT NULL CONSTRAINT DF_delegations_conf DEFAULT (0),  -- xem/tải văn bản mật
    valid_from              DATETIME2(0) NOT NULL,
    valid_to                DATETIME2(0) NOT NULL,
    is_active               BIT NOT NULL CONSTRAINT DF_delegations_active DEFAULT (1),
    reason                  NVARCHAR(300) NULL,
    created_at              DATETIME2(0) NOT NULL CONSTRAINT DF_delegations_created DEFAULT (SYSDATETIME()),
    revoked_at              DATETIME2(0) NULL,
    CONSTRAINT PK_delegations PRIMARY KEY (delegation_id),
    CONSTRAINT FK_delegations_from FOREIGN KEY (from_user_id) REFERENCES dbo.users(user_id),
    CONSTRAINT FK_delegations_to   FOREIGN KEY (to_user_id)   REFERENCES dbo.users(user_id),
    CONSTRAINT CK_delegations_users  CHECK (from_user_id <> to_user_id),
    CONSTRAINT CK_delegations_period CHECK (valid_to > valid_from)
);
CREATE INDEX IX_delegations_to ON dbo.delegations(to_user_id, is_active, valid_from, valid_to);

-- A10. Lịch ngày làm việc – dùng để tính "còn bao nhiêu ngày làm việc".
--      Ngày nghỉ lễ do người quản trị nhập; hệ thống KHÔNG tự suy đoán ngày lễ.
CREATE TABLE dbo.calendar_days (
    cal_date        DATE NOT NULL,
    is_working_day  BIT  NOT NULL,
    note            NVARCHAR(100) NULL,           -- 'Thứ Bảy', 'Quốc khánh', 'Làm bù'...
    CONSTRAINT PK_calendar_days PRIMARY KEY (cal_date)
);

-- A11. Tham số cấu hình (ngưỡng sắp hạn, dung lượng tệp...)
CREATE TABLE dbo.system_settings (
    setting_key     VARCHAR(50)   NOT NULL,
    setting_value   NVARCHAR(200) NOT NULL,
    description     NVARCHAR(300) NULL,
    updated_at      DATETIME2(0)  NOT NULL CONSTRAINT DF_system_settings_upd DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_system_settings PRIMARY KEY (setting_key)
);
GO

/* =====================================================================
   NHÓM B. VĂN BẢN, SỔ VĂN BẢN, TỆP ĐÍNH KÈM, TRÌNH KÝ  (task 2.1.2)
   ===================================================================== */

-- B1. Cơ quan gửi / nhận văn bản
CREATE TABLE dbo.organizations (
    org_id      INT IDENTITY(1,1) NOT NULL,
    name        NVARCHAR(255) NOT NULL,
    short_name  NVARCHAR(50)  NULL,
    org_type    VARCHAR(10)   NOT NULL CONSTRAINT DF_organizations_type DEFAULT ('EXTERNAL'),
    address     NVARCHAR(255) NULL,
    email       VARCHAR(150)  NULL,
    is_active   BIT NOT NULL CONSTRAINT DF_organizations_active DEFAULT (1),
    CONSTRAINT PK_organizations PRIMARY KEY (org_id),
    CONSTRAINT UQ_organizations_name UNIQUE (name),
    CONSTRAINT CK_organizations_type CHECK (org_type IN ('INTERNAL','EXTERNAL'))
);

-- B2. Loại văn bản (Công văn, Quyết định, Thông báo, Báo cáo, Kế hoạch, Tờ trình, Giấy mời)
CREATE TABLE dbo.document_types (
    doc_type_id   INT IDENTITY(1,1) NOT NULL,
    code          VARCHAR(10)   NOT NULL,
    name          NVARCHAR(100) NOT NULL,
    abbreviation  NVARCHAR(10)  NOT NULL,       -- dùng ghép số ký hiệu: 15/QĐ-UBND
    CONSTRAINT PK_document_types PRIMARY KEY (doc_type_id),
    CONSTRAINT UQ_document_types_code UNIQUE (code)
);

-- B3. Sổ văn bản: mỗi năm 1 sổ đến, 1 sổ đi (có thể thêm sổ mật).
--     last_number = số cuối cùng đã cấp; cấp số mới qua thủ tục sp_next_book_number (có khóa).
CREATE TABLE dbo.document_books (
    book_id       INT IDENTITY(1,1) NOT NULL,
    code          VARCHAR(20)   NOT NULL,       -- SDEN, SDI, SDEN_MAT
    name          NVARCHAR(150) NOT NULL,
    direction     CHAR(3)       NOT NULL,       -- IN | OUT
    book_year     SMALLINT      NOT NULL,
    last_number   INT NOT NULL CONSTRAINT DF_document_books_last DEFAULT (0),
    is_active     BIT NOT NULL CONSTRAINT DF_document_books_active DEFAULT (1),
    CONSTRAINT PK_document_books PRIMARY KEY (book_id),
    CONSTRAINT UQ_document_books UNIQUE (code, book_year),
    CONSTRAINT CK_document_books_direction CHECK (direction IN ('IN','OUT')),
    CONSTRAINT CK_document_books_last CHECK (last_number >= 0)
);

-- B4. Văn bản (gộp văn bản đến và đi trong 1 bảng, phân biệt bằng direction)
--   Trạng thái văn bản ĐẾN : RECEIVED (mới tiếp nhận) -> REGISTERED (đã vào sổ)
--                            -> WAIT_DIRECTION (chờ lãnh đạo chỉ đạo) -> PROCESSING -> COMPLETED
--   Trạng thái văn bản ĐI  : DRAFT -> PENDING_APPROVAL -> (RETURNED -> PENDING_APPROVAL)
--                            -> APPROVED -> ISSUED ; CANCELLED
CREATE TABLE dbo.documents (
    document_id         INT IDENTITY(1,1) NOT NULL,
    direction           CHAR(3)        NOT NULL,
    book_id             INT NULL,                 -- NULL khi chưa vào sổ / chưa phát hành
    book_number         INT NULL,                 -- số đến hoặc số đi trong sổ
    symbol              NVARCHAR(60)   NULL,      -- số, ký hiệu: 125/UBND-VHXH
    doc_type_id         INT NOT NULL,
    summary             NVARCHAR(500)  NOT NULL,  -- trích yếu
    field_id            INT NOT NULL,
    issuing_org_id      INT NULL,                 -- cơ quan ban hành (văn bản đến)
    issued_date         DATE NULL,                -- ngày ký văn bản
    received_at         DATETIME2(0) NULL,        -- ngày giờ đến (chỉ văn bản đến)
    signer_name         NVARCHAR(100) NULL,       -- người ký (văn bản đến, ghi chữ)
    signed_by           INT NULL,                 -- lãnh đạo duyệt ký (văn bản đi)
    security_level      VARCHAR(12) NOT NULL CONSTRAINT DF_documents_security DEFAULT ('NORMAL'),
    urgency             VARCHAR(10) NOT NULL CONSTRAINT DF_documents_urgency  DEFAULT ('NORMAL'),
    status              VARCHAR(20) NOT NULL,
    due_date            DATE NULL,                -- hạn xử lý văn bản
    current_version_no  INT NOT NULL CONSTRAINT DF_documents_version DEFAULT (0),
    issued_at           DATETIME2(0) NULL,        -- thời điểm phát hành (văn bản đi)
    issued_by           INT NULL,
    created_by          INT NOT NULL,
    created_at          DATETIME2(0) NOT NULL CONSTRAINT DF_documents_created DEFAULT (SYSDATETIME()),
    updated_by          INT NULL,
    updated_at          DATETIME2(0) NULL,
    row_ver             ROWVERSION,               -- chống cập nhật đồng thời (optimistic lock)
    CONSTRAINT PK_documents PRIMARY KEY (document_id),
    CONSTRAINT FK_documents_books     FOREIGN KEY (book_id)        REFERENCES dbo.document_books(book_id),
    CONSTRAINT FK_documents_types     FOREIGN KEY (doc_type_id)    REFERENCES dbo.document_types(doc_type_id),
    CONSTRAINT FK_documents_fields    FOREIGN KEY (field_id)       REFERENCES dbo.fields(field_id),
    CONSTRAINT FK_documents_orgs      FOREIGN KEY (issuing_org_id) REFERENCES dbo.organizations(org_id),
    CONSTRAINT FK_documents_signed_by FOREIGN KEY (signed_by)      REFERENCES dbo.users(user_id),
    CONSTRAINT FK_documents_issued_by FOREIGN KEY (issued_by)      REFERENCES dbo.users(user_id),
    CONSTRAINT FK_documents_created   FOREIGN KEY (created_by)     REFERENCES dbo.users(user_id),
    CONSTRAINT FK_documents_updated   FOREIGN KEY (updated_by)     REFERENCES dbo.users(user_id),
    CONSTRAINT CK_documents_direction CHECK (direction IN ('IN','OUT')),
    CONSTRAINT CK_documents_security  CHECK (security_level IN ('NORMAL','CONFIDENTIAL','SECRET','TOP_SECRET')),
    CONSTRAINT CK_documents_urgency   CHECK (urgency IN ('NORMAL','URGENT','EXPRESS')),
    CONSTRAINT CK_documents_status CHECK (
        (direction = 'IN'  AND status IN ('RECEIVED','REGISTERED','WAIT_DIRECTION','PROCESSING','COMPLETED')) OR
        (direction = 'OUT' AND status IN ('DRAFT','PENDING_APPROVAL','RETURNED','APPROVED','ISSUED','CANCELLED'))),
    -- có số thì phải có sổ; văn bản đã vào sổ / đã phát hành thì phải có số
    CONSTRAINT CK_documents_book CHECK (book_number IS NULL OR (book_id IS NOT NULL AND book_number > 0)),
    CONSTRAINT CK_documents_numbered CHECK (
        status NOT IN ('REGISTERED','WAIT_DIRECTION','PROCESSING','COMPLETED','ISSUED') OR book_number IS NOT NULL),
    CONSTRAINT CK_documents_received CHECK (direction = 'IN' OR received_at IS NULL),
    CONSTRAINT CK_documents_issued CHECK (status <> 'ISSUED' OR (issued_at IS NOT NULL AND issued_by IS NOT NULL))
);
-- Số trong một sổ không được trùng (sổ đã gắn năm nên = không trùng theo năm)
CREATE UNIQUE INDEX UX_documents_book_number ON dbo.documents(book_id, book_number)
    WHERE book_number IS NOT NULL;
-- Chống vào sổ trùng một văn bản đến (cùng cơ quan, cùng số ký hiệu, cùng ngày ký)
CREATE UNIQUE INDEX UX_documents_incoming_dup ON dbo.documents(issuing_org_id, symbol, issued_date)
    WHERE direction = 'IN' AND symbol IS NOT NULL AND issuing_org_id IS NOT NULL;
CREATE INDEX IX_documents_search ON dbo.documents(direction, field_id, status, issued_date)
    INCLUDE (book_number, symbol, security_level);
CREATE INDEX IX_documents_received ON dbo.documents(received_at) WHERE direction = 'IN';

-- B5. Phiên bản dự thảo (mỗi lần sửa/trình lại tạo 1 phiên bản; tệp gắn qua attachments.version_id)
CREATE TABLE dbo.document_versions (
    version_id    INT IDENTITY(1,1) NOT NULL,
    document_id   INT NOT NULL,
    version_no    INT NOT NULL,
    change_note   NVARCHAR(500) NULL,
    created_by    INT NOT NULL,
    created_at    DATETIME2(0) NOT NULL CONSTRAINT DF_document_versions_created DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_document_versions PRIMARY KEY (version_id),
    CONSTRAINT UQ_document_versions UNIQUE (document_id, version_no),
    CONSTRAINT FK_document_versions_documents FOREIGN KEY (document_id) REFERENCES dbo.documents(document_id),
    CONSTRAINT FK_document_versions_users     FOREIGN KEY (created_by)  REFERENCES dbo.users(user_id),
    CONSTRAINT CK_document_versions_no CHECK (version_no >= 1)
);

-- B6. Nơi nhận của văn bản đi (cơ quan ngoài hoặc cán bộ trong phòng)
CREATE TABLE dbo.document_recipients (
    recipient_id   INT IDENTITY(1,1) NOT NULL,
    document_id    INT NOT NULL,
    org_id         INT NULL,
    user_id        INT NULL,
    note           NVARCHAR(200) NULL,          -- 'Như trên', 'Lưu: VT, VHXH'
    sent_at        DATETIME2(0) NULL,
    CONSTRAINT PK_document_recipients PRIMARY KEY (recipient_id),
    CONSTRAINT FK_document_recipients_documents FOREIGN KEY (document_id) REFERENCES dbo.documents(document_id),
    CONSTRAINT FK_document_recipients_orgs      FOREIGN KEY (org_id)      REFERENCES dbo.organizations(org_id),
    CONSTRAINT FK_document_recipients_users     FOREIGN KEY (user_id)     REFERENCES dbo.users(user_id),
    CONSTRAINT CK_document_recipients_target CHECK (org_id IS NOT NULL OR user_id IS NOT NULL OR note IS NOT NULL)
);

-- B7. Luân chuyển / chỉ đạo / phân công xử lý văn bản
--     DIRECTION : chuyển lãnh đạo cho ý kiến chỉ đạo  -> thẻ "Văn bản cần chỉ đạo"
--     MAIN      : xử lý chính   | COORDINATE : phối hợp | INFO : nhận để biết
--     -> MAIN/COORDINATE đang PENDING = "Hồ sơ chờ xử lý" của người nhận
CREATE TABLE dbo.document_handlings (
    handling_id         INT IDENTITY(1,1) NOT NULL,
    document_id         INT NOT NULL,
    parent_handling_id  INT NULL,               -- bước chuyển trước (để vẽ luồng)
    from_user_id        INT NOT NULL,
    to_user_id          INT NOT NULL,
    handling_type       VARCHAR(12) NOT NULL,
    instruction         NVARCHAR(1000) NULL,    -- ý kiến chỉ đạo
    due_date            DATE NULL,
    status              VARCHAR(10) NOT NULL CONSTRAINT DF_document_handlings_status DEFAULT ('PENDING'),
    created_at          DATETIME2(0) NOT NULL CONSTRAINT DF_document_handlings_created DEFAULT (SYSDATETIME()),
    done_at             DATETIME2(0) NULL,
    CONSTRAINT PK_document_handlings PRIMARY KEY (handling_id),
    CONSTRAINT FK_document_handlings_documents FOREIGN KEY (document_id)        REFERENCES dbo.documents(document_id),
    CONSTRAINT FK_document_handlings_parent    FOREIGN KEY (parent_handling_id) REFERENCES dbo.document_handlings(handling_id),
    CONSTRAINT FK_document_handlings_from      FOREIGN KEY (from_user_id)       REFERENCES dbo.users(user_id),
    CONSTRAINT FK_document_handlings_to        FOREIGN KEY (to_user_id)         REFERENCES dbo.users(user_id),
    CONSTRAINT CK_document_handlings_type   CHECK (handling_type IN ('DIRECTION','MAIN','COORDINATE','INFO')),
    CONSTRAINT CK_document_handlings_status CHECK (status IN ('PENDING','DONE','RECALLED')),
    CONSTRAINT CK_document_handlings_done   CHECK ((status = 'DONE' AND done_at IS NOT NULL) OR (status <> 'DONE' AND done_at IS NULL))
);
CREATE INDEX IX_document_handlings_to ON dbo.document_handlings(to_user_id, status, handling_type) INCLUDE (document_id, due_date);
CREATE INDEX IX_document_handlings_doc ON dbo.document_handlings(document_id);

-- B8. Cấp quyền xem/tải văn bản mật cho người được giao trực tiếp
CREATE TABLE dbo.document_access_grants (
    document_id  INT NOT NULL,
    user_id      INT NOT NULL,
    granted_by   INT NOT NULL,
    granted_at   DATETIME2(0) NOT NULL CONSTRAINT DF_document_access_grants_at DEFAULT (SYSDATETIME()),
    expires_at   DATETIME2(0) NULL,
    CONSTRAINT PK_document_access_grants PRIMARY KEY (document_id, user_id),
    CONSTRAINT FK_document_access_grants_documents FOREIGN KEY (document_id) REFERENCES dbo.documents(document_id),
    CONSTRAINT FK_document_access_grants_user      FOREIGN KEY (user_id)     REFERENCES dbo.users(user_id),
    CONSTRAINT FK_document_access_grants_granter   FOREIGN KEY (granted_by)  REFERENCES dbo.users(user_id)
);

-- B9. Trình ký / phê duyệt dự thảo (mỗi bước là 1 dòng; TP duyệt xong có thể FORWARDED lên PCT)
CREATE TABLE dbo.approval_requests (
    approval_id         INT IDENTITY(1,1) NOT NULL,
    document_id         INT NOT NULL,
    version_id          INT NOT NULL,           -- phiên bản được trình
    step_no             TINYINT NOT NULL CONSTRAINT DF_approval_requests_step DEFAULT (1),
    submitted_by        INT NOT NULL,
    submitted_at        DATETIME2(0) NOT NULL CONSTRAINT DF_approval_requests_sub DEFAULT (SYSDATETIME()),
    approver_id         INT NOT NULL,           -- người có thẩm quyền được trình
    status              VARCHAR(10) NOT NULL CONSTRAINT DF_approval_requests_status DEFAULT ('PENDING'),
    decided_by          INT NULL,               -- người bấm duyệt thực tế (có thể là PTP được ủy quyền)
    decided_at          DATETIME2(0) NULL,
    decision_note       NVARCHAR(1000) NULL,    -- bắt buộc khi trả lại
    via_delegation_id   INT NULL,
    row_ver             ROWVERSION,
    CONSTRAINT PK_approval_requests PRIMARY KEY (approval_id),
    CONSTRAINT FK_approval_requests_documents FOREIGN KEY (document_id)       REFERENCES dbo.documents(document_id),
    CONSTRAINT FK_approval_requests_versions  FOREIGN KEY (version_id)        REFERENCES dbo.document_versions(version_id),
    CONSTRAINT FK_approval_requests_submitter FOREIGN KEY (submitted_by)      REFERENCES dbo.users(user_id),
    CONSTRAINT FK_approval_requests_approver  FOREIGN KEY (approver_id)       REFERENCES dbo.users(user_id),
    CONSTRAINT FK_approval_requests_decider   FOREIGN KEY (decided_by)        REFERENCES dbo.users(user_id),
    CONSTRAINT FK_approval_requests_deleg     FOREIGN KEY (via_delegation_id) REFERENCES dbo.delegations(delegation_id),
    CONSTRAINT CK_approval_requests_status CHECK (status IN ('PENDING','APPROVED','RETURNED','FORWARDED','CANCELLED')),
    CONSTRAINT CK_approval_requests_decided CHECK (
        (status = 'PENDING' AND decided_at IS NULL AND decided_by IS NULL) OR
        (status = 'CANCELLED') OR
        (status IN ('APPROVED','RETURNED','FORWARDED') AND decided_at IS NOT NULL AND decided_by IS NOT NULL)),
    CONSTRAINT CK_approval_requests_return_reason CHECK (
        status <> 'RETURNED' OR LEN(LTRIM(RTRIM(ISNULL(decision_note, N'')))) > 0)
);
-- Mỗi văn bản tại một thời điểm chỉ có tối đa 1 lượt trình đang chờ
CREATE UNIQUE INDEX UX_approval_requests_one_pending ON dbo.approval_requests(document_id) WHERE status = 'PENDING';
CREATE INDEX IX_approval_requests_approver ON dbo.approval_requests(approver_id, status);
GO

/* =====================================================================
   NHÓM C. NHIỆM VỤ, GIA HẠN, LỊCH HỌP  (task 1.1.3 + 3.1, 3.3)
   ===================================================================== */

-- C1. Lịch họp lãnh đạo
CREATE TABLE dbo.meetings (
    meeting_id              INT IDENTITY(1,1) NOT NULL,
    title                   NVARCHAR(300) NOT NULL,
    content                 NVARCHAR(MAX) NULL,
    location                NVARCHAR(200) NULL,
    start_at                DATETIME2(0) NOT NULL,
    end_at                  DATETIME2(0) NOT NULL,
    chaired_by              INT NULL,
    created_by              INT NOT NULL,
    status                  VARCHAR(10) NOT NULL CONSTRAINT DF_meetings_status DEFAULT ('SCHEDULED'),
    remind_before_minutes   INT NOT NULL CONSTRAINT DF_meetings_remind DEFAULT (30),
    created_at              DATETIME2(0) NOT NULL CONSTRAINT DF_meetings_created DEFAULT (SYSDATETIME()),
    updated_at              DATETIME2(0) NULL,
    CONSTRAINT PK_meetings PRIMARY KEY (meeting_id),
    CONSTRAINT FK_meetings_chair   FOREIGN KEY (chaired_by) REFERENCES dbo.users(user_id),
    CONSTRAINT FK_meetings_creator FOREIGN KEY (created_by) REFERENCES dbo.users(user_id),
    CONSTRAINT CK_meetings_time   CHECK (end_at > start_at),
    CONSTRAINT CK_meetings_status CHECK (status IN ('SCHEDULED','DONE','CANCELLED')),
    CONSTRAINT CK_meetings_remind CHECK (remind_before_minutes >= 0)
);
CREATE INDEX IX_meetings_start ON dbo.meetings(start_at);

CREATE TABLE dbo.meeting_participants (
    meeting_id        INT NOT NULL,
    user_id           INT NOT NULL,
    participant_role  VARCHAR(10) NOT NULL CONSTRAINT DF_meeting_participants_role DEFAULT ('MEMBER'),
    attendance        VARCHAR(10) NOT NULL CONSTRAINT DF_meeting_participants_att  DEFAULT ('INVITED'),
    CONSTRAINT PK_meeting_participants PRIMARY KEY (meeting_id, user_id),
    CONSTRAINT FK_meeting_participants_meetings FOREIGN KEY (meeting_id) REFERENCES dbo.meetings(meeting_id),
    CONSTRAINT FK_meeting_participants_users    FOREIGN KEY (user_id)    REFERENCES dbo.users(user_id),
    CONSTRAINT CK_meeting_participants_role CHECK (participant_role IN ('CHAIR','MEMBER','SECRETARY','GUEST')),
    CONSTRAINT CK_meeting_participants_att  CHECK (attendance IN ('INVITED','ACCEPTED','DECLINED','ATTENDED','ABSENT'))
);

-- C2. Nhiệm vụ (việc được giao). Trạng thái quá hạn / sắp hạn KHÔNG lưu cứng
--     mà tính khi truy vấn (view v_task_deadline) để luôn đúng theo ngày hiện tại.
--     NEW (mới giao) -> IN_PROGRESS (đang làm) -> DONE (hoàn thành) ; CANCELLED (hủy)
CREATE TABLE dbo.tasks (
    task_id             INT IDENTITY(1,1) NOT NULL,
    task_code           AS ('NV' + RIGHT('000000' + CAST(task_id AS VARCHAR(10)), 6)) PERSISTED,
    title               NVARCHAR(300) NOT NULL,
    description         NVARCHAR(MAX) NULL,
    field_id            INT NOT NULL,
    document_id         INT NULL,               -- nhiệm vụ phát sinh từ văn bản
    meeting_id          INT NULL,               -- nhiệm vụ phát sinh sau cuộc họp
    parent_task_id      INT NULL,               -- việc con / chuyển tiếp
    assigned_by         INT NOT NULL,           -- người giao
    assignee_id         INT NOT NULL,           -- người xử lý chính
    priority            VARCHAR(10) NOT NULL CONSTRAINT DF_tasks_priority DEFAULT ('NORMAL'),
    start_date          DATE NOT NULL CONSTRAINT DF_tasks_start DEFAULT (CAST(SYSDATETIME() AS DATE)),
    due_date            DATE NOT NULL,          -- hạn hiện hành (đổi khi được gia hạn)
    original_due_date   DATE NOT NULL,          -- hạn ban đầu (để báo cáo trễ hạn)
    status              VARCHAR(12) NOT NULL CONSTRAINT DF_tasks_status DEFAULT ('NEW'),
    progress_percent    TINYINT NOT NULL CONSTRAINT DF_tasks_progress DEFAULT (0),
    result_note         NVARCHAR(1000) NULL,
    completed_at        DATETIME2(0) NULL,
    created_at          DATETIME2(0) NOT NULL CONSTRAINT DF_tasks_created DEFAULT (SYSDATETIME()),
    updated_at          DATETIME2(0) NULL,
    row_ver             ROWVERSION,
    CONSTRAINT PK_tasks PRIMARY KEY (task_id),
    CONSTRAINT FK_tasks_fields    FOREIGN KEY (field_id)       REFERENCES dbo.fields(field_id),
    CONSTRAINT FK_tasks_documents FOREIGN KEY (document_id)    REFERENCES dbo.documents(document_id),
    CONSTRAINT FK_tasks_meetings  FOREIGN KEY (meeting_id)     REFERENCES dbo.meetings(meeting_id),
    CONSTRAINT FK_tasks_parent    FOREIGN KEY (parent_task_id) REFERENCES dbo.tasks(task_id),
    CONSTRAINT FK_tasks_assigner  FOREIGN KEY (assigned_by)    REFERENCES dbo.users(user_id),
    CONSTRAINT FK_tasks_assignee  FOREIGN KEY (assignee_id)    REFERENCES dbo.users(user_id),
    CONSTRAINT CK_tasks_priority CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT CK_tasks_status   CHECK (status IN ('NEW','IN_PROGRESS','DONE','CANCELLED')),
    CONSTRAINT CK_tasks_progress CHECK (progress_percent BETWEEN 0 AND 100),
    CONSTRAINT CK_tasks_dates    CHECK (due_date >= start_date AND original_due_date >= start_date),
    CONSTRAINT CK_tasks_done     CHECK (
        (status = 'DONE'  AND completed_at IS NOT NULL AND progress_percent = 100) OR
        (status <> 'DONE' AND completed_at IS NULL))
);
CREATE INDEX IX_tasks_assignee ON dbo.tasks(assignee_id, status, due_date);
CREATE INDEX IX_tasks_field    ON dbo.tasks(field_id, status, due_date);
CREATE INDEX IX_tasks_assigner ON dbo.tasks(assigned_by, status);

-- C3. Lịch sử cập nhật tiến độ nhiệm vụ
CREATE TABLE dbo.task_updates (
    update_id         INT IDENTITY(1,1) NOT NULL,
    task_id           INT NOT NULL,
    updated_by        INT NOT NULL,
    old_status        VARCHAR(12) NULL,
    new_status        VARCHAR(12) NOT NULL,
    progress_percent  TINYINT NOT NULL,
    note              NVARCHAR(1000) NULL,
    created_at        DATETIME2(0) NOT NULL CONSTRAINT DF_task_updates_created DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_task_updates PRIMARY KEY (update_id),
    CONSTRAINT FK_task_updates_tasks FOREIGN KEY (task_id)    REFERENCES dbo.tasks(task_id),
    CONSTRAINT FK_task_updates_users FOREIGN KEY (updated_by) REFERENCES dbo.users(user_id),
    CONSTRAINT CK_task_updates_progress CHECK (progress_percent BETWEEN 0 AND 100)
);
CREATE INDEX IX_task_updates_task ON dbo.task_updates(task_id, created_at);

-- C4. Đề xuất gia hạn (chuyên viên đề xuất, lãnh đạo đồng ý / từ chối)
CREATE TABLE dbo.extension_requests (
    request_id          INT IDENTITY(1,1) NOT NULL,
    task_id             INT NOT NULL,
    requested_by        INT NOT NULL,
    old_due_date        DATE NOT NULL,
    proposed_due_date   DATE NOT NULL,
    reason              NVARCHAR(1000) NOT NULL,
    status              VARCHAR(10) NOT NULL CONSTRAINT DF_extension_requests_status DEFAULT ('PENDING'),
    decided_by          INT NULL,
    decided_at          DATETIME2(0) NULL,
    decision_note       NVARCHAR(1000) NULL,
    via_delegation_id   INT NULL,
    created_at          DATETIME2(0) NOT NULL CONSTRAINT DF_extension_requests_created DEFAULT (SYSDATETIME()),
    row_ver             ROWVERSION,
    CONSTRAINT PK_extension_requests PRIMARY KEY (request_id),
    CONSTRAINT FK_extension_requests_tasks     FOREIGN KEY (task_id)           REFERENCES dbo.tasks(task_id),
    CONSTRAINT FK_extension_requests_requester FOREIGN KEY (requested_by)      REFERENCES dbo.users(user_id),
    CONSTRAINT FK_extension_requests_decider   FOREIGN KEY (decided_by)        REFERENCES dbo.users(user_id),
    CONSTRAINT FK_extension_requests_deleg     FOREIGN KEY (via_delegation_id) REFERENCES dbo.delegations(delegation_id),
    CONSTRAINT CK_extension_requests_status CHECK (status IN ('PENDING','APPROVED','REJECTED','CANCELLED')),
    CONSTRAINT CK_extension_requests_dates  CHECK (proposed_due_date > old_due_date),
    CONSTRAINT CK_extension_requests_reason CHECK (LEN(LTRIM(RTRIM(reason))) > 0),
    CONSTRAINT CK_extension_requests_decided CHECK (
        (status = 'PENDING' AND decided_at IS NULL) OR
        (status = 'CANCELLED') OR
        (status IN ('APPROVED','REJECTED') AND decided_at IS NOT NULL AND decided_by IS NOT NULL)),
    CONSTRAINT CK_extension_requests_reject_note CHECK (
        status <> 'REJECTED' OR LEN(LTRIM(RTRIM(ISNULL(decision_note, N'')))) > 0)
);
-- mỗi nhiệm vụ chỉ có 1 đề xuất gia hạn đang chờ
CREATE UNIQUE INDEX UX_extension_requests_one_pending ON dbo.extension_requests(task_id) WHERE status = 'PENDING';
GO

-- C5. Tệp đính kèm dùng chung (văn bản / phiên bản dự thảo / nhiệm vụ / cuộc họp)
--     Tệp lưu ngoài CSDL (thư mục riêng, không public). CSDL chỉ lưu metadata + đường dẫn nội bộ.
CREATE TABLE dbo.attachments (
    attachment_id   INT IDENTITY(1,1) NOT NULL,
    document_id     INT NULL,
    version_id      INT NULL,
    task_id         INT NULL,
    meeting_id      INT NULL,
    original_name   NVARCHAR(255) NOT NULL,
    stored_name     VARCHAR(100)  NOT NULL,     -- tên ngẫu nhiên (GUID) trên server
    storage_path    NVARCHAR(400) NOT NULL,     -- đường dẫn nội bộ, không trả ra ngoài API
    mime_type       VARCHAR(100)  NOT NULL,
    file_ext        VARCHAR(10)   NOT NULL,
    size_bytes      BIGINT        NOT NULL,
    sha256          CHAR(64)      NULL,
    uploaded_by     INT NOT NULL,
    uploaded_at     DATETIME2(0)  NOT NULL CONSTRAINT DF_attachments_uploaded DEFAULT (SYSDATETIME()),
    is_deleted      BIT NOT NULL CONSTRAINT DF_attachments_deleted DEFAULT (0),
    deleted_at      DATETIME2(0) NULL,
    CONSTRAINT PK_attachments PRIMARY KEY (attachment_id),
    CONSTRAINT UQ_attachments_stored UNIQUE (stored_name),
    CONSTRAINT FK_attachments_documents FOREIGN KEY (document_id) REFERENCES dbo.documents(document_id),
    CONSTRAINT FK_attachments_versions  FOREIGN KEY (version_id)  REFERENCES dbo.document_versions(version_id),
    CONSTRAINT FK_attachments_tasks     FOREIGN KEY (task_id)     REFERENCES dbo.tasks(task_id),
    CONSTRAINT FK_attachments_meetings  FOREIGN KEY (meeting_id)  REFERENCES dbo.meetings(meeting_id),
    CONSTRAINT FK_attachments_users     FOREIGN KEY (uploaded_by) REFERENCES dbo.users(user_id),
    -- mỗi tệp thuộc đúng 1 đối tượng: văn bản (có thể kèm phiên bản) HOẶC nhiệm vụ HOẶC cuộc họp
    CONSTRAINT CK_attachments_owner CHECK (
        (CASE WHEN document_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN task_id     IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN meeting_id  IS NOT NULL THEN 1 ELSE 0 END) = 1),
    CONSTRAINT CK_attachments_version CHECK (version_id IS NULL OR document_id IS NOT NULL),
    -- giới hạn 20 MB; danh sách đuôi cho phép kiểm tra thêm ở backend theo system_settings
    CONSTRAINT CK_attachments_size CHECK (size_bytes > 0 AND size_bytes <= 20971520),
    CONSTRAINT CK_attachments_ext  CHECK (file_ext IN ('pdf','doc','docx','xls','xlsx','jpg','jpeg','png','zip')),
    CONSTRAINT CK_attachments_deleted CHECK ((is_deleted = 1 AND deleted_at IS NOT NULL) OR (is_deleted = 0 AND deleted_at IS NULL))
);
CREATE INDEX IX_attachments_document ON dbo.attachments(document_id) WHERE document_id IS NOT NULL;
CREATE INDEX IX_attachments_task     ON dbo.attachments(task_id)     WHERE task_id IS NOT NULL;
GO

/* =====================================================================
   NHÓM D. THÔNG BÁO, NHẬT KÝ THAO TÁC, BÁO CÁO GIAO BAN  (1.1.3, 2.3.3, 3.2)
   ===================================================================== */

-- D1. Thông báo. dedupe_key để không gửi trùng (VD: 'DUE_SOON:TASK:15:2026-11-16')
CREATE TABLE dbo.notifications (
    notification_id   BIGINT IDENTITY(1,1) NOT NULL,
    recipient_id      INT NOT NULL,
    notif_type        VARCHAR(25) NOT NULL,
    title             NVARCHAR(200) NOT NULL,
    message           NVARCHAR(1000) NULL,
    entity_type       VARCHAR(12) NULL,         -- TASK | DOCUMENT | APPROVAL | EXTENSION | MEETING
    entity_id         INT NULL,
    is_read           BIT NOT NULL CONSTRAINT DF_notifications_read DEFAULT (0),
    read_at           DATETIME2(0) NULL,
    dedupe_key        VARCHAR(100) NULL,
    created_at        DATETIME2(0) NOT NULL CONSTRAINT DF_notifications_created DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_notifications PRIMARY KEY (notification_id),
    CONSTRAINT FK_notifications_users FOREIGN KEY (recipient_id) REFERENCES dbo.users(user_id),
    CONSTRAINT CK_notifications_type CHECK (notif_type IN (
        'TASK_ASSIGNED','TASK_UPDATED','TASK_DUE_SOON','TASK_OVERDUE',
        'DOC_DIRECTED','DOC_HANDLING','DOC_RETURNED','DOC_ISSUED',
        'APPROVAL_PENDING','APPROVAL_DONE',
        'EXTENSION_REQUESTED','EXTENSION_DECIDED',
        'MEETING_INVITED','MEETING_REMINDER','DELEGATION','SYSTEM')),
    CONSTRAINT CK_notifications_entity CHECK (entity_type IS NULL OR entity_type IN ('TASK','DOCUMENT','APPROVAL','EXTENSION','MEETING','DELEGATION')),
    CONSTRAINT CK_notifications_read CHECK ((is_read = 1 AND read_at IS NOT NULL) OR (is_read = 0 AND read_at IS NULL))
);
CREATE INDEX IX_notifications_recipient ON dbo.notifications(recipient_id, is_read, created_at DESC);
CREATE UNIQUE INDEX UX_notifications_dedupe ON dbo.notifications(recipient_id, dedupe_key) WHERE dedupe_key IS NOT NULL;

-- D2. Nhật ký thao tác (Audit log) – chỉ được THÊM, không được sửa/xóa (có trigger chặn)
CREATE TABLE dbo.audit_logs (
    log_id          BIGINT IDENTITY(1,1) NOT NULL,
    user_id         INT NULL,                   -- NULL khi đăng nhập sai username
    active_role_id  INT NULL,
    action          VARCHAR(20) NOT NULL,
    entity_type     VARCHAR(12) NULL,
    entity_id       INT NULL,
    detail          NVARCHAR(MAX) NULL,         -- JSON: giá trị cũ/mới, lý do...
    ip_address      VARCHAR(45) NULL,
    created_at      DATETIME2(0) NOT NULL CONSTRAINT DF_audit_logs_created DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_audit_logs PRIMARY KEY (log_id),
    CONSTRAINT FK_audit_logs_users FOREIGN KEY (user_id)        REFERENCES dbo.users(user_id),
    CONSTRAINT FK_audit_logs_roles FOREIGN KEY (active_role_id) REFERENCES dbo.roles(role_id),
    CONSTRAINT CK_audit_logs_action CHECK (action IN (
        'LOGIN','LOGIN_FAILED','LOGOUT','SWITCH_ROLE',
        'CREATE','UPDATE','DELETE','VIEW','DOWNLOAD','UPLOAD',
        'REGISTER','DIRECT','SUBMIT','APPROVE','RETURN','FORWARD','ISSUE',
        'ASSIGN','UPDATE_PROGRESS','EXT_REQUEST','EXT_APPROVE','EXT_REJECT',
        'DELEGATE_ON','DELEGATE_OFF','REPORT','ACCESS_DENIED')),
    CONSTRAINT CK_audit_logs_detail CHECK (detail IS NULL OR ISJSON(detail) = 1)
);
CREATE INDEX IX_audit_logs_entity ON dbo.audit_logs(entity_type, entity_id, created_at);
CREATE INDEX IX_audit_logs_user   ON dbo.audit_logs(user_id, created_at);
GO

CREATE OR ALTER TRIGGER dbo.tr_audit_logs_readonly
ON dbo.audit_logs
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 50001, N'Nhật ký thao tác chỉ được thêm mới, không được sửa hoặc xóa.', 1;
END;
GO

-- D3. Báo cáo giao ban (lưu "ảnh chụp" số liệu tại thời điểm chốt để đối chiếu về sau)
CREATE TABLE dbo.briefing_reports (
    report_id     INT IDENTITY(1,1) NOT NULL,
    title         NVARCHAR(300) NOT NULL,
    period_from   DATE NOT NULL,
    period_to     DATE NOT NULL,
    field_id      INT NULL,                     -- NULL = toàn phòng
    status        VARCHAR(10) NOT NULL CONSTRAINT DF_briefing_reports_status DEFAULT ('DRAFT'),
    note          NVARCHAR(MAX) NULL,           -- nhận xét, kiến nghị của Trưởng phòng
    created_by    INT NOT NULL,
    created_at    DATETIME2(0) NOT NULL CONSTRAINT DF_briefing_reports_created DEFAULT (SYSDATETIME()),
    finalized_at  DATETIME2(0) NULL,
    CONSTRAINT PK_briefing_reports PRIMARY KEY (report_id),
    CONSTRAINT FK_briefing_reports_fields FOREIGN KEY (field_id)   REFERENCES dbo.fields(field_id),
    CONSTRAINT FK_briefing_reports_users  FOREIGN KEY (created_by) REFERENCES dbo.users(user_id),
    CONSTRAINT CK_briefing_reports_period CHECK (period_to >= period_from),
    CONSTRAINT CK_briefing_reports_status CHECK (status IN ('DRAFT','FINAL')),
    CONSTRAINT CK_briefing_reports_final  CHECK ((status = 'FINAL' AND finalized_at IS NOT NULL) OR (status = 'DRAFT' AND finalized_at IS NULL))
);

CREATE TABLE dbo.briefing_report_lines (
    line_id             INT IDENTITY(1,1) NOT NULL,
    report_id           INT NOT NULL,
    field_id            INT NOT NULL,
    assignee_id         INT NULL,               -- NULL = dòng tổng của lĩnh vực
    tasks_total         INT NOT NULL CONSTRAINT DF_brl_total    DEFAULT (0),
    tasks_done_on_time  INT NOT NULL CONSTRAINT DF_brl_ontime   DEFAULT (0),
    tasks_done_late     INT NOT NULL CONSTRAINT DF_brl_late     DEFAULT (0),
    tasks_in_progress   INT NOT NULL CONSTRAINT DF_brl_progress DEFAULT (0),
    tasks_overdue       INT NOT NULL CONSTRAINT DF_brl_overdue  DEFAULT (0),
    pending_approvals   INT NOT NULL CONSTRAINT DF_brl_pending  DEFAULT (0),
    docs_in             INT NOT NULL CONSTRAINT DF_brl_docs_in  DEFAULT (0),
    docs_out            INT NOT NULL CONSTRAINT DF_brl_docs_out DEFAULT (0),
    CONSTRAINT PK_briefing_report_lines PRIMARY KEY (line_id),
    CONSTRAINT FK_brl_reports FOREIGN KEY (report_id)   REFERENCES dbo.briefing_reports(report_id) ON DELETE CASCADE,
    CONSTRAINT FK_brl_fields  FOREIGN KEY (field_id)    REFERENCES dbo.fields(field_id),
    CONSTRAINT FK_brl_users   FOREIGN KEY (assignee_id) REFERENCES dbo.users(user_id)
);
CREATE UNIQUE INDEX UX_brl_report_field_user ON dbo.briefing_report_lines(report_id, field_id, assignee_id);
GO

PRINT N'01_schema.sql: tạo xong 30 bảng của CSDL QLVHXH.';
GO
