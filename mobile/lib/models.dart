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

bool asBool(dynamic v) => v == true || v == 'true' || v == 1;

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
    this.refreshMinutes = 30,
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
        refreshMinutes: asInt(json['refreshMinutes'], 30),
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
        'theme': theme,
      };

  Period? periodById(String id) {
    for (final p in periods) {
      if (p.id == id) return p;
    }
    return null;
  }

  Place? placeById(String id) {
    for (final p in weatherCities) {
      if (p.id == id) return p;
    }
    return null;
  }
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

  List<int> get usedWeeks => weeks.keys.toList()..sort();
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
    List<String>? tags,
    this.pinned = false,
    this.archived = false,
    this.createdAt = '',
    this.updatedAt = '',
    Map<String, dynamic>? extra,
  })  : items = items ?? <NoteItem>[],
        tags = tags ?? <String>[],
        extra = extra ?? <String, dynamic>{};

  String id;
  String title;
  String type;
  String body;
  List<NoteItem> items;
  List<String> tags;
  bool pinned;
  bool archived;
  String createdAt;
  String updatedAt;
  Map<String, dynamic> extra;

  static const Set<String> known = {
    'id',
    'title',
    'type',
    'body',
    'items',
    'tags',
    'pinned',
    'archived',
    'createdAt',
    'updatedAt',
  };

  bool get isTodo => type == NoteType.todo;
  int get itemsTotal => items.length;
  int get itemsDone => items.where((i) => i.done).length;

  /// 列表第二行要显示的摘要（和电脑版一致）。
  String get summary {
    if (isTodo) {
      return items.isEmpty ? '' : '$itemsDone/$itemsTotal 项完成';
    }
    return body.split('\n').first.trim();
  }

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: asString(json['id']),
        title: asString(json['title']),
        type: asString(json['type']) == NoteType.todo ? NoteType.todo : NoteType.text,
        body: asString(json['body']),
        items: (json['items'] is List)
            ? (json['items'] as List).map((e) => NoteItem.fromJson(asMap(e))).toList()
            : <NoteItem>[],
        tags: asStringList(json['tags']),
        pinned: asBool(json['pinned']),
        archived: asBool(json['archived']),
        createdAt: asString(json['createdAt']),
        updatedAt: asString(json['updatedAt']),
        extra: extraKeys(json, known),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'id': id,
        'title': title,
        'type': type,
        'body': body,
        'items': items.map((i) => i.toJson()).toList(),
        'tags': tags,
        'pinned': pinned,
        'archived': archived,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  Note copyWith({
    String? title,
    String? type,
    String? body,
    List<NoteItem>? items,
    List<String>? tags,
    bool? pinned,
    bool? archived,
    String? updatedAt,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        type: type ?? this.type,
        body: body ?? this.body,
        items: items ?? List<NoteItem>.from(this.items),
        tags: tags ?? List<String>.from(this.tags),
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
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
