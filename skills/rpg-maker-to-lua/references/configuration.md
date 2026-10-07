# project.lua、模板与目标绑定

**先填资料，再生成配置。** 字段收集的问法、空值处理和阶段条件见 [填写引导](intake.md)；可直接交给使用者编辑 [空白资料表](../assets/migration-inputs.md)。本文解释构建器字段名，不给任何人预设工程、引擎版本、目标ID或导出位置。

## 配置如何读取

`project.lua` 是返回一个配置表的受信任开发文件，当前 CLI 用空环境执行，不能在里面调用 require、os 或其他全局函数。使用普通 Lua 字面量。读 `src/cli.lua` 的 `project_config` 取得本版本字段白名单；不要把此 Skill 的流程变量写成未知配置项。

| 顶层字段 | 当前含义和限制 |
| --- | --- |
| gameId | 工程隔离标识；小写字母开头，后续字母/数字/下划线/连字符，≤64字符，排除系统保留名 |
| sourceRoot | 原始游戏根；相对当前配置文件或绝对路径，不是相对命令执行目录 |
| engineProfile | mv-turn / mz-turn / mz-tpb-active / mz-tpb-wait；必须匹配源战斗模式 |
| sourceVersion | 实际核心版本，不能写假值绕过转换器限制 |
| worldPreview | 完整地图/RPG接线；默认迁移选择 presentation='rpg-maker' |
| eventPreview | 单事件开发预览，含 programId、textTemplate、buttonTemplate；与 worldPreview 互斥，不等于完整游戏 |
| audioBindings | 源音频名→信号index或客户端SE资源；见平台参考 |
| assetBindings | 已存在的目标资源模板；精确键和帧尺寸见资源参考 |
| primitiveArt | `{path='art/primitives.lua'}`，项目内相对路径；已审核图元库，不是自动猜资源开关 |
| uiTemplateCatalog | 项目内相对JSON路径；模板根/后代结构与默认值，供真实控件数预算使用 |
| fontBindings | 显式source字体模式的映射/补字；platform一般直接用宿主文字，不复制作者机器字体绝对路径 |
| extensions | 显式扩展选择数组，path/version/config及可选integrity；见扩展参考 |
| gameAdapter | 明确的专用适配器；只在确认对应插件和参数契约时使用 |
| displayLocale | 本版本只支持已审查Visu样例的zh-CN，不是通用翻译开关 |

`primitiveArt` 历史 mode/detail/tileCategories 字段不能当作生成新造型的方法；当前只按明确库转换。旧设计中的存档/网络档案不是此配置白名单的已实现字段。

## worldPreview 的实际字段

完整游戏使用 `presentation='rpg-maker', renderMode='platform', actors=true`。`diagnostic` 为开发地图视图；`source` 为源字形/像素对照路径，控件成本高，不是普通千星移植默认。

| 字段 | 绑定什么 |
| --- | --- |
| containerTemplate | 空容器模板索引，用于场景/地图/资产父节点 |
| textTemplate | 原生文本框模板索引；检查字号下限、对齐、换行和颜色 |
| buttonTemplate | 按钮模板索引；不要假定原生按钮自带可写文字，标签可能是独立文本控件 |
| imageTemplate | 可设置颜色与图片源的图片控件模板索引 |
| cursorTemplate | 原生窗口交互/光标模板索引，按目标接口确认类型 |
| whiteImageId | 用于矩形等绘制的图片资源ID；不是模板索引 |
| artTemplates | portrait/icon及精确faces/icons映射；它们不是所有缺失素材的兜底资源 |
| windowPattern | platform只允许simple；source路径另有source/geometry，勿混用 |

## 将使用者填写结果落到配置

运行init取得本次配置候选后，按下表逐项写入，不能复制旧项目后只改sourceRoot：

| 本次资料来源 | Agent写入位置 | 未有值时怎么做 |
| --- | --- | --- |
| 已选gameId、实际源根 | gameId、sourceRoot | 只问仍缺的源路径；标识可建议并检查冲突 |
| 实际核心脚本与System | sourceVersion、engineProfile | 回到源文件定位，不让使用者猜版本号 |
| 当前目标的UI模板表 | worldPreview对应字段及artTemplates | 解释取得位置，保留待填，不借用别人的数字 |
| 同目标真实模板结构 | uiTemplateCatalog，转为当前项目内相对路径 | 提取/登记结构，不能只填一个不存在的文件名 |
| 源音频清单及接收端/资源ID | audioBindings | Agent列出缺少的源名和所需index/audioId，由使用者或目标文件补充 |
| 精确资产清单/实际图元库 | assetBindings或primitiveArt.path | 继续适配/重绘，不添加默认人或默认地块 |
| 已确认插件契约 | extensions或明确gameAdapter | 缺适配则登记缺口，不套visu/aurora示例值 |
| 使用者语言/美术需求 | 仅写当前实现支持的可选项 | 不支持就列为额外工作；不自动打开专用displayLocale |

汇总展示“字段、实际值、来源、未填原因”，供使用者看清自己的配置。已明确的值无需再次总审批；遇到矛盾或缺少关键决策再询问。未准备图元库时不要留下不存在的path。空audioBindings是“启用但没有绑定”，不是“源声音自动播放”；不能以删除该字段静默满足使用者需要声音的要求。

## 四种 ID 不可混淆

| 身份 | 生命周期/用途 |
| --- | --- |
| RPG源ID/源名+索引 | 固定语义键，如技能ID、tilesetId:tileId、Actor1:0 |
| 客户端模板索引 | 编辑器配置的可克隆模板，传给InstantiateClientUIControl |
| imageId / audioId | 千星图片/音效资源身份；可能被模板引用，但不是模板本身 |
| 运行实例id | 克隆后宿主分配，用于对象查找；不填写到project.lua、不跨运行保存 |

脚本映射索引也由目标工程设置，不能拿图片模板索引充当Lua入口。官方文档运行实例字段是小写`id`；模拟器存在大写`Id`变体。使用公共调度器处理此差异，不在项目中填假运行ID。

## 模板目录不是可选的成本猜测

从已配置且对应目标结构的模拟器存档导出：

```powershell
& $R2uPythonExe tools/import-ui-templates.py --source $R2uSimulatorFile --output $R2uTemplateCatalogFile
```

仅导入器依赖Python；生成目录后普通构建用Lua即可。目录包含version、模板ID、kind、properties、colors、children及每个子树count。根也算1个。现有导入器接受已支持的基础控件类型，拒绝动态/引用等不受支持类型及挂脚本模板，不能忽略错误手写count。

上面变量来自本次资料表；同一模拟器存档只证明其中的模板结构。默认 `assets/client-ui-templates.json` 是随附模板的实际结构，并非所有千星工程的模板注册表；只有核对为同一组模板才使用。若目标里模板增减了子控件，重新导入目录再构建。一个原子模板超过400控件必须拆分；构建器不能在一次宿主克隆内部暂停。

## 挂载步骤

在目标客户端UI建立宿主容器，绑定单Lua入口及实际基础模板；在宿主容器设置屏蔽按键穿透。正常导出入口通过 `script.object` 获取宿主，无需另填宿主实例ID。根画布尺寸、缩放、锚点与输入坐标必须一致。创建/绑定模板不由build自动完成；缺目标模板时明确报告，不拿模拟器ID冒充。

保留作者已有配置值。替换某个头像或资源模板ID后，同步目录、重新构建；不要让框架每次移动时改写模板全部后代。模板中的图片内容归模板所有。
