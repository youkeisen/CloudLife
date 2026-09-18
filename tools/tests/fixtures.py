# -*- coding: utf-8 -*-
"""测试用的 Open-Meteo 假数据（结构与真实接口一致）。"""
from datetime import datetime, timedelta


def forecast(hours=48, days=7, **over):
    base = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    times = [(base + timedelta(hours=i)).isoformat() for i in range(hours)]
    raw = {
        'latitude': 31.34,
        'longitude': 118.38,
        'current': {
            'time': base.isoformat(),
            'temperature_2m': 26.4,
            'relative_humidity_2m': 68,
            'apparent_temperature': 27.9,
            'is_day': 1,
            'weather_code': 3,
            'wind_speed_10m': 2.41,
            'wind_direction_10m': 135.0,
            'surface_pressure': 1008.3,
        },
        'hourly': {
            'time': times,
            'temperature_2m': [20 + (i % 12) for i in range(hours)],
            'precipitation_probability': [(i * 3) % 100 for i in range(hours)],
            'visibility': [12000 + i * 10 for i in range(hours)],
        },
        'daily': {
            'time': [(base + timedelta(days=i)).strftime('%Y-%m-%d') for i in range(days)],
            'weather_code': [3, 0, 2, 61, 3, 0, 1][:days],
            'temperature_2m_max': [27.0, 29.0, 28.0, 25.0, 24.0, 27.0, 28.0][:days],
            'temperature_2m_min': [21.0, 20.0, 22.0, 20.0, 19.0, 18.0, 20.0][:days],
            'precipitation_probability_max': [10, 0, 20, 80, 30, 5, 0][:days],
            'uv_index_max': [4.0, 6.5, 5.0, 2.0, 3.0, 7.0, 6.0][:days],
        },
    }
    if over.get('current'):
        raw['current'].update(over['current'])
    if over.get('daily'):
        raw['daily'].update(over['daily'])
    return raw


GEO_RESULTS = {
    'results': [
        {'name': '合肥', 'admin1': '安徽省', 'country': '中国', 'latitude': 31.86, 'longitude': 117.28},
        {'name': '芜湖', 'admin1': '安徽省', 'country': '中国', 'latitude': 31.34, 'longitude': 118.38},
    ]
}


class FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def read(self):
        import json
        return json.dumps(self._payload).encode('utf-8')

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


# ---------- 课表导入用的合成 xlsx ----------
# 注意：这里全部是虚构内容，不含任何真实学校/课程/人名/教室，
# 目的只是构造出和教务系统导出同构的表格来测解析器。
CONTENT_TYPES = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-'
    'officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-'
    'officedocument.spreadsheetml.worksheet+xml"/>'
    '</Types>')

ROOT_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>')

SHEET_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '</Relationships>')


def col_letters(n):
    s = ''
    while n > 0:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def xlsx_bytes(rows, merges=(), sheet_name='课表'):
    """按最朴素的方式手写一个 xlsx（inlineStr + mergeCells），只依赖标准库。"""
    import io
    import zipfile
    from xml.sax.saxutils import escape

    sheet_rows = []
    for ri, row in enumerate(rows, start=1):
        cells = []
        for ci, val in enumerate(row, start=1):
            val = '' if val is None else str(val)
            if val == '':
                continue
            cells.append('<c r="%s%d" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>'
                         % (col_letters(ci), ri, escape(val)))
        if cells:
            sheet_rows.append('<row r="%d">%s</row>' % (ri, ''.join(cells)))
    merge_xml = ''
    if merges:
        merge_xml = '<mergeCells count="%d">%s</mergeCells>' % (
            len(merges), ''.join('<mergeCell ref="%s"/>' % m for m in merges))
    sheet = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
             '<sheetData>%s</sheetData>%s</worksheet>' % (''.join(sheet_rows), merge_xml))
    workbook = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
                ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                '<sheets><sheet name="%s" sheetId="1" r:id="rId1"/></sheets></workbook>'
                % escape(sheet_name))

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CONTENT_TYPES)
        z.writestr('_rels/.rels', ROOT_RELS)
        z.writestr('xl/workbook.xml', workbook)
        z.writestr('xl/_rels/workbook.xml.rels', SHEET_RELS)
        z.writestr('xl/worksheets/sheet1.xml', sheet)
    return buf.getvalue()


def timetable_sheet():
    """一份虚构的「节次 × 星期」课表，形状和教务系统导出一致。

    覆盖到的情形：两节合并的课程格、一个格子里两门课（换行分隔）、
    单行课程格、只有节次没课的行、没写周次的脏数据。
    """
    multi = ('测试课程丙(考查)(必修课)测试专业251{1-1周 王老师 B-202}\n'
             '测试课程丁(考查)(选修课)测试专业251{2-3周 赵老师 C-303}')
    rows = [
        ['测试职业学院2026-2027-1学期学生课表', '', '', '', '', '', ''],
        ['学号：0000001    姓名：测试同学', '', '', '', '', '', ''],
        ['时间', '节次', '星期一', '星期二', '星期三', '星期四', '星期五'],
        ['上午', '1', '测试课程甲(考试)(必修课)测试专业251{1-2周 张老师 A-101}', '', multi, '', ''],
        ['', '2', '', '', '', '', ''],
        ['', '3', '', '测试课程乙(考查)(必修课)测试专业251{1-2周 李老师 B-202}', '',
         '', '测试课程戊(考查)(必修课)测试专业251{钱老师 A-101}'],
        ['中午', '中午1', '', '', '', '', ''],
        ['下午', '4', '', '', '', '', ''],
    ]
    merges = ['A1:G1', 'A2:G2', 'A4:A6', 'C4:C5', 'E4:E5']
    return rows, merges


def timetable_xlsx(sheet_name='学生课表'):
    rows, merges = timetable_sheet()
    return xlsx_bytes(rows, merges, sheet_name)


def col_index(letters):
    n = 0
    for ch in letters.upper():
        n = n * 26 + (ord(ch) - 64)
    return n


def fill_merges(rows, merges):
    """把合并区里每个格子都填成左上角的值（有些教务系统就是这么导出的）。"""
    grid = [list(row) for row in rows]
    for ref in merges:
        a, b = ref.split(':')
        r1 = int(''.join(ch for ch in a if ch.isdigit()))
        c1 = col_index(''.join(ch for ch in a if ch.isalpha()))
        r2 = int(''.join(ch for ch in b if ch.isdigit()))
        c2 = col_index(''.join(ch for ch in b if ch.isalpha()))
        val = grid[r1 - 1][c1 - 1]
        for rr in range(r1, r2 + 1):
            for cc in range(c1, c2 + 1):
                grid[rr - 1][cc - 1] = val
    return grid


def timetable_xlsx_filled(sheet_name='学生课表', width=7):
    """同一张表，但合并区每个格子都写了值——读取时只能算一遍。"""
    rows, merges = timetable_sheet()
    grid = [(list(r) + [''] * width)[:width] for r in rows]
    grid = fill_merges(grid, merges)
    return xlsx_bytes(grid, merges, sheet_name)
