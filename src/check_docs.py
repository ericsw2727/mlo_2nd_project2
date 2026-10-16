"""상대 링크·이미지·팀 범위와 숫자 근거의 기본 일관성을 확인한다."""
from pathlib import Path
import json,re
from urllib.parse import unquote
from markdown_it import MarkdownIt
ROOT=Path(__file__).resolve().parents[1]
md=MarkdownIt('commonmark',{'html':True}).enable('table');issues=[];links=0
for p in ROOT.rglob('*.md'):
 if '__pycache__' in p.parts:continue
 text=p.read_text();targets=[]
 for token in md.parse(text):
  for child in token.children or []:
   if child.type=='link_open':targets.append(child.attrGet('href'))
   if child.type=='image':targets.append(child.attrGet('src'))
 targets += re.findall(r'<img[^>]+src=["\']([^"\']+)',text)
 for target in targets:
  if not target or target.startswith(('http:','https:','mailto:','data:')):continue
  link,_,fragment=target.partition('#');resolved=(p.parent/unquote(link)).resolve() if link else p.resolve();links+=1
  if not resolved.exists():issues.append({'file':str(p.relative_to(ROOT)),'missing':target})
  if fragment and resolved==p.resolve() and fragment not in re.findall(r'<a\s+id=["\']([^"\']+)',text):issues.append({'file':str(p.relative_to(ROOT)),'missing_anchor':fragment})
  if re.search('[\u3400-\u4dbf\u4e00-\u9fff]',text):issues.append({'file':str(p.relative_to(ROOT)),'unsupported_characters':True})
text=(ROOT/'README.md').read_text()
for word in ['Delta','Spark','risk_priority','LOSS_PER_MINUTE','70.30','sandbox:']:
 if word in text:issues.append({'scope_violation':word})
checks={'checked_markdown_links':links,'issues':issues,'passed':not issues};(ROOT/'evidence/document_checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2));print(json.dumps(checks,ensure_ascii=False))
if issues:raise SystemExit(1)
