# MyDay 开发计划 v1（可直接执行）

> 依据：`PRD.md` v1 + 交互原型 `design/MyDay-prototype-v1.html`（v2 全自定义版）
> 目标：按本计划逐步实现，每个阶段结束都能跑起来验收，不会出现「写一半跑不了」的状态。
> 更新：2026-09-18

---

## 0. 总览

### 0.1 交付物清单

```
D:\App\MyDay\
├── 启动 MyDay.bat              双击启动（英文内容，避免 cmd 编码坑）
├── app\
│   ├── server.py               HTTP 服务 + 路由分发 + 启动自开浏览器
│   ├── store.py                数据读写层：原子写、默认值、损坏恢复
│   ├── weather.py              Open-Meteo 请求、归一化、WMO 映射、缓存
│   ├── backup.py               zip 备份 / 还原 / 清空
│   └── static\
│       ├── index.html          单页骨架（五页签）
│       ├── style.css           样式（沿用原型视觉）
│       └── app.js              前端全部逻辑
├── data\                       运行时生成
│   ├── settings.json
│   ├── courses.json
│   ├── notes.json
│   ├── weather_cache.json
│   └── backups\
├── tools\
│   └── smoke_test.py           接口冒烟测试（跑临时数据目录）
├── design\                     原型稿（已有）
├── PRD.md
└── DEV-PLAN.md                 本文件
```

### 0.2 执行顺序

| 阶段 | 内容 | 结束标志 |
| --- | --- | --- |
| 0 | 环境与骨架 | 双击 bat，浏览器自动打开空壳首页 |
| 1 | 数据层 | 四个 JSON 自动生成，读写原子、损坏可恢复 |
| 2 | 设置与节次管理 | 能改称呼、第一周日期，能增删节次并即时生效 |
| 3 | 课程模块 | 能排课、增删改、整周复制三种策略 |
| 4 | 备忘录 | 增删改、笔记/清单、置顶标签搜索归档 |
| 5 | 天气 | 选城市出实况+24h+7天，断网降级 |
| 6 | 首页聚合 | 三大块数据全部来自真实接口 |
| 7 | 备份还原 | 备份 zip、还原、清空全部数据 |
| 8 | 健壮性打磨 | 错误与空态全覆盖，冒烟测试通过 |
| 9 | 交付验收 | 按 PRD 第 10 节逐条打勾 |

> 建议每 1-2 个阶段停下来给凯森看一次，确认手感再往下。

### 0.3 运行约定

- Python 版本：3.9 以上（本机任意 Python 均可，只用标准库）。
- 所有源码文件统一 **UTF-8 无 BOM**；`server.py` 启动时执行 `sys.stdout.reconfigure(encoding='utf-8')`，避免中文日志乱码。
- 服务仅绑 `127.0.0.1`，端口从 **8765** 起，被占用则 +1 递增，最多试 10 个。
- 数据目录默认 `D:\App\MyDay\data`，支持覆盖以便测试：
  - 命令行参数 `--data <dir>`
  - 环境变量 `MYDAY_DATA`
  - 优先级：命令行 > 环境变量 > 默认目录
- 开发调试：`python app\server.py --data D:\App\MyDay\_devdata --no-browser`

---

## 1. 阶段 0：环境与骨架（T0）

### 任务

- **T0.1** 建目录：`app\`、`app\static\`、`data\backups\`、`tools\`。
- **T0.2** 写 `app/server.py` 骨架：
  - `argparse` 解析 `--data` / `--no-browser`
  - `ThreadingHTTPServer` + `BaseHTTPRequestHandler`
  - 路由分发表：`ROUTES = {(method, path): handler}`，静态文件走 `/` 与 `/static/*`
  - 启动成功打印 `MyDay running at http://127.0.0.1:<port>`，并 `webbrowser.open()` 自开浏览器（受 `--no-browser` 控制）
  - `Ctrl+C` 优雅退出
- **T0.3** 写 `app/static/index.html`：直接以原型 v2 为底稿，删掉所有假数据 script，改为 `<script src="app.js">`。
- **T0.4** 写 `app/static/style.css`：从原型 `<style>` 原样迁出。
- **T0.5** 写 `启动 MyDay.bat`（内容全英文）：

```bat
@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY (where python >nul 2>nul && set "PY=python")
if not defined PY (
  echo [MyDay] Python not found. Install Python 3 and add it to PATH.
  pause
  exit /b 1
)
echo [MyDay] starting...
%PY% "app\server.py"
echo [MyDay] stopped.
pause
```

> 若本机 `python` 指向 Python 2 或不可用，凯森可在 bat 第二行插入 `set "PY=D:\python\python.exe"` 指定解释器。

### 完成判定

双击 `启动 MyDay.bat` → 控制台打印端口 → 浏览器自动打开 → 看到侧边五个页签、可切换、页面无 JS 报错。

---

## 2. 阶段 1：数据层（T1）

### 数据 schema（照此实现，不要改字段名）

`settings.json`

```json
{
  "version": 1,
  "displayName": "",
  "semesterName": "",
  "week1Monday": "",
  "weekStartsOn": 1,
  "campus": "",
  "periods": [
    { "id": "p1", "label": "第 1-2 节", "start": "08:10", "end": "09:50" }
  ],
  "weatherCity": { "name": "", "latitude": null, "longitude": null, "timezone": "Asia/Shanghai" },
  "refreshMinutes": 30,
  "theme": "system"
}
```

`courses.json`

```json
{
  "version": 1,
  "weeks": {
    "1": [
      { "id": "c1", "day": 1, "slot": "p1", "spanEnd": "", "name": "高等数学",
        "location": "A 楼 302", "teacher": "", "note": "", "color": "" }
    ]
  }
}
```

`notes.json`

```json
{
  "version": 1,
  "notes": [
    { "id": "n1", "title": "", "type": "text", "body": "",
      "items": [], "tags": [], "pinned": false, "archived": false,
      "createdAt": "", "updatedAt": "" }
  ]
}
```

`weather_cache.json`

```json
{
  "version": 1,
  "fetchedAt": "2026-09-18T22:00:00+08:00",
  "city": { "name": "", "latitude": 0.0, "longitude": 0.0 },
  "payload": {}
}
```

### 任务

- **T1.1** `store.py`：`DEFAULT = {各文件默认结构}`；`ensure_files()` 首次启动创建缺的文件。
- **T1.2** `read(name)`：读 JSON；解析失败时把坏文件改名为 `<name>.corrupt-<时间戳>.json`，返回默认值，并在内存里置一个 `warnings` 列表供 `/api/bootstrap` 返回给前端提示。
- **T1.3** `write(name, obj)`：**原子写**——写入同目录 `<name>.tmp` → `os.replace()` 覆盖 → `flush + os.fsync`。所有写操作走这个函数。
- **T1.4** `load_lock`：用一个 `threading.Lock()` 包住读改写，避免并发写坏。
- **T1.5** 统一响应工具：`ok(data) → {"ok":true,"data":...}`、`fail(msg) → {"ok":false,"error":"..."}`，HTTP 状态码统一 200（错误放 body），避免前端 fetch 抛异常。
- **T1.6** 加 `GET /api/bootstrap`：返回 `{settings, weekMeta, warnings}`，给首屏一次拿齐。其中 `weekMeta` 含 `{todayISO, dow, week: number|null, weekOptions: 1..20}`。

### 教学周算法（放 `store.py`，前后端共用同一套逻辑）

```python
def week_of(date_iso, week1_monday):
    if not week1_monday: return None
    d = date.fromisoformat(date_iso)
    s = date.fromisoformat(week1_monday)
    delta = (d - s).days
    if delta < 0: return None
    return delta // 7 + 1
```

前端同样实现一份 `weekOf()`（JS），用于即时显示，服务端结果为最终权威。

### 完成判定

- 启动后 `data/` 下出现四个 JSON，内容为空默认结构。
- 手动往 `notes.json` 删一个 `}` → 重启服务 → 页面正常打开并出现「某个数据文件损坏，已恢复默认」提示；`data/` 下出现 `.corrupt-` 备份文件。

---

## 3. 阶段 2：设置与节次管理（T2）

### 任务

- **T2.1** `GET /api/settings` / `PUT /api/settings`：整体覆盖保存（前端传完整对象，简单可靠）。
- **T2.2** 前端设置页：称呼、学期名、第一周周一日期、周起始日、校区、外观主题、天气刷新间隔。改动即 `PUT`（输入框用 400ms debounce）。
- **T2.3** 节次管理 UI：列表每行「名称 + 开始时间 + 结束时间 + 删除 ×」，底部「+ 添加节次」。拖拽排序降级为「上移/下移」按钮（第一版够用，PRD 的拖动排序简化实现，需在交付说明里注明）。
- **T2.4** 节次 id 生成：`periods` 内自增 `p<n>`，避免重复。
- **T2.5** 删除节次保护：`DELETE /api/settings/period` 带 `{id, mode}`，服务端先统计被引用课程数：
  - 无引用 → 直接删
  - `mode=move` → 课程改挂到第一个剩余节次
  - `mode=drop` → 连同课程一起删
  - 返回 `{needConfirm:true, used:N}` 让前端弹二次确认
- **T2.6** 前端：`/api/bootstrap` 变化时重渲染课程表与首页。
- **T2.7** 「生成若干空白节次」按钮（本地 `for` 循环调用添加接口即可，不含任何真实作息数据）。
- **T2.8** 主题切换：CSS 变量 + `body[data-theme]`，先支持 light / dark 两态。

### 完成判定

添加两条节次 → 课程页立即出现两行；改时间 → 首页今日课程时间同步变化；删被占用节次 → 弹「有 N 节课用到它」的确认框并按选择处理；刷新页面全部保持。

---

## 4. 阶段 3：课程模块（T3）

### 接口

| 动作 | 请求 |
| --- | --- |
| 取周课表 | `GET /api/courses?week=3` → `{week, list:[...], total:N}` |
| 新增 | `POST /api/courses` body `{week, day, slot, spanEnd, name, location, teacher, note, color}` |
| 修改 | `PUT /api/courses` body 含 `id` |
| 删除 | `DELETE /api/courses` body `{id}` |
| 整周复制 | `POST /api/courses/copy` body `{from:4, to:[6,7,8], mode:"overwrite"\|"merge"\|"empty-only"}` |
| 清空某周 | `POST /api/courses/clear` body `{week}` |

### 任务

- **T3.1** 服务端写 `weeks` 字典，缺失的周补 `[]`。
- **T3.2** 三种复制策略实现：
  - `overwrite`：`target = deepcopy(src)`（新 id）
  - `merge`：保留目标原有 + 追加 src
  - `empty-only`：仅当目标周为空才写入
- **T3.3** 前端周次选择器（1-20）+「跳到本周」；本周按钮在未设置第一周日期时给出引导。
- **T3.4** 课程表渲染：列为周一至周日（受 `weekStartsOn` 影响），行为 `periods` 顺序；跨节次课 `rowspan` 用 `<td rowspan="2">` 实现，注意跳过被跨的行。
- **T3.5** 添加/编辑弹窗（复用原型），表单项：名称、星期、开始节次、跨到的节次（可选）、地点、老师、备注、颜色。
- **T3.6** 删除确认（弹窗内确认一次即可）。
- **T3.7** 本周课程数统计。
- **T3.8** 空态：无节次 → 「先去设置里添加节次」；有节次无课 → 「这一周还没有课」。
- **T3.9** 颜色：给 6 个预设色，课程块左侧色条。

### 完成判定

A 周加课、B 周看不到；任意两周课表互不影响；复制到三周且三种策略行为正确；跨节次课连续占两行；刷新后不变。

---

## 5. 阶段 4：备忘录（T4）

### 接口

`GET /api/notes`（全部，前端做过滤）/ `POST`（新建，返回带 id 的对象）/ `PUT`（整条更新）/ `DELETE`（`{id}`）。

### 任务

- **T4.1** 三栏布局：左分组（全部 / 置顶 / 各标签 / 归档）、中列表、右详情。
- **T4.2** 两种形态：`type=text` 多行 textarea；`type=todo` 清单（增行、勾选、删行、回车快速加一行）。
- **T4.3** 自动保存：详情区改动 500ms debounce 后 `PUT`，顶上显示「已保存」小灰字。
- **T4.4** 置顶 / 取消置顶、归档 / 还原、`DELETE`（二次确认）。
- **T4.5** 标签：详情区逗号分隔输入，前端拆成数组；左侧按标签聚合。
- **T4.6** 搜索：标题 + 正文 + 清单项文本，前端本地过滤即可。
- **T4.7** 列表默认隐藏 `archived=true`；归档分组可查看与还原。

### 完成判定

新建清单勾两项 → 显示 2/3 → 刷新仍在；置顶排最前；归档不进「全部」可在归档找回；搜索能命中清单项文字。

---

## 6. 阶段 5：天气（T5）

### 数据源与 URL（全部免 key）

```
实况与预报
https://api.open-meteo.com/v1/forecast
  ?latitude={lat}&longitude={lon}
  &current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m,surface_pressure
  &hourly=temperature_2m,precipitation_probability
  &daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max
  &timezone=Asia/Shanghai&forecast_days=7

城市搜索
https://geocoding-api.open-meteo.com/v1/search?name={关键词}&language=zh&count=8
```

### 任务

- **T5.1** `weather.py`：`fetch_raw(lat, lon)`，`urllib.request.urlopen(..., timeout=6)`，出错抛自定义 `WeatherError`。
- **T5.2** 归一化 `normalize(raw)` → 前端要的结构：

```json
{
  "current": {"temp":26.1,"feels":27.3,"code":3,"text":"多云","humidity":68,
              "wind":2.4,"windDir":135,"pressure":1008,"uv":0,"visibility":null,"precipProb":10},
  "hourly": [{"time":"22:00","temp":25.4,"pop":10}],
  "daily":  [{"date":"2026-09-18","code":3,"text":"多云","max":27,"min":21,"pop":10}],
  "city": {"name":"合肥","latitude":31.86,"longitude":117.28}
}
```

- **T5.3** `WMO_CODE` 中文映射表：`0 晴 / 1 大部晴朗 / 2 局部多云 / 3 阴 / 45,48 雾 / 51,53,55 毛毛雨 / 61,63,65 雨 / 66,67 冻雨 / 71,73,75 雪 / 77 米雪 / 80,81,82 阵雨 / 85,86 阵雪 / 95 雷阵雨 / 96,99 雷暴冰雹`；同时给一个图标名供前端渲染（纯 CSS/SVG，不用图片）。
- **T5.4** `GET /api/weather?refresh=1`：
  - 缓存新鲜（小于 `refreshMinutes`）且非强制 → 直接返缓存
  - 否则请求接口，成功写 `weather_cache.json` 再返回
  - 失败 → 有缓存返 `{ok:true, stale:true, fetchedAt, data}`，无缓存返 `{ok:false, error:"暂时取不到天气"}`
- **T5.5** `GET /api/cities?q=`：城市搜索；失败或为空时返回 `{ok:false}`，前端提供「手动填经纬度」兜底入口。
- **T5.6** 前端天气页：实况大卡（9 项指标）、24 小时柱状图（纯 div，高度按比例）、7 天列表。
- **T5.7** 生活提示规则（简单阈值）：昼夜温差 ≥ 8 度 → 「温差大，带件外套」；当前或未来 6 小时降水概率 ≥ 50% → 「出门带伞」；紫外线 ≥ 6 → 「注意防晒」。多条用顿号拼接。

### 完成判定

选城市出数据；关掉网络后开天气页显示上次数据并标注旧时间 / 或友好提示；改城市数据跟着变。

---

## 7. 阶段 6：首页聚合（T6）

### 任务

- **T6.1** 首屏只发一个 `GET /api/bootstrap`，随后并行 `GET /api/courses?week=<本周>`、`GET /api/notes`、`GET /api/weather`。
- **T6.2** 顶部状态行：问候（时间判断）+ 称呼 + 日期 + 星期 + 第几教学周 + 校区 + 今日课程数标签。未填第一周日期时显示「教学周未设置」并给跳转设置的链接。
- **T6.3** 今日课程块：
  - 排序按 `periods` 顺序
  - 时间状态：`now < start` 未来、`start ≤ now ≤ end` 正在（高亮 + 「正在上」）、`now > end` 已结束（灰）
  - 未来最近一节标「下一节」
  - 空态三种：无节次 / 未设第一周 / 今天没课
- **T6.4** 今日天气块：调用 T5 数据；未设城市与失败态各有占位。
- **T6.5** 备忘录速览：置顶优先 + 更新时间倒序取 3 条，点击跳备忘录页并选中该条（`sessionStorage` 传 id 即可，不落盘）。

### 完成判定

首页数据与三个模块实时一致；改任一处回首页刷新立即可见。

---

## 8. 阶段 7：备份、还原、清空（T7）

### 任务

- **T7.1** `GET /api/backup`：用 `zipfile` 打包含四个 JSON + `manifest.json`(`{version, exportedAt, appVersion}`)，文件名 `MyDay-backup-YYYYMMDD-HHMM.zip`，以二进制流返回，前端用 blob 下载到默认下载目录（也可弹保存框）。
- **T7.2** 同时服务端在 `data\backups\` 保留一份相同 zip（满足 PRD「能看到备份文件」）。
- **T7.3** `POST /api/restore`：前端 `<input type=file>` 读成 **base64 字符串**放进 JSON body，服务端解码后写临时 zip → 校验 manifest → 逐个覆盖数据文件 → 返回成功。**不用 multipart**，省掉手写解析。
- **T7.4** `POST /api/open-folder`：`os.startfile(data_dir)` 唤起资源管理器。
- **T7.5** `POST /api/reset-all`：先自动执行一次备份，再写入四个默认空数据，返回 `{backupFile: "..."}`。前端必须二次确认（输入框确认或直接确认按钮）。
- **T7.6** 启动时可选：当天首次启动自动备份一份，保留最近 10 份（清理旧文件）。

### 完成判定

备份出 zip → 清空 → 用 zip 还原 → 数据完全一致；清空前自动生成备份。

---

## 9. 阶段 8：健壮性与打磨（T8）

- **T8.1** 全局错误兜底：所有 `fetch` 包一层 `api()`，失败统一 toast，不弹原生 alert。
- **T8.2** 端口占用：启动失败自动换端口；把实际端口打印在控制台。
- **T8.3** 单实例：启动时写 `data\server.lock`（含 PID），检测到已有实例则提示并复用其端口提示。
- **T8.4** 静态资源缓存：`Cache-Control: no-cache`，避免改了 JS 不生效。
- **T8.5** 所有空态文案检查（课程无节次 / 无课、天气未设城市 / 失败、备忘录为空、搜索无结果）。
- **T8.6** 删除操作的二次确认统一用自定义弹窗（沿用原型样式）。
- **T8.7** `tools\smoke_test.py`：用 `urllib` 打一遍所有 API，跑 `--data` 指向的临时目录，断言：
  - 新建 → 读取一致
  - 改 → 落盘 JSON 内容正确
  - 复制周 → 三种策略数量正确
  - 备份 → 还原 → 数据一致
  - 损坏 JSON → 服务返回 warning 且文件被重命名
- **T8.8** 首屏性能：静态资源合并为 3 个文件即可，无外部 CDN 依赖；实测首次交互 < 1 秒。

---

## 10. 阶段 9：交付验收

按 PRD 第 10 节逐条执行，重点是这五条必测：

1. **重启数据不丢**：加几条课和笔记 → 关机重启 → 再启动，一条不少。
2. **不依赖 localStorage**：浏览器「清除浏览数据」全选后重开，数据还在。
3. **损坏可恢复**：手动改坏 `courses.json` → 启动不崩、有提示、可继续用。
4. **断网降级**：拔网线打开 App，除天气外全部正常。
5. **零预置检查**：用文本搜索整个项目（代码 + data），确认无真实课程名、教室编号、作息时间、校区、城市、姓名。

验收通过后交付给凯森的东西：目录清单 + 启动方式 + 一句话使用说明 + 「备份文件在哪」。

---

## 11. 风险与预案

| 风险 | 预案 |
| --- | --- |
| bat 找不到 Python | bat 依次试 `py -3` / `python`，都不行时提示；预留手工指定解释器路径的注释行 |
| 中文乱码 | 源码 UTF-8；`server.py` 重配置 stdout；bat 内容全英文 + `chcp 65001` |
| 端口被占 | 从 8765 递增尝试，控制台打印最终端口 |
| 天气接口超时/不通 | 6 秒超时，返缓存或友好提示；允许手动填经纬度绕开城市搜索 |
| open-meteo 城市搜索不准 | 支持手动输入经纬度并保存为自定义城市 |
| 写盘被杀软拦截 | 提示把 `D:\App\MyDay` 加入白名单；失败时给出明确错误而不是静默 |
| 重复双击导致多实例 | `server.lock` 检测，第二个实例提示已在运行 |
| JSON 并发写坏 | 全部走 `store.write()` 的原子写 + 线程锁 |

---

## 13. 实施记录（v1 开发完成时补充）

按本计划 T0-T9 全部实现完毕，测试情况：

```
python tools/run_tests.py            # 全部阶段（联网用例默认跳过）
python tools/run_tests.py all net    # 全部阶段 + 真实天气接口
python tools/run_tests.py 3          # 只跑阶段 3
python tools/smoke_test.py           # 独立冒烟脚本，打印中文清单
python tools/smoke_test.py net       # 冒烟 + 联网校验
```

最后一次全量结果：124 个用例，失败 0，错误 0，跳过 0（含联网用例）。

## 13.1 迭代记录

### 迭代 1（2026-09-19）：设置页天气栏的「我的地点」

问题：设置页 → 天气 →「城市」是个空的、点了没反应的下拉框，这个界面里没有任何添加地点的入口，只能靠手填经纬度。

改动：

1. `store.py`：设置新增 `weatherCities`（默认空列表，最多 20 条）；新增 `normalize_place` / `list_places` / `add_place` / `select_place` / `remove_place`。坐标相同视为同一地点（只更新名称），添加后立即成为当前城市；移除当前城市时顺位到第一个，列表空了就回到未设置。
2. `server.py`：新增 `GET/POST/DELETE /api/places`、`POST /api/places/select`。缺 id 走 400，未知 id 走 `not_found`，都不 500。
3. 前端：设置页天气卡片加「＋ 添加地点」（就地展开搜索框）+「我的地点」下拉 +「已保存」列表（逐条 × 移除）；手填经纬度也统一走添加地点；天气页选城市改为同一套接口，不再各自直写 `weatherCity`。
4. 测试：新增阶段 10（23 个用例）、冒烟脚本补 3 项；`run_tests.py` 的 STAGES 扩到 0-10。
5. 顺手修掉阶段 5 里一个「只在傍晚才会过」的假通过用例 `test_tips_umbrella`（原来靠 hourly 的偶然取值才满足），改成固定数据；并补了 hourly 触发和「温和天气不该给提示」两个用例。

全量结果：147 个用例，失败 0，错误 0，跳过 0（含联网用例）。

### 迭代 2（2026-09-19）：节次「+ 添加节次」点了不出东西

问题（凯森反馈）：点「添加节次」和「生成若干空白节次」都不出节次；并要求去掉批量生成，只留「添加节次」，点一下加一条。

查出来是三个叠加的 bug，都从 v1 一直存在：

1. `app.js` 末尾调用了从未定义的 `bootStage0();`，抛 ReferenceError 导致下一行的 `boot()` 执行不到——**整个 App 启动时根本没加载数据**，所以设置页看不到已有的 4 条节次（数据文件里其实有）。
2. `addPeriod()` 保存成功后只调 `renderPeriods()`，而它是从 `State.settings` 读的，状态没刷新，所以新节次画不出来（看起来「点了没反应」）。
3. 节次行里防抖保存的回调调用了未定义的 `render()`，改完名称/时间虽然存了，但后面重画时静默报错。

改动：

1. 删掉 `bootStage0();`，启动入口只剩 `boot();`。
2. `addPeriod()` 改为保存后 `reloadSettings()`（拉最新设置再重画），与 `movePeriod` / `removePeriod` 保持一致。
3. `render()` 改成 `reloadSettings()`。
4. 去掉「生成若干空白节次」按钮与 `genPer` 绑定，只保留「+ 添加节次」，点一下加一条空白节次；PRD 的节次规则同步改写。
5. 测试：新增阶段 11（18 个用例，含「一次请求只加一条」「连点 5 次正好 5 条」「重启后还在」和后端契约），并把 `run_tests.py` 的 STAGES 扩到 0-11；`test_stage8.py` 的元素清单去掉 `genPer`（需求变了）。

新增的一条通用防线：阶段 11 里加了静态扫描 `test_all_called_functions_are_defined`，把 `app.js` 里所有被调用的函数名和已定义的名字比对，专门防「render() / bootStage0() 这种未定义调用」——这类错误跑在 promise 里或启动路径上，不报错也不白屏，只表现为「点了没反应」，最容易漏。

全量结果：167 个用例，失败 0，错误 0，跳过 0（含联网用例）。

### 迭代 3（2026-09-19）：导入课表

需求（凯森）：加入导入课表功能，能直接吃教务系统导出的 xlsx。

先摸清表格形状：单张工作表，第 1 行标题（学校+学期）、第 2 行学号姓名、第 3 行表头
（时间 | 节次 | 星期一…星期日），第 4 行起一行一个节次；课程写在格子里，
格式 `课程名称(考核方式)(课程类别)专业班级{周次范围 教师 教室}`，
一格可能两门课（换行分隔），课程格普遍按两节纵向合并。

改动：

1. 新增 `app/timetable.py`（**只用标准库** zipfile + xml.etree，不引第三方库）：
   `read_xlsx` 读第一张工作表（兼容 sharedStrings / inlineStr、合并单元格），
   `parse_course_line` 拆课程名/班级/教师/教室/周次，`parse_weeks` 认 `4-17周`、
   `1,3,5周`、`1-17周(单)`，`parse_timetable` 把整张网格读成结构化课程。
2. 新增 `POST /api/import/preview`（只解析给预览，一字节都不写）与
   `POST /api/import`（先自动备份 → 建缺的节次 → 按周铺课程，模式 merge / overwrite）。
3. `store.py` 新增 `ensure_periods`（同名节次复用，时间一律留空——不替用户猜作息）
   与 `import_courses`（按周写入，支持追加/覆盖）。
4. 课程页加「导入课表」按钮：选 xlsx → 预览（多少条课程、覆盖哪些周、会新建哪些节次、
   跳过了什么）→ 选追加/覆盖 → 导入 → 跳到导入涉及的第一周。
5. 测试：`fixtures.py` 加合成 xlsx 生成器（手写 zip + XML，全部虚构内容，不用真实课表文件）；
   新增阶段 12（52 个用例）；`run_tests.py` 扩到 0-12；冒烟脚本加导入校验。

开发中被真实课表抓出的两个解析缺陷（合成数据里没有，拿凯森那份真表一跑就露）：

1. 那份课表把合并区的值在每个格子里**都存了一遍**，被读成两遍——周二 1-2 节变成了
   1-2 和 2-2 两条。修法：算出被合并盖住的格子跳过，另做一份「和 Excel 显示一致」的网格
   用来继承节次标签。测试里专门加了一组「合并区重复存值」的用例（`timetable_xlsx_filled`）。
2. 课程名和班级之间没有分隔符，纯靠正则猜边界会把「电气自动化技术251」切成「动化技术251」。
   改成优先用括号标注当分界（最后一个 `)` 后面剩下的就是班级），没有括号时才退回从末尾往前找。

真表验证：35 条课程记录、191 节课、覆盖 1-18 周、12 个节次，与已知课表逐条对得上，
无解析告警。

全量结果：219 个用例，失败 0，错误 0，跳过 0（含联网用例）。

### 迭代 4（2026-09-19）：备忘录加保存键 + 修「未分类」这个误导标签

问题（凯森反馈的截图）：
1. 备忘录编辑区没有保存键，想要一个。
2. 左边列表显示「未分类」，但这条笔记的类型明明就是「笔记」——那行原本是拿「标签」当类别显示，
   没标签就写「未分类」，看着像这条没归过类。

查代码时还顺手发现两个连带问题：

- 自动保存只更新了内存里的 State，**没刷新左边列表**，所以改完标题列表还显示「无标题」；
  但整块重画会导致输入框掉焦点，所以不能简单调 renderNotesList。
- 边打字边点左边另一条时，待执行的自动保存会对**新选中的那条**执行，刚敲的内容直接丢。

改动：

1. `renderNoteDetail` 里的操作行最前面加「保存」键（主按钮）+ 状态文字，
   点保存会先 `clearTimeout` 取消待执行的自动保存，再立刻存一次。
2. 状态文字在「有改动…」和「已保存」之间切换（`noteDirty` + `renderNoteStatus`）。
   自动保存保留（停手 0.5 秒存一次），手动保存只是立刻落盘，两条路都在。
3. 新增 `noteSubLine(n)`：列表第二行改成「**类型 · 标签 · 摘要**」，
   类型写「笔记 / 清单」，没标签就不再显示「未分类」。首页速览同样处理
   （为此 `api_home` 的 notesPreview 多带一个 `type` 字段）。
4. 新增 `refreshNoteRow(saved)`：存完只更新列表里那一行，不重建编辑区，输入框不掉焦点。
5. 切换备忘录前先 `clearTimeout` + `saveCurrentNote`，把没落盘的改动补上再切。
6. 测试：新增阶段 13（16 个用例），`run_tests.py` 扩到 0-13。

全量结果：235 个用例，失败 0，错误 0，跳过 0（含联网用例）。

### 迭代 5（2026-09-19）：清单每条能看清、能打字

问题（凯森反馈的截图）：清单里每条只剩一个小方块和一个 ×，内容框看不见也打不进字；
并要求内容排在「清单」这两个字的下面。

根因在 CSS：`.field input,.field select,.field textarea{width:100%}` 这条把勾选框和内容框
都撑成 100% 宽，三个元素（勾选框 / 内容框 / 删除键）挤在一个 flex 行里抢宽度，
内容框被压到 0 宽——所以看着「没法输入」。

改动：

1. `.field input[type=checkbox]` 写死 16×16、`flex:none`、`accent-color`，
   不再吃 `width:100%`（选择器权重比 `.field input` 高，压得住）。
2. `.todoitem input[type=text]` 显式 `width:auto` + `flex:1` + `min-width:0`，
   吃掉剩下的宽度。
3. `.todoitem .del` 固定 26×26 且 `flex:none`；`#todoList` 加一点上边距，
   整块就老实待在「清单」标签下面，左对齐。
4. 内容框加 placeholder（空行也有提示，不再看不出哪里能打字）。

测试：新增阶段 14（11 个用例），把 style.css 当结构化文件解析，
直接断言「复选框不是百分比宽」「内容框 width:auto + flex:1」「覆盖规则的选择器权重
确实高于 `.field input`」以及标记顺序（`<label>清单</label>` 必须在 `#todoList` 之前）。
`run_tests.py` 扩到 0-14。

全量结果：246 个用例，失败 0，错误 0，跳过 0（含联网用例）。

### 迭代 6（2026-09-19）：首页速览里显示清单内容与勾选

需求（凯森）：首页那张「备忘录速览」卡片，清单型笔记要能看到每一项的内容和勾没勾。

改动：

1. `api_home` 的 notesPreview 每条多带 `items`（前 `PREVIEW_ITEMS`=6 项，含 text 与 done）、
   `moreItems`（没显示出来的项数）、`itemsDone` / `itemsTotal`；笔记型就是空数组。
   条数上限也提成常量 `PREVIEW_NOTES`。
2. 首页速览改成块状渲染：标题行下面摊开清单项，未勾的是空心方框，勾过的实心打勾并加删除线；
   超过 6 项显示「… 还有 N 项」。点勾选框直接勾，点整条其它地方照旧跳备忘录。
3. 新增 `POST /api/notes/toggle`（`store.toggle_note_item`）：**只翻转指定序号的那一项**。
   这一步是必须的——首页只带了前 6 项，如果照旧整段回写 `items`，
   第 7 项之后的清单项会被静默删掉（测试 `test_toggle_does_not_lose_the_tail` 专门守这个）。
4. 勾选后首页的 x/y 摘要与「还有 N 项」按服务端返回的完整数据校正；失败回滚界面状态。
5. 顺手把前端静态检查用的小工具（`fn_body` / `css_rules` / `decls_for` / `specificity` /
   `read_static`）从各阶段测试里提到 `helpers.py`，避免每个阶段复制一份。
6. 测试：新增阶段 15（18 个用例），`run_tests.py` 扩到 0-15。

全量结果：270 个用例，失败 0，错误 0，跳过 0（含联网用例）。

### 迭代 7（2026-09-19）：首页速览加正文 + 收放小三角

需求（凯森）：笔记的正文也要加到首页速览里；正文和清单都要有一个像小三角那样的收放开关。

改动：

1. notesPreview 每条再带 `body`（服务端截到 200 字）和 `bodyCut`（有没有被截），
   清单那部分不变。
2. 首页速览每条改成「标题 + 小三角」的头部 + 可收放的详情区：
   - 小三角用 CSS 画的细箭头，展开时朝下、收起时朝右（`.caret` / `.caret.closed::before`）；
   - 详情区里先放正文（`.homeBody`，最多 4 行，超出省略），清单型的再放清单项；
   - 收起时详情区 `display:none`，只剩标题和摘要，卡片能一直保持紧凑。
3. 收放状态放在模块级的 `homeNoteOpen`（按备忘录 id 记），默认展开；
   勾选清单或重画速览都不会把它重置。
4. 点小三角、点勾选框都 `stopPropagation`，不会误跳到备忘录页；点整条其它地方照旧跳。
5. 测试：新增阶段 16（18 个用例），`run_tests.py` 扩到 0-16。

全量结果：286 个用例，失败 0，错误 0，跳过 0（含联网用例）。

对计划的几处实际调整：

1. 节次「拖动排序」改为「上移 / 下移」按钮（第一版够用，理由同计划里的预案）。
2. 新增 `--port-file` 参数：把最终端口写入文件，方便测试确定端口，也让双击启动时能判断实例是否已存在。
3. 新增单实例锁 `data/server.lock`：同一份数据目录重复启动时，提示已在运行并退出，不再抢端口。
4. 还原接口用 base64 JSON 传 zip，避开手写 multipart 解析。
5. 首页聚合抽出纯函数 `compute_lesson_states(lessons, periods, now_min)`，状态与排序可脱离真实时间做单元测试（避免跨零点抖动）。
6. 计划里的 `tools/smoke_test.py` 已实现为独立脚本，同时阶段 9 会调用它验收。

### 迭代 8（2026-09-19）：网页版也加上 PDF 导入 + 定位添加地点

对应手机版 v1.2.0 的同一批功能。

1. **课表导入支持 PDF**：新增 `app/timetable_pdf.py`（依赖 pypdf，本机已装：
   `py -3 -m pip install pypdf`）。思路同手机版：pypdf 的 visitor 拿带坐标的文字 →
   认星期方向（这份是转置布局）→ 按天分组 → 按左边缘聚簇重建格子 →
   「(起-止节)」标记切课程块。`server.py` 按 %PDF 魔数分流（xlsx 走原路），
   前端 `accept` 改成 `.xlsx,.pdf`。
   用真实课表 PDF 本地验证：18 门课全解析，节次 / 周次 / 教室都对；
   **老师名偶尔会粘到下一条课的名字上**（相邻格文字在 PDF 里没有分隔），
   导入预览里核对一下即可。
2. **定位添加地点**：设置 → 天气 → 「定位添加」。浏览器 `navigator.geolocation`
   拿坐标 → 新接口 `POST /api/places/locate` → `weather.reverse_geocode()`
   （Nominatim 反查，带 User-Agent）→ 直接加入我的地点。127.0.0.1 是安全上下文，
   浏览器允许定位。
3. 节次时间选择器：网页版本来就是 `<input type="time">`，不用改。
4. 顺带修：禁词守卫（阶段 8）拦到注释里写了凯森的名字，改成中性描述。

全量结果：289 个用例，失败 0，错误 0，跳过 0（含联网用例）。

开发中被测试抓出并修掉的真实缺陷：更新课程时把旧数据写回（同周修改无效）、Windows 的 SO_REUSEADDR 导致两个实例抢同一端口、天气接口返回无时区时间与本地时间比较崩溃、id 用毫秒生成在快速连点时重复、首页课程只按节次顺序而非实际时间排。

---

### 迭代 9（2026-09-22）：去掉标签 + 首页速览默认收起（对齐手机版 v1.9.0）

凯森 2026-09-22：「你把电脑版的补一下」。手机版这几轮改了什么，电脑版就补什么 ——
这一批补**界面能直接对齐的两件**（他说「先对齐界面」）：

1. **去掉备忘录标签，连数据一起清**（和手机版同一套做法）：
   - 分组不再生成 `tag:xxx`，只剩「全部 / 置顶 / 归档」
   - `filteredNotes` 去掉 `tag:` 分支（认不出来的键走兜底，返回全部）
   - `noteSubLine` 副标题不再拼标签
   - 编辑页删掉「标签（逗号分隔）」输入框和它的 input 监听
   - 保存请求、新建笔记都不再带 `tags`
   - `store.py`：`add_note` 不再写 `tags`，`update_note` 的字段白名单去掉 `tags`
     （**客户端硬塞 tags 进来也不写**，老页面缓存可能还会发）
   - 新增 `drop_legacy_note_tags()`，在 `init()` 里跑：扫一遍 notes.json，
     有残留才重写。只靠「不再解析」是清不掉存量数据的 —— 用户没编辑过的
     笔记不会重写文件，那些字段会一直躺着。
2. **首页速览内容默认收起**：`homeNoteOpen[n.id] !== false` → `=== true`，
   表里只记「用户手动展开过的那几条」。首页那行标签显示改成只显示类型。

版本 1.2.0 → **1.3.0**（改了功能，次位 +1）。

测试 `tools/tests/test_stage17.py`（15 个用例，已加进 `run_tests.py` 的 STAGES）：
- 后端 4 条：新建不带 tags、更新忽略客户端塞的 tags、落盘文件里没 tags
- 存量清理 3 条：启动时清掉、没残留不重写文件（比 mtime）、坏文件不崩
- 前端 8 条（静态检查，JS 没法在 Python 里跑）：分组/筛选/副标题/编辑框/
  保存请求/新建请求都不含标签，速览默认收起、显示类型而不是标签，
  以及「整个 app.js 里除了首页顶部那个教学周圆牌（`hometags`）不该再出现 tags」

两条关键守卫都**反向验证过**：把 `drop_legacy_note_tags()` 从 `init()` 里注释掉、
把速览改回 `!== false`，对应测试各自变红，恢复后绿。

写测试时踩了个小坑：断言 `assertNotIn('tag:', ...)` 被自己注释里那句
「认不出来的分组键（比如旧数据里的 tag:xxx）」命中了 ——
**静态检查的断言要具体到代码本身**（改成断言 `indexOf('tag:')`），
别断言一个会出现在注释里的短词。

---

## 12. 建议的日常使用方式（写进交付说明）

1. 双击 `启动 MyDay.bat`，浏览器自动打开，控制台窗口开着别关（关了服务就停）。
2. 想换台继续用：把整个 `D:\App\MyDay\data` 拷走，或直接在设置里备份 zip。
3. 每周换课前，在课程页把本周复制到下周，个别调课单独改。
