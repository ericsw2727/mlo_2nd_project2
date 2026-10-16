"""기존 MySQL CSV에서 필요한 데이터 사본을 추출하고 코드 사본을 연결한다."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
FIELD = re.compile(r'"(?:\\.|[^"\\])*"|[^,\r\n]*')
ESC = re.compile(r'\\(.)')
EM = {'0': '\0', 'b': '\b', 'n': '\n', 'r': '\r', 't': '\t', 'Z': '\x1a'}

def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def parse(line):
    line = line.rstrip('\r\n'); result = []; pos = 0
    while True:
        m = FIELD.match(line, pos)
        if m is None:
            raise ValueError('MySQL CSV 형식 오류')
        raw = m.group(); end = m.end()
        value = None if raw == r'\N' else raw[1:-1] if raw.startswith('"') else raw
        if value is not None:
            value = ESC.sub(lambda q: EM.get(q[1], q[1]), value)
        result.append(value)
        if end == len(line):
            return result
        if line[end] != ',':
            raise ValueError('CSV 구분자 오류')
        pos = end + 1

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--original-code', type=Path, required=True)
    p.add_argument('--catalog', type=Path, required=True)
    args = p.parse_args()
    data = ROOT / '데이터'; data.mkdir(exist_ok=True)
    catalog = json.loads(args.catalog.read_text(encoding='utf-8'))['documentation_column_catalog_v1']
    audit = {'source_files': [], 'original_codes': [], 'changes': [
        '모든 실행 사본: CSV 경로를 새 폴더의 데이터 로더로 연결. 분석 수식 유지.',
        '04: 누적 작업량만 유효 작업 이력 Gold 집계로 연결. 최신 상태 계산 유지.',
        '07·08: 검수 이력 중복 제거 대신 정상 검수원 마스터 사용(Y·N 포함).',
        '00: 위 변경을 동일 적용한 통합 실행 사본. 별도 원본 보관본은 생성하지 않음.'
    ]}
    def read(table):
        path = args.source / ('kream_full_' + table + '.csv')
        before = sha(path)
        cols = [c['column_name'] for c in sorted(
            [c for c in catalog if c['table_name'] == table], key=lambda c: int(c['column_position']))]
        with path.open(encoding='utf-8-sig', newline='') as f:
            rows = [parse(line) for line in f]
        if any(len(row) != len(cols) for row in rows):
            raise ValueError(table + ': 컬럼 수 불일치')
        frame = pd.DataFrame(rows, columns=cols)
        after = sha(path)
        assert before == after, '원천 해시 변경'
        audit['source_files'].append({'path': str(path), 'table': table, 'rows': len(frame),
                                      'sha256_before': before, 'sha256_after': after})
        return frame
    joined = read('silver_inspection_join_ready')
    required = ['INSP_ID', 'REV_NO', 'ITEM_STD_CODE', 'ITEM_NM', 'INSP_RESULT',
                'COMPENSATION_LOSS_KRW', 'INSPECTOR_EMP_NO', 'INSPECTOR_DEPT_NM',
                'INSPECTOR_POSITION_NM', 'INSP_DONE_DT', 'INSP_DURATION_MIN']
    joined[required].to_csv(data / 'clean_kream_inspection_joined.csv', index=False, encoding='utf-8-sig')
    staff = read('silver_inspector_master').rename(columns={
        'DEPT_NM': 'INSPECTOR_DEPT_NM', 'POSITION_NM': 'INSPECTOR_POSITION_NM',
        'EMP_NO': 'INSPECTOR_EMP_NO', 'ACTIVE_YN': 'IS_ACTIVE'})
    staff[['INSPECTOR_EMP_NO', 'INSPECTOR_DEPT_NM', 'INSPECTOR_POSITION_NM', 'IS_ACTIVE']].to_csv(
        data / 'inspector_master.csv', index=False, encoding='utf-8-sig')
    hourly = read('gold_inspection_workload_hourly_v1')
    hourly['inspection_event_rows'] = pd.to_numeric(hourly['inspection_event_rows'], errors='raise')
    work = hourly.pivot_table(index='department_name', columns='event_type',
        values='inspection_event_rows', aggfunc='sum', fill_value=0)
    work.to_csv(data / 'valid_workload_counts.csv', encoding='utf-8-sig')
    old_load = 'pd.read_csv(r"data\\Clean_(TO-BE)\\clean_kream_inspection_joined.csv", low_memory=False)'
    old_work = "pd.crosstab(\n    df['INSPECTOR_DEPT_NM'], \n    df['REV_NO'], \n    normalize='index'\n) * 100"
    files = sorted(args.original_code.glob('*.py'))
    assert len(files) == 11, '원본 코드 11개 필요'
    for source in files:
        before = sha(source)
        content = source.read_text(encoding='utf-8-sig')
        assert old_load in content, source.name
        content = content.replace(old_load, 'load_analysis_data()')
        if source.name.startswith(('00_', '04_')):
            assert old_work in content, '04 작업량 연결 패턴 확인 필요'
            content = content.replace(old_work, 'load_workload_ratio()')
        if source.name.startswith(('00_', '07_', '08_')):
            content = content.replace("df.drop_duplicates(subset=['INSPECTOR_EMP_NO']).copy()", 'load_staff_data()')
        # 원본의 인코딩 선언 다음에 데이터 연결 함수만 추가한다.
        content = content.replace('# -*- coding: utf-8 -*-',
            '# -*- coding: utf-8 -*-\nfrom data_loader import load_analysis_data, load_staff_data, load_workload_ratio', 1)
        (ROOT / '코드' / source.name).write_text(content, encoding='utf-8')
        assert sha(source) == before
        audit['original_codes'].append({'path': str(source), 'sha256': before})
    audit['extracted_files'] = [{'name': f.name, 'sha256': sha(f)} for f in sorted(data.glob('*.csv'))]
    (data / '출처_및_연결기록.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'최종검수': len(joined), '검수원': len(staff),
                      '유효작업': int(work.to_numpy().sum()), '연결코드': len(files)}, ensure_ascii=False))

if __name__ == '__main__':
    main()
