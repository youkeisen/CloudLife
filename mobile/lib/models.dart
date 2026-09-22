/// MyDay 手机版的数据模型。
///
/// **字段名必须和电脑版一字不差**——电脑版见 `D:\App\MyDay\app\store.py`
/// 里的 `DEFAULT_SETTINGS` / `DEFAULT_COURSES` / `DEFAULT_NOTES` / `DEFAULT_WEATHER`。
/// 只有字段名一致，电脑版导出的备份 zip 才能直接导进手机（见 PRD 第 6 节）。
///
/// 每个模型都留了一个 `extra`：JSON 里认不出来的字段原样留着、写回时带上。
/// 这样万一哪边先加了新字段，另一边读写一圈也不会把它吃掉。
library;

const int schemaVersion = 1;
const String defaultTimezone = 'Asia/Shanghai';

// ---------- 解析小工具 ----------
String asString(dynamic v) => v == null ? '' : v.toString();

int asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

double? asDoubleOrNull(dynamic v) {
  if (v is num) {
    final d = v.toDouble();
    if (d.isNaN || d.isInfinite) return null;
    return d;
  }
  if (v is String) {
    final d = double.tryParse(v.trim());
    if (d == null || d.isNaN || d.isInfinite) return null;
    return d;
  }
  return null;
}

/// 温度显示统一走这里：整数就去掉小数点（21.0 → 21），
/// 非数字给占位符（默认 `--`，传空串可以配合 join 过滤掉）。
String fmtTemp(dynamic v, [String placeholder = '--']) {
  final d = asDoubleOrNull(v);
  if (d == null) return placeholder;
  return d == d.roundToDouble() ? '${d.round()}' : '$d';
}

bool asBool(dynamic v) => v == true || v == 'true' || v == 1;

/// 规范提醒方式：只认 daily / days，**别的一律当单次**。
///
/// 写成函数是为了只有一处判断——以后加一种方式只改这里，
/// 而且「认不出来的值」有统一行为（当单次，不引入没实现的行为）。
String _normRepeat(String raw) {
  if (raw == Note.remindRepeatDaily) return Note.remindRepeatDaily;
  if (raw == Note.remindRepeatDays) return Note.remindRepeatDays;
  return '';
}

List<String> asStringList(dynamic v) {
  if (v is! List) return <String>[];
  return v.map(asString).where((s) => s.isNotEmpty).toList();
}

/// 取出认不出来的字段，留着原样写回去。
Map<String, dynamic> extraKeys(Map<String, dynamic> json, Set<String> known) {
  final out = <String, dynamic>{};
  json.forEach((k, v) {
    if (!known.contains(k)) out[k] = v;
  });
  return out;
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

// ---------- 节次 ----------
class Period {
  Period({
    required this.id,
    this.label = '',
    this.start = '',
    this.end = '',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  String id;
  String label;
  String start;
  String end;
  Map<String, dynamic> extra;

  static const Set<String> known = {'id', 'label', 'start', 'end'};

  factory Period.fromJson(Map<String, dynamic> json) => Period(
        id: asString(json['id']),
        label: asString(json['label']),
        start: asString(json['start']),
        end: asString(json['end']),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'id': id,
        'label': label,
        'start': start,
        'end': end,
      };

  Period copyWith({String? id, String? label, String? start, String? end}) => Period(
        id: id ?? this.id,
        label: label ?? this.label,
        start: start ?? this.start,
        end: end ?? this.end,
        extra: Map<String, dynamic>.from(extra),
      );

  @override
  bool operator ==(Object other) =>
      other is Period &&
      other.id == id &&
      other.label == label &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, label, start, end);
}

// ---------- 地点 ----------
/// 当前城市（settings.weatherCity）：只有名字和经纬度，没有 id。
class City {
  City({
    this.name = '',
    this.latitude,
    this.longitude,
    this.timezone = defaultTimezone,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  String name;
  double? latitude;
  double? longitude;

  /// 跟着备份序列化走；天气请求目前固定用 `defaultTimezone`，暂未消费。
  String timezone;
  Map<String, dynamic> extra;

  static const Set<String> known = {'name', 'latitude', 'longitude', 'timezone'};

  bool get isEmpty => name.isEmpty || latitude == null || longitude == null;
  bool get isSet => !isEmpty;

  factory City.fromJson(Map<String, dynamic> json) => City(
        name: asString(json['name']),
        latitude: asDoubleOrNull(json['latitude']),
        longitude: asDoubleOrNull(json['longitude']),
        timezone: asString(json['timezone']).isEmpty
            ? defaultTimezone
            : asString(json['timezone']),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
      };

  @override
  bool operator ==(Object other) =>
      other is City &&
      other.name == name &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(name, latitude, longitude, timezone);
}

/// 「我的地点」里的一条：比 City 多 id 和省/市。
class Place {
  Place({
    required this.id,
    required this.name,
    this.admin = '',
    required this.latitude,
    required this.longitude,
    this.timezone = defaultTimezone,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  String id;
  String name;
  String admin;
  double latitude;
  double longitude;

  /// 跟着备份序列化走；天气请求目前固定用 `defaultTimezone`，暂未消费。
  String timezone;
  Map<String, dynamic> extra;

  static const Set<String> known = {'id', 'name', 'admin', 'latitude', 'longitude', 'timezone'};

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: asString(json['id']),
        name: asString(json['name']),
        admin: asString(json['admin']),
        latitude: asDoubleOrNull(json['latitude']) ?? 0,
        longitude: asDoubleOrNull(json['longitude']) ?? 0,
        timezone: asString(json['timezone']).isEmpty
            ? defaultTimezone
            : asString(json['timezone']),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'id': id,
        'name': name,
        'admin': admin,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
      };

  /// 和电脑版 `_as_current` 一致：转成当前城市。
  City toCity() => City(
        name: name,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
      );

  String get label => admin.isEmpty ? name : '$name · $admin';

  @override
  bool operator ==(Object other) => other is Place && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ---------- 设置 ----------
class Settings {
  Settings({
    this.version = schemaVersion,
    this.displayName = '',
    this.semesterName = '',
    this.week1Monday = '',
    this.weekStartsOn = 1,
    this.campus = '',
    List<Period>? periods,
    City? weatherCity,
    List<Place>? weatherCities,
    this.refreshMinutes = 10,
    this.lessonRemindMinutes = 15,
    this.backupDir = '',
    this.theme = 'system',
    Map<String, dynamic>? extra,
  })  : periods = periods ?? <Period>[],
        weatherCity = weatherCity ?? City(),
        weatherCities = weatherCities ?? <Place>[],
        extra = extra ?? <String, dynamic>{};

  int version;
  String displayName;
  String semesterName;
  String week1Monday;
  int weekStartsOn;
  String campus;
  List<Period> periods;
  City weatherCity;
  List<Place> weatherCities;
  int refreshMinutes;
  String theme;

  /// 上课前多少分钟提醒（v1.6.0，需求文档第 1 条）。
  /// 0 = 不提醒；负数表示关掉。存在 extra 之外是因为手机版专属，
  /// 电脑版读不出来会原样留在 extra 里，不影响互通。
  int lessonRemindMinutes;

  /// 自定义备份位置（v1.6.0，需求文档第 9 条）；空 = 用默认的 backups/。
  String backupDir;
  Map<String, dynamic> extra;

  static const int maxPlaces = 20;

  static const Set<String> known = {
    'version',
    'displayName',
    'semesterName',
    'week1Monday',
    'weekStartsOn',
    'campus',
    'periods',
    'weatherCity',
    'weatherCities',
    'refreshMinutes',
    'lessonRemindMinutes',
    'backupDir',
    'theme',
  };

  /// 全新安装的默认设置：**一个字都不能有真东西**（零预置原则）。
  factory Settings.initial() => Settings();

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        version: asInt(json['version'], schemaVersion),
        displayName: asString(json['displayName']),
        semesterName: asString(json['semesterName']),
        week1Monday: asString(json['week1Monday']),
        weekStartsOn: asInt(json['weekStartsOn'], 1) == 7 ? 7 : 1,
        campus: asString(json['campus']),
        periods: (json['periods'] is List)
            ? (json['periods'] as List)
                .map((e) => Period.fromJson(asMap(e)))
                .toList()
            : <Period>[],
        weatherCity: City.fromJson(asMap(json['weatherCity'])),
        weatherCities: (json['weatherCities'] is List)
            ? (json['weatherCities'] as List)
                .map((e) => Place.fromJson(asMap(e)))
                .toList()
            : <Place>[],
        refreshMinutes: asInt(json['refreshMinutes'], 10),
        lessonRemindMinutes: asInt(json['lessonRemindMinutes'], 15),
        backupDir: asString(json['backupDir']),
        theme: asString(json['theme']).isEmpty ? 'system' : asString(json['theme']),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'version': schemaVersion,
        'displayName': displayName,
        'semesterName': semesterName,
        'week1Monday': week1Monday,
        'weekStartsOn': weekStartsOn,
        'campus': campus,
        'periods': periods.map((p) => p.toJson()).toList(),
        'weatherCity': weatherCity.toJson(),
        'weatherCities': weatherCities.map((p) => p.toJson()).toList(),
        'refreshMinutes': refreshMinutes,
        'lessonRemindMinutes': lessonRemindMinutes,
        'backupDir': backupDir,
        'theme': theme,
      };

}

// ---------- 课程 ----------
class Lesson {
  Lesson({
    required this.id,
    required this.day,
    required this.slot,
    this.spanEnd = '',
    this.name = '',
    this.location = '',
    this.teacher = '',
    this.note = '',
    this.color = '',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  String id;
  int day;
  String slot;
  String spanEnd;
  String name;
  String location;
  String teacher;
  String note;
  String color;
  Map<String, dynamic> extra;

  static const Set<String> known = {
    'id',
    'day',
    'slot',
    'spanEnd',
    'name',
    'location',
    'teacher',
    'note',
    'color',
  };

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
        id: asString(json['id']),
        day: asInt(json['day'], 1),
        slot: asString(json['slot']),
        spanEnd: asString(json['spanEnd']),
        name: asString(json['name']),
        location: asString(json['location']),
        teacher: asString(json['teacher']),
        note: asString(json['note']),
        color: asString(json['color']),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'id': id,
        'day': day,
        'slot': slot,
        'spanEnd': spanEnd,
        'name': name,
        'location': location,
        'teacher': teacher,
        'note': note,
        'color': color,
      };

  Lesson copyWith({
    String? id,
    int? day,
    String? slot,
    String? spanEnd,
    String? name,
    String? location,
    String? teacher,
    String? note,
    String? color,
  }) =>
      Lesson(
        id: id ?? this.id,
        day: day ?? this.day,
        slot: slot ?? this.slot,
        spanEnd: spanEnd ?? this.spanEnd,
        name: name ?? this.name,
        location: location ?? this.location,
        teacher: teacher ?? this.teacher,
        note: note ?? this.note,
        color: color ?? this.color,
        extra: Map<String, dynamic>.from(extra),
      );
}

class Courses {
  Courses({this.version = schemaVersion, Map<int, List<Lesson>>? weeks})
      : weeks = weeks ?? <int, List<Lesson>>{};

  int version;

  /// 周次 -> 那一周的课。JSON 里键是字符串（和电脑版一致）。
  Map<int, List<Lesson>> weeks;

  factory Courses.fromJson(Map<String, dynamic> json) {
    final weeks = <int, List<Lesson>>{};
    final raw = json['weeks'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final week = int.tryParse(k.toString());
        if (week == null) return;
        if (v is! List) return;
        weeks[week] = v.map((e) => Lesson.fromJson(asMap(e))).toList();
      });
    }
    return Courses(
      version: asInt(json['version'], schemaVersion),
      weeks: weeks,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': schemaVersion,
        'weeks': weeks.map((k, v) => MapEntry(k.toString(), v.map((l) => l.toJson()).toList())),
      };

  List<Lesson> week(int w) => List<Lesson>.from(weeks[w] ?? const <Lesson>[]);

  /// 和电脑版 `save_week` 一样：空的那周也留一个空数组，不删键。
  void setWeek(int w, List<Lesson> lessons) {
    weeks[w] = List<Lesson>.from(lessons);
  }
}

// ---------- 备忘录 ----------
class NoteItem {
  NoteItem({this.text = '', this.done = false, Map<String, dynamic>? extra})
      : extra = extra ?? <String, dynamic>{};

  String text;
  bool done;
  Map<String, dynamic> extra;

  static const Set<String> known = {'text', 'done'};

  factory NoteItem.fromJson(Map<String, dynamic> json) => NoteItem(
        text: asString(json['text']),
        done: asBool(json['done']),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'text': text,
        'done': done,
      };

  NoteItem copyWith({String? text, bool? done}) => NoteItem(
        text: text ?? this.text,
        done: done ?? this.done,
        extra: Map<String, dynamic>.from(extra),
      );
}

/// 备忘录类型：笔记 / 清单（JSON 里是 'text' / 'todo'，和电脑版一致）。
class NoteType {
  static const String text = 'text';
  static const String todo = 'todo';

  static String label(String type) => type == todo ? '清单' : '笔记';
}

class Note {
  Note({
    required this.id,
    this.title = '',
    this.type = NoteType.text,
    this.body = '',
    List<NoteItem>? items,
    this.pinned = false,
    this.archived = false,
    this.createdAt = '',
    this.updatedAt = '',
    this.remindAt = '',
    this.remindRepeat = '',
    this.remindDays = 0,
    Map<String, dynamic>? extra,
  })  : items = items ?? <NoteItem>[],
        extra = extra ?? <String, dynamic>{};

  String id;
  String title;
  String type;
  String body;
  List<NoteItem> items;

  /// v1.9.0：**标签字段已删除**（凯森要求「把笔记里的标签删除」「数据一起清掉」）。
  /// 存量数据由 `Store.init()` 里的一次性清理负责抹掉。
  bool pinned;
  bool archived;
  String createdAt;
  String updatedAt;

  /// 定时提醒的 ISO 时间；空 = 不提醒（凯森 v1.5.0 要求的定时通知）。
  ///
  /// [remindRepeat] 为 [remindRepeatDaily] 时，只有时:分有意义
  /// （日期部分只是「设的时候的基准」，重排时会算成下一次该响的时刻）。
  String remindAt;

  /// 重复方式（v1.8.2 加「每天」，v1.9.1 加「N 天后」）：
  /// '' = 单次（最近的那个时:分，响一次），
  /// [remindRepeatDaily] = 每天，
  /// [remindRepeatDays] = [remindDays] 天后的那个时:分，响一次。
  String remindRepeat;

  /// 「N 天后」的那个 N（只在 [remindRepeatDays] 时有用）。
  int remindDays;

  static const String remindRepeatDaily = 'daily';
  static const String remindRepeatDays = 'days';

  /// 是不是每天重复。
  bool get remindDaily => remindRepeat == remindRepeatDaily;

  /// 是不是「N 天后」。
  bool get remindAfterDays => remindRepeat == remindRepeatDays;
  Map<String, dynamic> extra;

  static const Set<String> known = {
    'id',
    'title',
    'type',
    'body',
    'items',
    // 'tags' 特意留在这里：这个字段已经不用了，但**不能从 known 里删** ——
    // extraKeys 会把「不认识」的键收进 extra 再原样写回去（见 v1.9.0 DEV-PLAN），
    // 删了反而把旧数据永久留在文件里。留着它，读进来就丢、写出去就没有。
    'tags',
    'pinned',
    'archived',
    'createdAt',
    'updatedAt',
    'remindAt',
    'remindRepeat',
    'remindDays',
  };

  bool get isTodo => type == NoteType.todo;
  int get itemsTotal => items.length;
  int get itemsDone => items.where((i) => i.done).length;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: asString(json['id']),
        title: asString(json['title']),
        type: asString(json['type']) == NoteType.todo ? NoteType.todo : NoteType.text,
        body: asString(json['body']),
        items: (json['items'] is List)
            ? (json['items'] as List).map((e) => NoteItem.fromJson(asMap(e))).toList()
            : <NoteItem>[],
        // 旧数据里的 tags 直接丢掉（标签功能已删）
        pinned: asBool(json['pinned']),
        archived: asBool(json['archived']),
        createdAt: asString(json['createdAt']),
        updatedAt: asString(json['updatedAt']),
        remindAt: asString(json['remindAt']),
        // 只认 daily / days，别的一律当单次（旧数据没这个键 → 单次，行为不变）
        remindRepeat: _normRepeat(asString(json['remindRepeat'])),
        remindDays: asInt(json['remindDays'], 0),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'id': id,
        'title': title,
        'type': type,
        'body': body,
        'items': items.map((i) => i.toJson()).toList(),
        'pinned': pinned,
        'archived': archived,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'remindAt': remindAt,
        'remindRepeat': remindRepeat,
        'remindDays': remindDays,
      };

  Note copyWith({
    String? title,
    String? type,
    String? body,
    List<NoteItem>? items,
    bool? pinned,
    bool? archived,
    String? updatedAt,
    String? remindAt,
    String? remindRepeat,
    int? remindDays,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        type: type ?? this.type,
        body: body ?? this.body,
        items: items ?? List<NoteItem>.from(this.items),
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        // 提醒这三样必须带上：copyWith 是「照着旧的造一个新的」，
        // 漏掉哪个字段就等于静默把它清空（提醒是最容易被这样弄丢的）。
        remindAt: remindAt ?? this.remindAt,
        remindRepeat: remindRepeat ?? this.remindRepeat,
        remindDays: remindDays ?? this.remindDays,
        extra: Map<String, dynamic>.from(extra),
      );
}

class Notes {
  Notes({this.version = schemaVersion, List<Note>? notes})
      : notes = notes ?? <Note>[];

  int version;
  List<Note> notes;

  factory Notes.fromJson(Map<String, dynamic> json) => Notes(
        version: asInt(json['version'], schemaVersion),
        notes: (json['notes'] is List)
            ? (json['notes'] as List).map((e) => Note.fromJson(asMap(e))).toList()
            : <Note>[],
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': schemaVersion,
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  Note? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

// ---------- 天气缓存 ----------
class WeatherCache {
  WeatherCache({
    this.version = schemaVersion,
    this.fetchedAt = '',
    City? city,
    this.payload,
    Map<String, dynamic>? extra,
  })  : city = city ?? City(),
        extra = extra ?? <String, dynamic>{};

  int version;
  String fetchedAt;

  /// 只有 name / latitude / longitude（和电脑版一致，不带 timezone）。
  City city;
  Map<String, dynamic>? payload;
  Map<String, dynamic> extra;

  static const Set<String> known = {'version', 'fetchedAt', 'city', 'payload'};

  factory WeatherCache.fromJson(Map<String, dynamic> json) {
    final rawCity = asMap(json['city']);
    return WeatherCache(
      version: asInt(json['version'], schemaVersion),
      fetchedAt: asString(json['fetchedAt']),
      city: City(
        name: asString(rawCity['name']),
        latitude: asDoubleOrNull(rawCity['latitude']),
        longitude: asDoubleOrNull(rawCity['longitude']),
      ),
      payload: json['payload'] is Map ? asMap(json['payload']) : null,
      extra: extraKeys(json, known),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'version': schemaVersion,
        'fetchedAt': fetchedAt,
        'city': <String, dynamic>{
          'name': city.name,
          'latitude': city.latitude,
          'longitude': city.longitude,
        },
        'payload': payload,
      };
}

// ---------- 记账（v1.7.0，需求文档第 3 条） ----------
//
// 设计稿（桌面文档里的 image2）用的是 SQLite 两张表：
//   categories(id, name, icon, sort)
//   records(id, amount, category_id, date, note, created_at)
// 这里沿用项目的 JSON 存储（要和电脑版备份互通），字段名照设计稿，
// 只是把 SQLite 的 id/外键换成了字符串 id。
//
// 记账是手机版独有的模块，电脑版暂时没有，所以这里没有「必须和电脑版
// 一字不差」的约束；但每份数据都带 extra，保持和其他模块一致的习惯。

/// 记账分类。icon 存的是图标标识（见 ledger_icons.dart 的映射表），
/// 不存图片，避免把资源文件塞进数据里。
class LedgerCategory {
  LedgerCategory({
    required this.id,
    required this.name,
    this.icon = 'other',
    this.sort = 0,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  final String id;
  final String name;
  final String icon;
  final int sort;
  final Map<String, dynamic> extra;

  static const Set<String> known = {'id', 'name', 'icon', 'sort'};

  factory LedgerCategory.fromJson(Map<String, dynamic> json) {
    return LedgerCategory(
      id: asString(json['id']),
      name: asString(json['name']),
      icon: asString(json['icon']),
      sort: asInt(json['sort'], 0),
      extra: extraKeys(json, known),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'id': id,
        'name': name,
        'icon': icon,
        'sort': sort,
      };

  LedgerCategory copyWith({String? name, String? icon, int? sort}) {
    return LedgerCategory(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sort: sort ?? this.sort,
      extra: extra,
    );
  }
}

/// 一笔账。
///
/// amount 存的是**正数**（元），方向由 kind 决定（支出 / 收入）；
/// 这样改了方向不用改金额，也避免「负负得正」这类算术坑。
class LedgerRecord {
  LedgerRecord({
    required this.id,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.createdAt = '',
    this.kind = ledgerKindExpense,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? <String, dynamic>{};

  final String id;
  final double amount;
  final String categoryId;

  /// `YYYY-MM-DD`
  final String date;
  final String note;
  final String createdAt;

  /// `expense` 支出 / `income` 收入
  final String kind;
  final Map<String, dynamic> extra;

  static const Set<String> known = {
    'id', 'amount', 'categoryId', 'date', 'note', 'createdAt', 'kind',
  };

  bool get isIncome => kind == ledgerKindIncome;

  /// 带符号的金额：支出负、收入正。汇总时直接用。
  double get signed => isIncome ? amount : -amount;

  factory LedgerRecord.fromJson(Map<String, dynamic> json) {
    final kind = asString(json['kind']);
    return LedgerRecord(
      id: asString(json['id']),
      // 金额兜底成 0，负数也掰成正数（方向归 kind 管）
      amount: (asDoubleOrNull(json['amount']) ?? 0).abs(),
      categoryId: asString(json['categoryId']),
      date: asString(json['date']),
      note: asString(json['note']),
      createdAt: asString(json['createdAt']),
      kind: kind == ledgerKindIncome ? ledgerKindIncome : ledgerKindExpense,
      extra: extraKeys(json, known),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'id': id,
        'amount': amount,
        'categoryId': categoryId,
        'date': date,
        'note': note,
        'createdAt': createdAt,
        'kind': kind,
      };

  LedgerRecord copyWith({
    double? amount,
    String? categoryId,
    String? date,
    String? note,
    String? kind,
  }) {
    return LedgerRecord(
      id: id,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      createdAt: createdAt,
      kind: kind ?? this.kind,
      extra: extra,
    );
  }
}

const String ledgerKindExpense = 'expense';
const String ledgerKindIncome = 'income';

/// 一整份记账数据（对应一个 ledger 文件）。
class Ledger {
  Ledger({
    List<LedgerCategory>? categories,
    List<LedgerRecord>? records,
    Map<String, dynamic>? extra,
  })  : categories = categories ?? <LedgerCategory>[],
        records = records ?? <LedgerRecord>[],
        extra = extra ?? <String, dynamic>{};

  List<LedgerCategory> categories;
  List<LedgerRecord> records;
  final Map<String, dynamic> extra;

  static const Set<String> known = {'version', 'categories', 'records'};

  factory Ledger.fromJson(Map<String, dynamic> json) {
    final cats = json['categories'];
    final recs = json['records'];
    return Ledger(
      categories: cats is List
          ? cats
              .whereType<Map>()
              .map((e) => LedgerCategory.fromJson(asMap(e)))
              .where((c) => c.id.isNotEmpty)
              .toList()
          : <LedgerCategory>[],
      records: recs is List
          ? recs
              .whereType<Map>()
              .map((e) => LedgerRecord.fromJson(asMap(e)))
              .where((r) => r.id.isNotEmpty)
              .toList()
          : <LedgerRecord>[],
      extra: extraKeys(json, known),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'version': schemaVersion,
        'categories': categories.map((c) => c.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
      };
}
