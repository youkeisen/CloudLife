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

## 应用图标（2026-09-20 起用凯森给的 Cloud logo）

图标**不是手改的，由脚本从原图生成**——重跑脚本会覆盖 `mipmap-*/ic_launcher*.png`，
所以不要手改那些文件。

- 原图：凯森给的 `D:\下载\Image_1789890840834_943.jpg`（500×350，深灰底
  (34,34,34) + 白色线条倒三角 logo，三角上方一行小字 CLOUD）。
  这个路径是外部的，将来重跑前先确认文件还在（或在 DEV-PLAN 里留一份说明）。
- `py -3 tools/make_app_icon.py`：裁正方形（去掉左右空白，以 logo 中心为圆心）
  → 生成 5 个密度的 `mipmap-*/ic_launcher.png` + `ic_launcher_round.png`（圆版）。
- `py -3 tools/make_adaptive_icon.py`：生成 Android 8+ 的**自适应图标**
  （`mipmap-anydpi-v26/ic_launcher.xml` + `drawable/ic_launcher_foreground.png`
  + `values/ic_launcher_background.xml`）。**Android 8+ 优先用这一套**，
  比位图那套显示得更好（系统自己裁形状，边缘干净）。

两个脚本都做了同一件事：**按 logo 的实际白像素边界自动定位中心**，再按比例
留安全边距。这里的关键取舍：
- 位图那套（老系统）留 56%——圆角裁切下小字不贴边；
- 自适应那套留 52%——自适应图标的「安全区」官方规范是 66%，
  但国产 ROM 的圆形桌面会裁到接近外接圆，收到 52% 才舒服。
- **别把这两个比例调大**：logo 会顶到圆形边缘被切。改完一定要用
  「圆形 / squircle / 圆角方」三种 mask 预览一遍再打包。

`AndroidManifest.xml` 里 `android:icon` 指 `@mipmap/ic_launcher`、
`android:roundIcon` 指 `@mipmap/ic_launcher_round`。

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

### v1.7.0 记账模块（需求文档第 3 条，2026-09-20）

需求文档第 3 条。设计稿（桌面文档内嵌的 image2，v2.1）给了四个区域：
记账主页 / 记一笔 / 分类管理底部弹层 / 数据结构（原稿是 SQLite 两张表）。
**配色按凯森要求沿用 CloudLife 现有浅色风格**，不照抄设计稿的深色稿。

数据层：
- `models.dart` 加 `LedgerCategory` / `LedgerRecord` / `Ledger`，字段名照设计稿的
  `categories(id,name,icon,sort)` / `records(id,amount,category_id,date,note,created_at)`，
  只是把 SQLite 的 id 换成字符串 id；照惯例带 `extra`（认不出的字段原样保留）。
- **金额一律存正数**，方向归 `kind`（expense / income）；`signed` getter 处符号。
  这样改方向不用改金额，也躲开「负负得正」的算术坑。读坏数据时负数会被 `.abs()` 掰正。
- `ledger.json` **故意不进 `Store.fileNames`**：那四份是和电脑版严格对齐的，
  记账是手机版独有。查过电脑版 `app/backup.py` 的 `restore_bytes` 只读那四份、
  多余文件忽略 → 所以把 ledger 作为**可选文件**打进 zip 是安全的。
- `backupOptionalFiles`：备份时「有就带上」（不能写 `{}` 占位），
  还原时「备份里确实有才覆盖」——否则电脑版备份导进来会把账本清空。
- `ensureLedgerSeed()` 用 `Ledger.extra['catsSeeded']` 当**种过标记**，
  而不是判断「列表是否为空」：用户可能主动把分类删光，那时不该又冒出默认分类。

纯逻辑（`ledger_logic.dart`，全部可单测）：
`monthKeyOf` / `dateKeyOf` / `parseDateKey`（拦 2 月 31 这类）、`shiftMonth`、
`formatAmount`（按分四舍五入 + 千分位）、`summarizeMonth` / `maxExpenseOf`、
`groupByDay`（日期倒序、组内 createdAt 倒序）、`dayLabel` / `monthLabel`、
`validateCategoryName` / `validateAmount`、`sortedCategories`、`recordCountOf`、`findCategory`。
**日均按「有记账的天数」算**，不是自然月天数——月中才开始记账时日均不会虚低。

界面：`ledger_page.dart`（主页）/ `ledger_edit_page.dart`（记一笔）/ 
`ledger_categories_sheet.dart`（分类管理弹层），入口挂在「功能」页 `feat-ledger`。
- 金额输入用**字符串缓存**：存 double 的话「32.」这种中间状态会丢掉小数点，没法继续敲。
- 自带数字键盘（对齐设计稿布局），数字区与功能区各占一侧。
- 单位金额按分四舍五入 `(v * 100).round() / 100`，规避 `0.1 + 0.2` 的浮点尾巴。
- 删分类**不连带删账**：那些账的 `categoryId` 指向不到了，界面按 `findCategory`
  返回 null 显示成「未分类」，金额和日期都还在。删之前会提示「还有 N 笔账」。

**这轮修掉的一个真实缺陷**：原先主页只在编辑页返回 `true`（保存过）时才刷新，
于是「在编辑页进分类管理改了名字 / 删了分类 → 按返回键退出」之后，
主页的流水还挂着已经删掉的名字。改成**从编辑页回来就无条件重读数据**
（几毫秒的事），并补了回归测试
「在编辑页改了分类名，直接按返回键退出，主页也要跟着变」。

测试：`ledger_logic_test.dart` 40 例、`store_test.dart` 新增 8 例、
`backup_test.dart` 新增 5 例、`ledger_page_test.dart` 17 例。
**359 个测试全绿，analyze 无问题。** 版本 1.6.1+25 → **1.7.0+26**
（加功能 → 次位 +1、修订位清 0，构建号 +1）。

### v1.7.2 修「进记账界面整屏变黑」（凯森 2026-09-20 反馈）

凯森发了两张截图：主页是正常的白底，一进「记一笔」就整屏全黑。
要求顺带**排查其他所有界面**有没有同样的问题。

根因和 v1.1.1 那次**是同一个坑**：`buildTheme()` 里
`scaffoldBackgroundColor: Colors.transparent`，配合 Liquid Glass 的
`GlassBackdrop` 垫层；而**独立整页（自己 push 成一条新路由的页面）底下没有壳子的
渐变背景，必须自己垫一层**，否则透明的 Scaffold 直接透出 `Navigator` 的路由遮罩黑底。
- `NoteEditPage`（备忘录）当年踩过，页面内部自己套了 `GlassBackdrop` —— OK
- `FeaturesPage._open` 是统一「外面套一层」的写法，走它的页面 —— OK
- **`LedgerEditPage` 漏了**（`ledger_edit_page.dart` 直接返回裸 `Scaffold`）→ 本轮修

修法（两层保险）：
1. `LedgerEditPage.build()` 外层包 `GlassBackdrop`，补 `import 'glass.dart';`
   —— 不给「从哪进来的」留假设，页面自己负责自己的底
2. 守卫测试从「只守备忘录」扩成**守所有独立整页**

排查方法：把 `lib/ui/` 下 5 处 `Navigator.push` 全过了一遍，逐个看目标页是谁、
背景从哪来。结论是**只有记账编辑页这一处漏了**。

测试：`editor_backdrop_test.dart` 从 2 例扩到 **7 例**：
- 备忘录 2 例（浅色 / 深色）
- 记账 4 例（记一笔页 / 改一笔页 / 从主页点「＋」进去的路 / **主页本身不该垫**——防止套两层叠出多余模糊）
- **源码兜底扫描 1 例**：扫 `lib/ui/` 下所有含 `Scaffold(` 的 .dart，
  白名单是「内容块」（被壳子套着、自己不该垫的那批：`features_page` / `home_page` /
  `weather_page` / `courses_page` / `settings_page` / `notes_page` / `ledger_page` /
  `glass.dart` / `wheel_time_picker.dart`），**其余只要有 `Scaffold` 就必须出现
  `GlassBackdrop`**，否则测试失败并报出文件名

这条兜底扫描是刻意写的：这类 bug 已经犯过两次（v1.1.1 备忘录、v1.7.2 记账），
靠人肉 review 不保险，不如让**以后任何新加的整页忘了垫背景时，测试直接拦住**。

**364 个测试全绿，analyze 无问题。** 版本 1.7.1+27 → **1.7.2+28**（修订位 +1）。

### v1.7.3 修「备份位置设不了」（需求文档第 9 条的延伸，凯森 2026-09-20 反馈）

凯森在设置页点「数据 → 备份位置 → 选择」，选了「下载」目录后弹：
```
这个位置写不进去，换一个（比如「下载」目录）：
PathAccessException: Cannot open file,
path = '/storage/emulated/0/下载/Download/.cloudlife-write-test'
(OS Error: Operation not permitted, errno = 1)
```

**两个问题叠在一起**：

1. **主因：没有「所有文件访问」权限。** 安卓 10（API 29）起的分区存储下，
   普通 `dart:io` 的 File IO **写不进 `/storage/emulated/0/**` 这类共享目录**，
   必须拿到 `MANAGE_EXTERNAL_STORAGE`。file_picker 的 `getDirectoryPath()`
   返回的是真实文件系统路径，能选中但写不了 —— 这正是「能选、选完报错」的现象。
2. **次因：路径叠层。** 报错里是 `/storage/emulated/0/下载/Download`，
   中英文两个名字叠在一起（部分 ROM 的目录选择器会这样返回）。

**凯森的选择**（2026-09-20，问过三个方案后）：走**申请「所有文件访问」权限**，
不改「另存为」弹窗那条路。已知代价：这是敏感权限，**系统只给跳转页、不给一键授权**，
用户必须手动点一次；个别国产 ROM 还会二次确认，甚至不生效。

改动分三层：

- **原生**（`MainActivity.kt`）：`cloudlife/system` 通道加两个方法
  `hasManageExternalStorage` / `requestManageExternalStorage`。
  查状态用 `Environment.isExternalStorageManager()`；跳转用
  `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`，打不开退
  `ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION`，再不行退应用详情页。
  **Android 11 以下直接当「有权限」**，免得在旧机型上误报。
- **清单**（`AndroidManifest.xml`）：加 `MANAGE_EXTERNAL_STORAGE`，
  带 `tools:ignore="ScopedStorage"`（不加 lint 会拦 release 打包），
  根节点补 `xmlns:tools`。
- **界面**（`settings_page.dart`）：`_pickBackupDir` 从「选完再试写」改成
  **「先查权限 → 没有就弹框引导 → 开完再选」**。引导框把原因讲清楚
  （不说明白用户不敢开敏感权限）。同一个引导也接到 `_doBackup` 上，
  覆盖「设过位置、但权限后来被系统撤了」的情况。
- `normalizeBackupDir()`（放 `backup.dart`，纯函数好测）：把
  `.../下载/Download` 收成 `.../下载`。**只做这一件事**——
  不去统一斜杠体裁（Windows 上会把 `C:\a\b` 改成 `C:/a/b`，
  看着等价其实破坏了原字符串，我第一版就踩了这个坑，被测试逮住）。

测试：`backup_test.dart` 加 6 例（含「Windows 盘符路径原样不动」的守卫）、
`settings_page_test.dart` 加 4 例（没权限弹引导 / 点「先不用」不落盘 /
有权限不打扰 / 设过位置但权限被撤时点备份也引导）。
为此给 `SystemTweaks` 加了 `debugSetStoragePermission()` 测试钩子——
桌面测试跑不到真安卓，没这个钩子就测不了权限分支。

**374 个测试全绿，analyze 无问题。** 版本 1.7.2+28 → **1.7.3+29**（修订位 +1）。
包内已确认 `MANAGE_EXTERNAL_STORAGE` 声明在位、versionName 1.7.3。

### v1.7.4 修「到时间不弹课程提醒通知」（需求文档第 1 条的延伸，凯森 2026-09-20 反馈）

凯森：**「到时间为什么课程没有提醒通知，我没退出软件，通知栏没有弹通知」**。
关键线索是「没退出软件」——App 在前台时定时通知照样该弹，所以不是「被后台杀了」。

查下来是**三个独立问题叠在一起**，缺一个都能导致不响：

**① 通知权限被拒后无人知晓（头号嫌疑）**
`NotificationService.init()` 里只在**首次**调
`requestNotificationsPermission()`，之后 `_ready = true` 直接短路。
用户第一次装的时候要是点了「不允许」，App 永远不会再问，而系统会把排进去的
通知**静默丢掉**——代码没错、通知也排了，就是不给弹，界面上一点提示都没有。

**② 用的是非精确闹钟**
原来死用 `AndroidScheduleMode.inexactAllowWhileIdle`。安卓会把非精确闹钟
**攒起来延后触发**，省电模式下晚十几分钟很常见，用户看到的就是「到点没动静，
过一会儿才冒出来」。而 manifest 里其实**早就声明了 `SCHEDULE_EXACT_ALARM`**，
只是没用上。

**③ 重排是「先全撤、后重排」**
`_rescheduleLessons` 原来先把所有课的通知 `cancelId` 掉，再逐条 `scheduleRaw`。
中间任何一步抛异常都会被 `catch (_)` 吞掉，结果是**旧的全撤了、新的一条没排上**
——用户那边看起来就是「本来能响的提醒突然全没了」，还没有任何报错。

改法：
- `notification_service.dart`：加 `notificationsEnabled()` /
  `exactAlarmsAllowed()` / `requestPermissionAgain()` 三个查询；
  排通知改走 `_mode()`——**优先 `exactAllowWhileIdle`，拿不到精确权限才退回非精确**；
  加 `debugSetPermissions()` 测试钩子（桌面跑不到真安卓）
- `reminder_scheduler.dart`：**先算出 `lessonReminders` 列表再动旧通知**；
  列表为空（用户主动关提醒/没设第 1 周周一）直接 return，不撤旧的；
  只撤「新列表里不要的」那些 id
- `settings_page.dart`：`后台运行与提醒` 卡片里**加两项状态 + 一键跳转**——
  通知权限被拒时顶部还给个橙色警告条（这是最容易让人找不到原因的一项）；
  「精确定时」那项提示「未允许时提醒可能晚几分钟」
- `system_tweaks.dart` + `MainActivity.kt`：加 `openExactAlarmSettings()`
  （`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`，Android 12+ 才有，低版本退应用详情页）

测试：新增 `notification_guard_test.dart` 11 例（权限查询、非安卓不误报、
重排不再先全撤、跨周边界——周日晚上要能算出第 4 周周一那节课）；
`settings_page_test.dart` 加 2 例（被拒显示警告 / 已开不打扰）。

**387 个测试全绿，analyze 无问题。** 版本 1.7.3+29 → **1.7.4+30**（修订位 +1）。

**给凯森的话**：装完新版请去「设置 → 后台运行与提醒」展开看一眼，
「通知权限」和「精确定时」两项都是「已开启/已允许」才算好。
没开的话点右边按钮，按提示走一遍。

### v1.7.5 **真凶**：漏声明通知接收器（凯森 2026-09-20 反馈 1.7.4 装完仍不响）

凯森装完 1.7.4 后回话：**「和之前一样，课表提醒和备忘录定时都没有通知」**。
两种提醒走同一套 `NotificationService`，所以问题一定在共同环节上。

**根因在 `AndroidManifest.xml`：漏了插件要求的两个 receiver。**

`flutter_local_notifications` 用 `AlarmManager` 排闹钟，但**闹钟到点不等于通知会弹**——
它靠一个广播接收器收到 `AlarmManager` 的广播、再把通知发出来。插件 README
（v17.2.4，第 252-263 行）明确要求 App 在自己的 `<application>` 里声明：

```xml
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

原文写得很直白：**"so that the plugin can actually show the scheduled
notification(s)"**。

**已确认插件自带的 manifest 里没有这两个**（`flutter_local_notifications-17.2.4/
android/src/main/AndroidManifest.xml` 只有 VIBRATE + POST_NOTIFICATIONS），
所以必须由 App 声明，不存在重复冲突。

后果正是凯森遇到的：闹钟**按时排进了 AlarmManager、到点广播也发了**，
**但没人在听** → 通知永远不出现，**且没有任何报错**。
权限、电池优化、精确闹钟全都正常也没用。
**也就是说：从 v1.6.0 引入通知功能开始，定时提醒就没真正跑通过。**
前几轮改的权限提示、精确闹钟都是必要的，但都不是「完全不响」的主因。

本轮改动：
- `AndroidManifest.xml`：补上两个 receiver（带醒目注释，写明「不要删」）
- `notification_service.dart`：加 `pendingRequests()`——**问系统实际排了几条**。
  非安卓返回 `null` 而不是 `[]`（返回空列表会让界面显示「一条都没有」，
  把排查带偏；null 让界面说「查不到」）
- `settings_page.dart`：卡片里加「已排提醒」自检行，点「检查」看系统里的条数
- `packaging_guard_test.dart`：加 3 例守卫——两个 receiver 必须在位、
  通知相关三个权限必须在位。**这类「漏声明」编译器完全不管，只能靠测试守**

**391 个测试全绿，analyze 无问题。** 版本 1.7.4+30 → **1.7.5+31**（修订位 +1）。

**凯森要求：等他确认 bug 真修好了再发 GitHub Release。** 所以本轮**只出 APK，
不发布**。

### v1.7.6 继续修：装完 1.7.5 后「到点没弹通知并且闪退」

凯森装了 1.7.5 之后回话：**「时间到了没有弹通知并且软件闪退了」**，
并附了设置页截图（「已排提醒」显示「查不到」）。

#### ⭐ 真凶（连上真机抓到的）：R8 擦掉了 Gson 的泛型签名

凯森开了 USB 调试连上手机，才第一次拿到真正的崩溃记录。
`adb logcat -b crash` 里有 3 条 MyDay 的崩溃，全在同一个地方：

```
09-20 22:29:59 E/AndroidRuntime: FATAL EXCEPTION: main
  Process: com.youkeisen.my_day_phone, PID: 16295
  java.lang.RuntimeException: Unable to start receiver
    com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver:
    java.lang.RuntimeException: Missing type parameter.
  at FlutterLocalNotificationsPlugin.loadScheduledNotifications(...)
  at FlutterLocalNotificationsPlugin.rescheduleNotifications(...)
  at ScheduledNotificationBootReceiver.onReceive(...)
```

时间点完全对得上：22:29:59（装完 1.7.5 触发 MY_PACKAGE_REPLACED）、
22:31:00、22:33:00 —— 凯森 22:33 发的截图就是在第三次崩溃之后。

**根因**：插件 `flutter_local_notifications 17.2.4` 源码第 508 行

```java
Type type = new TypeToken<ArrayList<NotificationDetails>>() {}.getType();
scheduledNotifications = gson.fromJson(json, type);
```

Gson 靠**匿名 TypeToken 子类的泛型签名**（class 文件里的 `Signature` 属性）
反射拿到 `ArrayList<NotificationDetails>` 这个具体类型。
**R8 默认会把 Signature 属性擦掉、并把 NotificationDetails 重命名**，
Gson 于是读不到类型参数 → 抛 `Missing type parameter`。

**后果链**：闹钟到点 → receiver 起来 → 读已存通知数据 → 崩 → 进程没了。
表现就是「通知永远不弹 + App 闪退」，而且**设置页查「已排提醒」也一起崩**
（`pendingNotificationRequests()` 走的是同一个 `loadScheduledNotifications`）——
这就是截图上「查不到」的由来。

**修法**：新增 `android/app/proguard-rules.pro` + 在 `build.gradle.kts` 的
release 里显式 `isMinifyEnabled = true` 并挂上规则文件。最关键的两条：

```proguard
-keepattributes Signature                                  # Gson 的 TypeToken 全靠它
-keep class com.dexterous.flutterlocalnotifications.** { *; }  # 反序列化目标类
```

另外还要保住 `com.google.gson.**`、`* extends TypeToken`、
`* implements TypeAdapterFactory`（插件的 RuntimeTypeAdapterFactory 走这条）。

**验证方式**（三道）：
1. `mapping.txt` 里插件的类是 `原名 -> 原名`（没被重命名），
   匿名内部类 `FlutterLocalNotificationsPlugin$1`~`$5` 也在（TypeToken 那个就是其中之一）；
2. 真机 `adb shell am broadcast -n <pkg>/...ScheduledNotificationReceiver`
   手动触发，crash buffer **0 条新增**（修复前每次必崩）；
3. `dumpsys alarm` 里排上了 3 条 `RTC_WAKEUP` 精确闹钟，全部指向该 receiver。

> **教训**：前四轮（v1.7.2~v1.7.5）全靠读源码猜，方向都不对。
> 「定时通知不响」这种跨 Dart/原生/R8 的问题，**必须拿到真机崩溃记录**，
> 不然就是在黑箱外面瞎试。**以后遇到「不响 + 闪退」，第一件事是让他开 USB 调试。**

#### 顺带修的两处（这两处本身也对，但不是主因）

**① 通知小图标用了彩色 launcher 图（主因）**

`AndroidInitializationSettings('@mipmap/ic_launcher')` —— 安卓通知栏的小图标
**必须是纯白剪影 + 透明背景**（系统只取 alpha 通道再染色）。
用彩色图当小图标时，安卓会强行转成单色方块（显示成白方块），
**部分国产 ROM（小米/OPPO 等）会认为图标不合规，在弹通知时直接崩掉进程**。

修法：新增 `tools/make_notification_icon.py` 生成纯剪影图标
（从 Cloud logo 里**只取倒三角主体并填实成剪影**——原图的 CLOUD 细字和
描边在 24dp 下会糊成一坨，所以不整张用）。
然后 `AndroidInitializationSettings` 和两个 `AndroidNotificationDetails.runner`
都显式指定 `@drawable/ic_notification`。

**①的后续：图标压根没进包 → 改用矢量**

第一版生成的是 5 张 PNG（`drawable-{m,h,x,xx,xxx}dpi/ic_notification.png`）。
打完包挖进 APK 里看，**5 张一张都没有**。

查 `build/app/outputs/mapping/release/resources.txt` 第 208 行找到原因：

```
drawable:ic_notification:2131099676 is not reachable.
```

release 打包会跑**资源压缩（Resource Shrinker）**，它靠**静态引用**判断资源
有没有人用。而 Dart 侧写的是**运行时字符串** `'@drawable/ic_notification'`，
构建期的资源分析器**看不见** → 判为「没人用」→ 直接删。

**走过一次弯路**：先在 `values/notification_icon.xml` 里写了个
`<item name="ic_notification_anchor" type="drawable">@drawable/ic_notification</item>`
当锚点。**没用**——`<item>` 是「**定义**一个新资源」，不是「**引用**一次」，
所以 resources.txt 里锚点自己也写着 "not reachable"，图标照样被删。

**正解**是 `res/raw/keep.xml`：

```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_notification*" />
```

加了这个之后 resources.txt 变成
`drawable:ic_notification:2131099676 reachable from keep xml file`，
APK 里 PNG 从 13 张变 18 张（正好多的 5 张）。

**但又发现第二个问题**：包里那张 96px 的图上框 + 倒三角**变成了细描边空心框**。
逐像素解析确认源 PNG 是对的（30.6% 不透明），说明是 **AAPT 的 PNG 优化
重新编码时把细则丢了** —— 通知栏 24dp 下那种细线等于看不见。

**定稿改用矢量 drawable** `drawable/ic_notification.xml`（24dp viewport，
两条 path：圆角横框 + 实心倒三角），删掉那 5 张 PNG。
矢量不走 PNG 优化，形状 100% 保真，体积也更小。这是安卓官方推荐做法。
校验方式：解包 APK，`res/vO.xml` 里能看到两条 path **原样**存在。

**② 无界面引擎上申请权限会崩**

`NotificationService.init()` 里有一句 `requestNotificationsPermission()`。
而开机的 `BootReceiver` → `BootRescheduleWorker` 拉的是**无界面 Flutter 引擎**
（跑 `bootMain`），那里**没有 Activity**——在这种引擎上申请运行时权限会崩。
表现就是「通知没弹 + App 崩了」。

修法：`init()` 里用 `_requestPermissionOnInit` 开关包住申请逻辑；
新增 `NotificationService.initHeadless()`；`rescheduleAll({headless})` 透传；
`bootMain` 里调 `rescheduleAllReminders(store, headless: true)`。

**顺带加固**：
- 重排加**防重入**（`_inFlight`）——App 启动、改设置、改课表可能几乎同时触发
  全量重排，并发会重复排通知、也更容易撞上「先撤后加」的中间态
- `pendingRequests()` 查不到时把**真实错误**记进 `lastPendingError`，
  设置页显示出来（只写「查不到」的话，下次还得重新猜一遍）

测试：`notification_guard_test.dart` 里的 v1.7.6 守卫——
矢量图标在位且两条 path 都在（并禁止同名 PNG 回退）、
`raw/keep.xml` 在位且含 `tools:keep`、
`initHeadless` 存在、`bootMain` 走 headless、重排有防重入。

**APK 终检**（解 `D:\App\apk\MyDay-手机版-v1.7.6.apk`）：
- 版本号 1.7.6 ✓（二进制 manifest 按 **UTF-16LE** 解码才搜得到）
- 权限：`MANAGE_EXTERNAL_STORAGE` / `SCHEDULE_EXACT_ALARM` /
  `POST_NOTIFICATIONS` / `RECEIVE_BOOT_COMPLETED` / `VIBRATE` 全在 ✓
- 组件：`ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` /
  `BootReceiver` 全在 ✓
- 通知图标：`res/vO.xml`（矢量）里两条 path 原样 ✓

#### 加守卫测试

`packaging_guard_test.dart` 加 4 例，守住这次的坑别再退回去：
- `proguard-rules.pro` 存在且含 `-keepattributes Signature`（最关键那条）
- 保住了 `com.dexterous.flutterlocalnotifications.**`
- 保住了 Gson（`com.google.gson.**` + TypeToken 子类 + TypeAdapterFactory）
- `build.gradle.kts` 的 release 里挂上了这个规则文件

**401 个测试全绿，analyze 无问题。** 版本 1.7.5+31 → **1.7.6+32**（修订位 +1）。

**仍然不发 Release，等凯森实机确认。**

#### v1.7.6 补：调试按钮不留（凯森 2026-09-20 定）

修完还剩一个问题：**怎么确认通知真的能弹**？排好的提醒最快也要等几分钟，
最慢得等到第二天早上那节课，排查一轮要一天。

我当时的做法是往「设置 → 后台运行与提醒」里塞一行：

> 测试通知  点一下，通知栏应该立刻弹出一条   [发一条]

验证完凯森说：**不留测试通知**。调试用的东西不该留在界面上。已全部移除：

- `notification_service.dart` 删掉 `showTestNotification()`
- `settings_page.dart` 删掉那一行和 `_sendTestNotification()`
- `settings_page_test.dart` 原本「有测试通知按钮」的用例改成**反向守卫**
  （断言 `btn-test-notification` 不存在、文案「通知栏应该立刻弹出」不存在），
  免得以后又被人加回去
- changelog 里那句也删了

**那以后怎么验证通知？** 不靠按钮，直接 adb 打 receiver：

```bash
adb shell am broadcast -n com.youkeisen.my_day_phone/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
```

它走的是真实链路（反序列化 payload → 建通知 → 调系统），
比一个自己 `show()` 的按钮**更能证明问题不在原生层**——
本次就是这么抓到 R8 那个崩溃的。

「已排提醒 → 检查」那一项**留着**，它是排查用的自检（显示真实错误），
不是调试按钮，凯森没让删。

#### 真机实测记录（2026-09-20 23:05~23:30）

| 项 | 结果 |
|---|---|
| 设备 | vivo S10（V2121A），安卓 13 / API 33 |
| 装前状态 | 1.7.5+31，通知权限 granted、精确闹钟 granted、所有文件访问 allow |
| ① 手动触发 receiver | **0 条崩溃**（修复前每次必崩 `Missing type parameter`）|
| ② 排上的闹钟 | 3 条 `RTC_WAKEUP` flags=9（精确）：09-21 08:00 / 09:50 / 18:50 |
| ③ adb 打 receiver 触发通知 | **通知真的出现在通知栏**，crash buffer 0 条 |
| ④ 通知小图标 | `icon=Icon(typ=RESOURCE ... id=0x7f06001c)`，反查 R.txt = **`drawable/ic_notification`** ✓ |

**四道验证全部通过，修复闭环完成。**

**1.7.6+34 复验**（去掉测试通知按钮后重新出包）：
403 个测试全绿、analyze 无问题、装到真机 `versionCode=34`，
`uiautomator dump` 确认「后台运行与提醒」里只剩
通知权限 / 电池优化白名单 / 精确定时 / 已排提醒 四项，没有多余按钮。

> ④ 的确认方法值得记下来：APK 里资源名被 AAPT 混淆，按名字搜不到。
> 做法是让系统把通知的 icon 资源 id 打出来（`dumpsys notification`），
> 再拿 id 去 `build/app/intermediates/runtime_symbol_list/release/processReleaseResources/R.txt`
> 反查名字 —— 直接证明「包里的图标确实被系统用上了」。

**adb 命令备忘**（下次直接抄）：
```bash
adb logcat -b crash -d          # 崩溃记录（main buffer 被 vivo 清了，crash buffer 还在）
adb shell dumpsys alarm         # 已排闹钟
adb shell dumpsys package <pkg> # 权限 + 版本
adb shell am broadcast -n <pkg>/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
```
vivo 拦 USB 安装（`INSTALL_FAILED_ABORTED: User rejected permissions`），
解法：`adb push` 到 `/sdcard/Download/` 再
`am start -a VIEW -d file:///sdcard/Download/xxx.apk -t application/vnd.android.package-archive`
唤起安装界面让凯森点。

## v1.8.0：自启动一键跳转 + APK 改名（2026-09-21）

凯森要的两件小事：**① 设置里加「自启动」开启按键；② APK 文件名改成 `CloudLife-版本`**。

### 为什么要自启动这一项

国产 ROM（小米 / 华为 / OPPO / vivo / 荣耀…）在安卓之上**额外加了一层「自启动」开关**。
关着的时候，系统重启或者进程被回收之后，App **不会被拉起来** ——
那么 `BootReceiver` 里那段「开机把提醒重新排一遍」的逻辑就**根本没有机会跑**，
表现是：**手机重启之后，课表提醒再也不响了**（而且 App 本身一切正常）。

之前这个只能靠设置页底部一行小字让用户自己去找。现在给成按钮。

### 难点：安卓没有标准的自启动 Intent

翻遍官方文档也不会有 `ACTION_AUTO_START` 这种东西。现实情况：

- **每家 ROM 的自启动管理页包名 + 类名都不一样**（同一家的不同系统版本还换过包名）
- **没有任何 API 能查这个开关现在是开还是关**
  → 所以界面上**不做「已开 / 未开」的判断**。猜错比不猜更糟，
  用户看到「已开启」就会以为没事了

实现（`MainActivity.kt` 的 `openAutoStartSettings()`）：

1. 列一张候选表（vivo / 小米 / OPPO / realme / 华为 / 荣耀 / 三星 / 魅族 / 联想 / 中兴 / 锤子）
2. 用 `Build.MANUFACTURER / BRAND / PRODUCT / DEVICE` 猜机型，
   **把自己那一组的候选排到最前面**（`sortedByDescending`）——
   不排的话，vivo 的机器可能先撞上一个不存在的 OPPO 页面
3. 逐个 `resolveActivity()` 判断页面存不存在，**存在才 `startActivity()`**
   （不直接 `start` 然后靠抛异常判断，猜错一堆会一路 ActivityNotFoundException）
4. 一个都不存在（原生 / Pixel 这类没有自启动概念的 ROM）→ 退到应用详情页，
   **返回 false 给 Dart 侧**，界面上 toast 说清楚「这台没有专门的自启动页」

返回值的用处：`true` = 跳到了专门的管理页，提示「找到 CloudLife 打开」；
`false` = 只退到应用详情，不装作成功。

**真机实测（vivo S10，2026-09-21 00:45）**：
点「去设置」→ `topResumedActivity = com.vivo.permissionmanager/.activity.BgStartUpManagerActivity`。
即 i 管家的**自启动管理页**（截图上那一列：自启动 / 悬浮窗 / 桌面快捷方式 / 锁屏显示…）。

第一版候选表里 vivo 写的是 `PurviewTabActivity`（权限管理页），实测也能跳，
但**只停在外层列表**（「自启动 92 个应用 ›」那一行），用户还得自己点进去再翻应用。
所以把 `BgStartUpManagerActivity` 加进候选表**并排到最前面**，一步到位。
—— 这就是「按机型排序 + 一个厂商留多个候选」的用处：同一个 ROM 有多个入口，
浅的那个也能用，但深的那个体验才对。

### 顺手加的守卫：`test/main_activity_guard_test.dart`

`cloudlife/system` 这个通道是**字符串对字符串**的：Dart 侧 `invokeMethod('xxx')`
必须和 Kotlin 侧 `when (call.method)` 的分支一字不差。写错的表现是
`MissingPluginException`，而且**只有真机点到那个按钮才会炸**，
桌面测试和 analyze 全都抓不到。

所以新建了这个文件，直接读两边的源码文本：
- 7 个 method 名两边对得上（以后加新 method 必须补一行，否则这层网破了）
- 自启动候选里必须含几个主流 ROM 的包名
- 必须按机型排序、必须先 resolve 再 start、必须有兜底

### APK 改名

- 本地：`D:\App\apk\` 从 `MyDay-手机版-vX.Y.Z.apk` 改成 **`CloudLife-vX.Y.Z.apk`**
- GitHub Release 的 asset 同名（`tools/release.py` 的 `default_asset_name` 改了）
- 理由：**手机桌面上显示的名字就是 CloudLife**（包名仍是 `com.youkeisen.my_day_phone`），
  安装包叫 MyDay 的话拿到的人对不上是哪个应用
- 历史的老包**没动**，还在原来的名字上

### 版本号

加功能 → 次位 +1、修订位清 0（凯森定的规矩）：1.7.6+34 → **1.8.0+35**。

417 个测试全绿（新增 14 个），analyze 无问题。

## v1.9.0：提醒三方式 + 首页速览收起 + 首页刷新（2026-09-21）

凯森 2026-09-21 连着提的几件事，**都还没发布过，所以算同一个版本、同一次提交**
（他明确要求：「没确定提交前的所有内容都为同一次提交的内容和版本」）。
下面分三块记，过程里的版本号 1.8.1 / 1.9.0 / 1.9.1 都收回到 1.9.0。

### 一、修「别处改了数据，首页不刷新」

现象（凯森报的）：「我把笔记删除了但是首页的没有删除，要重新进首页才会消失」。

首页 → 点「备忘录速览」里的一条 → 进编辑页删掉 → 返回 → **那条还在首页上**。
切到「功能」再切回「首页」才消失。

**根因**：页面画的都是 store 的**实时**数据（build 里现读），数据本身永远是新的；
缺的是「数据变了 → 叫界面重新 build」这一环。

- 首页的 `State` 在 push 子页面时**一直活着**（没被销毁），返回时不会重跑
  `initState`，也没有任何人叫它 `setState`，于是它继续显示旧内容。
- 切 Tab 看着「好了」其实是巧合，不是修好了：`HomeShell` 用
  `KeyedSubtree(key: ValueKey(label))` 包页面，切走时 key 变了 → State 被销毁，
  切回来重新 `initState` → 重读数据。**换成不销毁的写法这个 bug 立刻回来**。

**修法**：给 Store 加变更通知，关键是**挂在哪** —— 挂在每个 `saveXxx` 里写一遍
最容易想到，但那种写法早晚会漏一个（现在有 notes / settings / courses / ledger /
weather_cache 五个入口，以后还会加）。所以挂在 `write()`，它是**所有落盘的唯一总入口**。

细节（都有测试守着）：
- **防重入**：回调里万一又写了数据，`_notifying` 守卫挡住，不然是无限递归
- **遍历用快照**：回调里可能增删监听，直接遍历原列表会崩
- **只在落盘成功后通知**：写在 `try` 成功分支里，写失败就别让界面以为改好了

首页接上（`initState` 订阅 / `dispose` 摘掉），一行 `setState` 就完事。

**测试**：`store_test` 加一组「变更通知」5 条；`home_page_test` 加 2 条
（删掉后首页立刻不显示、销毁后不响应）。
这 2 条**验证过真能抓住 bug**：把 `addListener` 那行注释掉，第一条立刻变红。

一个小坑：文件不存在时 `read()` 会补一份默认值，那一趟**也走 `write`**，
所以也会通知一次。测试里先 `init()` 再计数（真机上 App 启动时已经 init 过）。

### 二、定时提醒改成「先选时间 + 单次 / 每天 / N 天后」

凯森的第一版要求是「定时这里加上每天和单次的选项」，我做成了
「点提醒 → 先问单次还是每天 → 再选时间」。他看了之后改需求：

> 要先选择时间，只用选择小时和分钟，不用设置天数，
> 选择的时候不用往后调一个小时默认是当前的时间，
> 设置好时间在编辑笔记的界面才能选择单次还是每天，或者是设置天数

拆开是四条：直接选时分（不选日期）、滚轮默认**当前时间**（原来 +1 小时）、
方式的选择放在**编辑页上**、方式两种变**三种**。问过他「设置天数」是哪种，
答「在单次和每天的基础下增加一个设置哪天通知的设置天数」→ 就是「几天后」。

**数据**：`Note` 加 `remindRepeat`（`''` 单次 / `'daily'` 每天 / `'days'` N 天后）
和 `remindDays`（那个 N）。`remindAt` 存的还是 ISO 时间，但角色变了 ——
它现在只代表「时:分」，日期部分是「设的时候的基准」，真正排哪天由方式现算：

- 单次   → `nextOnceOccurrence`：今天的点没过就今天，过了就明天
- 每天   → `nextDailyOccurrence` + `DateTimeComponents.time`
- N 天后 → `afterDaysOccurrence(base, N, now)`

这样用户**永远不用为了「选一个已经过去的时刻」而报错** —— 以前单次必须挑日期，
挑到今天又要选个已过的时间点，只能报「要选未来时间」让他重来。

`remindRepeat` 的解析只认 daily / days，别的一律当单次（老数据没这个键 → 单次，
行为不变；以后加没实现的值也不会被误当成新行为）。

**界面**：点提醒直接弹时间滚轮（默认 `TimeOfDay.now()`）；选完在编辑页上出现
「提醒方式」三个 ChoiceChip；选「N 天后」时出现天数输入框（默认 1 天）。
方式之间来回切时数据层把 `remindDays` 清 0（不留残值），但**输入框里记着
用户刚填的数**，切回来还是那个数。

**最容易踩的坑**：`ReminderScheduler._rescheduleNotes` 原本是「`remindAt` 已过 →
撤掉通知」，这对单次是对的，但对每天**是致命的** —— 每天提醒存的时刻**必然**
是过去的（设的是「今天 08:00」，第二天就过期），而重排是**每次 App 启动**都跑，
照原逻辑一重排就把它撤了，用户第二天收不到。所以每天那条分支要在「过期撤销」
**之前** `continue` 掉，改成现算下一次再排。`notification_guard_test` 用**源码位置**
卡这个顺序（`indexOf('if (n.remindDaily)') < indexOf('!when.isAfter(now)')`），
验证过：故意调换顺序，它立刻变红。

**顺带修的雷**：`Note.copyWith` 原来没带 `remindAt` / `remindRepeat` / `remindDays`，
谁拿它「只改个标题」提醒就被静默清空。目前没有调用方所以还没爆，已经补上。

### 三、首页「备忘录速览」内容默认收起

凯森要求「首页笔记的内容改成默认关闭」。

原来速览里每条的内容是**默认摊开**的（`_noteOpen[n.id] != false`，和电脑版
`homeNoteOpen` 一致），几条笔记下来首页被撑得很长，扫一眼反而看不到重点。

改成默认收起（`_noteOpen[n.id] == true`，表里只记「用户手动展开过的那几条」），
标题 + 摘要（清单给「x/y 项完成」）照旧一眼可见，想看内容点标题右边的小箭头。
小箭头图标本来就跟着 `open` 走（收起 ›/展开 ⌄），不用改。

测试跟着调了 4 条（速览那条要先展开、收放那条语义反过来、勾选那条要先展开、
新增 1 条把「默认收起→展开→再收」钉住）。**验证过真能抓住**：
把 `== true` 改回 `!= false`，两条立刻变红。

### 四、去掉备忘录的标签功能（连数据一起清）

凯森 2026-09-21：「把笔记里的标签删除」，随后补一句「数据一起清掉」。
所以是**功能和数据都去掉**：

- 编辑页去掉标签输入框（连 `_tagsCtl` 一起清掉）
- 模型 `Note` **删掉 `tags` 字段**（构造参数、fromJson、toJson、copyWith 都不再有）
- 列表分组只剩「全部 / 置顶 / 归档」，不再生成 `tag:xxx` 分组
- `filteredNotes` 去掉 `tag:` 分支（现在 `tag:` 开头的键走「认不出来」的兜底）
- 列表副标题、首页速览都不再显示标签（首页那行改成只显示类型）
- 搜索的全文也不再包含标签；`parseTags` 直接删掉

**这里有个反直觉的关键点，差点踩坑**：

模型不解析 `tags` 并不等于文件里的旧数据会消失。`Note.known` 是给
`extraKeys()` 用的 —— **不在 known 里的键会被当作「认不出来的字段」收进
`extra`，然后原样写回文件**。所以如果把 `'tags'` 从 `known` 里删掉，
旧标签反而会被**永久保留**在 notes.json 里，永远清不掉。

正确做法是**把 `'tags'` 留在 `known` 里**（只删字段、不删这个名字）：
读进来直接丢、写出去就没有。测试直接用「读一份带 tags 的旧 JSON，
断言 `extra` 和 `toJson()` 里都没有 tags」把这条钉住。

光靠这个还不够 —— 用户没编辑过的笔记根本不会重写。所以 `Store.init()`
里加了一次性清理 `dropLegacyNoteTags()`：扫一遍 notes.json，
**有残留才重写**（没残留不写盘，否则每次启动都写一次、白白触发界面刷新）。

测试：`store_test` 3 条（抹掉存量、没残留不动文件、夹着脏数据不崩）、
`models_test` 1 条（旧 JSON 读进来写出去就没 tags）、
以及原有 5 条改写成「用带旧标签的 JSON 造数据，界面不再显示标签」。

两条新守卫都**反向验证过**：把 `dropLegacyNoteTags()` 从 init 里注释掉、
把 `'tags'` 从 known 里删掉，对应测试各自变红，恢复后绿。

### 收口

全量测试绿，analyze 无问题。版本统一为 **1.9.0+40**
（过程中的 +37 / +38 / +39 是同一个版本的中间包）。

> 教训一：验证测试能不能抓住 bug 时**别用 `git checkout <file>` 恢复** ——
> 那次修改还没提交，checkout 恢复的是**上次提交的版本**，会把新写的代码一起抹掉。
>
> 教训二：用 Bash 的 heredoc 往文件里灌大段 Dart 代码会被 shell 吃掉
> （`unexpected EOF while looking for matching '`）。要改大块就写成 `.py`
> 脚本文件跑完再删，或者用编辑工具。


### v2.1.1：整体换肤 —— Liquid Glass → Apple 扁平（2026-09-22）

凯森给了一份《设计风格提示词》（Apple 官方设计语言），要求照它改手机版 UI。
这是一次**视觉换肤**：不改数据、不改字段、不改交互行为。

**做了什么**

- 新增 `lib/ui/design.dart` 设计令牌层：`Tone`（浅/深两套配色）、`Type`（8 档字阶）、
  `Gap`（间距常量），以及 `PageSurface` / `SectionCard` / `CardHead` / `IconPlate` /
  `Pill` / `GroupRow` / `GroupDivider` / `KvRow` / `EmptyHint` / `ThinChevron`。
- `buildTheme` 按令牌重写：底色改成**不透明实色**（原来 transparent + 每页自己垫
  渐变玻璃），卡片白底 + 1px 描边 + 圆角 18 + **elevation 0（无阴影）**，
  强调色统一成 `#0066CC`（深色 `#0A84FF`）；补了 chip / switch / checkbox /
  bottomSheet / input 的主题，免得各页各写一遍。
- 删掉 `lib/ui/glass.dart`（`Glass` + `GlassBackdrop`），独立整页改用 `PageSurface`
  垫一层实色底。
- 底栏：白色悬浮胶囊（高 62 / 圆角 36 / 1px 描边 / 内边距 4），选中项改成
  **实心强调色 + 白字**（原来只是图标文字变蓝）。
- 顶栏：页面标题 28 Bold + 右侧教学周胶囊。
- 各页散落的字号（9/10/11/12/13/14/16/18/20/22/32/34/44 共 14 档）收进 `Type` 的
  8 档；`Colors.red` / `Colors.orange` 换成 `Tone.danger`；备忘录列表的置顶标记
  从「★ 前缀」改成行首星形图标（设计稿禁止拿符号当图标）。
- 设置页「称呼」的说明原本写的是开发笔记（「凯森 v1.4.4 要求加回来」），
  换成面向用户的说明。

**测试**

- `app_test` 的主题断言重写：底色必须**不透明**且等于 `Tone.bg`、卡片色与强调色
  跟深浅色走、`cardTheme.elevation == 0`。**反向验证过**：把底色改回
  `Colors.transparent`，这条立刻变红，恢复后绿。
- `editor_backdrop_test` 的不变量从「每个独立整页必须有 `GlassBackdrop`」
  改成「必须有 `PageSurface`」，白名单补 `home_shell.dart`（壳子自己给底色）。
- `notes_page_test` 的三处 `'★ 置顶的'` 改成 `'置顶的'` + 断言星形图标在场。
- 全量测试绿、`analyze` 无问题。

**没动的**

数据文件、字段、备份包结构、通知与排程逻辑、所有控件 key 与用户可见文案
（除上面那条设置说明）一律没动，所以和电脑版的备份互通性不受影响。

### 接着换成 v2.0 设计系统（2026-09-22，同一个未发布版本）

上面那轮 Apple 扁平刚做完，凯森又给了三份东西：`设计规范.md`（v2.0 重构方案）、
`design-system.css`（设计令牌）、`mobile-ui-redesign.html`（可交互原型）。
v2.0 不是「再换一次色」，而是**配色体系 + 字阶 + 逐页布局**一起重做，
所以上面那轮的令牌被整体替换掉了（`Tone`/`Type`/`R`/`Sp`/`Sh` 全部改成 v2.0 的取值）。

**配色**

- 主色 靛蓝 `#2B54C8`（按下 `#1F3F9E`、浅底 `#EEF3FF`、描边 `#BCCEFB`），
  换掉高饱和的「链接蓝」
- **新增强调橙 `#F07A28`**：只给「进行中 / 即将开始 / 天气预警」用，一屏最多 1~2 次
- 中性阶改成冷调八档（`ink-900…ink-50`），避开死灰
- 语义色（成功/警告/危险）只用于图标着色；危险色只给「清除数据」
- 深色模式不再用纯黑：底 `#131720`、卡片 `#1C2230`，层级靠 1px 边框

**字阶**：40 / 26 / 20 / 16 / 14 / 12.5 / 11（收敛版 1.2 比例），
字重只用 400/500/600/700，数字一律 `tabular-nums`。
圆角四级 10/14/18/24（卡片统一 14），间距走 8pt 栅格，阴影改成极浅多层冷调。

**逐页布局重排**（对照原型的改动清单，逐条落地）

- 底部导航：蓝色大胶囊 → 白底半透明 + 顶部 3px 指示条（导航不该是最重的元素）
- 首页：删掉重复的大标题；问候语 + 日期做成页头；新增三栏状态条
  （本周 / 今日课程 / 下一节）；新增「正在上课」深蓝主卡（进度条 + 剩余分钟）；
  天气/备忘改双列小卡；课程列表改时间轴；**已结束从删除线改成降饱和**
  （删除线语义是「作废」不是「已完成」）
- 功能页：纵向长列表 → 2×2 宫格（彩色图标 + 关键数据），下面补快捷操作
- 课程页：操作按钮从顶部挪到底部（添加课程为主按钮）；周切换改大号箭头 +
  可下拉选周 + 「回到今天」；新增横向日期条和 日/周/列表 三种视图；
  日视图只显示那一天
- 天气页：温度升到 40px 展示级；预警从小胶囊改成带图标的提示条；
  24 小时柱状图 → 折线 + 渐变面积；8 行详情 → 2 列网格；补上 7 天预报
- 设置页：新增账号卡；卡片按 通用 / 数据 / 危险操作 分组，行头带图标；
  「清除所有本地数据」从「数据」卡里挪出来单独成组 + 底部脚注

**测试**

- 458 条全绿、`analyze` 无问题。布局大改，改到的断言逐条重写并写了理由：
  首页状态条的值拆成「标签 + 值」（`今日 0 节课` → `今日课程` + `0 节`）、
  课行副标题改成「节次 · 地点 · 老师」拼串、天气小卡副标题拼
  「天气 · 城市 · 湿度」、速览摘要用 `textContaining`、周次胶囊改成
  从 `WeekChip` 里取 Text 断言（保留「第 N 教学周」正则）。
- 主题断言换成 v2.0 令牌（底色不透明、卡片色、主色、非纯黑、elevation 0）。
- 备忘录速览那条「天气 / 课程 / 速览」的上下顺序测试补了一条笔记：
  没有笔记时速览区按设计不渲染（空态由「备忘」小卡承担）。

**过程中踩的坑**

- `Card2` 里面直接放 `ListTile` 会触发 Flutter 断言（「ListTile 的背景色和
  墨水可能看不见」）。做法是在卡片里垫一层透明 `Material`，顺带让卡片内的
  `InkWell` 水波纹有落点。
- 首页顶部状态条里的「下一节」时间和课行的时间都要等宽数字，否则每刷新一次
  整行会左右抖。
- 用脚本批量改令牌名时踩了一次：`Type.number` 会命中 `TextInputType.number`
  里的子串，把键盘类型改成了 `TextInputType.display`。批量替换要挑不含歧义的
  字面量，或者先把它换成占位符。

**已经试过又回退的：课表「固定左列 + 右侧横滑」（2026-09-22）**

设计稿里要求课表「固定左列 + 右侧横滑」（原来整张表一起平移，看第 5 节时不知道
那一列是星期几）。做了一版：外层纵向滚动 + 左边冻结节次列 + 右边横向滚动日期列，
课块也换成低饱和底色 + 左侧 3px 色条。

**凯森看完让回退到上一个版本**，所以这一版整个撤掉了，原因记在这里免得再走一遍：

- 代价是**必须扔掉双指缩放**（v1.3.8 他要求加的）。缩放是一个整体变换矩阵，
  没法只作用于一侧；要同时保住「固定左列 + 缩放」，得让左列跟着同一个矩阵缩放、
  横向锁死在 0，再把左列宽度跟着 scale 变，太脆。
- 而且周视图固定列宽之后，一周放不下、必须横滑；他现在更看重「一眼看到整周」。
- **结论：课表维持 `InteractiveViewer` 整体平移缩放**（当前实现）。
  以后要再试，先问清楚「缩放」和「固定左列」二选一他选哪个。

回退时把同轮做的课块色条（`_cellBox`）和主卡入场动效（`RiseIn`）也一起撤了；
**凯森随后说「色块和入场特效加上」**，所以这两样又加回来了 —— 它们跟「固定左列」
是两件独立的事，只是当时凑在同一轮里做的：

- 课块：低饱和底色（浅色模式 `alphaBlend(色相, surface, .10)`，深色 `.22`）+
  左侧 3px 色条，按课名取色（同一门课恒定同色）；空格子只留一条格线。
- 主卡入场：`RiseIn`（淡入 + 上移 10px / 500ms，一次性的）。
- 顺带补了 `日 / 周 / 列表三种视图都能切` 的测试（这三种视图本身留着）。

**动效的坑（一直有效）**：原型里的「进行中」脉冲点是**无限循环**动画，
做了会让 `pumpAndSettle()` 永远等不到静止、测试直接超时。要加循环动效，
得先想好测试怎么写（比如用 `pump(时长)` 代替 `pumpAndSettle`）。


### 检查更新（2026-09-22，同属 2.1.1）

设置 → 关于里加了个「检查更新」按钮：手动查一次 GitHub Releases，有新版就弹窗
（新版本号 + 发布说明 + 「去下载」），失败给一句人话。**只在手动点的时候查**，
不做后台轮询 —— 这种个人应用没必要，也省得没网时天天报错。

实现要点 / 踩的点：

- **不能用 `/releases/latest`**：仓库里还有电脑版的 release（tag 不带 mobile-
  前缀），latest 会撞上电脑版。做法是拉 `releases?per_page=20` 自己筛
  `mobile-v` 前缀、取最新一条。
- 版本比较是纯函数 `compareVersions`：抠数字段逐段比，**缺的段按 0**
  （2.1 等于 2.1.0）；`mobile-v2.2.0` / `v2.2.0` / `2.2.0` 都能解析。
- 附件丢了（release 没挂 apk）时按钮退化成「打开发布页」，不会给了个空链接。
- 打开下载链接用了新依赖 `url_launcher`（系统浏览器开 apk 附件）。
  **故意不内置下载器**：内置下载要碰分区存储 / 安装权限那一堆坑，
  浏览器下载交给系统最省心。
- 测试：逻辑层 11 条（解析 / 比较 / 挑手机版 / check 四种结论，拉取函数注入、
  不联网）+ 界面 3 条（有新版弹窗 / 已最新不弹 / 失败给原因，检查器注入）。
  SettingsPage 加了 `checkUpdate` 注入钩子，和 pickZip / api 一个路数。


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

**2026-09-22 补记**：凯森又提了一次「图片导入」。给了三条路（半自动框选填名 /
全自动按颜色分割 + 整张识别 / 纯对照稿），他选了**先不做**——维持现状：
xlsx / PDF 导入 + 手动加课。以后除非他主动再提，别主动把这个方案端出来。

