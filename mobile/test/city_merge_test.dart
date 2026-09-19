// 城市搜索「双查询合并」的单元测试（修「阜阳显示成江苏」的 bug）：
// Open-Meteo 的中文索引不全，搜「阜阳」只出江苏同名村，
// 补搜「阜阳市」才能命中安徽的地级市，合并后按人口排。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/weather_api.dart';

CitySuggestion place(String name, String admin, double lat, double lon,
        {int? pop}) =>
    CitySuggestion(
        name: name, admin: admin, latitude: lat, longitude: lon, population: pop);

void main() {
  group('双查询合并', () {
    test('安徽阜阳市要排到江苏同名村前面', () {
      final village = place('阜阳', '江苏', 33.79932, 119.70367);
      final city = place('阜阳市', '安徽', 32.9, 115.8, pop: 1768947);
      final merged = mergeCitySuggestions(<CitySuggestion>[village],
          <CitySuggestion>[city]);
      expect(merged, hasLength(2));
      expect(merged.first.admin, '安徽', reason: '人口多的真城市排前面');
      expect(merged.first.name, '阜阳市');
    });

    test('同一座城两套查询都返回时去重', () {
      final a = place('合肥', '安徽', 31.86389, 117.28, pop: 5050000);
      final b = place('合肥市', '安徽', 31.86389, 117.28, pop: 5050000);
      final merged = mergeCitySuggestions(<CitySuggestion>[a], <CitySuggestion>[b]);
      expect(merged, hasLength(1), reason: '坐标几乎一样的算同一座城');
    });

    test('没有人口信息的排后面', () {
      final unknown = place('某地', '某省', 30.0, 120.0);
      final big = place('大城市', '某省', 31.0, 121.0, pop: 800000);
      final merged = mergeCitySuggestions(<CitySuggestion>[unknown],
          <CitySuggestion>[big]);
      expect(merged.first.name, '大城市');
    });
  });

  group('补充查询词', () {
    test('中文名补「市」，带「市」的去后缀', () {
      expect(cityQueryVariant('阜阳'), '阜阳市');
      expect(cityQueryVariant('阜阳市'), '阜阳');
    });

    test('非中文和空串不补', () {
      expect(cityQueryVariant('Fuyang'), isNull);
      expect(cityQueryVariant('  '), isNull);
    });
  });
}
