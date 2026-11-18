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

    def test_host_names_and_absent_filesystem_are_distinct(self):
        root = "{% include 'CARD' %}"
        template = self.peer.compile(root, filesystem={'card.liquid': 'found'})['result']['template_id']
        result = self.peer.request('render', {'template_id': template})['result']
        self.assertEqual(result['output'], 'found')
        for extra, expected in [({}, 'does not allow includes'), ({'filesystem': {}}, 'Could not find asset')]:
            template = self.peer.compile(root, **extra)['result']['template_id']
            result = self.peer.request('render', {'template_id': template})['result']
            self.assertIn(expected, result['error']['message'])

    def test_compile_error_is_structured_and_invalidates_previous_slot(self):
        old = self.peer.compile('old')['result']['template_id']
        result = self.peer.compile('x\n{{ 1 | | upcase }}', options={'error_mode': 'strict2'})['result']
        self.assertIsNone(result['template_id']); self.assertEqual(result['error']['type'], 'syntax_error')
        self.assertEqual(result['error']['line'], 2)
        self.assertEqual(self.peer.request('render', {'template_id': old})['error']['code'], -32602)
        new = self.peer.compile('new')['result']['template_id']
        self.assertNotEqual(new, old)
        self.assertEqual(self.peer.request('render', {'template_id': old})['error']['code'], -32602)

    def test_selected_partial_syntax_failure_occurs_during_render(self):
        compiled = self.peer.compile("{% render 'broken' %}", filesystem={'broken': 'first\n{% if true'})['result']
        self.assertIsNotNone(compiled['template_id'])
        rendered = self.peer.request('render', {'template_id': compiled['template_id']})['result']
        self.assertIsNone(rendered['output'])
        self.assertEqual(rendered['error']['type'], 'syntax_error')
        self.assertEqual(rendered['error']['line'], 2)

    def test_default_lax_mode_accepts_empty_filter_segments(self):
        template = self.peer.compile("{{ 'hello' || upcase }}")['result']['template_id']
        result = self.peer.request('render', {'template_id': template})['result']
        self.assertEqual(result, {'output': 'HELLO', 'errors': []})

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

    def test_portable_method_drop_is_explicit_bounded_and_not_a_callback(self):
        template = self.peer.compile("{{ drop.echo_42 }}|{{ drop.square_5 }}|{{ drop.double_7 }}|{{ drop[key] }}|[{{ drop.secret }}]|[{{ drop.echo_bad }}]")['result']['template_id']
        marker = {'_instantiate': 'MethodDrop', 'params': {}}
        rendered = self.peer.request('render', {'template_id': template, 'environment': {'drop': marker, 'key': 'square_12'}})['result']
        self.assertEqual(rendered, {'output': '42|25|14|144|[]|[]', 'errors': []})
        for invalid in [{'_instantiate': 'OtherDrop', 'params': {}},
                        {'_instantiate': 'MethodDrop', 'params': {'extra': 1}},
                        {'_instantiate': 'MethodDrop', 'params': {}, 'extra': 1},
                        {'nested': marker}, {'_rpc_drop': 'external'}]:
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'drop': invalid}})['error']['code'], -32602)
        overflow = self.peer.compile('{{ drop.square_9223372036854775807 }}')['result']['template_id']
        error = self.peer.request('render', {'template_id': overflow, 'environment': {'drop': marker}})['result']
        self.assertIsNone(error['output']); self.assertEqual(error['error']['type'], 'domain_error')
        template = self.peer.compile('{{ drop.echo_42 }}')['result']['template_id']
        recovered = self.peer.request('render', {'template_id': template, 'environment': {'drop': marker}, 'options': {'strict_errors': False}})['result']
        self.assertIsNone(recovered['output']); self.assertEqual(recovered['error']['type'], 'operational_error')

    def test_portable_index_drop_keeps_string_integer_and_other_keys_distinct(self):
        source = "{{ drop[0] }}|{{ drop[1] }}|{{ drop[-1] }}|{{ drop[-6] }}|{{ drop[-7] }}|{{ drop['0'] }}|[{{ drop[''] }}]|{{ drop.foo }}|{{ drop[true] }}|{{ drop[1.0] }}|{{ drop[1.5] }}|{{ drop[missing] }}"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        marker = {'_instantiate': 'IndexDrop', 'params': {}}
        result = self.peer.request('render', {'template_id': template, 'environment': {'drop': marker}})['result']
        self.assertEqual(result, {'output': 'zero|one|five|zero|unknown|0|[]|foo|unknown|unknown|unknown|unknown', 'errors': []})
        for invalid in [{'_instantiate': 'IndexDrop', 'params': {'extra': 1}}, {'nested': marker}]:
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'drop': invalid}})['error']['code'], -32602)

    def test_portable_boolean_drop_keeps_value_and_object_boundaries(self):
        source = "{{ drop }}|{% if drop %}T{% else %}F{% endif %}|{% if drop == blank %}B{% endif %}|{% if drop == empty %}E{% endif %}|{{ drop | default: 'x' }}|{{ drop | default: 'x', allow_false: true }}|{{ drop | size }}|[{{ drop.value }}]"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        for value, expected in [(True, 'true|T|||true|true|0|[]'), (False, 'false|F|B||x|false|0|[]')]:
            marker = {'_instantiate': 'BooleanDrop', 'params': {'value': value}}
            result = self.peer.request('render', {'template_id': template, 'environment': {'drop': marker}})['result']
            self.assertEqual(result, {'output': expected, 'errors': []})
        for params in [{}, {'value': 1}, {'value': None}, {'value': True, 'extra': 1}]:
            marker = {'_instantiate': 'BooleanDrop', 'params': params}
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'drop': marker}})['error']['code'], -32602)

    def test_portable_number_drop_keeps_numeric_and_object_boundaries(self):
        source = "{{ drop }}|{% if drop %}T{% else %}F{% endif %}|{{ drop | plus: 1 }}|{{ drop | size }}|[{{ drop.size }}]|{% assign x = drop | default: 'no' %}[{{ x.size }}]"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        for value, expected in [(0, '0|T|1|0|[]|[]'), (41, '41|T|42|0|[]|[]'), (-2, '-2|T|-1|0|[]|[]')]:
            marker = {'_instantiate': 'NumberDrop', 'params': {'value': value}}
            result = self.peer.request('render', {'template_id': template, 'environment': {'drop': marker}})['result']
            self.assertEqual(result, {'output': expected, 'errors': []})
        for params in [{}, {'value': True}, {'value': 1.5}, {'value': None}, {'value': 1, 'extra': 1}]:
            marker = {'_instantiate': 'NumberDrop', 'params': params}
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'drop': marker}})['error']['code'], -32602)

    def test_portable_string_drop_preserves_object_and_array_identity(self):
        source = "{{ d }}|{{ d | size }}|[{{ d.size }}]|{% assign u = a | uniq %}{{ u }}|[{{ u[0].size }}]"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        drop = lambda value: {'_instantiate': 'StringDrop', 'params': {'value': value}}
        for array, expected in [([drop('foo'), 'foo', drop('bar')], 'text|0|[]|foobar|[]'),
                                (['foo', drop('foo'), drop('bar')], 'text|0|[]|foobar|[3]')]:
            result = self.peer.request('render', {'template_id': template, 'environment': {'d': drop('text'), 'a': array}})['result']
            self.assertEqual(result, {'output': expected, 'errors': []})
        nil_template = self.peer.compile("{% if d %}T{% else %}F{% endif %}|{% if d == blank %}B{% endif %}|{% if d == empty %}E{% endif %}", options={'error_mode': 'strict2'})['result']['template_id']
        for marker in [drop(None), {'_instantiate': 'StringDrop', 'params': {}}]:
            result = self.peer.request('render', {'template_id': nil_template, 'environment': {'d': marker}})['result']
            self.assertEqual(result, {'output': 'F|B|', 'errors': []})
        for params in [{'value': 1}, {'value': True}, {'value': 'x', 'extra': 1}, {'bad': None}]:
            marker = {'_instantiate': 'StringDrop', 'params': params}
            self.assertEqual(self.peer.request('render', {'template_id': nil_template, 'environment': {'d': marker}})['error']['code'], -32602)
        for invalid in [[{'nested': drop('x')}], [[drop('x')]], [drop('x'), {'_instantiate': 'NumberDrop', 'params': {'value': 1}}]]:
            self.assertEqual(self.peer.request('render', {'template_id': nil_template, 'environment': {'a': invalid}})['error']['code'], -32602)

    def test_portable_sequence_drop_has_bounded_object_iteration(self):
        source = "{{ d.size }}|{{ d.first }}|{{ d.last }}|[{{ d[0] }}]|{{ d | size }}|{{ d | join: ',' }}|{% for x in d %}{{ forloop.index }}:{{ x }};{% endfor %}|{% assign x = d %}{{ x.last }}"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        marker = {'_instantiate': 'SequenceDrop', 'params': {}}
        result = self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['result']
        self.assertEqual(result, {'output': '3|first|third|[]|3|first,second,third|1:first;2:second;3:third;|third', 'errors': []})
        for bad in [{'extra': 1}, {'values': ['changed']}]:
            marker = {'_instantiate': 'SequenceDrop', 'params': bad}
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['error']['code'], -32602)
        nested = {'_instantiate': 'SequenceDrop', 'params': {}}
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': [nested]}})['error']['code'], -32602)

    def test_portable_nested_drop_preserves_identity_and_bounds(self):
        source = "{{ d.nested.square.nested }}|{{ d.square.square }}|[{{ d.value }}]|{{ d | plus: 1 }}|{{ 5 | plus: d }}"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        marker = {'_instantiate': 'NestedDrop', 'params': {'value': 3}}
        result = self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['result']
        self.assertEqual(result, {'output': '9|81|[]|1|5', 'errors': []})
        for invalid in [{}, {'value': True}, {'value': '3'}, {'value': 3, 'extra': 1}]:
            marker = {'_instantiate': 'NestedDrop', 'params': invalid}
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['error']['code'], -32602)
        marker = {'_instantiate': 'NestedDrop', 'params': {'value': 3}}
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': [marker]}})['error']['code'], -32602)
        marker = {'_instantiate': 'NestedDrop', 'params': {'value': 9223372036854775807}}
        self.assertIsNotNone(self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['result']['error'])

    def test_portable_error_drop_recovers_through_explicit_partial_binding(self):
        template = self.peer.compile("{% render 'foo' with errors %}", options={'error_mode': 'strict2'}, filesystem={'foo': '{{ foo.standard_error }}'})['result']['template_id']
        marker = {'_instantiate': 'ErrorDrop', 'params': {}}
        result = self.peer.request('render', {'template_id': template, 'environment': {'errors': marker}, 'options': {'strict_errors': False}})['result']
        self.assertEqual(result['output'], 'Liquid error (foo line 1): ErrorDrop: access triggered an error')
        self.assertEqual(len(result['errors']), 1)
        self.assertEqual(result['errors'][0], {'type': 'render_error', 'message': 'ErrorDrop: access triggered an error', 'line': 1, 'template_name': 'foo'})
        self.assertIsNone(self.peer.request('render', {'template_id': template, 'environment': {'errors': marker}})['result']['output'])

    def test_portable_error_drop_returns_render_error_without_hiding_protocol_failures(self):
        template = self.peer.compile("{{ d.foo }}", options={'error_mode': 'strict2'})['result']['template_id']
        marker = {'_instantiate': 'ErrorDrop', 'params': {}}
        result = self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['result']
        self.assertIsNone(result['output'])
        self.assertEqual(result['error']['type'], 'render_error')
        self.assertIn('ErrorDrop: access triggered an error', result['error']['message'])
        for bad in [{'extra': 1}, {'value': None}]:
            marker = {'_instantiate': 'ErrorDrop', 'params': bad}
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['error']['code'], -32602)
        marker = {'_instantiate': 'ErrorDrop', 'params': {}}
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': [marker]}})['error']['code'], -32602)
        good = self.peer.compile('ok')['result']['template_id']
        self.assertEqual(self.peer.request('render', {'template_id': good})['result']['output'], 'ok')

    def test_portable_opaque_drop_keeps_identity_and_rejects_other_shapes(self):
        source = "{{ d }}|[{{ d.size }}]|{% if d %}T{% endif %}|{% if d == empty %}E{% else %}N{% endif %}|{% if d == 'opaque' %}E{% else %}N{% endif %}|{% if d == e %}E{% else %}N{% endif %}|{% assign x = d.to_liquid %}{% if d == x %}E{% endif %}|{{ d | size }}|{{ d | upcase }}|{{ d | plus: 1 }}"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        marker = {'_instantiate': 'OpaqueDrop', 'params': {}}
        result = self.peer.request('render', {'template_id': template, 'environment': {'d': marker, 'e': marker}})['result']
        self.assertEqual(result, {'output': 'opaque|[]|T|N|N|N|E|0|OPAQUE|1', 'errors': []})
        for bad in [{'value': None}, {'value': 'opaque'}, {'extra': 1}]:
            marker = {'_instantiate': 'OpaqueDrop', 'params': bad}
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['error']['code'], -32602)
        marker = {'_instantiate': 'OpaqueDrop', 'params': {}}
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': [marker]}})['error']['code'], -32602)
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': {'_instantiate': 'OpaqueDrop'}}})['error']['code'], -32602)

    def test_portable_nil_drop_is_present_null_and_rejects_other_shapes(self):
        source = "[{{ d }}]|{% if d %}T{% else %}F{% endif %}|{% if d == empty %}E{% else %}N{% endif %}|{% if d == blank %}B{% endif %}|{{ d | default: 'fallback' }}|{{ d | plus: 1 }}"
        template = self.peer.compile(source, options={'error_mode': 'strict2'})['result']['template_id']
        marker = {'_instantiate': 'NilDrop', 'params': {}}
        result = self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['result']
        self.assertEqual(result, {'output': '[]|F|N|B|fallback|1', 'errors': []})
        ordinary = self.peer.request('render', {'template_id': template, 'environment': {'d': None}})['result']
        self.assertEqual(result, ordinary)
        for bad in [{'value': None}, {'value': False}, {'extra': 1}]:
            marker = {'_instantiate': 'NilDrop', 'params': bad}
            self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': marker}})['error']['code'], -32602)
        marker = {'_instantiate': 'NilDrop', 'params': {}}
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': [marker]}})['error']['code'], -32602)
        self.assertEqual(self.peer.request('render', {'template_id': template, 'environment': {'d': {'_instantiate': 'NilDrop'}}})['error']['code'], -32602)

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
