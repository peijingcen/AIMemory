-- 按球队统计比赛结果（总计 + 主场 + 客场）
-- 参数说明：
-- 1) p_match_type_keyword_id: 比赛类型关键词ID，传 0 或 NULL 表示不过滤
-- 2) p_team_keyword_id: 球队关键词ID，传 0 或 NULL 表示不过滤
-- 3) p_season_keyword_id: 赛季关键词ID，传 0 或 NULL 表示不过滤
-- 4) p_Beginmatch_at: 开始时间，DATETIME 类型，传 NULL 表示不过滤
-- 5) p_Endmatch_at: 结束时间，DATETIME 类型，传 NULL 表示不过滤
-- 6) p_display_mode: 返回列模式，0=完整字段，1=关键汇总字段，2=只看净胜/净负分布及汇总数，3=只看半全场及汇总数

DROP PROCEDURE IF EXISTS sp_football_match_stat_by_team;
DELIMITER $$

CREATE PROCEDURE sp_football_match_stat_by_team (
	IN p_match_type_keyword_id BIGINT,
	IN p_team_keyword_id BIGINT,
	IN p_season_keyword_id BIGINT,
	IN p_Beginmatch_at DATETIME,
	IN p_Endmatch_at DATETIME,
	IN p_display_mode TINYINT
)
BEGIN
	IF IFNULL(p_display_mode, 0) = 1 THEN
		SELECT
			t.team_keyword_id,
			k.keyword_zh AS team_keyword_zh,
			k.keyword_en AS team_keyword_en,
			COUNT(*) AS total_matches,
			SUM(CASE WHEN t.goal_diff > 0 THEN 1 ELSE 0 END) AS total_win_matches,
			SUM(CASE WHEN t.goal_diff = 0 THEN 1 ELSE 0 END) AS total_draw,
			SUM(CASE WHEN t.goal_diff = 0 AND t.total_goals > 5 THEN 1 ELSE 0 END) AS total_draw_high_scoring,
			SUM(CASE WHEN t.goal_diff < 0 THEN 1 ELSE 0 END) AS total_lose_matches,
			SUM(CASE WHEN t.team_role = 'HOME' THEN 1 ELSE 0 END) AS home_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff > 0 THEN 1 ELSE 0 END) AS home_win_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 0 THEN 1 ELSE 0 END) AS home_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff < 0 THEN 1 ELSE 0 END) AS home_lose_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' THEN 1 ELSE 0 END) AS away_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff > 0 THEN 1 ELSE 0 END) AS away_win_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 0 THEN 1 ELSE 0 END) AS away_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff < 0 THEN 1 ELSE 0 END) AS away_lose_matches,
			COALESCE(ROUND(AVG(t.team_ft_goals), 3), 0.000) AS total_avg_goals_scored,
			COALESCE(ROUND(AVG(t.opp_ft_goals), 3), 0.000) AS total_avg_goals_conceded,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'HOME' THEN t.team_ft_goals END), 3), 0.000) AS home_avg_goals_scored,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'HOME' THEN t.opp_ft_goals END), 3), 0.000) AS home_avg_goals_conceded,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'AWAY' THEN t.team_ft_goals END), 3), 0.000) AS away_avg_goals_scored,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'AWAY' THEN t.opp_ft_goals END), 3), 0.000) AS away_avg_goals_conceded
		FROM (
			SELECT
				fmr.match_type_keyword_id,
				fmr.season_keyword_id,
				fmr.match_at,
				fmr.home_team_keyword_id AS team_keyword_id,
				'HOME' AS team_role,
				CAST(fmr.home_ft_goals AS SIGNED) AS team_ft_goals,
				CAST(fmr.away_ft_goals AS SIGNED) AS opp_ft_goals,
				(CAST(fmr.home_ft_goals AS SIGNED) - CAST(fmr.away_ft_goals AS SIGNED)) AS goal_diff,
				(CAST(fmr.home_ft_goals AS SIGNED) + CAST(fmr.away_ft_goals AS SIGNED)) AS total_goals,
				CONCAT(
					CASE
						WHEN fmr.home_ht_goals > fmr.away_ht_goals THEN 'W'
						WHEN fmr.home_ht_goals = fmr.away_ht_goals THEN 'D'
						ELSE 'L'
					END,
					CASE
						WHEN fmr.home_ft_goals > fmr.away_ft_goals THEN 'W'
						WHEN fmr.home_ft_goals = fmr.away_ft_goals THEN 'D'
						ELSE 'L'
					END
				) AS htft
			FROM football_match_results fmr
			WHERE fmr.is_finished = 1

			UNION ALL

			SELECT
				fmr.match_type_keyword_id,
				fmr.season_keyword_id,
				fmr.match_at,
				fmr.away_team_keyword_id AS team_keyword_id,
				'AWAY' AS team_role,
				CAST(fmr.away_ft_goals AS SIGNED) AS team_ft_goals,
				CAST(fmr.home_ft_goals AS SIGNED) AS opp_ft_goals,
				(CAST(fmr.away_ft_goals AS SIGNED) - CAST(fmr.home_ft_goals AS SIGNED)) AS goal_diff,
				(CAST(fmr.away_ft_goals AS SIGNED) + CAST(fmr.home_ft_goals AS SIGNED)) AS total_goals,
				CONCAT(
					CASE
						WHEN fmr.away_ht_goals > fmr.home_ht_goals THEN 'W'
						WHEN fmr.away_ht_goals = fmr.home_ht_goals THEN 'D'
						ELSE 'L'
					END,
					CASE
						WHEN fmr.away_ft_goals > fmr.home_ft_goals THEN 'W'
						WHEN fmr.away_ft_goals = fmr.home_ft_goals THEN 'D'
						ELSE 'L'
					END
				) AS htft
			FROM football_match_results fmr
			WHERE fmr.is_finished = 1
		) t
		LEFT JOIN keywords k ON k.id = t.team_keyword_id
		WHERE
			(p_match_type_keyword_id IS NULL OR p_match_type_keyword_id = 0 OR t.match_type_keyword_id = p_match_type_keyword_id)
			AND (p_team_keyword_id IS NULL OR p_team_keyword_id = 0 OR t.team_keyword_id = p_team_keyword_id)
			AND (p_season_keyword_id IS NULL OR p_season_keyword_id = 0 OR t.season_keyword_id = p_season_keyword_id)
			AND (p_Beginmatch_at IS NULL OR t.match_at >= p_Beginmatch_at)
			AND (p_Endmatch_at IS NULL OR t.match_at <= p_Endmatch_at)
		GROUP BY t.team_keyword_id, k.keyword_zh, k.keyword_en
		ORDER BY t.team_keyword_id;
	ELSEIF p_display_mode = 2 THEN
		SELECT
			t.team_keyword_id,
			k.keyword_zh AS team_keyword_zh,
			k.keyword_en AS team_keyword_en,
			COUNT(*) AS total_matches,

			SUM(CASE WHEN t.goal_diff > 0 THEN 1 ELSE 0 END) AS total_win_matches,
			SUM(CASE WHEN t.goal_diff = 1 THEN 1 ELSE 0 END) AS total_win_1,
			SUM(CASE WHEN t.goal_diff = 2 THEN 1 ELSE 0 END) AS total_win_2,
			SUM(CASE WHEN t.goal_diff = 3 THEN 1 ELSE 0 END) AS total_win_3,
			SUM(CASE WHEN t.goal_diff >= 4 THEN 1 ELSE 0 END) AS total_win_4_plus,
			SUM(CASE WHEN t.goal_diff = 0 THEN 1 ELSE 0 END) AS total_draw,
			SUM(CASE WHEN t.goal_diff = 0 AND t.total_goals > 5 THEN 1 ELSE 0 END) AS total_draw_high_scoring,
			SUM(CASE WHEN t.goal_diff < 0 THEN 1 ELSE 0 END) AS total_lose_matches,
			SUM(CASE WHEN t.goal_diff = -1 THEN 1 ELSE 0 END) AS total_lose_1,
			SUM(CASE WHEN t.goal_diff = -2 THEN 1 ELSE 0 END) AS total_lose_2,
			SUM(CASE WHEN t.goal_diff = -3 THEN 1 ELSE 0 END) AS total_lose_3,
			SUM(CASE WHEN t.goal_diff <= -4 THEN 1 ELSE 0 END) AS total_lose_4_plus,

			SUM(CASE WHEN t.team_role = 'HOME' THEN 1 ELSE 0 END) AS home_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff > 0 THEN 1 ELSE 0 END) AS home_win_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 1 THEN 1 ELSE 0 END) AS home_win_1,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 2 THEN 1 ELSE 0 END) AS home_win_2,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 3 THEN 1 ELSE 0 END) AS home_win_3,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff >= 4 THEN 1 ELSE 0 END) AS home_win_4_plus,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 0 THEN 1 ELSE 0 END) AS home_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 0 AND t.total_goals > 5 THEN 1 ELSE 0 END) AS home_draw_high_scoring,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff < 0 THEN 1 ELSE 0 END) AS home_lose_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = -1 THEN 1 ELSE 0 END) AS home_lose_1,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = -2 THEN 1 ELSE 0 END) AS home_lose_2,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = -3 THEN 1 ELSE 0 END) AS home_lose_3,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff <= -4 THEN 1 ELSE 0 END) AS home_lose_4_plus,

			SUM(CASE WHEN t.team_role = 'AWAY' THEN 1 ELSE 0 END) AS away_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff > 0 THEN 1 ELSE 0 END) AS away_win_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 1 THEN 1 ELSE 0 END) AS away_win_1,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 2 THEN 1 ELSE 0 END) AS away_win_2,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 3 THEN 1 ELSE 0 END) AS away_win_3,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff >= 4 THEN 1 ELSE 0 END) AS away_win_4_plus,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 0 THEN 1 ELSE 0 END) AS away_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 0 AND t.total_goals > 5 THEN 1 ELSE 0 END) AS away_draw_high_scoring,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff < 0 THEN 1 ELSE 0 END) AS away_lose_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = -1 THEN 1 ELSE 0 END) AS away_lose_1,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = -2 THEN 1 ELSE 0 END) AS away_lose_2,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = -3 THEN 1 ELSE 0 END) AS away_lose_3,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff <= -4 THEN 1 ELSE 0 END) AS away_lose_4_plus
		FROM (
			SELECT
				fmr.match_type_keyword_id,
				fmr.season_keyword_id,
				fmr.match_at,
				fmr.home_team_keyword_id AS team_keyword_id,
				'HOME' AS team_role,
				CAST(fmr.home_ft_goals AS SIGNED) AS team_ft_goals,
				CAST(fmr.away_ft_goals AS SIGNED) AS opp_ft_goals,
				(CAST(fmr.home_ft_goals AS SIGNED) - CAST(fmr.away_ft_goals AS SIGNED)) AS goal_diff,
				(CAST(fmr.home_ft_goals AS SIGNED) + CAST(fmr.away_ft_goals AS SIGNED)) AS total_goals,
				CONCAT(
					CASE
						WHEN fmr.home_ht_goals > fmr.away_ht_goals THEN 'W'
						WHEN fmr.home_ht_goals = fmr.away_ht_goals THEN 'D'
						ELSE 'L'
					END,
					CASE
						WHEN fmr.home_ft_goals > fmr.away_ft_goals THEN 'W'
						WHEN fmr.home_ft_goals = fmr.away_ft_goals THEN 'D'
						ELSE 'L'
					END
				) AS htft
			FROM football_match_results fmr
			WHERE fmr.is_finished = 1

			UNION ALL

			SELECT
				fmr.match_type_keyword_id,
				fmr.season_keyword_id,
				fmr.match_at,
				fmr.away_team_keyword_id AS team_keyword_id,
				'AWAY' AS team_role,
				CAST(fmr.away_ft_goals AS SIGNED) AS team_ft_goals,
				CAST(fmr.home_ft_goals AS SIGNED) AS opp_ft_goals,
				(CAST(fmr.away_ft_goals AS SIGNED) - CAST(fmr.home_ft_goals AS SIGNED)) AS goal_diff,
				(CAST(fmr.away_ft_goals AS SIGNED) + CAST(fmr.home_ft_goals AS SIGNED)) AS total_goals,
				CONCAT(
					CASE
						WHEN fmr.away_ht_goals > fmr.home_ht_goals THEN 'W'
						WHEN fmr.away_ht_goals = fmr.home_ht_goals THEN 'D'
						ELSE 'L'
					END,
					CASE
						WHEN fmr.away_ft_goals > fmr.home_ft_goals THEN 'W'
						WHEN fmr.away_ft_goals = fmr.home_ft_goals THEN 'D'
						ELSE 'L'
					END
				) AS htft
			FROM football_match_results fmr
			WHERE fmr.is_finished = 1
		) t
		LEFT JOIN keywords k ON k.id = t.team_keyword_id
		WHERE
			(p_match_type_keyword_id IS NULL OR p_match_type_keyword_id = 0 OR t.match_type_keyword_id = p_match_type_keyword_id)
			AND (p_team_keyword_id IS NULL OR p_team_keyword_id = 0 OR t.team_keyword_id = p_team_keyword_id)
			AND (p_season_keyword_id IS NULL OR p_season_keyword_id = 0 OR t.season_keyword_id = p_season_keyword_id)
			AND (p_Beginmatch_at IS NULL OR t.match_at >= p_Beginmatch_at)
			AND (p_Endmatch_at IS NULL OR t.match_at <= p_Endmatch_at)
		GROUP BY t.team_keyword_id, k.keyword_zh, k.keyword_en
		ORDER BY t.team_keyword_id;
	ELSEIF p_display_mode = 3 THEN
		SELECT
			t.team_keyword_id,
			k.keyword_zh AS team_keyword_zh,
			k.keyword_en AS team_keyword_en,
			COUNT(*) AS total_matches,
			SUM(CASE WHEN t.htft = 'WW' THEN 1 ELSE 0 END) AS total_htft_win_win,
			SUM(CASE WHEN t.htft = 'DW' THEN 1 ELSE 0 END) AS total_htft_draw_win,
			SUM(CASE WHEN t.htft = 'LW' THEN 1 ELSE 0 END) AS total_htft_lose_win,
			SUM(CASE WHEN t.htft = 'DD' THEN 1 ELSE 0 END) AS total_htft_draw_draw,
			SUM(CASE WHEN t.htft = 'WD' THEN 1 ELSE 0 END) AS total_htft_win_draw,
			SUM(CASE WHEN t.htft = 'LD' THEN 1 ELSE 0 END) AS total_htft_lose_draw,
			SUM(CASE WHEN t.htft = 'WL' THEN 1 ELSE 0 END) AS total_htft_win_lose,
			SUM(CASE WHEN t.htft = 'DL' THEN 1 ELSE 0 END) AS total_htft_draw_lose,
			SUM(CASE WHEN t.htft = 'LL' THEN 1 ELSE 0 END) AS total_htft_lose_lose,

			SUM(CASE WHEN t.team_role = 'HOME' THEN 1 ELSE 0 END) AS home_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'WW' THEN 1 ELSE 0 END) AS home_htft_win_win,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'DW' THEN 1 ELSE 0 END) AS home_htft_draw_win,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'LW' THEN 1 ELSE 0 END) AS home_htft_lose_win,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'DD' THEN 1 ELSE 0 END) AS home_htft_draw_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'WD' THEN 1 ELSE 0 END) AS home_htft_win_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'LD' THEN 1 ELSE 0 END) AS home_htft_lose_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'WL' THEN 1 ELSE 0 END) AS home_htft_win_lose,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'DL' THEN 1 ELSE 0 END) AS home_htft_draw_lose,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'LL' THEN 1 ELSE 0 END) AS home_htft_lose_lose,

			SUM(CASE WHEN t.team_role = 'AWAY' THEN 1 ELSE 0 END) AS away_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'WW' THEN 1 ELSE 0 END) AS away_htft_win_win,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'DW' THEN 1 ELSE 0 END) AS away_htft_draw_win,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'LW' THEN 1 ELSE 0 END) AS away_htft_lose_win,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'DD' THEN 1 ELSE 0 END) AS away_htft_draw_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'WD' THEN 1 ELSE 0 END) AS away_htft_win_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'LD' THEN 1 ELSE 0 END) AS away_htft_lose_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'WL' THEN 1 ELSE 0 END) AS away_htft_win_lose,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'DL' THEN 1 ELSE 0 END) AS away_htft_draw_lose,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'LL' THEN 1 ELSE 0 END) AS away_htft_lose_lose
		FROM (
			SELECT
				fmr.match_type_keyword_id,
				fmr.season_keyword_id,
				fmr.match_at,
				fmr.home_team_keyword_id AS team_keyword_id,
				'HOME' AS team_role,
				CAST(fmr.home_ft_goals AS SIGNED) AS team_ft_goals,
				CAST(fmr.away_ft_goals AS SIGNED) AS opp_ft_goals,
				(CAST(fmr.home_ft_goals AS SIGNED) - CAST(fmr.away_ft_goals AS SIGNED)) AS goal_diff,
				(CAST(fmr.home_ft_goals AS SIGNED) + CAST(fmr.away_ft_goals AS SIGNED)) AS total_goals,
				CONCAT(
					CASE
						WHEN fmr.home_ht_goals > fmr.away_ht_goals THEN 'W'
						WHEN fmr.home_ht_goals = fmr.away_ht_goals THEN 'D'
						ELSE 'L'
					END,
					CASE
						WHEN fmr.home_ft_goals > fmr.away_ft_goals THEN 'W'
						WHEN fmr.home_ft_goals = fmr.away_ft_goals THEN 'D'
						ELSE 'L'
					END
				) AS htft
			FROM football_match_results fmr
			WHERE fmr.is_finished = 1

			UNION ALL

			SELECT
				fmr.match_type_keyword_id,
				fmr.season_keyword_id,
				fmr.match_at,
				fmr.away_team_keyword_id AS team_keyword_id,
				'AWAY' AS team_role,
				CAST(fmr.away_ft_goals AS SIGNED) AS team_ft_goals,
				CAST(fmr.home_ft_goals AS SIGNED) AS opp_ft_goals,
				(CAST(fmr.away_ft_goals AS SIGNED) - CAST(fmr.home_ft_goals AS SIGNED)) AS goal_diff,
				(CAST(fmr.away_ft_goals AS SIGNED) + CAST(fmr.home_ft_goals AS SIGNED)) AS total_goals,
				CONCAT(
					CASE
						WHEN fmr.away_ht_goals > fmr.home_ht_goals THEN 'W'
						WHEN fmr.away_ht_goals = fmr.home_ht_goals THEN 'D'
						ELSE 'L'
					END,
					CASE
						WHEN fmr.away_ft_goals > fmr.home_ft_goals THEN 'W'
						WHEN fmr.away_ft_goals = fmr.home_ft_goals THEN 'D'
						ELSE 'L'
					END
				) AS htft
			FROM football_match_results fmr
			WHERE fmr.is_finished = 1
		) t
		LEFT JOIN keywords k ON k.id = t.team_keyword_id
		WHERE
			(p_match_type_keyword_id IS NULL OR p_match_type_keyword_id = 0 OR t.match_type_keyword_id = p_match_type_keyword_id)
			AND (p_team_keyword_id IS NULL OR p_team_keyword_id = 0 OR t.team_keyword_id = p_team_keyword_id)
			AND (p_season_keyword_id IS NULL OR p_season_keyword_id = 0 OR t.season_keyword_id = p_season_keyword_id)
			AND (p_Beginmatch_at IS NULL OR t.match_at >= p_Beginmatch_at)
			AND (p_Endmatch_at IS NULL OR t.match_at <= p_Endmatch_at)
		GROUP BY t.team_keyword_id, k.keyword_zh, k.keyword_en
		ORDER BY t.team_keyword_id;
	ELSE
		SELECT
			t.team_keyword_id,
			k.keyword_zh AS team_keyword_zh,
			k.keyword_en AS team_keyword_en,

			-- 总计：净胜/净负分布
			SUM(CASE WHEN t.goal_diff > 0 THEN 1 ELSE 0 END) AS total_win_matches,
			SUM(CASE WHEN t.goal_diff = 1 THEN 1 ELSE 0 END) AS total_win_1,
			SUM(CASE WHEN t.goal_diff = 2 THEN 1 ELSE 0 END) AS total_win_2,
			SUM(CASE WHEN t.goal_diff = 3 THEN 1 ELSE 0 END) AS total_win_3,
			SUM(CASE WHEN t.goal_diff >= 4 THEN 1 ELSE 0 END) AS total_win_4_plus,
			SUM(CASE WHEN t.goal_diff = 0 THEN 1 ELSE 0 END) AS total_draw,
			SUM(CASE WHEN t.goal_diff = 0 AND t.total_goals > 5 THEN 1 ELSE 0 END) AS total_draw_high_scoring,
			SUM(CASE WHEN t.goal_diff < 0 THEN 1 ELSE 0 END) AS total_lose_matches,
			SUM(CASE WHEN t.goal_diff = -1 THEN 1 ELSE 0 END) AS total_lose_1,
			SUM(CASE WHEN t.goal_diff = -2 THEN 1 ELSE 0 END) AS total_lose_2,
			SUM(CASE WHEN t.goal_diff = -3 THEN 1 ELSE 0 END) AS total_lose_3,
			SUM(CASE WHEN t.goal_diff <= -4 THEN 1 ELSE 0 END) AS total_lose_4_plus,

			-- 总计：半全场
			SUM(CASE WHEN t.htft = 'WW' THEN 1 ELSE 0 END) AS total_htft_win_win,
			SUM(CASE WHEN t.htft = 'DW' THEN 1 ELSE 0 END) AS total_htft_draw_win,
			SUM(CASE WHEN t.htft = 'LW' THEN 1 ELSE 0 END) AS total_htft_lose_win,
			SUM(CASE WHEN t.htft = 'DD' THEN 1 ELSE 0 END) AS total_htft_draw_draw,
			SUM(CASE WHEN t.htft = 'WD' THEN 1 ELSE 0 END) AS total_htft_win_draw,
			SUM(CASE WHEN t.htft = 'LD' THEN 1 ELSE 0 END) AS total_htft_lose_draw,
			SUM(CASE WHEN t.htft = 'WL' THEN 1 ELSE 0 END) AS total_htft_win_lose,
			SUM(CASE WHEN t.htft = 'DL' THEN 1 ELSE 0 END) AS total_htft_draw_lose,
			SUM(CASE WHEN t.htft = 'LL' THEN 1 ELSE 0 END) AS total_htft_lose_lose,

			-- 主场：净胜/净负分布
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff > 0 THEN 1 ELSE 0 END) AS home_win_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 1 THEN 1 ELSE 0 END) AS home_win_1,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 2 THEN 1 ELSE 0 END) AS home_win_2,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 3 THEN 1 ELSE 0 END) AS home_win_3,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff >= 4 THEN 1 ELSE 0 END) AS home_win_4_plus,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 0 THEN 1 ELSE 0 END) AS home_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = 0 AND t.total_goals > 5 THEN 1 ELSE 0 END) AS home_draw_high_scoring,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff < 0 THEN 1 ELSE 0 END) AS home_lose_matches,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = -1 THEN 1 ELSE 0 END) AS home_lose_1,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = -2 THEN 1 ELSE 0 END) AS home_lose_2,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff = -3 THEN 1 ELSE 0 END) AS home_lose_3,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.goal_diff <= -4 THEN 1 ELSE 0 END) AS home_lose_4_plus,

			-- 主场：半全场
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'WW' THEN 1 ELSE 0 END) AS home_htft_win_win,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'DW' THEN 1 ELSE 0 END) AS home_htft_draw_win,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'LW' THEN 1 ELSE 0 END) AS home_htft_lose_win,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'DD' THEN 1 ELSE 0 END) AS home_htft_draw_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'WD' THEN 1 ELSE 0 END) AS home_htft_win_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'LD' THEN 1 ELSE 0 END) AS home_htft_lose_draw,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'WL' THEN 1 ELSE 0 END) AS home_htft_win_lose,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'DL' THEN 1 ELSE 0 END) AS home_htft_draw_lose,
			SUM(CASE WHEN t.team_role = 'HOME' AND t.htft = 'LL' THEN 1 ELSE 0 END) AS home_htft_lose_lose,

			-- 客场：净胜/净负分布
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff > 0 THEN 1 ELSE 0 END) AS away_win_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 1 THEN 1 ELSE 0 END) AS away_win_1,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 2 THEN 1 ELSE 0 END) AS away_win_2,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 3 THEN 1 ELSE 0 END) AS away_win_3,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff >= 4 THEN 1 ELSE 0 END) AS away_win_4_plus,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 0 THEN 1 ELSE 0 END) AS away_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = 0 AND t.total_goals > 5 THEN 1 ELSE 0 END) AS away_draw_high_scoring,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff < 0 THEN 1 ELSE 0 END) AS away_lose_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = -1 THEN 1 ELSE 0 END) AS away_lose_1,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = -2 THEN 1 ELSE 0 END) AS away_lose_2,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff = -3 THEN 1 ELSE 0 END) AS away_lose_3,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.goal_diff <= -4 THEN 1 ELSE 0 END) AS away_lose_4_plus,

			-- 客场：半全场
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'WW' THEN 1 ELSE 0 END) AS away_htft_win_win,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'DW' THEN 1 ELSE 0 END) AS away_htft_draw_win,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'LW' THEN 1 ELSE 0 END) AS away_htft_lose_win,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'DD' THEN 1 ELSE 0 END) AS away_htft_draw_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'WD' THEN 1 ELSE 0 END) AS away_htft_win_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'LD' THEN 1 ELSE 0 END) AS away_htft_lose_draw,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'WL' THEN 1 ELSE 0 END) AS away_htft_win_lose,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'DL' THEN 1 ELSE 0 END) AS away_htft_draw_lose,
			SUM(CASE WHEN t.team_role = 'AWAY' AND t.htft = 'LL' THEN 1 ELSE 0 END) AS away_htft_lose_lose,

			COUNT(*) AS total_matches,
			SUM(CASE WHEN t.team_role = 'HOME' THEN 1 ELSE 0 END) AS home_matches,
			SUM(CASE WHEN t.team_role = 'AWAY' THEN 1 ELSE 0 END) AS away_matches,
			COALESCE(ROUND(AVG(t.team_ft_goals), 3), 0.000) AS total_avg_goals_scored,
			COALESCE(ROUND(AVG(t.opp_ft_goals), 3), 0.000) AS total_avg_goals_conceded,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'HOME' THEN t.team_ft_goals END), 3), 0.000) AS home_avg_goals_scored,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'HOME' THEN t.opp_ft_goals END), 3), 0.000) AS home_avg_goals_conceded,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'AWAY' THEN t.team_ft_goals END), 3), 0.000) AS away_avg_goals_scored,
			COALESCE(ROUND(AVG(CASE WHEN t.team_role = 'AWAY' THEN t.opp_ft_goals END), 3), 0.000) AS away_avg_goals_conceded
		FROM (
		SELECT
			fmr.match_type_keyword_id,
			fmr.season_keyword_id,
			fmr.match_at,
			fmr.home_team_keyword_id AS team_keyword_id,
			'HOME' AS team_role,
			CAST(fmr.home_ft_goals AS SIGNED) AS team_ft_goals,
			CAST(fmr.away_ft_goals AS SIGNED) AS opp_ft_goals,
			(CAST(fmr.home_ft_goals AS SIGNED) - CAST(fmr.away_ft_goals AS SIGNED)) AS goal_diff,
			(CAST(fmr.home_ft_goals AS SIGNED) + CAST(fmr.away_ft_goals AS SIGNED)) AS total_goals,
			CONCAT(
				CASE
					WHEN fmr.home_ht_goals > fmr.away_ht_goals THEN 'W'
					WHEN fmr.home_ht_goals = fmr.away_ht_goals THEN 'D'
					ELSE 'L'
				END,
				CASE
					WHEN fmr.home_ft_goals > fmr.away_ft_goals THEN 'W'
					WHEN fmr.home_ft_goals = fmr.away_ft_goals THEN 'D'
					ELSE 'L'
				END
			) AS htft
		FROM football_match_results fmr
		WHERE fmr.is_finished = 1

		UNION ALL

		SELECT
			fmr.match_type_keyword_id,
			fmr.season_keyword_id,
			fmr.match_at,
			fmr.away_team_keyword_id AS team_keyword_id,
			'AWAY' AS team_role,
			CAST(fmr.away_ft_goals AS SIGNED) AS team_ft_goals,
			CAST(fmr.home_ft_goals AS SIGNED) AS opp_ft_goals,
			(CAST(fmr.away_ft_goals AS SIGNED) - CAST(fmr.home_ft_goals AS SIGNED)) AS goal_diff,
			(CAST(fmr.away_ft_goals AS SIGNED) + CAST(fmr.home_ft_goals AS SIGNED)) AS total_goals,
			CONCAT(
				CASE
					WHEN fmr.away_ht_goals > fmr.home_ht_goals THEN 'W'
					WHEN fmr.away_ht_goals = fmr.home_ht_goals THEN 'D'
					ELSE 'L'
				END,
				CASE
					WHEN fmr.away_ft_goals > fmr.home_ft_goals THEN 'W'
					WHEN fmr.away_ft_goals = fmr.home_ft_goals THEN 'D'
					ELSE 'L'
				END
			) AS htft
		FROM football_match_results fmr
		WHERE fmr.is_finished = 1
	) t
	LEFT JOIN keywords k ON k.id = t.team_keyword_id
	WHERE
		(p_match_type_keyword_id IS NULL OR p_match_type_keyword_id = 0 OR t.match_type_keyword_id = p_match_type_keyword_id)
		AND (p_team_keyword_id IS NULL OR p_team_keyword_id = 0 OR t.team_keyword_id = p_team_keyword_id)
		AND (p_season_keyword_id IS NULL OR p_season_keyword_id = 0 OR t.season_keyword_id = p_season_keyword_id)
		AND (p_Beginmatch_at IS NULL OR t.match_at >= p_Beginmatch_at)
		AND (p_Endmatch_at IS NULL OR t.match_at <= p_Endmatch_at)
		GROUP BY t.team_keyword_id, k.keyword_zh, k.keyword_en
		ORDER BY t.team_keyword_id;
	END IF;
END $$

DELIMITER ;

-- 调用示例
-- CALL sp_football_match_stat_by_team(0, 0, 0, NULL, NULL, 0);
-- CALL sp_football_match_stat_by_team(0, 0, 0, NULL, NULL, 1);
-- CALL sp_football_match_stat_by_team(0, 0, 0, NULL, NULL, 2);
-- CALL sp_football_match_stat_by_team(0, 0, 0, NULL, NULL, 3);
-- CALL sp_football_match_stat_by_team(12, 0, 2026, '2026-01-01 00:00:00', '2026-12-31 23:59:59', 0);
-- CALL sp_football_match_stat_by_team(12, 0, 2026, '2026-01-01 00:00:00', '2026-12-31 23:59:59', 1);
