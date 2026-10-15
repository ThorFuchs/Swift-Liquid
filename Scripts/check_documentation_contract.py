#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Negative regressions for documentation, published API and site admission."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from documentation_catalog import public_symbols, verify_comments, verify_public_baseline, readme_examples
from build_documentation_site import verify_site, verify_docc_routes, prepare_navigation_index


def symbol():
    return {'identifier': {'precise': 'example'}, 'pathComponents': ['Example', 'init(value:)'],
            'docComment': {'lines': [{'text': 'Creates an example.'}, {'text': '- Parameter value: Input value.'}]},
            'functionSignature': {'parameters': [{'name': 'value'}]},
            'declarationFragments': [{'spelling': 'init(value: Int)'}]}


class DocumentationContractTests(unittest.TestCase):
    def test_missing_summary_or_named_parameter_cannot_pass(self):
        self.assertEqual(verify_comments([symbol()])['errors'], [])
        for lines in [[], [{'text': '- Parameter value: Input value.'}], [{'text': 'Creates an example.'}]]:
            changed = symbol(); changed['docComment']['lines'] = lines
            self.assertTrue(verify_comments([changed])['errors'])

    def test_synthesis_does_not_disguise_an_empty_or_foreign_graph(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); graph = root/'graph.json'
            source = root/'Sources/Liquid/Example.swift'; source.parent.mkdir(parents=True); source.write_text('')
            item = dict(symbol(), location={'uri': source.as_uri()}, kind={'identifier': 'swift.struct'}, accessLevel='public')
            data = {'module': {'name': 'Liquid'}, 'symbols': [item]}
            graph.write_text(json.dumps(data)); self.assertEqual(len(public_symbols(graph, root)), 1)
            for invalid in [{'module': {'name': 'Liquid'}, 'symbols': []},
                            {'module': {'name': 'Liquid'}, 'symbols': [symbol()]},
                            {'module': {'name': 'Other'}, 'symbols': [item]}]:
                graph.write_text(json.dumps(invalid))
                with self.assertRaises(ValueError): public_symbols(graph, root)
            item['location']['uri'] = (root.parent/'Foreign.swift').as_uri()
            graph.write_text(json.dumps(data))
            with self.assertRaises(ValueError): public_symbols(graph, root)

    def test_published_declarations_cannot_disappear_or_change(self):
        baseline = {'release': '1.3.0', 'commit': 'published', 'declarations': [
            {'identifier': 'example', 'path': ['Example'], 'declaration': 'init(value: Int)'}]}
        self.assertEqual(verify_public_baseline([symbol()], baseline)['errors'], [])
        self.assertTrue(verify_public_baseline([], baseline)['errors'])
        changed = symbol(); changed['declarationFragments'][0]['spelling'] = 'init(value: String)'
        self.assertTrue(verify_public_baseline([changed], baseline)['errors'])
        with self.assertRaises(ValueError): verify_public_baseline([], dict(baseline, declarations=[]))
        duplicate = copy.deepcopy(baseline); duplicate['declarations'] *= 2
        with self.assertRaises(ValueError): verify_public_baseline([symbol()], duplicate)

    def test_readme_examples_retain_scopes_and_expected_output(self):
        text = '```swift\n.package(url: "example", from: "1.0.0")\n```\n```swift\n.product(name: "Liquid")\n```\n```swift\nimport Liquid\nprint(42) // 42\n```'
        source, count, expected = readme_examples(text)
        self.assertIn('static func main() async throws', source)
        self.assertIn('do {', source); self.assertEqual(count, 1); self.assertEqual(expected, '42\n')
        for invalid in ['', text.replace(' // 42', ''), text.replace('```swift\n.package', '```text\n.package'),
                        text.replace('import Liquid\n', ''), text + '\n```swift\nimport Liquid\nlet unused = 1\n```']:
            with self.assertRaises(ValueError): readme_examples(invalid)

    def test_missing_routes_and_encoded_escapes_cannot_publish(self):
        with tempfile.TemporaryDirectory() as temporary:
            site = Path(temporary); (site/'guide').mkdir(); (site/'guide/index.html').write_text('<p>Guide</p>')
            index = site/'index.html'; index.write_text('<a href="/Swift-Liquid/guide/">Guide</a>')
            self.assertEqual(verify_site(site), 1)
            for link in ['/Swift-Liquid/missing/', '/wrong-base/guide/', '/Swift-Liquid/%2e%2e/outside.html']:
                index.write_text('<a href="'+link+'">Guide</a>')
                with self.assertRaises(ValueError): verify_site(site)
            index.write_text('<img src="missing.png">')
            with self.assertRaises(ValueError): verify_site(site)

    def test_source_links_and_private_markers_cannot_enter_site(self):
        with tempfile.TemporaryDirectory() as temporary:
            site = Path(temporary); index = site/'index.html'
            index.write_text('<p>/Users/thorfuchs/private-record</p>')
            with self.assertRaises(ValueError): verify_site(site)
            index.write_text('<p>Guide</p>'); (site/'linked').symlink_to(index)
            with self.assertRaises(ValueError): verify_site(site)

    def test_legacy_article_navigator_uses_the_compiler_index(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary); (archive/'index').mkdir()
            source = archive/'index/index.json'
            source.write_text('{"interfaceLanguages":{"swift":[{"title":"Liquid"}]}}')
            prepare_navigation_index(archive)
            self.assertEqual((archive/'index/documentation/index.json').read_bytes(), source.read_bytes())
            source.write_text('{"interfaceLanguages":{}}')
            with self.assertRaises(ValueError): prepare_navigation_index(archive)

    def test_client_rendered_reference_routes_need_html_and_page_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            site = Path(temporary); (site/'index').mkdir()
            (site/'index/index.json').write_text('{"interfaceLanguages":{"swift":[]}}')
            data = site/'data/documentation/liquid.json'; data.parent.mkdir(parents=True)
            data.write_text('{"variants":[{"paths":["/documentation/liquid"]}]}')
            with self.assertRaises(ValueError): verify_docc_routes(site)
            page = site/'documentation/liquid/index.html'; page.parent.mkdir(parents=True); page.write_text('Liquid')
            self.assertEqual(verify_docc_routes(site), 1)
            data.write_text('{"references":{"missing":{"url":"/documentation/liquid/missing"}}}')
            with self.assertRaises(ValueError): verify_docc_routes(site)
            data.write_text('{"variants":[{"paths":["/documentation/%2e%2e/%2e%2e/escape"]}]}')
            with self.assertRaises(ValueError): verify_docc_routes(site)


if __name__ == '__main__':
    unittest.main()
