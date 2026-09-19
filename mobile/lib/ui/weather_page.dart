/// 天气页：实况 + 24 小时温度 + 未来 7 天 + 生活提示 + 我的地点（增删切换）。
///
/// 行为对齐电脑版（`app.js` 的天气区 + `server.py` 的 weather_result）：
/// 优先用没过期的缓存，过期/强制刷新才联网；联网失败时同城市的旧缓存
/// 顶上并标「旧数据，网络不可用」；没选城市时引导去搜索，不预置任何地区。
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../weather_api.dart';
import '../weather_logic.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key, required this.store, this.api});

  final Store store;

  /// 测试时注入假接口；不传就用真的 Open-Meteo。
  final WeatherApi? api;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  late final WeatherApi _api = widget.api ?? WeatherApi();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _listCtrl = ScrollController();

  bool _loading = false;
  bool _searching = false;
  bool _stale = false;
  String? _error;
  Map<String, dynamic>? _payload;
  String? _fetchedAt;
  List<CitySuggestion> _results = <CitySuggestion>[];
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  /// 取天气：缓存没过期就直接用；否则联网，失败降级旧缓存。
  Future<void> _load({bool force = false}) async {
    final gen = ++_gen;
    final settings = widget.store.settings();
    final city = settings.weatherCity;
    if (!city.isSet) {
      if (gen == _gen && mounted) {
        setState(() {
          _payload = null;
          _fetchedAt = null;
          _stale = false;
          _error = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() => _loading = true);

    final cache = widget.store.weatherCache();
    final fresh = weatherCacheFresh(
      city: city,
      cache: cache,
      refreshMinutes: settings.refreshMinutes,
      now: DateTime.now(),
    );
    if (!force && fresh) {
      if (gen == _gen && mounted) {
        setState(() {
          _payload = cache.payload;
          _fetchedAt = cache.fetchedAt;
          _stale = false;
          _error = null;
          _loading = false;
        });
      }
      return;
    }

    try {
      final raw = await _api.fetchWeather(city.latitude!, city.longitude!);
      final payload = normalize(raw, city, now: DateTime.now());
      final saved = widget.store.setWeatherCache(city, payload);
      if (gen == _gen && mounted) {
        setState(() {
          _payload = payload;
          _fetchedAt = saved.fetchedAt;
          _stale = false;
          _error = null;
          _loading = false;
        });
      }
    } on WeatherApiException catch (e) {
      final fb = staleFallback(city: city, cache: cache);
      if (gen == _gen && mounted) {
        setState(() {
          if (fb != null && fb.payload != null) {
            _payload = fb.payload;
            _fetchedAt = fb.fetchedAt;
            _stale = true;
          } else {
            _payload = null;
            _fetchedAt = null;
            _stale = false;
          }
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      _toast('先输入城市名');
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await _api.searchCities(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searching = false;
      });
      if (r.isEmpty) {
        _toast('没搜到，检查一下网络');
      } else {
        _toast('搜到 ${r.length} 个，选择即可');
      }
    } on WeatherApiException catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      _toast('城市搜索失败：${e.message}');
    }
  }

  /// 把地点写回 settings（weatherCities + weatherCity 一起存），再强制刷新天气。
  void _applyPlaces(PlacesWrite w, {String? toast}) {
    final s = widget.store.settings();
    s.weatherCities = w.places;
    s.weatherCity = w.current;
    widget.store.saveSettings(s);
    setState(() => _results = <CitySuggestion>[]);
    if (toast != null) _toast(toast);
    _load(force: true);
  }

  void _addFromSuggestion(CitySuggestion c) {
    try {
      final s = widget.store.settings();
      final w = addPlace(s.weatherCities, c.toPlaceData(),
          newId: () => widget.store.newId('pl'));
      _applyPlaces(w, toast: '已切换到 ${c.name}');
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  void _selectPlace(Place p) {
    final s = widget.store.settings();
    final w = selectPlace(s.weatherCities, p.id);
    if (w == null) return;
    _applyPlaces(w, toast: '已切换到 ${p.name}');
  }

  void _removePlace(Place p) {
    final s = widget.store.settings();
    final w = removePlace(s.weatherCities, s.weatherCity, p.id);
    _applyPlaces(w, toast: w.deleted ? '已删除 ${p.name}' : null);
  }

  // ---------- 渲染小工具 ----------

  /// `更新于 HH:MM` 的 HH:MM：fetchedAt 形如 2026-09-19T08:30:00+08:00，取 11~16。
  String get _stampHhmm {
    final t = _fetchedAt ?? '';
    return t.length >= 16 ? t.substring(11, 16) : '--:--';
  }

  String _numText(dynamic v, [String suffix = '']) =>
      (v == null || v == '') ? '—' : '$v$suffix';

  Widget _kv(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: <Widget>[
        Text(label, style: TextStyle(fontSize: 12, color: cs.outline)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  String weekdayCn(String date) {
    const names = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final d = DateTime.tryParse(date);
    return d == null ? '' : names[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.store.settings();
    final city = settings.weatherCity;
    final cs = Theme.of(context).colorScheme;

    Widget body;
    if (!city.isSet) {
      body = _empty(cs, key: 'wx-empty-no-city', icon: Icons.location_off_outlined,
          title: '先选一个城市',
          hint: '软件不预设任何地区，选好之后这里会显示实况、24 小时温度和未来 7 天预报');
    } else if (_payload == null && _error != null) {
      body = _empty(cs, key: 'wx-empty-error', icon: Icons.cloud_off_outlined,
          title: '暂时取不到天气',
          hint: '其他地方都能正常用，过一会儿再点刷新试试');
    } else if (_payload == null) {
      body = const Center(
        key: ValueKey('wx-loading'),
        child: CircularProgressIndicator(),
      );
    } else {
      body = _weatherList(_payload!);
    }

    return Column(
      key: const ValueKey('page-weather'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey('wx-city-search'),
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.travel_explore, size: 20),
                  hintText: '搜索城市，加到我的地点',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            IconButton(
              key: const ValueKey('wx-search-btn'),
              tooltip: '搜索城市',
              onPressed: _searching ? null : _search,
              icon: _searching
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
            ),
            IconButton(
              key: const ValueKey('wx-refresh'),
              tooltip: '刷新天气',
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text(
            _stampText(city),
            key: const ValueKey('wx-stamp'),
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),
        if (_results.isNotEmpty)
          Flexible(
            child: Card(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final c = _results[i];
                  return ListTile(
                    key: ValueKey('wx-result-$i'),
                    dense: true,
                    title: Text(c.name),
                    subtitle: c.admin.isEmpty ? null : Text(c.admin),
                    trailing: c.country.isEmpty ? null : Text(c.country,
                        style: TextStyle(fontSize: 11, color: cs.outline)),
                    onTap: () => _addFromSuggestion(c),
                  );
                },
              ),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  String _stampText(City city) {
    if (!city.isSet) return '城市未设置';
    if (_payload == null && _error != null) return '取数据失败';
    if (_payload == null) return '正在取数据…';
    final staleMark = _stale ? '（旧数据，网络不可用）' : '';
    return '更新于 $_stampHhmm$staleMark · 数据源 Open-Meteo';
  }

  Widget _empty(ColorScheme cs,
      {required String key, required IconData icon, required String title, required String hint}) {
    return Center(
      key: ValueKey<String>(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 46, color: cs.outline),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(hint, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ],
        ),
      ),
    );
  }

  Widget _weatherList(Map<String, dynamic> p) {
    final cs = Theme.of(context).colorScheme;
    final settings = widget.store.settings();
    final cur = asMap(p['current']);
    final payloadCity = asMap(p['city']);
    final hours = p['hourly'] is List ? p['hourly'] as List : const <dynamic>[];
    final daily = p['daily'] is List ? p['daily'] as List : const <dynamic>[];
    final places = widget.store.settings().weatherCities;
    final tips = (p['tips'] is List ? p['tips'] as List : const <dynamic>[])
        .map(asString)
        .where((s) => s.isNotEmpty)
        .toList();
    final today = daily.isNotEmpty ? asMap(daily[0]) : const <String, dynamic>{};

    // 24 小时温度柱的高度（和电脑版同款公式）
    final temps = <double>[];
    for (final h in hours) {
      final t = asDoubleOrNull(asMap(h)['temp']);
      if (t != null) temps.add(t);
    }
    final maxT = temps.isNotEmpty ? temps.reduce((a, b) => a > b ? a : b) : 1.0;
    final minT = temps.isNotEmpty ? temps.reduce((a, b) => a < b ? a : b) : 0.0;
    final span = (maxT - minT) < 1 ? 1.0 : maxT - minT;

    return ListView(
      controller: _listCtrl,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(
                  _numText(cur['temp']).replaceAll('—', '--'),
                  key: const ValueKey('wx-temp'),
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w300, height: 1.1),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${asString(cur['text'])}${payloadCity['name'] == null ? '' : ' · ${asString(payloadCity['name'])}'}',
                      style: TextStyle(fontSize: 13, color: cs.outline),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: tips.isEmpty
                    ? Text('暂无特别提示',
                        key: const ValueKey('wx-tips-none'),
                        style: TextStyle(fontSize: 12, color: cs.outline))
                    : Container(
                        key: const ValueKey('wx-tips'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(tips.join('；'),
                            style: const TextStyle(fontSize: 12)),
                      ),
              ),
              const Divider(height: 20),
              _kv('体感', _numText(cur['feels'], '°')),
              _kv('湿度', _numText(cur['humidity'], '%')),
              _kv('风', '${asString(cur['windDir'])} ${_numText(cur['wind'], ' m/s')}'),
              _kv('气压', _numText(cur['pressure'], ' hPa')),
              _kv('能见度', _numText(cur['visibility'], ' km')),
              _kv('降水概率', _numText(cur['pop'], '%')),
              _kv('今日最高', _numText(today['max'], '°')),
              _kv('今日最低', _numText(today['min'], '°')),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('未来 24 小时温度',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                key: const ValueKey('wx-hours'),
                height: 96,
                child: hours.isEmpty
                    ? Text('没有小时数据', style: TextStyle(fontSize: 12, color: cs.outline))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: hours.length,
                        itemBuilder: (context, i) {
                          final h = asMap(hours[i]);
                          final t = asDoubleOrNull(h['temp']);
                          final hgt = t == null
                              ? 8
                              : (16 + (t - minT) / span * 52).round();
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                Text(t == null ? '' : '${t.round()}',
                                    style: const TextStyle(fontSize: 11)),
                                const SizedBox(height: 2),
                                Container(
                                  width: 8,
                                  height: hgt.toDouble(),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(asString(h['time']),
                                    style: TextStyle(fontSize: 10, color: cs.outline)),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('未来 7 天',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (daily.isEmpty)
                Text('没有预报数据', style: TextStyle(fontSize: 12, color: cs.outline)),
              for (var i = 0; i < daily.length; i++)
                Padding(
                  key: ValueKey('wx-day-$i'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: <Widget>[
                    SizedBox(
                      width: 86,
                      child: Text(
                        '${weekdayCn(asString(asMap(daily[i])['date']))} ${asString(asMap(daily[i])['date']).length >= 10 ? asString(asMap(daily[i])['date']).substring(5) : asString(asMap(daily[i])['date'])}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Text(asString(asMap(daily[i])['text']),
                          style: TextStyle(fontSize: 13, color: cs.outline)),
                    ),
                    Text(
                      '${_numText(asMap(daily[i])['min'], '°')} / ${_numText(asMap(daily[i])['max'], '°')}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('我的地点',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              if (places.isEmpty)
                Text('搜一个城市加进来，切换更快',
                    style: TextStyle(fontSize: 12, color: cs.outline)),
              for (final pl in places)
                ListTile(
                  key: ValueKey('wx-place-${pl.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isCurrentPlace(settings.weatherCity, pl)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: isCurrentPlace(settings.weatherCity, pl)
                        ? cs.primary
                        : cs.outline,
                  ),
                  title: Text(pl.label, style: const TextStyle(fontSize: 14)),
                  trailing: IconButton(
                    key: ValueKey('wx-place-del-${pl.id}'),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: '删除',
                    onPressed: () => _removePlace(pl),
                  ),
                  onTap: () => _selectPlace(pl),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}
