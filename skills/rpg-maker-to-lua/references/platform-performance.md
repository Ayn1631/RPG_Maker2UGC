# 千星运行接口、UI、音频与性能

## Lua边界

用户目标运行时Lua 5.3。不可用：string.dump、io.*、coroutine.*；os仅time/date/clock/difftime，debug仅traceback，补充math.isnan/math.isinf。模块环境还有项目自己的限制，例如不直接使用math.random/randomseed；不要说成官方禁止。

标准库可能通过宿主__index暴露，`pairs(math)`不一定能枚举math.huge等字段。沿用 `src/build/bundle.lua` 的只读白名单及受限懒读取，不改成遍历一次复制全部，也不放开被禁止成员。

官方/模拟器接口必须分开确认。真实例子：官方文档ClientUIBaseControl使用id，已安装模拟器使用Id；当前公共调度器只在首次宿主绑定时选择这两个已知字段，之后按缓存字段访问。不要把一个模拟器测试当官方接口事实，不使用猜测属性连试掩盖无证据行为。

## 文字

- 文字内容、颜色、层级、根active/visible、clip区域、字号与行高要一起检查。看到背景没字不能先断言没创建文本框。
- fontSize写入原生前必须是整数，遵守目标模板minimumFontSize；不能设置1来强行缩小，曾实际触发字号超限。
- 文本框尺寸必须容纳真实字号和行高。设置项/标题优先增加宽度，必要时在允许范围内缩小字号；正文用布局换行和分页，长选择列表滚动/分页。
- 一个原生文本框最多1000字，本项目按UTF-16单位保守计数并保护UTF-8边界，复用 `src/runtime/ui/text_limit.lua`。中文不能用Lua字节长度代替字符数；完整正文用split/分页，不以clip截断冒充完整显示。
- 默认platform使用宿主字体，源字形不同可接受。精确源字体路线需要明确fontBindings、字体许可与补字范围，控件成本也更高。

## 输入与退出

挂载容器 `script.object.disableKeyEventPassthrough=true`，阻止WASD传到底层3D角色。监听按下与抬起，按住状态驱动持续移动；用逻辑帧重复节奏，不能依赖浏览器的字符自动重复。关闭/失焦/切场景后清理按住状态及原回调监听，避免卡键。

标题页与结束菜单的退出操作发 `R2U_EXIT_GAME`，当前无参数，由接收端处理真正离开关卡。不要在Lua里假定可直接关闭宿主，也不要把返回标题当作退出游戏。

## 音频配置与信号

`audioBindings.bgm/bgs/me/se` 按源音频名精确绑定正整数index。该index是接收端约定的索引，不是源文件顺序，也不是BGM字符串常量。可以在audioBindings.signals中改对应信号名，默认R2U_BGM/R2U_BGS/R2U_ME/R2U_SE。

每条信号依次追加以下7个参数，类型与位置不能变：

| 位置 | 参数 | API类型 | 含义 |
| --- | --- | --- | --- |
| 1 | index | AddInt | 要播放的映射索引；0表示停止 |
| 2 | operation | AddString | play、stop、fade、update、volume |
| 3 | volume | AddFloat | 源音量乘设置音量后的值，范围沿用0..100 |
| 4 | pitch | AddInt | 源音高百分比 |
| 5 | pan | AddInt | 源声像 |
| 6 | seconds | AddFloat | 渐变时长 |
| 7 | position | AddFloat | 续播位置（秒） |

接收端必须按约定解析。信号发出不等于听到声音。保存/恢复BGM记录当前cue及位置，恢复发送play带position，不需要单独名为resume的operation；若目标播放器不能定位，明确记录这种替代差异。进入/离开战斗要检查地图BGM/BGS的恢复，不能只有停止。

客户端SE配置形式为 `audioBindings.se[sourceName]={index=实际索引,audioId=实际千星音效ID}`。uiFeedback可直接指定cursor/ok/cancel/buzzer的audioId。当前平台适配使用PlayAudio2D、IsAudioAlive、StopAudio；正音量播放路径未传入完整音高/声像参数，不能声称已精确复刻源SE混音。目标ID应从真实资源目录desc与授权范围选择，不复制旧示例值假装目标已有。

## 控件预算与所有权

公共 `ui_lifecycle` 提供即时逻辑句柄，真正宿主创建/销毁只能在同一个OnUpdate预算中flush：创建≤400、销毁≤400，所有界面合计，重复flush不清零。模板内置后代计数；不能一次删父容器间接销毁几千个控件。

未创建请求过时直接取消；退场先隐藏最高父容器一次，再按子先父后排队回收。保留正在使用或合理缓冲中的控件，不无休止缓存所有历史场景。400是本项目规定，不是已测得的官方安全上限；属性写次数也需减少，不因创建达标就忽略数千次SetPosition/SetColor。

预算边界：原子模板结构须与编译目录一致，不能在克隆前动态猜后代数。编辑器强制销毁脚本根树、其他脚本分配由其自身/引擎管理；该Lua无法接管。发现外部模板改大应更正目录/拆模板，不靠伪造count保持“通过”。

## 地图与资源性能

当前地图另有更低的每次更新8组/96地形控件限制，见实际 `map_view.lua`。地图仅当前可见区与有限缓冲驻留；合并在构建期做，移动改父容器，静态图元不逐帧重写。背景在最底层常驻一个黑色图片，不随地图反复创建。

检查热点先区分：宿主创建/销毁、属性写、读取原生树、静态表深拷贝、规则重算。纯移动不重新遍历全图，缓存维护不能每帧GetChildren扫描全部控件。人物转向/步态按需切已创建父组，不能每次重建全部帧。

## 逻辑超时不是只能加帧预算

控件限额不限制某条事件内部的纯Lua计算。若“Lua execution took too long”落在技能/物品/属性链：先查源循环上界、转换后的调用次数和无用视图计算。优先减少总工作；确需分帧的事件用可恢复协议，不能擅自把事件当完成、放大宿主超时或关闭守卫。

性能记录必须写实际环境、构建、样本范围和单位。模拟器wall time、计数宿主的调用数、官方FPS是不同测量，不互相替代。
