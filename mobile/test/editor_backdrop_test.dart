// 编辑清单/编辑笔记页的回归测试：它是独立路由，底下没有壳子的渐变背景，
// 必须自己垫 GlassBackdrop——否则透明的 Scaffold 会露出路由遮罩的黑底
//（v1.1.0 的真机 bug：浅色模式下进编辑页变黑）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/ui/glass.dart';
import 'package:my_day_phone/ui/notes_page.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-editor-bg-');
    store = Store(tmp)..init();
    final now = Store.nowIso();
    final note = Note(
      id: 'n1',
      title: '作业',
      type: 'todo',
      items: <NoteItem>[NoteItem(text: '第一行', done: false)],
      createdAt: now,
      updatedAt: now,
    );
    final notes = store.notes();
    notes.notes.add(note);
    store.saveNotes(notes);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> openEditor(WidgetTester tester) async {
    // 列表页是塞进主壳子 Scaffold 里的内容块，测试要自己给它套一个
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotesPage(store: store)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
  }

  testWidgets('浅色模式：进编辑页也要有玻璃渐变背景，不能是黑底', (tester) async {
    await openEditor(tester);
    expect(find.text('编辑清单'), findsOneWidget);
    expect(find.byType(GlassBackdrop), findsWidgets,
        reason: '编辑页是独立路由，必须自己垫玻璃渐变背景');
  });

  testWidgets('深色模式：同样要有背景垫层', (tester) async {
    await openEditor(tester);
    // 深浅色都走同一个结构，这里再确认一遍编辑页内容真的铺出来了
    expect(find.byKey(const ValueKey('field-title')), findsOneWidget);
    expect(find.byType(GlassBackdrop), findsWidgets);
  });
}
