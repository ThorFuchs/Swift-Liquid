#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate authored recovery controls from a clean, pinned Liquid checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

PIN = '4e39ae4cc3da73921923c0669e0fc84a66b2f696'
# Raw ASCII source avoids the host-language backslash interpretation under study.
CASES = [
 ('single_escaped_closer', r"{{ 'a\'b' }}"),
 ('double_escaped_closer', r'{{ "a\"b" }}'),
 ('single_open_lookup', r"{{ 'unterminated }}"),
 ('double_open_lookup', r'{{ "unterminated }}'),
 ('single_open_nested_lookup', r"{{ 'a\n }}"),
 ('single_trailing_quote', r"{{ 'abc' }}'"),
 ('trailing_quote_before_close', r"{{ 'abc' ' }}"),
 ('unclosed_filter_argument', r"{{ 'x' | append: 'unterminated }}"),
 ('filter_stray_quote', r'''{{ 'abc' | append: 'x'" }}'''),
 ('filter_cross_pipe_quote', r'''{{ 'hi there' | split:'t'" | reverse | first }}'''),
 ('filter_two_cross_pipe_quotes', r'''{{ 'abc' | append:"x"" | z" | append: "q" }}'''),
 ('filter_chain_literal', r"{{ 'a\n' | append: '\t' | upcase }}"),
 ('malformed_tail', r"{{ value ! true }}"),
 ('single_tail', r"{{ value ! }}"),
 ('assign_unclosed', r"{% assign x = 'unterminated %}{{ x }}"),
 ('assign_escaped_closer', r"{% assign x = 'a\'b' %}{{ x }}"),
 ('echo_unclosed', r"{% echo 'unterminated %}"),
 ('echo_escaped_closer', r"{% echo 'a\'b' %}"),
 ('multiline_echo_unclosed', "{% liquid\n echo 'unterminated\n%}"),
 ('multiline_assign_escaped', "{% liquid\n assign x = 'a\\'b'\n echo x\n%}"),
 ('adjacent_output_delimiter', r"{{ '}}' }}"),
 ('adjacent_tag_delimiter', r"{% echo '%}' %}"),
 ('multiple_constructs', r"A{{ 'a\'b' }}B{{ 'c\n' }}C"),
 ('no_outer_close', r"{{ 'unterminated"),
 ('valid_backslash_and_opposite', r'''{{ 'a\n"z' }}'''),
]
RUBY = r'''require 'json'
require 'liquid'
abort 'Wrong Liquid version' unless Liquid::VERSION == '5.14.0'
rows = []
JSON.parse(STDIN.read).each do |item|
  source = item.fetch('sourceBytes').pack('C*').force_encoding(Encoding::UTF_8)
  abort 'Invalid UTF-8' unless source.valid_encoding?
  [:lax, :strict, :strict2].each do |mode|
    row = {name: item.fetch('name'), sourceBytes: item.fetch('sourceBytes'), mode: mode.to_s}
    begin
      template = Liquid::Template.parse(source, error_mode: mode, line_numbers: true)
      row[:phase] = 'render'
      begin
        output = template.render!({'unterminated' => 'FOUND', 'a' => {'n' => 'NESTED'}, 'value' => 'ok'}, strict_filters: true)
        row[:outcome] = 'output'; row[:outputBytes] = output.bytes
      rescue StandardError => e
        row[:outcome] = 'render-error'; row[:errorClass] = e.class.name; row[:message] = e.message
        row[:line] = e.respond_to?(:line_number) ? e.line_number : nil
      end
    rescue StandardError => e
      row[:phase] = 'parse'; row[:outcome] = 'parse-error'; row[:errorClass] = e.class.name; row[:message] = e.message
      row[:line] = e.respond_to?(:line_number) ? e.line_number : nil
    end
    rows << row
  end
end
puts JSON.generate(rows)
'''

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference-path', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    def git(*parts):
        return subprocess.check_output(['git', '-C', str(args.reference_path), *parts], text=True).strip()
    if git('rev-parse', 'HEAD') != PIN or git('status', '--porcelain'):
        raise ValueError('reference must be clean and pinned')
    if args.output.exists():
        raise ValueError('refusing to overwrite existing evidence')
    vectors = [{'name': name, 'sourceBytes': list(source.encode('utf-8'))} for name, source in CASES]
    env = dict(os.environ, RUBYLIB=str(args.reference_path.resolve() / 'lib'), TZ='UTC')
    result = subprocess.run(['ruby', '-e', RUBY], input=json.dumps(vectors).encode(), capture_output=True, env=env, check=True)
    rows = json.loads(result.stdout)
    if len(rows) != 3 * len(CASES):
        raise ValueError('reference case count changed')
    data = {'schemaVersion': 1, 'referenceCommit': PIN, 'referenceVersion': '5.14.0', 'context': {'unterminated': 'FOUND', 'a': {'n': 'NESTED'}, 'value': 'ok'}, 'cases': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False)
        stream.write('\n')
    print(json.dumps({'vectors': len(CASES), 'variants': len(rows), 'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest()}))

if __name__ == '__main__':
    main()
