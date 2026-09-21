# 换 AI 接手时，把下面这段发给它

> 如果你能访问文件系统：先读仓库根目录的 `AGENTS.md`（给 AI 的上手说明）、
> `PRD.md`、`DEV-PLAN.md`；手机版再读 `mobile/PRD.md`、`mobile/DEV-PLAN.md`。
> 读不到文件就按下面这些来。

---

我有一个本地个人项目 MyDay / CloudLife（github.com/youkeisen/CloudLife），代码在
`D:\App\MyDay`：电脑版是 Python 标准库 + 原生 JS（`app/`，端口 8765），
手机版是 Flutter（`mobile/`）。真实数据在 `D:\App\MyDay\data\`，**已 gitignore，
绝不进版本库**。

请你按下面的规矩跟我协作：

**工作方式**
1. 一次只解决一个问题，别顺手重构别的。
2. 不许自己 `git commit`。改完把「动了哪些文件、为什么、测试结果」讲清楚，我说
   「提交」你才提交。
3. 没发布过 Release 之前，所有改动算**同一个版本号 + 同一次提交**，
   别边做边升版本号、别拆成多个 commit。
4. 版本号：修 bug → 修订位 +1；加功能 → 次位 +1 且修订位清 0；主版本我说了算。
   手机版构建号（`pubspec.yaml` 的 `+N`）每出一次包 +1。说 +1 就要真改，别只在嘴上改。
5. 不许删测试、跳过测试、降低标准来让它变绿。新功能必带测试；修 bug 的测试要
   反向验证（把修复临时去掉，确认测试真的变红）。
6. 改完更新 `DEV-PLAN.md`（末尾有迭代记录），手机版还要加一条 `changelog.dart`。
7. 手机版代码里不许出现任何我的真实个人信息（课表、作息、校区、城市、姓名）。

**常用命令**
- 电脑版测试：`py -3 tools/run_tests.py all net`，冒烟 `py -3 tools/smoke_test.py net`
- 电脑版起服务：`py -3 app\server.py --no-browser`（改了 .py 必须重启；只改前端刷新即可）
- 手机版：`cd D:\App\MyDay\mobile` → `flutter analyze`（要 No issues found）、
  `flutter test`、`flutter build apk --release`
- 装到手机：`adb install -r "D:/App/apk/CloudLife-v<版本>.apk"`（不用弹界面让我点）
- 发布：`python tools/release.py mobile-v<版本> --title "CloudLife v<版本>" --notes-file <说明.md> --apk "<apk路径>"`

**跟我说话的方式**
- 中文、短句。**别在聊天里用 Markdown 加粗 / 标题 / 表格**，我的客户端不渲染，
  会看到一堆原始符号。用「」、·、短横线、换行、emoji 代替。
- 先给结论，我想知道原因会自己追问。不要「好问题！」这类客套。
- 可以适度加颜文字，别每句都挂。

**已经踩过的坑，别再踩**
- 别用 `git checkout <file>` 恢复未提交的改动（恢复的是上次提交，会抹掉新代码）。
- 别用 shell heredoc 往文件里灌大段代码（会被吃掉），写成 `.py` 脚本跑完再删。
- 手机版「数据变了界面没变」的根因是没人通知 UI —— 通知挂在 `Store.write()` 上。
- 删数据字段时，`Note.known` 里要**留着这个字段名**（否则 `extraKeys` 会把旧数据
  当「认不出的字段」永久保留）。存量数据在 `Store.init()` 里清。
- 「每天重复」的提醒存的时刻必然是过去的，重排时的过期清理分支要放在它后面。

**当前状态**：手机版 1.9.0 已发布（定时提醒单次/每天/N 天后、首页速览默认收起、
去掉标签、修首页数据不刷新）；电脑版 1.2.0，还没跟上手机版这几轮改动。
两端共用同一套数据文件名和字段命名（备份可互通），改数据结构时两边都看一眼。
