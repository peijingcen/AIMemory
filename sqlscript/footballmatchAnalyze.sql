-- 查询未完成的比赛数据
-- 参数说明：
-- 1) p_match_type_keyword_id: 比赛类型关键词ID，传 0 或 NULL 表示不过滤
-- 2) p_season_keyword_id: 赛季关键词ID，传 0 或 NULL 表示不过滤
-- 3) p_seasonround: 当前轮次，传 0 或 NULL 表示不过滤
-- 4) p_match_keyword_id: 比赛ID，传 0 或 NULL 表示不过滤
-- 5) p_UpcomingBeginmatch_at: 将要开始比赛筛选开始时间，DATETIME 类型，传 NULL 表示不过滤
-- 6) p_UpcomingEndmatch_at: 将要开始比赛筛选结束时间，DATETIME 类型，传 NULL 表示不过滤
-- 7) p_Beginmatch_at: 开始时间，DATETIME 类型，传 NULL 表示不过滤，用于统计主客队区间战绩
-- 8) p_Endmatch_at: 结束时间，DATETIME 类型，传 NULL 表示不过滤，用于统计主客队区间战绩
-- 9) p_RecentBeginmatch_at: 近期开始时间，DATETIME 类型，传 NULL 表示不过滤，用于统计主客队近期胜平负
-- 10) p_RecentEndmatch_at: 近期结束时间，DATETIME 类型，传 NULL 表示不过滤，用于统计主客队近期胜平负

DROP PROCEDURE IF EXISTS sp_analyze_unfinished_football_matches;
DELIMITER $$

CREATE PROCEDURE sp_analyze_unfinished_football_matches (
	IN p_match_type_keyword_id BIGINT,
	IN p_season_keyword_id BIGINT,
	IN p_seasonround TINYINT UNSIGNED,
	IN p_match_keyword_id BIGINT,
	IN p_UpcomingBeginmatch_at DATETIME,
	IN p_UpcomingEndmatch_at DATETIME,
	IN p_Beginmatch_at DATETIME,
	IN p_Endmatch_at DATETIME,
	IN p_RecentBeginmatch_at DATETIME,
	IN p_RecentEndmatch_at DATETIME
)
BEGIN
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_role;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_total;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_recent_stats;

	CREATE TEMPORARY TABLE tmp_team_stats_role AS
	SELECT
		t.team_keyword_id,
		t.team_role,
		COUNT(*) AS total_matches,
		SUM(CASE WHEN t.goal_diff > 0 THEN 1 ELSE 0 END) AS win_matches,
		SUM(CASE WHEN t.goal_diff = 0 THEN 1 ELSE 0 END) AS draw_matches,
		SUM(CASE WHEN t.goal_diff < 0 THEN 1 ELSE 0 END) AS lose_matches,
		SUM(CASE WHEN t.goal_diff = 1 THEN 1 ELSE 0 END) AS win_1,
		SUM(CASE WHEN t.goal_diff = 2 THEN 1 ELSE 0 END) AS win_2,
		SUM(CASE WHEN t.goal_diff = 3 THEN 1 ELSE 0 END) AS win_3,
		SUM(CASE WHEN t.goal_diff >= 4 THEN 1 ELSE 0 END) AS win_4_plus,
		SUM(CASE WHEN t.goal_diff = -1 THEN 1 ELSE 0 END) AS lose_1,
		SUM(CASE WHEN t.goal_diff = -2 THEN 1 ELSE 0 END) AS lose_2,
		SUM(CASE WHEN t.goal_diff = -3 THEN 1 ELSE 0 END) AS lose_3,
		SUM(CASE WHEN t.goal_diff <= -4 THEN 1 ELSE 0 END) AS lose_4_plus,
		SUM(t.goals_for) AS total_goals_for,
		SUM(CASE WHEN t.htft = 'WW' THEN 1 ELSE 0 END) AS htft_ww,
		SUM(CASE WHEN t.htft = 'DW' THEN 1 ELSE 0 END) AS htft_dw,
		SUM(CASE WHEN t.htft = 'LW' THEN 1 ELSE 0 END) AS htft_lw,
		SUM(CASE WHEN t.htft = 'DD' THEN 1 ELSE 0 END) AS htft_dd,
		SUM(CASE WHEN t.htft = 'WD' THEN 1 ELSE 0 END) AS htft_wd,
		SUM(CASE WHEN t.htft = 'LD' THEN 1 ELSE 0 END) AS htft_ld,
		SUM(CASE WHEN t.htft = 'WL' THEN 1 ELSE 0 END) AS htft_wl,
		SUM(CASE WHEN t.htft = 'DL' THEN 1 ELSE 0 END) AS htft_dl,
		SUM(CASE WHEN t.htft = 'LL' THEN 1 ELSE 0 END) AS htft_ll
	FROM (
		SELECT
			f1.home_team_keyword_id AS team_keyword_id,
			'HOME' AS team_role,
			(CAST(f1.home_ft_goals AS SIGNED) - CAST(f1.away_ft_goals AS SIGNED)) AS goal_diff,
			CAST(f1.home_ft_goals AS SIGNED) AS goals_for,
			CONCAT(
				CASE WHEN f1.home_ht_goals > f1.away_ht_goals THEN 'W' WHEN f1.home_ht_goals = f1.away_ht_goals THEN 'D' ELSE 'L' END,
				CASE WHEN f1.home_ft_goals > f1.away_ft_goals THEN 'W' WHEN f1.home_ft_goals = f1.away_ft_goals THEN 'D' ELSE 'L' END
			) AS htft,
			f1.match_at
		FROM football_match_results f1
		WHERE f1.is_finished = 1
		  AND (p_Beginmatch_at IS NULL OR f1.match_at >= p_Beginmatch_at)
		  AND (p_Endmatch_at IS NULL OR f1.match_at <= p_Endmatch_at)

		UNION ALL

		SELECT
			f2.away_team_keyword_id AS team_keyword_id,
			'AWAY' AS team_role,
			(CAST(f2.away_ft_goals AS SIGNED) - CAST(f2.home_ft_goals AS SIGNED)) AS goal_diff,
			CAST(f2.away_ft_goals AS SIGNED) AS goals_for,
			CONCAT(
				CASE WHEN f2.away_ht_goals > f2.home_ht_goals THEN 'W' WHEN f2.away_ht_goals = f2.home_ht_goals THEN 'D' ELSE 'L' END,
				CASE WHEN f2.away_ft_goals > f2.home_ft_goals THEN 'W' WHEN f2.away_ft_goals = f2.home_ft_goals THEN 'D' ELSE 'L' END
			) AS htft,
			f2.match_at
		FROM football_match_results f2
		WHERE f2.is_finished = 1
		  AND (p_Beginmatch_at IS NULL OR f2.match_at >= p_Beginmatch_at)
		  AND (p_Endmatch_at IS NULL OR f2.match_at <= p_Endmatch_at)
	) t
	GROUP BY t.team_keyword_id, t.team_role;

	ALTER TABLE tmp_team_stats_role
		ADD INDEX idx_tmp_team_stats_role_team (team_keyword_id),
		ADD INDEX idx_tmp_team_stats_role_team_role (team_keyword_id, team_role);

	CREATE TEMPORARY TABLE tmp_team_stats_total AS
	SELECT
		team_keyword_id,
		SUM(total_matches) AS total_matches,
		SUM(win_matches) AS win_matches,
		SUM(draw_matches) AS draw_matches,
		SUM(lose_matches) AS lose_matches,
		SUM(win_1) AS win_1,
		SUM(win_2) AS win_2,
		SUM(win_3) AS win_3,
		SUM(win_4_plus) AS win_4_plus,
		SUM(lose_1) AS lose_1,
		SUM(lose_2) AS lose_2,
		SUM(lose_3) AS lose_3,
		SUM(lose_4_plus) AS lose_4_plus,
		SUM(total_goals_for) AS total_goals_for,
		SUM(htft_ww) AS htft_ww,
		SUM(htft_dw) AS htft_dw,
		SUM(htft_lw) AS htft_lw,
		SUM(htft_dd) AS htft_dd,
		SUM(htft_wd) AS htft_wd,
		SUM(htft_ld) AS htft_ld,
		SUM(htft_wl) AS htft_wl,
		SUM(htft_dl) AS htft_dl,
		SUM(htft_ll) AS htft_ll
	FROM tmp_team_stats_role
	GROUP BY team_keyword_id;

	ALTER TABLE tmp_team_stats_total
		ADD INDEX idx_tmp_team_stats_total_team (team_keyword_id);

	CREATE TEMPORARY TABLE tmp_team_recent_stats AS
	SELECT
		r.team_keyword_id,
		COUNT(*) AS recent_total_matches,
		SUM(CASE WHEN r.goal_diff > 0 THEN 1 ELSE 0 END) AS recent_win_matches,
		SUM(CASE WHEN r.goal_diff = 0 THEN 1 ELSE 0 END) AS recent_draw_matches,
		SUM(CASE WHEN r.goal_diff < 0 THEN 1 ELSE 0 END) AS recent_lose_matches
	FROM (
		SELECT
			f1.home_team_keyword_id AS team_keyword_id,
			(CAST(f1.home_ft_goals AS SIGNED) - CAST(f1.away_ft_goals AS SIGNED)) AS goal_diff,
			f1.match_at
		FROM football_match_results f1
		WHERE f1.is_finished = 1
		  AND (p_RecentBeginmatch_at IS NULL OR f1.match_at >= p_RecentBeginmatch_at)
		  AND (p_RecentEndmatch_at IS NULL OR f1.match_at <= p_RecentEndmatch_at)

		UNION ALL

		SELECT
			f2.away_team_keyword_id AS team_keyword_id,
			(CAST(f2.away_ft_goals AS SIGNED) - CAST(f2.home_ft_goals AS SIGNED)) AS goal_diff,
			f2.match_at
		FROM football_match_results f2
		WHERE f2.is_finished = 1
		  AND (p_RecentBeginmatch_at IS NULL OR f2.match_at >= p_RecentBeginmatch_at)
		  AND (p_RecentEndmatch_at IS NULL OR f2.match_at <= p_RecentEndmatch_at)
	) r
	GROUP BY r.team_keyword_id;

	ALTER TABLE tmp_team_recent_stats
		ADD INDEX idx_tmp_team_recent_stats_team (team_keyword_id);

	-- MySQL 对临时表有“同一条 SQL 不能重复 reopen”限制，给每个 JOIN 准备独立副本
	CREATE TEMPORARY TABLE tmp_team_stats_total_home AS
	SELECT * FROM tmp_team_stats_total;

	CREATE TEMPORARY TABLE tmp_team_stats_total_away AS
	SELECT * FROM tmp_team_stats_total;

	CREATE TEMPORARY TABLE tmp_team_stats_role_h_home AS
	SELECT * FROM tmp_team_stats_role WHERE team_role = 'HOME';

	CREATE TEMPORARY TABLE tmp_team_stats_role_h_away AS
	SELECT * FROM tmp_team_stats_role WHERE team_role = 'AWAY';

	CREATE TEMPORARY TABLE tmp_team_stats_role_a_home AS
	SELECT * FROM tmp_team_stats_role WHERE team_role = 'HOME';

	CREATE TEMPORARY TABLE tmp_team_stats_role_a_away AS
	SELECT * FROM tmp_team_stats_role WHERE team_role = 'AWAY';

	CREATE TEMPORARY TABLE tmp_team_recent_stats_home AS
	SELECT * FROM tmp_team_recent_stats;

	CREATE TEMPORARY TABLE tmp_team_recent_stats_away AS
	SELECT * FROM tmp_team_recent_stats;

	ALTER TABLE tmp_team_stats_total_home
		ADD INDEX idx_tmp_team_stats_total_home_team (team_keyword_id);

	ALTER TABLE tmp_team_stats_total_away
		ADD INDEX idx_tmp_team_stats_total_away_team (team_keyword_id);

	ALTER TABLE tmp_team_stats_role_h_home
		ADD INDEX idx_tmp_team_stats_role_h_home_team (team_keyword_id);

	ALTER TABLE tmp_team_stats_role_h_away
		ADD INDEX idx_tmp_team_stats_role_h_away_team (team_keyword_id);

	ALTER TABLE tmp_team_stats_role_a_home
		ADD INDEX idx_tmp_team_stats_role_a_home_team (team_keyword_id);

	ALTER TABLE tmp_team_stats_role_a_away
		ADD INDEX idx_tmp_team_stats_role_a_away_team (team_keyword_id);

	ALTER TABLE tmp_team_recent_stats_home
		ADD INDEX idx_tmp_team_recent_stats_home_team (team_keyword_id);

	ALTER TABLE tmp_team_recent_stats_away
		ADD INDEX idx_tmp_team_recent_stats_away_team (team_keyword_id);

	SELECT
		fmr.id,
		CONCAT(khome.keyword_zh, ' vs ', kaway.keyword_zh) AS home_vs_away_team_names,
		fmr.match_type_keyword_id,
		kmt.keyword_zh AS match_type_keyword_zh,
		fmr.home_team_keyword_id,
		khome.keyword_zh AS home_team_keyword_zh,
		COALESCE(h_recent.recent_win_matches, 0) AS home_team_recent_win_matches,
		COALESCE(h_recent.recent_draw_matches, 0) AS home_team_recent_draw_matches,
		COALESCE(h_recent.recent_lose_matches, 0) AS home_team_recent_lose_matches,
		COALESCE(h_total.total_matches, 0) AS home_team_total_matches,
		COALESCE(h_total.win_matches, 0) AS home_team_win_matches,
		COALESCE(h_total.draw_matches, 0) AS home_team_draw_matches,
		COALESCE(h_total.lose_matches, 0) AS home_team_lose_matches,
		COALESCE(h_total.win_1, 0) AS home_team_win_1,
		COALESCE(h_total.win_2, 0) AS home_team_win_2,
		COALESCE(h_total.win_3, 0) AS home_team_win_3,
		COALESCE(h_total.win_4_plus, 0) AS home_team_win_4_plus,
		COALESCE(h_total.lose_1, 0) AS home_team_lose_1,
		COALESCE(h_total.lose_2, 0) AS home_team_lose_2,
		COALESCE(h_total.lose_3, 0) AS home_team_lose_3,
		COALESCE(h_total.lose_4_plus, 0) AS home_team_lose_4_plus,
		ROUND(COALESCE(h_total.total_goals_for, 0) / NULLIF(COALESCE(h_total.total_matches, 0), 0), 2) AS home_team_avg_goals,
		COALESCE(h_total.htft_ww, 0) AS home_team_htft_ww,
		COALESCE(h_total.htft_dw, 0) AS home_team_htft_dw,
		COALESCE(h_total.htft_lw, 0) AS home_team_htft_lw,
		COALESCE(h_total.htft_dd, 0) AS home_team_htft_dd,
		COALESCE(h_total.htft_wd, 0) AS home_team_htft_wd,
		COALESCE(h_total.htft_ld, 0) AS home_team_htft_ld,
		COALESCE(h_total.htft_wl, 0) AS home_team_htft_wl,
		COALESCE(h_total.htft_dl, 0) AS home_team_htft_dl,
		COALESCE(h_total.htft_ll, 0) AS home_team_htft_ll,
		COALESCE(h_home.total_matches, 0) AS home_team_as_home_total_matches,
		COALESCE(h_home.win_matches, 0) AS home_team_as_home_win_matches,
		COALESCE(h_home.draw_matches, 0) AS home_team_as_home_draw_matches,
		COALESCE(h_home.lose_matches, 0) AS home_team_as_home_lose_matches,
		COALESCE(h_home.win_1, 0) AS home_team_as_home_win_1,
		COALESCE(h_home.win_2, 0) AS home_team_as_home_win_2,
		COALESCE(h_home.win_3, 0) AS home_team_as_home_win_3,
		COALESCE(h_home.win_4_plus, 0) AS home_team_as_home_win_4_plus,
		COALESCE(h_home.lose_1, 0) AS home_team_as_home_lose_1,
		COALESCE(h_home.lose_2, 0) AS home_team_as_home_lose_2,
		COALESCE(h_home.lose_3, 0) AS home_team_as_home_lose_3,
		COALESCE(h_home.lose_4_plus, 0) AS home_team_as_home_lose_4_plus,
		ROUND(COALESCE(h_home.total_goals_for, 0) / NULLIF(COALESCE(h_home.total_matches, 0), 0), 2) AS home_team_as_home_avg_goals,
		COALESCE(h_home.htft_ww, 0) AS home_team_as_home_htft_ww,
		COALESCE(h_home.htft_dw, 0) AS home_team_as_home_htft_dw,
		COALESCE(h_home.htft_lw, 0) AS home_team_as_home_htft_lw,
		COALESCE(h_home.htft_dd, 0) AS home_team_as_home_htft_dd,
		COALESCE(h_home.htft_wd, 0) AS home_team_as_home_htft_wd,
		COALESCE(h_home.htft_ld, 0) AS home_team_as_home_htft_ld,
		COALESCE(h_home.htft_wl, 0) AS home_team_as_home_htft_wl,
		COALESCE(h_home.htft_dl, 0) AS home_team_as_home_htft_dl,
		COALESCE(h_home.htft_ll, 0) AS home_team_as_home_htft_ll,
		COALESCE(h_away.total_matches, 0) AS home_team_as_away_total_matches,
		COALESCE(h_away.win_matches, 0) AS home_team_as_away_win_matches,
		COALESCE(h_away.draw_matches, 0) AS home_team_as_away_draw_matches,
		COALESCE(h_away.lose_matches, 0) AS home_team_as_away_lose_matches,
		COALESCE(h_away.win_1, 0) AS home_team_as_away_win_1,
		COALESCE(h_away.win_2, 0) AS home_team_as_away_win_2,
		COALESCE(h_away.win_3, 0) AS home_team_as_away_win_3,
		COALESCE(h_away.win_4_plus, 0) AS home_team_as_away_win_4_plus,
		COALESCE(h_away.lose_1, 0) AS home_team_as_away_lose_1,
		COALESCE(h_away.lose_2, 0) AS home_team_as_away_lose_2,
		COALESCE(h_away.lose_3, 0) AS home_team_as_away_lose_3,
		COALESCE(h_away.lose_4_plus, 0) AS home_team_as_away_lose_4_plus,
		ROUND(COALESCE(h_away.total_goals_for, 0) / NULLIF(COALESCE(h_away.total_matches, 0), 0), 2) AS home_team_as_away_avg_goals,
		COALESCE(h_away.htft_ww, 0) AS home_team_as_away_htft_ww,
		COALESCE(h_away.htft_dw, 0) AS home_team_as_away_htft_dw,
		COALESCE(h_away.htft_lw, 0) AS home_team_as_away_htft_lw,
		COALESCE(h_away.htft_dd, 0) AS home_team_as_away_htft_dd,
		COALESCE(h_away.htft_wd, 0) AS home_team_as_away_htft_wd,
		COALESCE(h_away.htft_ld, 0) AS home_team_as_away_htft_ld,
		COALESCE(h_away.htft_wl, 0) AS home_team_as_away_htft_wl,
		COALESCE(h_away.htft_dl, 0) AS home_team_as_away_htft_dl,
		COALESCE(h_away.htft_ll, 0) AS home_team_as_away_htft_ll,
		fmr.away_team_keyword_id,
		kaway.keyword_zh AS away_team_keyword_zh,
		COALESCE(a_recent.recent_win_matches, 0) AS away_team_recent_win_matches,
		COALESCE(a_recent.recent_draw_matches, 0) AS away_team_recent_draw_matches,
		COALESCE(a_recent.recent_lose_matches, 0) AS away_team_recent_lose_matches,
		ROUND(COALESCE(a_total.total_goals_for, 0) / NULLIF(COALESCE(a_total.total_matches, 0), 0), 2) AS away_team_avg_goals,
		COALESCE(a_total.total_matches, 0) AS away_team_total_matches,
		COALESCE(a_total.win_matches, 0) AS away_team_win_matches,
		COALESCE(a_total.draw_matches, 0) AS away_team_draw_matches,
		COALESCE(a_total.lose_matches, 0) AS away_team_lose_matches,
		COALESCE(a_total.win_1, 0) AS away_team_win_1,
		COALESCE(a_total.win_2, 0) AS away_team_win_2,
		COALESCE(a_total.win_3, 0) AS away_team_win_3,
		COALESCE(a_total.win_4_plus, 0) AS away_team_win_4_plus,
		COALESCE(a_total.lose_1, 0) AS away_team_lose_1,
		COALESCE(a_total.lose_2, 0) AS away_team_lose_2,
		COALESCE(a_total.lose_3, 0) AS away_team_lose_3,
		COALESCE(a_total.lose_4_plus, 0) AS away_team_lose_4_plus,
		COALESCE(a_total.htft_ww, 0) AS away_team_htft_ww,
		COALESCE(a_total.htft_dw, 0) AS away_team_htft_dw,
		COALESCE(a_total.htft_lw, 0) AS away_team_htft_lw,
		COALESCE(a_total.htft_dd, 0) AS away_team_htft_dd,
		COALESCE(a_total.htft_wd, 0) AS away_team_htft_wd,
		COALESCE(a_total.htft_ld, 0) AS away_team_htft_ld,
		COALESCE(a_total.htft_wl, 0) AS away_team_htft_wl,
		COALESCE(a_total.htft_dl, 0) AS away_team_htft_dl,
		COALESCE(a_total.htft_ll, 0) AS away_team_htft_ll,
		COALESCE(a_home.total_matches, 0) AS away_team_as_home_total_matches,
		COALESCE(a_home.win_matches, 0) AS away_team_as_home_win_matches,
		COALESCE(a_home.draw_matches, 0) AS away_team_as_home_draw_matches,
		COALESCE(a_home.lose_matches, 0) AS away_team_as_home_lose_matches,
		COALESCE(a_home.win_1, 0) AS away_team_as_home_win_1,
		COALESCE(a_home.win_2, 0) AS away_team_as_home_win_2,
		COALESCE(a_home.win_3, 0) AS away_team_as_home_win_3,
		COALESCE(a_home.win_4_plus, 0) AS away_team_as_home_win_4_plus,
		COALESCE(a_home.lose_1, 0) AS away_team_as_home_lose_1,
		COALESCE(a_home.lose_2, 0) AS away_team_as_home_lose_2,
		COALESCE(a_home.lose_3, 0) AS away_team_as_home_lose_3,
		COALESCE(a_home.lose_4_plus, 0) AS away_team_as_home_lose_4_plus,
		ROUND(COALESCE(a_home.total_goals_for, 0) / NULLIF(COALESCE(a_home.total_matches, 0), 0), 2) AS away_team_as_home_avg_goals,
		COALESCE(a_home.htft_ww, 0) AS away_team_as_home_htft_ww,
		COALESCE(a_home.htft_dw, 0) AS away_team_as_home_htft_dw,
		COALESCE(a_home.htft_lw, 0) AS away_team_as_home_htft_lw,
		COALESCE(a_home.htft_dd, 0) AS away_team_as_home_htft_dd,
		COALESCE(a_home.htft_wd, 0) AS away_team_as_home_htft_wd,
		COALESCE(a_home.htft_ld, 0) AS away_team_as_home_htft_ld,
		COALESCE(a_home.htft_wl, 0) AS away_team_as_home_htft_wl,
		COALESCE(a_home.htft_dl, 0) AS away_team_as_home_htft_dl,
		COALESCE(a_home.htft_ll, 0) AS away_team_as_home_htft_ll,
		COALESCE(a_away.total_matches, 0) AS away_team_as_away_total_matches,
		COALESCE(a_away.win_matches, 0) AS away_team_as_away_win_matches,
		COALESCE(a_away.draw_matches, 0) AS away_team_as_away_draw_matches,
		COALESCE(a_away.lose_matches, 0) AS away_team_as_away_lose_matches,
		COALESCE(a_away.win_1, 0) AS away_team_as_away_win_1,
		COALESCE(a_away.win_2, 0) AS away_team_as_away_win_2,
		COALESCE(a_away.win_3, 0) AS away_team_as_away_win_3,
		COALESCE(a_away.win_4_plus, 0) AS away_team_as_away_win_4_plus,
		COALESCE(a_away.lose_1, 0) AS away_team_as_away_lose_1,
		COALESCE(a_away.lose_2, 0) AS away_team_as_away_lose_2,
		COALESCE(a_away.lose_3, 0) AS away_team_as_away_lose_3,
		COALESCE(a_away.lose_4_plus, 0) AS away_team_as_away_lose_4_plus,
		ROUND(COALESCE(a_away.total_goals_for, 0) / NULLIF(COALESCE(a_away.total_matches, 0), 0), 2) AS away_team_as_away_avg_goals,
		COALESCE(a_away.htft_ww, 0) AS away_team_as_away_htft_ww,
		COALESCE(a_away.htft_dw, 0) AS away_team_as_away_htft_dw,
		COALESCE(a_away.htft_lw, 0) AS away_team_as_away_htft_lw,
		COALESCE(a_away.htft_dd, 0) AS away_team_as_away_htft_dd,
		COALESCE(a_away.htft_wd, 0) AS away_team_as_away_htft_wd,
		COALESCE(a_away.htft_ld, 0) AS away_team_as_away_htft_ld,
		COALESCE(a_away.htft_wl, 0) AS away_team_as_away_htft_wl,
		COALESCE(a_away.htft_dl, 0) AS away_team_as_away_htft_dl,
		COALESCE(a_away.htft_ll, 0) AS away_team_as_away_htft_ll,
		fmr.season_keyword_id,
		kseason.keyword_zh AS season_keyword_zh,
		fmr.seasonround,
		fmr.match_at,
		fmr.home_win_odds,
		fmr.draw_odds,
		fmr.away_win_odds,
		fmr.home_ft_goals,
		fmr.away_ft_goals,
		fmr.home_ht_goals,
		fmr.away_ht_goals,
		fmr.is_finished,
		fmr.created_at,
		fmr.updated_at
	FROM football_match_results fmr
	LEFT JOIN keywords kmt ON kmt.id = fmr.match_type_keyword_id
	LEFT JOIN keywords khome ON khome.id = fmr.home_team_keyword_id
	LEFT JOIN keywords kaway ON kaway.id = fmr.away_team_keyword_id
	LEFT JOIN keywords kseason ON kseason.id = fmr.season_keyword_id
	LEFT JOIN tmp_team_stats_total_home h_total ON h_total.team_keyword_id = fmr.home_team_keyword_id
	LEFT JOIN tmp_team_stats_role_h_home h_home ON h_home.team_keyword_id = fmr.home_team_keyword_id
	LEFT JOIN tmp_team_stats_role_h_away h_away ON h_away.team_keyword_id = fmr.home_team_keyword_id
	LEFT JOIN tmp_team_recent_stats_home h_recent ON h_recent.team_keyword_id = fmr.home_team_keyword_id
	LEFT JOIN tmp_team_stats_total_away a_total ON a_total.team_keyword_id = fmr.away_team_keyword_id
	LEFT JOIN tmp_team_stats_role_a_home a_home ON a_home.team_keyword_id = fmr.away_team_keyword_id
	LEFT JOIN tmp_team_stats_role_a_away a_away ON a_away.team_keyword_id = fmr.away_team_keyword_id
	LEFT JOIN tmp_team_recent_stats_away a_recent ON a_recent.team_keyword_id = fmr.away_team_keyword_id
	WHERE fmr.is_finished = 0
	  AND (p_UpcomingBeginmatch_at IS NULL OR fmr.match_at >= p_UpcomingBeginmatch_at)
	  AND (p_UpcomingEndmatch_at IS NULL OR fmr.match_at <= p_UpcomingEndmatch_at)
	  AND (p_match_type_keyword_id IS NULL OR p_match_type_keyword_id = 0 OR fmr.match_type_keyword_id = p_match_type_keyword_id)
	  AND (p_season_keyword_id IS NULL OR p_season_keyword_id = 0 OR fmr.season_keyword_id = p_season_keyword_id)
	  AND (p_seasonround IS NULL OR p_seasonround = 0 OR fmr.seasonround = p_seasonround)
	  AND (p_match_keyword_id IS NULL OR p_match_keyword_id = 0 OR fmr.id = p_match_keyword_id)
	ORDER BY fmr.match_at ASC, fmr.id ASC;

	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_role_a_away;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_role_a_home;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_role_h_away;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_role_h_home;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_recent_stats_away;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_recent_stats_home;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_recent_stats;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_total_away;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_total_home;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_total;
	DROP TEMPORARY TABLE IF EXISTS tmp_team_stats_role;
END $$

DELIMITER ;



-- CALL sp_analyze_unfinished_football_matches(
--     0,
--     0,
--     0,
--     0,
--     NULL,
--     NULL,
--     '2026-01-01 00:00:00',
--     '2026-08-17 23:59:59',
--     '2026-07-01 00:00:00',
--     '2026-08-17 23:59:59'
-- );




-- 中文列名（逗号分隔）
-- 比赛ID,主队名称 vs 客队名称,比赛类型关键词ID,比赛类型,主队关键词ID,主队名称,主队近期胜场,主队近期平场,主队近期负场,主队场均进球,主队总场次,主队总胜场,主队总平场,主队总负场,主队总净胜1球场次,主队总净胜2球场次,主队总净胜3球场次,主队总净胜4球及以上场次,主队总净负1球场次,主队总净负2球场次,主队总净负3球场次,主队总净负4球及以上场次,主队总半全场胜胜场次,主队总半全场平胜场次,主队总半全场负胜场次,主队总半全场平平场次,主队总半全场胜平场次,主队总半全场负平场次,主队总半全场胜负场次,主队总半全场平负场次,主队总半全场负负场次,主队主场场均进球,主队主场总场次,主队主场胜场,主队主场平场,主队主场负场,主队主场净胜1球场次,主队主场净胜2球场次,主队主场净胜3球场次,主队主场净胜4球及以上场次,主队主场净负1球场次,主队主场净负2球场次,主队主场净负3球场次,主队主场净负4球及以上场次,主队主场半全场胜胜场次,主队主场半全场平胜场次,主队主场半全场负胜场次,主队主场半全场平平场次,主队主场半全场胜平场次,主队主场半全场负平场次,主队主场半全场胜负场次,主队主场半全场平负场次,主队主场半全场负负场次,主队客场场均进球,主队客场总场次,主队客场胜场,主队客场平场,主队客场负场,主队客场净胜1球场次,主队客场净胜2球场次,主队客场净胜3球场次,主队客场净胜4球及以上场次,主队客场净负1球场次,主队客场净负2球场次,主队客场净负3球场次,主队客场净负4球及以上场次,主队客场半全场胜胜场次,主队客场半全场平胜场次,主队客场半全场负胜场次,主队客场半全场平平场次,主队客场半全场胜平场次,主队客场半全场负平场次,主队客场半全场胜负场次,主队客场半全场平负场次,主队客场半全场负负场次,客队关键词ID,客队名称,客队近期胜场,客队近期平场,客队近期负场,客队场均进球,客队总场次,客队总胜场,客队总平场,客队总负场,客队总净胜1球场次,客队总净胜2球场次,客队总净胜3球场次,客队总净胜4球及以上场次,客队总净负1球场次,客队总净负2球场次,客队总净负3球场次,客队总净负4球及以上场次,客队总半全场胜胜场次,客队总半全场平胜场次,客队总半全场负胜场次,客队总半全场平平场次,客队总半全场胜平场次,客队总半全场负平场次,客队总半全场胜负场次,客队总半全场平负场次,客队总半全场负负场次,客队主场场均进球,客队主场总场次,客队主场胜场,客队主场平场,客队主场负场,客队主场净胜1球场次,客队主场净胜2球场次,客队主场净胜3球场次,客队主场净胜4球及以上场次,客队主场净负1球场次,客队主场净负2球场次,客队主场净负3球场次,客队主场净负4球及以上场次,客队主场半全场胜胜场次,客队主场半全场平胜场次,客队主场半全场负胜场次,客队主场半全场平平场次,客队主场半全场胜平场次,客队主场半全场负平场次,客队主场半全场胜负场次,客队主场半全场平负场次,客队主场半全场负负场次,客队客场场均进球,客队客场总场次,客队客场胜场,客队客场平场,客队客场负场,客队客场净胜1球场次,客队客场净胜2球场次,客队客场净胜3球场次,客队客场净胜4球及以上场次,客队客场净负1球场次,客队客场净负2球场次,客队客场净负3球场次,客队客场净负4球及以上场次,客队客场半全场胜胜场次,客队客场半全场平胜场次,客队客场半全场负胜场次,客队客场半全场平平场次,客队客场半全场胜平场次,客队客场半全场负平场次,客队客场半全场胜负场次,客队客场半全场平负场次,客队客场半全场负负场次,赛季关键词ID,赛季,轮次,比赛时间,主队全场进球,客队全场进球,主队半场进球,客队半场进球,是否完赛,创建时间,更新时间