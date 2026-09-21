# -*- coding: utf-8 -*-
"""运行 MyDay 全部测试（或指定阶段）。

用法：
    python tools/run_tests.py            # 跑全部阶段
    python tools/run_tests.py 3          # 只跑阶段 3
    python tools/run_tests.py all net    # 跑全部并把联网测试也算进来
"""
import io
import os
import sys
import time
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
TESTS_DIR = TOOLS_DIR / 'tests'
sys.path.insert(0, str(TESTS_DIR))

STAGES = list(range(0, 18))  # 加 stage17：电脑版对齐手机版（去标签 + 速览默认收起）


def load_stage(stage):
    name = 'test_stage%d' % stage
    mod = __import__(name)
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(mod)
    return suite


def main(argv):
    args = argv[1:]
    include_net = 'net' in args
    args = [a for a in args if a != 'net']
    if args and args[0] != 'all':
        stages = [int(a) for a in args if a.isdigit()]
    else:
        stages = STAGES

    if include_net:
        os.environ['MYDAY_NET'] = '1'

    suite = unittest.TestSuite()
    for s in stages:
        try:
            suite.addTests(load_stage(s))
        except ImportError as exc:
            print('跳过阶段 %d：%s' % (s, exc))

    stream = io.StringIO()
    runner = unittest.TextTestRunner(stream=stream, verbosity=2, resultclass=unittest.TextTestResult)
    t0 = time.time()
    result = runner.run(suite)
    cost = time.time() - t0

    out = stream.getvalue()
    try:
        sys.stdout.write(out)
    except UnicodeEncodeError:
        sys.stdout.write(out.encode('utf-8', 'replace').decode('utf-8'))

    print('')
    print('=' * 60)
    print('结果：跑 %d 个用例，失败 %d，错误 %d，跳过 %d，用时 %.1f 秒'
          % (result.testsRun, len(result.failures), len(result.errors),
             len(getattr(result, 'skipped', [])), cost))
    if result.failures:
        print('--- 失败 ---')
        for test, _ in result.failures:
            print('  ' + str(test))
    if result.errors:
        print('--- 错误 ---')
        for test, _ in result.errors:
            print('  ' + str(test))
    print('=' * 60)
    return 1 if (result.failures or result.errors) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
