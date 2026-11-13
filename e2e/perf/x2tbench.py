#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
"""Converts xlsx files to Editor.bin with x2t and prints one JSON line per conversion.

Measures wall time, CPU time and peak RSS of the x2t process (from wait4, exact), the
Editor.bin size and its SHA-256, so two x2t builds can be checked for byte-identical output.

  python3 perf/x2tbench.py --container NAME [options] file.xlsx...   # x2t inside a DS container
  python3 perf/x2tbench.py --x2t PATH [options] file.xlsx...         # a local x2t build

See README.md.
"""

import argparse
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from xml.sax.saxutils import escape

# Install path in the Euro-Office image. For other builds, pass --x2t.
CONTAINER_X2T = '/var/www/euro-office/documentserver/server/FileConverter/bin/x2t'
FORMAT_XLSX_TO_EDITOR_BIN = 8194


def params_xml(src, dst, tmp, themes):
    theme = f'<m_sThemeDir>{escape(themes)}</m_sThemeDir>' if themes else ''
    return (
        '\ufeff<?xml version="1.0" encoding="utf-8"?>'
        '<TaskQueueDataConvert xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xmlns:xsd="http://www.w3.org/2001/XMLSchema">'
        f'<m_sKey>perf</m_sKey><m_sFileFrom>{escape(src)}</m_sFileFrom>'
        f'<m_sFileTo>{escape(dst)}</m_sFileTo>'
        f'<m_nFormatTo>{FORMAT_XLSX_TO_EDITOR_BIN}</m_nFormatTo>{theme}'
        f'<m_bIsNoBase64>true</m_bIsNoBase64><m_sTempDir>{escape(tmp)}</m_sTempDir>'
        '</TaskQueueDataConvert>'
    )


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def convert(x2t, src, workdir, themes, do_gzip):
    out = os.path.join(workdir, 'out')
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, 'tmp'))
    params = os.path.join(out, 'params.xml')
    target = os.path.join(out, 'Editor.bin')
    with open(params, 'w', encoding='utf-8') as f:
        f.write(params_xml(src, target, os.path.join(out, 'tmp'), themes))
    env = dict(os.environ)
    libs = os.path.dirname(os.path.abspath(x2t))
    env['LD_LIBRARY_PATH'] = libs + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
    with open(os.path.join(out, 'x2t.log'), 'wb') as log:
        start = time.monotonic()
        pid = os.posix_spawn(
            x2t,
            [x2t, params],
            env,
            file_actions=[
                (os.POSIX_SPAWN_DUP2, log.fileno(), 1),
                (os.POSIX_SPAWN_DUP2, log.fileno(), 2),
            ],
        )
        _, status, usage = os.wait4(pid, 0)
        wall = time.monotonic() - start
    with open(os.path.join(out, 'x2t.log'), 'rb') as f:
        log_tail = f.read()[-300:].decode('utf-8', 'replace').strip()
    row = {
        'file': os.path.basename(src),
        'rc': os.waitstatus_to_exitcode(status),
        'wall_s': round(wall, 3),
        'user_s': round(usage.ru_utime, 3),
        'sys_s': round(usage.ru_stime, 3),
        'peak_rss_mb': round(usage.ru_maxrss / 1024, 1),  # ru_maxrss is in KiB on Linux
        'load1': round(os.getloadavg()[0], 2),
    }
    if os.path.exists(target):
        row['bin_bytes'] = os.path.getsize(target)
        row['bin_sha256'] = sha256(target)
        if do_gzip:
            # nginx compresses Editor.bin at gzip level 5 on every download.
            with open(target, 'rb') as f:
                t = time.monotonic()
                row['gz5_bytes'] = len(gzip.compress(f.read(), 5))
                row['gz5_s'] = round(time.monotonic() - t, 3)
    if row['rc'] != 0 or 'bin_bytes' not in row:
        row['error'] = log_tail or 'no Editor.bin'
    shutil.rmtree(out, ignore_errors=True)
    return row


def run_local(args):
    workdir = tempfile.mkdtemp(prefix='x2tbench-', dir=args.workdir)
    failures = 0
    try:
        for rep in range(1, args.reps + 1):
            for src in args.files:
                row = convert(args.x2t, os.path.abspath(src), workdir, args.themes, args.gzip)
                row['rep'] = rep
                if args.label:
                    row['label'] = args.label
                failures += 'error' in row
                print(json.dumps(row), flush=True)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    return 1 if failures else 0


def docker(*cmd, **kw):
    return subprocess.run(['docker', *cmd], check=True, **kw)


def run_in_container(args):
    """Copies the inputs and this script into the container and runs it there."""
    container = args.container
    workdir = docker('exec', container, 'mktemp', '-d', capture_output=True, text=True).stdout.strip()
    try:
        inside = []
        for i, src in enumerate(args.files):
            # One folder per input keeps the original file name in the output.
            folder = f'{workdir}/in/{i}'
            docker('exec', container, 'mkdir', '-p', folder)
            docker('cp', src, f'{container}:{folder}/{os.path.basename(src)}')
            inside.append(f'{folder}/{os.path.basename(src)}')
        with open(os.path.abspath(__file__), 'rb') as f:
            script = f.read()
        cmd = ['exec', '-i', container, 'python3', '-', '--x2t', args.x2t or CONTAINER_X2T]
        cmd += ['--reps', str(args.reps), '--workdir', workdir]
        if args.themes:
            cmd += ['--themes', args.themes]
        if args.gzip:
            cmd.append('--gzip')
        if args.label:
            cmd += ['--label', args.label]
        result = subprocess.run(['docker', *cmd, *inside], input=script)
        return result.returncode
    finally:
        subprocess.run(['docker', 'exec', container, 'rm', '-rf', workdir], check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    where = parser.add_mutually_exclusive_group(required=True)
    where.add_argument('--container', help='run the x2t inside this Docker container')
    where.add_argument('--x2t', help='x2t binary; its folder must hold its shared libraries')
    parser.add_argument('--container-x2t', dest='container_x2t', help=f'x2t path inside the container (default {CONTAINER_X2T})')
    parser.add_argument('--reps', type=int, default=1, help='convert every file this many times (default 1)')
    parser.add_argument('--themes', help='m_sThemeDir for x2t (not needed for xlsx)')
    parser.add_argument('--gzip', action='store_true', help='also report the Editor.bin size at gzip level 5')
    parser.add_argument('--label', help='copied into every output line')
    parser.add_argument('--workdir', help=argparse.SUPPRESS)  # set when running inside the container
    parser.add_argument('files', nargs='+')
    args = parser.parse_args()
    if args.container:
        args.x2t = args.container_x2t
        sys.exit(run_in_container(args))
    sys.exit(run_local(args))


if __name__ == '__main__':
    main()
