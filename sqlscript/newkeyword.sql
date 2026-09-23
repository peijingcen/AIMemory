DELIMITER $$

DROP PROCEDURE IF EXISTS sp_create_keyword $$
CREATE PROCEDURE sp_create_keyword(
	IN p_token_hash CHAR(64),
	IN p_keyword_zh VARCHAR(100),
	IN p_keyword_en VARCHAR(100),
	IN p_first_char CHAR(1),
	IN p_client_ip VARCHAR(45),
	IN p_request_id VARCHAR(64),
	OUT o_code INT,
	OUT o_msg VARCHAR(100),
	OUT o_keyword_id BIGINT
)
BEGIN
	DECLARE v_user_id BIGINT DEFAULT NULL;
	DECLARE v_user_type VARCHAR(20) DEFAULT NULL;
	DECLARE v_keyword_zh VARCHAR(100) DEFAULT NULL;
	DECLARE v_keyword_en VARCHAR(100) DEFAULT NULL;
	DECLARE v_first_char CHAR(1) DEFAULT NULL;
	DECLARE v_keyword_id BIGINT DEFAULT NULL;
	DECLARE v_done TINYINT DEFAULT 0;

	-- 任意 SQL 异常时回滚并返回统一错误码
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		ROLLBACK;
		SET o_code = 9000;
		SET o_msg = 'db_error';
		SET o_keyword_id = NULL;
	END;

	-- 初始化输出参数
	SET o_code = NULL;
	SET o_msg = NULL;
	SET o_keyword_id = NULL;
	SET v_keyword_zh = TRIM(IFNULL(p_keyword_zh, ''));
	SET v_keyword_en = TRIM(IFNULL(p_keyword_en, ''));
	SET v_first_char = UPPER(NULLIF(TRIM(IFNULL(p_first_char, '')), ''));

	IF v_keyword_en = '' THEN
		SET v_keyword_en = NULL;
	END IF;

	START TRANSACTION;

	IF p_token_hash IS NULL OR p_token_hash = '' THEN
		SET o_code = 3002;
		SET o_msg = 'token_required';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'keyword', 'create', 'keywords', NULL,
			p_request_id, p_client_ip, 0, 'token_required', 'token_required',
			JSON_OBJECT('keyword_zh', p_keyword_zh, 'keyword_en', p_keyword_en, 'first_char', p_first_char), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 AND v_keyword_zh = '' THEN
		SET o_code = 3003;
		SET o_msg = 'keyword_zh_required';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'keyword', 'create', 'keywords', NULL,
			p_request_id, p_client_ip, 0, 'keyword_zh_required', 'keyword_zh_required',
			JSON_OBJECT('keyword_en', p_keyword_en, 'first_char', p_first_char), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 AND v_first_char IS NOT NULL AND v_first_char NOT REGEXP '^[A-Z0-9]$' THEN
		SET o_code = 3004;
		SET o_msg = 'first_char_invalid';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'keyword', 'create', 'keywords', NULL,
			p_request_id, p_client_ip, 0, 'first_char_invalid', 'first_char_invalid',
			JSON_OBJECT('keyword_zh', p_keyword_zh, 'keyword_en', p_keyword_en, 'first_char', p_first_char), NOW()
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
		SET o_code = 3001;
		SET o_msg = 'login_invalid';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'keyword', 'create', 'keywords', NULL,
			p_request_id, p_client_ip, 0, 'login_invalid', 'login_invalid',
			JSON_OBJECT('keyword_zh', p_keyword_zh, 'keyword_en', p_keyword_en, 'first_char', p_first_char), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 AND EXISTS (
		SELECT 1
		FROM keywords
		WHERE keyword_zh = v_keyword_zh
		LIMIT 1
		FOR UPDATE
	) THEN
		SET o_code = 3005;
		SET o_msg = 'keyword_zh_exists';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			v_user_id, v_user_type, 'keyword', 'create', 'keywords', NULL,
			p_request_id, p_client_ip, 0, 'keyword_zh_exists', 'keyword_zh_exists',
			JSON_OBJECT('keyword_zh', p_keyword_zh, 'keyword_en', p_keyword_en, 'first_char', p_first_char), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 AND v_keyword_en IS NOT NULL AND EXISTS (
		SELECT 1
		FROM keywords
		WHERE keyword_en = v_keyword_en
		LIMIT 1
		FOR UPDATE
	) THEN
		SET o_code = 3006;
		SET o_msg = 'keyword_en_exists';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			v_user_id, v_user_type, 'keyword', 'create', 'keywords', NULL,
			p_request_id, p_client_ip, 0, 'keyword_en_exists', 'keyword_en_exists',
			JSON_OBJECT('keyword_zh', p_keyword_zh, 'keyword_en', p_keyword_en, 'first_char', p_first_char), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 THEN
		INSERT INTO keywords (
			keyword_zh,
			keyword_en,
			first_char,
			created_at
		) VALUES (
			v_keyword_zh,
			v_keyword_en,
			v_first_char,
			NOW()
		);

		SET v_keyword_id = LAST_INSERT_ID();
		SET o_keyword_id = v_keyword_id;

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
			'keyword',
			'create',
			'keywords',
			CAST(v_keyword_id AS CHAR(100)),
			p_request_id,
			p_client_ip,
			1,
			NULL,
			NULL,
			JSON_OBJECT('keyword_zh', v_keyword_zh, 'keyword_en', v_keyword_en, 'first_char', v_first_char),
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
-- SET @o_keyword_id = NULL;
-- CALL sp_create_keyword(
--     'token_hash_value_64_chars',
--     '数据库',
--     'Database',
--     'D',
--     '127.0.0.1',
--     'req-20260608-0004',
--     @o_code,
--     @o_msg,
--     @o_keyword_id
-- );
-- SELECT @o_code, @o_msg, @o_keyword_id;
