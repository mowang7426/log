# CrashAnalyzer 1.4.0 final changelog

## 可见功能
- IPSLog 列表继续使用 `CAReportViewController : PSListController`，以 PSSpecifier 构建，避免 Preferences 将普通 UITableViewController 当 detail 实例化。
- 列表顶部提供搜索与按时间/按进程切换；搜索字段包括进程、Bundle ID、文件名、异常、时间、bug_type、Panic、watchdog、Jetsam reason/largestProcess。
- “按类型查看日志”的崩溃、内存、重启、资源、其他及同类分类页移除重复的自定义返回，仅保留 Preferences 导航栈的系统原生返回和侧滑手势；左侧分组操作不充当返回。分类页右上角原有“清空”与搜索继续并存。
- “最近日志”右上角新增与搜索并存的“清空”。二次确认时冻结当前已加载的全部最近日志（不是当前搜索结果）与 `CALogStore.deletableReportPaths` 的交集并显示数量；复用 `deleteReportsAtPaths:`，不触及确认后新增日志、AI 历史、案例或插件证据，完成后重新扫描刷新并显示成功、失败数量。
- 分类清空保持现有行为：确认弹窗显示数量并冻结当前分类中经 `CALogStore` 核准的普通日志路径；不触及其他分类、AI 历史、案例、插件证据或确认后新增日志。
- 单条日志可从原生详情旁选择删除或直接删除；选择多条后使用顶部批量删除并二次确认。删除保持安全的普通文件路径快照，不删除 AI、案例、插件证据或用户未列入快照的新文件。
- 详情保持本地分析、AI/case/plugin evidence、增量扫描、工作台及原文入口；Jetsam/Panic/watchdog 专项字段继续显示解析状态与不确定性边界。

## 兼容与构建
- 未引入或编译 `CALogListController`；未修改 main；未安装插件；未主动删除用户日志。
- `CALogExperience.m` 在 Makefile 中，包含 `CAReportDate` 实现；建议 CI 对 bundle 执行 undefined-symbol 检查，重点确认 `_CAReportDate` 不在未定义列表。
- Foundation 回归覆盖搜索专项字段、日期时区排序、严格 IPS 解析、删除路径安全性及 Jetsam pageSize 行为。

## 限制
- 本次环境未进行真实设备安装、Settings 视觉回归或 RootHide 权限差异验证；这些仍需在目标设备确认。
- UIKit/Preferences 私有 API 的最终行为以设备系统版本为准；实现刻意使用 Preferences 生命周期及原生 PSSpecifier 导航。
