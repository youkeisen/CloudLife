# -*- coding: utf-8 -*-
"""阶段 10 测试：设置页天气栏的「我的地点」——添加、切换、移除、持久化。

背景（本次要解决的问题）：
    设置页 → 天气 →「城市」原来是个空的、点了没反应的下拉框，
    在这个界面里没有任何「添加地点」的入口，只能靠手填经纬度。
"""
import json
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import STATIC_DIR, ServerTestCase, TestServer  # noqa: E402
import fixtures  # noqa: E402
import store as store_mod  # noqa: E402
import weather as wx  # noqa: E402

CST = timezone(timedelta(hours=8))


class TestPlacesDefaults(unittest.TestCase):
    """零预置：地点列表默认必须是空的。"""

    def test_default_places_empty(self):
        d = store_mod.DEFAULTS['settings']
        self.assertIn('weatherCities', d, '设置里要有「我的地点」字段')
        self.assertEqual(d['weatherCities'], [], '默认不能预置任何地点')
        self.assertEqual(d['weatherCity']['name'], '')

    def test_max_places_is_sane(self):
        self.assertGreaterEqual(store_mod.MAX_PLACES, 5)
        self.assertLessEqual(store_mod.MAX_PLACES, 100)


class TestNormalizePlace(unittest.TestCase):
    """store.normalize_place 的边界，不依赖服务。"""

    def test_ok(self):
        p = store_mod.normalize_place({'name': ' 甲城 ', 'latitude': '31.1000',
                                       'longitude': 118.2, 'admin': ' 测试省 '})
        self.assertEqual(p['name'], '甲城')
        self.assertEqual(p['admin'], '测试省')
        self.assertEqual(p['latitude'], 31.1)
        self.assertEqual(p['timezone'], 'Asia/Shanghai')

    def test_bad(self):
        bads = [[], {'name': ''}, {'name': '甲城'},
                {'name': '甲城', 'latitude': None, 'longitude': 118.0},
                {'name': '甲城', 'latitude': 'abc', 'longitude': 118.0},
                {'name': '甲城', 'latitude': 91.0, 'longitude': 118.0},
                {'name': '甲城', 'latitude': -91.0, 'longitude': 118.0},
                {'name': '甲城', 'latitude': 31.0, 'longitude': 181.0},
                {'name': '甲城', 'latitude': True, 'longitude': 118.0}]
        for bad in bads:
            with self.assertRaises(ValueError, msg='应该拒绝：%r' % (bad,)):
                store_mod.normalize_place(bad)


class TestPlacesApi(ServerTestCase):

    def add(self, name='甲城', lat=31.10, lon=118.20, admin='测试省'):
        return self.srv.ok('/api/places', 'POST',
                           {'name': name, 'latitude': lat, 'longitude': lon, 'admin': admin})

    def names(self):
        return [p['name'] for p in self.srv.ok('/api/places')['places']]

    # ---------- 列表 / 添加 ----------
    def test_list_empty_at_first(self):
        d = self.srv.ok('/api/places')
        self.assertEqual(d['places'], [])
        self.assertEqual(d['current']['name'], '')
        self.assertIn('weatherCities', d['settings'])

    def test_add_creates_place_and_sets_current(self):
        d = self.add('甲城', 31.1, 118.2, '测试省')
        self.assertTrue(d['created'])
        p = d['place']
        self.assertTrue(p['id'], '地点要有 id，前端切换靠它')
        self.assertEqual(p['name'], '甲城')
        self.assertEqual(p['admin'], '测试省')
        self.assertEqual(p['latitude'], 31.1)
        self.assertEqual(p['longitude'], 118.2)
        self.assertEqual(len(d['places']), 1)
        self.assertEqual(d['current']['name'], '甲城')
        self.assertEqual(d['current']['latitude'], 31.1)
        # 当前城市必须真的落到设置里，天气页才认得
        s = self.srv.ok('/api/settings')
        self.assertEqual(s['weatherCity']['name'], '甲城')
        self.assertEqual(s['weatherCity']['latitude'], 31.1)
        self.assertEqual(len(s['weatherCities']), 1)
        self.assertIn('weatherCities', self.srv.ok('/api/bootstrap')['settings'])

    def test_add_second_becomes_current(self):
        self.add('甲城', 31.1, 118.2)
        d = self.add('乙城', 30.2, 120.3)
        self.assertEqual([p['name'] for p in d['places']], ['甲城', '乙城'])
        self.assertEqual(d['current']['name'], '乙城', '新加的地点应直接变成当前')

    def test_add_duplicate_coords_does_not_duplicate(self):
        first = self.add('甲城', 31.1, 118.2)
        again = self.add('甲城新名', 31.1, 118.2)
        self.assertFalse(again['created'], '同坐标应视为同一个地点')
        self.assertEqual(len(again['places']), 1, '不能出现重复地点')
        self.assertEqual(again['place']['id'], first['place']['id'])
        self.assertEqual(again['place']['name'], '甲城新名')
        self.assertEqual(again['current']['name'], '甲城新名')

    def test_add_keeps_order(self):
        for i, name in enumerate(['甲城', '乙城', '丙城']):
            self.add(name, 20.0 + i, 100.0 + i)
        self.assertEqual(self.names(), ['甲城', '乙城', '丙城'])

    # ---------- 切换 ----------
    def test_select_switches_current(self):
        a = self.add('甲城', 31.1, 118.2)['place']
        self.add('乙城', 30.2, 120.3)
        d = self.srv.ok('/api/places/select', 'POST', {'id': a['id']})
        self.assertEqual(d['current']['name'], '甲城')
        self.assertEqual(d['place']['id'], a['id'])
        s = self.srv.ok('/api/settings')
        self.assertEqual(s['weatherCity']['name'], '甲城')
        self.assertEqual(s['weatherCity']['longitude'], 118.2)
        self.assertEqual(len(s['weatherCities']), 2, '切换不该动列表')

    # ---------- 移除 ----------
    def test_delete_current_falls_back_to_first(self):
        a = self.add('甲城', 31.1, 118.2)['place']
        b = self.add('乙城', 30.2, 120.3)['place']
        d = self.srv.ok('/api/places', 'DELETE', {'id': b['id']})
        self.assertTrue(d['deleted'])
        self.assertEqual([p['id'] for p in d['places']], [a['id']])
        self.assertEqual(d['current']['name'], '甲城', '删掉当前地点应顺位到剩下的第一个')

    def test_delete_other_keeps_current(self):
        a = self.add('甲城', 31.1, 118.2)['place']
        self.add('乙城', 30.2, 120.3)
        d = self.srv.ok('/api/places', 'DELETE', {'id': a['id']})
        self.assertEqual(d['current']['name'], '乙城', '删别人不该影响当前城市')
        self.assertEqual(self.names(), ['乙城'])

    def test_delete_last_clears_current(self):
        a = self.add('甲城', 31.1, 118.2)['place']
        d = self.srv.ok('/api/places', 'DELETE', {'id': a['id']})
        self.assertEqual(d['places'], [])
        self.assertEqual(d['current']['name'], '', '最后一个地点删掉后当前城市要清空')
        self.assertIsNone(d['current']['latitude'])
        res = self.srv.request('/api/weather')
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'no_city')

    # ---------- 持久化 ----------
    def test_places_persist_across_restart(self):
        self.add('甲城', 31.1, 118.2)
        self.add('乙城', 30.2, 120.3)
        data_dir = str(self.srv.data_dir)
        self.srv.proc.terminate()
        self.srv.proc.wait(timeout=10)
        revived = TestServer(data_dir=data_dir)
        revived.start()
        try:
            d = revived.ok('/api/places')
            self.assertEqual([p['name'] for p in d['places']], ['甲城', '乙城'])
            self.assertEqual(d['current']['name'], '乙城')
            self.assertEqual(d['places'][0]['latitude'], 31.1)
        finally:
            revived.stop()
        self.srv.proc = None

    # ---------- 坏输入 ----------
    def test_bad_payloads_rejected(self):
        cases = [{'name': '', 'latitude': 31.0, 'longitude': 118.0},
                 {'name': '   ', 'latitude': 31.0, 'longitude': 118.0},
                 {'name': '甲城', 'latitude': 'abc', 'longitude': 118.0},
                 {'name': '甲城', 'latitude': 999, 'longitude': 118.0},
                 {'name': '甲城', 'latitude': 31.0, 'longitude': 200.0},
                 {'name': '甲城'},
                 {}]
        for body in cases:
            res = self.srv.request('/api/places', 'POST', body)
            self.assertEqual(res['status'], 400, '%r 应被拒绝' % (body,))
            self.assertEqual(res['json']['code'], 'bad_request')
        self.assertEqual(self.names(), [], '非法入参不能留下脏数据')

    def test_unknown_or_missing_id_never_500(self):
        self.add('甲城', 31.1, 118.2)
        for path, method in (('/api/places', 'DELETE'), ('/api/places/select', 'POST')):
            res = self.srv.request(path, method, {'id': 'nope'})
            self.assertNotEqual(res['status'], 500, path + ' 不该 500')
            self.assertFalse(res['json']['ok'])
            self.assertEqual(res['json']['code'], 'not_found')
            res = self.srv.request(path, method, {})
            self.assertEqual(res['status'], 400, path + ' 缺 id 应报错')
        self.assertEqual(self.names(), ['甲城'], '失败的操作不能改动数据')

    def test_place_limit(self):
        for i in range(store_mod.MAX_PLACES):
            self.add('城%d' % i, 10.0 + i, 80.0 + i)
        res = self.srv.request('/api/places', 'POST',
                               {'name': '多出来的', 'latitude': 60.0, 'longitude': 140.0})
        self.assertEqual(res['status'], 400, '超过上限应被拒绝')
        self.assertEqual(len(self.names()), store_mod.MAX_PLACES)

    # ---------- 和天气串起来 ----------
    def test_added_place_drives_weather(self):
        """加了地点之后天气页直接能用；走缓存，不依赖真实网络。"""
        self.add('测试城', 31.0, 118.0)
        self.srv.ok('/api/settings', 'PUT', {'refreshMinutes': 0})
        self._seed_cache('测试城', 31.0, 118.0)
        res = self.srv.request('/api/weather')
        self.assertTrue(res['json']['ok'], res['json'])
        self.assertEqual(res['json']['data']['source'], 'cache')
        self.assertEqual(res['json']['data']['payload']['current']['temp'], 26.4)

    def test_select_switching_city_invalidates_cache(self):
        """切到另一个地点后，旧城市的缓存不能再冒充新城市的天气。"""
        self.add('甲城', 31.0, 118.0)
        self.srv.ok('/api/settings', 'PUT', {'refreshMinutes': 0})
        self._seed_cache('甲城', 31.0, 118.0)
        # 先确认这份缓存本来是生效的，否则下面的断言没有意义
        before = self.srv.request('/api/weather')
        self.assertTrue(before['json']['ok'], before['json'])
        self.assertEqual(before['json']['data']['source'], 'cache')
        self.assertEqual(before['json']['data']['payload']['city']['name'], '甲城')
        # 换成另一个地点
        b = self.add('乙城', 32.0, 119.0)['place']
        self.srv.ok('/api/places/select', 'POST', {'id': b['id']})
        res = self.srv.request('/api/weather')
        if res['json']['ok']:
            data = res['json']['data']
            self.assertEqual(data['payload']['city']['name'], '乙城')
            self.assertNotEqual(data['source'], 'cache', '不该把甲城的缓存当乙城的用')
        else:
            self.assertEqual(res['json']['code'], 'weather_error')

    def _seed_cache(self, name, lat, lon):
        obj = {
            'version': 1,
            'fetchedAt': datetime.now(CST).isoformat(timespec='seconds'),
            'city': {'name': name, 'latitude': lat, 'longitude': lon},
            'payload': wx.normalize(fixtures.forecast(), {'name': name, 'latitude': lat, 'longitude': lon}),
        }
        (self.srv.data_dir / 'weather_cache.json').write_text(
            json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')
        return obj


class TestPlacesFrontend(unittest.TestCase):
    """设置页确实多了「添加地点」这套东西，且不是摆设。"""

    def test_settings_has_add_place_ui(self):
        html = (STATIC_DIR / 'index.html').read_text(encoding='utf-8')
        for elem in ('s_city', 's_cityToggle', 's_cityQ', 's_citySearchBtn',
                     's_cityResults', 's_placeList', 's_placeAddBox'):
            self.assertIn('id="%s"' % elem, html, '设置页缺少「我的地点」元素：' + elem)
        self.assertIn('添加地点', html, '界面上要有「添加地点」字样')

    def test_frontend_uses_places_api(self):
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        self.assertIn("api('/api/places'", js)
        self.assertIn("api('/api/places/select'", js)
        self.assertIn('weatherCities', js)
        for fn in ('function bindPlaces', 'function renderPlaces', 'function addPlace'):
            self.assertIn(fn, js, 'app.js 缺少 ' + fn)

    def test_city_state_has_single_source(self):
        """选城市统一走「我的地点」，别再各自直写 weatherCity 造成两套状态。"""
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        self.assertNotIn('saveSettings({ weatherCity', js)
        self.assertNotIn('Weather city', js)

    def test_search_results_are_clickable(self):
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        self.assertIn('data-city=', js, '搜索结果要带 data-city 才能点')
        self.assertIn('data-place=', js, '已保存地点要带 data-place 才能移除')


if __name__ == '__main__':
    unittest.main(verbosity=2)
