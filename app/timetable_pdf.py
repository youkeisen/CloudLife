# -*- coding: utf-8 -*-
"""课表导入（PDF 版，电脑版）：解析教务系统导出的课表 PDF。

思路和手机版 `mobile/lib/pdf_timetable.dart` 一致：
1. 用 pypdf 按坐标提取文字（visitor_text 拿到每个文字片段的 x/y）；
2. 认出「星期一…星期日」的位置判断表格方向：
   - 经典布局：星期是列（沿 x 铺开），节次行在左侧；
   - 转置布局：星期是行（沿 y 铺开），节次是横着的列（有些学校的导出就是这种）；
3. 文字按天分组，再按 x 聚簇重建格子（同一格的换行文字中心几乎重合）；
4. 每格用「(起-止节)」标记切课程块，起止节直接取标记里的数字。

返回的结构和 `timetable.parse_timetable()` 完全一致，下游（预览/落库）
不用分叉。
"""
import io
import re

import timetable as tt

# 课程块里的「(起-止节)」标记
MARKER = re.compile(r'[(（]\s*(\d+)\s*(?:[-–]\s*(\d+)\s*)?节[)）]')


# 课表读不出来时抛这个，和 timetable.TimetableError 是同一个，上层统一处理
TimetableError = tt.TimetableError


def looks_like_pdf(raw):
    return bool(raw) and raw[:4] == b'%PDF'


def _items_with_position(raw):
    """提取 [(文字, x, y, 宽度)]；pypdf 的 visitor 回调给文字片段 + 变换矩阵 + 字号。

    宽度按「字数 × 字号」估（课表基本是中文，一个字约一个字宽），
    用来判断同一格的换行文字是否属于同一个格子（它们的横向区间相互嵌套）。
    """
    try:
        from pypdf import PdfReader
    except ImportError:
        raise TimetableError('这台电脑上还没装 pypdf，先执行：py -3 -m pip install pypdf')

    try:
        reader = PdfReader(io.BytesIO(raw))
        items = []

        def visitor(text, cm, tm, font_dict, font_size):
            if text is None:
                return
            t = str(text).strip()
            if not t:
                return
            size = float(font_size or 10)
            width = len(t) * size * 0.8
            items.append((t, float(tm[4]), float(tm[5]), width))
        for page in reader.pages:
            try:
                page.extract_text(visitor_text=visitor)
            except TypeError:
                # 老版本 pypdf 的 visitor 签名不同：退回纯文本（没有坐标就认不出网格）
                plain = page.extract_text() or ''
                for line in plain.split('\n'):
                    if line.strip():
                        items.append((line.strip(), 0.0, 0.0, len(line) * 8.0))
        return items
    except TimetableError:
        raise
    except Exception as exc:
        raise TimetableError('PDF 内容读不出来：%s' % exc)


def _day_of(text):
    return tt.day_of(text)


def parse_pdf_timetable(raw):
    if not looks_like_pdf(raw):
        raise TimetableError('这个文件不是 PDF。请用教务系统导出的课表 PDF 再试')
    items = _items_with_position(raw)
    if not items:
        raise TimetableError('这份 PDF 里没有提取到文字，可能是扫描件，暂时导不了')

    # ---------- 星期词的位置：决定表格方向 ----------
    day_pos = {}
    for text, x, y, w in items:
        d = _day_of(text)
        if d is not None and d not in day_pos:
            day_pos[d] = (x, y)
    if not day_pos:
        raise TimetableError('没认出课表的表头：PDF 里要有「星期一…星期日」这些列')
    xs = [p[0] for p in day_pos.values()]
    ys = [p[1] for p in day_pos.values()]
    transposed = (max(ys) - min(ys)) > (max(xs) - min(xs))

    # 星期行/列的几何：按位置分带
    def axis(p):
        return p[1] if transposed else p[0]
    bands = sorted(((axis(pos), day) for day, pos in day_pos.items()),
                   key=lambda e: e[0])
    half_gap = abs(bands[1][0] - bands[0][0]) / 2 if len(bands) > 1 else 100.0

    def day_of_position(p):
        for i, (b, day) in enumerate(bands):
            top = bands[0][0] - 100 if i == 0 else (bands[i - 1][0] + b) / 2
            bottom = b + half_gap if i == len(bands) - 1 else (b + bands[i + 1][0]) / 2
            if top <= p < bottom:
                return day
        return None

    # ---------- 节次编号 ----------
    numbers = [(x, y, t) for t, x, y, w in items if _is_number(t)]
    min_day_y, max_day_y = min(ys), max(ys)
    min_day_x = min(xs)
    if transposed:
        outside = [w for w in numbers if w[1] < min_day_y - 20 or w[1] > max_day_y + 20]
        groups = {}
        for x, y, t in outside:
            groups.setdefault(round(y / 25), []).append((x, y, t))
        best = max(groups.values(), key=len) if groups else []
        if not best:
            raise TimetableError('没找到节次列，确认一下是不是课表 PDF')
        best.sort(key=lambda w: w[0])
        cols = []
        for x, y, t in best:
            if not cols or abs(x - cols[-1][0]) > 5:
                cols.append((x, t))
        labels = [t for _, t in cols]
    else:
        left = sorted([w for w in numbers if w[0] < min_day_x], key=lambda w: w[1])
        labels = []
        for x, y, t in left:
            if not labels or abs(y - (left[len(labels) - 1][1] if labels else y)) > 2:
                labels.append(t)
        labels = sorted(set(labels), key=lambda s: float(s))
    if not labels:
        raise TimetableError('没找到节次编号，确认一下是不是课表 PDF')
    number_label = {s: s for s in labels}

    # ---------- 按天分组 ----------
    day_items = {}
    for text, x, y, w in items:
        day = day_of_position(y if transposed else x)
        if day is None:
            continue
        day_items.setdefault(day, []).append((x, y, w, text))

    courses = []
    warnings = []
    for day in sorted(day_items):
        # 按左边缘聚簇重建格子：教务系统的课表格子是左对齐的，
        # 同一格的换行文字左边缘完全重合，邻格的左边缘至少差一个列宽。
        group = sorted(day_items[day], key=lambda e: e[0])
        clusters = []
        cur_left = None
        for x, y, w, text in group:
            if cur_left is None or x > cur_left + 8:
                clusters.append([(x, y, text)])
                cur_left = x
            else:
                clusters[-1].append((x, y, text))
        for cluster in clusters:
            # pypdf 的 y 轴向上增大，所以从大到小排才是「从上往下」的阅读顺序：
            # 先课程名，再 (起-止节) 详情。
            cluster.sort(key=lambda e: (-e[1], e[0]))
            cell = '\n'.join(c[2] for c in cluster)
            for block in split_course_blocks(cell):
                parsed = parse_cell(block, day, number_label)
                if parsed is None:
                    continue
                if not parsed['weeks']:
                    warnings.append('%s %s 的「%s」没写周次，已跳过'
                                    % (tt.DAY_CN.get(day, ''), parsed['periodFrom'],
                                       parsed['name'][:16]))
                    continue
                courses.append(parsed)
    if not courses:
        raise TimetableError('这份 PDF 里没读到任何带周次的课程，确认一下是不是课表本身')

    # 后清理：PDF 里相邻格的文字常被粘在一起——
    # - 教师后面可能带着下一条课程的课程名；
    # - 课程名前面可能带着上一条课程的教师名。
    # 同一天里能互相认出来，就截掉那一段。
    names = sorted({c['name'] for c in courses if len(c['name']) >= 2},
                   key=len, reverse=True)
    teachers = sorted({c['teacher'] for c in courses if 2 <= len(c['teacher']) <= 4},
                      key=len, reverse=True)
    for c in courses:
        for other in names:
            if other == c['name']:
                continue
            idx = c['teacher'].find(other)
            if idx >= 2:  # 教师名一般 2-4 字，后面冒出来的都是别格的课程名
                c['teacher'] = c['teacher'][:idx].strip()
                break
        for t in teachers:
            if c['name'].startswith(t) and len(c['name']) > len(t):
                c['name'] = c['name'][len(t):].strip()
                break

    return {
        'sheet': 'PDF',
        'title': '',
        'student': '',
        'courses': courses,
        'warnings': warnings,
        'periodRows': labels,
    }


def _is_number(text):
    t = (text or '').strip()
    if not t:
        return False
    try:
        float(t)
        return True
    except ValueError:
        return False


def split_course_blocks(cell_text):
    """每门课都带一个「(起-止节)」标记，标记前是课程名。"""
    matches = list(MARKER.finditer(cell_text))
    if not matches:
        return []
    blocks = []
    for i, m in enumerate(matches):
        start = 0 if i == 0 else matches[i - 1].end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(cell_text)
        block = cell_text[start:end].strip()
        if block:
            blocks.append(block)
    return blocks


def parse_cell(block, day, number_label):
    m = MARKER.search(block)
    if m is None:
        return None
    start_label = number_label.get(m.group(1))
    if start_label is None:
        return None
    end_num = m.group(2)
    period_to = number_label.get(end_num) if end_num else None
    if period_to is None:
        period_to = start_label

    # 课程名：标记前的文字，取最后一段不含 / : 的（甩掉串进来的场地/教师碎片），去 ★☆
    name = block[:m.start()].replace('\n', ' ')
    seg = re.search(r'[^/:／：]+$', name)
    if seg:
        name = seg.group(0)
    name = re.sub(r'[★☆]', '', name)
    name = re.sub(r'\s+', ' ', name).strip()
    if not name:
        return None

    rest = block[m.start():].replace('\n', '').strip()
    slash = rest.find('/')
    week_text = (rest[:slash] if slash >= 0 else rest).strip()
    weeks = tt.parse_weeks(week_text)

    room_m = re.search(r'/场地[:：](.*?)(?=/教师|/校区|/上课|$)', rest)
    room = room_m.group(1).strip() if room_m else ''
    # 教师：到下一个「★/☆」（下一条课程的课程名末尾标记）、左括号或斜杠为止
    teacher_m = re.search(r'/教师[:：]([^/(（★☆]*)', rest)
    teacher = teacher_m.group(1).strip() if teacher_m else ''

    # 名字前面可能粘着「星期一」这类表头列，去掉
    name = re.sub(r'^星期[一二三四五六日天]\s*', '', name).strip()
    if not name:
        return None

    return {
        'day': day,
        'periodFrom': start_label,
        'periodTo': period_to,
        'name': name,
        'className': '',
        'teacher': teacher,
        'room': room,
        'weekText': week_text,
        'weeks': weeks,
        'raw': block.replace('\n', ' '),
    }
