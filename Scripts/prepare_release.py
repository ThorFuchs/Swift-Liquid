#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate exact-source CI evidence and prepare release assets without publishing."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import posixpath
import shutil
import subprocess
import tarfile
from ci import ROOT, source_snapshot
from compare_benchmarks import BASELINE, HARNESS_SHA256, MANIFEST_SHA256, index_records, comparisons


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--run-url', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        raise RuntimeError('Expected a stable semantic version')
    if not re.fullmatch(r'https://github.com/ThorFuchs/Swift-Liquid/actions/runs/\d+', args.run_url):
        raise RuntimeError('Expected this repository\'s qualification run URL')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip():
        raise RuntimeError('Release packaging requires a clean candidate')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=ROOT, text=True).strip()
    evidence = args.evidence.resolve()
    run = json.loads((evidence / 'github-run.json').read_text())
    if run['status'] != 'completed' or run['conclusion'] != 'success' or run['headSha'] != commit or run['url'] != args.run_url:
        raise RuntimeError('GitHub run does not qualify this candidate commit')
    expected_sources = source_snapshot()
    lanes = ['native', 'safety', 'reference', 'platforms', 'docs', 'performance', 'matched-performance', 'archive']
    for lane in lanes:
        receipt = json.loads((evidence / ('liquid-' + lane) / 'receipt.json').read_text())
        if receipt['status'] != 'passed' or receipt['sources'] != expected_sources:
            raise RuntimeError(f'{lane} is failed or does not match the candidate source inventory')
    archive_root = evidence / 'liquid-archive'
    archive_receipt = json.loads((archive_root / 'archive.json').read_text())
    if not archive_receipt['byteIdenticalRepeatedSourceArchives'] or archive_receipt['cleanNativeQualification'] != 'passed':
        raise RuntimeError('Source archive was not reproducible and cleanly rebuilt')
    inventory = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).split(b'\0')
    if sorted(archive_receipt['inventory']) != sorted(p.decode() for p in inventory if p):
        raise RuntimeError('Source archive inventory differs from the candidate')
    if set(archive_receipt['assets']) != {'Swift-Liquid-source.tar.gz', 'Liquid.doccarchive.tar.gz'}:
        raise RuntimeError('Unexpected release asset inventory')
    for name, digest in archive_receipt['assets'].items():
        if hashlib.sha256((archive_root / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'Asset checksum mismatch: {name}')
    with tarfile.open(archive_root / 'Swift-Liquid-source.tar.gz') as archive:
        seen = set()
        for member in archive.getmembers():
            if member.issym() or member.islnk() or Path(member.name).is_absolute() or '..' in Path(member.name).parts:
                raise RuntimeError('Unsafe source archive entry')
            if member.isfile():
                if member.name in seen or archive.extractfile(member).read() != (ROOT / member.name).read_bytes():
                    raise RuntimeError(f'Source archive differs: {member.name}')
                seen.add(member.name)
        if seen != set(archive_receipt['inventory']):
            raise RuntimeError('Missing source archive files')
    matched_root = evidence / 'liquid-matched-performance'
    comparison_bytes = (matched_root / 'comparison.json').read_bytes()
    matched = json.loads(comparison_bytes)
    if (matched['candidateCommit'] != archive_receipt['candidateCommit'] or matched['baselineCommit'] != BASELINE
            or matched['harnessSHA256'] != HARNESS_SHA256 or matched['manifestSHA256'] != MANIFEST_SHA256
            or matched['order'] != ['baseline', 'candidate', 'candidate', 'baseline'] * 3
            or [r['version'] for r in matched['runs']] != matched['order']
            or len(matched['comparisons']) != 14):
        raise RuntimeError('Matched comparison is incomplete or belongs to another candidate')
    common_records = {r['name']: index_records(json.loads((matched_root / r['result']).read_text())) for r in matched['runs']}
    if comparisons(matched['runs'], common_records, ['baseline', 'candidate']) != matched['comparisons']:
        raise RuntimeError('Matched summary differs from retained measurements')
    metrics = matched['metrics']
    if (metrics['candidateCommit'] != matched['candidateCommit'] or metrics['librarySHA256'] != matched['candidateLibrarySHA256']
            or metrics['harnessSHA256'] != matched['metricsHarnessSHA256']
            or metrics['order'] != ['ordinary', 'metrics', 'metrics', 'ordinary'] * 3
            or [r['version'] for r in metrics['runs']] != metrics['order'] or len(metrics['comparisons']) != 12):
        raise RuntimeError('Metrics comparison is incomplete or uses another library')
    metric_records = {r['name']: index_records(json.loads((matched_root / r['result']).read_text()), r['version']) for r in metrics['runs']}
    if comparisons(metrics['runs'], metric_records, ['ordinary', 'metrics']) != metrics['comparisons']:
        raise RuntimeError('Metrics summary differs from retained measurements')
    review = json.loads((evidence / 'benchmark-review.json').read_text())
    if (review['status'] != 'reviewed' or review['releaseQualification'] != 'passed'
            or review['comparisonSHA256'] != hashlib.sha256(comparison_bytes).hexdigest()
            or review['baselineCommit'] != BASELINE or review['candidateLibrarySHA256'] != matched['candidateLibrarySHA256']
            or sorted(review['reviewedCompatibilityFlags']) != sorted(matched['reviewRequired'])
            or sorted(review['reviewedMetricsFlags']) != sorted(metrics['reviewRequired'])):
        raise RuntimeError('Benchmark review is missing, incomplete or belongs to different measurements')
    output = ROOT / 'Artifacts/release' / args.version
    output.mkdir(parents=True, exist_ok=True)
    assets = {}
    for name in ['Swift-Liquid-source.tar.gz', 'Liquid.doccarchive.tar.gz']:
        shutil.copyfile(archive_root / name, output / name)
        assets[name] = hashlib.sha256((output / name).read_bytes()).hexdigest()
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, filename='', mode='wb', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for path in sorted(evidence.rglob('*')):
                if path.is_symlink():
                    raise RuntimeError('Unexpected link in qualification evidence')
                if path.is_file():
                    contents = path.read_bytes()
                    member = tarfile.TarInfo('qualification/' + str(path.relative_to(evidence)))
                    member.size = len(contents); member.mode = 0o644; member.mtime = 0
                    archive.addfile(member, io.BytesIO(contents))
    name = 'Swift-Liquid-qualification.tar.gz'
    (output / name).write_bytes(buffer.getvalue())
    assets[name] = hashlib.sha256(buffer.getvalue()).hexdigest()
    (output / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(assets.items())))
    notes = (ROOT / 'Documentation/Releases' / (args.version + '.md')).read_text()
    notes = re.sub(r'\]\((\.\./[^)]+)\)', lambda match: '](https://github.com/ThorFuchs/Swift-Liquid/blob/' + commit + '/' + posixpath.normpath('Documentation/Releases/' + match.group(1)) + ')', notes)
    notes += f'\nQualification: candidate `{commit}`, source tree `{tree}`, tested as `{archive_receipt["candidateCommit"]}`. [Exact-source CI evidence]({args.run_url}).\n'
    (output / 'release-notes.md').write_text(notes)
    manifest = {'version': args.version, 'status': 'prepared-unpublished', 'candidateCommit': commit,
                'qualifiedCommit': archive_receipt['candidateCommit'], 'sourceTree': tree, 'runURL': args.run_url,
                'passedLanes': lanes, 'benchmarkReviewStatus': 'reviewed',
                'benchmarkReviewRequired': matched['reviewRequired'], 'metricsReviewRequired': metrics['reviewRequired'], 'assets': assets}
    (output / 'release.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
