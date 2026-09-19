// 网络层测试：不起真网，在 127.0.0.1 起一个假 Open-Meteo，
// 验证 URL、解析、错误处理。返回的数据全是虚构的。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/weather_api.dart';
import 'package:my_day_phone/weather_logic.dart';

/// 和 weather_logic_test 里同款的原始返回（这里只挑重点字段）。
Map<String, dynamic> rawFixture() => <String, dynamic>{
      'current': <String, dynamic>{
        'temperature_2m': 21.5,
        'apparent_temperature': 22.0,
        'relative_humidity_2m': 55,
        'is_day': 1,
        'weather_code': 0,
        'wind_speed_10m': 2.0,
        'wind_direction_10m': 90,
        'surface_pressure': 1008.0,
      },
      'hourly': <String, dynamic>{
        'time': <String>['2026-09-19T00:00', '2026-09-19T01:00'],
        'temperature_2m': <double>[20.0, 20.5],
        'precipitation_probability': <int>[0, 10],
        'visibility': <double>[10000.0, 10000.0],
      },
      'daily': <String, dynamic>{
        'time': <String>['2026-09-19'],
        'weather_code': <int>[0],
        'temperature_2m_max': <double>[25.0],
        'temperature_2m_min': <double>[15.0],
        'precipitation_probability_max': <int>[10],
        'uv_index_max': <double>[2.0],
      },
    };

void main() {
  late HttpServer server;
  late String base;
  final hits = <Uri>[];

  setUp(() async {
    hits.clear();
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      hits.add(req.uri);
      if (req.uri.path == '/v1/forecast') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(rawFixture()));
        await req.response.close();
      } else if (req.uri.path == '/v1/search') {
        req.response.headers.contentType = ContentType.json;
        if (req.uri.queryParameters['name'] == '示例') {
          req.response.write(jsonEncode(<String, dynamic>{
            'results': <dynamic>[
              <String, dynamic>{
                'name': '示例市',
                'admin1': '示例省',
                'country': '中国',
                'latitude': 30.1,
                'longitude': 118.2,
              },
              <String, dynamic>{
                'name': '示例镇',
                'admin1': '示例省',
                'country': '中国',
                'latitude': 30.2,
                'longitude': 118.3,
              },
            ],
          }));
        } else {
          req.response.write(jsonEncode(<String, dynamic>{}));
        }
        await req.response.close();
      } else if (req.uri.path == '/broken') {
        req.response.headers.contentType = ContentType.json;
        req.response.write('这不是 JSON');
        await req.response.close();
      } else {
        req.response.statusCode = 500;
        await req.response.close();
      }
    });
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  WeatherApi api() => WeatherApi(
        forecastBase: '$base/v1/forecast',
        geoBase: '$base/v1/search',
        timeout: const Duration(seconds: 5),
      );

  test('fetchWeather：拿到 JSON，请求参数齐全', () async {
    final raw = await api().fetchWeather(30.5, 118.2);
    expect(raw['current']['temperature_2m'], 21.5);
    expect(hits, hasLength(1));
    expect(hits.first.path, '/v1/forecast');
    expect(hits.first.queryParameters['latitude'], '30.5');
    expect(hits.first.queryParameters['timezone'], 'Asia/Shanghai');
  });

  test('fetchWeather + normalize 端到端', () async {
    final raw = await api().fetchWeather(30.5, 118.2);
    final payload = normalize(raw, City(name: '示例市', latitude: 30.5, longitude: 118.2));
    expect((payload['current'] as Map)['text'], '晴');
    expect((payload['current'] as Map)['visibility'], 10.0);
  });

  test('searchCities：解析 name/admin1/country', () async {
    final list = await api().searchCities('示例');
    expect(list, hasLength(2));
    expect(list.first.name, '示例市');
    expect(list.first.admin, '示例省');
    expect(list.first.country, '中国');
    expect(list.first.latitude, 30.1);
    expect(hits.first.path, '/v1/search');
    expect(hits.first.queryParameters['language'], 'zh');
    expect(hits.first.queryParameters['count'], '8');
    expect(hits.first.queryParameters['name'], '示例');
  });

  test('searchCities：没有 results 时给空列表', () async {
    final list = await api().searchCities('查无此地');
    expect(list, isEmpty);
  });

  test('非 200 抛 WeatherApiException', () async {
    // 服务器对未知路径一律回 500
    final bad = WeatherApi(
      forecastBase: '$base/other',
      geoBase: '$base/other',
      timeout: const Duration(seconds: 5),
    );
    await expectLater(
      bad.searchCities('示例'),
      throwsA(isA<WeatherApiException>()),
    );
  });

  test('返回不是 JSON 抛 WeatherApiException', () async {
    final bad = WeatherApi(
      forecastBase: '$base/broken',
      geoBase: '$base/broken',
      timeout: const Duration(seconds: 5),
    );
    await expectLater(
      bad.fetchWeather(30.5, 118.2),
      throwsA(isA<WeatherApiException>()),
    );
  });

  test('连不上的地址抛 WeatherApiException（不裸抛 SocketException）', () async {
    final dead = WeatherApi(
      forecastBase: 'http://127.0.0.1:9/v1/forecast',
      timeout: const Duration(milliseconds: 800),
    );
    await expectLater(
      dead.fetchWeather(30.5, 118.2),
      throwsA(isA<WeatherApiException>()),
    );
  });
}
