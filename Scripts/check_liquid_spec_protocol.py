#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Black-box adapter contract checks. No peer timing measurements."""
import argparse
import json
import select
import subprocess
import unittest

BINARY = None


class Peer:
    def __init__(self):
        self.process = subprocess.Popen([BINARY], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.sequence = 0

    def request(self, method, params=None):
        self.sequence += 1
        value = {'jsonrpc': '2.0', 'id': self.sequence, 'method': method, 'params': params or {}}
        self.process.stdin.write((json.dumps(value) + '\n').encode())
        self.process.stdin.flush()
        return self.response()

    def response(self):
        if not select.select([self.process.stdout], [], [], 10)[0]:
            raise AssertionError('Adapter response deadline exceeded')
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError('Adapter exited without response')
        return json.loads(line)

    def initialize(self):
        result = self.request('initialize', {'version': '1.0'})['result']
        assert result['features'] == []
        assert result['limits']['active_templates'] == 1

    def compile(self, source, **params):
        return self.request('compile', {'template': source, **params})

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.write(b'{"jsonrpc":"2.0","method":"quit"}\n')
            self.process.stdin.flush()
            self.process.wait(timeout=10)
        assert self.process.returncode == 0
        assert self.process.stdout.read() == b'', 'Notification emitted a response or stdout log'
        assert self.process.stderr.read() == b'', 'Unexpected stderr'
        self.process.stdin.close(); self.process.stdout.close(); self.process.stderr.close()


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.peer = Peer()
        self.addCleanup(self.peer.close)
        self.peer.initialize()

    def test_parse_once_explicit_partials_invocation_clock_and_assign_isolation(self):
        template = self.peer.compile("{{ name }}{% render 'p' %}|{{ 'now' | date: '%F' }}|{{ current_time }}|{% increment n %}", filesystem={'p': 'P'})['result']['template_id']
        for date, name in [('2001-02-03T00:00:00Z', 'A'), ('2004-05-06T00:00:00Z', 'B')]:
            result = self.peer.request('render', {'template_id': template, 'environment': {'name': name}, 'options': {'registers': {'current_time': date}}})['result']
            self.assertEqual(result, {'output': name + 'P|' + date[:10] + '||0', 'errors': []})

    def test_compile_error_is_structured_and_invalidates_previous_slot(self):
        old = self.peer.compile('old')['result']['template_id']
        result = self.peer.compile('x\n{{ 1 | | upcase }}')['result']
        self.assertIsNone(result['template_id']); self.assertEqual(result['error']['type'], 'syntax_error')
        self.assertEqual(result['error']['line'], 2)
        self.assertEqual(self.peer.request('render', {'template_id': old})['error']['code'], -32602)
        new = self.peer.compile('new')['result']['template_id']
        self.assertNotEqual(new, old)
        self.assertEqual(self.peer.request('render', {'template_id': old})['error']['code'], -32602)

    def test_raised_and_recovered_errors_are_distinct_outcomes(self):
        template = self.peer.compile('A{% assign x = items | reject: missing %}B')['result']['template_id']
        raised = self.peer.request('render', {'template_id': template, 'environment': {'items': ['x']}})['result']
        self.assertIsNone(raised['output']); self.assertEqual(raised['error']['type'], 'render_error')
        recovered = self.peer.request('render', {'template_id': template, 'environment': {'items': ['x']}, 'options': {'strict_errors': False}})['result']
        self.assertEqual(recovered['output'], 'AB'); self.assertEqual(len(recovered['errors']), 1)

    def test_finite_native_integer_domain_has_no_arbitrary_double_bridge(self):
        template = self.peer.compile('{{ value }}')['result']['template_id']
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'value': 9007199254740993}})['result']['output'], '9007199254740993')
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'value': 2**63}})['error']['code'], -32602)
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'value': {'_rpc_drop': 'fake'}}})['error']['code'], -32602)

    def test_modes_and_unknown_options_do_not_change_library_defaults(self):
        for mode in ['lax', 'strict', 'strict2']:
            self.assertIn('template_id', self.peer.compile('ok', options={'error_mode': mode})['result'])
        self.assertEqual(self.peer.compile('ok', options={'error_mode': 'future'})['error']['code'], -32602)
        self.assertEqual(self.peer.compile('ok', options={'error_mode': 1})['error']['code'], -32602)
        self.assertEqual(self.peer.compile('ok', options={'line_numbers': 'yes'})['error']['code'], -32602)
        self.assertEqual(self.peer.compile('ok', options={'unknown': True})['error']['code'], -32602)
        template = self.peer.compile('ok')['result']['template_id']
        self.assertEqual(self.peer.request('render', {'template_id': template, 'options': {'resource_limits': {'render_score_limit': 1}}})['error']['code'], -32602)
        self.assertEqual(self.peer.request('render', {'template_id': template, 'options': {'registers': {'current_time': 'bad'}}})['error']['code'], -32602)
        self.assertEqual(self.peer.request('render', {'template_id': template, 'options': {'registers': {'host_value': 1}}})['error']['code'], -32602)

    def test_protocol_errors_and_notifications_are_separate(self):
        self.assertEqual(self.peer.request('unknown')['error']['code'], -32601)
        self.assertEqual(self.peer.request('render', {'template_id': 'absent'})['error']['code'], -32602)
        self.peer.process.stdin.write(b'bad\n'); self.peer.process.stdin.flush()
        self.assertEqual(self.peer.response()['error']['code'], -32700)
        self.peer.process.stdin.write(b'{"jsonrpc":"2.0","method":"unknown"}\n'); self.peer.process.stdin.flush()
        self.assertEqual(self.peer.request('initialize', {'version': '1.0'})['id'], self.peer.sequence)

    def test_cache_source_and_frame_capacities_are_finite(self):
        self.assertEqual(self.peer.compile('x' * 262145)['error']['code'], -32602)
        self.peer.process.stdin.write(b'x' * (1048576 + 1)); self.peer.process.stdin.flush()
        self.assertEqual(self.peer.response()['error']['code'], -32600)
        self.peer.process.wait(timeout=10)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('binary')
    args, other = parser.parse_known_args(); BINARY = args.binary
    unittest.main(argv=[__file__, *other])
