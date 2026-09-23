DELIMITER $$

DROP PROCEDURE IF EXISTS sp_delete_keyword $$
CREATE PROCEDURE sp_delete_keyword(
	IN p_token_hash CHAR(64),
	IN p_keyword_id BIGINT,
	IN p_client_ip VARCHAR(45),
	IN p_request_id VARCHAR(64),
	OUT o_code INT,
	OUT o_msg VARCHAR(100)
)
BEGIN
	DECLARE v_user_id BIGINT DEFAULT NULL;
	DECLARE v_user_type VARCHAR(20) DEFAULT NULL;
	DECLARE v_keyword_exists BIGINT DEFAULT NULL;
	DECLARE v_keyword_zh VARCHAR(100) DEFAULT NULL;
	DECLARE v_keyword_en VARCHAR(100) DEFAULT NULL;
	DECLARE v_first_char CHAR(1) DEFAULT NULL;
	DECLARE v_ref_count BIGINT DEFAULT 0;
	DECLARE v_done TINYINT DEFAULT 0;

	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		ROLLBACK;
		SET o_code = 9000;
		SET o_msg = 'db_error';
	END;

	SET o_code = NULL;
	SET o_msg = NULL;

	START TRANSACTION;

	IF p_token_hash IS NULL OR p_token_hash = '' THEN
		SET o_code = 3202;
		SET o_msg = 'token_required';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'keyword', 'delete', 'keywords', CAST(p_keyword_id AS CHAR(100)),
			p_request_id, p_client_ip, 0, 'token_required', 'token_required',
			JSON_OBJECT(), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 AND (p_keyword_id IS NULL OR p_keyword_id <= 0) THEN
		SET o_code = 3203;
		SET o_msg = 'keyword_id_invalid';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'keyword', 'delete', 'keywords', CAST(p_keyword_id AS CHAR(100)),
			p_request_id, p_client_ip, 0, 'keyword_id_invalid', 'keyword_id_invalid',
			JSON_OBJECT(), NOW()
		);

		SET v_done = 1;
	END IF;

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
		SET o_code = 3201;
		SET o_msg = 'login_invalid';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'keyword', 'delete', 'keywords', CAST(p_keyword_id AS CHAR(100)),
			p_request_id, p_client_ip, 0, 'login_invalid', 'login_invalid',
			JSON_OBJECT(), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 THEN
		SELECT id, keyword_zh, keyword_en, first_char
		INTO v_keyword_exists, v_keyword_zh, v_keyword_en, v_first_char
		FROM keywords
		WHERE id = p_keyword_id
		LIMIT 1
		FOR UPDATE;
	END IF;

	IF v_done = 0 AND v_keyword_exists IS NULL THEN
		SET o_code = 3204;
		SET o_msg = 'keyword_not_found';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			v_user_id, v_user_type, 'keyword', 'delete', 'keywords', CAST(p_keyword_id AS CHAR(100)),
			p_request_id, p_client_ip, 0, 'keyword_not_found', 'keyword_not_found',
			JSON_OBJECT(), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 THEN
		SELECT COUNT(1)
		INTO v_ref_count
		FROM entry_keywords
		WHERE keyword_id = p_keyword_id
		FOR UPDATE;
	END IF;

	IF v_done = 0 AND v_ref_count > 0 THEN
		SET o_code = 3205;
		SET o_msg = 'keyword_in_use';

		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			v_user_id, v_user_type, 'keyword', 'delete', 'keywords', CAST(p_keyword_id AS CHAR(100)),
			p_request_id, p_client_ip, 0, 'keyword_in_use', 'keyword_in_use',
			JSON_OBJECT('ref_count', v_ref_count), NOW()
		);

		SET v_done = 1;
	END IF;

	IF v_done = 0 THEN
		DELETE FROM keywords
		WHERE id = p_keyword_id;

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
			'delete',
			'keywords',
			CAST(p_keyword_id AS CHAR(100)),
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
-- CALL sp_delete_keyword(
--     'token_hash_value_64_chars',
--     1,
--     '127.0.0.1',
--     'req-20260608-0006',
--     @o_code,
--     @o_msg
-- );
-- SELECT @o_code, @o_msg;
