# 插件与进阶功能的双端适配

## 先确认行为，不能假装翻译 JavaScript

本构建器不在千星运行JS，也不自动翻译任意RPG插件。插件修改的原生类、备注解释、参数、事件脚本和绘图均须逐项确定语义。读源代码、受支持命令和实际源调用；必要时在有授权的原生试玩中确认输入/输出，不能仅凭插件文件名宣布兼容。

用表记录：插件名称/版本、启用顺序、参数组合、修改点、源调用位置、Lua实现、原生实现、已验证/未验证。参数哈希或白名单若阻断新工程，先检查变化，不直接删除约束。源插件有混淆/许可限制时明确边界，不移除版权或许可控制。

## 选择实现位置

- 标准MV/MZ语义已支持而公共实现有误：构建器Bug，修公共模块。
- 某插件的可复用能力：独立SDK扩展，显式选择并声明适用profile。
- 大型游戏私有规则或已审查专用脚本集合：清晰的gameAdapter/私有扩展；禁止按gameId偷改通用规则。
- 纯显示差异：明确美术/演出替代契约，不改变战斗/事件结果。

没有现成适配时先实现源工程实际使用的闭包，同时保留剩余缺口。不得禁用源插件、吞掉355/655脚本或357插件命令、将异常catch后当作成功。

## SDK真实参考

以 `extensions/sample.quest/` 为可执行范式，而不是照抄旧架构中的未来目录。当前包包含：

```text
extension.json
schema.json
source/main.lua
build/main.lua
runtime/main.lua
preview/R2UQuest.js
preview/behavior.js
fixtures/shared.json
```

manifest真实字段由 `src/sdk/registry.lua` 校验：id、version、contractVersion、stateSchemaVersion、frameworkVersion、engineProfiles、dependencies、plugin、schema、dataFile、runtime、preview、capabilities，以及需要时的sourceAdapter/buildAdapter。

扩展选择项的字段是path、version、config及可选integrity。Agent应读取**本次使用者选定包**的真实manifest，将其路径/精确版本/已填config写入extensions；不要预填sample.quest路径或版本，也不要因示例有任务系统就给所有游戏启用它。包内README及schema决定应追问的config字段。

扩展源共享数据路径为 `data/r2u/<extensionId>/<dataFile>`。ID与数据契约在原生和Lua两端共用。不能把共享数据仅写到构建目录，让原生试玩读另一份手写副本。

**现有第三方插件不一定能直接装入通用SDK。** 当前registry.acceptPlugin拒绝非空`js/plugins.js`参数（通用契约使用显式config/共享数据），且源插件JS须与包内登记的对应native适配文件逐字节一致；注册时还校验原生适配的身份契约。只抄sample.quest的manifest、改plugin名字或放入未经适配的原JS都不够。不要改源参数为空、篡改manifest或删除检查来伪装支持。

对已有任意自定义任务插件，先查它是否已遵守R2U共享数据/原生适配约定。若没有，需实现明确的专用插件适配器，或在作者允许的工作副本中接入受支持的双端SDK契约并原生复核；默认保持原工程不变。用户没有授权改源时不能把“为了接SDK改了插件”藏在迁移中。此依赖应在首次盘点时说明，避免等到资源导出/构建才发现阻断。

## 接口职责

| 部分 | 任务 |
| --- | --- |
| schema | config/data/state、命令参数、查询结果、菜单、备注与额外输入的类型/范围 |
| SourceAdapter | normalize及可选collectInputs，收集源备注/静态文件并转换成统一输入 |
| BuildAdapter | compile，生成静态计划、私有索引与可执行Lua模块；不访问宿主UI |
| Lua runtime | initial、execute，以及声明了才需要的query/menu/policy；通过context获得明确服务 |
| Native preview | MV/MZ插件入口和行为，遵守相同ID、参数、状态转移和结果 |
| fixtures | 两端共用初态、输入、预期结果，能覆盖幂等/边界/取消 |

命令能力、状态schema和菜单不是任意table通道。查询不得暗中改变状态；游戏规则通过规则接口接入，不能在UI绘制器里偷偷结算金币或伤害。同一排他policy冲突须诊断。扩展不要直接调用宿主创建/销毁控件绕过公共400/400预算。

新增模块登记真实依赖，运行时不得用require/load或任意脚本字符串。生成程序保留源位置，以便报错定位到原始命令，而不是只留单Lua行号。

## 批量操作也要正确转换

看到源循环先判断副作用和顺序。纯技能集合并集可批量合并，物品获得有提示/上限/交易副作用则需按契约处理。不能一概把所有循环异步化，因为后续命令可能依赖立即完成的结果；需要分帧时用已有事件等待/恢复token协议，完成前不越过后续指令。

VisuMZ公共事件20的实际修复：163技能×8角色被旧接入转成1304次角色事务及视图计算。现使用公共 `actors.learnSkills(actorIds,skillIds)`，先验证全部引用、去重、一次提交，不复制Party、不请求未使用的stats视图。此为明确学习行为的优化，不能宣称所有JS循环都支持。

## 双端验收

至少检查源入口实际可调用、同输入状态一致、错误/重复执行不双发奖励、菜单读写契约一致。MV/MZ只实现一端就只声明该端。轨迹比较可复用已有verify机制，但不得自行编造两份相同JSON当“原生通过”。测试只覆盖新增能力的关键语义，不重复整个游戏全套。

先记录工程转换Bug，再说明新增公共能力与回归范围。一次专用参数组合通过，不能扩写成“所有VisuStella/Aurora插件兼容”。
