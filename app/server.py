# -*- coding: utf-8 -*-
"""MyDay 本地服务：路由分发 + 静态页面托管。

只用 Python 标准库。启动方式：
    python app/server.py [--data <dir>] [--port <n>] [--no-browser]
"""
import argparse
from datetime import date as _date, datetime, timedelta, timezone
import json
import mimetypes
import os
import sys
import threading
import traceback
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
import urllib.request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
if APP_DIR not in sys.path:
    sys.path.insert(0, APP_DIR)
STATIC_DIR = os.path.join(APP_DIR, 'static')
ROOT_DIR = os.path.dirname(APP_DIR)

sys.path.insert(0, APP_DIR)
import store  # noqa: E402

APP_VERSION = '1.1.1'
CST = timezone(timedelta(hours=8))


def now_iso():
    return datetime.now(CST).isoformat(timespec='seconds')


def ok(data=None):
    return {'ok': True, 'data': data if data is not None else {}}


def fail(message, code='error'):
    return {'ok': False, 'error': message, 'code': code}


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'MyDay/' + APP_VERSION

    # ---------- 基础收发 ----------
    def _headers(self, ctype, length, extra=None):
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(length))
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        self.send_header('Connection', 'close')
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()

    def _raw(self, body, ctype, extra=None):
        if isinstance(body, str):
            body = body.encode('utf-8')
        self._headers(ctype, len(body), extra)
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionAbortedError):
            pass

    def _json(self, obj, status=200):
        self.send_response(status)
        payload = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        self.send_header('Connection', 'close')
        self.end_headers()
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionAbortedError):
            pass

    def _body_json(self):
        length = int(self.headers.get('Content-Length') or 0)
        if not length:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode('utf-8'))
        except Exception:
            return {}

    def _static(self, rel):
        path = os.path.join(STATIC_DIR, rel)
        if not os.path.isfile(path):
            self._json(fail('资源不存在: ' + rel, 'not_found'), 404)
            return
        ctype = mimetypes.guess_type(path)[0] or 'application/octet-stream'
        if ctype.startswith('text/') or rel.endswith('.js'):
            ctype += '; charset=utf-8'
        with open(path, 'rb') as f:
            self._raw(f.read(), ctype)

    # ---------- 方法入口 ----------
    def do_GET(self):
        self.dispatch('GET')

    def do_POST(self):
        self.dispatch('POST')

    def do_PUT(self):
        self.dispatch('PUT')

    def do_DELETE(self):
        self.dispatch('DELETE')

    def log_message(self, fmt, *args):
        sys.stderr.write('[MyDay] %s %s\n' % (datetime.now().strftime('%H:%M:%S'),
                                              (fmt % args) if args else fmt))

    def dispatch(self, method):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/') or '/'
        query = parse_qs(parsed.query)
        body = {}
        if method in ('POST', 'PUT', 'DELETE'):
            body = self._body_json()
        key = (method, path)
        handler = ROUTES.get(key)
        try:
            if handler is None:
                self._json(fail('接口不存在: ' + method + ' ' + path, 'not_found'), 404)
                return
            handler(self, {'query': query, 'body': body, 'path': path})
        except ValueError as exc:
            self._json(fail(str(exc), 'bad_request'), 400)
        except Exception as exc:  # 任何异常都不能让服务崩掉
            traceback.print_exc()
            self._json(fail('服务端出错: ' + str(exc), 'server_error'), 500)


def _q1(query, name, default=None):
    v = query.get(name)
    if not v:
        return default
    return v[0]


def api_health(h, ctx):
    h._json(ok({
        'version': APP_VERSION,
        'time': now_iso(),
        'dataDir': DATA_DIR,
        'port': PORT,
        'pid': os.getpid(),
    }))


def today_meta():
    s = store.get_settings()
    today = datetime.now(CST)
    iso = today.date().isoformat()
    week = store.week_of(iso, s.get('week1Monday'))
    monday = store.monday_of(week, s.get('week1Monday')) if week else None
    sunday = None
    if monday:
        sunday = (_date.fromisoformat(monday) + timedelta(days=6)).isoformat()
    return {
        'today': iso,
        'dow': today.isoweekday(),
        'week': week,
        'weekStartsOn': s.get('weekStartsOn', 1),
        'weekStart': monday,
        'weekEnd': sunday,
        'campus': s.get('campus', ''),
        'displayName': s.get('displayName', ''),
        'semesterName': s.get('semesterName', ''),
    }


def api_bootstrap(h, ctx):
    # 顺手体检四份数据文件：缺的建立、坏的隔离恢复并产生警告
    for name in ('settings', 'courses', 'notes', 'weather_cache'):
        try:
            store.read(name)
        except Exception as exc:
            store.append_warning(name, '读取失败：' + str(exc))
    h._json(ok({
        'version': APP_VERSION,
        'dataDir': DATA_DIR,
        'settings': store.get_settings(),
        'weekMeta': today_meta(),
        'warnings': store.warnings(),
    }))


def api_get_settings(h, ctx):
    h._json(ok(store.get_settings()))


def api_put_settings(h, ctx):
    body = dict(ctx['body'] or {})
    body.pop('version', None)
    saved = store.save_settings(body)
    h._json(ok(saved))


def _require_period_id(h, body):
    pid = (body or {}).get('id')
    if not pid:
        h._json(fail('缺少节次 id', 'bad_request'))
        return None
    return pid


def api_add_period(h, ctx):
    body = ctx['body'] or {}
    settings = store.get_settings()
    item = {
        'id': store.next_period_id(),
        'label': str(body.get('label') or '').strip(),
        'start': str(body.get('start') or '').strip(),
        'end': str(body.get('end') or '').strip(),
    }
    settings['periods'].append(item)
    store.write('settings', settings)
    h._json(ok(item))


def api_update_period(h, ctx):
    body = ctx['body'] or {}
    pid = _require_period_id(h, body)
    if pid is None:
        return
    settings = store.get_settings()
    found = None
    for p in settings['periods']:
        if p.get('id') == pid:
            found = p
            break
    if found is None:
        h._json(fail('节次不存在：' + str(pid), 'not_found'))
        return
    for field in ('label', 'start', 'end'):
        if field in body:
            found[field] = str(body[field] or '').strip()
    store.write('settings', settings)
    h._json(ok(found))


def api_move_period(h, ctx):
    body = ctx['body'] or {}
    pid = _require_period_id(h, body)
    if pid is None:
        return
    direction = body.get('direction') or 'up'
    settings = store.get_settings()
    items = settings['periods']
    idx = next((i for i, p in enumerate(items) if p.get('id') == pid), -1)
    if idx < 0:
        h._json(fail('节次不存在：' + str(pid), 'not_found'))
        return
    target = idx - 1 if direction == 'up' else idx + 1
    if target < 0 or target >= len(items):
        h._json(ok({'moved': False, 'periods': items}))
        return
    items[idx], items[target] = items[target], items[idx]
    store.write('settings', settings)
    h._json(ok({'moved': True, 'periods': items}))


def api_delete_period(h, ctx):
    body = ctx['body'] or {}
    pid = body.get('id')
    mode = body.get('mode') or 'cancel'
    if not pid:
        h._json(fail('缺少节次 id', 'bad_request'))
        return
    used = store.period_usage(pid)
    if used and mode == 'cancel':
        h._json(ok({'used': used, 'deleted': False, 'needConfirm': True}))
        return
    result = store.delete_period(pid, mode)
    h._json(ok(result))


# ---------- 天气 ----------
def _cache_age_minutes(fetched_at):
    if not fetched_at:
        return None
    try:
        when = datetime.fromisoformat(fetched_at)
    except ValueError:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=CST)
    return (datetime.now(CST) - when).total_seconds() / 60.0


def weather_result(force=False):
    """复用的天气取数逻辑：优先缓存，失败降级。返回 dict。"""
    import weather as wx
    s = store.get_settings()
    city = s.get('weatherCity') or {}
    if city.get('latitude') is None or city.get('longitude') is None or not city.get('name'):
        return {'state': 'no_city'}
    refresh_minutes = s.get('refreshMinutes', 30)
    cache = store.get_weather_cache()
    same_city = (cache.get('city') or {}).get('name') == city.get('name')
    age = _cache_age_minutes(cache.get('fetchedAt')) if same_city else None
    if refresh_minutes == 0:
        fresh = bool(cache.get('payload')) and same_city
    else:
        fresh = age is not None and age < refresh_minutes and bool(cache.get('payload'))
    if not force and fresh:
        return {'state': 'ok', 'payload': cache['payload'], 'fetchedAt': cache.get('fetchedAt'),
                'stale': False, 'source': 'cache'}
    try:
        raw = wx.fetch_weather(city['latitude'], city['longitude'])
        payload = wx.normalize(raw, city)
        saved = store.set_weather_cache(city, payload)
        return {'state': 'ok', 'payload': payload, 'fetchedAt': saved['fetchedAt'],
                'stale': False, 'source': 'network'}
    except wx.WeatherError as exc:
        if cache.get('payload') and same_city:
            return {'state': 'ok', 'payload': cache['payload'],
                    'fetchedAt': cache.get('fetchedAt'), 'stale': True,
                    'source': 'cache', 'error': str(exc)}
        return {'state': 'error', 'error': str(exc)}


def api_weather(h, ctx):
    result = weather_result(force=_q1(ctx['query'], 'refresh') == '1')
    if result['state'] == 'no_city':
        h._json(fail('还没选城市，先去设置里选一个', 'no_city'))
        return
    if result['state'] == 'error':
        h._json(fail('暂时取不到天气：' + result['error'], 'weather_error'))
        return
    h._json(ok(result))


def _minutes(hhmm):
    try:
        parts = str(hhmm).split(':')
        return int(parts[0]) * 60 + int(parts[1])
    except (ValueError, IndexError, AttributeError, TypeError):
        return None


def compute_lesson_states(lessons, periods, now_min):
    """把今天的课按时间排出状态；now_min 为当天 0 点起的分钟数。"""
    enriched = []
    for lesson in lessons or []:
        start_p = next((p for p in periods if p.get('id') == lesson.get('slot')), None)
        end_p = next((p for p in periods if p.get('id') == lesson.get('spanEnd')), None) if lesson.get('spanEnd') else None
        begin = _minutes((start_p or {}).get('start'))
        finish = _minutes((end_p or start_p or {}).get('end'))
        status = 'unknown'
        if begin is not None and finish is not None:
            if finish < begin:  # 跨零点，按次日凌晨处理
                finish += 24 * 60
            if now_min < begin:
                status = 'upcoming'
            elif begin <= now_min <= finish:
                status = 'now'
            else:
                status = 'done'
        period_range = (((start_p or {}).get('start') or '') + ' - ' +
                        ((end_p or start_p or {}).get('end') or '')).strip(' -')
        enriched.append({
            'lesson': lesson,
            'periodLabel': (start_p or {}).get('label', ''),
            'periodRange': period_range or '时间未设置',
            'status': status,
            'begin': begin,
            'order': next((i for i, p in enumerate(periods) if p.get('id') == lesson.get('slot')), 999),
        })
    enriched.sort(key=lambda x: (x['begin'] is None, x['begin'] or 0, x['order']))
    next_marked = False
    for item in enriched:
        item['next'] = False
        if item['status'] == 'upcoming' and not next_marked:
            item['next'] = True
            next_marked = True
    return enriched


# 首页备忘录速览：最多几条、每条最多摊开几项清单、正文最多带多少字
PREVIEW_NOTES = 3
PREVIEW_ITEMS = 6
PREVIEW_BODY = 200


def api_home(h, ctx):
    s = store.get_settings()
    meta = today_meta()
    periods = s.get('periods') or []
    now = datetime.now(CST)
    now_min = now.hour * 60 + now.minute
    lessons = []
    if meta.get('week'):
        lessons = [c for c in store.list_week(meta['week']) if c.get('day') == meta.get('dow')]
    enriched = compute_lesson_states(lessons, periods, now_min)

    notes = [n for n in store.read('notes').get('notes', []) if not n.get('archived')]
    notes.sort(key=lambda n: n.get('updatedAt', ''), reverse=True)
    notes.sort(key=lambda n: not n.get('pinned'))
    preview = []
    for n in notes[:PREVIEW_NOTES]:
        raw_items = n.get('items') or []
        total = len(raw_items)
        done = len([i for i in raw_items if i.get('done')])
        shown = raw_items[:PREVIEW_ITEMS]
        preview.append({
            'id': n.get('id'),
            'title': n.get('title') or '无标题',
            'type': n.get('type') or 'text',
            'tags': n.get('tags') or [],
            'summary': ('%d/%d 项完成' % (done, total)) if n.get('type') == 'todo'
                       else (n.get('body') or '').split('\n')[0][:24],
            'pinned': n.get('pinned'),
            # 清单：把内容和勾选状态一起带上，首页直接看得见、也能勾
            'items': [{'text': (i.get('text') or ''), 'done': bool(i.get('done'))} for i in shown],
            'moreItems': max(0, total - len(shown)),
            'itemsDone': done,
            'itemsTotal': total,
            # 正文：首页折叠区里显示，太长就截断
            'body': (n.get('body') or '').strip()[:PREVIEW_BODY],
            'bodyCut': len((n.get('body') or '').strip()) > PREVIEW_BODY,
        })

    h._json(ok({
        'meta': meta,
        'greeting': greeting_of(now),
        'hasPeriods': bool(periods),
        'todayLessons': enriched,
        'todayCount': len(enriched),
        'weather': weather_result(force=False),
        'notesPreview': preview,
    }))


def greeting_of(now):
    hour = now.hour
    if hour < 6:
        return '还没睡'
    if hour < 11:
        return '早上好'
    if hour < 14:
        return '中午好'
    if hour < 18:
        return '下午好'
    return '晚上好'


def api_cities(h, ctx):
    import weather as wx
    name = (_q1(ctx['query'], 'q') or '').strip()
    if not name:
        h._json(fail('请输入城市名', 'bad_request'))
        return
    try:
        h._json(ok({'cities': wx.search_cities(name)}))
    except wx.WeatherError as exc:
        h._json(fail('城市搜索失败：' + str(exc), 'weather_error'))


# ---------- 我的地点 ----------
def _places_data():
    settings = store.get_settings()
    return {'places': store.list_places(),
            'current': settings.get('weatherCity') or store.EMPTY_CITY,
            'settings': settings}


def api_list_places(h, ctx):
    h._json(ok(_places_data()))


def api_add_place(h, ctx):
    result = store.add_place(ctx['body'] or {})
    h._json(ok(result))


def api_select_place(h, ctx):
    pid = (ctx['body'] or {}).get('id')
    if not pid:
        raise ValueError('请选择要切换的地点')
    result = store.select_place(pid)
    if result is None:
        h._json(fail('地点不存在，可能已经被删掉了', 'not_found'))
        return
    h._json(ok(result))


def api_delete_place(h, ctx):
    pid = (ctx['body'] or {}).get('id')
    if not pid:
        raise ValueError('请指明要删除的地点')
    result = store.remove_place(pid)
    if not result['deleted']:
        h._json(fail('地点不存在，可能已经被删掉了', 'not_found'))
        return
    h._json(ok(result))


# ---------- 备忘录 ----------
def api_list_notes(h, ctx):
    include_archived = _q1(ctx['query'], 'archived') == '1'
    notes = store.list_notes(include_archived)
    notes.sort(key=lambda n: n.get('updatedAt', ''), reverse=True)
    notes.sort(key=lambda n: not n.get('pinned'))
    h._json(ok({'notes': notes, 'total': len(notes)}))


def api_add_note(h, ctx):
    h._json(ok(store.add_note(ctx['body'] or {})))


def api_update_note(h, ctx):
    try:
        h._json(ok(store.update_note(ctx['body'] or {})))
    except ValueError as exc:
        h._json(fail(str(exc), 'not_found'))


def api_delete_note(h, ctx):
    removed = store.delete_note((ctx['body'] or {}).get('id'))
    if not removed:
        h._json(fail('备忘录不存在', 'not_found'))
        return
    h._json(ok({'deleted': True}))


def api_toggle_note_item(h, ctx):
    """首页速览里直接勾选清单项用；只翻一项，不整段回写。"""
    body = ctx['body'] or {}
    nid = body.get('id')
    if not nid:
        raise ValueError('缺少备忘录 id')
    if body.get('index') is None:
        raise ValueError('缺少清单项序号')
    note = store.toggle_note_item(nid, body.get('index'))
    if note is None:
        h._json(fail('备忘录或这一项不存在，可能已经被删掉了', 'not_found'))
        return
    h._json(ok(note))


# ---------- 备份 / 还原 / 清空 ----------
def api_backup(h, ctx):
    import backup
    path, manifest = backup.save_backup(DATA_DIR, store.backups_dir())
    backup.keep_recent(store.backups_dir(), limit=10)
    with open(path, 'rb') as f:
        payload = f.read()
    name = os.path.basename(path)
    h._raw(payload, 'application/zip',
           {'Content-Disposition': 'attachment; filename="%s"' % name})


def api_restore(h, ctx):
    import backup
    import base64
    body = ctx['body'] or {}
    raw_b64 = body.get('content') or ''
    if not raw_b64:
        h._json(fail('没有选择备份文件', 'bad_request'))
        return
    try:
        raw = base64.b64decode(raw_b64)
    except Exception as exc:
        h._json(fail('备份内容无法解析：' + str(exc), 'bad_request'))
        return
    # 还原前先自动留一份当前数据，避免手滑
    backup.save_backup(DATA_DIR, store.backups_dir())
    try:
        info = backup.restore_bytes(DATA_DIR, raw)
        h._json(ok({'restored': info['files'], 'exportedAt': info.get('exportedAt')}))
    except backup.BackupError as exc:
        h._json(fail(str(exc), 'bad_request'))


def api_open_folder(h, ctx):
    body = ctx['body'] or {}
    if body.get('open'):
        try:
            if os.name == 'nt':
                os.startfile(DATA_DIR)  # noqa: S606 - 本机自己打开自己的数据目录
        except Exception as exc:
            h._json(fail('打开文件夹失败：' + str(exc), 'open_failed'))
            return
    h._json(ok({'path': DATA_DIR}))


def api_reset_all(h, ctx):
    import backup
    path, _ = backup.save_backup(DATA_DIR, store.backups_dir())
    for name in ('settings', 'courses', 'notes', 'weather_cache'):
        store.write(name, json.loads(json.dumps(store.DEFAULTS[name])))
    h._json(ok({'backupFile': os.path.basename(path)}))


# ---------- 课程 ----------
def _week_from_query(ctx, default=1):
    raw = _q1(ctx['query'], 'week')
    try:
        return int(raw) if raw else int(default)
    except ValueError:
        raise ValueError('周次必须是数字')


def api_list_courses(h, ctx):
    week = _week_from_query(ctx)
    lessons = store.list_week(week)
    h._json(ok({'week': week, 'list': lessons, 'total': len(lessons)}))


def api_add_course(h, ctx):
    body = ctx['body'] or {}
    if not body.get('slot'):
        raise ValueError('请先选择节次')
    item = store.add_course(body)
    h._json(ok(item))


def api_update_course(h, ctx):
    item = store.update_course(ctx['body'] or {})
    h._json(ok(item))


def api_delete_course(h, ctx):
    removed = store.delete_course((ctx['body'] or {}).get('id'))
    if not removed:
        h._json(fail('课程不存在', 'not_found'))
        return
    h._json(ok({'deleted': True}))


def api_copy_week(h, ctx):
    body = ctx['body'] or {}
    src = int(body.get('from') or 0)
    targets = body.get('to') or []
    mode = body.get('mode') or 'overwrite'
    if mode not in ('overwrite', 'merge', 'empty-only'):
        raise ValueError('未知的复制方式：' + str(mode))
    if not src:
        raise ValueError('缺少源周')
    if not isinstance(targets, list) or not targets:
        raise ValueError('请至少选择一周')
    result = store.copy_week(src, targets, mode)
    h._json(ok({'from': src, 'mode': mode, 'result': result}))


def api_clear_week(h, ctx):
    body = ctx['body'] or {}
    week = int(body.get('week') or 0)
    if not week:
        raise ValueError('缺少周次')
    store.clear_week(week)
    h._json(ok({'week': week, 'total': 0}))


# ---------- 导入课表 ----------
MAX_UPLOAD = 6 * 1024 * 1024


def _upload_bytes(body):
    import base64
    raw_b64 = (body or {}).get('content') or ''
    if not raw_b64:
        raise ValueError('没有拿到文件内容')
    if len(raw_b64) > MAX_UPLOAD * 2:
        raise ValueError('文件太大了，先确认是不是导错了文件')
    text = raw_b64.split(',', 1)[1] if raw_b64.startswith('data:') else raw_b64
    try:
        raw = base64.b64decode(text, validate=False)
    except Exception as exc:
        raise ValueError('文件内容解析不了：' + str(exc))
    if not raw:
        raise ValueError('文件是空的')
    if len(raw) > MAX_UPLOAD:
        raise ValueError('文件超过 6MB 了，这个大小的课表不太正常')
    return raw


def _import_plan(raw):
    import timetable as tt
    parsed = tt.parse_timetable(raw)
    labels = [tt.period_label_text(l) for l in tt.period_labels(parsed)]
    existing = {str(p.get('label') or '').strip() for p in store.periods()}
    courses = []
    for c in parsed['courses']:
        courses.append({
            'day': c['day'],
            'dayText': tt.DAY_CN.get(c['day'], ''),
            'periodFrom': tt.period_label_text(c['periodFrom']),
            'periodTo': tt.period_label_text(c['periodTo']),
            'name': c['name'],
            'className': c['className'],
            'teacher': c['teacher'],
            'room': c['room'],
            'weekText': c['weekText'],
            'weeks': c['weeks'],
            'lessonCount': len(c['weeks']),
        })
    return {
        'parsed': parsed,
        'labels': labels,
        'plan': {
            'sheet': parsed['sheet'],
            'title': parsed['title'],
            'student': parsed['student'],
            'courses': courses,
            'courseCount': len(courses),
            'warnings': parsed['warnings'],
            'periodLabels': labels,
            'newPeriods': [l for l in labels if l not in existing],
            'reusePeriods': [l for l in labels if l in existing],
            'weeks': tt.week_span(parsed),
            'totalLessons': tt.total_lessons(parsed),
        },
    }


def api_import_preview(h, ctx):
    """只解析给用户看，一个字都不写盘。"""
    raw = _upload_bytes(ctx['body'] or {})
    import timetable as tt
    try:
        built = _import_plan(raw)
    except tt.TimetableError as exc:
        h._json(fail(str(exc), 'bad_timetable'))
        return
    h._json(ok(built['plan']))


def api_import(h, ctx):
    import backup
    import timetable as tt
    body = ctx['body'] or {}
    mode = body.get('mode') or 'merge'
    if mode not in ('merge', 'overwrite'):
        raise ValueError('未知的导入方式：' + str(mode))
    raw = _upload_bytes(body)
    try:
        built = _import_plan(raw)
    except tt.TimetableError as exc:
        h._json(fail(str(exc), 'bad_timetable'))
        return
    parsed = built['parsed']
    # 导入前先自动留一份，手滑了能退回来
    backup_path, _manifest = backup.save_backup(DATA_DIR, store.backups_dir())
    backup.keep_recent(store.backups_dir(), limit=10)

    mapping, created = store.ensure_periods(built['labels'])
    by_week = {}
    for c in parsed['courses']:
        start_id = mapping.get(tt.period_label_text(c['periodFrom']))
        end_label = tt.period_label_text(c['periodTo'])
        end_id = mapping.get(end_label)
        if not start_id:
            continue
        item = {
            'day': c['day'],
            'slot': start_id,
            'spanEnd': end_id if (end_id and end_id != start_id) else '',
            'name': c['name'],
            'location': c['room'],
            'teacher': c['teacher'],
            'note': (c['className'] + ' ' + c['weekText'] + '周').strip() if c['className'] else (c['weekText'] + '周'),
            'color': '',
        }
        for w in c['weeks']:
            by_week.setdefault(w, []).append(item)
    result = store.import_courses(by_week, mode)
    h._json(ok({
        'mode': mode,
        'added': result['added'],
        'weeks': result['weeks'],
        'courses': built['plan']['courseCount'],
        'createdPeriods': [p['label'] for p in created],
        'reusedPeriods': built['plan']['reusePeriods'],
        'backupFile': os.path.basename(backup_path),
        'warnings': built['plan']['warnings'],
    }))


def page_index(h, ctx):
    h._static('index.html')


def page_static(h, ctx):
    name = os.path.basename(ctx['path'])
    allowed = {'app.js', 'style.css', 'favicon.ico'}
    if name not in allowed:
        h._json(fail('资源不存在: ' + name, 'not_found'), 404)
        return
    if name == 'favicon.ico':
        h._raw(b'', 'image/x-icon')
        return
    h._static(name)


ROUTES = {
    ('GET', '/api/health'): api_health,
    ('GET', '/api/bootstrap'): api_bootstrap,
    ('GET', '/api/settings'): api_get_settings,
    ('PUT', '/api/settings'): api_put_settings,
    ('POST', '/api/settings/period'): api_add_period,
    ('PUT', '/api/settings/period'): api_update_period,
    ('POST', '/api/settings/period/move'): api_move_period,
    ('DELETE', '/api/settings/period'): api_delete_period,
    ('GET', '/api/courses'): api_list_courses,
    ('POST', '/api/courses'): api_add_course,
    ('PUT', '/api/courses'): api_update_course,
    ('DELETE', '/api/courses'): api_delete_course,
    ('POST', '/api/courses/copy'): api_copy_week,
    ('POST', '/api/courses/clear'): api_clear_week,
    ('POST', '/api/import/preview'): api_import_preview,
    ('POST', '/api/import'): api_import,
    ('GET', '/api/notes'): api_list_notes,
    ('POST', '/api/notes'): api_add_note,
    ('PUT', '/api/notes'): api_update_note,
    ('DELETE', '/api/notes'): api_delete_note,
    ('POST', '/api/notes/toggle'): api_toggle_note_item,
    ('GET', '/api/weather'): api_weather,
    ('GET', '/api/home'): api_home,
    ('GET', '/api/backup'): api_backup,
    ('POST', '/api/restore'): api_restore,
    ('POST', '/api/open-folder'): api_open_folder,
    ('POST', '/api/reset-all'): api_reset_all,
    ('GET', '/api/cities'): api_cities,
    ('GET', '/api/places'): api_list_places,
    ('POST', '/api/places'): api_add_place,
    ('POST', '/api/places/select'): api_select_place,
    ('DELETE', '/api/places'): api_delete_place,
    ('GET', '/'): page_index,
    ('GET', '/index.html'): page_index,
    ('GET', '/app.js'): page_static,
    ('GET', '/style.css'): page_static,
    ('GET', '/favicon.ico'): page_static,
}

DATA_DIR = None
PORT = None


def lock_path(data_dir):
    return os.path.join(data_dir, 'server.lock')


def check_running_instance(data_dir):
    """同一份数据目录已经有实例在跑时返回它的端口，否则 None。"""
    path = lock_path(data_dir)
    if not os.path.isfile(path):
        return None
    try:
        info = json.loads(open(path, 'r', encoding='utf-8').read())
        port = int(info.get('port') or 0)
    except Exception:
        return None
    if not port:
        return None
    try:
        req = urllib.request.Request('http://127.0.0.1:%d/api/health' % port, method='GET')
        with urllib.request.urlopen(req, timeout=2) as resp:
            body = json.loads(resp.read().decode('utf-8'))
        if body.get('ok'):
            return port
    except Exception:
        return None
    return None


def write_lock(data_dir, port):
    try:
        with open(lock_path(data_dir), 'w', encoding='utf-8') as f:
            json.dump({'pid': os.getpid(), 'port': port,
                       'startedAt': now_iso()}, f)
    except OSError as exc:
        emit('[MyDay] 写实例锁失败：' + str(exc))


class MyDayServer(ThreadingHTTPServer):
    """关掉 SO_REUSEADDR：Windows 上它会让两个实例绑同一个端口，必须避免。"""

    allow_reuse_address = False
    daemon_threads = True


def pick_port(start=8765, tries=12):
    port = start
    for _ in range(tries):
        try:
            srv = MyDayServer(('127.0.0.1', port), Handler)
            return srv, port
        except OSError:
            port += 1
    raise SystemExit('[MyDay] 从 %d 开始的端口都被占用了' % start)


def emit(msg):
    print(msg)
    try:
        sys.stdout.flush()
    except Exception:
        pass


def main(argv=None):
    global DATA_DIR, PORT
    parser = argparse.ArgumentParser(description='MyDay 本地服务')
    parser.add_argument('--data', default=None, help='数据目录，默认 D:\\App\\MyDay\\data')
    parser.add_argument('--port', type=int, default=0, help='端口，默认从 8765 开始自动找')
    parser.add_argument('--no-browser', action='store_true', help='不自动打开浏览器')
    parser.add_argument('--port-file', default=None, help='把最终使用的端口写入这个文件')
    args = parser.parse_args(argv)

    DATA_DIR = args.data or os.getenv('MYDAY_DATA') or os.path.join(ROOT_DIR, 'data')
    os.makedirs(DATA_DIR, exist_ok=True)
    store.init(DATA_DIR)

    alive = check_running_instance(DATA_DIR)
    if alive:
        emit('MyDay 已经在运行了：http://127.0.0.1:%d/' % alive)
        emit('不需要再开一个窗口。（要重启的话，先把上一个 MyDay 窗口关掉）')
        if not args.no_browser:
            webbrowser.open('http://127.0.0.1:%d/' % alive)
        return

    srv = None
    if args.port:
        try:
            srv = MyDayServer(('127.0.0.1', args.port), Handler)
            PORT = args.port
        except OSError:
            emit('[MyDay] 端口 %d 被占用，换一个' % args.port)
    if srv is None:
        srv, PORT = pick_port()

    url = 'http://127.0.0.1:%d/' % PORT
    if args.port_file:
        try:
            with open(args.port_file, 'w', encoding='utf-8') as f:
                f.write(str(PORT))
        except OSError as exc:
            emit('[MyDay] 写端口文件失败：' + str(exc))

    write_lock(DATA_DIR, PORT)

    emit('=' * 46)
    emit('  MyDay is running at ' + url)
    emit('  数据目录: ' + DATA_DIR)
    emit('  停止服务: 关掉这个窗口或按 Ctrl+C')
    emit('=' * 46)

    if not args.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()

    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print('\n[MyDay] 已停止')
    finally:
        srv.server_close()


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass
    main()
