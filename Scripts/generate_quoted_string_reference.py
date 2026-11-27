#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate authored byte-vector expectations using the pinned Ruby reference."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

PIN = '4e39ae4cc3da73921923c0669e0fc84a66b2f696'

def vectors():
    result = []
    for quote, label, opposite in [(39, 'single', 34), (34, 'double', 39)]:
        def output(inner, close=True):
            return [123, 123, 32, quote] + inner + ([quote] if close else []) + [32, 125, 125]
        cases = [
            ('backslash_n', [97, 92, 110, 98], True),
            ('backslash_t', [97, 92, 116, 98], True),
            ('backslash_r', [97, 92, 114, 98], True),
            ('unknown_escape', [97, 92, 113, 98], True),
            ('two_backslashes', [97, 92, 92, 98], True),
            ('three_backslashes', [97, 92, 92, 92, 98], True),
            ('backslash_before_closer', [97, 92], True),
            ('repeated_before_closer', [97, 92, 92], True),
            ('escaped_delimiter', [97, 92, quote, 98], True),
            ('unterminated', [97, 92, 110], False),
            ('actual_newline', [97, 10, 98], True),
            ('actual_tab', [97, 9, 98], True),
            ('actual_carriage_return', [97, 13, 98], True),
            ('opposite_quote', [97, opposite, 98], True),
            ('unicode_backslash', [195, 169, 92, 110, 240, 159, 152, 128], True),
            ('empty', [], True),
        ]
        for name, inner, close in cases:
            result.append({'name': label + '_' + name, 'sourceBytes': output(inner, close)})
    return result

RUBY = r'''require 'json'
require 'liquid'
abort 'Wrong Liquid version' unless Liquid::VERSION == '5.14.0'
inputs = JSON.parse(STDIN.read)
rows = []
inputs.each do |item|
  source = item.fetch('sourceBytes').pack('C*').force_encoding(Encoding::UTF_8)
  abort 'Invalid UTF-8 test vector' unless source.valid_encoding?
  [:lax, :strict, :strict2].each do |mode|
    row = {name: item.fetch('name'), sourceBytes: item.fetch('sourceBytes'), mode: mode.to_s}
    begin
      template = Liquid::Template.parse(source, error_mode: mode, line_numbers: true)
      row[:phase] = 'render'
      begin
        output = template.render!
        row[:outcome] = 'output'; row[:outputBytes] = output.bytes
      rescue StandardError => error
        row[:outcome] = 'render-error'; row[:errorClass] = error.class.name; row[:message] = error.message
        row[:line] = error.respond_to?(:line_number) ? error.line_number : nil
      end
    rescue StandardError => error
      row[:phase] = 'parse'; row[:outcome] = 'parse-error'; row[:errorClass] = error.class.name; row[:message] = error.message
      row[:line] = error.respond_to?(:line_number) ? error.line_number : nil
    end
    rows << row
  end
end
puts JSON.generate(rows)
'''

def main():
    p=argparse.ArgumentParser();p.add_argument('--reference-path',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    def git(*parts):return subprocess.check_output(['git','-C',str(args.reference_path),*parts],text=True).strip()
    if git('rev-parse','HEAD')!=PIN or git('status','--porcelain'):raise ValueError('reference must be clean and pinned')
    if args.output.exists():raise ValueError('refusing to overwrite evidence')
    env=dict(os.environ,RUBYLIB=str(args.reference_path.resolve()/'lib'),TZ='UTC')
    done=subprocess.run(['ruby','-e',RUBY],input=json.dumps(vectors()).encode(),capture_output=True,env=env,check=True)
    rows=json.loads(done.stdout);assert len(rows)==len(vectors())*3
    data={'schemaVersion':1,'referenceCommit':PIN,'referenceVersion':'5.14.0','sourceConstruction':'explicit UTF-8 byte arrays','cases':rows}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x') as f:json.dump(data,f,indent=2,ensure_ascii=False);f.write('\n')
    print(json.dumps({'vectors':len(vectors()),'variants':len(rows),'sha256':hashlib.sha256(args.output.read_bytes()).hexdigest()}))
if __name__=='__main__':main()
