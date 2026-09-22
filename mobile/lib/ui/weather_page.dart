/// 天气页（v2.0 重排）。
///
/// 改动动机：温度是这一页的主角，之前被塞在卡片内部稀释了；8 行详情是纵向
/// 扫 8 次；24 小时用柱状图表达不出趋势。
///
/// 现在：主卡（靛蓝渐变 + 40px 大温度 + 预警提示条）→ 24 小时折线 →
/// 天气详情 2×4 网格 → 未来 7 天 → 我的地点。
///
/// 行为仍对齐电脑版 `weather_result`：缓存优先、过期才联网、失败降级旧数据。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../weather_api.dart';
import '../weather_logic.dart';
import 'design.dart';

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

  /// 把地点写回 settings，再强制刷新天气。
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

  // ---------- 小工具 ----------

  String get _stampHhmm {
    final t = _fetchedAt ?? '';
    return t.length >= 16 ? t.substring(11, 16) : '--:--';
  }

  String _numText(dynamic v, [String suffix = '']) =>
      (v == null || v == '') ? '—' : '$v$suffix';

  String _fmtTemp(dynamic v) {
    final d = asDoubleOrNull(v);
    if (d == null) return '--';
    return d == d.roundToDouble() ? '${d.round()}' : '$d';
  }

  String weekdayCn(String date) {
    const names = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final d = DateTime.tryParse(date);
    return d == null ? '' : names[d.weekday - 1];
  }

  String _stampText(City city) {
    if (!city.isSet) return '城市未设置';
    if (_payload == null && _error != null) return '取数据失败';
    if (_payload == null) return '正在取数据…';
    final staleMark = _stale ? '（旧数据，网络不可用）' : '';
    return '更新于 $_stampHhmm$staleMark · 数据源 Open-Meteo';
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.store.settings();
    final city = settings.weatherCity;

    Widget body;
    if (!city.isSet) {
      body = _empty(
        key: 'wx-empty-no-city',
        icon: Icons.location_off_outlined,
        title: '先选一个城市',
        hint: '软件不预设任何地区，选好之后这里会显示实况、24 小时温度和未来 7 天预报',
      );
    } else if (_payload == null && _error != null) {
      body = _empty(
        key: 'wx-empty-error',
        icon: Icons.cloud_off_outlined,
        title: '暂时取不到天气',
        hint: '其他地方都能正常用，过一会儿再点刷新试试',
      );
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
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s2, Sp.s2, 0),
          child: Row(children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey('wx-city-search'),
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: '搜索城市，加到我的地点',
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
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search, size: 20),
            ),
            IconButton(
              key: const ValueKey('wx-refresh'),
              tooltip: '刷新天气',
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s2, Sp.gutter, 0),
          child: Text(
            _stampText(city),
            key: const ValueKey('wx-stamp'),
            style: Type.xs.copyWith(color: Tone.of(context).ink400),
          ),
        ),
        if (_results.isNotEmpty)
          Card2(
            margin: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s2, Sp.gutter, 0),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                for (var i = 0; i < _results.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      color: Tone.of(context).ink100,
                    ),
                  InkWell(
                    key: ValueKey('wx-result-$i'),
                    onTap: () => _addFromSuggestion(_results[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _results[i].name,
                                  style: Type.body
                                      .copyWith(color: Tone.of(context).ink900),
                                ),
                                if (_results[i].admin.isNotEmpty)
                                  Text(_results[i].admin,
                                      style: Type.xs
                                          .copyWith(color: Tone.of(context).ink400)),
                              ],
                            ),
                          ),
                          if (_results[i].country.isNotEmpty)
                            Text(_results[i].country,
                                style: Type.xs
                                    .copyWith(color: Tone.of(context).ink400)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  Widget _empty(
      {required String key,
      required IconData icon,
      required String title,
      required String hint}) {
    final tone = Tone.of(context);
    return Center(
      key: ValueKey<String>(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 40, color: tone.ink300),
            const SizedBox(height: 12),
            Text(title, style: Type.h3.copyWith(color: tone.ink900)),
            const SizedBox(height: 6),
            Text(hint,
                textAlign: TextAlign.center,
                style: Type.sm.copyWith(color: tone.ink400)),
          ],
        ),
      ),
    );
  }

  Widget _weatherList(Map<String, dynamic> p) {
    final tone = Tone.of(context);
    final settings = widget.store.settings();
    final cur = asMap(p['current']);
    final payloadCity = asMap(p['city']);
    final hours = p['hourly'] is List ? p['hourly'] as List : const <dynamic>[];
    final daily = p['daily'] is List ? p['daily'] as List : const <dynamic>[];
    final places = settings.weatherCities;
    final today = daily.isNotEmpty ? asMap(daily[0]) : const <String, dynamic>{};
    final cityName = asString(payloadCity['name']);

    return ListView(
      controller: _listCtrl,
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s2, Sp.gutter, Sp.s6),
      children: <Widget>[
        _hero(cur, cityName, today),
        const SizedBox(height: Sp.s4),
        Card2(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHead(
                title: '未来 24 小时',
                trailing: '逐小时',
                fontSize: 16,
              ),
              _HourChart(
                key: const ValueKey('wx-hours'),
                temps: <double>[
                  for (final h in hours)
                    if (asDoubleOrNull(asMap(h)['temp']) != null)
                      asDoubleOrNull(asMap(h)['temp'])!,
                ],
                labels: <String>[
                  for (final h in hours) asString(asMap(h)['time']),
                ],
                nowTemp: _fmtTemp(cur['temp']),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.s4),
        Card2(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHead(title: '天气详情', fontSize: 16),
              _detailGrid(cur, today, tone),
            ],
          ),
        ),
        const SizedBox(height: Sp.s4),
        Card2(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHead(title: '未来 7 天', fontSize: 16),
              if (daily.isEmpty)
                Text('没有预报数据', style: Type.sm.copyWith(color: tone.ink400)),
              for (var i = 0; i < daily.length; i++)
                Padding(
                  key: ValueKey('wx-day-$i'),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(children: <Widget>[
                    SizedBox(
                      width: 46,
                      child: Text(
                        i == 0
                            ? '今天'
                            : weekdayCn(asString(asMap(daily[i])['date'])),
                        style: Type.sm.copyWith(
                          color: tone.ink700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        asString(asMap(daily[i])['text']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sm.copyWith(color: tone.ink400),
                      ),
                    ),
                    Text(
                      '${_numText(asMap(daily[i])['min'], '°')} / ${_numText(asMap(daily[i])['max'], '°')}',
                      style: Type.num(Type.sm).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tone.ink900,
                      ),
                    ),
                  ]),
                ),
              if (daily.isNotEmpty)
                Divider(height: 1, thickness: 1, color: tone.ink100),
            ],
          ),
        ),
        const SizedBox(height: Sp.s4),
        Card2(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHead(title: '我的地点', fontSize: 16),
              if (places.isEmpty)
                Text('搜一个城市加进来，切换更快',
                    style: Type.xs.copyWith(color: tone.ink400)),
              for (final pl in places)
                _placeRow(pl, settings.weatherCity),
            ],
          ),
        ),
      ],
    );
  }

  /// 主卡：靛蓝渐变 + 40px 大温度 + 预警提示条。
  Widget _hero(Map<String, dynamic> cur, String cityName, Map<String, dynamic> today) {
    const c1 = Color(0xFF3D6BE5);
    const c2 = Color(0xFF2B54C8);
    const c3 = Color(0xFF22409C);
    final popValue = asDoubleOrNull(cur['pop']);
    final hasAlert = popValue != null && popValue >= 50;

    Widget line(String text) => Text(
          text,
          style: TextStyle(
            fontSize: 11,
            height: 1.45,
            color: Colors.white.withValues(alpha: .78),
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(R.lg),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.7, -1),
            end: Alignment(0.7, 1),
            colors: <Color>[c1, c2, c3],
            stops: <double>[0, .52, 1],
          ),
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -90,
              top: -120,
              child: IgnorePointer(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[Color(0x4DFFFFFF), Color(0x00FFFFFF)],
                      stops: <double>[0, .66],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.place_outlined,
                          size: 13, color: Colors.white.withValues(alpha: .82)),
                      const SizedBox(width: 4),
                      Text(
                        cityName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: .82),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _fmtTemp(cur['temp']),
                            key: const ValueKey('wx-temp'),
                            style: Type.display.copyWith(color: Colors.white),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              '°',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: .95),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                asString(cur['text']),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              line('体感 ${_numText(cur['feels'], '°')} · 湿度 ${_numText(cur['humidity'], '%')}'),
                              Text(
                                '${_numText(today['min'], '°')} / ${_numText(today['max'], '°')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.45,
                                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                                  color: Colors.white.withValues(alpha: .78),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 预警条：原来只是卡内一个小胶囊，现在给它真正的视觉权重
                  if (hasAlert) ...<Widget>[
                    const SizedBox(height: 16),
                    Container(
                      key: const ValueKey('wx-tips'),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(R.sm),
                        border: const Border(
                          left: BorderSide(color: Color(0xFFFFC46B), width: 3),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.warning_amber_rounded,
                              size: 15, color: Color(0xFFFFC46B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '未来几小时降水概率 ${_numText(cur['pop'], '%')}，出门记得带伞',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: Colors.white.withValues(alpha: .95),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (asString(cur['text']).isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      '暂无特别提示',
                      key: const ValueKey('wx-tips-none'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: .62),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 详情：2 列网格（比纵向 8 行扫视快）。
  Widget _detailGrid(
    Map<String, dynamic> cur,
    Map<String, dynamic> today,
    Tone tone,
  ) {
    final items = <(String, String)>[
      ('体感', _numText(cur['feels'], '°')),
      ('降水概率', _numText(cur['pop'], '%')),
      ('湿度', _numText(cur['humidity'], '%')),
      ('能见度', _numText(cur['visibility'], ' km')),
      ('风', '${asString(cur['windDir'])} ${_numText(cur['wind'], ' m/s')}'),
      ('气压', _numText(cur['pressure'], ' hPa')),
      ('今日最高', _numText(today['max'], '°')),
      ('今日最低', _numText(today['min'], '°')),
    ];

    return Column(
      children: <Widget>[
        for (var i = 0; i < items.length; i += 2)
          Row(
            children: <Widget>[
              Expanded(child: _detailCell(items[i].$1, items[i].$2, tone, i)),
              Expanded(
                child: i + 1 < items.length
                    ? _detailCell(items[i + 1].$1, items[i + 1].$2, tone, i + 1)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _detailCell(String k, String v, Tone tone, int index) {
    final right = index.isOdd;
    return Padding(
      padding: EdgeInsets.only(
        top: 11,
        bottom: 11,
        left: right ? 12 : 0,
        right: right ? 0 : 12,
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: tone.ink100),
            left: BorderSide(
              color: right ? tone.ink100 : Colors.transparent,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Row(
            children: <Widget>[
              Text(k, style: Type.sm.copyWith(color: tone.ink400)),
              const Spacer(),
              Flexible(
                child: Text(
                  v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.num(Type.sm).copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: tone.ink900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeRow(Place p, City current) {
    final tone = Tone.of(context);
    final on = isCurrentPlace(current, p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(
            on ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: on ? tone.primary : tone.ink300,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(p.label, style: Type.body.copyWith(color: tone.ink900)),
          ),
          IconButton(
            key: ValueKey('wx-place-${p.id}'),
            tooltip: '切换到 ${p.label}',
            visualDensity: VisualDensity.compact,
            onPressed: on ? null : () => _selectPlace(p),
            icon: const Icon(Icons.swap_horiz, size: 18),
          ),
          IconButton(
            key: ValueKey('wx-place-del-${p.id}'),
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            onPressed: () => _removePlace(p),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 24 小时温度折线（带渐变面积）；柱状图表达「量」，折线表达「趋势」。
class _HourChart extends StatelessWidget {
  const _HourChart({super.key, required this.temps, required this.labels, required this.nowTemp});

  final List<double> temps;
  final List<String> labels;
  final String nowTemp;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    if (temps.isEmpty) {
      return Text('没有小时数据', style: Type.sm.copyWith(color: tone.ink400));
    }
    // 最多画 24 个点，多的均匀抽样，免得线上全是疙瘩。
    final pts = <double>[];
    final step = math.max(1, (temps.length / 24).ceil());
    for (var i = 0; i < temps.length; i += step) {
      pts.add(temps[i]);
    }
    if (pts.length < 2) pts.add(pts.first);

    final axis = <String>[];
    if (labels.length >= 4) {
      final q = (labels.length - 1) / 4;
      for (var i = 0; i < 5; i++) {
        final s = labels[(q * i).round()];
        axis.add(s.length >= 16 ? s.substring(11, 16) : s);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: tone.primarySoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '现在',
                style: Type.xs.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: tone.primary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$nowTemp°',
              style: Type.num(Type.sm).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tone.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: CustomPaint(
            size: Size.infinite,
            painter: _LinePainter(
              values: pts,
              line: tone.primary,
              fillTop: tone.primary.withValues(alpha: .26),
              dotFill: tone.surface,
            ),
          ),
        ),
        if (axis.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final a in axis)
                Text(
                  a,
                  style: Type.num(Type.xs).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: tone.ink300,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.line,
    required this.fillTop,
    required this.dotFill,
  });

  final List<double> values;
  final Color line;
  final Color fillTop;
  final Color dotFill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      min = math.min(min, v);
      max = math.max(max, v);
    }
    final span = (max - min) < 1 ? 1.0 : max - min;
    const pad = 8.0;
    final h = size.height - pad * 2;

    Offset at(int i) {
      final x = size.width * i / (values.length - 1);
      final y = pad + h - (values[i] - min) / span * h;
      return Offset(x, y);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[fillTop, fillTop.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (values.length <= 12) {
      for (var i = 0; i < values.length; i++) {
        canvas.drawCircle(at(i), 3.6, Paint()..color = dotFill);
        canvas.drawCircle(
          at(i),
          3.6,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.line != line || old.fillTop != fillTop;
}
