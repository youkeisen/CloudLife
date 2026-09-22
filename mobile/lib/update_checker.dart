/// 检查更新（设置 → 关于 → 检查更新）。
///
/// 数据源是 GitHub Releases（仓库 youkeisen/CloudLife）：
///   · 手机版的 tag 是 `mobile-vX.Y.Z`，发布说明在 body 里，apk 挂在附件上
///   · 仓库里还有**电脑版**的 release（tag 不带 mobile- 前缀）——所以不能用
///     `/releases/latest`（它返回的是所有类型里最新的一个，可能撞上电脑版），
///     要拉列表自己筛
///
/// 网络层用 dart:io 的 HttpClient（同 weather_api，不引额外网络包）。
/// 手动检查、带超时；GitHub 对未登录请求限流（每小时几十次），手动点完全够用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'models.dart';

/// 一次检查的结论。
enum UpdateStatus {
  /// 已经是最新（或者发布列表里还没有手机版）。
  upToDate,

  /// 有更新的版本，[UpdateCheckResult.release] 里有详情。
  available,

  /// 检查失败（网络、限流等），[UpdateCheckResult.message] 给人看的原因。
  error,
}

/// 一条手机版 release 的信息。
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.apkUrl,
    required this.releaseUrl,
  });

  /// 纯版本号，如 `2.2.0`。
  final String version;

  /// 原始 tag，如 `mobile-v2.2.0`。
  final String tagName;

  /// 发布说明（GitHub body 原文，可能是 markdown，按普通文本展示）。
  final String notes;

  /// .apk 附件的下载地址；附件丢了就是空串（界面改给发布页链接）。
  final String apkUrl;

  /// release 页面地址（兜底入口）。
  final String releaseUrl;
}

class UpdateCheckResult {
  const UpdateCheckResult.upToDate([this.message])
      : status = UpdateStatus.upToDate,
        release = null;

  const UpdateCheckResult.available(ReleaseInfo this.release)
      : status = UpdateStatus.available,
        message = null;

  const UpdateCheckResult.error(this.message)
      : status = UpdateStatus.error,
        release = null;

  final UpdateStatus status;
  final ReleaseInfo? release;
  final String? message;
}

/// GitHub 返回的不是预期结构。
class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 从各种写法里抠出版本号数字段：`2.2.0` / `v2.2.0` / `mobile-v2.2.0` 都行。
List<int> parseVersionParts(String s) {
  final m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(s);
  if (m == null) return const <int>[];
  return m.group(1)!.split('.').map(int.parse).toList();
}

/// 比较版本号：>0 表示 [a] 更新，<0 表示 [b] 更新，0 表示一样。
/// 缺的段按 0 算（2.1 等于 2.1.0）。
int compareVersions(String a, String b) {
  final pa = parseVersionParts(a);
  final pb = parseVersionParts(b);
  final n = math.max(pa.length, pb.length);
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// 从一条 release JSON 里取手机版信息；不是手机版（tag 不带 `mobile-` 前缀）
/// 返回 null。
ReleaseInfo? releaseFromJson(Map<String, dynamic> m) {
  final tag = asString(m['tag_name']);
  const prefix = 'mobile-v';
  if (!tag.startsWith(prefix)) return null;
  final version = tag.substring(prefix.length);

  String apkUrl = '';
  final assets = m['assets'] is List ? m['assets'] as List : const <dynamic>[];
  for (final a in assets) {
    final am = asMap(a);
    final name = asString(am['name']);
    if (name.toLowerCase().endsWith('.apk')) {
      apkUrl = asString(am['browser_download_url']);
      break;
    }
  }

  return ReleaseInfo(
    version: version,
    tagName: tag,
    notes: asString(m['body']),
    apkUrl: apkUrl,
    releaseUrl: asString(m['html_url']),
  );
}

/// 从 release 列表里挑最新的手机版（GitHub 按新到旧返回，取第一个命中的）。
ReleaseInfo? pickMobileRelease(List<dynamic> items) {
  for (final item in items) {
    if (item is! Map) continue;
    final r = releaseFromJson(item.map((k, v) => MapEntry(k.toString(), v)));
    if (r != null) return r;
  }
  return null;
}

class UpdateChecker {
  UpdateChecker({
    String? apiBase,
    this.timeout = const Duration(seconds: 15),
    this.fetchReleases,
  }) : apiBase = apiBase ?? defaultApiBase;

  /// 测试时注入一个假的拉取函数；不给就走真的 HTTP。
  final Future<List<dynamic>> Function()? fetchReleases;

  static const String defaultApiBase =
      'https://api.github.com/repos/youkeisen/CloudLife/releases';

  final String apiBase;
  final Duration timeout;

  /// 拉一次发布列表并和当前版本比。
  Future<UpdateCheckResult> check(String currentVersion) async {
    try {
      final fetch = fetchReleases ?? _fetchReleasesOverHttp;
      final items = await fetch().timeout(timeout);
      final release = pickMobileRelease(items);
      if (release == null) {
        // 一个手机版 release 都没有：不弹窗，给一句人话
        return const UpdateCheckResult.upToDate('发布列表里还没有手机版');
      }
      if (compareVersions(release.version, currentVersion) > 0) {
        return UpdateCheckResult.available(release);
      }
      return const UpdateCheckResult.upToDate('已经是最新版本');
    } catch (e) {
      return UpdateCheckResult.error(
          e is UpdateCheckException ? e.message : e.toString());
    }
  }

  Future<List<dynamic>> _fetchReleasesOverHttp() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('$apiBase?per_page=20'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>().timeout(timeout);
        throw UpdateCheckException('HTTP ${response.statusCode}');
      }
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      final obj = jsonDecode(text);
      if (obj is List) return obj;
      throw UpdateCheckException('返回的不是列表');
    } on UpdateCheckException {
      rethrow;
    } catch (e) {
      throw UpdateCheckException(e.toString());
    } finally {
      client.close(force: true);
    }
  }
}
