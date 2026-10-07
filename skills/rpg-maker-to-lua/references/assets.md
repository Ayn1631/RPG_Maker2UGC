# 资源映射、图元重绘与图层

先按 [填写引导](intake.md) 取得本次美术路线和目标档案。Agent自动枚举源键，在 [资料表E组](../assets/migration-inputs.md) 留待填写的目标模板/图元对应行；不能沿用旧游戏的faces、icons、tiles映射。下文命令变量均取自当前使用者已填资料。

## 身份先于美术

源工程通过数据库ID、资源名、图集索引及图块ID引用资源。名称“像树”、绿色像草、同名不同图集、编号取余等都不能决定映射。先建立明确对应，再决定目标外观；用户允许风格化并不允许错误绑定。

| 资源 | 明确源身份 |
| --- | --- |
| 地图地块 | tilesetId + tileId，并核对Tilesets图集槽、普通/自动图块recipe及图层 |
| 角色行走 | characterName + 从0开始的characterIndex；方向2/4/6/8及每方向3步态 |
| 头像 | faceName + 从0开始的faceIndex，通常键 `Actor1:0` |
| 图标 | 实际IconSet索引；物品图标0可为实际资源，不能套用“状态icon0无图标”规则 |
| 敌人/侧视角色 | 源ID与真实battlerName、动作帧契约同时保留 |
| 战斗背景/远景/剧情图片 | 类型目录 + 源名称，不能只按basename混用 |
| 动画/气泡/视频替代 | 源ID或名称 + 已声明时间/帧/尺寸/声音契约 |

审阅记录建议带 sourceIdentity、sourceCrop/sourceRecipe、目标键、模板ID或图元库条目、原图与目标截图及允许的差异。源png数学切片/自动图块拼接不是猜测；但不能以图块ID区间猜“墙/草/树”。

## 两条可执行路线

### 目标图片模板

使用有授权的图像，按源规则裁切为目标图片模板，保留尺寸/透明区域/锚点。已有工具只导出PNG和清单，**不会上传图片或替你创建官方模板**：

前置条件：当前export-tiles/export-characters也先经过project_config、插件inspect和事件compile。init留下的0基础模板ID、未支持的插件/脚本会在导出前阻断。它们不是绕过适配检查的独立PNG切图器；缺目标ID时先做源资源盘点，取得基本绑定并完成所需插件适配后再执行。不要为拿到图片清单临时删源插件。

```powershell
& $R2uLuaExe tools/r2u.lua export-tiles --project $R2uProjectFile
& $R2uLuaExe tools/r2u.lua export-characters --project $R2uProjectFile
```

把生成的 manifest.json 复制到作者维护的绑定文件再填ID，不修改会被重导出覆盖的manifest。图块的uniqueFrames/tableEdge、人物12帧和需要的bush上下半身按清单填，不重新猜序号。

“自定义角色图片”若仍遵守RPG Maker标准图集，可沿用现有切片：普通表是12列×8行（8角色，每角色3步态×4方向），`$`单角色表是3列×4行。更改了帧数、方向数、布局或插件切片规则的图集须明确适配，不能仅改宽高就宣称支持。

```powershell
& $R2uLuaExe tools/r2u.lua build --project $R2uProjectFile --tile-bindings $R2uTileBindingsFile --character-bindings $R2uCharacterBindingsFile
```

源键不能在project.lua和导入清单中重复覆盖。新模板必须进入uiTemplateCatalog。使用外部清单时，后续build/部署也必须携带同样的参数，或明确整合回作者配置，不能导出时漏绑定。

### 明确图元库

按原图/可读取绘图代码绘制矩形、椭圆、三角形等真实UI图元，存为 `primitiveArt.path` 指向的Lua库；不是AI生成的整张图片，也不是把像素逐个变成控件。库结构以 `src/converter/primitive_art.lua` 和已有库为准，帧由 `src/assets/primitive_art.lua` 校验。

帧包含 kind='r2u.primitive-frame'、schemaVersion=1、width/height、RGBA palette、rects。每个图元使用已支持的imageId、x/y/width/height/colorIndex及可选rotation；不要擅自塞SVG路径或任意PNG给此格式。当前帧校验最多512图元、16色，并有限定的原生形状ID；这是本实现边界，不是官方通用资源上限。更复杂轮廓需要明确扩展或多部件设计，不能关掉校验。

`export-primitives` 只校验和选择已有库中被引用的条目，输出选择库，不会首次自动把任意PNG理解成角色/房屋。旧CLI帮助中的“creates an editable library”措辞不能当作自动重绘能力。作者确认的库不存在时先完成绘制/绑定。

## 重绘判断与控件成本

- 先读目标资源目录的desc，再选择可直接表达轮廓的原生图元；不能看到资源编号就假定形状。可复用的单个圆/三角形优于几十条横条模拟同一形状。
- 人物优先轮廓、四方向侧面、头发/衣服和手脚；左右转向不能只移动眼睛。远景/地面以少量大色块为主，战斗主体可比地图角色更精细，按用户预算选择。
- 山用明确三角/多边形结构，纯背景可一块固定色；不要用水平条纹近似纯色或渐变导致伪影。
- 房屋屋顶、墙体、道路使用可辨识的色值/结构，仍与源地块身份对应。多格建筑明确atlasRegion，不按相邻名字推断覆盖范围。
- 一个资产优先一个根容器；确实需要独立动画/旋转的部件才加子容器，不为每个三角形增加一层空模板。
- 先后图层保持“后方部件→主体→前方细节”；尾巴/手臂/角/眼睛不能穿过前景。按目标宿主sibling绘制顺序实际截图确认。
- 非等比缩放后的旋转可能改变斜线方向/包围框。确认位置是左上角还是中心、pivot与旋转基准，不用HTML效果推断宿主一致。

## 引用闭包与按需加载

只把工程实际引用的明确资产编进Lua。相邻同材质图块在构建期合并，保持源上/下图层、通行和事件遮挡；美术合并不能改变地图碰撞。运行树应是宿主/场景根 → 地图根 → 块或资产根 → 图元；镜头滚动改地图父节点，角色移动改角色父节点。

只加载当前地图可见区及有限预加载/驻留缓冲；不要因离开一格视野立即销毁，也不要保留所有访问过的地图。形态/动画按需缓存，普通移动不重写静态子图元。用户授权的渐隐/调色可按变化更新少量子控件。

## 必要视觉验收

先显示一页源/目标对应，再实际运行地图/人物转向/战斗主体。检查同一来源身份、方向、图层、透明、尺寸、文字与命中框；不得只审核HTML预览就说官方效果正确。模板替换、库变化才复查相关资产，无需每次重画或导出全图库。
