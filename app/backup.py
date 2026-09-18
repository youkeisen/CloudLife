# -*- coding: utf-8 -*-
"""备份与还原：zip 打包四份数据 + manifest，还原时校验再覆盖。"""
import io
import json
import os
import zipfile
from datetime import datetime, timedelta, timezone

CST = timezone(timedelta(hours=8))
DATA_FILES = ('settings.json', 'courses.json', 'notes.json', 'weather_cache.json')
MANIFEST = 'manifest.json'


class BackupError(Exception):
    pass


def zip_name():
    return 'MyDay-backup-' + datetime.now(CST).strftime('%Y%m%d-%H%M') + '.zip'


def make_bytes(data_dir):
    buf = io.BytesIO()
    manifest = {
        'app': 'MyDay',
        'version': 1,
        'exportedAt': datetime.now(CST).isoformat(timespec='seconds'),
        'files': list(DATA_FILES),
    }
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(MANIFEST, json.dumps(manifest, ensure_ascii=False, indent=2))
        for name in DATA_FILES:
            path = os.path.join(data_dir, name)
            data = b'{}'
            if os.path.isfile(path):
                with open(path, 'rb') as f:
                    data = f.read()
            zf.writestr(name, data)
    return buf.getvalue(), manifest


def save_backup(data_dir, backups_dir=None):
    payload, manifest = make_bytes(data_dir)
    out_dir = backups_dir or os.path.join(data_dir, 'backups')
    os.makedirs(out_dir, exist_ok=True)
    name = zip_name()
    path = os.path.join(out_dir, name)
    with open(path, 'wb') as f:
        f.write(payload)
    return path, manifest


def inspect_bytes(raw):
    """检查 zip 是否合法：必须含 manifest 且能被解析。"""
    try:
        zf = zipfile.ZipFile(io.BytesIO(raw))
    except Exception as exc:
        raise BackupError('不是有效的备份文件：' + str(exc))
    names = zf.namelist()
    if MANIFEST not in names:
        raise BackupError('备份文件缺少 manifest.json')
    try:
        manifest = json.loads(zf.read(MANIFEST).decode('utf-8'))
    except Exception as exc:
        raise BackupError('manifest 读不出来：' + str(exc))
    missing = [n for n in DATA_FILES if n not in names]
    if missing:
        raise BackupError('备份缺少数据文件：' + '、'.join(missing))
    return zf, manifest


def restore_bytes(data_dir, raw):
    """把备份覆盖回数据目录；任一步失败就抛出，不做半套修改。"""
    import store
    zf, manifest = inspect_bytes(raw)
    staged = {}
    for name in DATA_FILES:
        try:
            obj = json.loads(zf.read(name).decode('utf-8'))
        except Exception as exc:
            raise BackupError('%s 解析失败：%s' % (name, exc))
        if not isinstance(obj, dict):
            raise BackupError('%s 内容不是 JSON 对象' % name)
        staged[name] = obj
    for name, obj in staged.items():
        store.write(name[:-5], obj)
    store.clear_warnings()
    return {'files': list(staged.keys()), 'exportedAt': manifest.get('exportedAt')}


def keep_recent(backups_dir, limit=10):
    """只保留最近的 limit 份备份。"""
    if not os.path.isdir(backups_dir):
        return []
    items = sorted([os.path.join(backups_dir, f) for f in os.listdir(backups_dir)
                    if f.endswith('.zip')], key=os.path.getmtime)
    removed = []
    while len(items) > limit:
        old = items.pop(0)
        try:
            os.remove(old)
            removed.append(os.path.basename(old))
        except OSError:
            pass
    return removed
