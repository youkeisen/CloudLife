/// 天气的网络层：请求 Open-Meteo（免 key），用 dart:io 的 HttpClient，
/// 不引额外网络包（电脑版也是标准库直连）。
///
/// 地址与参数拼法见 `weather_logic.dart` 的 buildForecastUrl / buildGeocodeUrl，
/// 和电脑版 `weather.py` 一致。测试时可以换 baseUrl 指到本地假服务器。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'weather_logic.dart';

/// 城市搜索结果里的一条（对应电脑版 `search_cities` 的返回）。
class CitySuggestion {
  CitySuggestion({
    required this.name,
    this.admin = '',
    this.country = '',
    this.latitude,
    this.longitude,
  });

  final String name;
  final String admin;
  final String country;
  final double? latitude;
  final double? longitude;

  /// 拿去 addPlace 的入参（和电脑版前端提交的字段一致）。
  Map<String, dynamic> toPlaceData() => <String, dynamic>{
        'name': name,
        'admin': admin,
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// 网络出错（超时、状态码不对、JSON 不对）都归到这里，界面统一处理。
class WeatherApiException implements Exception {
  WeatherApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WeatherApi {
  WeatherApi({
    String? forecastBase,
    String? geoBase,
    this.timeout = const Duration(seconds: 8),
  })  : forecastBase = forecastBase ?? forecastApi,
        geoBase = geoBase ?? geocodeApi;

  /// 测试时可指向本地假服务器。
  final String forecastBase;
  final String geoBase;
  final Duration timeout;

  Future<Map<String, dynamic>> httpGetJson(Uri url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>().timeout(timeout);
        throw WeatherApiException('HTTP ${response.statusCode}');
      }
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final obj = jsonDecode(text);
      if (obj is Map) {
        return obj.map((k, v) => MapEntry(k.toString(), v));
      }
      throw WeatherApiException('返回的不是 JSON 对象');
    } on WeatherApiException {
      rethrow;
    } catch (e) {
      throw WeatherApiException(e.toString());
    } finally {
      client.close(force: true);
    }
  }

  /// 拉原始天气数据（归一化在 weather_logic 里做，和电脑版分层一样）。
  Future<Map<String, dynamic>> fetchWeather(num lat, num lon) {
    final url = Uri.parse(forecastBase).replace(
        queryParameters: forecastQuery(lat, lon));
    return httpGetJson(url);
  }

  Future<List<CitySuggestion>> searchCities(String name) async {
    final url =
        Uri.parse(geoBase).replace(queryParameters: geocodeQuery(name));
    final raw = await httpGetJson(url);
    final results = raw['results'];
    final out = <CitySuggestion>[];
    if (results is List) {
      for (final item in results) {
        final m = asMap(item);
        out.add(CitySuggestion(
          name: asString(m['name']),
          admin: asString(m['admin1']),
          country: asString(m['country']),
          latitude: asDoubleOrNull(m['latitude']),
          longitude: asDoubleOrNull(m['longitude']),
        ));
      }
    }
    return out;
  }
}
