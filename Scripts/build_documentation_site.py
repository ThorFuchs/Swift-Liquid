#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Adapted from Swift-JSON's documentation site builder; Copyright 2026 Thor Fuchs.
# Modified for one Liquid catalog, stable existing routes and source-bound receipts.
"""Build a base-path-aware landing page around the qualified native DocC catalog."""
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import unquote, urlsplit
from ci import ROOT, source_snapshot

BASE_PATH = '/Swift-Liquid'
REPOSITORY = 'https://github.com/ThorFuchs/Swift-Liquid'
GUIDES = ['gettingstarted', 'commandline', 'testingandconformance', 'renderingandpartials',
          'templateinspection', 'partialdependencies', 'rendermetrics', 'limitsandconcurrency']
GUIDE_PATH = 'documentation/documentation'


def prepare_navigation_index(archive):
    """Retain legacy article URLs across DocC Render's optional-locale routing.

    On Swift 6.4, /documentation/documentation/article is interpreted with a
    `documentation` locale when fetching the navigator. Serve the unchanged
    catalog index at that path too; never rewrite generated JavaScript or URLs.
    """
    source = archive / 'index/index.json'
    index = json.loads(source.read_text())
    if not index.get('interfaceLanguages', {}).get('swift'):
        raise ValueError('Missing Swift DocC navigator entries')
    alias = archive / 'index/documentation/index.json'
    alias.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, alias)


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        self.urls.extend(value for key, value in attrs if key in ('href', 'src') and value)


def verify_site(site):
    root = site.resolve()
    count = 0
    for path in sorted(site.rglob('*')):
        if path.is_symlink():
            raise ValueError('Unexpected link in documentation site: ' + str(path.relative_to(site)))
        if not path.is_file():
            continue
        if path.suffix in ('.html', '.json', '.js', '.css', '.txt', '.xml'):
            text = path.read_text()
            if re.search(r'/Users/thorfuchs/|github_pat_[A-Za-z0-9_]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN .*PRIVATE KEY-----', text):
                raise ValueError('Private content marker in documentation site')
        if path.suffix != '.html':
            continue
        links = Links(); links.feed(path.read_text())
        for raw in links.urls:
            url = urlsplit(raw)
            if url.scheme or url.netloc or not url.path:
                continue
            target = unquote(url.path)
            if target.startswith('/'):
                if not target.startswith(BASE_PATH + '/'):
                    raise ValueError('Local link outside project base path: ' + raw)
                candidate = site / target[len(BASE_PATH) + 1:]
            else:
                candidate = path.parent / target
            candidate = candidate.resolve()
            if candidate != root and root not in candidate.parents:
                raise ValueError('Local documentation link escapes site: ' + raw)
            if not candidate.is_file() and not (candidate / 'index.html').is_file():
                raise ValueError('Missing local documentation route or asset: ' + raw)
            count += 1
    return count


def verify_docc_routes(site):
    """Check routes that the client renders from JSON rather than HTML anchors."""
    routes = set()
    pages = list((site / 'data/documentation').rglob('*.json'))
    if not pages:
        raise ValueError('Missing DocC page data')
    for page in pages:
        data = json.loads(page.read_text())
        for reference in data.get('references', {}).values():
            url = reference.get('url', '')
            if url.startswith('/documentation/'):
                routes.add(url)
        for variant in data.get('variants', []):
            routes.update(variant.get('paths', []))
    def collect(entries):
        for entry in entries:
            if 'path' in entry:
                routes.add(entry['path'])
            collect(entry.get('children', []))
    index = json.loads((site / 'index/index.json').read_text())
    collect(index.get('interfaceLanguages', {}).get('swift', []))
    for route in sorted(routes):
        path = unquote(urlsplit(route).path).lstrip('/')
        target = (site / path).resolve()
        if site.resolve() not in target.parents:
            raise ValueError('DocC JSON route escapes site: ' + route)
        if not (target / 'index.html').is_file() or not (site / 'data' / (path + '.json')).is_file():
            raise ValueError('Missing DocC JSON route or page data: ' + route)
    return len(routes)


def landing(commit):
    source = (f'<a href="{REPOSITORY}/commit/{commit}"><code>{commit[:12]}</code></a>'
              if commit else 'Local preview with uncommitted source')
    cards = [
        ('Start with Swift', 'Install the package, supply typed context and render your first template.', 'gettingstarted', 'Getting started'),
        ('Use the command line', 'Render files, validate syntax and write explicit analysis or metrics reports.', 'commandline', 'CLI guide'),
        ('Render and compose', 'Reuse parsed templates and pass partials explicitly, with clear scope and escaping rules.', 'renderingandpartials', 'Rendering and partials'),
        ('Inspect before rendering', 'Read syntactic references and bounded partial dependencies without evaluating the template.', 'partialdependencies', 'Partial dependencies'),
        ('Measure and bound work', 'Understand opt-in timing, cumulative logical quotas and cooperative cancellation.', 'rendermetrics', 'Render metrics'),
        ('Review compatibility', 'Follow independent fixtures, Shopify reference comparisons and the limits of qualification.', 'testingandconformance', 'Testing and conformance')]
    content = ''.join(f'<article class="card"><h2>{title}</h2><p>{description}</p><a href="{BASE_PATH}/{GUIDE_PATH}/{slug}/">{label} <span aria-hidden="true">→</span></a></article>' for title, description, slug, label in cards)
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Swift-Liquid Documentation</title>
<meta name="description" content="Shopify Liquid templates for Swift 6.4. Typed values, reusable templates, explicit partials, custom filters, inspection and opt-in metrics.">
<link rel="canonical" href="https://thorfuchs.github.io{BASE_PATH}/">
<link rel="icon" href="{BASE_PATH}/favicon.svg" type="image/svg+xml">
<style>
:root {{ color-scheme: light dark; --background:#f7f9fc; --surface:#fff; --text:#182335; --muted:#4e5d73; --link:#135dc7; --border:#dce3ed; }}
* {{ box-sizing:border-box; }} body {{ margin:0; background:var(--background); color:var(--text); font:17px/1.65 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }}
a {{ color:var(--link); text-underline-offset:.18em; }} a:hover {{ text-decoration-thickness:2px; }} a:focus-visible {{ outline:3px solid var(--link); outline-offset:5px; border-radius:2px; }}
.skip {{ position:absolute; top:-100px; left:1rem; padding:.6rem 1rem; background:var(--surface); }} .skip:focus {{ top:1rem; }}
.container {{ max-width:1080px; margin:0 auto; padding:0 28px; }} header {{ border-bottom:1px solid var(--border); background:var(--surface); }}
nav {{ display:flex; align-items:center; justify-content:space-between; gap:24px; min-height:76px; }} .brand {{ font-weight:700; color:var(--text); text-decoration:none; letter-spacing:-.025em; }} .nav-links {{ display:flex; flex-wrap:wrap; gap:24px; font-size:15px; }}
main {{ padding-top:58px; }} .eyebrow {{ font-size:13px; font-weight:650; text-transform:uppercase; letter-spacing:.1em; color:var(--muted); }}
h1 {{ font-size:clamp(36px,6vw,54px); line-height:1.12; letter-spacing:-.045em; margin:16px 0 22px; }} .intro {{ max-width:790px; font-size:21px; line-height:1.6; color:var(--muted); }}
.baseline {{ margin:22px 0 30px; font-size:15px; color:var(--muted); }} .primary {{ display:inline-block; margin:0 0 36px; font-weight:650; }}
.grid {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:20px; }} .card {{ display:flex; flex-direction:column; align-items:flex-start; padding:28px; border:1px solid var(--border); border-radius:14px; background:var(--surface); }}
.card h2 {{ font-size:25px; margin:0; letter-spacing:-.025em; }} .card p {{ color:var(--muted); margin:14px 0 22px; flex:1; }} .card>a {{ font-size:15px; }}
.details {{ margin:42px 0 48px; max-width:840px; }} .details h2 {{ font-size:22px; margin-bottom:12px; }} .details p {{ color:var(--muted); }}
footer {{ border-top:1px solid var(--border); padding:24px 0 36px; color:var(--muted); font-size:14px; }} code {{ font-size:.95em; }}
@media(prefers-color-scheme:dark) {{ :root {{ --background:#111823; --surface:#192332; --text:#e8edf5; --muted:#b2bfd1; --link:#88b9ff; --border:#33435a; }} }}
@media(max-width:650px) {{ .container {{ padding:0 20px; }} nav {{ align-items:flex-start; flex-direction:column; gap:8px; padding-top:16px; padding-bottom:16px; }} main {{ padding-top:38px; }} .grid {{ grid-template-columns:1fr; }} .card {{ padding:24px; }} .intro {{ font-size:19px; }} }}
</style></head><body>
<a class="skip" href="#content">Skip to documentation</a>
<header><nav class="container" aria-label="Main navigation"><a class="brand" href="{BASE_PATH}/">Swift-Liquid</a><div class="nav-links"><a href="{REPOSITORY}#installation">Install</a><a href="{BASE_PATH}/documentation/liquid/">API reference</a><a href="{REPOSITORY}">GitHub</a></div></nav></header>
<main id="content" class="container"><p class="eyebrow">Public Swift documentation</p><h1>Liquid templates, written in Swift.</h1>
<p class="intro">Render with typed values and reusable templates. Compose explicit partials, add engine-scoped filters, inspect dependencies and measure the work you choose to observe.</p>
<p class="baseline">Swift 6.4+ · Swift language mode 6 · Liquid library and liquid CLI · No root package dependencies</p>
<a class="primary" href="{BASE_PATH}/documentation/liquid/">Explore the complete API reference <span aria-hidden="true">→</span></a>
<section class="grid" aria-label="Documentation guides">{content}</section>
<section class="details"><h2>A focused engine, with inspectable evidence</h2><p>The language target is <a href="https://github.com/Shopify/liquid">Shopify's open-source Liquid core</a>. Qualification combines the independent <a href="https://github.com/jg-rp/golden-liquid">Golden Liquid corpus</a>, pinned Ruby reference comparisons, public consumers, Swift Testing and sanitizers. Published evidence distinguishes successful renders, expected failures and unsupported boundaries.</p>
<p>Runtime qualification covers macOS with separate Apple simulator compilation. Read the <a href="{BASE_PATH}/{GUIDE_PATH}/limitsandconcurrency/">limits and concurrency contract</a> before selecting an operation profile.</p>
<p>These pages track <code>main</code> and deploy after all eight release lanes pass. For a released version's exact documentation, use its <a href="{REPOSITORY}/releases">compiled DocC archive</a>. Build source: {source}. <a href="{BASE_PATH}/build-info.json">Build information</a>.</p></section></main>
<footer><div class="container">Maintained by <a href="https://github.com/ThorFuchs">Thorsten Fuchs</a> · <a href="{REPOSITORY}/blob/main/LICENSE">Apache-2.0</a> · <a href="{REPOSITORY}/blob/main/THIRD_PARTY_NOTICES.md">Upstream notices</a> · <a href="{REPOSITORY}/security/advisories/new">Private security reporting</a></div></footer>
</body></html>'''


def build_site(archive, output, toolchain):
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(archive, output, symlinks=True)
    top = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=ROOT, capture_output=True, text=True)
    clean = top.returncode == 0 and Path(top.stdout.strip()).resolve() == ROOT
    if clean:
        clean = not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip()
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() if clean else None
    inventory = source_snapshot()
    run_id = os.environ.get('GITHUB_RUN_ID', '')
    info = {'schemaVersion': 1, 'documentationTracks': 'main', 'sourceCommit': commit,
            'sourceInventorySHA256': hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest(),
            'toolchain': toolchain.splitlines()[0],
            'runURL': REPOSITORY + '/actions/runs/' + run_id if run_id.isdigit() else None,
            'sourceState': 'clean' if clean else 'local-preview'}
    (output / 'build-info.json').write_text(json.dumps(info, indent=2) + '\n')
    (output / 'index.html').write_text(landing(commit))
    if (output / 'index/documentation/index.json').read_bytes() != (output / 'index/index.json').read_bytes():
        raise ValueError('Legacy article navigator differs from the catalog index')
    for route in ['documentation/liquid'] + [GUIDE_PATH + '/' + slug for slug in GUIDES]:
        folder = output / route
        if not (folder / 'index.html').is_file():
            raise ValueError('Missing qualified DocC route: ' + str(folder.relative_to(output)))
        if not (output / 'data' / (route + '.json')).is_file():
            raise ValueError('Missing qualified DocC page data: ' + route)
    links = verify_site(output)
    docc_routes = verify_docc_routes(output)
    files = [{'path': str(p.relative_to(output)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
             for p in sorted(output.rglob('*')) if p.is_file()]
    return {'status': 'passed', 'basePath': BASE_PATH, 'qualifiedGuideRoutes': GUIDES,
            'verifiedLocalLinks': links, 'verifiedDocCRoutes': docc_routes,
            'buildInformation': info, 'files': files}
