# -*- coding: utf-8 -*-
"""阶段 5 测试：天气归一化（用替身数据）+ 联网失败降级 + 真实接口（需 net 参数）。"""
import json
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import ServerTestCase  # noqa: E402
import fixtures  # noqa: E402
import weather as wx  # noqa: E402

NET = os.environ.get('MYDAY_NET') == '1'


class TestWeatherUnit(unittest.TestCase):
    """直接测 weather 模块：网络用替身，永远不依赖真实网络。"""

    def setUp(self):
        self.city = {'name': '测试城', 'latitude': 31.34, 'longitude': 118.38}
        self.original_urlopen = wx.urllib.request.urlopen

    def tearDown(self):
        wx.urllib.request.urlopen = self.original_urlopen

    def test_normalize_current(self):
        p = wx.normalize(fixtures.forecast(), self.city)
        self.assertEqual(p['current']['temp'], 26.4)
        self.assertEqual(p['current']['feels'], 27.9)
        self.assertEqual(p['current']['humidity'], 68)
        self.assertEqual(p['current']['text'], '阴')
        self.assertEqual(p['current']['pressure'], 1008.3)
        self.assertTrue(p['current']['visibility'])
        self.assertEqual(p['city']['name'], '测试城')

    def test_hourly_24_and_daily_7(self):
        p = wx.normalize(fixtures.forecast(), self.city)
        self.assertEqual(len(p['hourly']), 24)
        self.assertEqual(len(p['daily']), 7)
        self.assertTrue(all('time' in h and 'temp' in h for h in p['hourly']))

    def test_wmo_texts_are_chinese_and_complete(self):
        for code in wx.WMO_CODES:
            self.assertTrue(wx.wmo_text(code), '码 %s 缺少中文' % code)
            self.assertTrue(wx.wmo_icon(code))
        self.assertEqual(wx.wmo_text(0), '晴')
        self.assertEqual(wx.wmo_text(61), '小雨')
        self.assertEqual(wx.wmo_text(95), '雷阵雨')
        self.assertEqual(wx.wmo_text(9999), '未知天气')

    def test_wind_direction(self):
        self.assertIn(wx.wind_dir_name(0), ('北',))
        self.assertIn(wx.wind_dir_name(90), ('东',))
        self.assertEqual(wx.wind_dir_name(None), '')

    def test_tips_temperature_gap(self):
        p = wx.normalize(fixtures.forecast(daily={'temperature_2m_max': [30.0],
                                                  'temperature_2m_min': [18.0]}), self.city)
        self.assertTrue(any('温差' in t for t in p['tips']), str(p['tips']))

    def test_tips_umbrella(self):
        # 用固定数据，避免结果随运行时刻变化（原来靠 hourly 的偶然取值才过）
        p = wx.normalize(fixtures.forecast(daily={'precipitation_probability_max': [80]}), self.city)
        self.assertTrue(any('伞' in t for t in p['tips']), '今天降水概率 80 应提示带伞：%s' % p['tips'])

    def test_tips_umbrella_from_hourly(self):
        # 整天概率不高、但最近几小时会下雨，同样要提醒
        raw = fixtures.forecast()
        raw['hourly']['precipitation_probability'] = [90] * len(raw['hourly']['time'])
        raw['daily']['precipitation_probability_max'] = [0] * 7
        p = wx.normalize(raw, self.city)
        self.assertTrue(any('伞' in t for t in p['tips']), '未来几小时要下雨应提示带伞：%s' % p['tips'])

    def test_tips_empty_when_nothing_to_warn(self):
        # 不该无中生有：温和天气不给提示
        raw = fixtures.forecast()
        raw['daily']['temperature_2m_max'] = [26.0] * 7
        raw['daily']['temperature_2m_min'] = [22.0] * 7
        raw['daily']['precipitation_probability_max'] = [0] * 7
        raw['daily']['uv_index_max'] = [2.0] * 7
        raw['hourly']['precipitation_probability'] = [0] * len(raw['hourly']['time'])
        p = wx.normalize(raw, self.city)
        self.assertEqual(p['tips'], [], '温和天气不该硬凑提示：%s' % p['tips'])

    def test_tips_uv(self):
        p = wx.normalize(fixtures.forecast(daily={'uv_index_max': [7.0]}), self.city)
        self.assertTrue(any('防晒' in t for t in p['tips']), str(p['tips']))

    def test_fetch_raises_weather_error_on_network_failure(self):
        def boom(*a, **k):
            raise OSError('模拟断网')
        wx.urllib.request.urlopen = boom
        with self.assertRaises(wx.WeatherError):
            wx.fetch_weather(31.0, 118.0)

    def test_search_cities_parses_results(self):
        wx.urllib.request.urlopen = lambda *a, **k: fixtures.FakeResponse(fixtures.GEO_RESULTS)
        cities = wx.search_cities('合肥')
        self.assertEqual(len(cities), 2)
        self.assertEqual(cities[0]['name'], '合肥')
        self.assertEqual(cities[1]['admin'], '安徽省')

    def test_url_built_without_key(self):
        url = wx.build_forecast_url(31.0, 118.0)
        self.assertIn('api.open-meteo.com', url)
        self.assertIn('current=', url)
        self.assertNotIn('apikey', url.lower())
        self.assertNotIn('key=', url.lower())


class TestWeatherApi(ServerTestCase):

    def set_city(self, lat, lon, name='测试城', refresh=30):
        self.srv.ok('/api/settings', 'PUT', {
            'weatherCity': {'name': name, 'latitude': lat, 'longitude': lon,
                            'timezone': 'Asia/Shanghai'},
            'refreshMinutes': refresh})

    def seed_cache(self, name='测试城', hours_old=0):
        from datetime import datetime, timedelta, timezone
        cst = timezone(timedelta(hours=8))
        when = datetime.now(cst) - timedelta(hours=hours_old)
        obj = {
            'version': 1,
            'fetchedAt': when.isoformat(timespec='seconds'),
            'city': {'name': name, 'latitude': 31.0, 'longitude': 118.0},
            'payload': wx.normalize(fixtures.forecast(), {'name': name,
                                                          'latitude': 31.0, 'longitude': 118.0}),
        }
        (self.srv.data_dir / 'weather_cache.json').write_text(
            json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')
        return obj

    def test_no_city_selected(self):
        res = self.srv.request('/api/weather')
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'no_city')

    def test_manual_mode_uses_cache_without_network(self):
        self.set_city(31.0, 118.0, refresh=0)
        self.seed_cache()
        res = self.srv.request('/api/weather')
        self.assertTrue(res['json']['ok'])
        data = res['json']['data']
        self.assertEqual(data['source'], 'cache')
        self.assertFalse(data['stale'])
        self.assertEqual(data['payload']['current']['temp'], 26.4)

    def test_network_failure_falls_back_to_stale_cache(self):
        # 越界坐标必然请求失败，无论有没有网
        self.set_city(9999.0, 9999.0, refresh=30)
        self.seed_cache(hours_old=5)
        res = self.srv.request('/api/weather')
        self.assertTrue(res['json']['ok'])
        data = res['json']['data']
        self.assertTrue(data['stale'], '取不到新数据时应返回旧缓存')
        self.assertEqual(data['payload']['current']['temp'], 26.4)

    def test_network_failure_without_cache_is_graceful(self):
        self.set_city(9999.0, 9999.0, refresh=30)
        res = self.srv.request('/api/weather')
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'weather_error')
        self.assertTrue(res['json']['error'])

    def test_cities_bad_request(self):
        res = self.srv.request('/api/cities?q=')
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'bad_request')

    @unittest.skipUnless(NET, '需要联网，运行 run_tests.py all net 才会执行')
    def test_real_api(self):
        self.set_city(31.86, 117.28, name='合肥')
        res = self.srv.request('/api/weather?refresh=1')
        self.assertTrue(res['json']['ok'], res['json'])
        data = res['json']['data']
        self.assertEqual(data['source'], 'network')
        cur = data['payload']['current']
        self.assertIsInstance(cur['temp'], (int, float))
        self.assertTrue(cur['text'])
        self.assertEqual(len(data['payload']['hourly']), 24)
        self.assertEqual(len(data['payload']['daily']), 7)
        cached = json.loads((self.srv.data_dir / 'weather_cache.json').read_text(encoding='utf-8'))
        self.assertEqual(cached['payload']['current']['temp'], cur['temp'])
        # 第二次不应再打网络
        again = self.srv.request('/api/weather')
        self.assertEqual(again['json']['data']['source'], 'cache')

    @unittest.skipUnless(NET, '需要联网，运行 run_tests.py all net 才会执行')
    def test_real_city_search(self):
        res = self.srv.request('/api/cities?q=' + 'hefei')
        self.assertTrue(res['json']['ok'], res['json'])
        self.assertTrue(res['json']['data']['cities'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
