/* =====================================================================
   File   : 02_programmability.sql – Hàm, view, thủ tục lưu trữ
   Phục vụ: 1.2.3 (kiểm tra quyền), 1.3.1 (thống kê Hôm nay, hạn xử lý),
            1.4.x (việc của tôi), 2.1.x (sổ, tra cứu, cấp số), 2.2.x (trình ký),
            2.3.x (chỉ đạo, gia hạn, thông báo, nhật ký), 3.2 (giao ban)
   Quy ước mã lỗi THROW (backend map sang HTTP):
       50400 dữ liệu không hợp lệ (400)   50403 không có quyền (403)
       50404 không tìm thấy (404)         50409 xung đột trạng thái / đã xử lý (409)
   ===================================================================== */
USE QLVHXH;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* =====================================================================
   PHẦN 1. HÀM TIỆN ÍCH
   ===================================================================== */

-- 1.1 Đọc tham số kiểu số từ system_settings
CREATE OR ALTER FUNCTION dbo.fn_setting_int (@key VARCHAR(50))
RETURNS INT
AS
BEGIN
    RETURN (SELECT TRY_CAST(setting_value AS INT) FROM dbo.system_settings WHERE setting_key = @key);
END;
GO

-- 1.2 Số ngày làm việc giữa 2 ngày theo bảng calendar_days.
--     @to >= @from : số ngày làm việc trong khoảng (@from, @to]  -> "còn N ngày làm việc"
--     @to <  @from : số âm = số ngày làm việc đã trễ
--     VD: hôm nay thứ Hai, hạn thứ Tư -> 2 ; hạn hôm nay -> 0
CREATE OR ALTER FUNCTION dbo.fn_working_days_between (@from DATE, @to DATE)
RETURNS INT
AS
BEGIN
    DECLARE @n INT;
    IF @from IS NULL OR @to IS NULL RETURN NULL;
    -- lịch chưa phủ tới ngày cần tính -> trả NULL (không đoán), view sẽ xếp vào ON_TRACK
    IF NOT EXISTS (SELECT 1 FROM dbo.calendar_days WHERE cal_date = @from)
       OR NOT EXISTS (SELECT 1 FROM dbo.calendar_days WHERE cal_date = @to)
        RETURN NULL;
    IF @to >= @from
        SELECT @n = COUNT(*) FROM dbo.calendar_days
        WHERE cal_date > @from AND cal_date <= @to AND is_working_day = 1;
    ELSE
        SELECT @n = -COUNT(*) FROM dbo.calendar_days
        WHERE cal_date > @to AND cal_date <= @from AND is_working_day = 1;
    RETURN @n;
END;
GO

-- 1.3 Sinh lịch một năm: thứ Bảy, Chủ nhật là ngày nghỉ. Ngày lễ/làm bù cập nhật riêng.
CREATE OR ALTER PROCEDURE dbo.sp_generate_calendar
    @year INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @d DATE = DATEFROMPARTS(@year, 1, 1);
    DECLARE @end DATE = DATEFROMPARTS(@year, 12, 31);
    DECLARE @wd INT;      -- 0 = thứ Hai ... 5 = thứ Bảy, 6 = Chủ nhật (không phụ thuộc SET DATEFIRST)
    WHILE @d <= @end
    BEGIN
        SET @wd = DATEDIFF(DAY, CAST('19000101' AS DATE), @d) % 7;
        IF NOT EXISTS (SELECT 1 FROM dbo.calendar_days WHERE cal_date = @d)
            INSERT INTO dbo.calendar_days (cal_date, is_working_day, note)
            VALUES (@d,
                    CASE WHEN @wd IN (5, 6) THEN 0 ELSE 1 END,
                    CASE @wd WHEN 5 THEN N'Thứ Bảy' WHEN 6 THEN N'Chủ nhật' END);
        SET @d = DATEADD(DAY, 1, @d);
    END;
END;
GO

-- 1.4 Ghi nhật ký thao tác
CREATE OR ALTER PROCEDURE dbo.sp_write_audit
    @user_id      INT,
    @role_id      INT,
    @action       VARCHAR(20),
    @entity_type  VARCHAR(12) = NULL,
    @entity_id    INT = NULL,
    @detail       NVARCHAR(MAX) = NULL,
    @ip_address   VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.audit_logs (user_id, active_role_id, action, entity_type, entity_id, detail, ip_address)
    VALUES (@user_id, @role_id, @action, @entity_type, @entity_id, @detail, @ip_address);
END;
GO

-- 1.5 Tạo thông báo (bỏ qua nếu trùng dedupe_key)
CREATE OR ALTER PROCEDURE dbo.sp_notify
    @recipient_id INT,
    @notif_type   VARCHAR(25),
    @title        NVARCHAR(200),
    @message      NVARCHAR(1000) = NULL,
    @entity_type  VARCHAR(12) = NULL,
    @entity_id    INT = NULL,
    @dedupe_key   VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @dedupe_key IS NOT NULL AND EXISTS (
        SELECT 1 FROM dbo.notifications WHERE recipient_id = @recipient_id AND dedupe_key = @dedupe_key)
        RETURN;
    INSERT INTO dbo.notifications (recipient_id, notif_type, title, message, entity_type, entity_id, dedupe_key)
    VALUES (@recipient_id, @notif_type, @title, @message, @entity_type, @entity_id, @dedupe_key);
END;
GO

/* =====================================================================
   PHẦN 2. NGỮ CẢNH NGƯỜI DÙNG, ỦY QUYỀN, KIỂM TRA QUYỀN  (1.2.3)
   ===================================================================== */

-- 2.1 Các ủy quyền đang có hiệu lực mà @to_user_id được nhận tại thời điểm @at
CREATE OR ALTER FUNCTION dbo.fn_active_delegations (@to_user_id INT, @at DATETIME2(0))
RETURNS TABLE
AS
RETURN
    SELECT d.delegation_id, d.from_user_id, d.can_sign, d.can_approve_extension, d.can_view_confidential,
           d.valid_from, d.valid_to
    FROM dbo.delegations d
    WHERE d.to_user_id = @to_user_id
      AND d.is_active = 1
      AND d.revoked_at IS NULL
      AND @at >= d.valid_from
      AND @at <  d.valid_to;
GO

-- 2.2 Ngữ cảnh (user, vai trò đang hoạt động). Không trả dòng nào nếu user không giữ vai trò đó
--     hoặc tài khoản bị khóa -> mọi hàm dữ liệu phía sau cũng trả rỗng (an toàn mặc định).
CREATE OR ALTER FUNCTION dbo.fn_user_context (@user_id INT, @role_id INT)
RETURNS TABLE
AS
RETURN
    SELECT u.user_id, u.full_name, r.role_id, r.code AS role_code, r.name AS role_name,
           r.role_level, r.rank_no, r.field_id
    FROM dbo.users u
    JOIN dbo.user_roles ur ON ur.user_id = u.user_id
    JOIN dbo.roles r       ON r.role_id  = ur.role_id
    WHERE u.user_id = @user_id
      AND r.role_id = @role_id
      AND u.is_active = 1;
GO

-- 2.3 Kiểm tra quyền: middleware API gọi trước mỗi thao tác. Trả 1 = được phép.
--     Quyền "U" (requires_delegation = 1) chỉ hợp lệ khi có ủy quyền đúng loại còn hiệu lực.
CREATE OR ALTER FUNCTION dbo.fn_has_permission
    (@user_id INT, @role_id INT, @function_code VARCHAR(40), @action CHAR(1))
RETURNS BIT
AS
BEGIN
    DECLARE @ok BIT = 0;
    DECLARE @now DATETIME2(0) = SYSDATETIME();
    IF EXISTS (
        SELECT 1
        FROM dbo.users u
        JOIN dbo.user_roles ur       ON ur.user_id = u.user_id
        JOIN dbo.role_permissions rp ON rp.role_id = ur.role_id
        JOIN dbo.app_functions f     ON f.function_id = rp.function_id
        WHERE u.user_id = @user_id
          AND u.is_active = 1
          AND ur.role_id = @role_id
          AND f.code = @function_code
          AND rp.action = @action
          AND ( rp.requires_delegation = 0
                OR EXISTS (
                    SELECT 1 FROM dbo.fn_active_delegations(@user_id, @now) d
                    WHERE (f.code IN ('F08_PENDING_APPROVAL','F15_DRAFT_APPROVE','F16_DOCUMENT_ISSUE') AND d.can_sign = 1)
                       OR (f.code = 'F19_EXTENSION_DECIDE'  AND d.can_approve_extension = 1)
                       OR (f.code = 'F11_CONFIDENTIAL_FILE' AND d.can_view_confidential = 1)
                       OR (f.code NOT IN ('F08_PENDING_APPROVAL','F15_DRAFT_APPROVE','F16_DOCUMENT_ISSUE',
                                          'F19_EXTENSION_DECIDE','F11_CONFIDENTIAL_FILE'))))
    )
        SET @ok = 1;
    RETURN @ok;
END;
GO

-- 2.4 Danh sách quyền đang dùng được của (user, vai trò) -> frontend dựng menu / ẩn nút
CREATE OR ALTER FUNCTION dbo.fn_permissions_of (@user_id INT, @role_id INT)
RETURNS TABLE
AS
RETURN
    SELECT f.code AS function_code, f.name AS function_name, f.group_code, rp.action, rp.scope,
           rp.requires_delegation,
           dbo.fn_has_permission(@user_id, @role_id, f.code, rp.action) AS is_usable_now
    FROM dbo.user_roles ur
    JOIN dbo.role_permissions rp ON rp.role_id = ur.role_id
    JOIN dbo.app_functions f     ON f.function_id = rp.function_id
    WHERE ur.user_id = @user_id AND ur.role_id = @role_id;
GO

-- 2.5 Đổi vai trò trong phiên: chỉ sang vai trò đã được cấp (FK kép cũng chặn ở mức dữ liệu)
CREATE OR ALTER PROCEDURE dbo.sp_switch_role
    @session_id   UNIQUEIDENTIFIER,
    @new_role_id  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @user_id INT, @old_role INT;
    SELECT @user_id = s.user_id, @old_role = s.active_role_id
    FROM dbo.user_sessions s
    JOIN dbo.users u ON u.user_id = s.user_id AND u.is_active = 1
    WHERE s.session_id = @session_id AND s.revoked_at IS NULL AND s.expires_at > SYSDATETIME();
    IF @user_id IS NULL
        THROW 50403, N'Phiên đăng nhập không hợp lệ hoặc đã hết hạn.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.user_roles WHERE user_id = @user_id AND role_id = @new_role_id)
        THROW 50403, N'Vai trò này không nằm trong danh sách được cấp cho tài khoản.', 1;

    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.user_sessions SET active_role_id = @new_role_id, last_seen_at = SYSDATETIME()
        WHERE session_id = @session_id;
        DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"from_role_id":', @old_role, N',"to_role_id":', @new_role_id, N'}');
        EXEC dbo.sp_write_audit @user_id, @new_role_id, 'SWITCH_ROLE', NULL, NULL, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

/* =====================================================================
   PHẦN 3. HẠN XỬ LÝ, PHẠM VI DỮ LIỆU  (1.3.1, 1.4.2)
   ===================================================================== */

-- 3.1 Trạng thái hạn của từng nhiệm vụ tại ngày @today. Mỗi nhiệm vụ rơi vào ĐÚNG 1 nhóm
--     (DONE / CANCELLED / OVERDUE / DUE_SOON / ON_TRACK) nên không bị đếm trùng.
--     - OVERDUE : chưa xong và due_date < hôm nay
--     - DUE_SOON: chưa xong, chưa quá hạn, còn <= DUE_SOON_WORKING_DAYS ngày làm việc
CREATE OR ALTER FUNCTION dbo.fn_task_deadline (@today DATE)
RETURNS TABLE
AS
RETURN
    SELECT t.task_id, t.task_code, t.title, t.field_id, t.document_id, t.meeting_id,
           t.assigned_by, t.assignee_id, t.priority, t.status, t.progress_percent,
           t.start_date, t.due_date, t.original_due_date, t.completed_at,
           dbo.fn_working_days_between(@today, t.due_date) AS working_days_left,
           CASE
               WHEN t.status IN ('DONE','CANCELLED') THEN t.status
               WHEN t.due_date < @today THEN 'OVERDUE'
               WHEN dbo.fn_working_days_between(@today, t.due_date) <= s.due_soon_days THEN 'DUE_SOON'
               ELSE 'ON_TRACK'
           END AS deadline_state,
           CASE WHEN t.status = 'DONE' AND CAST(t.completed_at AS DATE) > t.due_date THEN 1 ELSE 0 END AS is_done_late,
           CASE WHEN t.due_date > t.original_due_date THEN 1 ELSE 0 END AS was_extended
    FROM dbo.tasks t
    CROSS JOIN (SELECT ISNULL(dbo.fn_setting_int('DUE_SOON_WORKING_DAYS'), 2) AS due_soon_days) s;
GO

CREATE OR ALTER VIEW dbo.v_task_deadline
AS
    SELECT * FROM dbo.fn_task_deadline(CAST(SYSDATETIME() AS DATE));
GO

-- 3.2 Nhiệm vụ người dùng được thấy (lãnh đạo: cả phòng; chuyên viên: việc của mình)
CREATE OR ALTER FUNCTION dbo.fn_visible_tasks (@user_id INT, @role_id INT, @today DATE)
RETURNS TABLE
AS
RETURN
    SELECT td.*, f.name AS field_name,
           ua.full_name AS assignee_name, ub.full_name AS assigned_by_name,
           CASE WHEN td.assignee_id = @user_id THEN 1 ELSE 0 END AS is_mine
    FROM dbo.fn_task_deadline(@today) td
    CROSS JOIN dbo.fn_user_context(@user_id, @role_id) c
    JOIN dbo.fields f ON f.field_id = td.field_id
    JOIN dbo.users ua ON ua.user_id = td.assignee_id
    JOIN dbo.users ub ON ub.user_id = td.assigned_by
    WHERE c.role_level = 'LEADER'
       OR td.assignee_id = @user_id;
GO

-- 3.3 Văn bản người dùng được thấy + có được tải tệp hay không (ma trận dòng 9–11)
--   * Văn bản thường : lãnh đạo xem tất cả; CV Nội vụ (đầu mối văn thư) xem tất cả;
--                      CV khác xem văn bản thuộc lĩnh vực mình hoặc có liên quan.
--   * Văn bản mật    : chỉ PCT, TP, người có liên quan trực tiếp (được giao/cấp quyền/được trình),
--                      PTP chỉ khi có ủy quyền can_view_confidential.
--   * Dự thảo chưa trình (DRAFT/RETURNED/CANCELLED): chỉ người soạn, TP, PTP.
CREATE OR ALTER FUNCTION dbo.fn_visible_documents (@user_id INT, @role_id INT)
RETURNS TABLE
AS
RETURN
    SELECT d.document_id,
           CAST(CASE
                    WHEN d.security_level = 'NORMAL' THEN 1
                    WHEN c.role_code IN ('PCT','TP') THEN 1
                    WHEN rel.is_related = 1 THEN 1
                    WHEN c.role_code = 'PTP' AND dl.can_conf = 1 THEN 1
                    ELSE 0
                END AS BIT) AS can_download,
           ISNULL(rel.is_related, 0) AS is_related
    FROM dbo.documents d
    CROSS JOIN dbo.fn_user_context(@user_id, @role_id) c
    CROSS JOIN (SELECT MAX(CAST(can_view_confidential AS INT)) AS can_conf
                FROM dbo.fn_active_delegations(@user_id, SYSDATETIME())) dl
    OUTER APPLY (
        SELECT 1 AS is_related          -- SELECT không FROM: trả 1 dòng nếu điều kiện đúng
        WHERE d.created_by = @user_id
           OR EXISTS (SELECT 1 FROM dbo.document_access_grants g
                      WHERE g.document_id = d.document_id AND g.user_id = @user_id
                        AND (g.expires_at IS NULL OR g.expires_at > SYSDATETIME()))
           OR EXISTS (SELECT 1 FROM dbo.document_handlings h
                      WHERE h.document_id = d.document_id AND h.to_user_id = @user_id AND h.status <> 'RECALLED')
           OR EXISTS (SELECT 1 FROM dbo.approval_requests a
                      WHERE a.document_id = d.document_id AND a.approver_id = @user_id)
           OR EXISTS (SELECT 1 FROM dbo.tasks t
                      WHERE t.document_id = d.document_id AND t.assignee_id = @user_id)
           OR EXISTS (SELECT 1 FROM dbo.document_recipients r
                      WHERE r.document_id = d.document_id AND r.user_id = @user_id)
    ) rel
    WHERE
        -- dự thảo chưa trình chỉ người soạn và lãnh đạo phòng thấy
        NOT (d.direction = 'OUT' AND d.status IN ('DRAFT','RETURNED','CANCELLED')
             AND d.created_by <> @user_id AND c.role_code NOT IN ('TP','PTP')
             AND ISNULL(rel.is_related, 0) = 0)
        AND (
            (d.security_level = 'NORMAL'
                AND (c.role_level = 'LEADER' OR c.role_code = 'CV_NV'
                     OR d.field_id = c.field_id OR rel.is_related = 1))
            OR
            (d.security_level <> 'NORMAL'
                AND (c.role_code IN ('PCT','TP') OR rel.is_related = 1
                     OR (c.role_code = 'PTP' AND dl.can_conf = 1)))
        );
GO

/* =====================================================================
   PHẦN 4. MÀN HÌNH HÔM NAY  (task 1.3.1)
   ===================================================================== */

-- 4.1 Số liệu các thẻ Hôm nay. Thẻ trả NULL = vai trò không có thẻ đó (frontend ẩn thẻ).
CREATE OR ALTER FUNCTION dbo.fn_today_cards (@user_id INT, @role_id INT, @today DATE)
RETURNS TABLE
AS
RETURN
WITH ctx AS (
    SELECT role_code, role_level FROM dbo.fn_user_context(@user_id, @role_id)
),
tk AS (
    SELECT td.task_id, td.deadline_state
    FROM dbo.fn_task_deadline(@today) td
    CROSS JOIN ctx
    WHERE ctx.role_level = 'LEADER' OR td.assignee_id = @user_id
)
SELECT
    @user_id AS user_id,
    ctx.role_code,
    CASE WHEN ctx.role_level = 'LEADER' THEN 'DEPARTMENT' ELSE 'PERSONAL' END AS scope_type,
    -- Hồ sơ chờ ký: lượt trình đang chờ tôi, hoặc chờ người đã ủy quyền ký cho tôi
    CASE WHEN dbo.fn_has_permission(@user_id, @role_id, 'F08_PENDING_APPROVAL', 'X') = 1 THEN
        (SELECT COUNT(*) FROM dbo.approval_requests a
         WHERE a.status = 'PENDING'
           AND a.submitted_by <> @user_id          -- không tự duyệt bản mình trình
           AND (a.approver_id = @user_id
                OR a.approver_id IN (SELECT dl.from_user_id
                                     FROM dbo.fn_active_delegations(@user_id, SYSDATETIME()) dl
                                     WHERE dl.can_sign = 1)))
    END AS pending_sign,
    (SELECT COUNT(*) FROM tk WHERE tk.deadline_state = 'OVERDUE')  AS overdue_tasks,
    (SELECT COUNT(*) FROM tk WHERE tk.deadline_state = 'DUE_SOON') AS due_soon_tasks,
    -- Văn bản cần chỉ đạo (chỉ lãnh đạo)
    CASE WHEN ctx.role_level = 'LEADER' THEN
        (SELECT COUNT(DISTINCT h.document_id) FROM dbo.document_handlings h
         WHERE h.to_user_id = @user_id AND h.handling_type = 'DIRECTION' AND h.status = 'PENDING')
    END AS need_direction_docs,
    -- Hồ sơ chờ tôi: văn bản được giao xử lý + dự thảo của tôi bị trả lại
    --               + (riêng CV Nội vụ) văn bản đến chưa vào sổ. UNION để không đếm trùng.
    (SELECT COUNT(*) FROM (
        SELECT h.document_id FROM dbo.document_handlings h
        WHERE h.to_user_id = @user_id AND h.status = 'PENDING' AND h.handling_type IN ('MAIN','COORDINATE')
        UNION
        SELECT d.document_id FROM dbo.documents d
        WHERE d.direction = 'OUT' AND d.status = 'RETURNED' AND d.created_by = @user_id
        UNION
        SELECT d.document_id FROM dbo.documents d
        WHERE ctx.role_code = 'CV_NV' AND d.direction = 'IN' AND d.status = 'RECEIVED'
    ) x) AS waiting_me,
    -- Đề xuất gia hạn chờ quyết định
    CASE WHEN dbo.fn_has_permission(@user_id, @role_id, 'F19_EXTENSION_DECIDE', 'D') = 1 THEN
        (SELECT COUNT(*) FROM dbo.extension_requests e
         JOIN dbo.tasks t ON t.task_id = e.task_id
         WHERE e.status = 'PENDING'
           AND (ctx.role_code IN ('TP','PTP') OR t.assigned_by = @user_id))
    END AS pending_extensions,
    (SELECT COUNT(*) FROM dbo.tasks t
     WHERE t.assignee_id = @user_id AND t.status IN ('NEW','IN_PROGRESS')) AS my_open_tasks,
    (SELECT COUNT(*) FROM dbo.notifications n
     WHERE n.recipient_id = @user_id AND n.is_read = 0) AS unread_notifications
FROM ctx;
GO

-- 4.2 Danh sách "Hồ sơ chờ tôi" (chi tiết cho thẻ waiting_me)
CREATE OR ALTER FUNCTION dbo.fn_waiting_documents (@user_id INT, @role_id INT)
RETURNS TABLE
AS
RETURN
    -- mỗi văn bản chỉ 1 dòng (khớp với số đếm của thẻ waiting_me); ưu tiên lý do có pri nhỏ hơn
    SELECT y.document_id, y.reason_code, y.handling_id, y.due_date, y.instruction,
           d.direction, d.symbol, d.book_number, d.summary, d.status, d.urgency, d.security_level
    FROM (
        SELECT x.*, ROW_NUMBER() OVER (PARTITION BY x.document_id ORDER BY x.pri, x.handling_id) AS rn
        FROM (
            SELECT h.document_id,
                   CASE h.handling_type WHEN 'MAIN' THEN 'HANDLE_MAIN' ELSE 'HANDLE_COORDINATE' END AS reason_code,
                   h.handling_id, h.due_date, h.instruction,
                   CASE h.handling_type WHEN 'MAIN' THEN 1 ELSE 2 END AS pri
            FROM dbo.document_handlings h
            WHERE h.to_user_id = @user_id AND h.status = 'PENDING' AND h.handling_type IN ('MAIN','COORDINATE')
            UNION ALL
            SELECT d.document_id, 'DRAFT_RETURNED', NULL, d.due_date, NULL, 0
            FROM dbo.documents d
            WHERE d.direction = 'OUT' AND d.status = 'RETURNED' AND d.created_by = @user_id
            UNION ALL
            SELECT d.document_id, 'TO_REGISTER', NULL, d.due_date, NULL, 0
            FROM dbo.documents d
            CROSS JOIN dbo.fn_user_context(@user_id, @role_id) c
            WHERE c.role_code = 'CV_NV' AND d.direction = 'IN' AND d.status = 'RECEIVED'
        ) x
    ) y
    JOIN dbo.documents d ON d.document_id = y.document_id
    WHERE y.rn = 1;
GO

/* =====================================================================
   PHẦN 5. SỔ VĂN BẢN, TRA CỨU, CẤP SỐ  (task 2.1.2)
   ===================================================================== */

-- 5.1 Sổ đăng ký văn bản đến (cột theo mẫu sổ văn thư; tham khảo Nghị định 30/2020/NĐ-CP)
CREATE OR ALTER VIEW dbo.v_incoming_register
AS
    SELECT b.book_year, b.code AS book_code, d.book_number AS so_den,
           CAST(d.received_at AS DATE) AS ngay_den,
           o.name AS tac_gia, d.symbol AS so_ky_hieu, d.issued_date AS ngay_van_ban,
           dt.name + N' – ' + d.summary AS ten_loai_trich_yeu,
           f.name AS linh_vuc, d.security_level, d.urgency, d.status, d.due_date AS han_xu_ly,
           (SELECT STRING_AGG(u.full_name, N', ')
            FROM dbo.document_handlings h JOIN dbo.users u ON u.user_id = h.to_user_id
            WHERE h.document_id = d.document_id AND h.handling_type = 'MAIN') AS nguoi_xu_ly,
           d.document_id
    FROM dbo.documents d
    JOIN dbo.document_books b  ON b.book_id = d.book_id
    JOIN dbo.document_types dt ON dt.doc_type_id = d.doc_type_id
    JOIN dbo.fields f          ON f.field_id = d.field_id
    LEFT JOIN dbo.organizations o ON o.org_id = d.issuing_org_id
    WHERE d.direction = 'IN' AND d.book_number IS NOT NULL;
GO

-- 5.2 Sổ đăng ký văn bản đi
CREATE OR ALTER VIEW dbo.v_outgoing_register
AS
    SELECT b.book_year, b.code AS book_code, d.book_number AS so_di, d.symbol AS so_ky_hieu,
           d.issued_date AS ngay_van_ban, dt.name + N' – ' + d.summary AS ten_loai_trich_yeu,
           us.full_name AS nguoi_ky,
           (SELECT STRING_AGG(COALESCE(o.name, ur.full_name, r.note), N'; ')
            FROM dbo.document_recipients r
            LEFT JOIN dbo.organizations o ON o.org_id = r.org_id
            LEFT JOIN dbo.users ur ON ur.user_id = r.user_id
            WHERE r.document_id = d.document_id) AS noi_nhan,
           f.name AS linh_vuc, d.security_level, d.issued_at, d.document_id
    FROM dbo.documents d
    JOIN dbo.document_books b  ON b.book_id = d.book_id
    JOIN dbo.document_types dt ON dt.doc_type_id = d.doc_type_id
    JOIN dbo.fields f          ON f.field_id = d.field_id
    LEFT JOIN dbo.users us     ON us.user_id = d.signed_by
    WHERE d.direction = 'OUT' AND d.status = 'ISSUED';
GO

-- 5.3 Tra cứu văn bản: lọc kết hợp, không phân biệt dấu, khoảng ngày gồm cả 2 mốc, phân trang.
--     Kết quả đã lọc theo quyền (fn_visible_documents) nên API không thể lộ văn bản ngoài quyền.
CREATE OR ALTER PROCEDURE dbo.sp_search_documents
    @user_id      INT,
    @role_id      INT,
    @direction    CHAR(3)       = NULL,   -- IN | OUT | NULL = cả hai
    @keyword      NVARCHAR(200) = NULL,   -- tìm trong trích yếu và số ký hiệu
    @book_number  INT           = NULL,
    @org_id       INT           = NULL,
    @field_id     INT           = NULL,
    @doc_type_id  INT           = NULL,
    @status       VARCHAR(20)   = NULL,
    @date_from    DATE          = NULL,   -- ngày đến (VB đến) / ngày văn bản (VB đi)
    @date_to      DATE          = NULL,
    @page         INT           = 1,
    @page_size    INT           = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F10_DOCUMENT_SEARCH', 'X') = 0
        THROW 50403, N'Bạn không có quyền tra cứu văn bản.', 1;
    IF @date_from IS NOT NULL AND @date_to IS NOT NULL AND @date_from > @date_to
        THROW 50400, N'Ngày bắt đầu phải nhỏ hơn hoặc bằng ngày kết thúc.', 1;
    IF @page IS NULL OR @page < 1 SET @page = 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 100 SET @page_size = 20;

    -- chuẩn hóa từ khóa: bỏ khoảng trắng thừa, đ -> d, thoát ký tự đặc biệt của LIKE
    DECLARE @kw NVARCHAR(800) = NULLIF(LTRIM(RTRIM(@keyword)), N'');   -- thoát ký tự có thể làm chuỗi dài gấp 3
    IF @kw IS NOT NULL
        SET @kw = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@kw, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]'), N'đ', N'd'), N'Đ', N'D');

    SELECT d.document_id, d.direction, b.code AS book_code, d.book_number, d.symbol,
           dt.name AS doc_type_name, d.summary, f.name AS field_name, o.name AS org_name,
           d.issued_date, d.received_at, d.security_level, d.urgency, d.status, d.due_date,
           v.can_download,
           COUNT(*) OVER () AS total_rows
    FROM dbo.documents d
    JOIN dbo.fn_visible_documents(@user_id, @role_id) v ON v.document_id = d.document_id
    JOIN dbo.document_types dt ON dt.doc_type_id = d.doc_type_id
    JOIN dbo.fields f          ON f.field_id = d.field_id
    LEFT JOIN dbo.document_books b ON b.book_id = d.book_id
    LEFT JOIN dbo.organizations o  ON o.org_id = d.issuing_org_id
    WHERE (@direction   IS NULL OR d.direction   = @direction)
      AND (@book_number IS NULL OR d.book_number = @book_number)
      AND (@org_id      IS NULL OR d.issuing_org_id = @org_id)
      AND (@field_id    IS NULL OR d.field_id    = @field_id)
      AND (@doc_type_id IS NULL OR d.doc_type_id = @doc_type_id)
      AND (@status      IS NULL OR d.status      = @status)
      AND (@date_from   IS NULL OR COALESCE(CAST(d.received_at AS DATE), d.issued_date, CAST(d.created_at AS DATE)) >= @date_from)
      AND (@date_to     IS NULL OR COALESCE(CAST(d.received_at AS DATE), d.issued_date, CAST(d.created_at AS DATE)) <= @date_to)
      AND (@kw IS NULL
           OR REPLACE(REPLACE(d.summary, N'đ', N'd'), N'Đ', N'D') COLLATE Latin1_General_100_CI_AI
                LIKE N'%' + @kw + N'%'
           OR REPLACE(REPLACE(ISNULL(d.symbol, N''), N'đ', N'd'), N'Đ', N'D') COLLATE Latin1_General_100_CI_AI
                LIKE N'%' + @kw + N'%')
    ORDER BY COALESCE(d.received_at, CAST(d.issued_date AS DATETIME2(0)), d.created_at) DESC, d.document_id DESC
    OFFSET (@page - 1) * @page_size ROWS FETCH NEXT @page_size ROWS ONLY
    OPTION (RECOMPILE);
END;
GO

-- 5.4 Cấp số tiếp theo của sổ (UPDATE nguyên tử -> 2 người vào sổ cùng lúc không bị trùng số).
--     Phải được gọi BÊN TRONG transaction của thủ tục gọi nó.
CREATE OR ALTER PROCEDURE dbo.sp_next_book_number
    @book_id  INT,
    @number   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @number = NULL;
    UPDATE dbo.document_books
    SET @number = last_number = last_number + 1
    WHERE book_id = @book_id AND is_active = 1;
    IF @number IS NULL
        THROW 50404, N'Sổ văn bản không tồn tại hoặc đã khóa sổ.', 1;
END;
GO

-- 5.5 Vào sổ văn bản đến (CV Nội vụ hoặc Trưởng phòng)
CREATE OR ALTER PROCEDURE dbo.sp_register_incoming
    @user_id      INT,
    @role_id      INT,
    @document_id  INT,
    @book_id      INT,
    @book_number  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F09_INCOMING_REGISTER', 'S') = 0
       AND dbo.fn_has_permission(@user_id, @role_id, 'F09_INCOMING_REGISTER', 'C') = 0
        THROW 50403, N'Chỉ CV Nội vụ (đầu mối) hoặc Trưởng phòng được vào sổ văn bản đến.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.documents WHERE document_id = @document_id AND direction = 'IN')
        THROW 50404, N'Không tìm thấy văn bản đến.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.documents WHERE document_id = @document_id AND status = 'RECEIVED')
        THROW 50409, N'Văn bản đã được vào sổ trước đó.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.document_books b JOIN dbo.documents d ON d.document_id = @document_id
                   WHERE b.book_id = @book_id AND b.direction = 'IN'
                     AND b.book_year = YEAR(ISNULL(d.received_at, SYSDATETIME())))
        THROW 50400, N'Sổ không phải sổ văn bản đến của năm nhận văn bản.', 1;

    BEGIN TRY
        BEGIN TRAN;
        -- khóa dòng văn bản, chỉ vào sổ khi đang ở trạng thái RECEIVED
        IF NOT EXISTS (SELECT 1 FROM dbo.documents WITH (UPDLOCK, ROWLOCK)
                       WHERE document_id = @document_id AND status = 'RECEIVED')
            THROW 50409, N'Văn bản đã được vào sổ trước đó.', 1;
        EXEC dbo.sp_next_book_number @book_id, @book_number OUTPUT;
        UPDATE dbo.documents
        SET book_id = @book_id, book_number = @book_number, status = 'REGISTERED',
            received_at = ISNULL(received_at, SYSDATETIME()),
            updated_by = @user_id, updated_at = SYSDATETIME()
        WHERE document_id = @document_id;
        DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"book_id":', @book_id, N',"book_number":', @book_number, N'}');
        EXEC dbo.sp_write_audit @user_id, @role_id, 'REGISTER', 'DOCUMENT', @document_id, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 5.6 Chỉ đạo / chuyển văn bản (PCT -> phòng, TP -> chuyên viên, PTP -> mảng phụ trách)
CREATE OR ALTER PROCEDURE dbo.sp_direct_document
    @user_id             INT,
    @role_id             INT,
    @document_id         INT,
    @to_user_id          INT,
    @handling_type       VARCHAR(12),          -- DIRECTION | MAIN | COORDINATE | INFO
    @instruction         NVARCHAR(1000) = NULL,
    @due_date            DATE = NULL,
    @handling_id         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @role_code VARCHAR(20), @field_id INT, @status VARCHAR(20), @parent INT;
    SELECT @role_code = role_code FROM dbo.fn_user_context(@user_id, @role_id);
    SELECT @field_id = field_id, @status = status FROM dbo.documents WHERE document_id = @document_id AND direction = 'IN';

    IF dbo.fn_has_permission(@user_id, @role_id, 'F12_DIRECT_DOCUMENT', 'G') = 0
        THROW 50403, N'Vai trò hiện tại không có quyền chỉ đạo / chuyển văn bản.', 1;
    IF @field_id IS NULL
        THROW 50404, N'Không tìm thấy văn bản đến.', 1;
    IF @status IN ('RECEIVED','COMPLETED')
        THROW 50409, N'Văn bản chưa vào sổ hoặc đã hoàn thành, không thể chuyển.', 1;
    IF @role_code = 'PTP' AND NOT EXISTS (SELECT 1 FROM dbo.leader_fields WHERE user_id = @user_id AND field_id = @field_id)
        THROW 50403, N'Phó Trưởng phòng chỉ chỉ đạo văn bản thuộc mảng được phân công.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.users WHERE user_id = @to_user_id AND is_active = 1) OR @to_user_id = @user_id
        THROW 50400, N'Người nhận không hợp lệ.', 1;
    IF @handling_type NOT IN ('DIRECTION','MAIN','COORDINATE','INFO')
        THROW 50400, N'Loại xử lý không hợp lệ.', 1;

    -- bước chuyển tới tôi đang chờ (nếu có) sẽ được đóng lại
    SELECT TOP (1) @parent = handling_id FROM dbo.document_handlings
    WHERE document_id = @document_id AND to_user_id = @user_id AND status = 'PENDING'
    ORDER BY handling_id DESC;

    BEGIN TRY
        BEGIN TRAN;
        IF @parent IS NOT NULL
            UPDATE dbo.document_handlings SET status = 'DONE', done_at = SYSDATETIME() WHERE handling_id = @parent;

        INSERT INTO dbo.document_handlings (document_id, parent_handling_id, from_user_id, to_user_id,
                                            handling_type, instruction, due_date)
        VALUES (@document_id, @parent, @user_id, @to_user_id, @handling_type, @instruction, @due_date);
        SET @handling_id = SCOPE_IDENTITY();

        UPDATE dbo.documents
        SET status = CASE WHEN @handling_type = 'DIRECTION' THEN 'WAIT_DIRECTION'
                          WHEN @handling_type IN ('MAIN','COORDINATE') THEN 'PROCESSING'
                          ELSE status END,
            due_date = ISNULL(@due_date, due_date),
            updated_by = @user_id, updated_at = SYSDATETIME()
        WHERE document_id = @document_id;

        -- văn bản mật: người được giao trực tiếp được cấp quyền xem/tải
        IF EXISTS (SELECT 1 FROM dbo.documents WHERE document_id = @document_id AND security_level <> 'NORMAL')
           AND NOT EXISTS (SELECT 1 FROM dbo.document_access_grants WHERE document_id = @document_id AND user_id = @to_user_id)
            INSERT INTO dbo.document_access_grants (document_id, user_id, granted_by) VALUES (@document_id, @to_user_id, @user_id);

        DECLARE @ntype VARCHAR(25) = CASE WHEN @handling_type = 'DIRECTION' THEN 'DOC_DIRECTED' ELSE 'DOC_HANDLING' END;
        DECLARE @ntitle NVARCHAR(200) = CASE WHEN @handling_type = 'DIRECTION'
                                             THEN N'Có văn bản cần cho ý kiến chỉ đạo'
                                             ELSE N'Bạn được giao xử lý một văn bản' END;
        EXEC dbo.sp_notify @to_user_id, @ntype, @ntitle, @instruction, 'DOCUMENT', @document_id;
        DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"to_user_id":', @to_user_id, N',"type":"', @handling_type, N'"}');
        EXEC dbo.sp_write_audit @user_id, @role_id, 'DIRECT', 'DOCUMENT', @document_id, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

/* =====================================================================
   PHẦN 6. DỰ THẢO – TRÌNH KÝ – DUYỆT – PHÁT HÀNH  (hỗ trợ 2.2.x)
   ===================================================================== */

-- 6.1 Tạo dự thảo văn bản đi (phiên bản 1). Tệp dự thảo backend lưu vào attachments với version_id.
CREATE OR ALTER PROCEDURE dbo.sp_create_draft
    @user_id         INT,
    @role_id         INT,
    @doc_type_id     INT,
    @field_id        INT,
    @summary         NVARCHAR(500),
    @security_level  VARCHAR(12) = 'NORMAL',
    @urgency         VARCHAR(10) = 'NORMAL',
    @change_note     NVARCHAR(500) = NULL,
    @document_id     INT OUTPUT,
    @version_id      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @role_code VARCHAR(20), @my_field INT;
    SELECT @role_code = role_code, @my_field = field_id FROM dbo.fn_user_context(@user_id, @role_id);
    IF dbo.fn_has_permission(@user_id, @role_id, 'F13_DRAFT_CREATE', 'S') = 0
        THROW 50403, N'Vai trò hiện tại không được soạn dự thảo.', 1;
    IF @my_field IS NOT NULL AND @my_field <> @field_id
        THROW 50403, N'Chuyên viên chỉ soạn dự thảo thuộc lĩnh vực của mình.', 1;
    IF @role_code = 'PTP' AND NOT EXISTS (SELECT 1 FROM dbo.leader_fields WHERE user_id = @user_id AND field_id = @field_id)
        THROW 50403, N'Phó Trưởng phòng chỉ soạn dự thảo thuộc mảng phụ trách.', 1;
    IF LEN(LTRIM(RTRIM(ISNULL(@summary, N'')))) = 0
        THROW 50400, N'Trích yếu không được để trống.', 1;

    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO dbo.documents (direction, doc_type_id, summary, field_id, security_level, urgency,
                                   status, current_version_no, created_by)
        VALUES ('OUT', @doc_type_id, @summary, @field_id, @security_level, @urgency, 'DRAFT', 1, @user_id);
        SET @document_id = SCOPE_IDENTITY();
        INSERT INTO dbo.document_versions (document_id, version_no, change_note, created_by)
        VALUES (@document_id, 1, ISNULL(@change_note, N'Dự thảo lần 1'), @user_id);
        SET @version_id = SCOPE_IDENTITY();
        EXEC dbo.sp_write_audit @user_id, @role_id, 'CREATE', 'DOCUMENT', @document_id, N'{"version_no":1}';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 6.2 Thêm phiên bản mới (sửa dự thảo sau khi bị trả lại)
CREATE OR ALTER PROCEDURE dbo.sp_add_draft_version
    @user_id      INT,
    @role_id      INT,
    @document_id  INT,
    @change_note  NVARCHAR(500),
    @version_id   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.documents
                   WHERE document_id = @document_id AND direction = 'OUT'
                     AND status IN ('DRAFT','RETURNED') AND created_by = @user_id)
        THROW 50409, N'Chỉ người soạn được sửa dự thảo đang ở trạng thái Dự thảo hoặc Bị trả lại.', 1;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F13_DRAFT_CREATE', 'S') = 0
        THROW 50403, N'Vai trò hiện tại không được sửa dự thảo.', 1;

    BEGIN TRY
        BEGIN TRAN;
        DECLARE @no INT;
        UPDATE dbo.documents
        SET @no = current_version_no = current_version_no + 1,
            status = 'DRAFT', updated_by = @user_id, updated_at = SYSDATETIME()
        WHERE document_id = @document_id AND status IN ('DRAFT','RETURNED') AND created_by = @user_id;
        IF @@ROWCOUNT = 0
            THROW 50409, N'Dự thảo vừa được trình hoặc thay đổi trạng thái.', 1;
        INSERT INTO dbo.document_versions (document_id, version_no, change_note, created_by)
        VALUES (@document_id, @no, @change_note, @user_id);
        SET @version_id = SCOPE_IDENTITY();
        DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"version_no":', @no, N'}');
        EXEC dbo.sp_write_audit @user_id, @role_id, 'UPDATE', 'DOCUMENT', @document_id, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 6.3 Trình ký dự thảo (phiên bản mới nhất) lên lãnh đạo có thẩm quyền (TP hoặc PCT)
CREATE OR ALTER PROCEDURE dbo.sp_submit_draft
    @user_id      INT,
    @role_id      INT,
    @document_id  INT,
    @approver_id  INT,
    @approval_id  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @version_id INT;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F14_DRAFT_SUBMIT', 'S') = 0
        THROW 50403, N'Vai trò hiện tại không được trình ký.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.documents
                   WHERE document_id = @document_id AND direction = 'OUT'
                     AND status IN ('DRAFT','RETURNED') AND created_by = @user_id)
        THROW 50409, N'Chỉ trình được dự thảo của mình ở trạng thái Dự thảo hoặc Bị trả lại.', 1;
    -- người duyệt phải giữ vai trò PCT hoặc TP (PTP chỉ duyệt thay qua ủy quyền)
    IF @approver_id = @user_id OR NOT EXISTS (
        SELECT 1 FROM dbo.user_roles ur JOIN dbo.roles r ON r.role_id = ur.role_id
        JOIN dbo.users u ON u.user_id = ur.user_id
        WHERE ur.user_id = @approver_id AND r.code IN ('PCT','TP') AND u.is_active = 1)
        THROW 50400, N'Người duyệt phải là Trưởng phòng hoặc Phó Chủ tịch (không tự trình cho mình).', 1;
    SELECT TOP (1) @version_id = version_id FROM dbo.document_versions
    WHERE document_id = @document_id ORDER BY version_no DESC;
    IF @version_id IS NULL
        THROW 50400, N'Dự thảo chưa có phiên bản nội dung.', 1;

    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO dbo.approval_requests (document_id, version_id, step_no, submitted_by, approver_id)
        VALUES (@document_id, @version_id, 1, @user_id, @approver_id);
        SET @approval_id = SCOPE_IDENTITY();
        UPDATE dbo.documents SET status = 'PENDING_APPROVAL', updated_by = @user_id, updated_at = SYSDATETIME()
        WHERE document_id = @document_id;
        EXEC dbo.sp_notify @approver_id, 'APPROVAL_PENDING', N'Có dự thảo chờ bạn duyệt ký', NULL, 'APPROVAL', @approval_id;
        -- báo cả người đang được ủy quyền ký thay
        DECLARE @deleg_user INT = (SELECT TOP (1) to_user_id FROM dbo.delegations
                                   WHERE from_user_id = @approver_id AND is_active = 1 AND can_sign = 1
                                     AND revoked_at IS NULL AND SYSDATETIME() >= valid_from AND SYSDATETIME() < valid_to);
        IF @deleg_user IS NOT NULL
            EXEC dbo.sp_notify @deleg_user, 'APPROVAL_PENDING', N'Có dự thảo chờ duyệt (theo ủy quyền)', NULL, 'APPROVAL', @approval_id;
        EXEC dbo.sp_write_audit @user_id, @role_id, 'SUBMIT', 'DOCUMENT', @document_id, NULL;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 6.4 Duyệt / Trả lại / Chuyển tiếp lên PCT. Mỗi lượt trình chỉ được quyết định MỘT lần:
--     UPDATE ... WHERE status = 'PENDING' + kiểm tra @@ROWCOUNT (2 người bấm cùng lúc chỉ 1 người thắng).
CREATE OR ALTER PROCEDURE dbo.sp_decide_approval
    @user_id      INT,
    @role_id      INT,
    @approval_id  INT,
    @decision     VARCHAR(10),               -- APPROVE | RETURN | FORWARD
    @note         NVARCHAR(1000) = NULL,     -- bắt buộc khi RETURN
    @forward_to   INT = NULL                 -- bắt buộc khi FORWARD (thường là PCT)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @approver INT, @document_id INT, @version_id INT, @step TINYINT, @submitter INT, @deleg INT, @creator INT;
    SELECT @approver = a.approver_id, @document_id = a.document_id, @version_id = a.version_id,
           @step = a.step_no, @submitter = a.submitted_by, @creator = d.created_by
    FROM dbo.approval_requests a JOIN dbo.documents d ON d.document_id = a.document_id
    WHERE a.approval_id = @approval_id AND a.status = 'PENDING';

    IF @approver IS NULL
        THROW 50409, N'Lượt trình không tồn tại hoặc đã được xử lý.', 1;
    IF @user_id IN (@submitter, @creator)
        THROW 50403, N'Không được tự duyệt dự thảo do mình soạn hoặc trình.', 1;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F15_DRAFT_APPROVE', 'D') = 0
        THROW 50403, N'Vai trò hiện tại không có quyền duyệt dự thảo.', 1;
    IF @approver <> @user_id
    BEGIN
        SELECT TOP (1) @deleg = delegation_id FROM dbo.fn_active_delegations(@user_id, SYSDATETIME())
        WHERE from_user_id = @approver AND can_sign = 1;
        IF @deleg IS NULL
            THROW 50403, N'Lượt trình này không thuộc thẩm quyền của bạn.', 1;
    END;
    IF @decision NOT IN ('APPROVE','RETURN','FORWARD')
        THROW 50400, N'Quyết định không hợp lệ.', 1;
    IF @decision = 'RETURN' AND LEN(LTRIM(RTRIM(ISNULL(@note, N'')))) = 0
        THROW 50400, N'Trả lại dự thảo bắt buộc nhập lý do.', 1;
    IF @decision = 'FORWARD' AND (@forward_to IS NULL OR @forward_to IN (@user_id, @approver) OR NOT EXISTS (
            SELECT 1 FROM dbo.user_roles ur JOIN dbo.roles r ON r.role_id = ur.role_id
            WHERE ur.user_id = @forward_to AND r.code IN ('PCT','TP')))
        THROW 50400, N'Người nhận chuyển tiếp phải là lãnh đạo có thẩm quyền khác.', 1;

    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.approval_requests
        SET status = CASE @decision WHEN 'APPROVE' THEN 'APPROVED' WHEN 'RETURN' THEN 'RETURNED' ELSE 'FORWARDED' END,
            decided_by = @user_id, decided_at = SYSDATETIME(), decision_note = @note, via_delegation_id = @deleg
        WHERE approval_id = @approval_id AND status = 'PENDING';
        IF @@ROWCOUNT = 0
            THROW 50409, N'Lượt trình vừa được người khác xử lý.', 1;

        IF @decision = 'APPROVE'
        BEGIN
            -- người ký là người bấm duyệt thực tế (PTP ký thay "KT. Trưởng phòng" khi có ủy quyền)
            UPDATE dbo.documents SET status = 'APPROVED', signed_by = @user_id,
                   updated_by = @user_id, updated_at = SYSDATETIME()
            WHERE document_id = @document_id;
            EXEC dbo.sp_notify @creator, 'APPROVAL_DONE', N'Dự thảo của bạn đã được duyệt', @note, 'DOCUMENT', @document_id;
            EXEC dbo.sp_write_audit @user_id, @role_id, 'APPROVE', 'DOCUMENT', @document_id, NULL;
        END
        ELSE IF @decision = 'RETURN'
        BEGIN
            UPDATE dbo.documents SET status = 'RETURNED', updated_by = @user_id, updated_at = SYSDATETIME()
            WHERE document_id = @document_id;
            EXEC dbo.sp_notify @creator, 'DOC_RETURNED', N'Dự thảo bị trả lại', @note, 'DOCUMENT', @document_id;
            DECLARE @detail NVARCHAR(MAX) = (SELECT @note AS reason FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            EXEC dbo.sp_write_audit @user_id, @role_id, 'RETURN', 'DOCUMENT', @document_id, @detail;
        END
        ELSE
        BEGIN
            DECLARE @new_id INT;
            INSERT INTO dbo.approval_requests (document_id, version_id, step_no, submitted_by, approver_id)
            VALUES (@document_id, @version_id, @step + 1, @user_id, @forward_to);
            SET @new_id = SCOPE_IDENTITY();
            EXEC dbo.sp_notify @forward_to, 'APPROVAL_PENDING', N'Có dự thảo trình lên chờ bạn duyệt', @note, 'APPROVAL', @new_id;
            EXEC dbo.sp_write_audit @user_id, @role_id, 'FORWARD', 'DOCUMENT', @document_id, NULL;
        END;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 6.5 Phát hành văn bản đi: cấp số đi, ghép số ký hiệu "<số>/<viết tắt loại>-<ký hiệu phòng>"
CREATE OR ALTER PROCEDURE dbo.sp_issue_document
    @user_id      INT,
    @role_id      INT,
    @document_id  INT,
    @book_id      INT,
    @book_number  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F16_DOCUMENT_ISSUE', 'D') = 0
       AND dbo.fn_has_permission(@user_id, @role_id, 'F16_DOCUMENT_ISSUE', 'C') = 0
        THROW 50403, N'Vai trò hiện tại không được phát hành văn bản.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.document_books
                   WHERE book_id = @book_id AND direction = 'OUT' AND book_year = YEAR(SYSDATETIME()))
        THROW 50400, N'Phải chọn sổ văn bản đi của năm hiện tại.', 1;

    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.documents WITH (UPDLOCK, ROWLOCK)
                       WHERE document_id = @document_id AND direction = 'OUT' AND status = 'APPROVED')
            THROW 50409, N'Chỉ phát hành được văn bản đã duyệt và chưa phát hành.', 1;
        EXEC dbo.sp_next_book_number @book_id, @book_number OUTPUT;
        DECLARE @dept NVARCHAR(20) = ISNULL((SELECT setting_value FROM dbo.system_settings WHERE setting_key = 'DEPARTMENT_SYMBOL'), N'VHXH');
        UPDATE d
        SET book_id = @book_id, book_number = @book_number,
            symbol = CONCAT(@book_number, N'/', dt.abbreviation, N'-', @dept),
            issued_date = CAST(SYSDATETIME() AS DATE), issued_at = SYSDATETIME(), issued_by = @user_id,
            status = 'ISSUED', updated_by = @user_id, updated_at = SYSDATETIME()
        FROM dbo.documents d JOIN dbo.document_types dt ON dt.doc_type_id = d.doc_type_id
        WHERE d.document_id = @document_id;
        DECLARE @creator INT = (SELECT created_by FROM dbo.documents WHERE document_id = @document_id);
        EXEC dbo.sp_notify @creator, 'DOC_ISSUED', N'Văn bản đã được phát hành', NULL, 'DOCUMENT', @document_id;
        DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"book_id":', @book_id, N',"book_number":', @book_number, N'}');
        EXEC dbo.sp_write_audit @user_id, @role_id, 'ISSUE', 'DOCUMENT', @document_id, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

/* =====================================================================
   PHẦN 7. NHIỆM VỤ – TIẾN ĐỘ – GIA HẠN  (hỗ trợ 1.4.x, 2.3.x, 3.1)
   ===================================================================== */

-- 7.1 Giao việc
CREATE OR ALTER PROCEDURE dbo.sp_assign_task
    @user_id      INT,
    @role_id      INT,
    @title        NVARCHAR(300),
    @description  NVARCHAR(MAX) = NULL,
    @field_id     INT,
    @assignee_id  INT,
    @due_date     DATE,
    @priority     VARCHAR(10) = 'NORMAL',
    @document_id  INT = NULL,
    @meeting_id   INT = NULL,
    @task_id      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @role_code VARCHAR(20), @my_rank TINYINT, @today DATE = CAST(SYSDATETIME() AS DATE);
    SELECT @role_code = role_code, @my_rank = rank_no FROM dbo.fn_user_context(@user_id, @role_id);
    IF dbo.fn_has_permission(@user_id, @role_id, 'F17_TASK_ASSIGN', 'G') = 0
        THROW 50403, N'Vai trò hiện tại không được giao việc.', 1;
    IF @role_code = 'PTP' AND NOT EXISTS (SELECT 1 FROM dbo.leader_fields WHERE user_id = @user_id AND field_id = @field_id)
        THROW 50403, N'Phó Trưởng phòng chỉ giao việc thuộc mảng phụ trách.', 1;
    -- chỉ giao cho người cấp thấp hơn mình
    IF NOT EXISTS (SELECT 1 FROM dbo.user_roles ur JOIN dbo.roles r ON r.role_id = ur.role_id
                   JOIN dbo.users u ON u.user_id = ur.user_id
                   WHERE ur.user_id = @assignee_id AND u.is_active = 1 AND r.rank_no > @my_rank)
        THROW 50400, N'Chỉ giao việc cho cán bộ cấp dưới đang hoạt động.', 1;
    IF @due_date IS NULL OR @due_date < @today
        THROW 50400, N'Hạn xử lý phải từ hôm nay trở đi.', 1;
    IF LEN(LTRIM(RTRIM(ISNULL(@title, N'')))) = 0
        THROW 50400, N'Tên nhiệm vụ không được để trống.', 1;

    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO dbo.tasks (title, description, field_id, document_id, meeting_id, assigned_by, assignee_id,
                               priority, start_date, due_date, original_due_date)
        VALUES (@title, @description, @field_id, @document_id, @meeting_id, @user_id, @assignee_id,
                @priority, @today, @due_date, @due_date);
        SET @task_id = SCOPE_IDENTITY();
        INSERT INTO dbo.task_updates (task_id, updated_by, old_status, new_status, progress_percent, note)
        VALUES (@task_id, @user_id, NULL, 'NEW', 0, N'Giao việc');
        EXEC dbo.sp_notify @assignee_id, 'TASK_ASSIGNED', N'Bạn được giao nhiệm vụ mới', @title, 'TASK', @task_id;
        EXEC dbo.sp_write_audit @user_id, @role_id, 'ASSIGN', 'TASK', @task_id, NULL;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 7.2 Cập nhật tiến độ: chỉ người được giao; chuyển trạng thái hợp lệ
--     NEW -> IN_PROGRESS | DONE ; IN_PROGRESS -> IN_PROGRESS (cập nhật %) | DONE ; DONE/CANCELLED: khóa
CREATE OR ALTER PROCEDURE dbo.sp_update_task_progress
    @user_id     INT,
    @role_id     INT,
    @task_id     INT,
    @new_status  VARCHAR(12),
    @progress    TINYINT,
    @note        NVARCHAR(1000) = NULL,
    @row_ver     BINARY(8) = NULL       -- gửi kèm khi mở form để chống ghi đè đồng thời
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @old VARCHAR(12), @assignee INT, @assigner INT, @cur_ver BINARY(8), @title NVARCHAR(300);
    SELECT @old = status, @assignee = assignee_id, @assigner = assigned_by, @cur_ver = row_ver, @title = title
    FROM dbo.tasks WHERE task_id = @task_id;

    IF @old IS NULL THROW 50404, N'Không tìm thấy nhiệm vụ.', 1;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F06_MY_TASKS', 'C') = 0 OR @assignee <> @user_id
        THROW 50403, N'Chỉ người được giao mới cập nhật tiến độ nhiệm vụ.', 1;
    IF @old IN ('DONE','CANCELLED')
        THROW 50409, N'Nhiệm vụ đã kết thúc, không thể cập nhật.', 1;
    IF @new_status NOT IN ('IN_PROGRESS','DONE')
        THROW 50400, N'Trạng thái mới không hợp lệ (chỉ Đang làm hoặc Hoàn thành).', 1;
    IF @new_status = 'DONE' SET @progress = 100;
    IF @progress IS NULL OR @progress > 100
        THROW 50400, N'Tiến độ phải trong khoảng 0–100%.', 1;
    IF @new_status = 'IN_PROGRESS' AND @progress = 100
        THROW 50400, N'Tiến độ 100% thì chọn trạng thái Hoàn thành.', 1;
    IF @row_ver IS NOT NULL AND @row_ver <> @cur_ver
        THROW 50409, N'Nhiệm vụ vừa được cập nhật bởi người khác, vui lòng tải lại.', 1;

    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.tasks
        SET status = @new_status, progress_percent = @progress,
            completed_at = CASE WHEN @new_status = 'DONE' THEN SYSDATETIME() ELSE NULL END,
            result_note = CASE WHEN @new_status = 'DONE' THEN @note ELSE result_note END,
            updated_at = SYSDATETIME()
        WHERE task_id = @task_id AND status = @old
          AND (@row_ver IS NULL OR row_ver = @row_ver);      -- optimistic lock thật sự nằm ở đây
        IF @@ROWCOUNT = 0 THROW 50409, N'Nhiệm vụ vừa được cập nhật bởi người khác, vui lòng tải lại.', 1;
        -- hoàn thành thì hủy đề xuất gia hạn còn treo
        IF @new_status = 'DONE'
            UPDATE dbo.extension_requests SET status = 'CANCELLED', decision_note = N'Tự hủy do nhiệm vụ đã hoàn thành'
            WHERE task_id = @task_id AND status = 'PENDING';
        INSERT INTO dbo.task_updates (task_id, updated_by, old_status, new_status, progress_percent, note)
        VALUES (@task_id, @user_id, @old, @new_status, @progress, @note);
        IF @new_status = 'DONE'
            EXEC dbo.sp_notify @assigner, 'TASK_UPDATED', N'Nhiệm vụ đã hoàn thành', @title, 'TASK', @task_id;
        DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"old":"', @old, N'","new":"', @new_status, N'","progress":', @progress, N'}');
        EXEC dbo.sp_write_audit @user_id, @role_id, 'UPDATE_PROGRESS', 'TASK', @task_id, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 7.3 Chuyên viên đề xuất gia hạn
CREATE OR ALTER PROCEDURE dbo.sp_request_extension
    @user_id        INT,
    @role_id        INT,
    @task_id        INT,
    @proposed_date  DATE,
    @reason         NVARCHAR(1000),
    @request_id     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @due DATE, @assignee INT, @assigner INT, @status VARCHAR(12);
    SELECT @due = due_date, @assignee = assignee_id, @assigner = assigned_by, @status = status
    FROM dbo.tasks WHERE task_id = @task_id;
    IF @due IS NULL THROW 50404, N'Không tìm thấy nhiệm vụ.', 1;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F18_EXTENSION_REQUEST', 'S') = 0 OR @assignee <> @user_id
        THROW 50403, N'Chỉ chuyên viên được giao mới được xin gia hạn.', 1;
    IF @status IN ('DONE','CANCELLED')
        THROW 50409, N'Nhiệm vụ đã kết thúc.', 1;
    IF @proposed_date IS NULL OR @proposed_date <= @due
        THROW 50400, N'Hạn đề xuất phải sau hạn hiện tại.', 1;
    IF LEN(LTRIM(RTRIM(ISNULL(@reason, N'')))) = 0
        THROW 50400, N'Phải nhập lý do xin gia hạn.', 1;
    IF EXISTS (SELECT 1 FROM dbo.extension_requests WHERE task_id = @task_id AND status = 'PENDING')
        THROW 50409, N'Nhiệm vụ đang có một đề xuất gia hạn chờ duyệt.', 1;

    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO dbo.extension_requests (task_id, requested_by, old_due_date, proposed_due_date, reason)
        VALUES (@task_id, @user_id, @due, @proposed_date, @reason);
        SET @request_id = SCOPE_IDENTITY();
        EXEC dbo.sp_notify @assigner, 'EXTENSION_REQUESTED', N'Có đề xuất xin gia hạn nhiệm vụ', @reason, 'EXTENSION', @request_id;
        EXEC dbo.sp_write_audit @user_id, @role_id, 'EXT_REQUEST', 'TASK', @task_id, NULL;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 7.4 Lãnh đạo đồng ý / từ chối gia hạn (quyết định 1 lần; đồng ý thì đổi hạn nhiệm vụ)
CREATE OR ALTER PROCEDURE dbo.sp_decide_extension
    @user_id     INT,
    @role_id     INT,
    @request_id  INT,
    @decision    VARCHAR(10),            -- APPROVE | REJECT
    @note        NVARCHAR(1000) = NULL   -- bắt buộc khi REJECT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @task_id INT, @proposed DATE, @requester INT, @assigner INT, @role_code VARCHAR(20), @deleg INT,
            @task_status VARCHAR(12);
    SELECT @task_id = e.task_id, @proposed = e.proposed_due_date, @requester = e.requested_by,
           @assigner = t.assigned_by, @task_status = t.status
    FROM dbo.extension_requests e JOIN dbo.tasks t ON t.task_id = e.task_id
    WHERE e.request_id = @request_id AND e.status = 'PENDING';
    SELECT @role_code = role_code FROM dbo.fn_user_context(@user_id, @role_id);

    IF @task_id IS NULL THROW 50409, N'Đề xuất không tồn tại hoặc đã được quyết định.', 1;
    IF @task_status IN ('DONE','CANCELLED') THROW 50409, N'Nhiệm vụ đã kết thúc, không xét gia hạn.', 1;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F19_EXTENSION_DECIDE', 'D') = 0
        THROW 50403, N'Vai trò hiện tại không có quyền duyệt gia hạn.', 1;
    IF @role_code = 'PCT' AND @assigner <> @user_id
        THROW 50403, N'Phó Chủ tịch chỉ duyệt gia hạn nhiệm vụ do mình giao.', 1;
    IF @role_code = 'PTP'
        SELECT TOP (1) @deleg = delegation_id FROM dbo.fn_active_delegations(@user_id, SYSDATETIME())
        WHERE can_approve_extension = 1;
    IF @decision NOT IN ('APPROVE','REJECT')
        THROW 50400, N'Quyết định không hợp lệ.', 1;
    IF @decision = 'REJECT' AND LEN(LTRIM(RTRIM(ISNULL(@note, N'')))) = 0
        THROW 50400, N'Từ chối gia hạn bắt buộc nhập lý do.', 1;

    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.extension_requests
        SET status = CASE WHEN @decision = 'APPROVE' THEN 'APPROVED' ELSE 'REJECTED' END,
            decided_by = @user_id, decided_at = SYSDATETIME(), decision_note = @note, via_delegation_id = @deleg
        WHERE request_id = @request_id AND status = 'PENDING';
        IF @@ROWCOUNT = 0 THROW 50409, N'Đề xuất vừa được người khác quyết định.', 1;
        IF @decision = 'APPROVE'
            UPDATE dbo.tasks SET due_date = @proposed, updated_at = SYSDATETIME() WHERE task_id = @task_id;
        DECLARE @msg NVARCHAR(1000) = CASE WHEN @decision = 'APPROVE'
              THEN CONCAT(N'Đồng ý gia hạn đến ', CONVERT(NVARCHAR(10), @proposed, 103))
              ELSE CONCAT(N'Từ chối gia hạn: ', @note) END;
        EXEC dbo.sp_notify @requester, 'EXTENSION_DECIDED', N'Kết quả đề xuất gia hạn', @msg, 'EXTENSION', @request_id;
        DECLARE @act VARCHAR(20) = CASE WHEN @decision = 'APPROVE' THEN 'EXT_APPROVE' ELSE 'EXT_REJECT' END;
        DECLARE @detail NVARCHAR(MAX) = (SELECT @request_id AS request_id, @note AS note FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        EXEC dbo.sp_write_audit @user_id, @role_id, @act, 'TASK', @task_id, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 7.5 Bật / tắt ủy quyền (Trưởng phòng -> Phó Trưởng phòng), ma trận dòng 24
CREATE OR ALTER PROCEDURE dbo.sp_set_delegation
    @user_id                INT,
    @role_id                INT,
    @to_user_id             INT,
    @turn_on                BIT,
    @valid_to               DATETIME2(0) = NULL,
    @can_sign               BIT = 1,
    @can_approve_extension  BIT = 1,
    @can_view_confidential  BIT = 0,
    @reason                 NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF dbo.fn_has_permission(@user_id, @role_id, 'F24_DELEGATION_TOGGLE', 'C') = 0
        THROW 50403, N'Chỉ Trưởng phòng được bật/tắt ủy quyền.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.user_roles ur JOIN dbo.roles r ON r.role_id = ur.role_id
                   WHERE ur.user_id = @to_user_id AND r.code = 'PTP')
        THROW 50400, N'Chỉ ủy quyền cho Phó Trưởng phòng.', 1;
    IF @turn_on = 1 AND (@valid_to IS NULL OR @valid_to <= SYSDATETIME())
        THROW 50400, N'Phải nhập thời hạn ủy quyền sau thời điểm hiện tại.', 1;

    BEGIN TRY
        BEGIN TRAN;
        -- luôn thu hồi ủy quyền cũ còn hiệu lực trước
        DECLARE @deleg_id INT = (SELECT MAX(delegation_id) FROM dbo.delegations
                                 WHERE from_user_id = @user_id AND to_user_id = @to_user_id AND is_active = 1);
        UPDATE dbo.delegations SET is_active = 0, revoked_at = SYSDATETIME()
        WHERE from_user_id = @user_id AND to_user_id = @to_user_id AND is_active = 1;
        IF @turn_on = 1
        BEGIN
            INSERT INTO dbo.delegations (from_user_id, to_user_id, can_sign, can_approve_extension,
                                         can_view_confidential, valid_from, valid_to, reason)
            VALUES (@user_id, @to_user_id, @can_sign, @can_approve_extension, @can_view_confidential,
                    SYSDATETIME(), @valid_to, @reason);
            SET @deleg_id = SCOPE_IDENTITY();
        END;
        DECLARE @title NVARCHAR(200) = CASE WHEN @turn_on = 1 THEN N'Bạn được ủy quyền ký duyệt' ELSE N'Ủy quyền đã được thu hồi' END;
        EXEC dbo.sp_notify @to_user_id, 'DELEGATION', @title, @reason, 'DELEGATION', @deleg_id;
        DECLARE @act VARCHAR(20) = CASE WHEN @turn_on = 1 THEN 'DELEGATE_ON' ELSE 'DELEGATE_OFF' END;
        DECLARE @detail NVARCHAR(MAX) = CONCAT(N'{"to_user_id":', @to_user_id, N'}');
        EXEC dbo.sp_write_audit @user_id, @role_id, @act, 'DELEGATION', @deleg_id, @detail;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

-- 7.6 Job hằng ngày: sinh thông báo sắp hạn / quá hạn (dedupe theo ngày nên chạy lại không bị trùng)
CREATE OR ALTER PROCEDURE dbo.sp_generate_deadline_notifications
    @today DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @today IS NULL SET @today = CAST(SYSDATETIME() AS DATE);
    DECLARE @d VARCHAR(10) = CONVERT(VARCHAR(10), @today, 23);

    INSERT INTO dbo.notifications (recipient_id, notif_type, title, message, entity_type, entity_id, dedupe_key)
    SELECT td.assignee_id,
           CASE td.deadline_state WHEN 'OVERDUE' THEN 'TASK_OVERDUE' ELSE 'TASK_DUE_SOON' END,
           CASE td.deadline_state WHEN 'OVERDUE' THEN N'Nhiệm vụ đã quá hạn' ELSE N'Nhiệm vụ sắp đến hạn' END,
           CONCAT(td.task_code, N' – ', td.title, N' (hạn ', CONVERT(NVARCHAR(10), td.due_date, 103), N')'),
           'TASK', td.task_id,
           CONCAT(td.deadline_state, ':TASK:', td.task_id, ':', @d)
    FROM dbo.fn_task_deadline(@today) td
    WHERE td.deadline_state IN ('OVERDUE','DUE_SOON')
      AND NOT EXISTS (SELECT 1 FROM dbo.notifications n
                      WHERE n.recipient_id = td.assignee_id
                        AND n.dedupe_key = CONCAT(td.deadline_state, ':TASK:', td.task_id, ':', @d));
    SELECT @@ROWCOUNT AS notifications_created;
END;
GO

/* =====================================================================
   PHẦN 8. TỔNG HỢP GIAO BAN  (task 3.2)
   ===================================================================== */

-- 8.1 Phân loại từng nhiệm vụ trong kỳ [@from, @to]. Mốc đánh giá @asof = min(@to, @today).
--     Mỗi nhiệm vụ thuộc đúng 1 cột -> tasks_total = done_on_time + done_late + in_progress + overdue
--     (dùng để đối chiếu số liệu trước khi in báo cáo).
CREATE OR ALTER FUNCTION dbo.fn_briefing_task_flags (@from DATE, @to DATE, @today DATE)
RETURNS TABLE
AS
RETURN
    SELECT t.task_id, t.task_code, t.title, t.field_id, t.assignee_id, t.due_date, t.original_due_date,
           t.status, t.completed_at, p.asof,
           CASE WHEN CAST(t.completed_at AS DATE) BETWEEN @from AND p.asof
                     AND CAST(t.completed_at AS DATE) <= t.due_date THEN 1 ELSE 0 END AS done_on_time,
           CASE WHEN CAST(t.completed_at AS DATE) BETWEEN @from AND p.asof
                     AND CAST(t.completed_at AS DATE) >  t.due_date THEN 1 ELSE 0 END AS done_late,
           CASE WHEN (t.completed_at IS NULL OR CAST(t.completed_at AS DATE) > p.asof)
                     AND t.due_date >= p.asof THEN 1 ELSE 0 END AS in_progress,
           CASE WHEN (t.completed_at IS NULL OR CAST(t.completed_at AS DATE) > p.asof)
                     AND t.due_date <  p.asof THEN 1 ELSE 0 END AS overdue
    FROM dbo.tasks t
    CROSS JOIN (SELECT CASE WHEN @to < @today THEN @to ELSE @today END AS asof) p
    WHERE t.status <> 'CANCELLED'
      AND t.start_date <= p.asof
      AND (t.completed_at IS NULL OR CAST(t.completed_at AS DATE) >= @from);
GO

-- 8.2 Số liệu giao ban theo lĩnh vực (dòng tổng: field_id NULL)
CREATE OR ALTER FUNCTION dbo.fn_briefing_by_field (@from DATE, @to DATE, @today DATE)
RETURNS TABLE
AS
RETURN
    SELECT f.field_id, f.code AS field_code, f.name AS field_name,
           ISNULL(t.tasks_total, 0)        AS tasks_total,
           ISNULL(t.tasks_done_on_time, 0) AS tasks_done_on_time,
           ISNULL(t.tasks_done_late, 0)    AS tasks_done_late,
           ISNULL(t.tasks_in_progress, 0)  AS tasks_in_progress,
           ISNULL(t.tasks_overdue, 0)      AS tasks_overdue,
           (SELECT COUNT(*) FROM dbo.approval_requests a JOIN dbo.documents d ON d.document_id = a.document_id
            WHERE a.status = 'PENDING' AND d.field_id = f.field_id) AS pending_approvals,
           (SELECT COUNT(*) FROM dbo.documents d
            WHERE d.direction = 'IN' AND d.field_id = f.field_id
              AND CAST(d.received_at AS DATE) BETWEEN @from AND @to) AS docs_in,
           (SELECT COUNT(*) FROM dbo.documents d
            WHERE d.direction = 'OUT' AND d.status = 'ISSUED' AND d.field_id = f.field_id
              AND CAST(d.issued_at AS DATE) BETWEEN @from AND @to) AS docs_out
    FROM dbo.fields f
    LEFT JOIN (
        SELECT field_id, COUNT(*) AS tasks_total, SUM(done_on_time) AS tasks_done_on_time,
               SUM(done_late) AS tasks_done_late, SUM(in_progress) AS tasks_in_progress, SUM(overdue) AS tasks_overdue
        FROM dbo.fn_briefing_task_flags(@from, @to, @today)
        GROUP BY field_id
    ) t ON t.field_id = f.field_id
    WHERE f.is_active = 1;
GO

-- 8.3 Thủ tục cho màn hình "Tổng hợp giao ban": trả 3 bảng kết quả
--     (1) theo lĩnh vực + dòng TỔNG, (2) theo chuyên viên, (3) danh sách việc quá hạn/trễ hạn
CREATE OR ALTER PROCEDURE dbo.sp_briefing_summary
    @user_id    INT,
    @role_id    INT,
    @from       DATE,
    @to         DATE,
    @field_id   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CAST(SYSDATETIME() AS DATE);
    IF dbo.fn_has_permission(@user_id, @role_id, 'F21_BRIEFING_REPORT', 'X') = 0
       AND dbo.fn_has_permission(@user_id, @role_id, 'F21_BRIEFING_REPORT', 'S') = 0
        THROW 50403, N'Vai trò hiện tại không xem được báo cáo giao ban.', 1;
    IF @from IS NULL OR @to IS NULL OR @from > @to
        THROW 50400, N'Kỳ báo cáo không hợp lệ.', 1;
    IF @from > @today
        THROW 50400, N'Kỳ báo cáo chưa bắt đầu.', 1;

    -- (1) Theo lĩnh vực + dòng tổng
    SELECT field_id AS sort_order, field_code, field_name, tasks_total, tasks_done_on_time, tasks_done_late,
           tasks_in_progress, tasks_overdue, pending_approvals, docs_in, docs_out,
           CAST(CASE WHEN tasks_total = 0 THEN NULL
                     ELSE 100.0 * (tasks_done_on_time + tasks_done_late) / tasks_total END AS DECIMAL(5,1)) AS completion_rate
    FROM dbo.fn_briefing_by_field(@from, @to, @today)
    WHERE @field_id IS NULL OR field_id = @field_id
    UNION ALL
    SELECT 999, 'TOTAL', N'TỔNG CỘNG', SUM(tasks_total), SUM(tasks_done_on_time), SUM(tasks_done_late),
           SUM(tasks_in_progress), SUM(tasks_overdue), SUM(pending_approvals), SUM(docs_in), SUM(docs_out),
           CAST(CASE WHEN SUM(tasks_total) = 0 THEN NULL
                     ELSE 100.0 * (SUM(tasks_done_on_time) + SUM(tasks_done_late)) / SUM(tasks_total) END AS DECIMAL(5,1))
    FROM dbo.fn_briefing_by_field(@from, @to, @today)
    WHERE @field_id IS NULL OR field_id = @field_id
    ORDER BY sort_order;

    -- (2) Theo chuyên viên / người xử lý
    SELECT f.name AS field_name, u.full_name AS assignee_name,
           COUNT(*) AS tasks_total, SUM(x.done_on_time) AS tasks_done_on_time, SUM(x.done_late) AS tasks_done_late,
           SUM(x.in_progress) AS tasks_in_progress, SUM(x.overdue) AS tasks_overdue
    FROM dbo.fn_briefing_task_flags(@from, @to, @today) x
    JOIN dbo.fields f ON f.field_id = x.field_id
    JOIN dbo.users u  ON u.user_id  = x.assignee_id
    WHERE @field_id IS NULL OR x.field_id = @field_id
    GROUP BY f.field_id, f.name, u.user_id, u.full_name
    ORDER BY f.field_id, u.full_name;

    -- (3) Việc quá hạn và hoàn thành trễ hạn (để lãnh đạo nhắc tại cuộc họp)
    SELECT x.task_code, x.title, f.name AS field_name, u.full_name AS assignee_name,
           x.original_due_date, x.due_date, x.completed_at,
           CASE WHEN x.overdue = 1 THEN N'Quá hạn' ELSE N'Hoàn thành trễ' END AS tinh_trang,
           DATEDIFF(DAY, x.due_date, ISNULL(CAST(x.completed_at AS DATE), x.asof)) AS so_ngay_tre
    FROM dbo.fn_briefing_task_flags(@from, @to, @today) x
    JOIN dbo.fields f ON f.field_id = x.field_id
    JOIN dbo.users u  ON u.user_id  = x.assignee_id
    WHERE (x.overdue = 1 OR x.done_late = 1)
      AND (@field_id IS NULL OR x.field_id = @field_id)
    ORDER BY so_ngay_tre DESC;
END;
GO

-- 8.4 Chốt báo cáo giao ban: lưu snapshot số liệu (Trưởng phòng)
CREATE OR ALTER PROCEDURE dbo.sp_create_briefing_report
    @user_id    INT,
    @role_id    INT,
    @title      NVARCHAR(300),
    @from       DATE,
    @to         DATE,
    @field_id   INT = NULL,
    @note       NVARCHAR(MAX) = NULL,
    @finalize   BIT = 0,
    @report_id  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @today DATE = CAST(SYSDATETIME() AS DATE);
    IF dbo.fn_has_permission(@user_id, @role_id, 'F21_BRIEFING_REPORT', 'S') = 0
        THROW 50403, N'Chỉ Trưởng phòng được lập báo cáo giao ban.', 1;
    IF @from IS NULL OR @to IS NULL OR @from > @to OR @from > @today
        THROW 50400, N'Kỳ báo cáo không hợp lệ.', 1;

    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO dbo.briefing_reports (title, period_from, period_to, field_id, status, note, created_by, finalized_at)
        VALUES (@title, @from, @to, @field_id,
                CASE WHEN @finalize = 1 THEN 'FINAL' ELSE 'DRAFT' END, @note, @user_id,
                CASE WHEN @finalize = 1 THEN SYSDATETIME() END);
        SET @report_id = SCOPE_IDENTITY();

        -- dòng tổng theo lĩnh vực
        INSERT INTO dbo.briefing_report_lines (report_id, field_id, assignee_id, tasks_total, tasks_done_on_time,
               tasks_done_late, tasks_in_progress, tasks_overdue, pending_approvals, docs_in, docs_out)
        SELECT @report_id, field_id, NULL, tasks_total, tasks_done_on_time, tasks_done_late,
               tasks_in_progress, tasks_overdue, pending_approvals, docs_in, docs_out
        FROM dbo.fn_briefing_by_field(@from, @to, @today)
        WHERE @field_id IS NULL OR field_id = @field_id;

        -- dòng chi tiết theo người xử lý
        INSERT INTO dbo.briefing_report_lines (report_id, field_id, assignee_id, tasks_total, tasks_done_on_time,
               tasks_done_late, tasks_in_progress, tasks_overdue)
        SELECT @report_id, field_id, assignee_id, COUNT(*), SUM(done_on_time), SUM(done_late), SUM(in_progress), SUM(overdue)
        FROM dbo.fn_briefing_task_flags(@from, @to, @today)
        WHERE @field_id IS NULL OR field_id = @field_id
        GROUP BY field_id, assignee_id;

        EXEC dbo.sp_write_audit @user_id, @role_id, 'REPORT', 'REPORT', @report_id, NULL;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

/* =====================================================================
   PHẦN 9. NHẬT KÝ THAO TÁC CỦA MỘT ĐỐI TƯỢNG (ma trận dòng 25)
   ===================================================================== */
CREATE OR ALTER FUNCTION dbo.fn_audit_trail (@user_id INT, @role_id INT, @entity_type VARCHAR(12), @entity_id INT)
RETURNS TABLE
AS
RETURN
    SELECT l.log_id, l.created_at, u.full_name AS actor, r.name AS actor_role, l.action, l.detail
    FROM dbo.audit_logs l
    LEFT JOIN dbo.users u ON u.user_id = l.user_id
    LEFT JOIN dbo.roles r ON r.role_id = l.active_role_id
    WHERE l.entity_type = @entity_type AND l.entity_id = @entity_id
      AND dbo.fn_has_permission(@user_id, @role_id, 'F25_AUDIT_LOG', 'X') = 1;
GO

PRINT N'02_programmability.sql: tạo xong hàm, view và thủ tục.';
GO
