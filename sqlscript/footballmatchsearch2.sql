DELIMITER $$

DROP FUNCTION IF EXISTS fn_search_football_match_results_json $$
CREATE FUNCTION fn_search_football_match_results_json(
	p_token_hash CHAR(64),
	p_home_team_keyword_id BIGINT,
	p_away_team_keyword_id BIGINT,
	p_match_type_keyword_id BIGINT,
	p_season_keyword_id BIGINT,
	p_match_at_start DATETIME,
	p_match_at_end DATETIME
)
RETURNS JSON
READS SQL DATA
BEGIN
	DECLARE v_user_id BIGINT DEFAULT NULL;
	DECLARE v_is_best TINYINT DEFAULT 1;
	DECLARE v_suggestions JSON DEFAULT JSON_ARRAY();
	DECLARE v_range_days INT DEFAULT NULL;
	DECLARE v_total_count BIGINT DEFAULT 0;
	DECLARE v_items JSON DEFAULT JSON_ARRAY();
	DECLARE v_result JSON DEFAULT NULL;

	IF p_token_hash IS NULL OR p_token_hash = '' THEN
		RETURN JSON_OBJECT(
			'code', 3002,
			'msg', 'token_required',
			'is_best', FALSE,
			'suggestions', JSON_ARRAY('provide_valid_login_token'),
			'total', 0,
			'items', JSON_ARRAY()
		);
	END IF;

	SELECT u.id
	INTO v_user_id
	FROM user_tokens t
	INNER JOIN users u ON u.id = t.user_id
	WHERE t.token_hash = p_token_hash
	  AND t.revoked_at IS NULL
	  AND t.expires_at > NOW()
	  AND u.status = 1
	  AND u.deleted_at IS NULL
	LIMIT 1;

	IF v_user_id IS NULL THEN
		RETURN JSON_OBJECT(
			'code', 3001,
			'msg', 'login_invalid',
			'is_best', FALSE,
			'suggestions', JSON_ARRAY('relogin_and_retry'),
			'total', 0,
			'items', JSON_ARRAY()
		);
	END IF;

	IF p_match_at_start IS NULL OR p_match_at_end IS NULL THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'add_match_date_start_and_end');
	ELSEIF p_match_at_start > p_match_at_end THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'match_at_start_must_be_lte_match_at_end');
	ELSE
		SET v_range_days = TIMESTAMPDIFF(DAY, p_match_at_start, p_match_at_end);
		IF v_range_days > 120 THEN
			SET v_is_best = 0;
			SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'date_range_too_large_recommend_within_120_days');
		END IF;
	END IF;

	IF p_home_team_keyword_id IS NULL THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'add_home_team_keyword_id');
	END IF;

	IF p_away_team_keyword_id IS NULL THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'add_away_team_keyword_id');
	END IF;

	IF p_match_type_keyword_id IS NULL THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'add_match_type_keyword_id');
	END IF;

	IF p_season_keyword_id IS NULL THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'add_season_keyword_id');
	END IF;

	IF p_home_team_keyword_id IS NOT NULL
	   AND p_away_team_keyword_id IS NOT NULL
	   AND p_home_team_keyword_id = p_away_team_keyword_id THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'home_team_and_away_team_should_be_different');
	END IF;

	SELECT COUNT(1)
	INTO v_total_count
	FROM football_match_results f
	WHERE (p_home_team_keyword_id IS NULL OR f.home_team_keyword_id = p_home_team_keyword_id)
	  AND (p_away_team_keyword_id IS NULL OR f.away_team_keyword_id = p_away_team_keyword_id)
	  AND (p_match_type_keyword_id IS NULL OR f.match_type_keyword_id = p_match_type_keyword_id)
	  AND (p_season_keyword_id IS NULL OR f.season_keyword_id = p_season_keyword_id)
	  AND (p_match_at_start IS NULL OR f.match_at >= p_match_at_start)
	  AND (p_match_at_end IS NULL OR f.match_at <= p_match_at_end);

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
	) INTO v_items
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

	IF v_total_count = 0 THEN
		SET v_is_best = 0;
		SET v_suggestions = JSON_ARRAY_APPEND(v_suggestions, '$', 'no_result_try_relaxing_filters_or_check_keyword_ids');
	END IF;

	SET v_result = JSON_OBJECT(
		'code', 0,
		'msg', 'ok',
		'is_best', IF(v_is_best = 1, TRUE, FALSE),
		'suggestions', v_suggestions,
		'total', v_total_count,
		'items', v_items
	);

	RETURN v_result;
END $$

DELIMITER ;

-- 调用示例（单条 SELECT）：
-- SELECT fn_search_football_match_results_json(
--     'token_hash_value_64_chars',
--     1001,
--     1002,
--     2001,
--     3001,
--     '2026-01-01 00:00:00',
--     '2026-12-31 23:59:59'
-- ) AS result_json;
