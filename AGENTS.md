# AGENTS.md — 接手这个项目前先读

给 AI 助手看的（人也可以看）。读完这份 + `PRD.md` + `DEV-PLAN.md` 就能接着干，
不用再问一遍背景。

## 0. 刚接手的话，照这三步走

1. 读这份文件；电脑版再读 `PRD.md`、`DEV-PLAN.md`，手机版再读 `mobile/` 下那两份。
2. **先看有没有现成的 skill**：这台机器上有两个专门为这个项目写的——
   `myday-iterate`（做一轮迭代的完整流程和坑）和 `flutter-android-build`
   （Flutter/安卓环境、装机、发布）。**动手之前先加载它们**，
   里面全是踩过的坑，能省一大圈弯路。
3. 跑一遍测试确认环境是好的：
   - 电脑版：`py -3 tools/run_tests.py all net`、`py -3 tools/smoke_test.py net`
   - 手机版：`cd mobile` → `flutter analyze`（要 No issues found）、`flutter test`
4. 然后等凯森派活，**一次一件**。

下面这些是「文件里写不全、得当面交代」的，现在补在这里：

- **`data/` 是真实数据**：别删、别提交、别拷进项目目录、别拿去写测试。
- **手机版是他每天在用的那个**，电脑版算备用。电脑版的笔记目前是空的，
  所以那边没什么数据可验（别以为改坏了）。
- **他说「提交」之前不要 commit。** 他**经常改主意**（同一件事可能连着改两三版），
  按最新的来就行，别把上一版当规格、别嫌返工。
- **环境**：flutter 在 `D:\dev\flutter\bin`，adb 在 `D:\dev\Android\sdk\platform-tools`，
  Python 一律 `py -3`。（细节见第 4 节。）
- **发布不用配令牌**：`tools/release.py` 现从 git 凭据管理器取，
  能 `git push` 的环境就能发 Release。但要用这台机器上能用的那个 git。

---

## 1. 这是什么

凯森（芜湖上学）的**本地个人生活助手**，叫 MyDay / CloudLife。两个端：

| | 电脑版 | 手机版 |
|---|---|---|
| 技术 | Python 3 标准库 + 原生 JS（无框架） | Flutter（Dart） |
| 代码 | `app/`（`server.py` 起本地服务，端口 8765） | `mobile/` |
| 需求文档 | `PRD.md` | `mobile/PRD.md` |
| 开发计划 + 迭代记录 | `DEV-PLAN.md` | `mobile/DEV-PLAN.md` |
| 版本号在 | `app/server.py` 的 `APP_VERSION` | `mobile/pubspec.yaml` 的 `version:` |
| 当前版本 | 1.3.0 | 1.9.0 |

功能：课表（含 xlsx/pdf 导入）、天气、备忘录、记账、设置与备份。
仓库：https://github.com/youkeisen/CloudLife

**两边版本号是独立的**，各按各自的节奏走，不要求同步。

### 数据在哪（重要）

- 真实数据在 `D:\App\MyDay\data\`（`courses.json` / `notes.json` / `settings.json` /
  `weather_cache.json` / `backups/`）。
- **这个目录已 gitignore，绝对不许进版本库、不许拷进项目目录、不许写进测试。**
- 凯森的真实课表 xlsx 在 `D:\下载`，只能本地验证用，同上。

---

## 2. 铁律（违反会被打回）

1. **一次只解决一个问题。** 他一次提一件，你做一件；别顺手重构别的。
2. **不要自己 `git commit`。** 改完把「动了哪些文件、为什么、测试结果」讲清楚就行。
   只有他明确说「提交」才提交。
3. **没发布之前的所有改动 = 同一个版本号 + 同一次提交。**
   判断标准是**有没有对外发过 Release**，不是「本地打过几个包」。
   别边做边升版本名、别一轮功能拆成多个 commit。
   （已经推上去过又要收回，就 `git reset --soft <base>` 合成一次再
   `git push --force-with-lease`，**别用 `-f`**，并跟他讲清楚改写了远端历史。）
4. **版本号规则**：起步 `主.次.修订`。修 bug → 修订 +1；加功能 → 次 +1 且修订清 0；
   **主版本由他决定，别动**。构建号（手机版 `+N`）每出一次安装包 +1。
   说「+1」就必须真的改 `pubspec.yaml` / `APP_VERSION`，出包前对一眼。
5. **零预置原则**：App 代码里不许出现任何真实个人信息（真实课表、作息、校区、
   城市、姓名）。默认值一律为空。
6. **不许删测试、跳过测试、降低验收标准来让它变绿。**
   新功能必带测试；修 bug 的测试要**反向验证**（把修复临时去掉，确认测试真的变红）。
   功能被删掉时，对应的测试可以删——但要说明理由。
7. **改完更新文档**：`PRD.md` / `DEV-PLAN.md`（DEV-PLAN 末尾有「迭代记录」）。
   手机版改完还要在 `mobile/lib/changelog.dart` 加一条面向用户的说明。

---

## 3. 一轮迭代的标准动作

```
定位问题（读代码/复现）
  → 改代码（一次只解决一个）
  → 加测试
      · 电脑版：新建 tools/tests/test_stageN.py，并把它加进 tools/run_tests.py 的 STAGES
        （现在 STAGES = 0..16，下一个就是 test_stage17.py）
      · 手机版：写进 mobile/test/ 里对应的文件
  → 全量跑通
  → 改 PRD.md / DEV-PLAN.md（+ changelog.dart）
  → 讲清楚改动，等他确认
```

他说「解决一下问题 / 功能添加」时走这套。**别跳步。**

---

## 4. 环境事实（这台机器上实测过的）

| 东西 | 在哪 / 怎么用 |
|---|---|
| Flutter | `D:\dev\flutter\bin\flutter`（3.47.4 stable），已在 PATH |
| adb | `D:\dev\Android\sdk\platform-tools\adb`，已在 PATH |
| Python | 一律用 `py -3`（不是 `python`） |
| PDF 导入依赖 | `pypdf`（6.x，本机已装；缺了用 `py -3 -m pip install pypdf`） |
| 手机 | USB 打开调试，`adb devices` 看得到就能装。包名 `com.youkeisen.my_day_phone` |
| git | 用**当前 PATH 里的 git**；这台机器上是 WorkBuddy 自带的 PortableGit |

**发布用的 GitHub 令牌不在任何配置文件里** —— `tools/release.py` 是现从
`git credential fill` 取的（即 Windows 凭据管理器）。所以：
**能 `git push` 的环境就能发 Release**，不用另配 token。
反过来，如果换了另一个 git（系统装的），凭据库里可能没有，`release.py` 会报
「拿不到 GitHub 令牌」。这时候用原来那个 git 就行。

**git push 的证书坑已经修好了**（写进了全局 git 配置，直接 push 即可）：
之前报 `schannel: CRYPT_E_NO_REVOCATION_CHECK` 是因为 PortableGit 自带的
ca-bundle 不含系统根证书，已改用从 Windows 证书库导出的 PEM。
如果换机器又遇到，别怀疑网络，照这个思路修。

## 5. 技术速查

### 电脑版

```bash
py -3 tools/run_tests.py all net      # 全量测试
py -3 tools/smoke_test.py net         # 冒烟
py -3 app\server.py --no-browser      # 起服务（端口 8765）
```
- **改了 `.py` 必须重启服务**；只改前端（`app/static/`）不用重启，刷新即可。

### 手机版

```bash
cd D:\App\MyDay\mobile
flutter analyze                       # 必须 No issues found
flutter test                          # 全量测试
flutter build apk --release           # 出包
```
- 包产物：`build/app/outputs/flutter-apk/app-release.apk`，
  拷成 `D:\App\apk\CloudLife-v<版本>.apk`。
- **装到手机**（推荐，不用他点确认）：
  ```bash
  adb install -r "D:/App/apk/CloudLife-v1.9.0.apk"
  adb shell dumpsys package com.youkeisen.my_day_phone | grep -m1 versionCode
  ```
  （用 `am start ... file:///...apk` 弹安装界面也行，但 vivo 上拉几次就失灵。）
- 手机没有真机时：`flutter analyze` + `flutter test` 就能验绝大部分逻辑。

### 发布（手机版）

```bash
cd D:\App\MyDay
python tools/release.py mobile-v<版本> \
  --title "CloudLife v<版本>" \
  --notes-file <写好的说明.md> \
  --apk "D:/App/apk/CloudLife-v<版本>.apk"
```
- **千万别加 `--commit`**（那个参数会去动源码，是给自动化用的，手工发布不要碰）。
- 标题不要写「手机版」三个字。
- 发完验证：Release 不是 draft、attachment 大小、下载地址 HEAD 200。

---

## 6. 已知的坑（都踩过，别再踩）

**通用**

- **别用 `git checkout <file>` 去「恢复」还没提交的改动** —— 它恢复的是**上次提交**的版本，
  会把新写的代码一起抹掉。要撤销就反向操作一遍，或者先 `git stash`。
- **别用 Bash 的 heredoc 往文件里灌大段 Dart/JS 代码** —— shell 会吃掉，报
  `unexpected EOF while looking for matching '`。写成 `.py` 脚本文件跑完再删，或者用编辑工具。

**手机版**

- 「数据变了界面没变」的根因几乎都是**没人通知 UI**，不是数据没更新。
  这个项目里通知挂在 `Store.write()`（所有落盘的唯一总入口），
  别在每个 `saveXxx` 里各写一遍。**「切一下页面就好了」是巧合不是修复。**
- 模型不再解析某个字段 ≠ 文件里的旧数据会消失。
  `Note.known` 是给 `extraKeys()` 用的：**不在 known 里的键会被当「认不出的字段」
  收进 `extra` 再原样写回**。所以要删字段时，**字段删掉、名字留在 known 里**，
  否则旧数据会被永久保留。存量数据在 `Store.init()` 里清。
- 「周期性数据 + 过期清理」要小心顺序：每天重复的提醒存的时刻**必然是过去的**，
  而重排每次启动都跑 —— 清理分支必须放在「过期就撤」**之前**。
- `flutter_local_notifications` 在桌面测试里没有插件，调用会抛异常。
  排程参数用 `NotificationService.debugLastSchedule` 断言，别指望真排成功。
- 测试里点界面前要确认控件真的在树上（默认收起的内容不在树上，`tap` 会失败）。

---

## 7. 怎么跟他说话

- **中文，短句。** 不要在聊天里用 Markdown 加粗 / 标题 / 表格 —— 他的客户端不渲染，
  会看到一堆原始符号。用「」、·、短横线、换行、emoji 代替。
- **先给结论**（比如「好玩」/「不好玩」/「别去」），他想知道原因会自己追问。
- 不要「好问题！」「乐意效劳！」这类客套，直接办事。
- 可以适度加颜文字（(๑•̀ㅂ•́)و✧、(￣▽￣)、(๑´ㅂ`๑) 之类），别每句都挂。
- 汇报时说清楚：**动了哪些文件、为什么这么改、测试结果、还剩什么没做**。

---

## 8. 现在到哪了

- 手机版 **1.9.0 已发布**（tag `mobile-v1.9.0`）：定时提醒（单次/每天/N 天后）、
  首页速览默认收起、去掉标签（含数据）、修了首页数据不刷新。
- 电脑版 **1.3.0**：刚把「去掉标签（含数据）+ 首页速览默认收起」补上（和手机版对齐）。
  **还没跟上的**：定时提醒（电脑版压根没有这个功能）、首页数据不刷新那个修复
  （电脑版每次操作都会重画，没这个问题）。
- 两端共用同一套数据文件名和字段命名（备份可互通），
  所以改数据结构时**两边都要看一眼**。之前去掉标签就是两边都改了
  （连存量数据的清理逻辑也各写了一份）。
