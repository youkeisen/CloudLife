// 首页的测试：三个区块（今日课程 / 今日天气 / 备忘录速览）的空态与内容、
// 天气的缓存与降级、清单勾选落盘、收放与跳转。数据全部虚构，网络用假接口。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/weather_api.dart';
import 'package:my_day_phone/weather_logic.dart';
import 'package:my_day_phone/ui/home_page.dart';

/// 假接口：不联网，返回固定数据；fail=true 时模拟网络挂了。
class FakeApi extends WeatherApi {
  FakeApi({this.fail = false, this.temp = 24.5});

  bool fail;
  double temp;
  int forecastCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchWeather(num lat, num lon) async {
    forecastCalls++;
    if (fail) throw WeatherApiException('网络断了');
    return rawFixture(temp: temp);
  }
}

/// 造一段 Open-Meteo 风格的原始返回（时间跨度够宽，真实 now 也能落在窗口里）。
Map<String, dynamic> rawFixture({required double temp}) {
  String p2(int n) => n < 10 ? '0$n' : '$n';
  final now = DateTime.now();
  final times = <String>[];
  final temps = <double>[];
  final pops = <int>[];
  for (var i = 0; i < 72; i++) {
    final d = DateTime(now.year, now.month, now.day - 1, i);
    times.add('${d.year}-${p2(d.month)}-${p2(d.day)}T${p2(d.hour)}:00');
    temps.add(temp);
    pops.add(20);
  }
  final days = <String>[];
  for (var i = 0; i < 3; i++) {
    final d = DateTime(now.year, now.month, now.day + i);
    days.add('${d.year}-${p2(d.month)}-${p2(d.day)}');
  }
  return <String, dynamic>{
    'current': <String, dynamic>{
      'temperature_2m': temp,
      'apparent_temperature': temp + 1,
      'relative_humidity_2m': 60,
      'is_day': 1,
      'weather_code': 0,
      'wind_speed_10m': 3.0,
      'wind_direction_10m': 45,
      'surface_pressure': 1010.0,
    },
    'hourly': <String, dynamic>{
      'time': times,
      'temperature_2m': temps,
      'precipitation_probability': pops,
      'visibility': <double>[for (var i = 0; i < 72; i++) 9000.0],
    },
    'daily': <String, dynamic>{
      'time': days,
      'weather_code': <int>[0, 1, 2],
      'temperature_2m_max': <double>[temp + 1, temp + 1, temp + 1],
      'temperature_2m_min': <double>[temp - 1, temp - 1, temp - 1],
      'precipitation_probability_max': <int>[20, 20, 20],
      'uv_index_max': <double>[3.0, 3.0, 3.0],
    },
  };
}

void main() {
  late Directory tmp;
  late Store store;
  late FakeApi api;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-home-test-');
    store = Store(tmp)..init();
    api = FakeApi();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester,
      {WeatherApi? customApi, void Function(String)? onOpenNote}) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomePage(
          store: store,
          api: customApi ?? api,
          onOpenNote: onOpenNote,
        ),
      ),
    ));
    await tester.pump(); // initState 里发起的 _load
    await tester.pump(const Duration(milliseconds: 50)); // 等假接口的微任务落定
  }

  void setCity(String name) {
    final s = store.settings()
      ..weatherCity = City(name: name, latitude: 30.1, longitude: 118.2);
    store.saveSettings(s);
  }

  testWidgets('空数据：问候、日期行、计数和三个空态都在，天气不联网', (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('page-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-greet')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-date')), findsOneWidget);
    // v2.0：首页页头是三栏状态条（本周 / 今日课程 / 下一节），值和标签分开显示
    expect(find.text('教学周未设置'), findsOneWidget);
    expect(find.text('0 节'), findsOneWidget);
    expect(find.text('还没有任何节次'), findsOneWidget);
    expect(find.text('还没选城市'), findsOneWidget);
    expect(find.text('还没有备忘录'), findsOneWidget);
    expect(api.forecastCalls, 0, reason: '没选城市时不该发请求');
  });

  testWidgets('今日课程：有课渲染课行，未来的课带「下一节」', (tester) async {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    String p2(int n) => n < 10 ? '0$n' : '$n';
    final s = store.settings()
      ..week1Monday =
          '${monday.year}-${p2(monday.month)}-${p2(monday.day)}';
    // 时间相对当前钟点构造，保证任何时刻跑都是「一节已上完、一节还没到」；
    // 越过 0 点 / 24 点时夹回当天边界（极限边界各只有一两分钟）。
    final nowMin = now.hour * 60 + now.minute;
    var upBegin = nowMin + 60;
    var upEnd = nowMin + 120;
    if (upBegin > 1439) {
      upBegin = 1439;
      upEnd = 1439;
    }
    var dnBegin = nowMin - 120;
    var dnEnd = nowMin - 60;
    if (dnBegin < 0) {
      dnBegin = 0;
      dnEnd = 0;
    }
    s.periods = <Period>[
      Period(id: 'p1', label: '第1节', start: _hhmmOfMinute(dnBegin), end: _hhmmOfMinute(dnEnd)),
      Period(id: 'p2', label: '第2节', start: _hhmmOfMinute(upBegin), end: _hhmmOfMinute(upEnd)),
    ];
    store.saveSettings(s);
    final courses = store.courses()
      ..setWeek(1, <Lesson>[
        Lesson(id: 'l1', day: now.weekday, slot: 'p1', name: '示例课一', location: '示例楼101', teacher: '张老师'),
        Lesson(id: 'l2', day: now.weekday, slot: 'p2', name: '示例课二', location: '示例楼202'),
      ]);
    store.saveCourses(courses);

    await pumpHome(tester);
    expect(find.text('2 节'), findsOneWidget);
    expect(find.text('示例课一'), findsOneWidget);
    expect(find.text('示例课二'), findsOneWidget);
    // 「下一节」现在是状态条里那一栏（原来挂在课行的小胶囊上）
    expect(find.text('下一节'), findsOneWidget);
    // v2.0：课行改成时间轴，副标题是「节次 · 地点 · 老师」拼起来的
    expect(find.textContaining('示例楼101 · 张老师'), findsOneWidget);
    expect(find.textContaining('示例楼202'), findsOneWidget);
  });

  testWidgets('设了节次但没设教学周 → 「还不知道今天是第几周」', (tester) async {
    final s = store.settings()
      ..periods = <Period>[Period(id: 'p1', label: '第1节', start: '08:00', end: '08:45')];
    store.saveSettings(s);
    await pumpHome(tester);
    expect(find.text('还不知道今天是第几周'), findsOneWidget);
  });

  testWidgets('天气：假接口成功 → 显示温度并写缓存', (tester) async {
    setCity('示例市');
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('home-wx-temp')), findsOneWidget);
    expect(find.text('24.5°'), findsOneWidget);
    // v2.1.1：大温度下面带一行今天的最低 / 最高
    expect(find.byKey(const ValueKey('home-wx-range')), findsOneWidget);
    expect(find.textContaining('° / '), findsOneWidget);
    // v2.0：天气变成双列小卡，副标题拼「天气 · 城市 · 湿度」
    expect(find.textContaining('晴 · 示例市'), findsOneWidget);
    expect(api.forecastCalls, 1);
    expect(store.weatherCache().payload, isNotNull, reason: '取回来的要写进缓存');
    expect(find.byKey(const ValueKey('home-wx-stale')), findsNothing);
  });

  testWidgets('天气：缓存新鲜就不联网', (tester) async {
    setCity('示例市');
    store.setWeatherCache(City(name: '示例市', latitude: 30.1, longitude: 118.2),
        normalize(rawFixture(temp: 21.0), City(name: '示例市', latitude: 30.1, longitude: 118.2)));
    await pumpHome(tester);
    expect(find.text('21°'), findsOneWidget);
    expect(find.textContaining('晴 · 示例市'), findsOneWidget);
    expect(api.forecastCalls, 0);
  });

  testWidgets('天气：失败且没缓存 → 空态文案', (tester) async {
    setCity('示例市');
    await pumpHome(tester, customApi: FakeApi(fail: true));
    expect(find.text('暂时取不到天气'), findsOneWidget);
  });

  testWidgets('v1.6.0 第 6 条：天气卡片里没有「体感」和「风」', (tester) async {
    setCity('示例市');
    await pumpHome(tester);
    // v2.1.1：湿度也从小卡里拿掉了（要看去天气页），小卡只留天气和城市
    expect(find.textContaining('湿度'), findsNothing);
    // 体感、风按凯森要求去掉
    expect(find.text('体感'), findsNothing);
    expect(find.text('风'), findsNothing);
  });

  testWidgets('v1.6.0 第 5 条：天气在最上面、课程在中间、速览在最下面', (tester) async {
    setCity('示例市');
    // 速览列表一条都没有时不渲染（空态由「备忘」小卡承担），塞一条才有得比
    final seeded = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '占位的一条',
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
      ];
    store.saveNotes(seeded);
    await pumpHome(tester);

    final wx = tester.getTopLeft(find.byKey(const ValueKey('home-card-wx'))).dy;
    final lessons =
        tester.getTopLeft(find.byKey(const ValueKey('home-card-lessons'))).dy;
    final notes =
        tester.getTopLeft(find.byKey(const ValueKey('home-card-notes'))).dy;

    expect(wx, lessThan(lessons), reason: '天气要排在课程上面');
    expect(lessons, lessThan(notes), reason: '课程要排在备忘录速览上面');
  });

  testWidgets('天气小卡和备忘小卡等宽等高（v2.1.1）', (tester) async {
    setCity('示例市');
    final seeded = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '占位的一条',
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
      ];
    store.saveNotes(seeded);
    await pumpHome(tester);

    final wx = tester.getRect(find.byKey(const ValueKey('home-card-wx')));
    final memo = tester.getRect(find.byKey(const ValueKey('home-card-notes-mini')));
    expect(wx.width, closeTo(memo.width, 0.5), reason: '两张小卡要一样宽');
    expect(wx.height, closeTo(memo.height, 0.5),
        reason: '两张小卡要一样高，内容少的那张撑到和另一张齐平');
  });

  testWidgets('天气：失败但有旧缓存 → 显示旧数据标注', (tester) async {
    setCity('示例市');
    store.setWeatherCache(City(name: '示例市', latitude: 30.1, longitude: 118.2),
        normalize(rawFixture(temp: 19.0), City(name: '示例市', latitude: 30.1, longitude: 118.2)));
    // 把 fetchedAt 拨回两小时前，让它必然过期
    final t = DateTime.now().subtract(const Duration(hours: 2));
    String p2(int n) => n < 10 ? '0$n' : '$n';
    final cacheObj = store.weatherCache();
    cacheObj.fetchedAt =
        '${t.year}-${p2(t.month)}-${p2(t.day)}T${p2(t.hour)}:${p2(t.minute)}:00+08:00';
    store.write('weather_cache', cacheObj.toJson());
    await pumpHome(tester, customApi: FakeApi(fail: true));
    expect(find.byKey(const ValueKey('home-wx-stale')), findsOneWidget);
    expect(find.text('19°'), findsOneWidget);
  });

  // ---------- v1.8.1：数据变了首页要跟着变 ----------
  //
  // 凯森 2026-09-21 报的：在首页点开一条备忘录，在编辑页删掉，返回首页 ——
  // 那条**还在**「备忘录速览」里，得切走再切回来才消失。
  //
  // 根因是首页的 State 一直在（没被销毁），而 store 变了没有任何东西通知它重建。
  // 下面这条守着「删掉之后立刻不显示」，不靠切 Tab。

  testWidgets('v1.8.1：别处删掉备忘录，首页立刻不显示（不需要切 Tab）', (tester) async {
    final notes = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '但是', body: '随便写点什么',
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
        Note(
          id: 'n2', title: '留着的那条',
          createdAt: '2026-09-19T06:00:00+08:00',
          updatedAt: '2026-09-19T06:00:00+08:00',
        ),
      ];
    store.saveNotes(notes);

    await pumpHome(tester);
    expect(find.text('但是'), findsOneWidget);

    // 模拟「在编辑页里删掉了这条」——编辑页最终也是走 saveNotes
    final after = store.notes()
      ..notes = store.notes().notes.where((n) => n.id != 'n1').toList();
    store.saveNotes(after);
    await tester.pump();

    expect(find.text('但是'), findsNothing,
        reason: 'store 变了首页就该重建，不该等切 Tab');
    expect(find.text('留着的那条'), findsOneWidget, reason: '别误伤别的条目');
  });

  testWidgets('v1.8.1：首页销毁后不再响应 store 变化（监听没泄漏）', (tester) async {
    await pumpHome(tester);
    // 把首页从树上换掉，dispose 应该已经摘掉监听
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump();

    // 这个时候再写数据，不该出现「setState after dispose」之类的异常
    store.saveNotes(store.notes());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('备忘录速览：最多 3 条、置顶在前、清单项内容和勾选态都看得到', (tester) async {
    final notes = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '普通笔记', body: '第一行正文\n第二行',
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
        Note(
          id: 'n2', title: '置顶清单', type: NoteType.todo, pinned: true,
          items: <NoteItem>[
            NoteItem(text: '买菜', done: false),
            NoteItem(text: '拿快递', done: true),
          ],
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:30:00+08:00',
        ),
        Note(
          id: 'n3', title: '长清单',
          type: NoteType.todo,
          items: <NoteItem>[for (var i = 1; i <= 8; i++) NoteItem(text: '任务$i')],
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:10:00+08:00',
        ),
        Note(
          id: 'n4', title: '第四条不该出现', archived: false,
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
      ];
    store.saveNotes(notes);

    await pumpHome(tester);
    expect(find.text('普通笔记'), findsOneWidget);
    expect(find.text('置顶清单'), findsOneWidget);
    expect(find.text('长清单'), findsOneWidget);
    expect(find.text('第四条不该出现'), findsNothing, reason: '速览最多 3 条');
    expect(find.byKey(const ValueKey('home-note-n1')), findsOneWidget,
        reason: '速览按 updatedAt 排，最新的三条里包含 n1');
    // 摘要（标题下面那行）照旧一眼能看到
    expect(find.textContaining('1/2 项完成'), findsOneWidget);
    // 但内容默认收起（v1.9.1，凯森要求）—— 里面的项一开始看不见
    expect(find.text('买菜'), findsNothing, reason: '默认收起，内容不该露出来');
    expect(find.text('拿快递'), findsNothing);

    // 点小三角展开那一条，内容才出来
    await tester.tap(find.byKey(const ValueKey('home-caret-n2')));
    await tester.pumpAndSettle();
    expect(find.text('买菜'), findsOneWidget);
    expect(find.text('拿快递'), findsOneWidget);

    // 长清单（8 项）展开后才会显示「还有几项」
    await tester.tap(find.byKey(const ValueKey('home-caret-n3')));
    await tester.pumpAndSettle();
    expect(find.text('… 还有 2 项'), findsOneWidget);
  });

  testWidgets('v1.9.1：内容默认收起，点小三角展开、再点收起', (tester) async {
    final notes = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '有正文的笔记', body: '第一行正文\n第二行',
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
      ];
    store.saveNotes(notes);

    await pumpHome(tester);
    // 收起：只有标题
    expect(find.text('有正文的笔记'), findsOneWidget);
    expect(find.text('第一行正文\n第二行'), findsNothing);

    // 展开
    await tester.tap(find.byKey(const ValueKey('home-caret-n1')));
    await tester.pumpAndSettle();
    expect(find.text('第一行正文\n第二行'), findsOneWidget);

    // 再点收起
    await tester.tap(find.byKey(const ValueKey('home-caret-n1')));
    await tester.pumpAndSettle();
    expect(find.text('第一行正文\n第二行'), findsNothing);
  });

  testWidgets('点清单项直接勾，落盘且尾巴的项不被冲掉（v1.9.1 要先展开）',
      (tester) async {
    final notes = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '长清单', type: NoteType.todo,
          items: <NoteItem>[
            NoteItem(text: '任务1', done: false),
            NoteItem(text: '任务2', done: false),
            for (var i = 3; i <= 9; i++) NoteItem(text: '任务$i', done: false),
          ],
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
      ];
    store.saveNotes(notes);

    await pumpHome(tester);
    // v1.9.1：内容默认收起，先展开才能点里面的项
    await tester.tap(find.byKey(const ValueKey('home-caret-n1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-item-n1-0')));
    await tester.pump();

    // 落盘验证：直接读文件
    final raw = jsonDecode(File('${tmp.path}/notes.json').readAsStringSync())
        as Map<String, dynamic>;
    final items = (raw['notes'] as List).first['items'] as List;
    expect(items[0]['done'], isTrue);
    expect(items[1]['done'], isFalse);
    expect(items.length, 9, reason: '首页只显示前 6 项，第 7 项之后不能被冲掉');
    expect(items[8]['text'], '任务9');
    // 界面摘要同步更新
    expect(find.textContaining('1/9 项完成'), findsOneWidget);
  });

  testWidgets('小三角收放：默认收起，点开展开、再点收回去', (tester) async {
    final notes = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '带清单的', type: NoteType.todo,
          items: <NoteItem>[NoteItem(text: '任务1', done: false)],
          createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
      ];
    store.saveNotes(notes);

    await pumpHome(tester);
    expect(find.text('任务1'), findsNothing, reason: 'v1.9.1 起默认收起');
    await tester.tap(find.byKey(const ValueKey('home-caret-n1')));
    await tester.pump();
    expect(find.text('任务1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-caret-n1')));
    await tester.pump();
    expect(find.text('任务1'), findsNothing, reason: '再点一下收回去');
  });

  testWidgets('点速览的笔记行 → onOpenNote 带上那条的 id', (tester) async {
    final opened = <String>[];
    final notes = store.notes()
      ..notes = <Note>[
        Note(
          id: 'n1', title: '点我', createdAt: '2026-09-19T07:00:00+08:00',
          updatedAt: '2026-09-19T07:00:00+08:00',
        ),
      ];
    store.saveNotes(notes);

    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomePage(store: store, api: api, onOpenNote: opened.add),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('点我'));
    await tester.pump();
    expect(opened, <String>['n1']);
  });
}

String _hhmmOfMinute(int m) {
  m = m % 1440;
  String p2(int n) => n < 10 ? '0$n' : '$n';
  return '${p2(m ~/ 60)}:${p2(m % 60)}';
}
