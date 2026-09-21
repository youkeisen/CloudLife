# -*- coding: utf-8 -*-
"""数据层：四份 JSON 的读写、默认值、原子写、损坏恢复。"""
import json
import os
import tempfile
import threading
import time
import uuid
from datetime import date, datetime, timedelta, timezone

CST = timezone(timedelta(hours=8))
SCHEMA_VERSION = 1

DEFAULT_SETTINGS = {
    'version': SCHEMA_VERSION,
    'displayName': '',
    'semesterName': '',
    'week1Monday': '',
    'weekStartsOn': 1,
    'campus': '',
    'periods': [],
    'weatherCity': {'name': '', 'latitude': None, 'longitude': None, 'timezone': 'Asia/Shanghai'},
    'weatherCities': [],
    'refreshMinutes': 30,
    'theme': 'system',
}

EMPTY_CITY = {'name': '', 'latitude': None, 'longitude': None, 'timezone': 'Asia/Shanghai'}
MAX_PLACES = 20

DEFAULT_COURSES = {'version': SCHEMA_VERSION, 'weeks': {}}
DEFAULT_NOTES = {'version': SCHEMA_VERSION, 'notes': []}
DEFAULT_WEATHER = {
    'version': SCHEMA_VERSION,
    'fetchedAt': '',
    'city': {'name': '', 'latitude': None, 'longitude': None},
    'payload': None,
}

DEFAULTS = {
    'settings': DEFAULT_SETTINGS,
    'courses': DEFAULT_COURSES,
    'notes': DEFAULT_NOTES,
    'weather_cache': DEFAULT_WEATHER,
}

_lock = threading.RLock()
_data_dir = None
_warnings = []


def init(data_dir):
    global _data_dir, _warnings
    _data_dir = str(data_dir)
    _warnings = []
    os.makedirs(_data_dir, exist_ok=True)
    os.makedirs(backups_dir(), exist_ok=True)
    ensure_files()
    drop_legacy_note_tags()
    return _data_dir


def data_dir():
    return _data_dir


def backups_dir():
    return os.path.join(_data_dir, 'backups')


def warnings():
    return list(_warnings)


def clear_warnings():
    global _warnings
    _warnings = []


def append_warning(name, message, broken_copy=''):
    _warnings.append({'file': name + '.json', 'brokenCopy': broken_copy, 'message': message})


def filepath(name):
    return os.path.join(_data_dir, name + '.json')


def _default_of(name):
    return json.loads(json.dumps(DEFAULTS[name]))


def ensure_files():
    for name in DEFAULTS:
        p = filepath(name)
        if not os.path.isfile(p):
            write(name, _default_of(name))


def drop_legacy_note_tags():
    """把存量数据里的旧 tags 字段抹掉（去掉标签功能，和手机版对齐）。

    为什么非要单独清一遍：「不再解析 tags」清不掉文件里的旧数据 ——
    用户没编辑过的笔记不会重写，那些 tags 会一直躺在 notes.json 里。
    所以启动时扫一遍、有残留才重写（没残留不写，否则每次启动都写一次文件）。
    """
    try:
        obj = read('notes')
    except Exception:
        return
    notes = obj.get('notes')
    if not isinstance(notes, list):
        return
    changed = False
    for n in notes:
        if isinstance(n, dict) and 'tags' in n:
            n.pop('tags', None)
            changed = True
    if changed:
        write('notes', obj)


def write(name, obj):
    """原子写：临时文件 -> os.replace，避免中断写坏文件。"""
    path = filepath(name)
    directory = os.path.dirname(path)
    with _lock:
        fd, tmp = tempfile.mkstemp(prefix=name + '.', suffix='.tmp', dir=directory)
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                json.dump(obj, f, ensure_ascii=False, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, path)
        except Exception:
            if os.path.exists(tmp):
                try:
                    os.remove(tmp)
                except OSError:
                    pass
            raise
    return obj


def read(name):
    """读一份数据；坏文件改名留存，返回默认值并记录警告。"""
    path = filepath(name)
    if not os.path.isfile(path):
        obj = _default_of(name)
        write(name, obj)
        return obj
    try:
        with open(path, 'r', encoding='utf-8') as f:
            obj = json.load(f)
    except Exception as exc:
        stamp = time.strftime('%Y%m%d-%H%M%S')
        broken = path + '.corrupt-' + stamp
        try:
            os.replace(path, broken)
        except OSError:
            pass
        _warnings.append({
            'file': name + '.json',
            'brokenCopy': os.path.basename(broken),
            'message': '数据文件损坏，已恢复默认内容：' + name + '.json（' + str(exc) + '）',
        })
        obj = _default_of(name)
        write(name, obj)
        return obj
    if not isinstance(obj, dict):
        obj = _default_of(name)
        write(name, obj)
    obj.setdefault('version', SCHEMA_VERSION)
    return obj


# ---------- 小工具 ----------
_counter = [0]


def new_id(prefix):
    _counter[0] += 1
    return '%s%s_%d_%s' % (prefix, datetime.now(CST).strftime('%Y%m%d%H%M%S'),
                           _counter[0], uuid.uuid4().hex[:8])


def today_iso():
    return datetime.now(CST).date().isoformat()


def week_of(date_iso, week1_monday):
    """第几教学周；未设置或早于第一周返回 None。"""
    if not week1_monday:
        return None
    try:
        d = date.fromisoformat(date_iso)
        start = date.fromisoformat(week1_monday)
    except ValueError:
        return None
    delta = (d - start).days
    if delta < 0:
        return None
    return delta // 7 + 1


def monday_of(week, week1_monday):
    if not week1_monday:
        return None
    start = date.fromisoformat(week1_monday)
    return (start + timedelta(days=7 * (int(week) - 1))).isoformat()


# ---------- 设置 ----------
def get_settings():
    s = read('settings')
    base = _default_of('settings')
    for k, v in base.items():
        if k not in s:
            s[k] = v
    return s


def save_settings(obj):
    cleaned = json.loads(json.dumps(get_settings()))
    cleaned.update(obj or {})
    cleaned['version'] = SCHEMA_VERSION
    cleaned['periods'] = list(obj.get('periods', cleaned.get('periods', [])))
    return write('settings', cleaned)


def periods():
    return get_settings().get('periods', [])


def next_period_id():
    ids = [p.get('id', '') for p in periods()]
    n = 1
    while ('p%d' % n) in ids:
        n += 1
    return 'p%d' % n


def period_usage(pid):
    """有多少节课用到了某个节次。"""
    count = 0
    for _w, lessons in read('courses').get('weeks', {}).items():
        for c in lessons:
            if c.get('slot') == pid or c.get('spanEnd') == pid:
                count += 1
    return count


def delete_period(pid, mode='cancel'):
    """删除节次。mode: move / drop / cancel。返回 {used, deleted}"""
    used = period_usage(pid)
    if used and mode == 'cancel':
        return {'used': used, 'deleted': False}
    settings = get_settings()
    rest = [p for p in settings['periods'] if p.get('id') != pid]
    if used:
        if mode == 'drop':
            raw = read('courses')
            for w in list(raw.get('weeks', {}).keys()):
                raw['weeks'][w] = [c for c in raw['weeks'][w]
                                   if c.get('slot') != pid and c.get('spanEnd') != pid]
            write('courses', raw)
        else:  # move
            target = rest[0]['id'] if rest else None
            raw = read('courses')
            for w in list(raw.get('weeks', {}).keys()):
                for c in raw['weeks'][w]:
                    if c.get('slot') == pid:
                        c['slot'] = target
                    if c.get('spanEnd') == pid:
                        c['spanEnd'] = ''
            write('courses', raw)
    settings['periods'] = rest
    write('settings', settings)
    return {'used': used, 'deleted': True}


def ensure_periods(labels):
    """按给定顺序确保这些节次存在（名称相同的直接复用）。

    返回 (label -> id 的映射, 新建出来的节次列表)。
    时间一律留空，由用户自己填——导入不替用户猜作息。
    """
    settings = get_settings()
    periods = list(settings.get('periods') or [])
    used_ids = {p.get('id', '') for p in periods}
    by_label = {}
    for p in periods:
        by_label.setdefault(str(p.get('label') or '').strip(), p)

    def next_id():
        n = 1
        while ('p%d' % n) in used_ids:
            n += 1
        pid = 'p%d' % n
        used_ids.add(pid)
        return pid

    mapping = {}
    created = []
    for label in labels:
        label = str(label or '').strip()
        if not label:
            continue
        hit = by_label.get(label)
        if hit is not None:
            mapping[label] = hit['id']
            continue
        item = {'id': next_id(), 'label': label, 'start': '', 'end': ''}
        periods.append(item)
        by_label[label] = item
        mapping[label] = item['id']
        created.append(item)
    if created:
        settings['periods'] = periods
        write('settings', settings)
    return mapping, created


# ---------- 我的地点 ----------
def _coord(value, low, high):
    """把坐标收成合法数字；不合法返回 None。"""
    if isinstance(value, bool) or value is None or value == '':
        return None
    try:
        num = float(value)
    except (TypeError, ValueError):
        return None
    if num != num or num in (float('inf'), float('-inf')):
        return None
    if num < low or num > high:
        return None
    return round(num, 4)


def normalize_place(data):
    """把入参整理成标准地点；不合法就抛 ValueError。"""
    data = data or {}
    name = str(data.get('name') or '').strip()
    if not name:
        raise ValueError('地点名称不能为空')
    lat = _coord(data.get('latitude'), -90.0, 90.0)
    lon = _coord(data.get('longitude'), -180.0, 180.0)
    if lat is None or lon is None:
        raise ValueError('经纬度不合法，纬度 -90~90、经度 -180~180')
    return {
        'id': str(data.get('id') or ''),
        'name': name,
        'admin': str(data.get('admin') or '').strip(),
        'latitude': lat,
        'longitude': lon,
        'timezone': str(data.get('timezone') or 'Asia/Shanghai'),
    }


def list_places():
    """已保存的地点列表；坏条目直接跳过，不让它拖垮页面。"""
    places = []
    for raw in get_settings().get('weatherCities') or []:
        try:
            places.append(normalize_place(raw))
        except ValueError:
            continue
    return places


def _same_place(a, b):
    return (abs(a['latitude'] - b['latitude']) < 1e-4 and
            abs(a['longitude'] - b['longitude']) < 1e-4)


def _is_current(current, place):
    if not current or not current.get('name'):
        return False
    if current.get('name') != place['name']:
        return False
    try:
        return (abs(float(current.get('latitude')) - place['latitude']) < 1e-4 and
                abs(float(current.get('longitude')) - place['longitude']) < 1e-4)
    except (TypeError, ValueError):
        return False


def _as_current(place):
    return {'name': place['name'], 'latitude': place['latitude'],
            'longitude': place['longitude'], 'timezone': place['timezone']}


def _save_places(places, current):
    settings = get_settings()
    settings['weatherCities'] = places
    settings['weatherCity'] = current
    write('settings', settings)
    return settings


def add_place(data):
    """添加地点并设为当前；坐标相同的视为同一个地点，只改名不重复添加。"""
    incoming = normalize_place(data)
    places = list_places()
    created = True
    target = None
    for p in places:
        if _same_place(p, incoming):
            created = False
            target = p
            p['name'] = incoming['name']
            if incoming['admin']:
                p['admin'] = incoming['admin']
            break
    if target is None:
        if len(places) >= MAX_PLACES:
            raise ValueError('最多保存 %d 个地点，先删掉几个再加' % MAX_PLACES)
        target = dict(incoming)
        target['id'] = new_id('pl')
        places.append(target)
    current = _as_current(target)
    settings = _save_places(places, current)
    return {'place': target, 'created': created, 'places': places,
            'current': current, 'settings': settings}


def find_place(pid):
    for p in list_places():
        if p['id'] == pid:
            return p
    return None


def select_place(pid):
    """把某个已保存地点设为当前城市。"""
    place = find_place(pid)
    if place is None:
        return None
    places = list_places()
    current = _as_current(place)
    settings = _save_places(places, current)
    return {'place': place, 'places': places, 'current': current, 'settings': settings}


def remove_place(pid):
    """删除已保存地点；删掉当前城市就顺位到第一个，没有剩余就清空当前城市。"""
    places = list_places()
    removed = None
    rest = []
    for p in places:
        if p['id'] == pid and removed is None:
            removed = p
            continue
        rest.append(p)
    if removed is None:
        return {'deleted': False, 'places': places,
                'current': get_settings().get('weatherCity') or EMPTY_CITY}
    settings = get_settings()
    current = settings.get('weatherCity') or EMPTY_CITY
    if _is_current(current, removed):
        current = _as_current(rest[0]) if rest else dict(EMPTY_CITY)
    settings = _save_places(rest, current)
    return {'deleted': True, 'place': removed, 'places': rest,
            'current': current, 'settings': settings}


# ---------- 课程 ----------
def get_courses_raw():
    raw = read('courses')
    raw.setdefault('weeks', {})
    return raw


def list_week(week):
    raw = get_courses_raw()
    return list(raw['weeks'].get(str(int(week)), []))


def save_week(week, lessons):
    raw = get_courses_raw()
    raw['weeks'][str(int(week))] = lessons
    write('courses', raw)
    return lessons


def find_course(cid):
    raw = get_courses_raw()
    for week, lessons in raw['weeks'].items():
        for c in lessons:
            if c.get('id') == cid:
                return week, c
    return None, None


def add_course(data):
    week = int(data.get('week') or 1)
    lessons = list_week(week)
    item = {
        'id': new_id('c'),
        'day': int(data.get('day') or 1),
        'slot': str(data.get('slot') or ''),
        'spanEnd': str(data.get('spanEnd') or ''),
        'name': str(data.get('name') or '').strip(),
        'location': str(data.get('location') or '').strip(),
        'teacher': str(data.get('teacher') or '').strip(),
        'note': str(data.get('note') or '').strip(),
        'color': str(data.get('color') or '').strip(),
    }
    if not item['name']:
        raise ValueError('课程名不能为空')
    lessons.append(item)
    save_week(week, lessons)
    return item


def update_course(data):
    cid = data.get('id')
    if not cid:
        raise ValueError('缺少课程 id')
    raw = get_courses_raw()
    weeks = raw['weeks']
    found_week, item = None, None
    for w in list(weeks.keys()):
        for c in weeks[w]:
            if c.get('id') == cid:
                found_week, item = w, c
                break
        if item:
            break
    if item is None:
        raise ValueError('课程不存在：' + str(cid))
    for field in ('day', 'slot', 'spanEnd', 'name', 'location', 'teacher', 'note', 'color'):
        if field in data:
            item[field] = data[field]
    if data.get('week') is not None:
        target = str(int(data['week']))
        if target != found_week:
            weeks[found_week] = [c for c in weeks[found_week] if c.get('id') != cid]
            weeks.setdefault(target, []).append(item)
    write('courses', raw)
    return item


def delete_course(cid):
    week, item = find_course(cid)
    if item is None:
        return False
    lessons = [c for c in list_week(week) if c.get('id') != cid]
    save_week(week, lessons)
    return True


def copy_week(src_week, targets, mode='overwrite'):
    """整周复制。mode: overwrite / merge / empty-only"""
    source = list_week(src_week)
    result = {}
    for t in targets:
        t = int(t)
        if t == int(src_week):
            continue
        dest = list_week(t)
        fresh = []
        for c in source:
            clone = dict(c)
            clone['id'] = new_id('c') + str(len(fresh))
            fresh.append(clone)
        if mode == 'overwrite':
            final = fresh
        elif mode == 'merge':
            final = dest + fresh
        else:  # empty-only
            final = fresh if not dest else dest
        save_week(t, final)
        result[str(t)] = len(final)
    return result


def clear_week(week):
    save_week(week, [])
    return True


def import_courses(by_week, mode='merge'):
    """把导入解析出来的课按周写进去。

    by_week: {周次: [课程...]}，课程里已经带好 slot / spanEnd 等字段。
    mode: merge 追加，overwrite 覆盖整周。
    """
    raw = get_courses_raw()
    weeks = raw['weeks']
    added = 0
    touched = []
    for week in sorted(by_week, key=lambda w: int(w)):
        key = str(int(week))
        fresh = []
        for lesson in by_week[week]:
            item = dict(lesson)
            item['id'] = new_id('c') + str(len(fresh))
            fresh.append(item)
        if mode == 'overwrite':
            weeks[key] = fresh
        else:
            weeks[key] = list(weeks.get(key) or []) + fresh
        added += len(fresh)
        touched.append(int(week))
    write('courses', raw)
    return {'added': added, 'weeks': touched}


# ---------- 备忘录 ----------
def list_notes(include_archived=False):
    notes = read('notes').get('notes', [])
    if include_archived:
        return list(notes)
    return [n for n in notes if not n.get('archived')]


def save_notes_obj(notes):
    raw = read('notes')
    raw['notes'] = notes
    raw['version'] = SCHEMA_VERSION
    return write('notes', raw)


def add_note(data):
    notes = read('notes').get('notes', [])
    item = {
        'id': new_id('n'),
        'title': str(data.get('title') or '').strip(),
        'type': data.get('type') or 'text',
        'body': str(data.get('body') or ''),
        'items': [{'text': str(i.get('text', '')), 'done': bool(i.get('done'))}
                  for i in (data.get('items') or [])],
        'pinned': bool(data.get('pinned')),
        'archived': bool(data.get('archived')),
        'createdAt': datetime.now(CST).isoformat(timespec='seconds'),
        'updatedAt': datetime.now(CST).isoformat(timespec='seconds'),
    }
    notes.append(item)
    save_notes_obj(notes)
    return item


def update_note(data):
    cid = data.get('id')
    notes = read('notes').get('notes', [])
    for n in notes:
        if n.get('id') == cid:
            for field in ('title', 'type', 'body', 'items', 'pinned', 'archived'):
                if field in data:
                    n[field] = data[field]
            n['updatedAt'] = datetime.now(CST).isoformat(timespec='seconds')
            save_notes_obj(notes)
            return n
    raise ValueError('备忘录不存在：' + str(cid))


def delete_note(cid):
    notes = read('notes').get('notes', [])
    rest = [n for n in notes if n.get('id') != cid]
    if len(rest) == len(notes):
        return False
    save_notes_obj(rest)
    return True


def toggle_note_item(cid, index):
    """只翻转某一条清单项，顺便避免整段回写把没显示出来的项冲掉。"""
    try:
        index = int(index)
    except (TypeError, ValueError):
        return None
    notes = read('notes').get('notes', [])
    for n in notes:
        if n.get('id') != cid:
            continue
        items = n.get('items') or []
        if index < 0 or index >= len(items):
            return None
        items[index]['done'] = not bool(items[index].get('done'))
        n['items'] = items
        n['updatedAt'] = datetime.now(CST).isoformat(timespec='seconds')
        save_notes_obj(notes)
        return n
    return None


# ---------- 天气缓存 ----------
def get_weather_cache():
    return read('weather_cache')


def set_weather_cache(city, payload):
    obj = {
        'version': SCHEMA_VERSION,
        'fetchedAt': datetime.now(CST).isoformat(timespec='seconds'),
        'city': city or {'name': '', 'latitude': None, 'longitude': None},
        'payload': payload,
    }
    write('weather_cache', obj)
    return obj
