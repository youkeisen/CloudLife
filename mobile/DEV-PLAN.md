# MyDay 手机版 开发计划

每完成一个阶段就补该阶段的测试并跑通，再进下一个阶段。测试用 `flutter test`（无需真机）。
**git 提交由凯森自己手动做**，我只汇报改了什么。

## 代码放哪（2026-09-19 凯森定的）

手机版源码放在 **CloudLife 仓库的 `mobile/` 子目录**里，也就是
**`D:\App\MyDay\mobile`**——`D:\App\MyDay` 就是 CloudLife 的工作目录（根目录是电脑版）。

- 一个仓库两个平台：根目录 = 电脑版（Python + 网页），`mobile/` = 手机版（Flutter）。
- 手机版的 APK 也在这个仓库的 Releases 里发布，和电脑版在同一个 GitHub 项目下。
- 安卓打包产物（`build/`、`.dart_tool/`、`.idea/`、`.iml`、`android/local.properties`）
  都被 `mobile/.gitignore` 和 `mobile/android/.gitignore` 排除掉了，只会提交源码。

## 运行约定（本机）

```powershell
$env:no_proxy='127.0.0.1,localhost'   # 必须！否则 flutter test 连不上本地测试进程
Set-Location D:\App\MyDay\mobile
& 'D:\dev\flutter\bin\flutter.bat' analyze
& 'D:\dev\flutter\bin\flutter.bat' test
& 'D:\dev\flutter\bin\flutter.bat' build apk --release   # 出包，产物在 build\app\outputs\flutter-apk\
```

环境：Flutter 3.47.4 / Dart 3.13.3（`D:\dev\flutter`）、Android SDK `D:\dev\Android\sdk`、
JDK 21、Gradle 9.3.1。包名 `com.youkeisen.my_day_phone`。

## 发布流程（2026-09-19 16:50 起改：GitHub 上传由小凯负责）

**版本号规则（凯森 2026-09-19 定）**：三段式 主.次.修订，起步 1.0.0。
修 bug → 修订 +1；加功能 → 次 +1 且修订清 0；主版本由凯森决定。
pubspec.yaml 写成 `主.次.修订+构建号`，构建号每出一个安装包 +1。

1. 改 pubspec.yaml 的 `version:`（比如修 bug 后 `1.0.1+2`、加功能后 `1.1.0+3`）；
2. `flutter analyze` + `flutter test` 全绿后 `flutter build apk --release`，
   产物拷到 `D:\App\apk\MyDay-手机版-vX.Y.Z.apk`；
3. 小凯提交并推送（commit 信息里写清版本与改动）；
4. 小凯用 GitHub API 发 Release：tag `mobile-vX.Y.Z`、标题=版本名、描述=更新内容、
   附件传 APK（令牌走 git credential fill，不落盘不进日志）；
   **现在用 `py -3 tools/release.py <tag> --title "CloudLife vX.Y.Z" --notes-file <md> --apk <路径>`**，
   踩过的三个坑（都已修在脚本里）：
   - **asset 名不能用中文**：中文放进 URL 会让 urllib 用 ascii 编码报
     `UnicodeEncodeError`。脚本默认按 `MyDay-vX.Y.Z.apk` 命名。
   - **传附件必须走 `uploads.github.com`**（用 release 对象里的 `upload_url`），
     打 `api.github.com/.../assets` 是 404。
   - **别传 `target_commitish` 短 SHA**，GitHub 会回 422
     （`tag_name is not a valid tag` + `invalid target_commitish`）。
     不传，让它用默认分支 HEAD。
   - 补传附件（release 已建但没传上）加 `--upload-only`。
5. 凯森在手机上下载安装（覆盖装数据保留）。

## 依赖（尽量少）

| 包 | 用途 | 阶段 |
| --- | --- | --- |
| `path_provider` | 拿手机应用私有目录，存四份 JSON | M1 |
| `archive` | zip 读写：备份导出/导入、xlsx 解压 | M1 / M7 |
| `file_picker` | 让用户选 zip / xlsx 文件 | M7 |

天气用 `dart:io` 的 `HttpClient`，不引额外网络包。日期时间用 `intl` 可视需要再加。

## 阶段划分

### M0 骨架与工具链（已完成）
- `flutter create --platforms android`，项目名 `my_day_phone`，包名 `com.youkeisen.my_day_phone`。
- 空模板 `flutter analyze` 无问题、`flutter test` 通过。
- 记下 `no_proxy` 这个坑。模板自带的计数器 widget test 已删掉（那是模板 demo 的，不属于 MyDay）。

### 打包链路已验证（2026-09-19，属于 M0 的延伸）
出包成功：`build\app\outputs\flutter-apk\app-release.apk`，42.6 MB，里面
`classes.dex`、`AndroidManifest.xml`、`resources.arsc`、
`lib/{arm64-v8a,armeabi-v7a,x86_64}/{libapp.so,libflutter.so,libdartjni.so}`、
`assets/flutter_assets/*` 都在，是个正常可装的 Flutter 包。

这一轮顺带自动装上的 SDK 组件（**只装一次，以后构建不再花这时间**）：
- NDK `28.2.13676358`（r28c，2.1 GB 下载 / 解压后一两 GB）
- Build-Tools `36.0.0`、Platform `android-35`、CMake `3.22.1`

两个坑记一下：
1. `llvm-strip ... Permission denied`（裁剪原生库时的警告）**不是致命错误**，
   构建照样成功出包，别被它吓到。
2. 判断成功一律看「有没有 APK 文件 + 日志里有没有 BUILD FAILED」，
   后台任务的退出码不可信（PowerShell 的退出码不代表构建结果）。

### M1 数据层（已完成）
- `lib/models.dart`：Settings / Period / City / Place / Lesson / Courses / Note / NoteItem /
  Notes / WeatherCache。字段名与电脑版**逐字对齐**；每个模型带一个 `extra`，
  把 JSON 里认不出来的字段原样留着写回去——这样两边任何一边先加了新字段，
  另一边读写一圈也不会把它吃掉（有专门的测试守这条）。
- `lib/week.dart`：`weekOf` / `mondayOf` / `datesOfWeek` / `daysBetween`，
  算法照抄电脑版（用 UTC 算天数差，避开夏令时误差；`2026-02-30` 这种日期挡掉）。
- `lib/store.dart`：四份 JSON 的读写、**原子写**（先写 `.tmp` 再改名）、
  坏文件改名 `.corrupt-<时间戳>` 留存 + 回落默认值 + 记警告、`newId`、`nowIso`。
  用同步文件读写（文件都是几 KB，简单好测），目录由外部注入，方便测试给临时目录。
- 测试：`test/models_test.dart`（默认值键名、序列化往返、未知字段保留、类型错不崩）、
  `test/store_test.dart`（自愈、原子写、按周存取、排序、缓存）、`test/week_test.dart`（跨月跨年、来回算）。
  **共 51 个测试，`flutter analyze` 无问题。**

### M2 界面骨架（已完成）
- `lib/main.dart` 换掉计数器 demo：`path_provider` 拿应用私有目录 →
  `Store(Directory(docs/MyDay))` + `init()` → 启动 `MyDayApp`。
- `lib/app.dart`：MaterialApp + 深浅两套主题（主色跟电脑版一致 #4B5BF7 / #7B86FF，跟随系统）。
- `lib/ui/home_shell.dart`：底部五 Tab（首页/课程/天气/备忘录/设置）+ 顶栏标题
  和「第几教学周」圆牌（没设置时灰字提示）。
- `lib/ui/pages.dart`：五个页面的占位空态（M3 起逐个替换成真页面）。
- 测试：`test/app_test.dart`（5 个用例）——默认落在首页、教学周圆牌两种状态、
  五个 Tab 依次切换、深浅色主题都能构建。**全部 56 个测试通过，analyze 无问题。**
- 踩坑：Flutter 的 `TestPlatformDispatcher` 没有 `platformBrightnessOverride`
  （版本 API 变了），深色模式的测试改成直接单测主题构建函数。

### M3 课程模块（已完成 2026-09-19 凌晨，自动驾驶第 1 轮）
- 新增 `lib/courses_logic.dart`（纯逻辑，不碰界面）：星期列顺序 `dayOrder`
  （weekStartsOn=7 时周日排最前，与电脑版一致）、周次日期范围 `weekRangeText`
  （M月D日 - M月D日，没设第 1 周周一时提示）、节次文案 `timeRange`/`periodLabel`、
  整周复制 `copyWeek`（**overwrite / merge / empty-only 三种策略逐字对齐电脑版
  `store.py` 的 `copy_week`**：目标==来源跳过、复制课全部换新 id、extra/颜色带过去、
  空周保留键）、课程名校验（报错文案与电脑版一致：「课程名不能为空」）。
- 新增 `lib/ui/courses_page.dart` 替换占位页：周次下拉（1-20）+「回到今天」、
  周次日期范围与「本周 N 节课」统计、课表网格（节次列 × 星期列，横向可滚动，
  跨节次的课块占多格高度、被盖住的格子不渲染）、点课块编辑 / 点空格新增
  （星期、开始节次、跨到哪一节、地点、老师、备注，空名拦下不关面板）、
  整周复制面板（1-20 周多选、默认选下一周、三种策略）、清空本周（二次确认）、
  没节次时的引导空态（文案对齐电脑版）。
- 今天列高亮：当前教学周 + 星期几都对上才亮（用的还是电脑版同款 weekOf 算法）。
- 测试：`test/courses_logic_test.dart`（14 个：星期顺序两种、周次范围含跨月、
  节次文案、复制三策略 + 跳过自身 + 空来源周 + extra 保留、课程名校验）、
  `test/courses_page_test.dart`（11 个：渲染含跨节次跳格、改名保存、空名拦截、
  删除、清空本周键保留、整周复制默认下一周、周次切换、回到今天两种状态、
  没节次引导）。app_test 的课程 Tab 断言同步改成真页面（添加课程按钮）。
- **共 81 个测试全部通过，`flutter analyze` 无问题。**
- 踩坑：① Flutter 3.47 里 DropdownButtonFormField 的 `value` 参数废弃了，
  要用 `initialValue`；② 下拉框放在 Row 里且菜单文案长时，必须 `isExpanded: true`
  否则横向溢出 4.5px（测试里算渲染错误）；③ StatefulBuilder 里 Builder 重新执行
  会重置局部变量，错误提示状态要放在 builder 外面闭包捕获。

### M4 备忘录（已完成 2026-09-19 早上，自动驾驶第 2 轮）
- 新增 `lib/notes_logic.dart`（纯逻辑，行为基准是电脑版 `app.js` 的
  `noteGroupsHtml` / `filteredNotes` / `noteSubLine`）：分组统计（全部=未归档、
  置顶、各标签按首次出现序、归档，标签数只算未归档的）、分组过滤 + 搜索
  （标题/正文/清单项全文，大小写不敏感，先分组后搜索，认不出的分组键兜底返回全部）、
  标签解析（逗号/中文逗号/顿号切分，去空白，不合并重复）、列表副标题
  （类型 · 标签 · 摘要，笔记摘要取正文第一行截 20 字，没标签不写「未分类」）。
- 新增 `lib/ui/notes_page.dart` 替换占位页，含列表页 + 编辑页两个界面：
  - 列表：搜索框 + 「新建备忘录」按钮 + 横向滑动的分组 chips（带计数）+ 卡片列表
    （置顶 ★ 前缀、副标题），排序沿用 Store 的 sortedNotes（置顶在前、改过的在前）；
    空态「这里还没有东西」/ 无结果「没有符合条件的内容」两套文案。
  - 编辑页：标题、标签（按逗号顿号切分实时保存）、类型下拉（笔记/清单，
    切成清单时一条都没有就先给一行空的并立即保存——对齐电脑版）、
    笔记正文多行输入 / 清单每行 checkbox + 文本 + 删除行 + 「加一行」、
    底部状态字「已保存 / 有改动…」、置顶/归档/删除（二次确认「删除后不可恢复。」）。
  - 保存机制：500ms 防抖自动保存 + 保存键立即落盘 + **PopScope 在返回键按下时补存**。
- 测试：`test/notes_logic_test.dart`（19 个：分组四种、过滤、搜索含大小写和归档隔离、
  标签解析、副标题与摘要截断）、`test/notes_page_test.dart`（12 个：空态与新建、
  列表星标与副标题、分组切换、搜索、防抖自动保存、切走前补存、标签落盘、正文落盘、
  清单切换/输入/勾选/加行/删行、置顶归档进归档分组、删除二次确认、保存键立即落盘），
  全部直接读临时目录里的 notes.json 验证落盘。app_test 的备忘录 Tab 断言同步改成真页面。
- **共 112 个测试全部通过，`flutter analyze` 无问题。**
- 踩坑：① 标题输入框的 onChanged 别写成只标 dirty 不写值，保存出去的就是旧数据；
  ② dispose 在路由转场结束才跑，那时列表页已经重读过了——「切走前补存」要用
  PopScope 的 onPopInvokedWithResult（pop 一触发就同步补存），不能指望 dispose；
  ③ 同一文件的多个编辑别并行发，会互相覆盖（这轮有两个编辑被吞了，靠 analyze 兜回来）；
  ④ 3.47 里 `(_, __)` 会报 unnecessary_underscores，直接 `(_, _)`；
  ⑤ 测试里 DropdownButtonFormField 用 initialValue（M3 已踩过，这次没再犯）。
- 未跑 APK 打包（慢，偶尔验证一次即可；M0 已验证过链路）。

### M5 天气（已完成 2026-09-19 上午，自动驾驶第 3 轮）
- 新增 `lib/weather_logic.dart`（纯逻辑，不碰网络不碰界面，行为逐字对齐电脑版
  `weather.py` / `server.py` / `store.py`）：WMO 码中文映射（28 条 + 兜底「未知天气」）、
  16 方位风向、Open-Meteo URL 拼法（current/hourly/daily 参数与电脑版一致）、
  归一化 `normalize`（24 小时窗口从当前小时起、能见度米→公里、payload 结构
  city/current/hourly/daily/tips 与电脑版一致，缓存里的 payload 两边能互读）、
  生活提示（昼夜温差≥8、降水概率≥50 取「未来 6 小时与今日最大」、紫外线≥6）、
  缓存决策（同城市 + 未过期才用缓存；refreshMinutes=0 永不过期；联网失败时同城市
  旧缓存顶上并标旧数据）、我的地点增删切换（normalizePlace 校验文案与电脑版一致、
  坐标收 4 位小数、1e-4 阈值去重只改名、上限 20、删当前城市顺位到第一个）。
- 新增 `lib/weather_api.dart`：`dart:io` HttpClient（不引网络包），8 秒超时，
  非 200 / 坏 JSON / 连不上一律包成 `WeatherApiException`；forecastBase/geoBase
  可注入，测试指到本地假服务器，不打真网。
- 新增 `lib/ui/weather_page.dart` 替换占位页：城市搜索框（geocoding，language=zh、
  count=8）→ 结果列表 → 点选即加进「我的地点」并设为当前城市 + 强制刷新；
  实况卡（大字温度、天气文案 · 城市名、提示 chip 或「暂无特别提示」、体感/湿度/风/
  气压/能见度/降水概率/今日最高/今日最低，空值显示「—」）；未来 24 小时温度柱状条
  （高度公式同电脑版）；未来 7 天（周X 日期 + 最低/最高）；我的地点区块（当前城市
  打勾、点切换、可删）。状态机：没城市给引导空态「先选一个城市」（文案对齐电脑版）/
  加载中 / 取数失败「暂时取不到天气」/ 旧数据标注，时间戳行「更新于 HH:MM（旧数据，
  网络不可用）· 数据源 Open-Meteo」。
- `home_shell.dart` 换真页面；`app_test.dart` 的天气 Tab 断言同步改成真页面断言。
- 测试：`test/weather_logic_test.dart`（24 个：WMO 两种、风向、round1、两种 URL、
  归一化全字段 + 空返回 + 全未来小时、提示阈值边界 8/50/6、缓存年龄与新鲜判定六种、
  地点校验/新增/去重/上限/切换/删除四种情况）、`test/weather_api_test.dart`
  （7 个：本地 HttpServer 假 Open-Meteo，验请求参数、端到端归一化、搜索解析、
  空 results、非 200、坏 JSON、连不上）、`test/weather_page_test.dart`（10 个：
  未选城市不联网、联网成功写缓存、缓存新鲜不联网、过期缓存降级标旧数据、失败空态、
  刷新强制联网、搜索→选中→加地点+自动刷新、切换地点、删当前顺位/删光回未选城市、
  整页渲染）。测试全部用虚构城市（示例市/甲城/乙城/测试城），零真实数据。
- **共 158 个测试全部通过，`flutter analyze` 无问题。**
- 踩坑：① `WeatherApi` 一开始没把注入的 baseUrl 真正用上（fetch 里直写了真实常量
  地址），本地假服务器根本没被访问、测试全打到真 Open-Meteo 还拿回了真实天气——
  注入的 base 必须参与拼 URL；② 同一文件的多条编辑并行发会被吞、只有最后一条生效
  （M4 踩过又犯了一次），**必须逐条串行改**；③ 测试里 ListView 底部内容命中不了，
  与其折腾 scrollUntilVisible（在嵌套滚动里会「No element」），不如把测试视口直接
  拉成 1080x2600 逻辑像素一屏渲染完；④ SnackBar 换条（hideCurrent+show）要等前一条
  退出动画放完，测试里先 pump 600ms 再断言；⑤「切地点后刷新次数」这类断言别忘了
  初始加载那次也计费。
- 未跑 APK 打包（M0 验证过链路，M9 再出包）。git 未提交（凯森手动）。

### M6 首页聚合（已完成 2026-09-19 上午，自动驾驶第 4 轮）
- 新增 `lib/home_logic.dart`（纯逻辑，行为逐字对齐电脑版 `server.py` 的
  `api_home` / `compute_lesson_states` / `greeting_of` / `_minutes`）：
  问候语五段（<6 还没睡 / <11 早上好 / <14 中午好 / <18 下午好 / 晚上好）、
  星期几中文名、`HH:MM`→分钟数（带秒也认）、`strip(' -')` 等价物、
  今日课程状态机（upcoming/now/done/unknown；用 spanEnd 的结束时间；
  结束早于开始按跨零点 +24h；节次缺失或没设时间 → unknown 且排最后；
  排序 = begin 空排尾 → begin → 节次顺序 → 原始序（模拟 Python 稳定排序）；
  「下一节」只标第一个 upcoming）、备忘录速览（未归档、最多 3 条、置顶在前、
  改过的在前；清单摘要永远给「x/y 项完成」含 0 项、笔记摘要取正文第一行截 24 字；
  清单只摊前 6 项记 moreItems；正文 trim 后截 200 字标 bodyCut；空标题给「无标题」）、
  `toggleNoteItem` 只翻转指定一条清单项并更新 updatedAt（**绝不整段回写 items**，
  防止把没显示出来的第 7 项之后冲掉——电脑版为此专门做过 /api/notes/toggle）。
- 新增 `lib/ui/home_page.dart` 替换占位页：
  - 问候行 + 日期行（今天 · 周X · 第 N 教学周 / 教学周未设置 · 校区 · 学期名）+
    「第 N 周 / 未设置教学周」和「今日 N 节课」两个 chip。
  - 今日课程卡：三种空态（还没有任何节次 / 还不知道今天是第几周 / 今天没课·休息一下，
    文案对齐电脑版）+ 课行（节次名 + 起止时间在左，课名 + 「正在上」/「下一节」徽标，
    地点 · 老师在右；已上完的课划线变灰）。
  - 今日天气卡：状态机与天气页同款（没城市不联网 / 缓存新鲜直接用 / 过期联网 /
    失败降级旧缓存标「网络不可用，显示的是 MM-DD HH:MM 的数据」/ 失败无缓存空态），
    紧凑版只留大字温度、天气 · 城市、体感/湿度/风/最低最高。
  - 备忘录速览卡：空态「还没有备忘录 · 想到什么随手记一条」+ 卡片式条目
    （置顶标、标题、小三角收放默认展开、右侧摘要、标签或类型 chip、
    正文最多 4 行、清单项带勾选框可点、空的项显示「（没写内容）」、
    「… 还有 N 项」）；点清单项立刻落盘（只翻单条），点笔记行跳备忘录 Tab
    并直接打开那条（HomeShell 的 `_openNoteFromHome`）。
- `pages.dart` 删掉首页占位（剩设置页占位等 M7）；`app_test.dart` 首页断言改成真页面
  （三个空态文案）。
- 测试：`test/home_logic_test.dart`（20 个：问候边界、时间换算、strip 等价、
  状态三态 + 下一节 + 跨节次 + 跨零点 + unknown 排序 + 半截时间文案 + 节次名原文、
  速览上限/置顶排序/两种摘要/6 项截断/200 字截断/标签、勾选翻单条保尾巴 + 越界 + 翻回）、
  `test/home_page_test.dart`（11 个：空数据三空态且不联网、课行 + 下一节徽标
  （时间相对当前钟点构造并夹回当天边界，避免清晨深夜跑挂）、没设教学周空态、
  天气成功写缓存 / 缓存新鲜不联网 / 失败空态 / 失败降级旧数据标注、
  速览 3 条上限与置顶、点清单项落盘且第 7 项之后保留、小三角收放、点笔记行回调带 id）。
- **共 189 个测试全部通过，`flutter analyze` 无问题。**
- 踩坑：① 测试里构造「一节已上完一节还没到」别写死钟点——用相对当前时刻 ±小时并夹回
  当天边界（00:00-02:00 / 22:00-24:00 跑也不挂）；② 逻辑测试里自己把 08:20 时 p3
  想成了 done（实际是 upcoming），状态断言要先按钟点推一遍再写；
  ③ 缓存测试要存 `normalize()` 之后的 payload（天气页实际缓存的就是归一化结果），
  别直接存 raw；④ Git Bash 跑 flutter 没问题（no_proxy 照设），但工作目录每条命令都会
  重置回工作区，`cd` 要和命令写在一起。
- 未跑 APK 打包（M0 验证过链路，M9 再出包）。git 未提交（凯森手动）。

### M6 首页聚合（原计划条目）
- 今日课程（状态：已上/正在上/下一节）、今日天气、备忘录速览（可勾 + 可收放）。

### M7 设置与数据（已完成 2026-09-19 中午，自动驾驶第 5 轮）
- 新增 `lib/backup.dart`（纯逻辑，**逐字对齐电脑版 `app/backup.py`**）：
  zip 里是 manifest.json + settings/courses/notes/weather_cache 四份 JSON（无目录层级）；
  manifest 为 `{app: MyDay, version: 1, exportedAt, files}`；zip 名
  `MyDay-backup-YYYYMMDD-HHMM.zip`；exportedAt 用本地时区（`Store.isoOf`，
  格式同电脑版 isoformat）；缺的数据文件按电脑版写 `{}` 占位。
  校验失败的文案与电脑版一字不差（「不是有效的备份文件」「备份文件缺少 manifest.json」
  「manifest 读不出来」「备份缺少数据文件：a、b」（顿号连接）「xx 解析失败」「xx 内容不是 JSON 对象」）；
  **先全部校验、后一次性写盘**，半套还原不可能发生；`safetyBackup` 还原/清空前自动留一份；
  `resetAllData` 四份文件写回默认（调用方先备份，同电脑版 api_reset_all）。
  `Store` 补了 `isoOf(DateTime)`（nowIso 拆出来的可传时刻版本）。
- 新增依赖：`archive ^3.6.1`（zip 打包解析）、`file_picker ^8.1.2`（选 zip；
  测试通过注入 `pickZip` 函数完全绕开，不碰平台通道）。
- 新增 `lib/ui/settings_page.dart` 替换占位页，四块卡片文案对齐电脑版：
  - 基本：称呼 / 学期名 / 第 1 周周一日期（showDatePicker）/ 每周起始日（周一/周日）/
    校区 / 外观（跟随系统/浅色/深色）。**每处改动立即落盘**。
  - 天气：我的地点（当前 ✓、「切换」、× 移除，复用 M5 的 addPlace/selectPlace/removePlace）、
    ＋添加地点（就地展开搜索，WeatherApi 可注入假接口）、自动刷新（10 分钟/30 分钟/
    1 小时/仅手动）。
  - 作息与节次：每行 名称+开始+结束+×，空名允许（对齐电脑版），「+ 添加节次」一次加一条。
  - 数据：立即备份（zip 落到 `<数据目录>/backups/`，本机留一份）、从备份还原
    （选 zip → 校验 → 确认对话框 → 自动备份当前 → 覆盖 → 整页重读）、
    清空全部数据（对话框**必须输入「清空」两个字**，输错只提示不清；确认后先备份再清空，
    文案对齐电脑版）。
- 外观联动：`MyDayApp` 改为 StatefulWidget，设置页通过 `onChanged` 回调逐层
  （SettingsPage → HomeShell → MyDayApp）通知重读 settings.theme 重建 MaterialApp，
  切深色立刻生效；`themeModeFromSetting('system'|'light'|'dark')` 对齐电脑版取值。
- `pages.dart` 整个删除（最后一个占位页消化完）；`home_shell.dart` 改接真设置页。
- 测试：`test/backup_test.dart`（17 个：zip 名/manifest 字段与 files 顺序/打包内容/
  缺文件 {} 占位/落盘路径/合法校验/四类坏备份文案逐字断言/还原覆盖与空周回来/
  非 JSON 对象拒绝且不做半套修改/安全备份/往返一致/resetAllData 回默认/
  **手工按电脑版 backup.py 布局拼的 zip 直接还原互通**）、
  `test/settings_page_test.dart`（20 个：四区块渲染、称呼/学期名/校区落盘、日期选择器、
  起始日、外观落盘+整 App 变深色、自动刷新、节次增删改与 id 不重复、地点切换/删除顺位/
  搜索添加、立即备份落盘、还原覆盖+取消+坏 zip 文案、清空输错不清+输对清+先备份）。
  app_test 设置 Tab 断言改真页面，并启用了 M2 搁置的「改第 1 周周一顶栏跟上」用例。
- **共 226 个测试全部通过，`flutter analyze` 无问题。**
- 踩坑：① 页面里改完数据忘了 setState，界面不重画导致两个测试挂（电脑版会整块重画，
  Flutter 要显式刷）；② 测试辅助函数把 `settings.json` 当文件名传给了 `Store.read`
  （它收的是不带扩展名的名字）；③ 当前地点的「切换」按钮是**存在但禁用**，
  不是不存在，断言要查 `onPressed == null`；④ 卡片容器（DecoratedBox 带底色）里放
  ListTile 会被测试框架直接断言报错（墨水效果会被盖住），换成 InkWell 行；
  ⑤ `textContaining('教学周')` 太宽——设置页说明文字里也有这四个字，断言要收紧到具体 key。
- 未跑 APK 打包（M0 验证过链路，M9 再出包）。git 未提交（凯森手动）。

### M7 设置与数据（原计划条目）
- 基本设置、作息与节次、我的地点、外观。
- 备份导出 zip / 从备份导入 / 清空（强制先备份 + 二次确认）。
- **兼容电脑版备份**：字段名一致，能直接吃电脑版导出的 zip。

### M8 导入课表 xlsx（已完成 2026-09-19 下午）
- `lib/timetable.dart`：电脑版 `timetable.py` 的逐条移植——xlsx 解压（archive 包）+
  工作表 XML 解析（xml 包）、共享字符串、合并单元格（covered/resolved/spanEnd 三件套）、
  表头识别（节次列 + 星期列同行）、「课程名(考核)(类别)班级{周次 老师 教室}」拆分、
  周次区间/列表/单双周、一格多门课（换行分隔）、没写周次的跳过并给警告。
  解析规则和电脑版一致，同一个文件两边解析结果一样。
- `lib/import_logic.dart`：`buildImportPlan`（预览，不落盘）、`ensurePeriods`
  （同名节次复用，缺的补建、时间留空）、`applyImport`（导入前 `safetyBackup`，
  merge 追加 / overwrite 覆盖整周）。
- 课程页加了「导入」按钮（file_picker 选 xlsx，测试注入假选择器），
  预览确认框里写清楚会建哪些节次、涉及哪些周，覆盖 / 追加 / 取消三种选择。
- 测试：`timetable_test.dart`（15 个：拆分、周次、合并区去重、一格多门、坏表报错、
  落库与备份）、`import_page_test.dart`（3 个：导入流程、取消、坏文件）。
  **全部 250 个测试通过，analyze 无问题。**
- 另：清掉了 M1 时我自己写进测试样例的真实信息（文昌校区/工程制图/1#303/芜湖），
  换成虚构数据，并加了 `preset_guard_test.dart` 守卫——lib/ 源码里出现禁词（真实学校、
  课程、教室、人名、学号、城市）测试就挂。

### v1.0.1（2026-09-19 13:53）：修「手机上添加不了城市」

真机 bug：城市搜索必失败、天气也取不到。

原因：Flutter 模板只在 debug/profile 清单里有 INTERNET 权限，`flutter run` 调试时一切正常，
**但 release APK 根本没有联网权限**——天气取数、城市搜索全部失败。1.0.0 的包就是这样的。

修复：
1. `android/app/src/main/AndroidManifest.xml` 显式声明 `<uses-permission android:name=
   "android.permission.INTERNET"/>`（顺便把桌面显示名从包名 my_day_phone 改成 MyDay）。
2. 加 `test/packaging_guard_test.dart`：主清单必须含 INTERNET 权限、应用名不能是包名，
   防止再悄悄丢掉。
3. 版本号按规矩：修 bug → 1.0.0+1 升 **1.0.1+2**。

验证：252 个测试全绿，analyze 无问题；重新出包 `D:\App\apk\MyDay-手机版-v1.0.1.apk`。

### v1.1.0（2026-09-19 15:35）：Liquid Glass「液态玻璃」整体换肤

网页版（v1.1.0，APP_VERSION 已升）和手机版同步应用 macOS Tahoe 风格的玻璃质感，
**只换视觉，不动任何结构 / 交互 / 文案**（验收依据：全部既有测试原样通过）。

- 网页版 `app/static/style.css` 末尾追加 Liquid Glass 层：body 彩色渐变底、
  侧边栏/顶栏/卡片/弹窗/按钮/输入框/列表行/标签全部半透明磨砂
  （backdrop-filter blur+saturation）、1px 高光描边（inset box-shadow）、柔和外投影、
  大圆角（12-20px）；遮罩加模糊；深浅色各一套玻璃参数（`--glass*` 变量）。
  顺手修了 test_stage9 的一个测试基建 bug：`r.stdout[-1500:]` 在 stdout 为 None 的
  环境里会 TypeError（assertEqual 的消息是先求值的），改成 `r.stdout or r.stderr or ''`。
  **286 个用例 0 失败 0 错误，冒烟 22/22。**
- 手机版：新增 `lib/ui/glass.dart`（Glass = ClipRRect + BackdropFilter + 渐变染色 +
  高光描边 + 柔影；GlassBackdrop = 页面底下的彩色渐变）；`buildTheme` 全面玻璃化
  （Card/Dialog/Input/NavigationBar/SnackBar 全部半透明大圆角、AppBar 透明）；
  HomeShell 换成 GlassBackdrop 渐变壳 + extendBody（内容从玻璃底栏下滑过）+
  顶栏/底栏真·背景模糊。页面结构与文案零改动。
  **252 个测试全绿，analyze 无问题**（app_test 里「底色不同」的断言按新设计改成
  「壳子透明 + 玻璃染色随主题」）。
- 版本号按规矩：加功能 → 1.0.1 升 **1.1.0**（修订清 0），构建号 +1 → 1.1.0+3；
  网页版 APP_VERSION 同步 1.0.0 → 1.1.0。

### v1.1.1（2026-09-19 16:40）：修「浅色模式进编辑页变黑底」

真机 bug：设置选浅色，点进「编辑清单 / 编辑笔记」整页变黑。

原因：玻璃化把 Scaffold 底色调成透明（颜色靠壳子的渐变背景透出来），但编辑页是
**独立推入的路由**，底下没有壳子的渐变——透明底直接露出路由遮罩的黑。

修复：`notes_page.dart` 的编辑页（含备忘录不存在的兜底分支）自己套一层
`GlassBackdrop` 渐变背景；加回归测试 `editor_backdrop_test.dart`（2 个用例：
浅色/深色进编辑页都必须有背景垫层）。
版本号按规矩：修 bug → 1.1.0 升 **1.1.1+4**。
验证：254 个测试全绿，analyze 无问题。

### v1.1.2（2026-09-19 17:20）：修「城市搜索省份显示错」（阜阳→江苏）

两边共同的 bug：搜「阜阳」加进我的地点，省份显示江苏。
根因在数据源——Open-Meteo 的中文索引不全：`name=阜阳&language=zh` 只返回江苏一个
同名小村（无人口），安徽阜阳市根本不在结果里；`name=阜阳市` 或拼音 Fuyang 才能命中。

修复（网页版同步 1.1.1）：中文输入时补一发带「市」/去「市」的查询，两批结果按坐标
去重（人口多的留下）再按人口从大到小排——真地级市浮上来、同名村沉底；顺带治了
「上海市→伊利诺伊州」这类乱数据。
- 手机版：weather_api.dart 双查询 + mergeCitySuggestions + CitySuggestion 加 population；
  新增 test/city_merge_test.dart（5 用例）。**259 个测试全绿。**
- 版本号按规矩：修 bug → 1.1.1 升 **1.1.2+5**。

### v1.2.0（2026-09-19 17:30）：三个新功能

1. **节次时间改时间选择器**：设置页的开始/结束时间框改成只读 + 点击弹
   `showTimePicker`，不能再手输乱七八糟的内容。`SettingsPage.pickTime` 可注入（测试用）。
2. **定位添加地点**：设置 → 天气 → 「定位添加」按钮。geolocator 拿坐标 +
   Nominatim 反查城市名（`WeatherApi.reverseGeocode`，带 User-Agent），
   走和搜索添加同一套落库。AndroidManifest 加了 ACCESS_COARSE/FINE_LOCATION。
   `SettingsPage.locate` 可注入（测试用）。
3. **课表导入支持 PDF**：新增 `lib/pdf_timetable.dart`（syncfusion_flutter_pdf）。
   教务系统的课表 PDF 是**转置布局**（星期是行、节次是列，1-12 横排在底部），
   解析器会自动识别两种方向。解析分两条路互补：A 按左边缘分桶（名字/周次准），
   B 按「x 区间重叠聚簇」重建格子（场地/教师全），按 (天, 名字, 起始节) 合并。
   课程名解析：标记前取最后一段不含 / : 的文字（甩掉串进来的碎片），去 ★☆。
   导入入口现在同时收 .xlsx 和 .pdf（按 %PDF 魔数分流）；
   `import_logic.planFromParsed` 抽出来共用下游。
   手动验证工具：`tool/pdf_check_test.dart`（设 MYDAY_PDF 环境变量跑，不进测试；
   用凯森的真实课表 PDF 本地验证过：18 门课全部解析，名称/节次/周次正确，
   场地/教师部分有截断——PDF 是启发式解析，导入预览里要人工过一眼）。
   测试：`city_merge_test.dart` 5 个 + `editor_backdrop_test.dart` 2 个 +
   设置页时间选择器用例改造。**259 个测试全绿，analyze 无问题。**
- 版本号按规矩：加功能 → 1.1.2 升 **1.2.0+6**（修订清 0）。

### M9 打包与真机验收（APK 已出，真机验收待凯森）

- `flutter build apk --release` 成功：51.8 MB，产物在
  `build\app\outputs\flutter-apk\app-release.apk`，并拷贝到 **`D:\App\apk\MyDay-手机版-v1.0.0.apk`**。
  校验过 zip 里的 classes.dex、三个架构的 libapp/libdartjni/libflutter、
  flutter_assets、resources.arsc 都在。用 debug 密钥签的名（自己装够用，上架要换正式签名）。
- 排坑记录（都会在下次打包时遇到）：
  1. `file_picker` 的安卓模块按 android-34 编译，而它依赖的 `flutter_plugin_android_lifecycle`
     要求使用方 compileSdk >= 36 → 在 `android/build.gradle.kts` 的 subprojects 里
     afterEvaluate 统一把 compileSdk 抬到 36。**afterEvaluate 必须注册在
     `evaluationDependsOn(":app")` 之前**，否则报「already evaluated」。
  2. 判断打包成功：看日志里 `Built build\app\outputs\flutter-apk\app-release.apk` 且没有
     `BUILD FAILED`，并确认 APK 文件真的在——后台任务的退出码不可信。
  3. `llvm-strip ... Permission denied` 是警告，不拦构建。
- 剩下的就是凯森实机验收：装 APK、按 PRD 第 8 节过一遍（课表、备忘录、天气、
  导入 xlsx、电脑版备份互导）。

### v1.6.1 导入入口说明（需求文档第 2 条）

需求文档第 2 条原本要的是「从相册选课表截图导入」。**验证后否决**（详见下面
「已否决的方案」），改成把现有的 xlsx / PDF 导入入口做清楚：

- 课程页按钮「导入」→「**导入课表**」；
- 点按钮**先弹说明**（`_explainImportFile`，`import-help-go` / `import-help-cancel`）：
  讲清能导 Excel(.xlsx) / PDF、去哪拿（手机浏览器开教务系统导出）、
  并明确写「课表截图导不了」把用户劝回正路；
- 选了不是课表的文件仍有 toast 提示，不崩。

测试：课程页新增 4 个（说明内容、取消不调选择器、确认才调选择器、坏文件不崩），
`import_page_test.dart` 三处点击补上过弹窗（`tapImport` 辅助）。
**291 个测试全绿，analyze 无问题。** 版本 1.6.0+24 → **1.6.1+25**（修订位 +1）。

## 风险

1. **文件选择与存储权限**：安卓 11+ 分区存储，导出备份要落到用户能找到的位置
   （可能要先落到 App 目录再引导用户分享/另存）。M7 里实测。2. **中文字体**：安卓自带字体够用，但要确认表格里「中午1」这类混排不乱。
3. **大课表渲染**：7 列 × 12 行的表格在窄屏上要能横向滚动，字号要压得住。
4. **无真机时**：我只能靠 `flutter test` + `analyze` 保证逻辑正确，界面得凯森实机看。

## 已否决的方案：从相册选课表截图导入（2026-09-20）

需求文档第 2 条的原始想法是「从相册选课表图片，OCR 识别成课表」。**已做可行性
验证并否决**，结论记录在这里，免得以后又想起重做一遍。

做法：接 `google_mlkit_text_recognition`（中文识别，离线），写出
`ocr.dart`（图 → 带坐标文字块）+ `timetable_image.dart`（文字块 → ParsedTimetable
纯函数，17 个单测全过）。

**用凯森真实截图（kebiao-web-20260915.jpg，有表头那张）的真实文字坐标跑验证，
结果不可用：**

| 期望 | 实际 |
| --- | --- |
| 节次 1、2、…、9、中午1、中午2 | 「第2节、第3节、第4节、中午1、**中午25**…」——1 和 5 丢了，中午1/中午2 粘成中午25 |
| 各课落在正确的星期列 | 全挤到周一，多列文字互相串行 |
| 周三的课在周三 | 跨到了周二 |

**根本原因**：教务系统网页版课表用**彩色块**占位，文字贴着块内壁竖排，且课块
**会横跨两列**（如「工程制图」那块红底压着周三周四两列）。OCR 只给文字的坐标，
**不知道彩色块的边界在哪**，所以无法判断一个课块属于哪一天。要硬做得加颜色分割
找色块 + 块级几何，工作量翻几倍，准确率仍无保证，用户还得逐条手工核对。

**替代方案（更稳）**：手机浏览器直接登录教务系统下载课表 xlsx，用现有导入功能
选它即可——手机版的 xlsx / PDF 导入从 M8 起就做好了，入口在课程页右上角。

**如果以后还要试**：唯一可能work的切入点是**按颜色分割**先找出每个彩色课块的
矩形范围，再把块内的文字归给该块——而不是像这次一样从文字坐标反推格子。

