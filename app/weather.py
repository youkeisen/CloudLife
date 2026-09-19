# -*- coding: utf-8 -*-
"""天气：请求 Open-Meteo（免 key）、归一化、中文映射、生活提示。"""
import json
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

TIMEOUT = 8
CST = timezone(timedelta(hours=8))
API = 'https://api.open-meteo.com/v1/forecast'
GEO = 'https://geocoding-api.open-meteo.com/v1/search'


class WeatherError(Exception):
    pass


WMO_CODES = {
    0: ('晴', 'sun'),
    1: ('大部晴朗', 'sun'),
    2: ('局部多云', 'cloud'),
    3: ('阴', 'cloud'),
    45: ('雾', 'fog'),
    48: ('雾凇', 'fog'),
    51: ('毛毛雨', 'drizzle'),
    53: ('细雨', 'drizzle'),
    55: ('密集毛毛雨', 'drizzle'),
    56: ('冻毛毛雨', 'drizzle'),
    57: ('强冻雨', 'drizzle'),
    61: ('小雨', 'rain'),
    63: ('中雨', 'rain'),
    65: ('大雨', 'rain'),
    66: ('冻雨', 'rain'),
    67: ('强冻雨', 'rain'),
    71: ('小雪', 'snow'),
    73: ('中雪', 'snow'),
    75: ('大雪', 'snow'),
    77: ('米雪', 'snow'),
    80: ('阵雨', 'shower'),
    81: ('强阵雨', 'shower'),
    82: ('暴雨', 'shower'),
    85: ('阵雪', 'snow'),
    86: ('强阵雪', 'snow'),
    95: ('雷阵雨', 'thunder'),
    96: ('雷阵雨伴冰雹', 'thunder'),
    99: ('强雷暴冰雹', 'thunder'),
}

WIND_NAMES = ['北', '东北偏北', '东北', '东北偏东', '东', '东南偏东', '东南', '东南偏南',
              '南', '西南偏南', '西南', '西南偏西', '西', '西北偏西', '西北', '西北偏北']


def wmo_text(code):
    try:
        return WMO_CODES[int(code)][0]
    except (KeyError, TypeError, ValueError):
        return '未知天气'


def wmo_icon(code):
    try:
        return WMO_CODES[int(code)][1]
    except (KeyError, TypeError, ValueError):
        return 'cloud'


def wind_dir_name(deg):
    if deg is None:
        return ''
    try:
        idx = int((float(deg) % 360) / 22.5 + 0.5) % 16
        return WIND_NAMES[idx]
    except (TypeError, ValueError):
        return ''


def build_forecast_url(lat, lon, days=7):
    params = {
        'latitude': lat,
        'longitude': lon,
        'current': ('temperature_2m,relative_humidity_2m,apparent_temperature,is_day,'
                    'weather_code,wind_speed_10m,wind_direction_10m,surface_pressure'),
        'hourly': 'temperature_2m,precipitation_probability,visibility',
        'daily': ('weather_code,temperature_2m_max,temperature_2m_min,'
                  'precipitation_probability_max,uv_index_max'),
        'timezone': 'Asia/Shanghai',
        'forecast_days': days,
    }
    return API + '?' + urllib.parse.urlencode(params)


def build_geocode_url(name):
    return GEO + '?' + urllib.parse.urlencode({'name': name, 'language': 'zh', 'count': 8})


def _place_pop(item):
    p = item.get('population')
    return p if isinstance(p, (int, float)) else -1


def merge_place_results(a, b):
    """合并两批城市搜索结果：按坐标去重（同名城市两套查询都会返回），
    人口多的留下；最后按人口从大到小排——大城市天然排前面，
    同名小村子（Open-Meteo 中文数据的常见坑）沉底。"""
    merged = []
    index_of = {}
    for item in list(a or []) + list(b or []):
        key = (round(float(item.get('latitude') or 0) * 100),
               round(float(item.get('longitude') or 0) * 100))
        idx = index_of.get(key)
        if idx is None:
            index_of[key] = len(merged)
            merged.append(item)
        elif _place_pop(item) > _place_pop(merged[idx]):
            merged[idx] = item
    merged.sort(key=_place_pop, reverse=True)
    return merged


def city_query_variant(name):
    """给中文城市名配一个补充查询：阜阳 ↔ 阜阳市。
    Open-Meteo 的中文索引不全——搜「阜阳」只会命中江苏的同名村，
    带「市」后缀才能搜到安徽阜阳市；反过来有的城市又必须去后缀。"""
    name = (name or '').strip()
    if not name:
        return None
    if name.endswith('市'):
        return name[:-1] or None
    if all('\u4e00' <= ch <= '\u9fff' for ch in name):
        return name + '市'
    return None


def _geocode(name, timeout):
    raw = http_get_json(build_geocode_url(name), timeout)
    return [{
        'name': item.get('name'),
        'admin': item.get('admin1') or '',
        'country': item.get('country') or '',
        'latitude': item.get('latitude'),
        'longitude': item.get('longitude'),
        'population': item.get('population'),
    } for item in (raw.get('results') or [])]


def search_cities(name, timeout=TIMEOUT):
    name = (name or '').strip()
    results = _geocode(name, timeout)
    variant = city_query_variant(name)
    if variant:
        try:
            results = merge_place_results(results, _geocode(variant, timeout))
        except Exception:
            pass  # 补充查询失败不影响第一发的结果
    return results



def reverse_geocode(latitude, longitude, timeout=TIMEOUT):
    """用坐标反查地名（Nominatim 免费服务，给「定位添加地点」用）。

    返回 {'name': 城市名, 'admin': 省/州}；拿不到像样的名字就抛 WeatherError。
    """
    url = ('https://nominatim.openstreetmap.org/reverse?'
           + urllib.parse.urlencode({
               'format': 'jsonv2',
               'lat': latitude,
               'lon': longitude,
               'accept-language': 'zh',
               'zoom': 10,
           }))
    req = urllib.request.Request(
        url, headers={'User-Agent': 'MyDay/1.x (personal app)'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = json.loads(resp.read().decode('utf-8'))
    except Exception as exc:
        raise WeatherError('反查地名失败：%s' % exc)
    address = raw.get('address') or {}
    name = ''
    for key in ('city', 'town', 'county', 'village', 'state'):
        value = str(address.get(key) or '').strip()
        if value:
            name = value
            break
    if not name:
        raise WeatherError('定位到了坐标，但没认出城市名')
    return {'name': name, 'admin': str(address.get('state') or '').strip()}


def http_get_json(url, timeout=TIMEOUT):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as exc:
        raise WeatherError(str(exc))


def fetch_weather(lat, lon, timeout=TIMEOUT):
    return http_get_json(build_forecast_url(lat, lon), timeout)


def _as_aware(dt):
    if dt.tzinfo is None:
        return dt.replace(tzinfo=CST)
    return dt.astimezone(CST)


def _hour_index(times, target):
    """找到 <= 目标时刻的最近一小时的位置；接口返回的时间没有时区，统一按本地时区算。"""
    best = None
    target = _as_aware(target)
    for i, t in enumerate(times or []):
        try:
            dt = _as_aware(datetime.fromisoformat(t))
        except ValueError:
            continue
        if dt <= target:
            best = i
        else:
            break
    return best if best is not None else 0


def round1(v):
    try:
        return round(float(v), 1)
    except (TypeError, ValueError):
        return None


def normalize(raw, city):
    cur = raw.get('current') or {}
    hourly = raw.get('hourly') or {}
    daily = raw.get('daily') or {}
    now = datetime.now(CST)
    start = _hour_index(hourly.get('time'), now.replace(minute=0, second=0, microsecond=0))
    hours = []
    for i in range(start, min(start + 24, len(hourly.get('time') or []))):
        hours.append({
            'time': (hourly['time'][i][11:16] if 'T' in hourly['time'][i] else hourly['time'][i][-5:]),
            'temp': round1((hourly.get('temperature_2m') or [None] * len(hourly['time']))[i]),
            'pop': (hourly.get('precipitation_probability') or [None] * len(hourly['time']))[i],
        })
    visibility = None
    vis_list = hourly.get('visibility') or []
    if vis_list and start < len(vis_list):
        visibility = round1(vis_list[start] / 1000.0) if vis_list[start] is not None else None

    def _at(bucket, key, i):
        arr = bucket.get(key) or []
        return arr[i] if i < len(arr) else None

    days = []
    for i, d in enumerate(daily.get('time') or []):
        code = _at(daily, 'weather_code', i)
        days.append({
            'date': d,
            'code': code,
            'text': wmo_text(code),
            'icon': wmo_icon(code),
            'max': round1(_at(daily, 'temperature_2m_max', i)),
            'min': round1(_at(daily, 'temperature_2m_min', i)),
            'pop': _at(daily, 'precipitation_probability_max', i),
            'uv': round1(_at(daily, 'uv_index_max', i)),
        })

    code = cur.get('weather_code')
    current = {
        'temp': round1(cur.get('temperature_2m')),
        'feels': round1(cur.get('apparent_temperature')),
        'humidity': cur.get('relative_humidity_2m'),
        'code': code,
        'text': wmo_text(code),
        'icon': wmo_icon(code),
        'wind': round1(cur.get('wind_speed_10m')),
        'windDirDeg': round1(cur.get('wind_direction_10m')),
        'windDir': wind_dir_name(cur.get('wind_direction_10m')),
        'pressure': round1(cur.get('surface_pressure')),
        'visibility': visibility,
        'pop': (hours[0]['pop'] if hours else None),
        'isDay': cur.get('is_day'),
    }
    payload = {
        'city': {'name': (city or {}).get('name', ''),
                 'latitude': (city or {}).get('latitude'),
                 'longitude': (city or {}).get('longitude')},
        'current': current,
        'hourly': hours,
        'daily': days,
    }
    payload['tips'] = build_tips(payload)
    return payload


def build_tips(payload):
    tips = []
    days = payload.get('daily') or []
    hours = payload.get('hourly') or []
    today = days[0] if days else None
    if today and today.get('max') is not None and today.get('min') is not None:
        try:
            if float(today['max']) - float(today['min']) >= 8:
                tips.append('昼夜温差约 %d 度，早晚加件外套'
                            % round(float(today['max']) - float(today['min'])))
        except (TypeError, ValueError):
            pass
    pop_today = None
    for h in hours[:6]:
        try:
            v = float(h.get('pop'))
        except (TypeError, ValueError):
            continue
        pop_today = v if pop_today is None else max(pop_today, v)
    if today and today.get('pop') is not None:
        try:
            pop_today = max(pop_today or 0, float(today['pop']))
        except (TypeError, ValueError):
            pass
    if pop_today is not None and pop_today >= 50:
        tips.append('未来几小时降水概率 %d%%，出门带把伞' % round(pop_today))
    uv = today.get('uv') if today else None
    try:
        if uv is not None and float(uv) >= 6:
            tips.append('紫外线偏强，注意防晒')
    except (TypeError, ValueError):
        pass
    return tips

