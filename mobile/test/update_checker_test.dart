// 检查更新的逻辑测试：版本号解析 / 比较、从 release 列表里挑手机版、
// check() 的四种结论（有新版 / 已最新 / 没有手机版 / 检查失败）。
// 拉取函数是注入的，不联网。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/update_checker.dart';

Map<String, dynamic> releaseJson({
  String tag = 'mobile-v2.2.0',
  String body = '· 修了一些问题',
  String? apkName = 'CloudLife-v2.2.0.apk',
}) =>
    <String, dynamic>{
      'tag_name': tag,
      'body': body,
      'html_url': 'https://github.com/youkeisen/CloudLife/releases/tag/$tag',
      'assets': apkName == null
          ? <dynamic>[]
          : <dynamic>[
              <String, dynamic>{
                'name': apkName,
                'browser_download_url':
                    'https://github.com/youkeisen/CloudLife/releases/download/$tag/$apkName',
              },
            ],
    };

void main() {
  group('parseVersionParts', () {
    test('裸版本 / 带 v / 带 mobile-v 前缀都能抠出来', () {
      expect(parseVersionParts('2.2.0'), <int>[2, 2, 0]);
      expect(parseVersionParts('v2.2.0'), <int>[2, 2, 0]);
      expect(parseVersionParts('mobile-v2.2.0'), <int>[2, 2, 0]);
      expect(parseVersionParts('2.1'), <int>[2, 1]);
      expect(parseVersionParts('没写版本'), isEmpty);
    });
  });

  group('compareVersions', () {
    test('逐段比，缺的段按 0', () {
      expect(compareVersions('2.2.0', '2.1.1'), greaterThan(0));
      expect(compareVersions('2.1.1', '2.2.0'), lessThan(0));
      expect(compareVersions('2.1.1', '2.1.1'), 0);
      expect(compareVersions('2.1.0', '2.1'), 0, reason: '缺的段按 0 算');
      expect(compareVersions('2.1.1', '2.1.1.1'), lessThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });
  });

  group('releaseFromJson / pickMobileRelease', () {
    test('mobile-v 的 tag 才算手机版，电脑版跳过', () {
      expect(releaseFromJson(releaseJson(tag: 'mobile-v2.2.0')), isNotNull);
      expect(releaseFromJson(releaseJson(tag: 'v1.3.0')), isNull,
          reason: '仓库里还有电脑版的 release，不能当成手机版更新');
    });

    test('apk 附件丢了就给空地址（界面改给发布页）', () {
      final r = releaseFromJson(releaseJson(apkName: null))!;
      expect(r.apkUrl, isEmpty);
      expect(r.releaseUrl, isNotEmpty);
    });

    test('列表里电脑版排前面也挑得出手机版', () {
      final r = pickMobileRelease(<dynamic>[
        releaseJson(tag: 'v1.3.0'),
        releaseJson(tag: 'mobile-v2.2.0'),
      ]);
      expect(r, isNotNull);
      expect(r!.version, '2.2.0');
    });

    test('列表为空给 null', () {
      expect(pickMobileRelease(<dynamic>[]), isNull);
    });
  });

  group('UpdateChecker.check', () {
    test('有新版本 → available，带 release 详情', () async {
      final checker = UpdateChecker(
        fetchReleases: () async => <dynamic>[releaseJson(tag: 'mobile-v2.2.0')],
      );
      final r = await checker.check('2.1.1');
      expect(r.status, UpdateStatus.available);
      expect(r.release!.version, '2.2.0');
      expect(r.release!.apkUrl, contains('.apk'));
    });

    test('当前就是最新 → upToDate', () async {
      final checker = UpdateChecker(
        fetchReleases: () async => <dynamic>[releaseJson(tag: 'mobile-v2.1.1')],
      );
      final r = await checker.check('2.1.1');
      expect(r.status, UpdateStatus.upToDate);
      expect(r.release, isNull);
    });

    test('本地比发布还新也算最新 → upToDate', () async {
      final checker = UpdateChecker(
        fetchReleases: () async => <dynamic>[releaseJson(tag: 'mobile-v2.0.0')],
      );
      final r = await checker.check('2.1.1');
      expect(r.status, UpdateStatus.upToDate);
    });

    test('发布列表里还没有手机版 → upToDate 并给一句人话', () async {
      final checker = UpdateChecker(fetchReleases: () async => <dynamic>[]);
      final r = await checker.check('2.1.1');
      expect(r.status, UpdateStatus.upToDate);
      expect(r.message, '发布列表里还没有手机版');
    });

    test('拉取失败 → error，原因是给人看的', () async {
      final checker = UpdateChecker(
        fetchReleases: () async => throw UpdateCheckException('网络断了'),
      );
      final r = await checker.check('2.1.1');
      expect(r.status, UpdateStatus.error);
      expect(r.message, '网络断了');
    });

    test('底层 SocketException（GitHub 直连不通）也翻译成人话', () async {
      final checker = UpdateChecker(
        fetchReleases: () async => throw const SocketException('refused'),
      );
      final r = await checker.check('2.1.1');
      expect(r.status, UpdateStatus.error);
      expect(r.message, contains('连不上 GitHub'),
          reason: '不能把异常原文怼到用户脸上');
    });
  });

  group('describeNetworkError', () {
    test('连接被拒 / 超时 / TLS 各给一句人话', () {
      expect(describeNetworkError(const SocketException('refused')),
          contains('连不上 GitHub'));
      expect(describeNetworkError(TimeoutException('t', Duration(seconds: 1))),
          contains('超时'));
      expect(describeNetworkError(const HandshakeException('bad')),
          contains('安全连接'));
    });

    test('已经是人话的异常原样透传', () {
      expect(
        describeNetworkError(UpdateCheckException('GitHub 限流了')),
        'GitHub 限流了',
      );
    });
  });
}
