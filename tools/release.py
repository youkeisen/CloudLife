# -*- coding: utf-8 -*-
"""发 GitHub Release（把 APK 作为 asset 传上去）。

用法：
    py -3 tools/release.py mobile-v1.6.0 --title "CloudLife v1.6.0" \
        --apk D:\\App\\apk\\MyDay-手机版-v1.6.0.apk --notes-file notes.md \
        --commit 37d1fd9

令牌从 `git credential fill` 取，不落盘、不进日志、不写进命令行参数。
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

REPO = 'youkeisen/CloudLife'
API = 'https://api.github.com'


class GitHubError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def token():
    """从 git 的凭据管理器里取令牌。"""
    out = subprocess.run(
        ['git', 'credential', 'fill'],
        input='protocol=https\nhost=github.com\n\n',
        capture_output=True, text=True, timeout=30,
    ).stdout
    for line in out.splitlines():
        if line.startswith('password='):
            return line[len('password='):].strip()
    raise SystemExit('拿不到 GitHub 令牌：git credential fill 没返回 password')


def call(tok, path, method='GET', body=None, raw=None, content_type='application/json',
         ok_codes=(200, 201), full_url=''):
    url = full_url or (API + path)
    data = None
    if body is not None:
        data = json.dumps(body).encode('utf-8')
    elif raw is not None:
        data = raw
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', 'token ' + tok)
    req.add_header('Accept', 'application/vnd.github+json')
    if data is not None:
        req.add_header('Content-Type', content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as exc:
        if exc.code in ok_codes:
            return {}
        detail = exc.read().decode('utf-8', 'replace')
        raise GitHubError(exc.code, '%s %s：%s\n%s' % (method, path, exc.code, detail))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('tag')
    ap.add_argument('--title', required=True)
    ap.add_argument('--notes-file', required=True)
    ap.add_argument('--apk', required=True)
    ap.add_argument('--asset-name', default='',
                    help='asset 名（默认按 tag 生成 MyDay-vX.Y.Z.apk，别用中文）')
    ap.add_argument('--commit', default='')
    ap.add_argument('--prerelease', action='store_true')
    ap.add_argument('--upload-only', action='store_true',
                    help='release 已存在时只补传 APK，不改说明')
    args = ap.parse_args()

    if not os.path.isfile(args.apk):
        raise SystemExit('APK 不存在：' + args.apk)
    with open(args.notes_file, encoding='utf-8') as fh:
        notes = fh.read().strip()
    if not notes:
        raise SystemExit('说明文件是空的：' + args.notes_file)

    tok = token()

    # 已经有同 tag 的 release 就报错，不静默覆盖
    try:
        existing = call(tok, '/repos/%s/releases/tags/%s' % (REPO, args.tag))
    except GitHubError as exc:
        if exc.code != 404:
            raise SystemExit('查已有 release 失败：' + str(exc))
        existing = None

    if existing is not None:
        if not args.upload_only:
            raise SystemExit('这个 tag 已经有 release 了：%s（要是只想补传 APK，加 --upload-only）'
                             % args.tag)
        rel = existing
        print('release 已存在，只补传附件：', rel.get('html_url'))
    else:
        payload = {
            'tag_name': args.tag,
            'name': args.title or args.tag,
            'body': notes,
            'draft': False,
            'prerelease': bool(args.prerelease),
        }
        if args.commit:
            payload['target_commitish'] = args.commit
        rel = call(tok, '/repos/%s/releases' % REPO, 'POST', body=payload)
        print('release 建好了：', rel.get('html_url'))

    # asset 名字用英文：中文名放进 URL 会让 urllib 用 ascii 编码报错
    # （之前踩过：UnicodeEncodeError: 'ascii' codec can't encode）。
    name = args.asset_name or default_asset_name(args.tag)
    have = {a.get('name') for a in rel.get('assets') or []}
    if name in have:
        raise SystemExit('这个 release 已经有同名附件了：' + name)
    # 传附件要走 uploads.github.com（release 对象里的 upload_url 给了地址，
    # 它在 api.github.com 上是 404）。
    upload_base = (rel.get('upload_url') or '').split('{')[0]
    if not upload_base:
        upload_base = 'https://uploads.github.com/repos/%s/releases/%s/assets' % (
            REPO, rel['id'])
    with open(args.apk, 'rb') as fh:
        blob = fh.read()
    up = call(
        tok, '',
        'POST', raw=blob, content_type='application/vnd.android.package-archive',
        full_url='%s?name=%s' % (upload_base, urllib.parse.quote(name)),
    )
    print('APK 传好了：%s（%d 字节）' % (up.get('name'), up.get('size', 0)))
    print('下载地址：', up.get('browser_download_url'))


def default_asset_name(tag):
    """tag `mobile-v1.6.0` → asset `MyDay-v1.6.0.apk`（沿用之前的命名）。"""
    ver = tag.split('mobile-v', 1)[-1] if 'mobile-v' in tag else tag
    return 'MyDay-v%s.apk' % ver


if __name__ == '__main__':
    main()
