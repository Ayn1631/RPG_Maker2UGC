# 工程迁移流程与代码导航

## 1. 接入前的事实表

先按 [填写引导](intake.md) 建立本次使用者的资料表。路径与交付目标由使用者提供或从当前上下文取得；版本、MV/MZ、战斗模式、插件及源资源由Agent读取。目标模板只能来自本次目标档案。不要为绕过版本校验把版本号改成支持值。

本次核对的标准 UI 支持 MV 1.5.1、MZ 1.10.0；MZ 1.9.0 仅有已审查 Visu 工程的明确分支。`mv-turn`、`mz-turn`、`mz-tpb-active`、`mz-tpb-wait` 是 profile，不代表整个版本系列都已兼容。检查 `src/converter/ui.lua`、`src/converter/inspect.lua` 和具体适配器。

普通构建用 Lua 5.3；LuaFileSystem 用于 init、目录准备和部署检查。Python 用于模板目录导入或已有离线美术工具；Node 只在模拟器、原生 HTML5 试玩等流程需要。不要为了转换先安装所有工具；缺哪个再按用户授权处理哪个。RPG Maker 编辑器不是读取现有工程的必要条件，原生验收才需要对应环境；安装试用版不等于获得素材再分发许可。

## 2. 首次配置

以下命令使用 [填写引导中的变量表](intake.md)，由Agent绑定为本次实际值后执行；未填写的变量不得带入命令，不提供可误复制的示例个人路径。先进入使用者的真实仓库：

```powershell
Set-Location -LiteralPath $R2uRepoRoot
& $R2uLuaExe tools/r2u.lua --help
& $R2uLuaExe tools/r2u.lua init --source $R2uSourceRoot --game-id $R2uGameId
```

有已核对的绑定档案才使用：

```powershell
& $R2uLuaExe tools/r2u.lua init --source $R2uSourceRoot --game-id $R2uGameId --bindings $R2uBindingsProjectFile
```

上述两条init路线只选一条。`init` 不改源工程，已有配置写到 `project.candidate.lua` 或编号候选。读回执中的实际output，并据此填写 `$R2uProjectFile`，不假定刚创建的候选就是现有 `project.lua`。默认模板ID为0，表示仍需引导使用者填写，不能直接构建。

当前 `--bindings` 只复制 worldPreview、fontBindings、audioBindings、assetBindings；**不会复制 primitiveArt、uiTemplateCatalog、extensions、gameAdapter 或 locale**。带路径的资源需重新定位，模板目录和艺术库也需明确接入；复制绑定不等于换游戏完成。

## 3. 引用与兼容盘点

- 数据库：System、Actors、Classes、Skills、Items、Weapons、Armors、States、Enemies、Troops 等实际引用。
- 地图：通过 MapInfos ID 找 MapXXX.json；记录事件页条件、触发类型、优先级、移动路线、传送、并行/自动执行与公共事件。
- 插件：读取静态 `js/plugins.js`，逐个区分已支持、需要适配、明确不在本次范围。不执行它来探测，不删除启用项。
- 资源：角色/头像索引、图块 recipe、敌人、战斗背景、图标、动画、剧情图片及音频源名。动态插件引用必须由适配器明确收集。

把缺口按“阻止编译”“已有明确替代”“待官方验证”记录，勿写笼统的“全兼容”。源工程本身的问题与迁移错误可通过同路径原生试玩区分；无法原生复现时保持未确认。

## 4. 配置与转换迭代

先解决插件/脚本、源身份及绑定，再构建。第一次需要诊断时：

```powershell
& $R2uLuaExe tools/r2u.lua inspect --project $R2uProjectFile --json
```

按诊断的 code、file、jsonPath、commandIndex 回到源/适配器。一个错误可能导致大量下游缺口，先修最早的明确根因。已知配置齐备后直接 build 即可，build 自带 inspect，不需要每次先重复 inspect。

```powershell
& $R2uLuaExe tools/r2u.lua build --project $R2uProjectFile --json
```

只编辑作者配置、源码和显式库；`generated/` 与 `dist/` 为生成产物。不要在 dist 里手工换 ID 后交付，下一次构建会丢失修改。

## 5. 模块定位

| 内容 | 真实入口 |
| --- | --- |
| 命令/配置校验与构建编排 | src/cli.lua、src/build/project_init.lua |
| 读取/事件/地图/规则转换 | src/converter/inspect.lua、events.lua、world.lua、rpg.lua |
| 预编译目录与程序 | src/converter/*_program.lua、生成模块清单 |
| 显式资源和宿主模板目录 | src/converter/resources.lua、primitive_art.lua、ui_templates.lua |
| 插件注册、类型与共享契约 | src/sdk/、extensions/sample.quest/ |
| 地图、事件调度 | src/runtime/world/session.lua、events.lua |
| 角色与战斗规则 | src/runtime/rpg/ |
| 游戏菜单和布局 | src/runtime/ui/ |
| 控件、输入接线、地图渲染 | src/platform/ugc/ |
| 单 Lua、来源映射与部署 | src/build/bundle.lua、deploy.lua |
| 生命周期与400/400总预算 | src/runtime/entry.lua、src/platform/ugc/ui_lifecycle.lua |

发现源码路径不存在，先 `rg --files`，不要根据旧设计目录继续编造文件。更改公共能力时保持无 gameId 分支；工程专用转换在明确适配器中。

## 6. 已有专用工程的边界

`gameAdapter='aurora'` 对应已经审查的 AuroraCore/Aurora；`gameAdapter='visu'` 对应仓库的 VisuMZ 示例及已锁定参数。Chachi、LanternNight 也有各自准备与资源工具。这些名字不是任意同类插件包的开关。不要把 `tools/pokemon-art.py`、`tools/visu-art.py` 等当作能重绘任意游戏的通用命令。

完成配置/适配后按 [验证与导出](verification-deployment.md) 选择一次构建路径；不要先 build 再无条件 deploy 重建同一版本。
