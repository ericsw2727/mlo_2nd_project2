"""갤러리 연결과 내보낸 그림 파일의 무결성을 점검한다."""
from pathlib import Path
from html.parser import HTMLParser
import json
from PIL import Image
from data_loader import ROOT

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('src', 'href') and not value.startswith('#'):
                self.refs.append(value)

def main():
    out = ROOT / '결과'
    parser = Links()
    parser.feed((out / '시각화_모아보기.html').read_text(encoding='utf-8'))
    assert all((out / ref).is_file() for ref in parser.refs)
    pngs = list((out / '그래프').glob('*.png'))
    svgs = list((out / '그래프').glob('*.svg'))
    assert len(pngs) == len(svgs) == 10
    for path in pngs:
        with Image.open(path) as im:
            im.verify()
    for path in svgs:
        assert '<svg' in path.read_text(encoding='utf-8')
    report = json.loads((out / '검증결과.json').read_text(encoding='utf-8'))
    assert report['failed'] == 0
    # Windows 더블클릭용 배치 파일은 CRLF로 저장한다.
    bat = ROOT / '실행.bat'
    bat.write_bytes(bat.read_text(encoding='utf-8').replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'))
    print(f'PNG {len(pngs)}개 · SVG {len(svgs)}개 · 갤러리 링크 {len(parser.refs)}개 정상')
    print(f'통계표 {len(list((out / "통계표").glob("*.csv")))}개 · 통계/보존 검증 {len(report["checks"])}개 통과')

if __name__ == '__main__':
    main()
