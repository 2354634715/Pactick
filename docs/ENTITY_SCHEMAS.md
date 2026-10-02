# 同步实体字段契约

本文件定义 `POST /v1/sync/push` 中 `patch` 的领域字段。实体 ID、版本、删除状态和设备审计由同步信封传递，不属于 `patch`。

创建实体时，`base_version` 为 0，`patch` 必须包含该实体的全部必填字段。更新实体时，只上传发生变化的顶层字段，字段集合必须与 `changed_fields` 完全一致。可选字段传 `null` 表示清除该字段。

整数值必须使用 JSON 整数。时间点必须使用带偏移量的 RFC 3339 格式，服务端统一保存为 UTC。

## project

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `name` | 必填，1–120 字符 | 项目或清单名称 |
| `color` | 可选 | `#RRGGBB` 或 `#RRGGBBAA` |
| `archived` | 可选布尔值 | 是否归档 |
| `sort_order` | 可选整数 | 项目列表排序值 |

## task

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `title` | 必填，1–500 字符 | 任务标题 |
| `note` | 可选，最多 50,000 字符 | 备注 |
| `project_id` | 可选 UUID | 为空时位于收集箱 |
| `priority` | 必填 | `none`、`low`、`medium`、`high`、`urgent` |
| `due_at` | 可选时间 | 截止时间，不表示排期 |
| `estimated_duration_seconds` | 可选非负整数 | 预计总用时 |
| `status` | 必填 | `open`、`completed`、`cancelled` |
| `completed_at` | 条件必填 | `completed` 时必须存在，其他状态必须清除 |
| `recurrence_rule_id` | 可选 UUID | 简单重复规则 |
| `recurrence_source_task_id` | 可选 UUID | 重复实例的来源任务 |
| `occurrence_date` | 可选本地日期 | 与来源任务同时存在；格式 `YYYY-MM-DD` |

相同账户下 `(recurrence_source_task_id, occurrence_date)` 唯一。离线客户端应使用稳定的 UUIDv5 生成实例 ID。各客户端生成的 ID 不同时，数据库唯一约束仍会拒绝同一来源任务在同一日期的重复实例。

## task_recurrence_rule

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `task_id` | 必填 UUID | 规则所属的来源任务 |
| `frequency` | 必填 | `daily`、`weekly`、`monthly` |
| `interval` | 必填，1–365 | 重复周期的间隔数 |
| `days_of_week` | 周重复必填 | 0–6 的去重数组，0 表示周日 |
| `day_of_month` | 月重复必填 | 1–31；短月份由客户端使用该月最后一天 |
| `starts_on` | 必填日期 | 首个可生成日期 |
| `ends_on` | 可选日期 | 最后可生成日期 |
| `max_occurrences` | 可选正整数 | 最大实例数 |
| `time_zone` | 必填 | IANA 时区 |

创建带重复规则的任务时，先创建不含 `recurrence_rule_id` 的任务，再创建规则，最后将规则 UUID 写回任务。该顺序避免任务与规则循环引用导致的提交排序问题。

## tag 与 task_tag

`tag` 必须包含 `name`（1–80 字符），可包含 `color`。`task_tag` 必须包含 `task_id` 和 `tag_id`。关联记录不可修改；移除关联时软删除记录，重新关联时使用新 UUID 创建记录。同一任务与标签只能有一条活动关联。

## plan_block

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `task_id` | 可选 UUID | 关联任务 |
| `title` | 条件必填 | 不关联任务时必须存在 |
| `starts_at` | 必填时间 | 计划开始 |
| `ends_at` | 必填时间 | 计划结束，必须晚于开始，跨度不超过七天 |
| `time_zone` | 必填 | 创建该计划时使用的 IANA 时区 |
| `status` | 必填 | `scheduled`、`completed`、`cancelled` |
| `original_plan_block_id` | 可选 UUID | 拆分或延期时指向来源计划 |

## day_entry

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `local_date` | 必填日期 | 今日清单所属本地日期 |
| `task_id` | 可选 UUID | 关联任务 |
| `plan_block_id` | 可选 UUID | 关联计划时段 |
| `title` | 条件必填 | 任务和计划均未关联时必填 |
| `source` | 必填 | `planned`、`manual` |
| `rank` | 必填，1–100 字符 | 离线可合并的有序字符串，如 fractional rank |
| `status` | 必填 | `pending`、`completed`、`deferred`、`skipped` |
| `deferred_from_date` | 可选日期 | 延期来源日期 |

相同计划时段和日期只能有一个活动今日条目。当天计划尚未保存为正式今日条目时，今日读模型返回派生条目。

## focus_policy

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `name` | 必填，1–120 字符 | 规则名称 |
| `mode` | 必填 | `normal`、`guard`、`strict` |
| `allow_pause` | 必填布尔值 | 是否允许暂停 |
| `early_exit_mode` | 必填 | `allow`、`reason`、`countdown` |
| `early_exit_wait_seconds` | 可选，0–300 | 提前退出前的等待秒数 |
| `max_app_exits` | 可选，0–1000 | 允许的离开次数 |
| `allowed_app_ids` | 兼容字段，只允许 `null` 或空数组 | 0.2 起应用标识与按项目白名单仅保存在设备本地；非空数组会被拒绝 |
| `emergency_app_categories` | 可选字符串数组 | 电话、地图、认证等类别 |
| `notification_mode` | 必填 | `silent`、`sound`、`vibrate`、`sound_and_vibrate` |
| `sound_enabled` | 可选布尔值 | 声音开关 |
| `vibration_enabled` | 可选布尔值 | 震动开关 |

已安装应用目录、包名、应用标签、当前前台应用、Usage Access/悬浮层权限状态和按收集箱或项目保存的白名单均为设备私密数据，不进入同步协议。跨设备只同步不含应用身份的策略参数。

客户端为兼容旧文档发送 `allowed_app_ids` 时，必须使用空数组；推荐省略该字段。升级既有服务器时，迁移 `000002_remove_synced_app_identifiers` 删除当前策略正文中的该字段，并发布脱敏后的实体快照。后续迁移 `000003_purge_historical_app_identifiers` 清理当前策略、旧同步日志、幂等结果快照，以及冲突记录顶层或 `body` 中的该字段；从游标 0 拉取或重放旧操作时不再返回其中的应用标识。

迁移不会改写已经生成的数据库备份。旧备份可能仍包含应用标识，管理员应按实际保留要求处置；恢复旧备份后，必须在开放 API 前执行完整迁移。升级时先停止旧版本 API；旧版本不遵守当前同步写锁，不能与迁移同时运行。

## focus_session

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `task_id` | 可选 UUID | 实际工作的任务 |
| `plan_block_id` | 可选 UUID | 对应计划时段 |
| `focus_policy_id` | 可选 UUID | 本次使用的规则 |
| `planned_duration_seconds` | 必填正整数 | 本次目标时长 |
| `started_at` | 必填时间 | 实际开始时间 |
| `ended_at` | 终态必填 | 实际结束时间 |
| `pause_started_at` | 暂停态必填 | 当前暂停开始时间 |
| `pause_intervals` | 条件必填 | 有暂停时保存全部暂停区间；仅暂停态允许最后一个区间没有结束时间 |
| `paused_duration_seconds` | 可选非负整数 | 使用可靠时钟累计的暂停秒数 |
| `actual_duration_seconds` | 终态必填 | 使用可靠时钟累计的实际专注秒数 |
| `started_device_id` | 必填 UUID | 必须等于创建该记录的设备 |
| `status` | 必填 | `running`、`paused`、`completed`、`abandoned`、`interrupted` |
| `termination_reason` | 可选，最多 1,000 字符 | 提前结束或异常原因 |
| `time_zone` | 必填 | 开始专注时的 IANA 时区 |
| `app_exit_count` | 可选非负整数 | 离开次数汇总 |
| `interruption_count` | 可选非负整数 | 中断次数汇总 |

终态专注记录不可覆盖，继续工作必须创建新的专注记录。已有会话的更新和删除必须由 `started_device_id` 对应的设备提交，其他设备收到 `focus_device_mismatch`，但仍可读取同步快照与历史记录。账户级约束禁止同一账户同时存在多个活动专注；时间区间约束检查已结束的离线记录之间是否重叠。

## focus_interruption

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `focus_session_id` | 必填 UUID | 所属专注 |
| `kind` | 必填 | `app_exit`、`phone`、`unlock`、`permission_disabled`、`clock_change`、`process_recovered`、`manual` |
| `category` | 必填 | `emergency`、`allowed`、`restricted`、`unknown` |
| `started_at` | 必填时间 | 中断开始 |
| `ended_at` | 可选时间 | 中断结束 |
| `duration_seconds` | 可选非负整数 | 可靠时钟累计时长 |

中断记录不可修改，应在事件结束后追加。客户端应在本机完成白名单判断，只上传分类和汇总。服务端拒绝具体应用 ID、包名、应用名称、前台应用和应用使用明细字段。

## reminder

| 字段 | 要求 | 说明 |
| --- | --- | --- |
| `target_type` | 必填 | `task`、`plan_block` |
| `target_id` | 必填 UUID | 同账户目标 |
| `trigger_at` | 必填时间 | 触发时间 |
| `time_zone` | 必填 | 创建提醒时的 IANA 时区 |
| `status` | 必填 | `scheduled`、`fired`、`dismissed`、`cancelled` |
| `delivery_mode` | 必填 | 第一版固定为 `local` |

各客户端在本地调度提醒。服务端只同步提醒定义和状态，提醒触发不依赖云端在线。
