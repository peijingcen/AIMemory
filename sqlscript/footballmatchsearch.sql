DELIMITER $$

DROP PROCEDURE IF EXISTS sp_search_football_match_results $$
CREATE PROCEDURE sp_search_football_match_results(
	IN p_token_hash CHAR(64),
	IN p_home_team_keyword_id BIGINT,
	IN p_away_team_keyword_id BIGINT,
	IN p_match_type_keyword_id BIGINT,
	IN p_season_keyword_id BIGINT,
	IN p_match_at_start DATETIME,
	IN p_match_at_end DATETIME,
	IN p_client_ip VARCHAR(45),
	IN p_request_id VARCHAR(64)
)
BEGIN
	-- =============================================================
	-- 0) 变量声明区
	--    - v_user_id / v_user_type: 当前登录用户信息（来自 token 校验）
	--    - v_done: 控制流程是否提前结束（例如 token 无效时）
	--    - v_is_best / v_suggestion: 查询是否“最佳”以及建议列表
	--    - v_total_count / v_data_json: 查询总数与 JSON 明细结果
	-- =============================================================
	DECLARE v_user_id BIGINT DEFAULT NULL;
	DECLARE v_user_type VARCHAR(20) DEFAULT NULL;
	DECLARE v_done TINYINT DEFAULT 0;
	DECLARE v_is_best TINYINT DEFAULT 1;
	DECLARE v_suggestion JSON DEFAULT JSON_ARRAY();
	DECLARE v_range_days INT DEFAULT NULL;
	DECLARE v_total_count BIGINT DEFAULT 0;
	DECLARE v_data_json JSON DEFAULT JSON_ARRAY();

	-- =============================================================
	-- 1) 异常处理器
	--    任意 SQL 异常触发：
	--    - 回滚事务
	--    - 返回统一错误结果集（code=9000）
	-- =============================================================
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		ROLLBACK;
		SELECT 9000 AS code,
			'db_error' AS msg,
			FALSE AS is_best,
			JSON_ARRAY('db_error_retry_or_check_sql') AS suggestions,
			0 AS total,
			JSON_ARRAY() AS items_json;
	END;

	-- =============================================================
	-- 2) 开启事务
	--    目的：让“校验 + 审计写入 + token 更新时间 + 返回前逻辑”成为一个原子流程。
	-- =============================================================
	START TRANSACTION;

	-- =============================================================
	-- 3) 基础鉴权：token 必填校验
	--    - token 为空：记录失败审计 + 返回 token_required
	-- =============================================================
	IF p_token_hash IS NULL OR p_token_hash = '' THEN
		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'football_match', 'search', 'football_match_results', NULL,
			p_request_id, p_client_ip, 0, 'token_required', 'token_required',
			JSON_OBJECT(
				'home_team_keyword_id', p_home_team_keyword_id,
				'away_team_keyword_id', p_away_team_keyword_id,
				'match_type_keyword_id', p_match_type_keyword_id,
				'season_keyword_id', p_season_keyword_id,
				'match_at_start', p_match_at_start,
				'match_at_end', p_match_at_end
			),
			NOW()
		);

		SELECT 3002 AS code,
			'token_required' AS msg,
			FALSE AS is_best,
			JSON_ARRAY('provide_valid_login_token') AS suggestions,
			0 AS total,
			JSON_ARRAY() AS items_json;

		SET v_done = 1;
	END IF;

	-- =============================================================
	-- 4) 登录态校验（仅在前一步未失败时执行）
	--    校验条件：
	--    - token 命中 user_tokens
	--    - token 未撤销、未过期
	--    - 用户状态正常且未软删除
	--    使用 FOR UPDATE：锁定命中的 token 相关行，减少并发竞争下状态不一致。
	-- =============================================================
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

	-- =============================================================
	-- 5) 登录态无效处理
	--    - 未查到有效用户：记录失败审计 + 返回 login_invalid
	-- =============================================================
	IF v_done = 0 AND v_user_id IS NULL THEN
		INSERT INTO audit_logs (
			user_id, user_type, module, action, target_type, target_id,
			request_id, client_ip, status, error_code, error_message, ext_json, created_at
		) VALUES (
			NULL, NULL, 'football_match', 'search', 'football_match_results', NULL,
			p_request_id, p_client_ip, 0, 'login_invalid', 'login_invalid',
			JSON_OBJECT(
				'home_team_keyword_id', p_home_team_keyword_id,
				'away_team_keyword_id', p_away_team_keyword_id,
				'match_type_keyword_id', p_match_type_keyword_id,
				'season_keyword_id', p_season_keyword_id,
				'match_at_start', p_match_at_start,
				'match_at_end', p_match_at_end
			),
			NOW()
		);

		SELECT 3001 AS code,
			'login_invalid' AS msg,
			FALSE AS is_best,
			JSON_ARRAY('relogin_and_retry') AS suggestions,
			0 AS total,
			JSON_ARRAY() AS items_json;

		SET v_done = 1;
	END IF;

	-- =============================================================
	-- 6) 主流程（仅在鉴权通过时执行）
	-- =============================================================
	IF v_done = 0 THEN
		-- 6.1 查询参数“最佳性”评估：日期范围
		IF p_match_at_start IS NULL OR p_match_at_end IS NULL THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'add_match_date_start_and_end');
		ELSEIF p_match_at_start > p_match_at_end THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'match_at_start_must_be_lte_match_at_end');
		ELSE
			SET v_range_days = TIMESTAMPDIFF(DAY, p_match_at_start, p_match_at_end);
			IF v_range_days > 120 THEN
				SET v_is_best = 0;
				SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'date_range_too_large_recommend_within_120_days');
			END IF;
		END IF;

		-- 6.2 查询参数“最佳性”评估：关键筛选项是否齐全
		IF p_home_team_keyword_id IS NULL THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'add_home_team_keyword_id');
		END IF;

		IF p_away_team_keyword_id IS NULL THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'add_away_team_keyword_id');
		END IF;

		IF p_match_type_keyword_id IS NULL THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'add_match_type_keyword_id');
		END IF;

		IF p_season_keyword_id IS NULL THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'add_season_keyword_id');
		END IF;

		-- 6.3 业务规则校验：主客队不能相同
		IF p_home_team_keyword_id IS NOT NULL
		   AND p_away_team_keyword_id IS NOT NULL
		   AND p_home_team_keyword_id = p_away_team_keyword_id THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'home_team_and_away_team_should_be_different');
		END IF;

		-- 6.4 先查总数，给调用方快速判断是否命中数据
		SELECT COUNT(1)
		INTO v_total_count
		FROM football_match_results f
		WHERE (p_home_team_keyword_id IS NULL OR f.home_team_keyword_id = p_home_team_keyword_id)
		  AND (p_away_team_keyword_id IS NULL OR f.away_team_keyword_id = p_away_team_keyword_id)
		  AND (p_match_type_keyword_id IS NULL OR f.match_type_keyword_id = p_match_type_keyword_id)
		  AND (p_season_keyword_id IS NULL OR f.season_keyword_id = p_season_keyword_id)
		  AND (p_match_at_start IS NULL OR f.match_at >= p_match_at_start)
		  AND (p_match_at_end IS NULL OR f.match_at <= p_match_at_end);

		-- 6.5 生成 JSON 明细数组
		--     - 将比赛结果与关键词表关联，带出中文名称
		--     - 按 match_at/id 倒序，返回最新比赛在前
		SELECT COALESCE(
			JSON_ARRAYAGG(
				JSON_OBJECT(
					'id', q.id,
					'match_type_keyword_id', q.match_type_keyword_id,
					'match_type_keyword_zh', q.match_type_keyword_zh,
					'home_team_keyword_id', q.home_team_keyword_id,
					'home_team_keyword_zh', q.home_team_keyword_zh,
					'away_team_keyword_id', q.away_team_keyword_id,
					'away_team_keyword_zh', q.away_team_keyword_zh,
					'season_keyword_id', q.season_keyword_id,
					'season_keyword_zh', q.season_keyword_zh,
					'seasonround', q.seasonround,
					'match_at', DATE_FORMAT(q.match_at, '%Y-%m-%d %H:%i:%s'),
					'home_ft_goals', q.home_ft_goals,
					'away_ft_goals', q.away_ft_goals,
					'home_ht_goals', q.home_ht_goals,
					'away_ht_goals', q.away_ht_goals,
					'created_at', DATE_FORMAT(q.created_at, '%Y-%m-%d %H:%i:%s'),
					'updated_at', DATE_FORMAT(q.updated_at, '%Y-%m-%d %H:%i:%s')
				)
			),
			JSON_ARRAY()
		) INTO v_data_json
		FROM (
			SELECT
				f.id,
				f.match_type_keyword_id,
				km.keyword_zh AS match_type_keyword_zh,
				f.home_team_keyword_id,
				kh.keyword_zh AS home_team_keyword_zh,
				f.away_team_keyword_id,
				ka.keyword_zh AS away_team_keyword_zh,
				f.season_keyword_id,
				ks.keyword_zh AS season_keyword_zh,
				f.seasonround,
				f.match_at,
				f.home_ft_goals,
				f.away_ft_goals,
				f.home_ht_goals,
				f.away_ht_goals,
				f.created_at,
				f.updated_at
			FROM football_match_results f
			LEFT JOIN keywords km ON km.id = f.match_type_keyword_id
			LEFT JOIN keywords kh ON kh.id = f.home_team_keyword_id
			LEFT JOIN keywords ka ON ka.id = f.away_team_keyword_id
			LEFT JOIN keywords ks ON ks.id = f.season_keyword_id
			WHERE (p_home_team_keyword_id IS NULL OR f.home_team_keyword_id = p_home_team_keyword_id)
			  AND (p_away_team_keyword_id IS NULL OR f.away_team_keyword_id = p_away_team_keyword_id)
			  AND (p_match_type_keyword_id IS NULL OR f.match_type_keyword_id = p_match_type_keyword_id)
			  AND (p_season_keyword_id IS NULL OR f.season_keyword_id = p_season_keyword_id)
			  AND (p_match_at_start IS NULL OR f.match_at >= p_match_at_start)
			  AND (p_match_at_end IS NULL OR f.match_at <= p_match_at_end)
			ORDER BY f.match_at DESC, f.id DESC
		) q;

		-- 6.6 无数据命中时，给出建议
		IF v_total_count = 0 THEN
			SET v_is_best = 0;
			SET v_suggestion = JSON_ARRAY_APPEND(v_suggestion, '$', 'no_result_try_relaxing_filters_or_check_keyword_ids');
		END IF;

		-- 6.7 更新 token 最近使用时间（会话活跃度）
		UPDATE user_tokens
		SET last_used_at = NOW()
		WHERE token_hash = p_token_hash;

		-- 6.8 写入成功审计日志
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
			'football_match',
			'search',
			'football_match_results',
			NULL,
			p_request_id,
			p_client_ip,
			1,
			NULL,
			NULL,
			JSON_OBJECT(
				'home_team_keyword_id', p_home_team_keyword_id,
				'away_team_keyword_id', p_away_team_keyword_id,
				'match_type_keyword_id', p_match_type_keyword_id,
				'season_keyword_id', p_season_keyword_id,
				'match_at_start', p_match_at_start,
				'match_at_end', p_match_at_end,
				'result_count', v_total_count,
				'is_best', IF(v_is_best = 1, TRUE, FALSE)
			),
			NOW()
		);

		-- 6.9 返回单结果集：状态 + 建议 + 总数 + JSON 明细
		SELECT 0 AS code,
			'ok' AS msg,
			IF(v_is_best = 1, TRUE, FALSE) AS is_best,
			v_suggestion AS suggestions,
			v_total_count AS total,
			v_data_json AS items_json;
	END IF;

	-- =============================================================
	-- 7) 提交事务
	-- =============================================================
	COMMIT;
END $$

DELIMITER ;

-- 调用示例：
-- CALL sp_search_football_match_results(
--     'token_hash_value_64_chars',
--     1001,
--     1002,
--     2001,
--     3001,
--     '2026-01-01 00:00:00',
--     '2026-12-31 23:59:59',
--     '127.0.0.1',
--     'req-20260803-0001'
-- );
-- 返回单个结果集：查询状态、是否最佳、建议、总数、items_json（比赛明细 JSON 数组）
