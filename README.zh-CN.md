# RPG Maker → Lua → UGC

[English](README.md) | 简体中文

RPG_Maker2UGC 可将符合当前适配范围的 RPG Maker MV/MZ 工程转换为面向 UGC 的独立 `levelScript.lua`。转换和打包在线下完成：游戏逻辑、静态数据、资源绑定及已登记扩展会编译进一个 Lua 文件。

本仓库包含构建器源码和 [`rpg-maker-to-lua` 迁移 Skill](skills/rpg-maker-to-lua/SKILL.md)，不包含游戏工程、游戏素材、目标 UI 模板目录、示例工程或测试夹具。请使用你有权使用的源工程及其资源和模板绑定。

## 支持范围

- 地图、事件、移动、对话、选项、开关、变量及常见 RPG Maker 游戏数据。
- 队伍、库存、装备、技能、物品、商店、菜单，以及当前适配的回合制或 TPB 战斗流程。
- 离线资源处理、显式模板/资源绑定，以及面向 UGC 宿主的模块化 Lua 运行时。
- 类型化扩展 SDK。JavaScript 插件需要显式适配；工具不会自动转换任意插件。
- 工程检查、构建诊断、单文件输出，以及带备份的本地部署。

模块已实现不代表每个引擎版本、插件、参数或目标模板均已验证。遇到缺失或不支持的输入时，应记录为构建缺口，不要用猜测的资源替代。构建成功也不代表官方编辑器已加载、运行、验收或发布产物。

## 存档支持

存档功能目前尚未开发，因为我的 UGC 创作者等级还不够；后续会补充。

## 环境要求

- Lua 5.3。
- 创建目录和部分资源导出/部署流程使用 LuaFileSystem（`lfs`）。如果没有 `lfs`，请预先创建相关输出目录。
- 只有可选的 UI 模板目录导入步骤需要 Python。

核心转换不需要网络。目标 UGC 编辑器和游戏运行与此命令行构建流程相互独立。

## 快速开始

在仓库根目录运行命令，从你自己的 RPG Maker 工程初始化配置：

```sh
lua tools/r2u.lua init --source "path/to/your-rpg-maker-project" --game-id my-game
```

检查 `projects/my-game/project.lua`，填写本工程所需的目标模板 ID，以及明确的资源、音频和扩展绑定，然后检查并构建：

```sh
lua tools/r2u.lua inspect --project projects/my-game/project.lua
lua tools/r2u.lua build --project projects/my-game/project.lua --json
```

生成的脚本位于 `dist/my-game/levelScript.lua`。构建还会生成包含诊断信息和源映射的报告。源工程作为输入读取；生成的配置、报告和产物保留在本机忽略目录中。

要将构建产物复制到本地目标文件，请使用已存在的目标目录：

```sh
lua tools/r2u.lua deploy --project projects/my-game/project.lua --target "path/to/ugc/levelScript.lua"
```

`deploy` 只构建一次，并为目标管理备份；它不会在编辑器中加载文件，也不会发布。运行 `lua tools/r2u.lua help` 查看当前命令摘要。

## 命令

| 命令 | 用途 |
| --- | --- |
| `init` | 检查源工程并生成工程配置与接入说明。 |
| `inspect` | 检查工程结构、事件、规则、绑定和已登记扩展。 |
| `build` | 转换并打包为单个 Lua 文件，同时输出诊断信息。 |
| `deploy` | 构建一次，然后带备份更新受管理的本地 Lua 目标。 |
| `export-tiles`、`export-characters` | 导出选中的源图像和绑定清单。 |
| `export-primitives` | 创建只包含明确选中图元素材的可编辑库。 |
| `verify` | 使用显式选择的本地测试用例或提供的轨迹检查已有构建。本仓库不含测试夹具。 |
| `release-check` | 检查已有构建和验收记录；不会运行游戏或发布。 |

若要使用不同的 UI 模板集合，可以通过 `tools/import-ui-templates.py` 从兼容的存档导入模板目录。该可选步骤需要 Python；常规转换使用 Lua。

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `src/converter/` | RPG Maker 源工程检查与转换。 |
| `src/build/` | 打包、工程初始化、部署、验证和发布检查。 |
| `src/runtime/` | 游戏、地图、RPG、UI 和音频运行时模块。 |
| `src/platform/ugc/` | UGC 宿主集成和 UI 生命周期管理。 |
| `src/sdk/` | 扩展契约和运行时注册。 |
| `tools/` | 构建器入口、模块清单及通用工具。 |
| `skills/rpg-maker-to-lua/` | 完整迁移 Skill，包含参考资料和模板。 |

## 迁移 Skill

阅读 [SKILL.md](skills/rpg-maker-to-lua/SKILL.md) 或使用 [Skill ZIP](skills/rpg-maker-to-lua.zip)。它会引导 Agent 盘点源工程、查找绑定、显式适配插件，并完成验证与部署。Skill 本身不包含构建器、游戏素材、目标模板 ID 或发布权限。

## 许可证

本仓库使用 [GNU GPL 第 3 版](LICENSE)。`src/vendor/` 中的压缩库另附许可证和来源说明。
