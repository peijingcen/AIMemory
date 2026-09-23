DELIMITER $$

DROP PROCEDURE IF EXISTS sp_create_content_entry $$
CREATE PROCEDURE sp_create_content_entry(
	IN p_token_hash CHAR(64),
	IN p_content TEXT,
	IN p_event_at DATETIME,
	IN p_category VARCHAR(50),
	IN p_keyword_ids_csv TEXT,
	IN p_client_ip VARCHAR(45),
	IN p_request_id VARCHAR(64),
	OUT o_code INT,
	OUT o_msg VARCHAR(100),
	OUT o_entry_id BIGINT
)
BEGIN
	DECLARE v_user_id BIGINT DEFAULT NULL;
	DECLARE v_user_type VARCHAR(20) DEFAULT NULL;
	DECLARE v_keyword_ids_csv TEXT DEFAULT NULL;
	DECLARE v_done TINYINT DEFAULT 0;

	-- 任意 SQL 异常时回滚并返回统一错误码
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		ROLLBACK;
		SET o_code = 9000;
		SET o_msg = 'db_error';
		SET o_entry_id = NULL;
	END;

	-- 初始化输出参数
	SET o_code = NULL;
	SET o_msg = NULL;
	SET o_entry_id = NULL;
	SET v_keyword_ids_csv = REPLACE(IFNULL(p_keyword_ids_csv, ''), ' ', '');

	START TRANSACTION;

	-- 参数基础校验
	IF p_token_hash IS NULL OR p_token_hash = '' THEN
		SET o_code = 2002;
		SET o_msg = 'token_required';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'content', 'create', 'content_entries', NULL,
			p_request_id, p_client_ip, 0, 'token_required', 'token_required',
			JSON_OBJECT('event_at', p_event_at, 'category', p_category, 'keyword_ids_csv', p_keyword_ids_csv), NOW()
		);
		SET v_done = 1;
	END IF;

	IF v_done = 0 AND (p_content IS NULL OR TRIM(p_content) = '') THEN
		SET o_code = 2003;
		SET o_msg = 'content_required';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'content', 'create', 'content_entries', NULL,
			p_request_id, p_client_ip, 0, 'content_required', 'content_required',
			JSON_OBJECT('event_at', p_event_at, 'category', p_category, 'keyword_ids_csv', p_keyword_ids_csv), NOW()
		);
		SET v_done = 1;
	END IF;

	IF v_done = 0 AND p_event_at IS NULL THEN
		SET o_code = 2004;
		SET o_msg = 'event_at_required';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'content', 'create', 'content_entries', NULL,
			p_request_id, p_client_ip, 0, 'event_at_required', 'event_at_required',
			JSON_OBJECT('category', p_category, 'keyword_ids_csv', p_keyword_ids_csv), NOW()
		);
		SET v_done = 1;
	END IF;

	-- 校验登录态：token 未撤销、未过期，且用户账号可用
	IF v_done = 0 THEN
		SELECT u.id, u.user_type
		INTO v_user_id, v_user_type
		FROM user_tokens t
		INNER JOIN users u ON u.id = t.user_id
		WHERE t.token_hash = p_token_hash
		  AND t.revoked_at IS NULL
		  AND t.expires_at > NOW()
		  AND u.status = 1
		  AND u.deleted_at IS NULL
		LIMIT 1
		FOR UPDATE;
	END IF;

	IF v_done = 0 AND v_user_id IS NULL THEN
		SET o_code = 2001;
		SET o_msg = 'login_invalid';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'content', 'create', 'content_entries', NULL,
			p_request_id, p_client_ip, 0, 'login_invalid', 'login_invalid',
			JSON_OBJECT('event_at', p_event_at, 'category', p_category, 'keyword_ids_csv', p_keyword_ids_csv), NOW()
		);
		SET v_done = 1;
	END IF;

	IF v_done = 0 THEN
		INSERT INTO content_entries (
			content,
			event_at,
			category,
			status,
			created_at,
			updated_at
		) VALUES (
			p_content,
			p_event_at,
			p_category,
			1,
			NOW(),
			NOW()
		);

		SET o_entry_id = LAST_INSERT_ID();

		IF v_keyword_ids_csv <> '' THEN
			INSERT INTO entry_keywords (entry_id, keyword_id)
			SELECT o_entry_id, k.id
			FROM keywords k
			WHERE FIND_IN_SET(k.id, v_keyword_ids_csv) > 0;
		END IF;

		UPDATE user_tokens
		SET last_used_at = NOW()
		WHERE token_hash = p_token_hash;

		INSERT INTO audit_logs (
			user_id,
			user_type,
			module,
			action,
			target_type,
			target_id,
			request_id,
			client_ip,
			status,
			error_code,
			error_message,
			ext_json,
			created_at
		) VALUES (
			v_user_id,
			v_user_type,
			'content',
			'create',
			'content_entries',
			CAST(o_entry_id AS CHAR(100)),
			p_request_id,
			p_client_ip,
			1,
			NULL,
			NULL,
			JSON_OBJECT('event_at', p_event_at, 'category', p_category, 'keyword_ids_csv', p_keyword_ids_csv),
			NOW()
		);

		SET o_code = 0;
		SET o_msg = 'ok';
	END IF;

	COMMIT;
END $$

DELIMITER ;

-- 调用示例：
-- SET @o_code = NULL;
-- SET @o_msg = NULL;
-- SET @o_entry_id = NULL;
-- CALL sp_create_content_entry(
--     'token_hash_value_64_chars',
--     '这里是内容正文',
--     '2026-06-08 10:30:00',
--     '工作日志',
--     '1,2,3',
--     '127.0.0.1',
--     'req-20260608-0001',
--     @o_code,
--     @o_msg,
--     @o_entry_id
-- );
-- SELECT @o_code, @o_msg, @o_entry_id;
