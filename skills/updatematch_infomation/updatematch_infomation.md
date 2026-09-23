当前文件中有若干未进行的比赛，请在https://liansai.500.com/ 寻找每场比赛的数据，json文件中seasonround为联赛的轮次（便于查找），需要获取 比赛 的 胜 平 负的 赔率 ，更新到home_win_odds，draw_odds，away_win_odds 三个字段，match_at也需要更新（json文件的match_at数据可能有误），做成UPDATE 语句，关键字段为json文件中id。如果当前比赛没有胜 平 负的 赔率的数据，即是更新失败。如果比赛已经结束，就要更新比分信息（共4个字段home_ft_goals，away_ft_goals，home_ht_goals，away_ht_goals），同时is_finished=1。updated_at更新为最新日期。 修改完后，把修改结果做成日志到一个markdown文件中。


## 数据源
select A.id,A.match_type_keyword_id,D.keyword_zh matchName, A.seasonround, A.home_team_keyword_id,B.keyword_zh home_teamName,A.away_team_keyword_id,C.keyword_zh away_teamName,
A.home_ft_goals,A.away_ft_goals,A.home_ht_goals,A.away_ht_goals, A.match_at,
A.home_win_odds,A.draw_odds,A.away_win_odds, A.is_finished from football_match_results A
LEFT JOIN keywords B ON A.home_team_keyword_id = B.id
LEFT JOIN keywords C ON A.away_team_keyword_id = C.id
LEFT JOIN keywords D ON A.match_type_keyword_id = D.id
where match_at >= '2026-09-16 00:00:00' AND match_at <= '2026-09-22 00:00:00' AND is_finished = 0 ORDER BY A.match_type_keyword_id;

## 2026-09-16 00:00:00 2026-09-22 00:00:00 改成当前日期范围
