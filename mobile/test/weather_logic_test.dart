// 天气纯逻辑的测试：WMO 映射、风向、URL、归一化、生活提示、
// 缓存决策、我的地点增删切换。全部用虚构数据。
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/weather_logic.dart';

City cityOf(String name) => City(name: name, latitude: 30.0, longitude: 118.0);

/// 造一段 Open-Meteo 风格的原始返回（虚构城市/数值）。
Map<String, dynamic> rawFixture({
  double temp = 23.44,
  int code = 61,
  int pop = 60,
}) {
  List<String> times = <String>[];
  List<double> temps = <double>[];
  List<int> pops = <int>[];
  List<double> vis = <double>[];
  for (var i = 0; i < 48; i++) {
    final d = DateTime(2026, 9, 19).add(Duration(hours: i));
    String p2(int n) => n < 10 ? '0$n' : '$n';
    times.add('${d.year}-${p2(d.month)}-${p2(d.day)}T${p2(d.hour)}:00');
    temps.add(20.0);
    pops.add(pop);
    vis.add(12000.0);
  }
  return <String, dynamic>{
    'current': <String, dynamic>{
      'temperature_2m': temp,
      'apparent_temperature': 24.0,
      'relative_humidity_2m': 66,
      'is_day': 1,
      'weather_code': code,
      'wind_speed_10m': 3.52,
      'wind_direction_10m': 135,
      'surface_pressure': 1002.3,
    },
    'hourly': <String, dynamic>{
      'time': times,
      'temperature_2m': temps,
      'precipitation_probability': pops,
      'visibility': vis,
    },
    'daily': <String, dynamic>{
      'time': <String>['2026-09-19', '2026-09-20', '2026-09-21'],
      'weather_code': <int>[code, 3, 0],
      'temperature_2m_max': <double>[28.4, 20.0, 18.0],
      'temperature_2m_min': <double>[18.2, 12.0, 10.0],
      'precipitation_probability_max': <int>[70, 0, 0],
      'uv_index_max': <double>[7.2, 1.0, 1.0],
    },
  };
}

/// 造一个最小 payload 给 buildTips 用。
Map<String, dynamic> tipsPayload({
  dynamic max,
  dynamic min,
  dynamic pop,
  dynamic uv,
  List<dynamic>? hourPops,
}) =>
    <String, dynamic>{
      'daily': <dynamic>[
        <String, dynamic>{'max': max, 'min': min, 'pop': pop, 'uv': uv},
      ],
      'hourly': <dynamic>[
        if (hourPops != null)
          for (final p in hourPops) <String, dynamic>{'pop': p},
      ],
    };

void main() {
  group('WMO 码映射', () {
    test('常见码有中文和图标', () {
      expect(wmoText(0), '晴');
      expect(wmoIcon(0), 'sun');
      expect(wmoText(3), '阴');
      expect(wmoText(61), '小雨');
      expect(wmoIcon(95), 'thunder');
      expect(wmoText('61'), '小雨', reason: '字符串数字也要认');
    });
    test('认不出的码兜底', () {
      expect(wmoText(42), '未知天气');
      expect(wmoText(999), '未知天气');
      expect(wmoText(null), '未知天气');
      expect(wmoText('abc'), '未知天气');
      expect(wmoIcon(42), 'cloud');
      expect(wmoIcon(null), 'cloud');
    });
  });

  group('风向', () {
    test('十六方位', () {
      expect(windDirName(0), '北');
      expect(windDirName(360), '北');
      expect(windDirName(45), '东北');
      expect(windDirName(100), '东');
      expect(windDirName(135), '东南');
      expect(windDirName(337.5), '西北偏北');
    });
    test('不合法输入给空串', () {
      expect(windDirName(null), '');
      expect(windDirName('x'), '');
    });
  });

  group('round1', () {
    test('数值进一位，不是数给 null', () {
      expect(round1(23.44), 23.4);
      expect(round1('23.46'), 23.5);
      expect(round1(20), 20.0);
      expect(round1(null), isNull);
      expect(round1('abc'), isNull);
    });
  });

  group('请求 URL', () {
    test('预报 URL 的参数和电脑版一致', () {
      final uri = Uri.parse(buildForecastUrl(30.5, 118.2));
      expect(uri.host, 'api.open-meteo.com');
      expect(uri.path, '/v1/forecast');
      expect(uri.queryParameters['latitude'], '30.5');
      expect(uri.queryParameters['longitude'], '118.2');
      expect(uri.queryParameters['timezone'], 'Asia/Shanghai');
      expect(uri.queryParameters['forecast_days'], '7');
      expect(uri.queryParameters['current'], contains('weather_code'));
      expect(uri.queryParameters['hourly'], contains('visibility'));
      expect(uri.queryParameters['daily'], contains('uv_index_max'));
    });
    test('城市搜索 URL 走 geocoding', () {
      final uri = Uri.parse(buildGeocodeUrl('测试城'));
      expect(uri.host, 'geocoding-api.open-meteo.com');
      expect(uri.path, '/v1/search');
      expect(uri.queryParameters['name'], '测试城');
      expect(uri.queryParameters['language'], 'zh');
      expect(uri.queryParameters['count'], '8');
    });
  });

  group('归一化 normalize', () {
    test('完整字段整理', () {
      final payload = normalize(rawFixture(), cityOf('测试城'),
          now: DateTime(2026, 9, 19, 15, 30));
      // 城市只有名字和坐标，和电脑版 payload['city'] 一致
      expect(payload['city'], <String, dynamic>{
        'name': '测试城',
        'latitude': 30.0,
        'longitude': 118.0,
      });
      final hours = payload['hourly'] as List;
      expect(hours.length, 24, reason: '从当前小时起 24 个小时');
      expect((hours[0] as Map)['time'], '15:00', reason: 'now=15:30 应落在 15:00');
      expect((hours[0] as Map)['pop'], 60);
      expect((hours[23] as Map)['time'], '14:00');

      final cur = payload['current'] as Map;
      expect(cur['temp'], 23.4);
      expect(cur['feels'], 24.0);
      expect(cur['humidity'], 66);
      expect(cur['text'], '小雨');
      expect(cur['icon'], 'rain');
      expect(cur['wind'], 3.5);
      expect(cur['windDirDeg'], 135.0);
      expect(cur['windDir'], '东南');
      expect(cur['pressure'], 1002.3);
      expect(cur['visibility'], 12.0, reason: '12000 米要换算成 12 公里');
      expect(cur['pop'], 60, reason: '当前小时段降水概率取自 24 小时第一格');
      expect(cur['isDay'], 1);

      final days = payload['daily'] as List;
      expect(days.length, 3);
      final d0 = days[0] as Map;
      expect(d0['date'], '2026-09-19');
      expect(d0['text'], '小雨');
      expect(d0['max'], 28.4);
      expect(d0['min'], 18.2);
      expect(d0['pop'], 70);
      expect(d0['uv'], 7.2);
    });
    test('生活提示三条齐发（今日概率 70 比小时段 60 大，取 70）', () {
      final payload = normalize(rawFixture(), cityOf('测试城'),
          now: DateTime(2026, 9, 19, 15, 30));
      expect(
        payload['tips'],
        <String>[
          '昼夜温差约 10 度，早晚加件外套',
          '未来几小时降水概率 70%，出门带把伞',
          '紫外线偏强，注意防晒',
        ],
      );
    });
    test('空返回不崩，兜底文案齐全', () {
      final payload = normalize(<String, dynamic>{}, cityOf('测试城'));
      expect((payload['current'] as Map)['text'], '未知天气');
      expect(payload['hourly'], isEmpty);
      expect(payload['daily'], isEmpty);
      expect(payload['tips'], isEmpty);
    });
    test('小时序列全在未来时，落回第 0 格', () {
      final raw = rawFixture();
      // 把时间整体挪到 2027 年，now 还在 2026 → 找不到 <= 目标的，取 0
      final times = (raw['hourly']['time'] as List)
          .map<String>((t) => '2027${(t as String).substring(4)}')
          .toList();
      raw['hourly']['time'] = times;
      final payload = normalize(raw, cityOf('测试城'),
          now: DateTime(2026, 9, 19, 15, 30));
      expect(((payload['hourly'] as List).first as Map)['time'], '00:00');
    });
  });

  group('生活提示阈值', () {
    test('温差 8 度起步', () {
      expect(buildTips(tipsPayload(max: 28, min: 20)),
          <String>['昼夜温差约 8 度，早晚加件外套']);
      expect(buildTips(tipsPayload(max: 28, min: 20.5)), isEmpty);
      expect(buildTips(tipsPayload(max: null, min: null)), isEmpty);
    });
    test('降水概率 50 起步，取未来 6 小时和今日最大值', () {
      expect(buildTips(tipsPayload(pop: 50)), hasLength(1));
      expect(buildTips(tipsPayload(pop: 49)), isEmpty);
      expect(buildTips(tipsPayload(hourPops: <dynamic>[10, 20, 49])), isEmpty);
      expect(buildTips(tipsPayload(hourPops: <dynamic>[10, 60, 40])),
          <String>['未来几小时降水概率 60%，出门带把伞']);
      expect(
        buildTips(tipsPayload(pop: 70, hourPops: <dynamic>[60])),
        <String>['未来几小时降水概率 70%，出门带把伞'],
        reason: '和今日概率取最大',
      );
    });
    test('紫外线 6 起步', () {
      expect(buildTips(tipsPayload(uv: 6)), <String>['紫外线偏强，注意防晒']);
      expect(buildTips(tipsPayload(uv: 5.9)), isEmpty);
      expect(buildTips(tipsPayload(uv: null)), isEmpty);
    });
  });

  group('缓存决策', () {
    final now = DateTime(2026, 9, 19, 12, 0);
    WeatherCache cacheAt(String fetchedAt, {String name = '测试城'}) =>
        WeatherCache(
          fetchedAt: fetchedAt,
          city: City(name: name, latitude: 30.0, longitude: 118.0),
          payload: <String, dynamic>{'current': <String, dynamic>{}},
        );

    test('缓存年龄：空串和坏串给 null', () {
      expect(cacheAgeMinutes('', now), isNull);
      expect(cacheAgeMinutes('不是时间', now), isNull);
      expect(cacheAgeMinutes('2026-09-19T11:50:00+08:00', now)!, closeTo(10, 0.01));
    });

    test('同城市且没过期才用缓存', () {
      final city = cityOf('测试城');
      expect(
        weatherCacheFresh(
            city: city,
            cache: cacheAt('2026-09-19T11:50:00+08:00'),
            refreshMinutes: 30,
            now: now),
        isTrue,
      );
      // 过期
      expect(
        weatherCacheFresh(
            city: city,
            cache: cacheAt('2026-09-19T11:00:00+08:00'),
            refreshMinutes: 30,
            now: now),
        isFalse,
      );
      // 不同城市
      expect(
        weatherCacheFresh(
            city: cityOf('别的城'),
            cache: cacheAt('2026-09-19T11:50:00+08:00'),
            refreshMinutes: 30,
            now: now),
        isFalse,
      );
      // 没有 payload
      final empty = cacheAt('2026-09-19T11:50:00+08:00')..payload = null;
      expect(
        weatherCacheFresh(city: city, cache: empty, refreshMinutes: 30, now: now),
        isFalse,
      );
      // fetchedAt 坏了
      expect(
        weatherCacheFresh(
            city: city, cache: cacheAt('坏时间'), refreshMinutes: 30, now: now),
        isFalse,
      );
      // refreshMinutes=0：永不过期，有数据就行
      expect(
        weatherCacheFresh(
            city: city,
            cache: cacheAt('2020-01-01T00:00:00+08:00'),
            refreshMinutes: 0,
            now: now),
        isTrue,
      );
    });

    test('联网失败时同城市旧缓存顶上', () {
      final fb = staleFallback(city: cityOf('测试城'), cache: cacheAt('随便'));
      expect(fb, isNotNull);
      expect(staleFallback(city: cityOf('别的城'), cache: cacheAt('随便')), isNull);
      final empty = cacheAt('随便')..payload = null;
      expect(staleFallback(city: cityOf('测试城'), cache: empty), isNull);
      expect(staleFallback(city: cityOf('测试城'), cache: null), isNull);
    });
  });

  group('我的地点', () {
    test('normalizePlace：合法入参收整（坐标取 4 位小数）', () {
      final p = normalizePlace(<String, dynamic>{
        'name': ' 测试城 ',
        'latitude': '31.12349',
        'longitude': 118.987654,
        'admin': ' 测试省 ',
      });
      expect(p.name, '测试城');
      expect(p.admin, '测试省');
      expect(p.latitude, 31.1235);
      expect(p.longitude, 118.9877);
      expect(p.timezone, defaultTimezone);
      expect(p.id, '');
    });
    test('normalizePlace：不合法就抛（文案和电脑版一致）', () {
      expect(
        () => normalizePlace(<String, dynamic>{'latitude': 30, 'longitude': 118}),
        throwsFormatException,
      );
      expect(
        () => normalizePlace(<String, dynamic>{'name': 'x', 'latitude': 91, 'longitude': 118}),
        throwsA(predicate((e) => e.toString().contains('经纬度不合法'))),
      );
      expect(
        () => normalizePlace(<String, dynamic>{'name': 'x', 'latitude': 30, 'longitude': 'abc'}),
        throwsA(predicate((e) => e.toString().contains('经纬度不合法'))),
      );
    });

    test('addPlace：新增并设为当前，id 用 newId 造', () {
      var n = 0;
      final w = addPlace(<Place>[], <String, dynamic>{
        'name': '测试城',
        'latitude': 30.0,
        'longitude': 118.0,
      }, newId: () => 'pl${++n}');
      expect(w.created, isTrue);
      expect(w.places, hasLength(1));
      expect(w.places.first.id, 'pl1');
      expect(w.current.name, '测试城');
      expect(w.current.latitude, 30.0);
      expect(w.current.timezone, defaultTimezone);
    });

    test('addPlace：坐标几乎一样的算同一个，只改名不重复加', () {
      final existing = Place(
          id: 'pl_old', name: '旧名', admin: '', latitude: 30.0, longitude: 118.0);
      final w = addPlace(<Place>[existing], <String, dynamic>{
        'name': '新名',
        'admin': '测试省',
        'latitude': 30.00002,
        'longitude': 118.00002,
      }, newId: () => 'pl_new');
      expect(w.created, isFalse);
      expect(w.places, hasLength(1));
      expect(w.places.first.id, 'pl_old', reason: '去重时保留旧 id');
      expect(w.places.first.name, '新名');
      expect(w.places.first.admin, '测试省');
      expect(w.current.name, '新名');
    });

    test('addPlace：去重时 incoming 的 admin 为空就不覆盖', () {
      final existing = Place(
          id: 'pl_old', name: '旧名', admin: '测试省', latitude: 30.0, longitude: 118.0);
      final w = addPlace(<Place>[existing], <String, dynamic>{
        'name': '新名',
        'latitude': 30.0,
        'longitude': 118.0,
      }, newId: () => 'pl_new');
      expect(w.places.first.admin, '测试省');
    });

    test('addPlace：超过上限拦下', () {
      final places = <Place>[
        for (var i = 0; i < Settings.maxPlaces; i++)
          Place(id: 'pl$i', name: '城$i', latitude: i * 1.0, longitude: i * 1.0),
      ];
      expect(
        () => addPlace(places, <String, dynamic>{
          'name': '多出来的',
          'latitude': 89.0,
          'longitude': -179.0,
        }, newId: () => 'pl_x'),
        throwsA(predicate((e) => e.toString().contains('最多保存 20 个地点'))),
      );
    });

    test('selectPlace：设当前；找不到返回 null', () {
      final places = <Place>[
        Place(id: 'a', name: '甲城', latitude: 1.0, longitude: 1.0),
        Place(id: 'b', name: '乙城', latitude: 2.0, longitude: 2.0),
      ];
      final w = selectPlace(places, 'b')!;
      expect(w.current.name, '乙城');
      expect(w.places, hasLength(2));
      expect(selectPlace(places, '没有'), isNull);
    });

    test('removePlace：删当前城市顺位到第一个', () {
      final places = <Place>[
        Place(id: 'a', name: '甲城', latitude: 1.0, longitude: 1.0),
        Place(id: 'b', name: '乙城', latitude: 2.0, longitude: 2.0),
        Place(id: 'c', name: '丙城', latitude: 3.0, longitude: 3.0),
      ];
      final w = removePlace(places, places.first.toCity(), 'a');
      expect(w.deleted, isTrue);
      expect(w.places.map((p) => p.id), <String>['b', 'c']);
      expect(w.current.name, '乙城', reason: '顺位到剩下的第一个');
    });

    test('removePlace：删的不是当前城市，当前不动', () {
      final places = <Place>[
        Place(id: 'a', name: '甲城', latitude: 1.0, longitude: 1.0),
        Place(id: 'b', name: '乙城', latitude: 2.0, longitude: 2.0),
      ];
      final w = removePlace(places, places.first.toCity(), 'b');
      expect(w.deleted, isTrue);
      expect(w.current.name, '甲城');
    });

    test('removePlace：删最后一个就清空当前城市', () {
      final places = <Place>[
        Place(id: 'a', name: '甲城', latitude: 1.0, longitude: 1.0),
      ];
      final w = removePlace(places, places.first.toCity(), 'a');
      expect(w.places, isEmpty);
      expect(w.current.isEmpty, isTrue);
    });

    test('removePlace：删不存在的 id，原样返回', () {
      final places = <Place>[
        Place(id: 'a', name: '甲城', latitude: 1.0, longitude: 1.0),
      ];
      final current = cityOf('别的城');
      final w = removePlace(places, current, '没有');
      expect(w.deleted, isFalse);
      expect(w.places, hasLength(1));
      expect(w.current.name, '别的城');
    });

    test('isCurrentPlace：名字和坐标都要对上', () {
      final p = Place(id: 'a', name: '甲城', latitude: 1.0, longitude: 1.0);
      expect(isCurrentPlace(p.toCity(), p), isTrue);
      expect(isCurrentPlace(City(name: '甲城', latitude: 1.5, longitude: 1.0), p), isFalse);
      expect(isCurrentPlace(City(name: '乙城', latitude: 1.0, longitude: 1.0), p), isFalse);
      expect(isCurrentPlace(City(), p), isFalse);
    });
  });
}
