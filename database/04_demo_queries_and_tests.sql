/* =====================================================================
   File   : 04_demo_queries_and_tests.sql
   Phần A : Truy vấn mẫu cho backend/demo (Hôm nay, việc của tôi, sổ, tra cứu, giao ban)
   Phần B : Ca kiểm thử ở mức CSDL (gửi Hiếu dùng cho 1.5.x, 2.3.4, 2.4.1)
            Mỗi ca in PASS/FAIL. Ca chạy đúng luồng được bọc BEGIN TRAN ... ROLLBACK
            nên chạy xong dữ liệu mẫu KHÔNG bị thay đổi.
   ===================================================================== */
USE QLVHXH;
GO
SET NOCOUNT ON;
GO

/* =====================================================================
   PHẦN A. TRUY VẤN MẪU
   ===================================================================== */

-- A1. Danh sách 9 tài khoản demo + vai trò (màn hình chọn nhanh vai trò)
SELECT u.user_id, u.username, u.full_name, r.role_id, r.code AS role_code, r.name AS role_name,
       ur.is_default, f.name AS field_name
FROM dbo.users u
JOIN dbo.user_roles ur ON ur.user_id = u.user_id
JOIN dbo.roles r       ON r.role_id  = ur.role_id
LEFT JOIN dbo.fields f ON f.field_id = r.field_id
ORDER BY r.rank_no, u.user_id, ur.is_default DESC;

-- A2. Ma trận quyền dạng pivot (đối chiếu với file Word ma trận vai trò – chức năng)
SELECT f.sort_no AS stt, f.name AS chuc_nang,
       MAX(CASE WHEN r.code = 'PCT'   THEN x.actions END) AS PCT,
       MAX(CASE WHEN r.code = 'TP'    THEN x.actions END) AS TP,
       MAX(CASE WHEN r.code = 'PTP'   THEN x.actions END) AS PTP,
       MAX(CASE WHEN r.code = 'CV_NV' THEN x.actions END) AS CV_NOIVU,
       MAX(CASE WHEN r.code = 'CV_YT' THEN x.actions END) AS CV_KHAC
FROM dbo.app_functions f
CROSS JOIN dbo.roles r
OUTER APPLY (SELECT STRING_AGG(CASE WHEN rp.requires_delegation = 1 THEN 'U(' + rp.action + ')' ELSE rp.action END, ',')
                    WITHIN GROUP (ORDER BY rp.action) AS actions
             FROM dbo.role_permissions rp
             WHERE rp.role_id = r.role_id AND rp.function_id = f.function_id) x
GROUP BY f.sort_no, f.name
ORDER BY f.sort_no;

-- A3. Menu / nút được dùng của Phó Trưởng phòng (có ủy quyền -> is_usable_now = 1 cho dòng U)
SELECT * FROM dbo.fn_permissions_of(3, 3) ORDER BY function_code, action;

-- A4. THẺ HÔM NAY của cả 9 tài khoản (task 1.3.1). NULL = vai trò không có thẻ đó.
SELECT u.username, c.*
FROM dbo.users u
JOIN dbo.user_roles ur ON ur.user_id = u.user_id AND ur.is_default = 1
CROSS APPLY dbo.fn_today_cards(u.user_id, ur.role_id, CAST(SYSDATETIME() AS DATE)) c
ORDER BY u.user_id;

-- A5. Danh sách chi tiết thẻ "Việc quá hạn" / "Sắp hạn" của Trưởng phòng
SELECT task_code, title, field_name, assignee_name, due_date, working_days_left, deadline_state, progress_percent
FROM dbo.fn_visible_tasks(2, 2, CAST(SYSDATETIME() AS DATE))
WHERE deadline_state IN ('OVERDUE','DUE_SOON')
ORDER BY CASE deadline_state WHEN 'OVERDUE' THEN 0 ELSE 1 END, due_date;

-- A6. "Việc của tôi" của CV Giáo dục (lọc trạng thái/hạn ở API, phân trang OFFSET/FETCH)
SELECT task_code, title, assigned_by_name, start_date, due_date, deadline_state, working_days_left, progress_percent
FROM dbo.fn_visible_tasks(6, 6, CAST(SYSDATETIME() AS DATE))
WHERE is_mine = 1
ORDER BY CASE deadline_state WHEN 'OVERDUE' THEN 0 WHEN 'DUE_SOON' THEN 1 WHEN 'ON_TRACK' THEN 2 ELSE 3 END, due_date
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;

-- A7. "Hồ sơ chờ tôi" của CV Nội vụ (có văn bản mật được giao + văn bản đến chưa vào sổ)
SELECT * FROM dbo.fn_waiting_documents(4, 4);

-- A8. Hồ sơ chờ ký của Phó Trưởng phòng (thấy hàng chờ của TP nhờ ủy quyền)
SELECT a.approval_id, d.summary, us.full_name AS nguoi_trinh, ua.full_name AS nguoi_duyet_goc, a.submitted_at
FROM dbo.approval_requests a
JOIN dbo.documents d ON d.document_id = a.document_id
JOIN dbo.users us ON us.user_id = a.submitted_by
JOIN dbo.users ua ON ua.user_id = a.approver_id
WHERE a.status = 'PENDING'
  AND dbo.fn_has_permission(3, 3, 'F08_PENDING_APPROVAL', 'X') = 1
  AND (a.approver_id = 3 OR a.approver_id IN (SELECT from_user_id FROM dbo.fn_active_delegations(3, SYSDATETIME()) WHERE can_sign = 1));

-- A9. Sổ văn bản đến / đi
SELECT * FROM dbo.v_incoming_register ORDER BY so_den;
SELECT * FROM dbo.v_outgoing_register ORDER BY so_di;

-- A10. Tra cứu: Trưởng phòng gõ không dấu "sot xuat huyet"
EXEC dbo.sp_search_documents @user_id = 2, @role_id = 2, @keyword = N'sot xuat huyet';
-- A11. Tra cứu: CV Y tế xem toàn bộ văn bản trong quyền (chỉ lĩnh vực Y tế + văn bản liên quan)
EXEC dbo.sp_search_documents @user_id = 5, @role_id = 5;

-- A12. Tổng hợp giao ban từ đầu tháng đến hôm nay (task 3.2) – 3 bảng kết quả
DECLARE @from DATE = DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1);
DECLARE @to   DATE = CAST(SYSDATETIME() AS DATE);
IF DATEDIFF(DAY, @from, @to) < 14 SET @from = DATEADD(DAY, -30, @to);   -- đầu tháng thì lấy 30 ngày gần nhất
EXEC dbo.sp_briefing_summary @user_id = 2, @role_id = 2, @from = @from, @to = @to;
GO

-- A13. Lịch sử thao tác của dự thảo 11 (Trưởng phòng xem được, chuyên viên không)
SELECT * FROM dbo.fn_audit_trail(2, 2, 'DOCUMENT', 11);
SELECT COUNT(*) AS cv_thay_duoc FROM dbo.fn_audit_trail(7, 7, 'DOCUMENT', 11);   -- = 0
GO

-- A14. Lịch họp của CV Y tế (chỉ cuộc họp mình tham gia)
SELECT m.meeting_id, m.title, m.start_at, m.end_at, m.location, p.participant_role
FROM dbo.meetings m
JOIN dbo.meeting_participants p ON p.meeting_id = m.meeting_id AND p.user_id = 5
WHERE m.status <> 'CANCELLED' AND m.start_at >= CAST(SYSDATETIME() AS DATE)
ORDER BY m.start_at;
GO

/* =====================================================================
   PHẦN B. CA KIỂM THỬ CSDL
   ===================================================================== */
PRINT N'===== BẮT ĐẦU KIỂM THỬ CSDL =====';

PRINT N'TC01 – CV Y tế bấm duyệt dự thảo -> phải bị chặn 50403';
BEGIN TRY
    EXEC dbo.sp_decide_approval @user_id = 5, @role_id = 5, @approval_id = 1, @decision = 'APPROVE';
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50403, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC02 – Trả lại dự thảo không nhập lý do -> 50400';
BEGIN TRY
    EXEC dbo.sp_decide_approval @user_id = 2, @role_id = 2, @approval_id = 1, @decision = 'RETURN', @note = N'   ';
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50400, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC03 – Một lượt trình chỉ được quyết định 1 lần (bấm Duyệt 2 lần) -> lần 2 lỗi 50409';
DECLARE @step INT = 0;
BEGIN TRAN;
BEGIN TRY
    SET @step = 1;
    EXEC dbo.sp_decide_approval @user_id = 2, @role_id = 2, @approval_id = 1, @decision = 'APPROVE';
    SET @step = 2;
    EXEC dbo.sp_decide_approval @user_id = 2, @role_id = 2, @approval_id = 1, @decision = 'APPROVE';
    PRINT N'   FAIL: duyệt được 2 lần';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(@step = 2 AND ERROR_NUMBER() = 50409, N'PASS', N'FAIL'), N' (bước ', @step, N', ', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC04 – PTP duyệt thay khi CÓ ủy quyền -> thành công, ghi via_delegation_id';
BEGIN TRAN;
BEGIN TRY
    EXEC dbo.sp_decide_approval @user_id = 3, @role_id = 3, @approval_id = 1, @decision = 'APPROVE';
    IF EXISTS (SELECT 1 FROM dbo.approval_requests WHERE approval_id = 1 AND status = 'APPROVED'
               AND decided_by = 3 AND via_delegation_id IS NOT NULL)
        PRINT N'   PASS';
    ELSE PRINT N'   FAIL: không ghi nhận ủy quyền';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   FAIL (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC05 – TP tắt ủy quyền, PTP duyệt lại -> 50403';
DECLARE @step INT = 0;
BEGIN TRAN;
BEGIN TRY
    SET @step = 1;
    EXEC dbo.sp_set_delegation @user_id = 2, @role_id = 2, @to_user_id = 3, @turn_on = 0;
    SET @step = 2;
    EXEC dbo.sp_decide_approval @user_id = 3, @role_id = 3, @approval_id = 1, @decision = 'APPROVE';
    PRINT N'   FAIL: vẫn duyệt được';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(@step = 2 AND ERROR_NUMBER() = 50403, N'PASS', N'FAIL'), N' (bước ', @step, N', ', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC06 – Vào sổ lại văn bản đã vào sổ -> 50409';
BEGIN TRAN;   -- lỡ chạy thành công thì cũng được ROLLBACK
BEGIN TRY
    DECLARE @n INT;
    EXEC dbo.sp_register_incoming @user_id = 4, @role_id = 4, @document_id = 1, @book_id = 1, @book_number = @n OUTPUT;
    PRINT N'   FAIL: vào sổ được 2 lần';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50409, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC07 – CV Nội vụ vào sổ văn bản mới đến -> nhận số tiếp theo (8)';
BEGIN TRAN;
BEGIN TRY
    DECLARE @n INT;
    EXEC dbo.sp_register_incoming @user_id = 4, @role_id = 4, @document_id = 7, @book_id = 1, @book_number = @n OUTPUT;
    PRINT CONCAT(N'   ', IIF(@n = 8, N'PASS', N'FAIL'), N': số đến = ', @n);
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   FAIL (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC08 – CV Y tế (không phải đầu mối) vào sổ -> 50403';
BEGIN TRAN;   -- lỡ chạy thành công thì cũng được ROLLBACK
BEGIN TRY
    DECLARE @n INT;
    EXEC dbo.sp_register_incoming @user_id = 5, @role_id = 5, @document_id = 7, @book_id = 1, @book_number = @n OUTPUT;
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50403, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC09 – Ghi trùng số đến trực tiếp vào bảng -> unique index chặn (2601)';
BEGIN TRAN;   -- lỡ chạy thành công thì cũng được ROLLBACK
BEGIN TRY
    UPDATE dbo.documents SET book_number = 3 WHERE document_id = 4;
    PRINT N'   FAIL: trùng số không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() IN (2601, 2627), N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC10 – Tạo phiên với vai trò không được cấp (CV Y tế dùng vai trò PCT) -> FK chặn (547)';
BEGIN TRAN;   -- lỡ chạy thành công thì cũng được ROLLBACK
BEGIN TRY
    INSERT INTO dbo.user_sessions (user_id, active_role_id, expires_at) VALUES (5, 1, DATEADD(HOUR, 1, SYSDATETIME()));
    PRINT N'   FAIL: tạo được phiên vượt quyền';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 547, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC11 – CV VHXH đổi sang vai trò kiêm nhiệm CV DTTG -> được; đổi lên TP -> 50403';
DECLARE @step INT = 0;
BEGIN TRAN;
BEGIN TRY
    DECLARE @sid UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.user_sessions (session_id, user_id, active_role_id, expires_at)
    VALUES (@sid, 7, 7, DATEADD(HOUR, 1, SYSDATETIME()));
    SET @step = 1;
    EXEC dbo.sp_switch_role @session_id = @sid, @new_role_id = 9;
    PRINT N'   PASS: đổi sang CV_DTTG thành công';
    SET @step = 2;
    EXEC dbo.sp_switch_role @session_id = @sid, @new_role_id = 2;
    PRINT N'   FAIL: đổi lên Trưởng phòng được';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(@step = 2 AND ERROR_NUMBER() = 50403, N'PASS', N'FAIL'), N' (bước ', @step, N', ', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC12 – Văn bản MẬT (doc 6): chỉ PCT, TP, CV Nội vụ (được giao) thấy; CV Y tế, PTP (không ủy quyền mật) không thấy';
DECLARE @r TABLE (who VARCHAR(10), cnt INT);
INSERT INTO @r SELECT 'PCT',   COUNT(*) FROM dbo.fn_visible_documents(1, 1) WHERE document_id = 6;
INSERT INTO @r SELECT 'TP',    COUNT(*) FROM dbo.fn_visible_documents(2, 2) WHERE document_id = 6;
INSERT INTO @r SELECT 'PTP',   COUNT(*) FROM dbo.fn_visible_documents(3, 3) WHERE document_id = 6;
INSERT INTO @r SELECT 'CV_NV', COUNT(*) FROM dbo.fn_visible_documents(4, 4) WHERE document_id = 6;
INSERT INTO @r SELECT 'CV_YT', COUNT(*) FROM dbo.fn_visible_documents(5, 5) WHERE document_id = 6;
IF (SELECT STRING_AGG(CONCAT(who, '=', cnt), ',') WITHIN GROUP (ORDER BY who) FROM @r)
   = 'CV_NV=1,CV_YT=0,PCT=1,PTP=0,TP=1'
    PRINT N'   PASS';
ELSE
    PRINT CONCAT(N'   FAIL: ', (SELECT STRING_AGG(CONCAT(who, '=', cnt), ',') FROM @r));
GO

PRINT N'TC13 – CV Y tế tra cứu: chỉ ra văn bản lĩnh vực Y tế hoặc có liên quan';
IF NOT EXISTS (SELECT 1 FROM dbo.fn_visible_documents(5, 5) v
               JOIN dbo.documents d ON d.document_id = v.document_id
               WHERE d.field_id <> 2 AND v.is_related = 0)
    PRINT N'   PASS';
ELSE PRINT N'   FAIL: lộ văn bản lĩnh vực khác';
GO

PRINT N'TC14 – Xin gia hạn với hạn mới <= hạn cũ -> 50400';
BEGIN TRY
    DECLARE @id INT, @d DATE = DATEADD(DAY, 5, CAST(SYSDATETIME() AS DATE));
    EXEC dbo.sp_request_extension @user_id = 6, @role_id = 6, @task_id = 4, @proposed_date = @d,
         @reason = N'Thử', @request_id = @id OUTPUT;
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50400, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC15 – Từ chối gia hạn không lý do -> 50400';
BEGIN TRY
    EXEC dbo.sp_decide_extension @user_id = 2, @role_id = 2, @request_id = 1, @decision = 'REJECT';
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50400, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC16 – PCT duyệt gia hạn nhiệm vụ KHÔNG do mình giao -> 50403';
BEGIN TRY
    EXEC dbo.sp_decide_extension @user_id = 1, @role_id = 1, @request_id = 1, @decision = 'APPROVE';
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50403, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC17 – TP đồng ý gia hạn -> hạn nhiệm vụ đổi, task hết quá hạn, CV nhận thông báo';
BEGIN TRAN;
BEGIN TRY
    EXEC dbo.sp_decide_extension @user_id = 2, @role_id = 2, @request_id = 1, @decision = 'APPROVE';
    IF EXISTS (SELECT 1 FROM dbo.v_task_deadline v JOIN dbo.extension_requests e ON e.task_id = v.task_id
               WHERE e.request_id = 1 AND v.due_date = e.proposed_due_date AND v.deadline_state <> 'OVERDUE')
       AND EXISTS (SELECT 1 FROM dbo.notifications WHERE recipient_id = 6 AND notif_type = 'EXTENSION_DECIDED')
        PRINT N'   PASS';
    ELSE PRINT N'   FAIL';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   FAIL (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC18 – CV Y tế cập nhật nhiệm vụ của người khác -> 50403';
BEGIN TRY
    EXEC dbo.sp_update_task_progress @user_id = 5, @role_id = 5, @task_id = 3, @new_status = 'IN_PROGRESS', @progress = 10;
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50403, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC19 – Cập nhật nhiệm vụ đã Hoàn thành -> 50409';
BEGIN TRY
    EXEC dbo.sp_update_task_progress @user_id = 7, @role_id = 7, @task_id = 6, @new_status = 'IN_PROGRESS', @progress = 50;
    PRINT N'   FAIL: không bị chặn';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50409, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC20 – Hoàn thành nhiệm vụ -> không còn bị tính quá hạn, số thẻ quá hạn giảm 1';
BEGIN TRAN;
BEGIN TRY
    DECLARE @today DATE = CAST(SYSDATETIME() AS DATE), @before INT, @after INT;
    SELECT @before = overdue_tasks FROM dbo.fn_today_cards(2, 2, @today);
    EXEC dbo.sp_update_task_progress @user_id = 5, @role_id = 5, @task_id = 2, @new_status = 'DONE', @progress = 100, @note = N'Đã gửi';
    SELECT @after = overdue_tasks FROM dbo.fn_today_cards(2, 2, @today);
    PRINT CONCAT(N'   ', IIF(@after = @before - 1, N'PASS', N'FAIL'), N': quá hạn ', @before, N' -> ', @after);
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   FAIL (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC21 – Thẻ Hôm nay không đếm trùng: mỗi nhiệm vụ thuộc đúng 1 nhóm hạn';
IF (SELECT COUNT(*) FROM dbo.tasks) =
   (SELECT COUNT(*) FROM dbo.v_task_deadline WHERE deadline_state IN ('OVERDUE','DUE_SOON','ON_TRACK','DONE','CANCELLED'))
   AND NOT EXISTS (SELECT task_id FROM dbo.v_task_deadline GROUP BY task_id HAVING COUNT(*) > 1)
    PRINT N'   PASS';
ELSE PRINT N'   FAIL';
GO

PRINT N'TC22 – Luồng đầy đủ: soạn -> trình -> trả lại -> sửa -> trình -> TP chuyển PCT -> PCT duyệt -> CV Nội vụ phát hành';
BEGIN TRAN;
BEGIN TRY
    DECLARE @a1 INT, @a2 INT, @v INT, @no INT;
    EXEC dbo.sp_submit_draft @user_id = 5, @role_id = 5, @document_id = 9, @approver_id = 2, @approval_id = @a1 OUTPUT;
    EXEC dbo.sp_decide_approval @user_id = 2, @role_id = 2, @approval_id = @a1, @decision = 'RETURN', @note = N'Bổ sung số liệu ca mắc';
    EXEC dbo.sp_add_draft_version @user_id = 5, @role_id = 5, @document_id = 9, @change_note = N'Đã bổ sung số liệu', @version_id = @v OUTPUT;
    EXEC dbo.sp_submit_draft @user_id = 5, @role_id = 5, @document_id = 9, @approver_id = 2, @approval_id = @a2 OUTPUT;
    EXEC dbo.sp_decide_approval @user_id = 2, @role_id = 2, @approval_id = @a2, @decision = 'FORWARD', @forward_to = 1;
    DECLARE @a3 INT = (SELECT approval_id FROM dbo.approval_requests WHERE document_id = 9 AND status = 'PENDING');
    EXEC dbo.sp_decide_approval @user_id = 1, @role_id = 1, @approval_id = @a3, @decision = 'APPROVE';
    EXEC dbo.sp_issue_document @user_id = 4, @role_id = 4, @document_id = 9, @book_id = 2, @book_number = @no OUTPUT;
    SELECT document_id, status, book_number, symbol, current_version_no, signed_by, issued_at FROM dbo.documents WHERE document_id = 9;
    SELECT action, created_at FROM dbo.audit_logs WHERE entity_type = 'DOCUMENT' AND entity_id = 9 ORDER BY log_id;
    IF EXISTS (SELECT 1 FROM dbo.documents WHERE document_id = 9 AND status = 'ISSUED' AND book_number = 2
               AND current_version_no = 2 AND signed_by = 1)
        PRINT CONCAT(N'   PASS: số đi = ', @no, N', ký hiệu = ', (SELECT symbol FROM dbo.documents WHERE document_id = 9));
    ELSE PRINT N'   FAIL';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   FAIL (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC23 – Số liệu giao ban khớp: tổng = đúng hạn + trễ hạn + đang làm + quá hạn';
DECLARE @to DATE = CAST(SYSDATETIME() AS DATE);
DECLARE @from DATE = DATEADD(DAY, -30, @to);
IF NOT EXISTS (SELECT 1 FROM dbo.fn_briefing_by_field(@from, @to, @to)
               WHERE tasks_total <> tasks_done_on_time + tasks_done_late + tasks_in_progress + tasks_overdue)
    PRINT N'   PASS';
ELSE PRINT N'   FAIL';
GO

PRINT N'TC24 – Job thông báo hạn chạy 2 lần không sinh trùng';
BEGIN TRAN;
BEGIN TRY
    DECLARE @c1 INT, @c2 INT;
    EXEC dbo.sp_generate_deadline_notifications;
    SET @c1 = (SELECT COUNT(*) FROM dbo.notifications);
    EXEC dbo.sp_generate_deadline_notifications;
    SET @c2 = (SELECT COUNT(*) FROM dbo.notifications);
    PRINT CONCAT(N'   ', IIF(@c1 = @c2, N'PASS', N'FAIL'), N': ', @c1, N' / ', @c2);
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   FAIL (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'TC25 – Sửa nhật ký thao tác -> trigger chặn (50001)';
BEGIN TRAN;   -- lỡ chạy thành công thì cũng được ROLLBACK
BEGIN TRY
    UPDATE dbo.audit_logs SET action = 'LOGIN' WHERE log_id = 1;
    PRINT N'   FAIL: sửa được nhật ký';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'   ', IIF(ERROR_NUMBER() = 50001, N'PASS', N'FAIL'), N' (', ERROR_NUMBER(), N') ', ERROR_MESSAGE());
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO

PRINT N'===== KẾT THÚC KIỂM THỬ =====';
GO
