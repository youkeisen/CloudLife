/// 首页（v2.0 重排）。
///
/// 改动动机：原来「首页」大标题和问候语语义重复，白占 90px；最重要的
/// 「正在上课」被埋在列表第三行、只用一个小蓝胶囊表示。
///
/// 现在的顺序：页头（日期 + 问候语 + 周次胶囊）→ 三栏状态条 →
/// 正在上课主卡（唯一的高饱和强调卡）→ 天气/备忘双列小卡 →
/// 今日课程时间轴 → 备忘录速览。
///
/// 行为仍对齐电脑版 `api_home`：天气缓存优先、失败降级旧数据；
/// 备忘录速览最多 3 条、清单项能直接勾（只翻转单条，不整段回写）。
library;

import 'package:flutter/material.dart';

import '../home_logic.dart';
import '../models.dart';
import '../store.dart';
import '../weather_api.dart';
import '../weather_logic.dart';
import '../week.dart';
import 'design.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    this.api,
    this.onOpenNote,
    this.onOpenWeather,
    this.onOpenNotes,
    this.onOpenCourses,
  });

  final Store store;

  /// 测试时注入假接口；不传就用真的 Open-Meteo。
  final WeatherApi? api;

  /// 点了一条备忘录（跳到备忘录并打开那条）。
  final void Function(String noteId)? onOpenNote;

  /// 小卡片的跳转入口（由壳子给）。
  final VoidCallback? onOpenWeather;
  final VoidCallback? onOpenNotes;
  final VoidCallback? onOpenCourses;

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

  /// 每条速览的收放状态。**默认收起**；表里只记「手动展开过的那几条」。
  final Map<String, bool> _noteOpen = <String, bool>{};

  @override
  void initState() {
    super.initState();
    // 首页的内容是 build 时实时读的，但要有人叫它重建才会重读 ——
    // 从首页点开一条备忘录、在编辑页删掉、返回，首页 State 一直活着。
    widget.store.addListener(_onStoreChanged);
    _loadWeather();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// 取天气：缓存没过期就直接用；否则联网，失败降级旧缓存。
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

  // ---------- 小工具 ----------

  String _greet(Settings s) =>
      '${greetingOf(DateTime.now())}${s.displayName.isEmpty ? '' : '，${s.displayName}'}';

  /// 分钟数 → `HH:MM`（跨零点折回当天）。
  String _hhmm(int m) {
    final x = m % 1440;
    return '${(x ~/ 60).toString().padLeft(2, '0')}:'
        '${(x % 60).toString().padLeft(2, '0')}';
  }

  /// 第一个满足条件的（没有就是 null）。不引 collection 包，自己写一个。
  T? _firstOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final x in items) {
      if (test(x)) return x;
    }
    return null;
  }

  /// 今天要上的课（按时间排序后的状态列表）。
  List<LessonState> _todayStates(Settings s, int? week) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final lessons = week == null
        ? const <Lesson>[]
        : widget.store.courses().week(week).where((l) => l.day == now.weekday).toList();
    return computeLessonStates(lessons, s.periods, nowMin);
  }

  // ---------- 页头 ----------

  Widget _header(Settings s, int? week, String dateLine) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s1, Sp.gutter, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  key: const ValueKey('home-date'),
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(dateLine, style: context.xs),
                ),
                Text(
                  _greet(s),
                  key: const ValueKey('home-greet'),
                  style: context.h1,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: week == null
                ? const WeekChip(
                    key: ValueKey('week-pill-off'),
                    text: '教学周未设置',
                    strong: false,
                  )
                : WeekChip(key: const ValueKey('week-pill'), text: '第 $week 教学周'),
          ),
        ],
      ),
    );
  }

  /// 三栏状态条：本周 / 今日课程 / 下一节。
  Widget _statStrip(List<LessonState> states, int? week) {
    final tone = Tone.of(context);
    final next = _firstOrNull(states, (x) => x.next);
    final nextText = next?.begin == null ? '—' : _hhmm(next!.begin!);

    Widget item(String k, String v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(k, style: Type.xs.copyWith(color: tone.ink400)),
              const SizedBox(height: 3),
              Text(
                v,
                style: Type.num(Type.body).copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tone.ink900,
                ),
              ),
            ],
          ),
        );

    Widget div() => Container(width: 1, height: 22, color: tone.ink200);

    return Container(
      margin: const EdgeInsets.only(top: Sp.s4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tone.ink200),
          bottom: BorderSide(color: tone.ink200),
        ),
      ),
      child: Row(
        children: <Widget>[
          item('本周', week == null ? '未设置' : '第 $week 周'),
          div(),
          item('今日课程', '${states.length} 节'),
          div(),
          item('下一节', nextText),
        ],
      ),
    );
  }

  // ---------- 正在上课（唯一强调卡） ----------

  /// 正在上课的主卡：唯一的高饱和强调卡，进场时淡入上移一次。
  Widget _liveCard(LessonState item, int nowMin) =>
      RiseIn(child: _liveCardBody(item, nowMin));

  Widget _liveCardBody(LessonState item, int nowMin) {
    const c1 = Color(0xFF2B54C8);
    const c2 = Color(0xFF1F3F9E);
    const c3 = Color(0xFF172F76);
    const liveGreen = Color(0xFF6FF0B0);

    final begin = item.begin;
    final finish = item.finish;
    double? progress;
    int? left;
    if (begin != null && finish != null && finish > begin) {
      progress = ((nowMin - begin) / (finish - begin)).clamp(0.0, 1.0);
      left = (finish - nowMin).clamp(0, 24 * 60);
    }

    final meta = <String>[
      if (item.periodLabel.isNotEmpty) item.periodLabel,
      if (item.lesson.location.isNotEmpty) item.lesson.location,
      if (item.lesson.teacher.isNotEmpty) item.lesson.teacher,
    ];

    return Padding(
      key: const ValueKey('home-live-card'),
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s3 + 2, Sp.gutter, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.7, -1),
              end: Alignment(0.7, 1),
              colors: <Color>[c1, c2, c3],
              stops: <double>[0, .58, 1],
            ),
          ),
          child: Stack(
            children: <Widget>[
              // 右上角的柔光（原型里的 live-glow）
              Positioned(
                right: -80,
                top: -110,
                child: IgnorePointer(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: <Color>[Color(0x47FFFFFF), Color(0x00FFFFFF)],
                        stops: <double>[0, .68],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding:
                              const EdgeInsets.fromLTRB(8, 4, 10, 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: liveGreen,
                                  shape: BoxShape.circle,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: liveGreen.withValues(alpha: .55),
                                      blurRadius: 0,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '正在上课',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: .22,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (left != null)
                          Text(
                            '剩余 $left 分钟',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: .82),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.lesson.name.isEmpty ? '（没写课名）' : item.lesson.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: Colors.white,
                        letterSpacing: -0.19,
                      ),
                    ),
                    if (meta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              meta.join('  ·  '),
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: Colors.white.withValues(alpha: .88),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (progress != null) ...<Widget>[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: .22),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF8FE9C0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: <Widget>[
                          Text(
                            begin == null ? '' : _hhmm(begin),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: .75),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            finish == null ? '' : _hhmm(finish),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: .75),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 双列小卡 ----------

  Widget _miniCard({
    required Key cardKey,
    required IconData icon,
    required Color iconColor,
    required String label,
    String? badge,
    required Widget value,
    required String sub,
    Widget? extra,
    VoidCallback? onTap,
  }) {
    final tone = Tone.of(context);
    return Card2(
      key: cardKey,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: Type.xs.copyWith(
                  color: tone.ink400,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (badge != null) ...<Widget>[
                const Spacer(),
                Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: tone.primary,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Center(
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // 值这一块撑开：两张卡的「说明行」贴同一条水平线，看起来才对称
          Expanded(child: Align(alignment: Alignment.topLeft, child: value)),
          const SizedBox(height: 2),
          Text(sub, style: Type.xs.copyWith(color: tone.ink400)),
          ?extra,
        ],
      ),
    );
  }

  Widget _miniWeather() {
    final tone = Tone.of(context);
    final settings = widget.store.settings();
    final city = settings.weatherCity;

    Widget value;
    String sub;
    if (!city.isSet) {
      value = Text('还没选城市', style: Type.body.copyWith(color: tone.ink500));
      sub = '到天气页选一个';
    } else if (_payload == null && _wxError != null) {
      value = Text('暂时取不到天气', style: Type.body.copyWith(color: tone.ink500));
      sub = '过会儿再试';
    } else if (_payload == null) {
      value = const SizedBox(
        key: ValueKey('home-wx-loading'),
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      sub = '正在取数据…';
    } else {
      final cur = asMap(_payload!['current']);
      final cityName = asString(asMap(_payload!['city'])['name']);
      final temp = asDoubleOrNull(cur['temp']);
      final daily =
          _payload!['daily'] is List ? _payload!['daily'] as List : const <dynamic>[];
      final today = daily.isNotEmpty ? asMap(daily[0]) : const <String, dynamic>{};
      final minT = asDoubleOrNull(today['min']);
      final maxT = asDoubleOrNull(today['max']);

      value = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            temp == null ? '--°' : '${_fmtNum(temp)}°',
            key: const ValueKey('home-wx-temp'),
            style: Type.num(Type.h3).copyWith(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              color: tone.ink900,
              letterSpacing: -0.8,
            ),
          ),
          // 今天最低 / 最高（v2.1.1 凯森要求加回来）
          if (minT != null && maxT != null)
            Padding(
              key: const ValueKey('home-wx-range'),
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${_fmtNum(minT)}° / ${_fmtNum(maxT)}°',
                style: Type.num(Type.sm).copyWith(color: tone.ink400),
              ),
            ),
        ],
      );
      // 小卡只留「天气 · 城市」（湿度在天气页看；v2.1.1 凯森要求去掉）
      sub = <String>[
        asString(cur['text']),
        cityName,
      ].where((x) => x.isNotEmpty).join(' · ');
    }

    // 「网络不可用，显示的是旧数据」这行放进卡里：不然有它没它，两张卡不一样高
    return _miniCard(
      cardKey: const ValueKey('home-card-wx'),
      icon: Icons.wb_sunny_outlined,
      iconColor: tone.accent,
      label: '天气',
      value: value,
      sub: sub,
      extra: _wxStale
          ? Padding(
              key: const ValueKey('home-wx-stale'),
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '网络不可用，显示的是 ${(_fetchedAt ?? '').length >= 16 ? (_fetchedAt ?? '').substring(5, 16) : (_fetchedAt ?? '')} 的数据',
                style: Type.xs.copyWith(color: tone.ink300),
              ),
            )
          : null,
      onTap: widget.onOpenWeather,
    );
  }

  String _fmtNum(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  Widget _miniMemo() {
    final tone = Tone.of(context);
    final preview = previewNotes(widget.store.sortedNotes().toList());
    final total = widget.store.notes().notes.where((n) => !n.archived).length;

    if (preview.isEmpty) {
      return _miniCard(
        cardKey: const ValueKey('home-card-notes-mini'),
        icon: Icons.edit_note_outlined,
        iconColor: tone.primary,
        label: '备忘',
        value: Text('还没有备忘录', style: Type.body.copyWith(color: tone.ink500)),
        sub: '想到什么随手记一条',
        onTap: widget.onOpenNotes,
      );
    }
    final n = preview.first;
    final pinned = widget.store.notes().notes
        .where((x) => x.pinned && !x.archived)
        .length;
    return _miniCard(
      cardKey: const ValueKey('home-card-notes-mini'),
      icon: Icons.edit_note_outlined,
      iconColor: tone.primary,
      label: '备忘',
      badge: total > 0 ? '$total' : null,
      // 这里只给关键数字；标题和内容在下面的「备忘录速览」里，别重复一遍
      value: Text(
        '$total 条',
        style: Type.num(Type.h3).copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: tone.ink900,
          letterSpacing: -0.19,
        ),
      ),
      sub: pinned > 0 ? '含 $pinned 条置顶' : '笔记与清单',
      onTap: () => widget.onOpenNote?.call(n.id),
    );
  }

  // ---------- 今日课程（时间轴） ----------

  Widget _lessonsSection(Settings s, int? week, List<LessonState> states) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    Widget body;
    if (s.periods.isEmpty) {
      body = const EmptyHint(
        key: ValueKey('home-empty-periods'),
        title: '还没有任何节次',
        hint: '先到「设置 → 作息与节次」添加自己的节次和时间，再回来排课',
        icon: Icons.schedule_outlined,
      );
    } else if (week == null) {
      body = const EmptyHint(
        key: ValueKey('home-empty-week'),
        title: '还不知道今天是第几周',
        hint: '去设置里填一下第 1 周周一的日期',
        icon: Icons.event_busy_outlined,
      );
    } else if (states.isEmpty) {
      body = const EmptyHint(
        key: ValueKey('home-empty-lessons'),
        title: '今天没课',
        hint: '休息一下',
        icon: Icons.free_breakfast_outlined,
      );
    } else {
      body = Column(
        children: <Widget>[
          for (var i = 0; i < states.length; i++)
            _timelineItem(states[i], i, nowMin, i == states.length - 1),
        ],
      );
    }

    return Padding(
      key: const ValueKey('home-card-lessons'),
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s5, Sp.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHead(
            title: '今日课程',
            trailing: widget.onOpenCourses == null ? null : '全部 ›',
            onTapTrailing: widget.onOpenCourses,
          ),
          body,
        ],
      ),
    );
  }

  /// 时间轴的一项：左侧时间 + 中轴节点 + 正文 + 状态标签。
  ///
  /// 用 [IntrinsicHeight] 是为了让中轴的竖线上下贯通（行高由内容撑开）。
  Widget _timelineItem(LessonState item, int i, int nowMin, bool isLast) {
    final tone = Tone.of(context);
    final done = item.status == 'done';
    final live = item.status == 'now';
    final unknown = item.status == 'unknown';

    final titleColor = done ? tone.ink400 : tone.ink900;
    final timeColor = live ? tone.primary : (done ? tone.ink400 : tone.ink700);

    final Widget? tag = live
        ? Pill(text: '进行中', bg: tone.primarySoft, fg: tone.primary)
        : done
            ? const Pill(text: '已结束')
            : unknown
                ? Pill(text: '时间未设置', bg: tone.accentSoft, fg: tone.accent)
                : null;

    final meta = <String>[
      if (item.periodLabel.isNotEmpty) item.periodLabel,
      if (item.lesson.location.isNotEmpty) item.lesson.location,
      if (item.lesson.teacher.isNotEmpty) item.lesson.teacher,
    ];

    return Stack(
      key: ValueKey<String>('home-lesson-$i'),
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(left: live ? 9 : 0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 52,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18, top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.begin == null ? '—' : _hhmm(item.begin!),
                          style: Type.num(Type.sm).copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: timeColor,
                          ),
                        ),
                        Text(
                          item.finish == null ? '' : _hhmm(item.finish!),
                          style: Type.xs.copyWith(fontSize: 11, color: tone.ink300),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 中轴：一条竖线 + 一个节点（最后一项不再往下画线）
                SizedBox(
                  width: 20,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      if (!isLast)
                        Positioned(
                          top: 14,
                          bottom: 0,
                          left: 9.25,
                          child: Container(width: 1.5, color: tone.ink200),
                        ),
                      Positioned(
                        top: 5,
                        left: 5.5,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: live ? tone.primary : tone.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: live ? tone.primary : tone.ink300,
                              width: 2,
                            ),
                            boxShadow: live
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: tone.primarySoft,
                                      blurRadius: 0,
                                      spreadRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.lesson.name.isEmpty ? '（没写课名）' : item.lesson.name,
                          style: Type.body.copyWith(
                            fontWeight: done ? FontWeight.w500 : FontWeight.w600,
                            color: titleColor,
                            height: 1.3,
                          ),
                        ),
                        if (meta.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              meta.join(' · '),
                              style: Type.sm.copyWith(
                                color: done ? tone.ink300 : tone.ink400,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (tag != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 18),
                    child: tag,
                  ),
              ],
            ),
          ),
        ),
        if (live)
          Positioned(
            left: 0,
            top: 4,
            bottom: 18,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: tone.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }

  // ---------- 备忘录速览 ----------

  Widget _notesSection() {
    final tone = Tone.of(context);
    final preview = previewNotes(widget.store.sortedNotes().toList());
    // 一条都没有时首页不再重复一遍空态（上面的「备忘」小卡已经说了）。
    if (preview.isEmpty) return const SizedBox.shrink();

    return Padding(
      key: const ValueKey('home-card-notes'),
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s5, Sp.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHead(
            title: '备忘录速览',
            trailing: widget.onOpenNotes == null ? null : '全部 ›',
            onTapTrailing: widget.onOpenNotes,
          ),
          Card2(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                for (var i = 0; i < preview.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, indent: 14, color: tone.ink100),
                  _noteRow(preview[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteRow(HomeNotePreview n) {
    final tone = Tone.of(context);
    final open = _noteOpen[n.id] == true;
    return Padding(
      key: ValueKey<String>('home-note-${n.id}'),
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onOpenNote?.call(n.id),
            child: Row(
              children: <Widget>[
                if (n.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.star, size: 15, color: tone.primary),
                  ),
                Expanded(
                  child: Text(
                    n.title.isEmpty ? '无标题' : n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tone.ink900,
                    ),
                  ),
                ),
                // 小三角收放：点它不触发整条跳转
                GestureDetector(
                  key: ValueKey<String>('home-caret-${n.id}'),
                  onTap: () => setState(() => _noteOpen[n.id] = !open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: tone.ink300,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            <String>[
              NoteType.label(n.type),
              if (n.summary.isNotEmpty) n.summary,
              if (n.pinned) '置顶',
            ].join(' · '),
            style: Type.xs.copyWith(color: tone.ink400),
          ),
          if (open) ...<Widget>[
            if (n.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: Text(
                  '${n.body}${n.bodyCut ? '…' : ''}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body.copyWith(color: tone.ink700),
                ),
              ),
            if (n.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  children: <Widget>[
                    for (var ix = 0; ix < n.items.length; ix++) _todoRow(n, ix),
                    if (n.moreItems > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 23, top: 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('… 还有 ${n.moreItems} 项',
                              style: Type.xs.copyWith(color: tone.ink300)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _todoRow(HomeNotePreview n, int ix) {
    final tone = Tone.of(context);
    final item = n.items[ix];
    final text = item.text.isEmpty ? '（没写内容）' : item.text;
    return InkWell(
      key: ValueKey<String>('home-item-${n.id}-$ix'),
      onTap: () => _toggleItem(n.id, ix),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(
              item.done ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: item.done ? tone.primary : tone.ink300,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: Type.sm.copyWith(
                  color: item.done ? tone.ink300 : tone.ink700,
                ),
              ),
            ),
          ],
        ),
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
    final s = widget.store.settings();
    final now = DateTime.now();
    final week = weekOf(now, s.week1Monday);
    final states = _todayStates(s, week);
    final live = _firstOrNull(states, (x) => x.status == 'now');
    final nowMin = now.hour * 60 + now.minute;

    final dateLine = <String>[
      '${isoOf(now)} ${weekdayCn(now.weekday)}',
      if (s.campus.isNotEmpty) s.campus,
      if (s.semesterName.isNotEmpty) s.semesterName,
    ].join(' · ');

    return ListView(
      key: const ValueKey('page-home'),
      padding: const EdgeInsets.only(bottom: Sp.bottomInset),
      children: <Widget>[
        _header(s, week, dateLine),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.gutter),
          child: _statStrip(states, week),
        ),
        if (live != null) _liveCard(live, nowMin),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s3 + 2, Sp.gutter, 0),
          // 两张小卡等高对称：内容少的那张撑到和另一张一样高
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _miniWeather()),
                const SizedBox(width: Sp.s3),
                Expanded(child: _miniMemo()),
              ],
            ),
          ),
        ),
        _lessonsSection(s, week, states),
        _notesSection(),
      ],
    );
  }
}
