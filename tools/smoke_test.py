# -*- coding: utf-8 -*-
"""MyDay 冒烟脚本：临时数据目录里完整跑一遍主要流程，打印中文清单。

用法：
    python tools/smoke_test.py            # 只需要单机，不联网
    python tools/smoke_test.py net        # 额外校验真实天气接口
"""
import base64
import json
import os
import sys
import time
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR / 'tests'))
from helpers import TestServer  # noqa: E402

CHECKS = []


def check(label, condition, detail=''):
    CHECKS.append((label, bool(condition), detail))
    print('  [%s] %s%s' % ('OK ' if condition else 'FAIL', label,
                           (' —— ' + detail) if (detail and not condition) else ''))
    return bool(condition)


def main(argv):
    net = 'net' in argv[1:]
    srv = TestServer()
    print('启动临时 MyDay 实例…')
    srv.start()
    ok_all = True
    try:
        b = srv.ok('/api/bootstrap')
        ok_all &= check('全新启动：节次与课程都是空的',
                        b['settings']['periods'] == [] and 'MyDay' == 'MyDay')
        ok_all &= check('全新启动：没有预置任何课程',
                        srv.ok('/api/courses?week=1')['total'] == 0)

        srv.ok('/api/settings', 'PUT', {'displayName': '冒烟', 'week1Monday': time.strftime('%Y-%m-%d')})
        p1 = srv.ok('/api/settings/period', 'POST', {'label': '第一节', 'start': '08:00', 'end': '09:00'})
        p2 = srv.ok('/api/settings/period', 'POST', {'label': '第二节', 'start': '09:10', 'end': '10:00'})
        ok_all &= check('添加节次', len(srv.ok('/api/settings')['periods']) == 2)

        meta = srv.ok('/api/bootstrap')['weekMeta']
        week = meta['week'] or 1
        srv.ok('/api/courses', 'POST', {'name': '冒烟课程', 'week': week, 'day': meta['dow'],
                                        'slot': p1['id'], 'spanEnd': p2['id']})
        ok_all &= check('添加今日课程', srv.ok('/api/courses?week=%d' % week)['total'] == 1)
        home = srv.ok('/api/home')
        ok_all &= check('首页能看到今天的课', home['todayCount'] == 1)
        ok_all &= check('首页能算出教学周', home['meta']['week'] == 1)

        srv.ok('/api/courses/copy', 'POST', {'from': week, 'to': [4, 5], 'mode': 'overwrite'})
        ok_all &= check('整周复制生效', srv.ok('/api/courses?week=4')['total'] == 1)

        note = srv.ok('/api/notes', 'POST', {'title': '冒烟笔记', 'type': 'todo',
                                             'items': [{'text': 'a', 'done': True},
                                                       {'text': 'b', 'done': False}]})
        srv.ok('/api/notes', 'PUT', {'id': note['id'], 'items': [
            {'text': 'a', 'done': True}, {'text': 'b', 'done': True}]})
        again = [n for n in srv.ok('/api/notes')['notes'] if n['id'] == note['id']][0]
        ok_all &= check('备忘录勾选能保存', again['items'][1]['done'] is True)

        ok_all &= check('未选城市时首页给出引导',
                        srv.ok('/api/home')['weather']['state'] == 'no_city')

        if net:
            srv.ok('/api/settings', 'PUT', {'weatherCity': {'name': '合肥', 'latitude': 31.86,
                                                            'longitude': 117.28,
                                                            'timezone': 'Asia/Shanghai'}})
            res = srv.request('/api/weather?refresh=1')
            ok_all &= check('真实天气接口可用',
                            res['json'].get('ok') and res['json']['data']['source'] == 'network',
                            str(res['json'])[:160])
        else:
            print('  [-- ] 跳过真实天气校验（加 net 参数才会联网）')

        raw = srv.get('/api/backup', raw=True)['body']
        srv.ok('/api/reset-all', 'POST', {})
        ok_all &= check('清空后数据归零', srv.ok('/api/notes')['total'] == 0)
        srv.ok('/api/restore', 'POST', {'content': base64.b64encode(raw).decode('ascii')})
        ok_all &= check('备份能还原回来',
                        [n['title'] for n in srv.ok('/api/notes')['notes']] == ['冒烟笔记'])
        ok_all &= check('还原后课程也在',
                        srv.ok('/api/courses?week=%d' % week)['total'] == 1)

        target = srv.data_dir / 'settings.json'
        target.write_text('{"broken"', encoding='utf-8')
        warned = srv.ok('/api/bootstrap')['warnings']
        ok_all &= check('坏数据文件能自愈', bool(warned) and
                        json.loads(target.read_text(encoding='utf-8'))['periods'] == [])

        data_dir = str(srv.data_dir)
        srv.proc.terminate()
        srv.proc.wait(timeout=10)
        revived = TestServer(data_dir=data_dir)
        revived.start()
        try:
            ok_all &= check('重启后数据仍在',
                            [n['title'] for n in revived.ok('/api/notes')['notes']] == ['冒烟笔记'])
        finally:
            revived.stop()
        srv.proc = None
    finally:
        srv.stop()

    failed = [n for n, ok, _ in CHECKS if not ok]
    print('')
    print('=' * 56)
    print('冒烟结果：%d 项通过，%d 项失败' % (len(CHECKS) - len(failed), len(failed)))
    if failed:
        for n in failed:
            print('  失败：' + n)
    print('=' * 56)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
