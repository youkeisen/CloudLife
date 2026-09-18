# -*- coding: utf-8 -*-
"""测试用的 Open-Meteo 假数据（结构与真实接口一致）。"""
from datetime import datetime, timedelta


def forecast(hours=48, days=7, **over):
    base = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    times = [(base + timedelta(hours=i)).isoformat() for i in range(hours)]
    raw = {
        'latitude': 31.34,
        'longitude': 118.38,
        'current': {
            'time': base.isoformat(),
            'temperature_2m': 26.4,
            'relative_humidity_2m': 68,
            'apparent_temperature': 27.9,
            'is_day': 1,
            'weather_code': 3,
            'wind_speed_10m': 2.41,
            'wind_direction_10m': 135.0,
            'surface_pressure': 1008.3,
        },
        'hourly': {
            'time': times,
            'temperature_2m': [20 + (i % 12) for i in range(hours)],
            'precipitation_probability': [(i * 3) % 100 for i in range(hours)],
            'visibility': [12000 + i * 10 for i in range(hours)],
        },
        'daily': {
            'time': [(base + timedelta(days=i)).strftime('%Y-%m-%d') for i in range(days)],
            'weather_code': [3, 0, 2, 61, 3, 0, 1][:days],
            'temperature_2m_max': [27.0, 29.0, 28.0, 25.0, 24.0, 27.0, 28.0][:days],
            'temperature_2m_min': [21.0, 20.0, 22.0, 20.0, 19.0, 18.0, 20.0][:days],
            'precipitation_probability_max': [10, 0, 20, 80, 30, 5, 0][:days],
            'uv_index_max': [4.0, 6.5, 5.0, 2.0, 3.0, 7.0, 6.0][:days],
        },
    }
    if over.get('current'):
        raw['current'].update(over['current'])
    if over.get('daily'):
        raw['daily'].update(over['daily'])
    return raw


GEO_RESULTS = {
    'results': [
        {'name': '合肥', 'admin1': '安徽省', 'country': '中国', 'latitude': 31.86, 'longitude': 117.28},
        {'name': '芜湖', 'admin1': '安徽省', 'country': '中国', 'latitude': 31.34, 'longitude': 118.38},
    ]
}


class FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def read(self):
        import json
        return json.dumps(self._payload).encode('utf-8')

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False
