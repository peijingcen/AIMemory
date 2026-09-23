DELIMITER $$

DROP PROCEDURE IF EXISTS sp_user_login $$
CREATE PROCEDURE sp_user_login(
	IN p_username VARCHAR(50),
	IN p_password_hash VARCHAR(255),
	IN p_client_ip VARCHAR(45),
	IN p_user_agent VARCHAR(255),
	IN p_device_id VARCHAR(100),
	IN p_token_hash CHAR(64),
	IN p_token_expires_at DATETIME,
	OUT o_code INT,
	OUT o_user_id BIGINT,
	OUT o_user_type VARCHAR(20),
	OUT o_msg VARCHAR(100)
)
BEGIN
	-- 用户信息临时变量
	DECLARE v_id BIGINT DEFAULT NULL;
	DECLARE v_pwd_hash VARCHAR(255) DEFAULT NULL;
	DECLARE v_status TINYINT DEFAULT NULL;
	DECLARE v_lock_until DATETIME DEFAULT NULL;
	DECLARE v_failed INT DEFAULT 0;
	DECLARE v_user_type VARCHAR(20) DEFAULT NULL;
	DECLARE v_done TINYINT DEFAULT 0;

	-- 安全策略参数
	DECLARE v_max_failed INT DEFAULT 5;
	DECLARE v_lock_minutes INT DEFAULT 15;

	-- 任意 SQL 异常时回滚并返回统一错误码
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		ROLLBACK;
		SET o_code = 9000;
		SET o_user_id = NULL;
		SET o_user_type = NULL;
		SET o_msg = 'db_error';
	END;

	-- 初始化输出参数
	SET o_code = NULL;
	SET o_user_id = NULL;
	SET o_user_type = NULL;
	SET o_msg = NULL;

	START TRANSACTION;

	-- 锁定用户行，避免并发登录导致失败次数/锁定状态被覆盖
	SELECT
		id, password_hash, status, lock_until, failed_login_count, user_type
	INTO
		v_id, v_pwd_hash, v_status, v_lock_until, v_failed, v_user_type
	FROM users
	WHERE username = p_username
	  AND deleted_at IS NULL
	LIMIT 1
	FOR UPDATE;

	-- 1001: 账号不存在
	IF v_id IS NULL THEN
		SET o_code = 1001;
		SET o_msg = 'username_not_found';
		SET v_done = 1;
	END IF;

	-- 1003: 账号禁用
	IF v_done = 0 AND v_status = 0 THEN
		SET o_code = 1003;
		SET o_user_id = v_id;
		SET o_user_type = v_user_type;
		SET o_msg = 'account_disabled';
		SET v_done = 1;
	END IF;

	-- 1004: 账号仍在锁定窗口内
	IF v_done = 0 AND v_lock_until IS NOT NULL AND v_lock_until > NOW() THEN
		SET o_code = 1004;
		SET o_user_id = v_id;
		SET o_user_type = v_user_type;
		SET o_msg = 'account_locked';
		SET v_done = 1;
	END IF;

	-- 1002/1004: 密码错误，累计失败并按阈值锁定
	IF v_done = 0 AND v_pwd_hash <> p_password_hash THEN
		SET v_failed = v_failed + 1;

		IF v_failed >= v_max_failed THEN
			UPDATE users
			SET failed_login_count = v_failed,
				lock_until = DATE_ADD(NOW(), INTERVAL v_lock_minutes MINUTE),
				updated_at = NOW()
			WHERE id = v_id;

			SET o_code = 1004;
			SET o_msg = 'account_locked';
		ELSE
			UPDATE users
			SET failed_login_count = v_failed,
				updated_at = NOW()
			WHERE id = v_id;

			SET o_code = 1002;
			SET o_msg = 'password_incorrect';
		END IF;

		SET o_user_id = v_id;
		SET o_user_type = v_user_type;
		SET v_done = 1;
	END IF;

	-- 1005: 登录成功但缺少 token 参数，拒绝放行，防止出现“成功却无会话”的状态
	IF v_done = 0 AND (p_token_hash IS NULL OR p_token_expires_at IS NULL) THEN
		SET o_code = 1005;
		SET o_user_id = v_id;
		SET o_user_type = v_user_type;
		SET o_msg = 'token_args_required';
		SET v_done = 1;
	END IF;

	IF v_done = 0 THEN
		-- 登录成功：重置失败计数和锁定状态
		UPDATE users
		SET failed_login_count = 0,
			lock_until = NULL,
			last_login_at = NOW(),
			last_login_ip = p_client_ip,
			updated_at = NOW()
		WHERE id = v_id;

		-- 撤销旧令牌：
		-- 1) 传 device_id：仅撤销该设备下未撤销令牌
		-- 2) 不传 device_id：撤销该用户全部未撤销令牌
		IF p_device_id IS NULL OR p_device_id = '' THEN
			UPDATE user_tokens
			SET revoked_at = NOW()
			WHERE user_id = v_id
			  AND revoked_at IS NULL;
		ELSE
			UPDATE user_tokens
			SET revoked_at = NOW()
			WHERE user_id = v_id
			  AND revoked_at IS NULL
			  AND device_id = p_device_id;
		END IF;

		-- 写入新的单会话 token
		INSERT INTO user_tokens (
			user_id, token_hash, issued_at, expires_at,
			revoked_at, last_used_at, client_ip, user_agent, device_id, created_at
		) VALUES (
			v_id, p_token_hash, NOW(), p_token_expires_at,
			NULL, NOW(), p_client_ip, p_user_agent, p_device_id, NOW()
		);

		-- 0: 登录成功并完成 token 更新
		SET o_code = 0;
		SET o_user_id = v_id;
		SET o_user_type = v_user_type;
		SET o_msg = 'ok';
	END IF;

	-- 记录登录日志：除账号不存在(1001)外，其它结果均记录
	IF o_code IS NOT NULL AND o_code <> 1001 THEN
		INSERT INTO login_logs (
			user_id,
			username_input,
			user_type,
			result_code,
			result_msg,
			client_ip,
			user_agent,
			device_id,
			created_at
		) VALUES (
			o_user_id,
			p_username,
			o_user_type,
			o_code,
			o_msg,
			p_client_ip,
			p_user_agent,
			p_device_id,
			NOW()
		);
	END IF;

	COMMIT;
END $$
DELIMITER ;

-- 调用示例：
-- SET @o_code = NULL;
-- SET @o_user_id = NULL;
-- SET @o_user_type = NULL;
-- SET @o_msg = NULL;
-- CALL sp_user_login(
--     'admin',
--     'password_hash_value',
--     '127.0.0.1',
--     'Mozilla/5.0',
--     'device-001',
--     'token_hash_value_64_chars',
--     '2026-06-08 23:59:59',
--     @o_code,
--     @o_user_id,
--     @o_user_type,
--     @o_msg
-- );
-- SELECT @o_code, @o_user_id, @o_user_type, @o_msg;