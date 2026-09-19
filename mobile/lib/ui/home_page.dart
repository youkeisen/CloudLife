/// 首页：问候 + 今天信息、今日课程（已上/正在上/下一节）、今日天气、备忘录速览。
///
/// 行为对齐电脑版（`app/static/app.js` 的 `renderHome` 区块 +
/// `server.py` 的 `api_home`）：天气走缓存优先（过期才联网，失败降级旧数据），
/// 备忘录速览最多 3 条、清单项能直接勾（只翻转单条，不整段回写），
/// 点笔记跳到备忘录页。
library;

import 'package:flutter/material.dart';

import '../home_logic.dart';
import '../models.dart';
import '../store.dart';
import '../weather_api.dart';
import '../weather_logic.dart';
import '../week.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    this.api,
    this.onOpenNote,
  });

  final Store store;

  /// 测试时注入假接口；不传就用真的 Open-Meteo。
  final WeatherApi? api;

  /// 点了一条备忘录速览（跳到备忘录页并打开那条）。
  final void Function(String noteId)? onOpenNote;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final WeatherApi _api = widget.api ?? WeatherApi();

  bool _wxStale = false;
  String? _wxError;
  Map<String, dynamic>? _payload;
  String? _fetchedAt;
  int _gen = 0;

  /// 每条速览的收放状态，默认展开（和电脑版 homeNoteOpen 一致）。
  final Map<String, bool> _noteOpen = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  /// 取天气：缓存没过期就直接用；否则联网，失败降级旧缓存（对齐 weather_result(force=False)）。
  Future<void> _loadWeather() async {
    final gen = ++_gen;
    final settings = widget.store.settings();
    final city = settings.weatherCity;
    if (!city.isSet) {
      if (gen == _gen && mounted) {
        setState(() {
          _payload = null;
          _fetchedAt = null;
          _wxStale = false;
          _wxError = null;
        });
      }
      return;
    }
    setState(() {});

    final cache = widget.store.weatherCache();
    final fresh = weatherCacheFresh(
      city: city,
      cache: cache,
      refreshMinutes: settings.refreshMinutes,
      now: DateTime.now(),
    );
    if (fresh) {
      if (gen == _gen && mounted) {
        setState(() {
          _payload = cache.payload;
          _fetchedAt = cache.fetchedAt;
          _wxStale = false;
          _wxError = null;
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
          _wxStale = false;
          _wxError = null;
        });
      }
    } on WeatherApiException catch (e) {
      final fb = staleFallback(city: city, cache: cache);
      if (gen == _gen && mounted) {
        setState(() {
          if (fb != null && fb.payload != null) {
            _payload = fb.payload;
            _fetchedAt = fb.fetchedAt;
            _wxStale = true;
          } else {
            _payload = null;
            _fetchedAt = null;
            _wxStale = false;
          }
          _wxError = e.message;
        });
      }
    }
  }

  // ---------- 渲染小工具 ----------

  String _greet(Settings s) =>
      '${greetingOf(DateTime.now())}${s.displayName.isEmpty ? '' : '，${s.displayName}'}';

  String _numText(dynamic v, [String suffix = '']) =>
      (v == null || v == '') ? '—' : '$v$suffix';

  Widget _card({required String cardKey, required String title, required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey<String>(cardKey),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary)),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }

  Widget _emptyLine(String key, String title, String hint) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey<String>(key),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(hint, style: TextStyle(fontSize: 12, color: cs.outline)),
      ]),
    );
  }

  // ---------- 今日课程 ----------

  Widget _lessonsCard(Settings s, int? week) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final lessons = week == null
        ? const <Lesson>[]
        : widget.store.courses().week(week).where((l) => l.day == now.weekday).toList();
    final states = computeLessonStates(lessons, s.periods, nowMin);

    Widget body;
    if (s.periods.isEmpty) {
      body = _emptyLine('home-empty-periods', '还没有任何节次',
          '先到「设置」里添加自己的节次和时间，再回来排课');
    } else if (week == null) {
      body = _emptyLine('home-empty-week', '还不知道今天是第几周',
          '去设置里填一下第 1 周周一的日期');
    } else if (states.isEmpty) {
      body = _emptyLine('home-empty-lessons', '今天没课', '休息一下');
    } else {
      body = Column(
        children: <Widget>[
          for (var i = 0; i < states.length; i++) _lessonRow(states[i], i, cs),
        ],
      );
    }
    return _card(cardKey: 'home-card-lessons', title: '今日课程', child: body);
  }

  Widget _lessonRow(LessonState item, int i, ColorScheme cs) {
    final done = item.status == 'done';
    final unknown = item.status == 'unknown';
    return Padding(
      key: ValueKey<String>('home-lesson-$i'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            '${item.periodLabel.isEmpty ? '' : '${item.periodLabel}\n'}${item.periodRange}',
            style: TextStyle(
              fontSize: 12,
              color: done ? cs.outline : cs.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Flexible(
                child: Text(
                  item.lesson.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: done ? cs.outline : cs.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (item.status == 'now') ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  key: const ValueKey('home-badge-now'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('正在上', style: TextStyle(fontSize: 11, color: Colors.white)),
                ),
              ],
              if (item.next) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  key: ValueKey('home-badge-next-${item.lesson.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('下一节',
                      style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
                ),
              ],
              if (unknown) ...<Widget>[
                const SizedBox(width: 6),
                Text('时间未设置',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ],
            ]),
            const SizedBox(height: 2),
            Text(
              <String>[item.lesson.location, item.lesson.teacher]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ]),
        ),
      ]),
    );
  }

  // ---------- 今日天气 ----------

  Widget _weatherCard() {
    final settings = widget.store.settings();
    final city = settings.weatherCity;
    Widget body;
    if (!city.isSet) {
      body = _emptyLine('home-wx-no-city', '还没选城市', '到天气页或设置里选一个，就能看到实况和预报');
    } else if (_payload == null && _wxError != null) {
      body = _emptyLine('home-wx-error', '暂时取不到天气', '其他地方照常能用，过会儿再试');
    } else if (_payload == null) {
      body = const Center(
        key: ValueKey('home-wx-loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else {
      body = _weatherBody();
    }
    return _card(cardKey: 'home-card-wx', title: '今日天气', child: body);
  }

  Widget _weatherBody() {
    final cs = Theme.of(context).colorScheme;
    final cur = asMap(_payload!['current']);
    final cityName = asString(asMap(_payload!['city'])['name']);
    final daily = _payload!['daily'] is List ? _payload!['daily'] as List : const <dynamic>[];
    final today = daily.isNotEmpty ? asMap(daily[0]) : const <String, dynamic>{};
    final temp = asDoubleOrNull(cur['temp']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
        Text(
          temp == null ? '--°' : '${_fmtNum(temp)}°',
          key: const ValueKey('home-wx-temp'),
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300, height: 1.1),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('${asString(cur['text'])}${cityName.isEmpty ? '' : ' · $cityName'}',
              style: TextStyle(fontSize: 13, color: cs.outline)),
        ),
      ]),
      if (_wxStale)
        Padding(
          key: const ValueKey('home-wx-stale'),
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '网络不可用，显示的是 ${(_fetchedAt ?? '').length >= 16 ? (_fetchedAt ?? '').substring(5, 16) : (_fetchedAt ?? '')} 的数据',
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ),
      const SizedBox(height: 6),
      _kv('体感', _numText(cur['feels'], '°')),
      _kv('湿度', _numText(cur['humidity'], '%')),
      _kv('风', '${asString(cur['windDir'])} ${_numText(cur['wind'], ' m/s')}'),
      _kv('最低 / 最高', '${_numText(today['min'], '°')} / ${_numText(today['max'], '°')}'),
    ]);
  }

  String _fmtNum(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  Widget _kv(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: <Widget>[
        Text(label, style: TextStyle(fontSize: 12, color: cs.outline)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  // ---------- 备忘录速览 ----------

  Widget _notesCard() {
    final cs = Theme.of(context).colorScheme;
    final preview = previewNotes(widget.store.sortedNotes().toList());

    Widget body;
    if (preview.isEmpty) {
      body = _emptyLine('home-notes-empty', '还没有备忘录', '想到什么随手记一条');
    } else {
      body = Column(
        children: <Widget>[
          for (final n in preview) _noteRow(n, cs),
        ],
      );
    }
    return _card(cardKey: 'home-card-notes', title: '备忘录速览', child: body);
  }

  Widget _noteRow(HomeNotePreview n, ColorScheme cs) {
    final open = _noteOpen[n.id] != false;
    final tags = n.tags.where((t) => t.isNotEmpty).toList();
    return Container(
      key: ValueKey<String>('home-note-${n.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpenNote?.call(n.id),
          child: Row(children: <Widget>[
            if (n.pinned)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('置顶',
                      style: TextStyle(fontSize: 10, color: cs.onPrimaryContainer)),
                ),
              ),
            Expanded(
              child: Text(
                n.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            // 小三角收放：点它不触发整条跳转
            GestureDetector(
              key: ValueKey<String>('home-caret-${n.id}'),
              onTap: () => setState(() => _noteOpen[n.id] = !open),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: cs.outline,
                ),
              ),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                n.summary.isEmpty ? '空' : n.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
          ]),
        ),
        Row(children: <Widget>[
          Flexible(
            child: Text(
              tags.isEmpty ? NoteType.label(n.type) : tags.join('、'),
              style: TextStyle(fontSize: 11, color: cs.primary),
            ),
          ),
        ]),
        if (open) ...<Widget>[
          if (n.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${n.body}${n.bodyCut ? '…' : ''}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          if (n.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(children: <Widget>[
                for (var ix = 0; ix < n.items.length; ix++) _todoRow(n, ix, cs),
                if (n.moreItems > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 21, top: 2),
                    child: Text('… 还有 ${n.moreItems} 项',
                        style: TextStyle(fontSize: 11, color: cs.outline)),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _todoRow(HomeNotePreview n, int ix, ColorScheme cs) {
    final item = n.items[ix];
    final text = item.text.isEmpty ? '（没写内容）' : item.text;
    return InkWell(
      key: ValueKey<String>('home-item-${n.id}-$ix'),
      onTap: () => _toggleItem(n.id, ix),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: <Widget>[
          Icon(
            item.done ? Icons.check_box : Icons.check_box_outline_blank,
            size: 17,
            color: item.done ? cs.primary : cs.outline,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: item.done ? cs.outline : cs.onSurface,
                decoration: item.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// 勾掉一项：只翻转这一条，立刻落盘（绝不整段回写 items）。
  void _toggleItem(String noteId, int ix) {
    final notes = widget.store.notes();
    final saved = toggleNoteItem(notes, noteId, ix, nowIso: Store.nowIso);
    if (saved == null) return;
    widget.store.saveNotes(notes);
    setState(() {});
  }

  // ---------- 整页 ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.store.settings();
    final now = DateTime.now();
    final week = weekOf(now, s.week1Monday);
    final todayIso = isoOf(now);

    final bits = <String>[
      '$todayIso ${weekdayCn(now.weekday)}',
      week == null ? '教学周未设置' : '第 $week 教学周',
      if (s.campus.isNotEmpty) s.campus,
      if (s.semesterName.isNotEmpty) s.semesterName,
    ];

    return ListView(
      key: const ValueKey('page-home'),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
      children: <Widget>[
        Padding(
          key: const ValueKey('home-greet'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Text(_greet(s),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        Padding(
          key: const ValueKey('home-date'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(bits.join(' · '),
              style: TextStyle(fontSize: 12, color: cs.outline)),
        ),
        Padding(
          key: const ValueKey('home-tags'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: week == null
                    ? cs.surfaceContainerHighest
                    : cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                week == null ? '未设置教学周' : '第 $week 周',
                style: TextStyle(
                    fontSize: 11,
                    color: week == null ? cs.outline : cs.onPrimaryContainer),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              key: const ValueKey('home-count'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '今日 ${_todayCount(s, week)} 节课',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
          ]),
        ),
        _lessonsCard(s, week),
        _weatherCard(),
        _notesCard(),
      ],
    );
  }

  int _todayCount(Settings s, int? week) {
    if (week == null) return 0;
    final lessons = widget.store
        .courses()
        .week(week)
        .where((l) => l.day == DateTime.now().weekday)
        .length;
    return lessons;
  }
}
