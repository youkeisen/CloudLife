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
    this.population,
  });

  final String name;
  final String admin;
  final String country;
  final double? latitude;
  final double? longitude;

  /// 人口：用来给搜索结果排序（大城市排前面，同名小村子沉底）。
  final int? population;

  /// 拿去 addPlace 的入参（和电脑版前端提交的字段一致）。
  Map<String, dynamic> toPlaceData() => <String, dynamic>{
        'name': name,
        'admin': admin,
        'latitude': latitude,
        'longitude': longitude,
      };
}

int _popOf(CitySuggestion c) => c.population ?? -1;

/// 给中文城市名配一个补充查询：阜阳 ↔ 阜阳市。
///
/// Open-Meteo 的中文索引不全——搜「阜阳」只会命中江苏的同名小村，
/// 带「市」后缀才能搜到安徽阜阳市；反过来有的城市又必须去后缀。
String? cityQueryVariant(String name) {
  final n = name.trim();
  if (n.isEmpty) return null;
  if (n.endsWith('市')) {
    final bare = n.substring(0, n.length - 1);
    return bare.isEmpty ? null : bare;
  }
  final allCjk = n.runes.every((ch) => ch >= 0x4E00 && ch <= 0x9FFF);
  return allCjk ? '$n市' : null;
}

/// 合并两批城市搜索结果：按坐标去重（同一座城两套查询都会返回，人口多的留下），
/// 再按人口从大到小排——大城市天然排前面。
List<CitySuggestion> mergeCitySuggestions(
    List<CitySuggestion> a, List<CitySuggestion> b) {
  final merged = <CitySuggestion>[];
  final indexOf = <(int, int), int>{};
  for (final c in <CitySuggestion>[...a, ...b]) {
    final key = (
      ((c.latitude ?? 0) * 100).round(),
      ((c.longitude ?? 0) * 100).round(),
    );
    final idx = indexOf[key];
    if (idx == null) {
      indexOf[key] = merged.length;
      merged.add(c);
    } else if (_popOf(c) > _popOf(merged[idx])) {
      merged[idx] = c;
    }
  }
  merged.sort((x, y) => _popOf(y).compareTo(_popOf(x)));
  return merged;
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

  Future<List<CitySuggestion>> _geocode(String name) async {
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
          population: asIntOrNull(m['population']),
        ));
      }
    }
    return out;
  }

  Future<List<CitySuggestion>> searchCities(String name) async {
    final query = name.trim();
    final results = await _geocode(query);
    // Open-Meteo 的中文索引不全：搜「阜阳」只出江苏的同名村，
    // 补一发「阜阳市」的查询，合并后按人口排，正确的地级市就会浮上来。
    final variant = cityQueryVariant(query);
    if (variant != null) {
      try {
        final more = await _geocode(variant);
        return mergeCitySuggestions(results, more);
      } catch (_) {
        // 补充查询失败不影响第一发的结果
      }
    }
    return results;
  }
}
