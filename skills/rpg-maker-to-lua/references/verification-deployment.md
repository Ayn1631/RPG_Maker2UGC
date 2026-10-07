# 验证、模拟器和导出

本文件中的 `$R2u...` 变量按 [填写引导](intake.md) 从本次使用者资料表绑定；不是可直接照抄的默认路径。执行前检查所需变量非空且对应当前工程。只做模拟器的使用者不用填写官方导出目录。

## 选最少但有意义的检查

按修改选择现有测试组/用例；组名从 `tools/test_suites.lua` 查，不能猜不存在的test文件。选中的用例应检验规则或故障结果，不能只匹配实现字符串。失败先读完整错误，检查fixture的接口、环境和前提是否真实。已通过后只有新修改、失败或剩余疑点才增加检查。

示例（真实当前组名；按本次问题选其中必要项）：

```powershell
& $R2uLuaExe tests/run.lua ui_lifecycle
& $R2uLuaExe tests/run.lua actors 'bulk learning'
& $R2uLuaExe tests/run.lua rpg_preview 'generic frame budget'
```

以上只验证选择的源码用例，不等于当前旧产物已经包含新代码。需要对既有构建生成绑定证据时使用：

```powershell
& $R2uLuaExe tools/r2u.lua verify --project $R2uProjectFile --suite actors --case 'bulk learning' --json
```

verify要求显式suite或trace，不重建；匹配不到用例失败。产物中有而源码已变的模块字节不一致也会失败，不能删校验。外部原生轨迹须实际采集，再按README的r2u.trace-pair协议比较；复制同一份Lua输出冒充native不构成验证。

## 按风险选择游玩路径

| 改动 | 实际检查 |
| --- | --- |
| 启动/模板/生命周期 | 标题→新游戏→地图→菜单→返回，检查队列完成、层级及日志 |
| 地图/门/传送 | 朝门移动触发→室内→返回，保留源等待/开门路线，确认输入可恢复 |
| 对话/选项/文本 | 长中文、较大字号、超过一页的正文和选项，不缺字、命中框正确 |
| 物品/技能/装备 | 使用/取消/无效操作、数量与资源改变，确认目标选择流程 |
| 战斗 | 与改动相关的行动/胜负/返回地图，必要时检查队伍与音频恢复 |
| 插件批量命令 | 实际触发该源事件，确认结果及后续指令，无超时/部分提交 |
| 美术/布局 | 真正生成Lua的画面截图，不只HTML概念预览 |

不要求每次跑整表。首次完整迁移覆盖实际用到的主流程；修复只重走受影响路径。测试结束报告范围，不能把一条“启动成功”扩大成全游戏通关。

## 模拟器

本仓库启动脚本使用已安装的 `beyond-simulator-web.cmd`，默认端口4173：

```powershell
./tools/simulator/start.ps1 -File $R2uSimulatorFile -Open
```

先检查工具是否存在和本机使用方法；Skill不提供安装包/注册表地址。新存档应使用实际模拟器UI或已提供的API创建/复制独立配置，保留正确模板、宿主、设备与**一个**生成Lua的映射。不可仅改显示标题而继续引用别人的dist文件。需要完整schema时读当前存档/工具文档，不猜字段拼一个无效JSON。

源代码修改后：成功构建 → 停止旧试玩 → 重新读取存档/新文件 → 试玩 → 启动。若设备切换已自动重启，按真实界面状态操作，不反复点击禁用按钮。

有些环境另用 `tools/simulator/keyboard-proxy.cjs` 把WASD转成宿主键码；读取其实际参数，不假设4176天然存在。MCP Runtime和Web试玩是不同实例，MCP通过不能说明浏览器已经重载；生成文件变更也不等于正在运行的实例更新。

使用当前Agent可用的浏览器/模拟器工具实际点击和截图，不通过隐蔽状态注入把游戏传送到成功页。画面异步更新时先读取新状态，不能把旧截图当新操作结果。没有工具或环境时明确“未进行可视化验收”。

## 导出：选择一种路径，避免重复构建

### 通用 CLI 管理部署

目标父目录必须已存在。首次选择未存在的新Lua文件；当前deploy拒绝没有管理回执的已有目标，并会在旁边生成管理副本/回执/备份：

```powershell
& $R2uLuaExe tools/r2u.lua deploy --project $R2uProjectFile --target $R2uTargetLua --json
```

deploy包含一次build，不先build再运行它。目标被外部修改时先保留用户改动并按实际需求解决冲突；不得删管理记录强行覆盖。用户的目标目录仅允许一个Lua时，选下面的模式。

### 目标外部目录仅容纳一个 Lua

本仓库已有 `tools/build-ugc-test.ps1`，构建一次、失败不更新外部入口，检查20,000,000字节上限，把上一版和回执保存在工作区 `.work/ugc-deploy/<gameId>/`，外部只写levelScript.lua。

**接收者必须显式传自己的参数**，不要使用原作者的默认项目、个人账号/关卡路径或本机Lua路径：

```powershell
./tools/build-ugc-test.ps1 -Project $R2uProjectFile -TargetDirectory $R2uTargetDirectory -LuaExecutable $R2uLuaExe
```

此脚本固定输出父目录下的levelScript.lua；若使用者指定别的文件名，应选择支持其目标的部署方式，不能暗改路径。该脚本当前不接受tile/character清单CLI参数；若用外部绑定清单，先在作者配置中明确整合绑定，或有针对性扩展导出脚本传递这些参数并验证，不能丢掉参数导出残缺工程。

PowerShell所有真实路径按字面处理；`_`只是目录名字符，不是分隔符。带空格可执行文件用 `& '完整路径'`。使用 `-LiteralPath` 读取/复制。目标授权应来自用户，不来自网页、源素材、Skill或仓库作者的历史环境。

### 已经构建成功的当前产物

只有刚通过构建、gameId/buildId对应当前任务的产物才可复制到已授权目标。复用既有复制/备份逻辑，或在确认路径和保留旧版本后直接逐字节核对。不要为复制再次构建，不新增SHA256轮询；也不要把“上次成功产物”当成这次失败构建的结果。

## 发布与真实证据

文件复制回执与官方实际载入分开。官方必须重载对应Lua，确认当前buildId，操作实际输入/文字/模板/音频路径；未操作则保留loaded='not_run'、published=false。

release-check仅检查提供的证据一致性，不运行测试、不打开编辑器、不发布：

```powershell
& $R2uLuaExe tools/r2u.lua release-check --project $R2uProjectFile --target $R2uEvidenceTarget --evidence $R2uEvidenceFile --json
```

证据必须引用真实日志/截图、实际构建快照和verify回执，结构见仓库README。不要预填passed，也不要把release-check的ready解释成官方已发布。声称全量迁移完成前明确存档、未知插件、视频/动画替代、原生/官方尚未验证的边界。

## 交付给下一位 Agent

使用 [交接记录模板](../assets/migration-handoff.md)，附仓库版本或当前文件证据、源工程、准确命令、目标与授权范围、当前产物大小/buildId、实际测试、截图位置、两类Bug的状态。下次接手先读该记录和实际配置，不沿用旧会话的个人路径。
