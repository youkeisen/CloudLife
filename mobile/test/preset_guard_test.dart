// 零预置原则的守卫：App 里（lib/ 下的所有源码）不许出现任何真实个人信息。
// 这份禁词表是「真实世界专属词」，用意是挡住把真实课表/城市/学校写死进代码的事故。
// 测试文件与文档不在扫描范围（它们不进 APK），但测试样例数据也要求用虚构内容。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 出现任何一个都算违规。
const List<String> banned = <String>[
  // 真实的学校 / 校区 / 教学楼
  '应用技术',
  '文昌',
  '笃学楼',
  'ehall',
  'abc.edu',
  // 真实的人名与学号
  '杨成川',
  '2501310133',
  // 真实的课程与教室编号
  '工程制图',
  '单片机',
  '电力电子',
  '电气控制',
  '劳动教育',
  '1#1',
  '1#2',
  '1#3',
  // 真实城市
  '芜湖',
];

/// lib/ 下所有 dart 源码。
List<File> libSources(String repoRoot) {
  final libDir = Directory('$repoRoot/lib');
  return libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

void main() {
  // 测试文件位于 <项目>/test，往上两级就是项目根。
  final repoRoot = Directory.current.path;

  test('lib/ 里不含任何真实个人信息（零预置）', () {
    final files = libSources(repoRoot);
    expect(files, isNotEmpty, reason: '找不到 lib 源码，扫描等于没做');

    final hits = <String>[];
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final word in banned) {
        if (text.contains(word)) {
          final lineNo = text.substring(0, text.indexOf(word)).split('\n').length;
          hits.add('${f.path}:$lineNo 含「$word」');
        }
      }
    }
    expect(hits, isEmpty, reason: 'App 代码里出现真实信息：\n${hits.join('\n')}');
  });

  test('禁词表本身是真实词，防呆：不能全是空串', () {
    expect(banned, isNotEmpty);
    expect(banned.every((w) => w.trim().isNotEmpty), isTrue);
  });
}
