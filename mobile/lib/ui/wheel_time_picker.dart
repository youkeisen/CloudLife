/// Windows 同款的两列滚轮时间选择（时 / 分 + 确定 / 取消）。
/// 节次时间和备忘录提醒共用（凯森 v1.3.2 指定这个样式）。
library;

import 'package:flutter/cupertino.dart' show CupertinoPicker, FixedExtentScrollController;
import 'package:flutter/material.dart';

/// 弹出滚轮时间选择，返回选中的时间；取消返回 null。
Future<TimeOfDay?> showWheelTimePicker(
    BuildContext context, TimeOfDay initial) {
  var hour = initial.hour.clamp(0, 23);
  var minute = initial.minute.clamp(0, 59);
  return showDialog<TimeOfDay>(
    context: context,
    barrierDismissible: false, // 防止误点外面关掉导致白选
    builder: (ctx) => AlertDialog(
      title: const Text('选择时间'),
      content: SizedBox(
        height: 180,
        child: Row(
          children: <Widget>[
            Expanded(
              child: CupertinoPicker(
                key: const ValueKey('wheel-hour'),
                scrollController: FixedExtentScrollController(initialItem: hour),
                itemExtent: 40,
                onSelectedItemChanged: (i) => hour = i,
                children: <Widget>[
                  for (var h = 0; h < 24; h++)
                    Center(
                      child: Text(h.toString().padLeft(2, '0'),
                          style: const TextStyle(fontSize: 20)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                key: const ValueKey('wheel-minute'),
                scrollController:
                    FixedExtentScrollController(initialItem: minute),
                itemExtent: 40,
                onSelectedItemChanged: (i) => minute = i,
                children: <Widget>[
                  for (var m = 0; m < 60; m++)
                    Center(
                      child: Text(m.toString().padLeft(2, '0'),
                          style: const TextStyle(fontSize: 20)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('wheel-ok'),
          onPressed: () =>
              Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
