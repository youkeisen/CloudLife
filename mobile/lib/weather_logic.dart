/// 天气模块的纯逻辑：不碰网络、不碰界面。
///
/// 行为基准是电脑版：
/// - `D:\App\MyDay\app\weather.py`（WMO 映射、归一化、生活提示、URL 拼法）
/// - `D:\App\MyDay\app\server.py` 的 `weather_result` / `_cache_age_minutes`
///   （缓存新鲜判定、离线降级）
/// - `D:\App\MyDay\app\store.py` 的 `add_place` / `select_place` / `remove_place`
///   （我的地点增删切换）
///
/// 字段名（payload 里的 current/hourly/daily/tips 等）与电脑版一字不差，
/// 这样电脑版缓存里存过的 payload、手机版也能直接读。
library;

import 'models.dart';

// ---------- Open-Meteo 接口地址（免 key） ----------
const String forecastApi = 'https://api.open-meteo.com/v1/forecast';
const String geocodeApi = 'https://geocoding-api.open-meteo.com/v1/search';

// ---------- WMO 天气码 → 中文 + 图标名（和电脑版逐条一致） ----------
const Map<int, List<String>> wmoCodes = <int, List<String>>{
  0: <String>['晴', 'sun'],
  1: <String>['大部晴朗', 'sun'],
  2: <String>['局部多云', 'cloud'],
  3: <String>['阴', 'cloud'],
  45: <String>['雾', 'fog'],
  48: <String>['雾凇', 'fog'],
  51: <String>['毛毛雨', 'drizzle'],
  53: <String>['细雨', 'drizzle'],
  55: <String>['密集毛毛雨', 'drizzle'],
  56: <String>['冻毛毛雨', 'drizzle'],
  57: <String>['强冻雨', 'drizzle'],
  61: <String>['小雨', 'rain'],
  63: <String>['中雨', 'rain'],
  65: <String>['大雨', 'rain'],
  66: <String>['冻雨', 'rain'],
  67: <String>['强冻雨', 'rain'],
  71: <String>['小雪', 'snow'],
  73: <String>['中雪', 'snow'],
  75: <String>['大雪', 'snow'],
  77: <String>['米雪', 'snow'],
  80: <String>['阵雨', 'shower'],
  81: <String>['强阵雨', 'shower'],
  82: <String>['暴雨', 'shower'],
  85: <String>['阵雪', 'snow'],
  86: <String>['强阵雪', 'snow'],
  95: <String>['雷阵雨', 'thunder'],
  96: <String>['雷阵雨伴冰雹', 'thunder'],
  99: <String>['强雷暴冰雹', 'thunder'],
};

String wmoText(dynamic code) {
  final c = _asIntOrNull(code);
  return (c != null && wmoCodes.containsKey(c)) ? wmoCodes[c]![0] : '未知天气';
}

String wmoIcon(dynamic code) {
  final c = _asIntOrNull(code);
  return (c != null && wmoCodes.containsKey(c)) ? wmoCodes[c]![1] : 'cloud';
}

int? _asIntOrNull(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 公开版：解析接口里的整数（人口等字段用）。
int? asIntOrNull(dynamic v) => _asIntOrNull(v);

// ---------- 风向 ----------
const List<String> windNames = <String>[
  '北', '东北偏北', '东北', '东北偏东', '东', '东南偏东', '东南', '东南偏南',
  '南', '西南偏南', '西南', '西南偏西', '西', '西北偏西', '西北', '西北偏北',
];

String windDirName(dynamic deg) {
  final d = asDoubleOrNull(deg);
  if (d == null) return '';
  final idx = ((d % 360) / 22.5 + 0.5).floor() % 16;
  return windNames[idx];
}

// ---------- 数值小工具 ----------
/// 四舍五入到 1 位小数；不是数就返回 null（和电脑版 round1 一致）。
double? round1(dynamic v) {
  final d = asDoubleOrNull(v);
  if (d == null) return null;
  return (d * 10).round() / 10.0;
}

// ---------- 请求 URL ----------
Map<String, String> forecastQuery(num lat, num lon, [int days = 7]) =>
    <String, String>{
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,'
          'weather_code,wind_speed_10m,wind_direction_10m,surface_pressure',
      'hourly': 'temperature_2m,precipitation_probability,visibility',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,uv_index_max',
      'timezone': 'Asia/Shanghai',
      'forecast_days': '$days',
    };

Map<String, String> geocodeQuery(String name) => <String, String>{
      'name': name,
      'language': 'zh',
      'count': '8',
    };

String buildForecastUrl(num lat, num lon, [int days = 7]) {
  final uri = Uri.parse(forecastApi)
      .replace(queryParameters: forecastQuery(lat, lon, days));
  return uri.toString();
}

String buildGeocodeUrl(String name) {
  final uri =
      Uri.parse(geocodeApi).replace(queryParameters: geocodeQuery(name));
  return uri.toString();
}

// ---------- 归一化 ----------
/// 接口返回的小时序列里，找到 <= 目标时刻的最近一小时的位置。
/// 时间串没有时区（如 `2026-09-19T13:00`），统一按本地钟面算（和电脑版一致）。
int hourIndex(List<dynamic> times, DateTime target) {
  var best = -1;
  for (var i = 0; i < times.length; i++) {
    final dt = DateTime.tryParse(asString(times[i]));
    if (dt == null) continue;
    if (!dt.isAfter(target)) {
      best = i;
    } else {
      break;
    }
  }
  return best < 0 ? 0 : best;
}

dynamic _at(Map<String, dynamic> bucket, String key, int i) {
  final arr = bucket[key];
  if (arr is! List || i >= arr.length) return null;
  return arr[i];
}

/// 把 Open-Meteo 的原始返回整理成界面要用的 payload。
/// 结构和电脑版 `weather.normalize` 一致：city / current / hourly / daily / tips。
Map<String, dynamic> normalize(Map<String, dynamic> raw, City city,
    {DateTime? now}) {
  final cur = asMap(raw['current']);
  final hourly = asMap(raw['hourly']);
  final daily = asMap(raw['daily']);
  final n = now ?? DateTime.now();
  final target = DateTime(n.year, n.month, n.day, n.hour);

  final times = hourly['time'] is List ? hourly['time'] as List : const <dynamic>[];
  final start = hourIndex(times, target);

  final hours = <Map<String, dynamic>>[];
  final end = start + 24 < times.length ? start + 24 : times.length;
  for (var i = start; i < end; i++) {
    final t = asString(times[i]);
    final hhmm = t.contains('T') && t.length >= 16
        ? t.substring(11, 16)
        : (t.length >= 5 ? t.substring(t.length - 5) : t);
    hours.add(<String, dynamic>{
      'time': hhmm,
      'temp': round1(_at(hourly, 'temperature_2m', i)),
      'pop': _at(hourly, 'precipitation_probability', i),
    });
  }

  double? visibility;
  final visList = hourly['visibility'];
  if (visList is List && start < visList.length && visList[start] != null) {
    final km = asDoubleOrNull(visList[start]);
    if (km != null) visibility = round1(km / 1000.0);
  }

  final days = <Map<String, dynamic>>[];
  final dailyTimes = daily['time'] is List ? daily['time'] as List : const <dynamic>[];
  for (var i = 0; i < dailyTimes.length; i++) {
    final code = _at(daily, 'weather_code', i);
    days.add(<String, dynamic>{
      'date': asString(dailyTimes[i]),
      'code': code,
      'text': wmoText(code),
      'icon': wmoIcon(code),
      'max': round1(_at(daily, 'temperature_2m_max', i)),
      'min': round1(_at(daily, 'temperature_2m_min', i)),
      'pop': _at(daily, 'precipitation_probability_max', i),
      'uv': round1(_at(daily, 'uv_index_max', i)),
    });
  }

  final code = cur['weather_code'];
  final current = <String, dynamic>{
    'temp': round1(cur['temperature_2m']),
    'feels': round1(cur['apparent_temperature']),
    'humidity': cur['relative_humidity_2m'],
    'code': code,
    'text': wmoText(code),
    'icon': wmoIcon(code),
    'wind': round1(cur['wind_speed_10m']),
    'windDirDeg': round1(cur['wind_direction_10m']),
    'windDir': windDirName(cur['wind_direction_10m']),
    'pressure': round1(cur['surface_pressure']),
    'visibility': visibility,
    'pop': hours.isNotEmpty ? hours[0]['pop'] : null,
    'isDay': cur['is_day'],
  };

  final payload = <String, dynamic>{
    'city': <String, dynamic>{
      'name': city.name,
      'latitude': city.latitude,
      'longitude': city.longitude,
    },
    'current': current,
    'hourly': hours,
    'daily': days,
  };
  payload['tips'] = buildTips(payload);
  return payload;
}

// ---------- 生活提示 ----------
/// 规则和电脑版 `build_tips` 一致：温差 ≥8 度、降水概率 ≥50%、紫外线 ≥6。
List<String> buildTips(Map<String, dynamic> payload) {
  final tips = <String>[];
  final days = payload['daily'] is List ? payload['daily'] as List : const <dynamic>[];
  final hours = payload['hourly'] is List ? payload['hourly'] as List : const <dynamic>[];
  final today = days.isNotEmpty ? asMap(days[0]) : null;

  if (today != null && today['max'] != null && today['min'] != null) {
    final maxV = asDoubleOrNull(today['max']);
    final minV = asDoubleOrNull(today['min']);
    if (maxV != null && minV != null && maxV - minV >= 8) {
      tips.add('昼夜温差约 ${(maxV - minV).round()} 度，早晚加件外套');
    }
  }

  double? popToday;
  for (final h in hours.take(6)) {
    final v = asDoubleOrNull(asMap(h)['pop']);
    if (v == null) continue;
    popToday = (popToday == null || v > popToday) ? v : popToday;
  }
  if (today != null && today['pop'] != null) {
    final v = asDoubleOrNull(today['pop']);
    if (v != null) {
      popToday = (popToday == null || v > popToday) ? v : popToday;
    }
  }
  if (popToday != null && popToday >= 50) {
    tips.add('未来几小时降水概率 ${popToday.round()}%，出门带把伞');
  }

  if (today != null && today['uv'] != null) {
    final uv = asDoubleOrNull(today['uv']);
    if (uv != null && uv >= 6) tips.add('紫外线偏强，注意防晒');
  }
  return tips;
}

// ---------- 缓存决策（对齐 server.py 的 weather_result） ----------
/// 缓存年龄（分钟）；fetchedAt 为空或解析不了返回 null。
double? cacheAgeMinutes(String fetchedAt, DateTime now) {
  if (fetchedAt.isEmpty) return null;
  final when = DateTime.tryParse(fetchedAt);
  if (when == null) return null;
  return now.difference(when).inMicroseconds / 60000000.0;
}

/// 缓存是否可以直接用：同一城市 + 没过期（refreshMinutes=0 表示永不过期，
/// 只要有数据就行）+ 确实存了数据。
bool weatherCacheFresh({
  required City city,
  required WeatherCache? cache,
  required int refreshMinutes,
  required DateTime now,
}) {
  if (cache == null || cache.payload == null) return false;
  if (cache.city.name != city.name) return false;
  if (refreshMinutes == 0) return true;
  final age = cacheAgeMinutes(cache.fetchedAt, now);
  return age != null && age < refreshMinutes;
}

/// 取数失败时的降级：同城市的旧缓存还能顶上（界面上要标「旧数据」）。
WeatherCache? staleFallback({required City city, WeatherCache? cache}) {
  if (cache == null || cache.payload == null || cache.city.name != city.name) {
    return null;
  }
  return cache;
}

// ---------- 我的地点（对齐 store.py 的地点管理） ----------
double? _coord(dynamic value, double low, double high) {
  if (value == null || value == '') return null;
  final d = value is num ? value.toDouble() : double.tryParse(asString(value).trim());
  if (d == null || d.isNaN || d.isInfinite) return null;
  if (d < low || d > high) return null;
  return (d * 10000).round() / 10000.0;
}

/// 把入参整理成标准地点；不合法就抛 FormatException（文案和电脑版一致）。
Place normalizePlace(Map<String, dynamic> data) {
  final name = asString(data['name']).trim();
  if (name.isEmpty) {
    throw const FormatException('地点名称不能为空');
  }
  final lat = _coord(data['latitude'], -90, 90);
  final lon = _coord(data['longitude'], -180, 180);
  if (lat == null || lon == null) {
    throw const FormatException('经纬度不合法，纬度 -90~90、经度 -180~180');
  }
  final tz = asString(data['timezone']).trim();
  return Place(
    id: asString(data['id']),
    name: name,
    admin: asString(data['admin']).trim(),
    latitude: lat,
    longitude: lon,
    timezone: tz.isEmpty ? defaultTimezone : tz,
  );
}

/// 坐标几乎一样的算同一个地点（阈值和电脑版一致：1e-4）。
bool samePlace(Place a, Place b) =>
    (a.latitude - b.latitude).abs() < 1e-4 && (a.longitude - b.longitude).abs() < 1e-4;

/// 当前城市是否就是这条地点（名字 + 坐标都对上）。
bool isCurrentPlace(City current, Place p) {
  if (current.name.isEmpty || current.name != p.name) return false;
  final lat = current.latitude;
  final lon = current.longitude;
  if (lat == null || lon == null) return false;
  return (lat - p.latitude).abs() < 1e-4 && (lon - p.longitude).abs() < 1e-4;
}

/// 地点写回结果：新的地点列表 + 新的当前城市（界面拿去存 settings）。
class PlacesWrite {
  PlacesWrite({
    required this.places,
    required this.current,
    this.target,
    this.created = false,
    this.deleted = false,
  });

  final List<Place> places;
  final City current;
  final Place? target;
  final bool created;
  final bool deleted;
}

List<Place> _copyPlaces(List<Place> src) =>
    src.map((p) => Place.fromJson(p.toJson())).toList();

/// 添加地点并设为当前；坐标相同的视为同一个地点，只改名不重复添加。
PlacesWrite addPlace(List<Place> places, Map<String, dynamic> data,
    {required String Function() newId}) {
  final incoming = normalizePlace(data);
  final list = _copyPlaces(places);
  var created = true;
  Place? target;
  for (final p in list) {
    if (samePlace(p, incoming)) {
      created = false;
      target = p;
      p.name = incoming.name;
      if (incoming.admin.isNotEmpty) p.admin = incoming.admin;
      break;
    }
  }
  if (target == null) {
    if (list.length >= Settings.maxPlaces) {
      throw FormatException('最多保存 ${Settings.maxPlaces} 个地点，先删掉几个再加');
    }
    target = incoming;
    target.id = newId();
    list.add(target);
  }
  return PlacesWrite(places: list, current: target.toCity(), target: target, created: created);
}

/// 把某个已保存地点设为当前城市；找不到返回 null。
PlacesWrite? selectPlace(List<Place> places, String pid) {
  Place? found;
  for (final p in places) {
    if (p.id == pid) {
      found = p;
      break;
    }
  }
  if (found == null) return null;
  return PlacesWrite(places: _copyPlaces(places), current: found.toCity(), target: found);
}

/// 删除已保存地点；删掉当前城市就顺位到第一个，没有剩余就清空当前城市。
PlacesWrite removePlace(List<Place> places, City current, String pid) {
  Place? removed;
  final rest = <Place>[];
  for (final p in places) {
    if (p.id == pid && removed == null) {
      removed = p;
      continue;
    }
    rest.add(p);
  }
  if (removed == null) {
    return PlacesWrite(places: _copyPlaces(places), current: current, deleted: false);
  }
  var newCurrent = current;
  if (isCurrentPlace(current, removed)) {
    newCurrent = rest.isNotEmpty ? rest.first.toCity() : City();
  }
  return PlacesWrite(
    places: rest,
    current: newCurrent,
    target: removed,
    deleted: true,
  );
}
