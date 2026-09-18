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

## 发布流程（凯森手动点发布）

1. 我跑 `flutter build apk --release`，把产出的 APK 放到他指定的目录（默认桌面临时目录）；
2. 他在 GitHub 上 CloudLife 仓库 → Releases → Draft a new release，打 tag（如 `mobile-v0.1.0`）、
   写上这版做了什么、把 APK 拖进附件，发布；
3. 他自己在手机上装（首次要允许「安装未知来源应用」）。

## 依赖（尽量少）

| 包 | 用途 | 阶段 |
| --- | --- | --- |
| `path_provider` | 拿手机应用私有目录，存四份 JSON | M1 |
| `archive` | zip 读写：备份导出/导入、xlsx 解压 | M1 / M7 |
| `file_picker` | 让用户选 zip / xlsx 文件 | M7 |

天气用 `dart:io` 的 `HttpClient`，不引额外网络包。日期时间用 `intl` 可视需要再加。

## 阶段划分

### M0 骨架与工具链（已完成）
- `flutter create --platforms android`，项目名 `my_day_phone`。
- 空模板 `flutter analyze` 无问题、`flutter test` 通过。
- 记下 `no_proxy` 这个坑。

### M1 数据层
- 数据模型：`Settings` / `Lesson` / `Period` / `Place` / `Note` / `WeatherCache`，
  字段名与电脑版 JSON **严格一致**（这是能和电脑版备份互通的前提）。
- `Store`：四份 JSON 的读写、原子写（写临时文件再 rename）、损坏文件改名留存并回落默认值。
- 默认值必须为空：periods 空、weatherCities 空、无示例课程。
- 测试：默认值为空、往返序列化、坏 JSON 自愈、原子写不产生半截文件。

### M2 界面骨架
- 底部 5 Tab + 顶部标题栏（含第几教学周）；深色浅色跟随系统。
- 空页面 + 每个页面的空态文案；`flutter test` 里用 widget test 断言五个 Tab 能切。

### M3 课程模块
- 周次切换、课表表格渲染（节次 × 星期）、点课块编辑、增删改。
- 整周复制三种策略、清空本周、节次缺失时的引导。
- 教学周计算算法与电脑版逐字一致，测试用同一天跨周边界的用例。

### M4 备忘录
- 列表（分组：全部/置顶/标签/归档 + 搜索）、详情编辑页。
- 笔记 / 清单两种形态，清单每条一行可输入可勾。
- 自动保存 + 保存键 + 「已保存 / 有改动…」状态；切走前补存。

### M5 天气
- Open-Meteo 取数与归一化（WMO 码中文映射、生活提示），离线降级用缓存。
- 「我的地点」增删切换；搜索城市走 geocoding。

### M6 首页聚合
- 今日课程（状态：已上/正在上/下一节）、今日天气、备忘录速览（可勾 + 可收放）。

### M7 设置与数据
- 基本设置、作息与节次、我的地点、外观。
- 备份导出 zip / 从备份导入 / 清空（强制先备份 + 二次确认）。
- **兼容电脑版备份**：字段名一致，能直接吃电脑版导出的 zip。

### M8 导入课表 xlsx
- 用 `archive` 解 zip，自己解析 `xl/worksheets/sheet1.xml` + `sharedStrings.xml`。
- 解析规则照搬电脑版（`timetable.py`）：格子里的多门课、周次范围与单双周、
  课程名与班级的切分、合并区重复存值只算一次。
- 先预览（不写数据）再导入，追加 / 覆盖二选一。

### M9 打包与真机验收
- `flutter build apk --release`，装到凯森手机上按 PRD 第 8 节过一遍。
- 需要他配合：装 APK、导一份电脑版备份进来、试一次导入课表。

## 风险

1. **文件选择与存储权限**：安卓 11+ 分区存储，导出备份要落到用户能找到的位置
   （可能要先落到 App 目录再引导用户分享/另存）。M7 里实测。
2. **中文字体**：安卓自带字体够用，但要确认表格里「中午1」这类混排不乱。
3. **大课表渲染**：7 列 × 12 行的表格在窄屏上要能横向滚动，字号要压得住。
4. **无真机时**：我只能靠 `flutter test` + `analyze` 保证逻辑正确，界面得凯森实机看。
