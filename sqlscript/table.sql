-- =============================================================================
-- 数据库：内容关键词管理系统
-- =============================================================================

-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS AIMemory
    DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

-- 使用数据库
USE AIMemory;


-- =============================================================================
-- 表1：users（用户账号表）
-- 作用：用于网站登录认证与账号管理
-- 设计要点：
-- 1) 仅存密码哈希，不存明文密码
-- 2) 支持账号禁用、软删除、登录失败锁定
-- 3) username 全局唯一，email/mobile 可选唯一
-- =============================================================================
CREATE TABLE users (
    id                  BIGINT       AUTO_INCREMENT PRIMARY KEY COMMENT '主键ID，自增，用户唯一标识',
    username            VARCHAR(50)  NOT NULL COMMENT '登录用户名，唯一，建议仅允许字母数字下划线',
    email               VARCHAR(100) DEFAULT NULL COMMENT '邮箱，可用于登录或找回密码',
    mobile              VARCHAR(20)  DEFAULT NULL COMMENT '手机号，可用于登录或找回密码',
    password_hash       VARCHAR(255) NOT NULL COMMENT '密码哈希值（建议 Argon2id 或 bcrypt）',
    password_algo       VARCHAR(20)  NOT NULL DEFAULT 'argon2id' COMMENT '密码哈希算法标识：argon2id/bcrypt',
    status              TINYINT      NOT NULL DEFAULT 1 COMMENT '账号状态：1=正常，0=禁用',
    user_type           ENUM('admin','operator','user') NOT NULL DEFAULT 'user' COMMENT '用户类型：admin=管理员，operator=操作员，user=普通用户',
    failed_login_count  INT          NOT NULL DEFAULT 0 COMMENT '连续登录失败次数，用于防爆破策略',
    lock_until          DATETIME     DEFAULT NULL COMMENT '账号锁定截止时间；NULL 表示未锁定',
    last_login_at       DATETIME     DEFAULT NULL COMMENT '最近一次成功登录时间',
    last_login_ip       VARCHAR(45)  DEFAULT NULL COMMENT '最近一次成功登录IP，兼容IPv4/IPv6',
    created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间（入库时间）',
    updated_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '最后更新时间',
    deleted_at          DATETIME     DEFAULT NULL COMMENT '软删除时间；NULL 表示未删除',

    UNIQUE KEY uk_users_username (username) COMMENT '用户名唯一索引，防止重复账号',
    UNIQUE KEY uk_users_email    (email)    COMMENT '邮箱唯一索引（允许多个 NULL）',
    UNIQUE KEY uk_users_mobile   (mobile)   COMMENT '手机号唯一索引（允许多个 NULL）',
    INDEX idx_users_status       (status)   COMMENT '按账号状态过滤（正常/禁用）',
    INDEX idx_users_user_type    (user_type) COMMENT '按用户类型过滤（管理员/操作员/普通用户）',
    INDEX idx_users_created_at   (created_at) COMMENT '按创建时间排序/分页'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='用户账号表：承载登录认证、状态管理与安全控制';


-- =============================================================================
-- 表2：user_tokens（用户令牌表）
-- 作用：保存登录后签发的单个会话 token（建议仅保存哈希），支持过期、撤销与审计
-- 设计要点：
-- 1) token_hash：保存 token 哈希值，不保存明文 token
-- 2) expires_at：控制 token 生命周期，超过时间即失效
-- 3) revoked_at：支持主动退出登录或踢下线
-- =============================================================================
CREATE TABLE user_tokens (
    id              BIGINT       AUTO_INCREMENT PRIMARY KEY COMMENT '主键ID，自增，令牌记录唯一标识',
    user_id         BIGINT       NOT NULL COMMENT '所属用户ID，关联 users.id',
    token_hash      CHAR(64)     NOT NULL COMMENT '会话 Token 的 SHA-256 哈希（64位十六进制）',
    issued_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '签发时间',
    expires_at      DATETIME     NOT NULL COMMENT '过期时间；超过该时间令牌失效',
    revoked_at      DATETIME     DEFAULT NULL COMMENT '撤销时间；非NULL表示已主动失效',
    last_used_at    DATETIME     DEFAULT NULL COMMENT '最近一次使用时间',
    client_ip       VARCHAR(45)  DEFAULT NULL COMMENT '签发时客户端IP，兼容IPv4/IPv6',
    user_agent      VARCHAR(255) DEFAULT NULL COMMENT '签发时客户端UA信息',
    device_id       VARCHAR(100) DEFAULT NULL COMMENT '设备标识（可选），用于多端会话管理',
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间（入库时间）',

    UNIQUE KEY uk_user_tokens_token_hash (token_hash) COMMENT 'Token 哈希唯一索引，防止重复',
    INDEX idx_user_tokens_user_expires (user_id, expires_at) COMMENT '按用户+过期时间查询，用于清理和会话管理',
    INDEX idx_user_tokens_valid_lookup (expires_at, revoked_at) COMMENT '校验可用令牌常用索引',
    INDEX idx_user_tokens_last_used_at (last_used_at) COMMENT '按最近使用时间做审计/清理',

    CONSTRAINT fk_user_tokens_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='用户令牌表：用于单 token 登录态校验和会话管理';

-- =============================================================================
-- 表3：login_logs（登录审计日志）
-- 作用：记录登录尝试与结果，便于安全审计与问题排查
-- 规则：账号不存在（1001）可不记录；其余结果均记录
-- =============================================================================
CREATE TABLE login_logs (
    id              BIGINT       AUTO_INCREMENT PRIMARY KEY COMMENT '主键ID，自增，日志记录唯一标识',
    user_id         BIGINT       DEFAULT NULL COMMENT '用户ID；登录账号不存在时为空',
    username_input  VARCHAR(100) DEFAULT NULL COMMENT '登录时输入的账号',
    user_type       VARCHAR(20)  DEFAULT NULL COMMENT '用户类型快照：admin/operator/user',
    result_code     INT          NOT NULL COMMENT '登录结果码：如 0/1002/1003/1004/1005',
    result_msg      VARCHAR(100) DEFAULT NULL COMMENT '登录结果消息键，如 ok/password_incorrect',
    client_ip       VARCHAR(45)  DEFAULT NULL COMMENT '客户端IP，兼容IPv4/IPv6',
    user_agent      VARCHAR(255) DEFAULT NULL COMMENT '客户端UA信息',
    device_id       VARCHAR(100) DEFAULT NULL COMMENT '设备标识（可选）',
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '日志创建时间',

    INDEX idx_login_user_time   (user_id, created_at) COMMENT '按用户和时间查询登录轨迹',
    INDEX idx_login_result_time (result_code, created_at) COMMENT '按结果码和时间统计分析',
    INDEX idx_login_name_time   (username_input, created_at) COMMENT '按输入账号和时间检索异常登录'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='登录审计日志：记录登录行为与结果，用于安全审计和排障';

-- =============================================================================
-- 表4：content_entries（内容记录主表）
-- 作用：存储每一条具体的内容，以及它的业务发生时间
-- =============================================================================
CREATE TABLE content_entries (
    id          BIGINT       AUTO_INCREMENT PRIMARY KEY   COMMENT '主键ID，自增，每条内容记录的唯一标识',
    content     TEXT         NOT NULL                      COMMENT '具体内容，支持长文本，如文章正文、笔记内容、日志描述等',
    event_at    DATETIME     NOT NULL                      COMMENT '业务发生日期时间，即这条内容实际产生的时间。例如：一条会议记录的事件时间是"2026-05-20 14:30:00"，而不是录入系统的时间',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '数据创建时间，即这条记录被录入数据库的时间（入库时间），与 event_at 不同',
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '最后更新时间，每次修改记录时自动更新',
    category    VARCHAR(50)  DEFAULT NULL                  COMMENT '可选分类，用于对内容进行粗粒度分组，如：技术笔记、生活记录、工作日志',
    status      TINYINT      NOT NULL DEFAULT 1            COMMENT '状态标识：1=正常（可见），0=删除（隐藏/软删除）',
    deleted_at  DATETIME     DEFAULT NULL                  COMMENT '软删除时间，NULL 表示未删除；仅在 status=0 时有值',
    -- 索引说明
    INDEX idx_created_at  (created_at)                     COMMENT '创建日期索引，用于按入库时间排序或分页，例如：查看最新录入的内容',
    INDEX idx_updated_at  (updated_at)                     COMMENT '更新时间索引，用于追踪最近被修改过的记录',
    INDEX idx_status_event_at_id (status, event_at, id)    COMMENT '组合索引：用于按状态+时间范围过滤并按时间分页',
    INDEX idx_status_category_event_at_id (status, category, event_at, id) COMMENT '组合索引：用于按状态+分类+时间范围过滤并按时间分页'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='内容记录主表：存储每条具体内容及其业务发生时间，是整个系统的核心表';

-- =============================================================================
-- 表5：keywords（关键词字典表）
-- 作用：统一管理所有关键词，保证同一个关键词只存一次（唯一），避免冗余
--       同时通过 first_char 字段支持按拼音首字母快速筛选
-- =============================================================================
CREATE TABLE keywords (
    id          BIGINT       AUTO_INCREMENT PRIMARY KEY   COMMENT '主键ID，自增，每个关键词的唯一标识',
    keyword_zh  VARCHAR(100) NOT NULL                      COMMENT '中文关键词，如：设计模式、数据库、系统架构等。不允许为空，且全局唯一',
    keyword_en  VARCHAR(100) DEFAULT NULL                  COMMENT '英文关键词，如：Design Pattern、Database、Architecture。可为空，非空时唯一',
    keyword_type CHAR(5) DEFAULT NULL                       COMMENT '类型字段，可为空，最多5个字符',
    first_char  CHAR(1)      DEFAULT NULL                  COMMENT '关键词首字的拼音首字母或数字。用于字母索引筛选。规则：优先按中文关键词首字计算；若中文为空则按英文首字；数字取数字本身，英文字母取大写，特殊字符为NULL',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '关键词添加时间（入库时间）',
    UNIQUE KEY uk_keyword_zh (keyword_zh)                  COMMENT '中文关键词唯一索引，保证中文关键词不重复，同时用于精确搜索和前缀搜索',
    UNIQUE KEY uk_keyword_en (keyword_en)                  COMMENT '英文关键词唯一索引（允许多个 NULL）',
    INDEX idx_keyword_type (keyword_type)                   COMMENT '类型排序/筛选索引',
    INDEX idx_first_char     (first_char)                  COMMENT '首字首字母索引，用于按字母筛选关键词，例如：查询所有首字母为 "S" 的关键词列表',
    CONSTRAINT chk_first_char_format CHECK (first_char IS NULL OR first_char REGEXP '^[A-Z0-9]$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='关键词字典表：集中管理中文和英文关键词，避免脏数据和冗余，支持拼音首字母快速检索';

-- =============================================================================
-- 表6：entry_keywords（内容与关键词关联表）
-- 作用：建立内容（content_entries）和关键词（keywords）之间的多对多关系
--       一条内容可以有多个关键词，一个关键词可以属于多条内容
-- =============================================================================
CREATE TABLE entry_keywords (
    id          BIGINT       AUTO_INCREMENT PRIMARY KEY   COMMENT '主键ID，自增，每条关联记录的唯一标识',
    entry_id    BIGINT       NOT NULL                      COMMENT '内容ID，关联 content_entries 表的主键。表示哪条内容被关联了关键词',
    keyword_id  BIGINT       NOT NULL                      COMMENT '关键词ID，关联 keywords 表的主键。表示哪个关键词被关联到了内容',
    UNIQUE KEY uk_entry_keyword (entry_id, keyword_id)     COMMENT '联合唯一索引：防止同一条内容重复关联同一个关键词。同时支撑按内容ID查询所有关联关键词（走索引前缀）',
    INDEX idx_keyword_id         (keyword_id)              COMMENT '关键词ID索引：支撑反向查询，即查询某个关键词被哪些内容使用了（按关键词找内容）',
    CONSTRAINT fk_ek_entry   FOREIGN KEY (entry_id)    REFERENCES content_entries(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ek_keyword FOREIGN KEY (keyword_id)   REFERENCES keywords(id)        ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='内容-关键词关联表：建立内容与关键词的多对多关系，是连接 content_entries 和 keywords 的桥梁表';


-- =============================================================================
-- 表7：football_match_results（足球比赛成绩记录表）
-- 作用：记录足球比赛结果，比赛类型/主客队/赛季均来自关键词表（keywords）
-- =============================================================================
CREATE TABLE football_match_results (
    id                    BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '主键ID，自增',
    match_type_keyword_id BIGINT NOT NULL COMMENT '比赛类型关键词ID，关联 keywords.id',
    home_team_keyword_id  BIGINT NOT NULL COMMENT '主队名称关键词ID，关联 keywords.id',
    away_team_keyword_id  BIGINT NOT NULL COMMENT '客队名称关键词ID，关联 keywords.id',
    season_keyword_id     BIGINT NOT NULL COMMENT '赛季名称关键词ID，关联 keywords.id',
    seasonround           TINYINT UNSIGNED DEFAULT NULL COMMENT '轮次',
    match_at              DATETIME NOT NULL COMMENT '比赛日期时间',
    home_win_odds         DECIMAL(10,4) NOT NULL DEFAULT 0.0000 COMMENT '主队胜赔率，保留4位小数',
    draw_odds             DECIMAL(10,4) NOT NULL DEFAULT 0.0000 COMMENT '平局赔率，保留4位小数',
    away_win_odds         DECIMAL(10,4) NOT NULL DEFAULT 0.0000 COMMENT '客队胜赔率，保留4位小数',
    home_ft_goals         TINYINT UNSIGNED NOT NULL COMMENT '主队全场进球数，通常不超过100',
    away_ft_goals         TINYINT UNSIGNED NOT NULL COMMENT '客队全场进球数，通常不超过100',
    home_ht_goals         TINYINT UNSIGNED NOT NULL COMMENT '主队半场进球数，通常不超过100',
    away_ht_goals         TINYINT UNSIGNED NOT NULL COMMENT '客队半场进球数，通常不超过100',
    created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录更新时间',
    is_finished           TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否完赛：1=完赛，0=未完赛',
    str1                  VARCHAR(64) DEFAULT NULL COMMENT '扩展字段1',
    str2                  VARCHAR(64) DEFAULT NULL COMMENT '扩展字段2',
    str3                  VARCHAR(64) DEFAULT NULL COMMENT '扩展字段3',
    INDEX idx_fmr_match_at (match_at) COMMENT '按比赛时间排序/筛选',
    INDEX idx_fmr_match_type (match_type_keyword_id) COMMENT '按比赛类型筛选',
    INDEX idx_fmr_home_team (home_team_keyword_id) COMMENT '按主队筛选',
    INDEX idx_fmr_away_team (away_team_keyword_id) COMMENT '按客队筛选',
    INDEX idx_fmr_season (season_keyword_id) COMMENT '按赛季筛选',
    INDEX idx_fmr_season_match_at (season_keyword_id, match_at) COMMENT '按赛季+时间排序/筛选'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='足球比赛成绩记录表';

ALTER TABLE football_match_results
    ADD COLUMN home_win_odds DECIMAL(10,4) NOT NULL DEFAULT 0.0000 COMMENT '主队胜赔率，保留4位小数' AFTER match_at,
    ADD COLUMN draw_odds DECIMAL(10,4) NOT NULL DEFAULT 0.0000 COMMENT '平局赔率，保留4位小数' AFTER home_win_odds,
    ADD COLUMN away_win_odds DECIMAL(10,4) NOT NULL DEFAULT 0.0000 COMMENT '客队胜赔率，保留4位小数' AFTER draw_odds;
-- 已有表结构升级脚本：为 football_match_results 增加“是否完赛”字段
-- ALTER TABLE football_match_results
--     ADD COLUMN is_finished TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否完赛：1=完赛，0=未完赛' AFTER updated_at;

  -- 操作审计日志：记录业务操作（新增/修改/删除/导出等）
CREATE TABLE audit_logs (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '主键',
    user_id         BIGINT DEFAULT NULL COMMENT '操作用户ID',
    user_type       VARCHAR(20) DEFAULT NULL COMMENT '用户类型',
    module          VARCHAR(50) NOT NULL COMMENT '模块，如 content/keyword/user',
    action          VARCHAR(50) NOT NULL COMMENT '动作，如 create/update/delete/login',
    target_type     VARCHAR(50) DEFAULT NULL COMMENT '对象类型',
    target_id       VARCHAR(100) DEFAULT NULL COMMENT '对象ID',
    request_id      VARCHAR(64) DEFAULT NULL COMMENT '请求追踪ID',
    client_ip       VARCHAR(45) DEFAULT NULL COMMENT '客户端IP',
    status          TINYINT NOT NULL DEFAULT 1 COMMENT '1成功 0失败',
    error_code      VARCHAR(50) DEFAULT NULL COMMENT '失败码',
    error_message   VARCHAR(255) DEFAULT NULL COMMENT '失败信息（避免敏感数据）',
    ext_json        JSON DEFAULT NULL COMMENT '扩展字段（脱敏）',
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录时间',
    INDEX idx_audit_user_time (user_id, created_at),
    INDEX idx_audit_module_action_time (module, action, created_at),
    INDEX idx_audit_target (target_type, target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='业务操作审计日志';


-- =============================================================================
-- 表8：events（活动/展会主表）
-- 作用：存储 data.json 中的活动主信息，如标题、城市、日期、地址、关键词、价格和详情
-- 数据来源：AIMemory/json/data.json
-- 设计要点：
-- 1) 以标题+日期+城市作为活动业务主体，便于前端查询和筛选
-- 2) keywords 字段以逗号分隔保存，便于快速展示和搜索
-- 3) price 和 detail 都可能是文本型内容，保留富文本兼容
-- 4) 采用软删除机制，避免直接物理删除影响历史记录
-- =============================================================================
CREATE TABLE events (
    id          BIGINT       AUTO_INCREMENT PRIMARY KEY COMMENT '主键ID，自增，活动记录唯一标识',
    title       VARCHAR(200) NOT NULL COMMENT '活动标题，如：2026 全球人工智能大会',
    city        VARCHAR(50)  NOT NULL COMMENT '活动城市，如：北京、上海、深圳',
    event_date  DATE         NOT NULL COMMENT '活动日期，来源于 JSON 中的 date 字段（YYYY-MM-DD）',
    address     VARCHAR(255) DEFAULT NULL COMMENT '活动举办地址，如：国家会展中心（上海青浦区崧泽大道333号）',
    keywords    VARCHAR(255) DEFAULT NULL COMMENT '关键词列表，多个关键词用逗号分隔，如：人工智能、大模型、AI芯片',
    price       VARCHAR(100) DEFAULT NULL COMMENT '费用说明，如：免费（需预约）、专业观众票 ¥200',
    detail      TEXT         DEFAULT NULL COMMENT '活动详情描述，来源于 JSON 中的 detail 字段，支持较长文本',
    status      TINYINT      NOT NULL DEFAULT 1 COMMENT '状态标识：1=正常可见，0=已禁用/已删除',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间（入库时间）',
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间',
    deleted_at  DATETIME     DEFAULT NULL COMMENT '软删除时间；NULL 表示未删除',

    INDEX idx_events_city_date (city, event_date) COMMENT '按城市和活动日期组合筛选，适合活动日历或城市列表查询',
    INDEX idx_events_status_date (status, event_date) COMMENT '按状态和日期过滤，适合展示有效活动',
    INDEX idx_events_title (title) COMMENT '按活动标题建立索引，便于精确或模糊搜索'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='活动/主表：存储 data.json 中每条活动的核心信息';


-- =============================================================================
-- 表9：event_images（活动图片表）
-- 作用：存储 images.json 中每个活动对应的图片列表
-- 数据来源：AIMemory/json/images.json
-- 设计要点：
-- 1) 一条活动可以对应多张图片，因此拆分为独立子表保存
-- 2) 使用 event_id + sort_order 作为排序和唯一约束，保证展示顺序稳定
-- 3) 采用 data URI 形式存储图片内容，兼容前端直接渲染，不依赖本地文件系统
-- =============================================================================
CREATE TABLE event_images (
    id          BIGINT       AUTO_INCREMENT PRIMARY KEY COMMENT '主键ID，自增，图片记录唯一标识',
    event_id    BIGINT       NOT NULL COMMENT '关联 events.id，表示当前图片属于哪条活动',
    image_url   LONGTEXT     NOT NULL COMMENT '图片内容，通常为 data:image/svg+xml;base64,... 格式的 Data URI',
    sort_order  TINYINT      UNSIGNED NOT NULL DEFAULT 0 COMMENT '图片展示顺序，值越小越靠前',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '图片录入时间',

    UNIQUE KEY uk_event_images_event_order (event_id, sort_order) COMMENT '同一活动下图片顺序唯一，避免重复展示顺序冲突',
    INDEX idx_event_images_event_id (event_id) COMMENT '按活动ID查询图片列表，支持一活动多图读取',

    CONSTRAINT fk_event_images_event
        FOREIGN KEY (event_id) REFERENCES events(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='活动图片表：存储每个活动的多张图片，支持按顺序展示';


-- =============================================================================
-- 说明：
-- 1) data.json 中每个对象对应 events 表中的一条记录
-- 2) images.json 中每个对象的 id 与 events.id 对应，images 数组中的每一项分别写入 event_images 表
-- 3) 示例：events.id = 1, event_images.event_id = 1 可以对应 3 张图片
-- =============================================================================