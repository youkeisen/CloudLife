// 天气页的测试：状态机（未选城市 / 网络成功 / 缓存 / 旧数据降级 / 失败）、
// 搜索城市加地点、我的地点切换与删除。数据全部虚构，网络用假接口。
library;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/weather_api.dart';
import 'package:my_day_phone/weather_logic.dart';
import 'package:my_day_phone/ui/weather_page.dart';

/// 假接口：不联网，返回固定数据；fail=true 时模拟网络挂了。
class FakeApi extends WeatherApi {
  FakeApi({this.fail = false, this.temp = 24.5});

  bool fail;
  double temp;
  int forecastCalls = 0;
  int searchCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchWeather(num lat, num lon) async {
    forecastCalls++;
    if (fail) throw WeatherApiException('网络断了');
    return rawFixture(temp: temp);
  }

  @override
  Future<List<CitySuggestion>> searchCities(String name) async {
    searchCalls++;
    if (fail) throw WeatherApiException('城市搜索失败：网络断了');
    return <CitySuggestion>[
      CitySuggestion(name: '示例市', admin: '示例省', latitude: 30.1, longitude: 118.2),
    ];
  }
}

/// 造一段 Open-Meteo 风格的原始返回（时间跨度够宽，真实 now 也能落在窗口里）。
Map<String, dynamic> rawFixture({required double temp}) {
  String p2(int n) => n < 10 ? '0$n' : '$n';
  final now = DateTime.now();
  final times = <String>[];
  final temps = <double>[];
  final pops = <int>[];
  final vis = <double>[];
  for (var i = 0; i < 72; i++) {
    final d = DateTime(now.year, now.month, now.day - 1, i);
    times.add('${d.year}-${p2(d.month)}-${p2(d.day)}T${p2(d.hour)}:00');
    temps.add(temp);
    pops.add(20);
    vis.add(9000.0);
  }
  final days = <String>[];
  final dayMax = <double>[];
  final dayMin = <double>[];
  for (var i = 0; i < 3; i++) {
    final d = DateTime(now.year, now.month, now.day + i);
    days.add('${d.year}-${p2(d.month)}-${p2(d.day)}');
    dayMax.add(temp + 1);
    dayMin.add(temp - 1);
  }
  return <String, dynamic>{
    'current': <String, dynamic>{
      'temperature_2m': temp,
      'apparent_temperature': temp + 1,
      'relative_humidity_2m': 60,
      'is_day': 1,
      'weather_code': 0,
      'wind_speed_10m': 3.0,
      'wind_direction_10m': 45,
      'surface_pressure': 1010.0,
    },
    'hourly': <String, dynamic>{
      'time': times,
      'temperature_2m': temps,
      'precipitation_probability': pops,
      'visibility': vis,
    },
    'daily': <String, dynamic>{
      'time': days,
      'weather_code': <int>[0, 1, 2],
      'temperature_2m_max': dayMax,
      'temperature_2m_min': dayMin,
      'precipitation_probability_max': <int>[20, 20, 20],
      'uv_index_max': <double>[3.0, 3.0, 3.0],
    },
  };
}

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-weather-test-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void setCity(String name, {double lat = 30.1, double lon = 118.2}) {
    final s = store.settings()
      ..weatherCity = City(name: name, latitude: lat, longitude: lon);
    store.saveSettings(s);
  }

  /// 直接往缓存里塞一份（fetchedAt 就是现在，肯定新鲜）。
  void setCache(City city, Map<String, dynamic> payload) {
    store.setWeatherCache(city, payload);
  }

  /// 塞一份过期缓存（fetchedAt 指定成过去的时间），用于测旧数据降级。
  void setExpiredCache(City city, Map<String, dynamic> payload,
      {Duration ago = const Duration(hours: 2)}) {
    final t = DateTime.now().subtract(ago);
    String p2(int n) => n < 10 ? '0$n' : '$n';
    final off = t.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final iso = '${t.year}-${p2(t.month)}-${p2(t.day)}T'
        '${p2(t.hour)}:${p2(t.minute)}:${p2(t.second)}'
        '$sign${p2(off.inHours.abs())}:${p2(off.inMinutes.abs() % 60)}';
    File('${tmp.path}/weather_cache.json').writeAsStringSync(jsonEncode(
      <String, dynamic>{
        'version': 1,
        'fetchedAt': iso,
        'city': <String, dynamic>{
          'name': city.name,
          'latitude': city.latitude,
          'longitude': city.longitude,
        },
        'payload': payload,
      },
    ));
  }

  Future<void> pumpPage(WidgetTester tester, WeatherApi api) async {
    // 测试视口拉高到 1080x2600 逻辑像素，整页一屏渲染完，
    // 省得「我的地点」在 ListView 底部要滚动才能命中。
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WeatherPage(store: store, api: api)),
    ));
    await tester.pump(); // initState 里发起的 _load
    await tester.pump(const Duration(milliseconds: 50)); // 等假接口的微任务落定
  }

  Map<String, dynamic> cacheJson() =>
      jsonDecode(File('${tmp.path}/weather_cache.json').readAsStringSync())
          as Map<String, dynamic>;

  Map<String, dynamic> settingsJson() =>
      jsonDecode(File('${tmp.path}/settings.json').readAsStringSync())
          as Map<String, dynamic>;

  testWidgets('没选城市：给引导空态，不联网', (tester) async {
    final api = FakeApi();
    await pumpPage(tester, api);
    expect(find.byKey(const ValueKey('wx-empty-no-city')), findsOneWidget);
    expect(find.text('先选一个城市'), findsOneWidget);
    expect(find.text('城市未设置'), findsOneWidget);
    expect(api.forecastCalls, 0);
  });

  testWidgets('有城市联网成功：渲染实况并写缓存', (tester) async {
    final api = FakeApi();
    setCity('示例市');
    await pumpPage(tester, api);

    expect(find.textContaining('24.5'), findsWidgets,
        reason: '大字温度 24.5° 至少出现一次');
    expect(find.textContaining('晴 · 示例市'), findsOneWidget);
    expect(find.textContaining('更新于'), findsOneWidget);
    expect(find.textContaining('Open-Meteo'), findsOneWidget);
    expect(api.forecastCalls, 1);

    final cache = cacheJson();
    expect(cache['city']['name'], '示例市');
    expect((cache['payload']['current'] as Map)['temp'], 24.5);
  });

  testWidgets('缓存新鲜就不联网，直接用缓存', (tester) async {
    final api = FakeApi();
    final city = City(name: '示例市', latitude: 30.1, longitude: 118.2);
    setCity('示例市');
    setCache(city, normalize(rawFixture(temp: 21.5), city));
    await pumpPage(tester, api);

    expect(api.forecastCalls, 0);
    expect(find.textContaining('21.5'), findsWidgets);
  });

  testWidgets('联网失败但有同城市过期缓存：降级旧数据并标注', (tester) async {
    final api = FakeApi()..fail = true;
    final city = City(name: '示例市', latitude: 30.1, longitude: 118.2);
    setCity('示例市');
    setExpiredCache(city, normalize(rawFixture(temp: 21.5), city));
    await pumpPage(tester, api);

    expect(api.forecastCalls, 1);
    expect(find.textContaining('（旧数据，网络不可用）'), findsOneWidget);
    expect(find.textContaining('21.5'), findsWidgets,
        reason: '展示的是缓存里的旧数据');
    expect(find.byKey(const ValueKey('wx-empty-error')), findsNothing);
  });

  testWidgets('联网失败且没缓存：失败空态', (tester) async {
    final api = FakeApi()..fail = true;
    setCity('示例市');
    await pumpPage(tester, api);

    expect(find.byKey(const ValueKey('wx-empty-error')), findsOneWidget);
    expect(find.text('暂时取不到天气'), findsOneWidget);
    expect(find.textContaining('取数据失败'), findsOneWidget);
  });

  testWidgets('刷新按钮强制联网，哪怕缓存还新鲜', (tester) async {
    final api = FakeApi(temp: 26.5);
    final city = City(name: '示例市', latitude: 30.1, longitude: 118.2);
    setCity('示例市');
    setCache(city, normalize(rawFixture(temp: 21.5), city));
    await pumpPage(tester, api);
    expect(api.forecastCalls, 0);

    await tester.tap(find.byKey(const ValueKey('wx-refresh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.forecastCalls, 1);
    expect(find.textContaining('26.5'), findsWidgets, reason: '换成网络上的新数据');
  });

  testWidgets('搜索城市 → 选中 → 加进我的地点并设为当前，随后刷新天气', (tester) async {
    final api = FakeApi();
    await pumpPage(tester, api);

    await tester.enterText(find.byKey(const ValueKey('wx-city-search')), '示例');
    await tester.tap(find.byKey(const ValueKey('wx-search-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.searchCalls, 1);
    expect(find.byKey(const ValueKey('wx-result-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wx-result-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final s = settingsJson();
    expect((s['weatherCity'] as Map)['name'], '示例市');
    expect((s['weatherCities'] as List), hasLength(1));
    expect(((s['weatherCities'] as List).first as Map)['id'], startsWith('pl'));
    expect(api.forecastCalls, 1, reason: '切了城市要立刻刷天气');
    expect(find.byKey(const ValueKey('wx-empty-no-city')), findsNothing);
    // SnackBar 要等前一条（「搜到 1 个…」）退出动画放完才出现
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('已切换到 示例市'), findsOneWidget);
  });

  testWidgets('我的地点：点另一个地点就切过去并刷新', (tester) async {
    final api = FakeApi();
    final s = store.settings()
      ..weatherCity = City(name: '甲城', latitude: 1.0, longitude: 1.0)
      ..weatherCities = <Place>[
        Place(id: 'pl_a', name: '甲城', latitude: 1.0, longitude: 1.0),
        Place(id: 'pl_b', name: '乙城', latitude: 2.0, longitude: 2.0),
      ];
    store.saveSettings(s);
    await pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('wx-place-pl_b')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect((settingsJson()['weatherCity'] as Map)['name'], '乙城');
    expect(api.forecastCalls, 2, reason: '初始加载 1 次 + 切换后强制刷新 1 次');
    expect(find.text('已切换到 乙城'), findsOneWidget);
  });

  testWidgets('删除当前地点顺位到下一个；删光后回到未选城市', (tester) async {
    final api = FakeApi();
    final s = store.settings()
      ..weatherCity = City(name: '甲城', latitude: 1.0, longitude: 1.0)
      ..weatherCities = <Place>[
        Place(id: 'pl_a', name: '甲城', latitude: 1.0, longitude: 1.0),
        Place(id: 'pl_b', name: '乙城', latitude: 2.0, longitude: 2.0),
      ];
    store.saveSettings(s);
    await pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('wx-place-del-pl_a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    var sj = settingsJson();
    expect((sj['weatherCity'] as Map)['name'], '乙城', reason: '当前城市被删，顺位到第一个');
    expect((sj['weatherCities'] as List), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('wx-place-del-pl_b')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    sj = settingsJson();
    expect((sj['weatherCities'] as List), isEmpty);
    expect((sj['weatherCity'] as Map)['name'], '');
    expect(find.byKey(const ValueKey('wx-empty-no-city')), findsOneWidget);
  });

  testWidgets('生活提示与 7 天预报都渲染出来', (tester) async {
    final api = FakeApi();
    setCity('示例市');
    await pumpPage(tester, api);

    expect(find.byKey(const ValueKey('wx-hours')), findsOneWidget);
    expect(find.byKey(const ValueKey('wx-day-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('wx-day-2')), findsOneWidget);
    expect(find.textContaining('示例市'), findsWidgets);
    expect(find.text('我的地点'), findsOneWidget, reason: '我的地点区块在一屏内直接可见');
  });
}
