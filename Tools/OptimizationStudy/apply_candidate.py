from pathlib import Path
import sys
root=Path(sys.argv[1]);variant=sys.argv[2]
path=root/'Sources/Liquid/Support/RubyDateParser.swift';text=path.read_text()
if variant=='normalization':
 old='text = regex.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: " ")'
 assert text.count(old)==1
 text=text.replace(old,'text = Self.normalized(source, using: regex)')
 marker='    private func find('
 assert text.count(marker)==1
 text=text.replace(marker,Path(__file__).with_name('NormalizationHelper.swift').read_text()+'\n'+marker)
elif variant=='matching':
 old='regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input))'
 assert text.count(old)==1
 text=text.replace(old,'regex.firstMatch(in: input, range: NSRange(location: 0, length: input.utf16.count))')
elif variant not in ['controlA','controlB']:raise ValueError(variant)
path.write_text(text)
