/// 备份与还原：zip 打包四份数据 + manifest，还原时校验再覆盖。
///
/// 行为逐字对齐电脑版 `D:\App\MyDay\app\backup.py`：
/// - zip 里是 `manifest.json` + `settings.json` / `courses.json` / `notes.json` /
///   `weather_cache.json` 五个条目（没有目录层级）；
/// - manifest 是 `{app, version, exportedAt, files}`；
/// - 还原前必须校验：能解压、有 manifest、四份数据都在、每份都是 JSON 对象；
/// - 校验失败抛 [BackupException]，文案和电脑版一致；**任一步失败都不写盘**。
///
/// 时间用本地时区、格式和电脑版一致（`Store.nowIso()`：
/// `2026-09-19T11:16:02+08:00`）。电脑版 backup.py 固定用 UTC+8，
/// 用户在国内，两边实际是同一个钟面时间。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'store.dart';
import 'week.dart' show pad2;

/// 备份里必须有的四份数据文件（顺序也照电脑版）。
const List<String> backupDataFiles = <String>[
  'settings.json',
  'courses.json',
  'notes.json',
  'weather_cache.json',
];

const String backupManifestName = 'manifest.json';

/// 还原/校验失败的异常；message 直接给人看。
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 备份文件名：`MyDay-backup-YYYYMMDD-HHMM.zip`（本地时间，和电脑版同款）。
String backupZipName(DateTime now) =>
    'MyDay-backup-${now.year}${pad2(now.month)}${pad2(now.day)}'
    '-${pad2(now.hour)}${pad2(now.minute)}.zip';

/// manifest 内容（字段名与电脑版一字不差）。
Map<String, dynamic> buildManifest(DateTime now) => <String, dynamic>{
      'app': 'MyDay',
      'version': 1,
      'exportedAt': Store.isoOf(now),
      'files': List<String>.from(backupDataFiles),
    };

/// 把整个数据目录打成一个 zip 的字节串。
/// 某份数据文件不在时按电脑版写一个 `{}` 占位。
List<int> buildBackupZip(Store store, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final archive = Archive();
  void addText(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText(backupManifestName,
      const JsonEncoder.withIndent('  ').convert(buildManifest(n)));
  for (final name in backupDataFiles) {
    final f = File(p.join(store.dir.path, name));
    addText(name, f.existsSync() ? f.readAsStringSync() : '{}');
  }
  return ZipEncoder().encode(archive)!;
}

/// 把备份 zip 落到指定目录里，返回完整路径。
///
/// [dirPath] 为空就用数据目录旁边的 `backups/`（默认行为，和电脑版一致）；
/// v1.6.0（需求文档第 9 条）起用户可以自己指定备份位置，那时传 [dirPath]。
String saveBackupFile(Store store, List<int> bytes,
    {DateTime? now, String? dirPath}) {
  final Directory out;
  if (dirPath != null && dirPath.trim().isNotEmpty) {
    out = Directory(dirPath.trim());
  } else {
    out = Directory(p.join(store.dir.path, 'backups'));
  }
  try {
    out.createSync(recursive: true);
  } catch (e) {
    throw BackupException('备份位置用不了：$dirPath（$e）');
  }
  final path = p.join(out.path, backupZipName(now ?? DateTime.now()));
  try {
    File(path).writeAsBytesSync(bytes, flush: true);
  } catch (e) {
    throw BackupException('备份位置写不进去：$dirPath（$e）');
  }
  return path;
}

/// 校验结果：manifest 内容。
/// 不是 zip / 缺 manifest / manifest 坏 / 缺数据文件 → 抛 [BackupException]。
Map<String, dynamic> inspectBackup(List<int> raw) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(raw);
  } catch (e) {
    throw BackupException('不是有效的备份文件：$e');
  }
  ArchiveFile? find(String name) {
    for (final f in archive.files) {
      if (f.name == name) return f;
    }
    return null;
  }

  final manifestFile = find(backupManifestName);
  if (manifestFile == null) {
    throw BackupException('备份文件缺少 manifest.json');
  }
  Map<String, dynamic>? manifest;
  try {
    final obj = jsonDecode(utf8.decode(manifestFile.content as List<int>));
    if (obj is Map) {
      manifest = obj.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (e) {
    throw BackupException('manifest 读不出来：$e');
  }
  if (manifest == null) throw BackupException('manifest 读不出来：顶层不是对象');
  final missing = <String>[];
  for (final name in backupDataFiles) {
    if (find(name) == null) missing.add(name);
  }
  if (missing.isNotEmpty) {
    throw BackupException('备份缺少数据文件：${missing.join('、')}');
  }
  return manifest;
}

/// 解出一份 JSON 对象数据；坏了解析就抛（文案和电脑版一致）。
Map<String, dynamic> _readDataFile(Archive archive, String name) {
  for (final f in archive.files) {
    if (f.name == name) {
      Object? obj;
      try {
        obj = jsonDecode(utf8.decode(f.content as List<int>));
      } catch (e) {
        throw BackupException('$name 解析失败：$e');
      }
      if (obj is! Map) throw BackupException('$name 内容不是 JSON 对象');
      return obj.map((k, v) => MapEntry(k.toString(), v));
    }
  }
  throw BackupException('备份缺少数据文件：$name');
}

/// 还原前先给当前数据留一份备份（对齐电脑版 api_restore 的自动备份），
/// 返回备份文件名（界面提示用）。
String safetyBackup(Store store, {DateTime? now, String? dirPath}) {
  final path = saveBackupFile(store, buildBackupZip(store, now: now),
      now: now, dirPath: dirPath);
  return p.basename(path);
}

/// 校验并覆盖还原。**先全部校验、后一次性写盘**——半套修改不可能发生。
/// 返回 `{restored: [...], exportedAt: ...}`（键名与电脑版一致）。
Map<String, dynamic> restoreBackup(Store store, List<int> raw) {
  final archive = ZipDecoder().decodeBytes(raw);
  final manifest = inspectBackup(raw);
  final staged = <String, Map<String, dynamic>>{};
  for (final name in backupDataFiles) {
    staged[name] = _readDataFile(archive, name);
  }
  staged.forEach((name, obj) {
    store.write(name.substring(0, name.length - '.json'.length), obj);
  });
  store.clearWarnings();
  return <String, dynamic>{
    'restored': staged.keys.toList(),
    'exportedAt': manifest['exportedAt'],
  };
}

/// 清空全部数据：把四份文件写回默认内容（电脑版 api_reset_all 同款）。
/// **调用方负责先做安全备份**——电脑版和这里都是「先备份再清」。
void resetAllData(Store store) {
  for (final name in Store.fileNames) {
    store.write(name, Store.defaultsFor(name));
  }
  store.clearWarnings();
}
