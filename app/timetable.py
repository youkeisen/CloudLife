# -*- coding: utf-8 -*-
"""课表导入：解析教务系统导出的 xlsx 课表（只用标准库 zipfile + xml）。

不依赖任何第三方库：xlsx 本身就是个 zip，里面是几份 XML。

认得的表格形状（教务系统「学生课表」常见样式）：

    第 1 行  标题：学校 + 学期
    第 2 行  学号 / 姓名
    第 3 行  表头：时间 | 节次 | 星期一 … 星期日
    第 4 行起  一行一个节次；课程格常按两节纵向合并

单元格里的内容是打包写的：

    课程名称(考核方式)(课程类别)专业班级{周次范围 教师 教室}

一个格子里有多门课时用换行分隔。解析只发生在内存里，不落盘。
"""
import io
import re
import zipfile
from xml.etree import ElementTree

MAIN_NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'

# 单元格末段那些括号里的说明，抽课程名时要剥掉
TAIL_TAGS = {
    '必修', '必修课', '选修', '选修课', '限选', '限选课', '公选', '公选课',
    '任选', '任选课', '专业必修', '专业选修', '考试', '考查', '考核', '练习',
    '其他', '补考', '重修',
}

DAY_WORDS = {
    '星期一': 1, '周一': 1, '礼拜一': 1,
    '星期二': 2, '周二': 2, '礼拜二': 2,
    '星期三': 3, '周三': 3, '礼拜三': 3,
    '星期四': 4, '周四': 4, '礼拜四': 4,
    '星期五': 5, '周五': 5, '礼拜五': 5,
    '星期六': 6, '周六': 6, '礼拜六': 6,
    '星期日': 7, '星期天': 7, '周日': 7, '周天': 7, '礼拜日': 7,
}

DAY_CN = {1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日'}

MAX_WEEKS = 30


class TimetableError(Exception):
    """课表读不出来时抛这个，消息直接给用户看。"""


# ---------- xlsx 基础读取 ----------
def _local(tag):
    return tag.rsplit('}', 1)[-1]


def _child(el, name):
    """取子元素，兼容有/没有命名空间两种写法。"""
    hit = el.find(MAIN_NS + name)
    if hit is not None:
        return hit
    for child in el:
        if _local(child.tag) == name:
            return child
    return None


def col_index(ref):
    """'C' -> 3，'AA' -> 27"""
    letters = ''.join(ch for ch in str(ref) if ch.isalpha())
    if not letters:
        raise TimetableError('单元格坐标看不懂：' + str(ref))
    n = 0
    for ch in letters.upper():
        n = n * 26 + (ord(ch) - 64)
    return n


def split_ref(ref):
    """'B7' -> (7, 2)"""
    digits = ''.join(ch for ch in str(ref) if ch.isdigit())
    if not digits:
        raise TimetableError('单元格坐标看不懂：' + str(ref))
    return int(digits), col_index(ref)


def _sheet_names(zf, names):
    try:
        root = ElementTree.fromstring(zf.read('xl/workbook.xml'))
    except Exception:
        return []
    out = []
    for el in root.iter():
        if _local(el.tag) == 'sheet':
            out.append((el.get('name') or '', el.get('sheetId') or ''))
    return out


def _sheet_path(zf, names):
    wanted = [n for n in names if re.fullmatch(r'xl/worksheets/sheet\d+\.xml', n)]
    if not wanted:
        raise TimetableError('这个 xlsx 里没有找到工作表')
    wanted.sort(key=lambda n: int(re.search(r'(\d+)', n).group(1)))
    return wanted[0]


def _shared_strings(zf):
    try:
        data = zf.read('xl/sharedStrings.xml')
    except KeyError:
        return []
    root = ElementTree.fromstring(data)
    out = []
    for si in root:
        if _local(si.tag) != 'si':
            continue
        out.append(''.join(t.text or '' for t in si.iter() if _local(t.tag) == 't'))
    return out


def read_xlsx(raw):
    """读第一张工作表，返回 {sheet, cells, merges, maxRow, maxCol}。

    cells 的 key 是 (行, 列)，都是 1 起；只放左上角有值的格。
    """
    if not raw:
        raise TimetableError('没有拿到文件内容')
    try:
        zf = zipfile.ZipFile(io.BytesIO(raw))
    except zipfile.BadZipFile:
        raise TimetableError('这个文件不是 xlsx。请用 Excel 打开后「另存为」.xlsx 再试')
    names = zf.namelist()
    if not any(n.startswith('xl/') for n in names):
        raise TimetableError('文件里没有工作表，确认一下是不是真正的 .xlsx')
    sheets = _sheet_names(zf, names)
    path = _sheet_path(zf, names)
    try:
        root = ElementTree.fromstring(zf.read(path))
    except ElementTree.ParseError as exc:
        raise TimetableError('工作表内容读不出来：' + str(exc))
    sst = _shared_strings(zf)

    cells = {}
    merges = []
    for el in root.iter():
        tag = _local(el.tag)
        if tag == 'c':
            ref = el.get('r') or ''
            if not ref:
                continue
            try:
                row, col = split_ref(ref)
            except TimetableError:
                continue
            ctype = el.get('t') or ''
            text = ''
            if ctype == 's':
                v = _child(el, 'v')
                if v is not None and v.text is not None:
                    try:
                        idx = int(v.text)
                    except ValueError:
                        idx = -1
                    if 0 <= idx < len(sst):
                        text = sst[idx]
            elif ctype == 'inlineStr':
                text = ''.join(t.text or '' for t in el.iter() if _local(t.tag) == 't')
            else:
                v = _child(el, 'v')
                if v is not None and v.text is not None:
                    text = v.text
            text = str(text).replace('\r\n', '\n').replace('\r', '\n').strip()
            if text:
                cells[(row, col)] = text
        elif tag == 'mergeCell':
            ref = el.get('ref') or ''
            if ':' not in ref:
                continue
            a, b = ref.split(':')[:2]
            try:
                r1, c1 = split_ref(a)
                r2, c2 = split_ref(b)
            except TimetableError:
                continue
            merges.append((min(r1, r2), min(c1, c2), max(r1, r2), max(c1, c2)))

    if not cells:
        raise TimetableError('这张表是空的，没读到任何内容')
    return {
        'sheet': (sheets[0][0] if sheets else ''),
        'cells': cells,
        'merges': merges,
        'maxRow': max(r for (r, _c) in cells),
        'maxCol': max(c for (_r, c) in cells),
    }


# ---------- 单元格内容解析 ----------
def day_of(text):
    key = re.sub(r'\s+', '', str(text or ''))
    return DAY_WORDS.get(key)


def _strip_tail_tags(head):
    """从末尾剥掉 (考试)(必修课) 这类标注，返回课程名部分。"""
    name = head.strip()
    while True:
        m = re.search(r'[（(]([^（()）]{1,8})[）)]\s*$', name)
        if not m:
            break
        tag = m.group(1).strip()
        if tag not in TAIL_TAGS:
            break
        name = name[:m.start()].strip()
    return name


CLASS_RE = re.compile(r'[\u4e00-\u9fa5]{2,10}?(?:技术|专业|班|学院|系|方向)\s*\d{2,4}')
CLASS_LIST_RE = re.compile(
    r'[\u4e00-\u9fa5]{2,10}?(?:技术|专业|班|学院|系|方向)\s*\d{2,4}'
    r'(?:\s*[,，、]\s*[\u4e00-\u9fa5]{2,10}?(?:技术|专业|班|学院|系|方向)\s*\d{2,4})*')


def split_class(head):
    """把「课程名 + 班级」拆开。

    教务系统的写法是：课程名(考核方式)(课程类别)专业班级，班级长这样
    「电气自动化技术251」= 专业名 + 年级号。课程名和班级之间没有分隔符，
    所以优先用括号标注当分界：最后一个 ')' 后面剩下的就是班级。
    没有括号时（有些表只写课程名和班级），再从末尾往前找最靠后的、能延到末尾的班级。
    """
    head = (head or '').strip()
    cut = head.rfind(')')
    if cut >= 0:
        tail = head[cut + 1:].strip()
        if tail and head[:cut + 1].strip() and CLASS_LIST_RE.fullmatch(tail):
            return head[:cut + 1].strip(), tail
    for start in range(len(head) - 1, 0, -1):
        m = CLASS_RE.match(head, start)
        if m and m.end() == len(head):
            return head[:start].strip(), head[start:].strip()
    return head, ''


def parse_weeks(text):
    """'4-17周' -> [4..17]；'1,3,5周' -> [1,3,5]；带「单/双」时只取单/双周。"""
    if text is None:
        return []
    t = str(text).strip()
    if not t:
        return []
    odd = '单' in t
    even = '双' in t
    t = t.replace('周', ' ')
    t = re.sub(r'[（()）第单双]+', ' ', t)
    weeks = set()
    for part in re.split(r'[,，、;；/\s]+', t):
        if not part:
            continue
        m = re.fullmatch(r'(\d+)\s*[-–~至]\s*(\d+)', part)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            if a > b:
                a, b = b, a
            weeks.update(range(a, b + 1))
        elif part.isdigit():
            weeks.add(int(part))
    if odd:
        weeks = {w for w in weeks if w % 2 == 1}
    if even:
        weeks = {w for w in weeks if w % 2 == 0}
    return sorted(w for w in weeks if 1 <= w <= MAX_WEEKS)


def parse_course_line(line):
    """一行课程文本 -> dict；解析不出课程名就返回 None。"""
    text = re.sub(r'\s+', ' ', str(line or '')).strip()
    if not text:
        return None
    meta = ''
    head = text
    m = re.search(r'\{(.*)\}', text)
    if m:
        head = (text[:m.start()] + text[m.end():]).strip()
        meta = m.group(1).strip()
    # 全角括号统一成半角，方便用最后一个 ')' 当班级的分界
    head = head.replace('（', '(').replace('）', ')')

    week_text = ''
    teacher = ''
    room = ''
    if meta:
        parts = [p for p in meta.split() if p]
        if parts:
            week_text = parts[0]
            rest = parts[1:]
            if rest:
                # 教室一般带数字或 #，教师是纯中文姓名
                if re.search(r'[\d#]', rest[-1]):
                    room = rest[-1]
                    teacher = ' '.join(rest[:-1])
                else:
                    teacher = ' '.join(rest)

    # 先按「班级」把尾巴切出去，再剥 (考试)(必修课) 这些标注——
    # 顺序反了的话，标注后面还跟着班级，就不在末尾了，剥不掉。
    name, class_name = split_class(head)
    name = _strip_tail_tags(name)
    if not name:
        return None
    return {
        'name': name,
        'className': class_name,
        'teacher': teacher,
        'room': room,
        'weekText': week_text,
        'weeks': parse_weeks(week_text),
        'raw': text,
    }


# ---------- 整张表解析 ----------
def parse_timetable(raw):
    """把整张课表读成结构化数据。

    返回 {sheet, title, student, courses, warnings, periodRows}
    courses 每一项：{day, periodFrom, periodTo, name, teacher, room, className,
                    weekText, weeks, raw}
    """
    book = read_xlsx(raw)
    cells = book['cells']
    merges = book['merges']
    rows = sorted({r for (r, _c) in cells})

    header_row = None
    period_col = None
    day_cols = {}
    for r in rows:
        row_cells = {c: v for (rr, c), v in cells.items() if rr == r}
        pcol = None
        for c, v in row_cells.items():
            if re.sub(r'\s+', '', v) in ('节次', '节数', '节'):
                pcol = c
                break
        days = {}
        for c, v in row_cells.items():
            d = day_of(v)
            if d is not None:
                days[d] = c
        if pcol and days:
            header_row, period_col, day_cols = r, pcol, days
            break
    if header_row is None:
        raise TimetableError('没认出课表的表头：表里要有「节次」这一列和「星期一…星期日」这些列')

    title = ''
    student = ''
    for r in rows:
        if r >= header_row:
            continue
        cols = sorted(cc for (rr, cc) in cells if rr == r)
        line = ' '.join(cells[(r, cc)] for cc in cols).strip()
        if not line:
            continue
        if ('学号' in line or '姓名' in line) and not student:
            student = line
        elif not title:
            title = line

    # 有些教务系统（这份就是）会把合并区的值在每个格子里都存一遍，
    # 所以要做两件事：算出「被合并盖住、不是左上角」的格子，以及一份
    # 和 Excel 显示一致的网格（合并区里继承左上角的值）。
    covered = set()
    resolved = dict(cells)
    for (r1, c1, r2, c2) in merges:
        top = cells.get((r1, c1))
        for rr in range(r1, r2 + 1):
            for cc in range(c1, c2 + 1):
                if (rr, cc) == (r1, c1):
                    continue
                covered.add((rr, cc))
                if top is not None:
                    resolved[(rr, cc)] = top

    # 纵向合并：左上角那股跨到哪一行
    span_end = {}
    for (r1, c1, r2, c2) in merges:
        if c1 == c2 and r2 > r1:
            span_end[(r1, c1)] = r2

    period_rows = []
    for r in rows:
        if r <= header_row:
            continue
        label = resolved.get((r, period_col))
        if label:
            period_rows.append((r, label))
    if not period_rows:
        raise TimetableError('表头下面没有找到任何节次行')

    courses = []
    warnings = []
    for (r, label) in period_rows:
        for day in sorted(day_cols):
            c = day_cols[day]
            if (r, c) in covered:
                continue  # 合并区里被盖住的格子，别重复读一遍
            text = cells.get((r, c))
            if not text:
                continue
            end = span_end.get((r, c), r)
            span = [pl for (rr, pl) in period_rows if r <= rr <= min(end, period_rows[-1][0])]
            if not span:
                continue
            for line in text.split('\n'):
                one = parse_course_line(line)
                if not one:
                    continue
                if not one['weeks']:
                    warnings.append('%s %s 的「%s」没写周次，已跳过'
                                    % (DAY_CN.get(day, ''), span[0], one['name'][:16]))
                    continue
                courses.append({
                    'day': day,
                    'periodFrom': span[0],
                    'periodTo': span[-1],
                    'name': one['name'],
                    'className': one['className'],
                    'teacher': one['teacher'],
                    'room': one['room'],
                    'weekText': one['weekText'],
                    'weeks': one['weeks'],
                    'raw': one['raw'],
                })

    if not courses:
        raise TimetableError('这张表里没读到任何带周次的课程，确认一下是不是课表本身')

    return {
        'sheet': book['sheet'],
        'title': title,
        'student': student,
        'courses': courses,
        'warnings': warnings,
        'periodRows': [pl for (_r, pl) in period_rows],
    }


def period_labels(parsed):
    """按表格里的行序，给出真正被课程用到的节次名。"""
    used = set()
    for c in parsed['courses']:
        used.add(c['periodFrom'])
        used.add(c['periodTo'])
    return [pl for pl in parsed['periodRows'] if pl in used]


def period_label_text(label):
    """'1' -> '第 1 节'；'中午1' 这种原样保留。"""
    text = str(label or '').strip()
    if re.fullmatch(r'\d+', text):
        return '第 %s 节' % text
    return text


def total_lessons(parsed):
    return sum(len(c['weeks']) for c in parsed['courses'])


def week_span(parsed):
    weeks = sorted({w for c in parsed['courses'] for w in c['weeks']})
    return weeks
