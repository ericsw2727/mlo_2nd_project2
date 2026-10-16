"""검증된 KREAM CSV를 읽어 발표용 그래프와 수치표를 만든다.

DB 연결과 원본 수정 없이 실행한다. 헤더 없는 MySQL OUTFILE 형식을 해석한다.
"""
from pathlib import Path
import argparse
import csv
from decimal import Decimal, ROUND_HALF_UP
import hashlib
import html
import json
import re
from collections import Counter

import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager, ticker

ROOT = Path(__file__).resolve().parents[1]
FIELD = re.compile(r'"(?:\\.|[^"\\])*"|[^,\r\n]*')
ESCAPE = re.compile(r'\\(.)')
ESCAPES = {'0': '\0', 'b': '\b', 'n': '\n', 'r': '\r', 't': '\t', 'Z': '\x1a'}
COLORS = {'blue': '#2457A6', 'teal': '#148782', 'amber': '#D79324', 'red': '#C95559',
          'ink': '#1B3048', 'muted': '#586B80', 'grid': '#E4EAF1'}
METHODS = {'RECENT_28_DAY_MEAN': '최근 28일 평균', 'SAME_WEEKDAY_MEAN': '같은 요일 평균'}


def parse_mysql_line(line):
    """SQL NULL과 빈 문자열, 실제 문자열을 구분하는 OUTFILE 파서."""
    line = line.rstrip('\r\n')
    result, pos = [], 0
    while True:
        match = FIELD.match(line, pos)
        if match is None:
            raise ValueError('CSV 필드를 해석할 수 없습니다.')
        raw, end = match.group(), match.end()
        if raw == r'\N':
            value = None
        else:
            value = raw[1:-1] if raw.startswith('"') else raw
            if '\\' in value:
                value = ESCAPE.sub(lambda m: ESCAPES.get(m[1], m[1]), value)
        result.append(value)
        if end == len(line):
            return result
        if line[end] != ',':
            raise ValueError('CSV 구분자가 올바르지 않습니다.')
        pos = end + 1


def load_table(data_dir, table_name, schemas, manifest, audit):
    schema = schemas[table_name]
    names = [c['column_name'] for c in schema]
    entry = manifest.loc[table_name]
    path = data_dir / entry['output_file_name']
    records = []
    with path.open(encoding='utf-8-sig', newline='') as stream:
        for line_no, line in enumerate(stream, 1):
            values = parse_mysql_line(line)
            if len(values) != len(names):
                raise ValueError(f'{path.name}: {line_no}행의 컬럼 수가 다릅니다.')
            for value, column in zip(values, schema):
                if value is None and column['is_nullable'] == 'NO':
                    raise ValueError(f'{table_name}.{column["column_name"]}: 필수값 누락')
            records.append(values)
    if len(records) != int(entry['actual_rows']):
        raise ValueError(f'{table_name}: 기준 행 수와 다릅니다. 잘린 CSV인지 확인하세요.')
    frame = pd.DataFrame(records, columns=names)
    for c in schema:
        name, typ = c['column_name'], c['column_type']
        if typ.startswith('decimal'):
            frame[name] = frame[name].map(lambda value: None if value is None else Decimal(value))
        elif re.match(r'(?:bigint|int|tinyint)', typ):
            frame[name] = pd.to_numeric(frame[name], errors='raise').astype('Int64')
    audit['source_files'].append({'table': table_name, 'rows': len(frame),
                                  'columns': len(names),
                                  'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return frame


def configure_font():
    # 배포 묶음에는 글꼴 파일을 포함하지 않는다. 시스템 한글 글꼴을 사용한다.
    available = {f.name for f in font_manager.fontManager.ttflist}
    candidates = ['NanumGothic', 'Nanum Gothic', 'Malgun Gothic', 'AppleGothic', 'Noto Sans CJK KR', 'Noto Sans KR']
    name = next((name for name in candidates if name in available), None)
    if name is None:
        raise RuntimeError('한글 글꼴을 찾지 못했습니다. Nanum Gothic 등 한글 글꼴을 시스템에 설치한 뒤 다시 실행하세요.')
    plt.rcParams.update({'font.family': name, 'font.size': 13, 'axes.unicode_minus': False,
                         'axes.spines.top': False, 'axes.spines.right': False,
                         'axes.labelcolor': COLORS['muted'], 'text.color': COLORS['ink'],
                         'xtick.color': COLORS['muted'], 'ytick.color': COLORS['muted'],
                         'axes.edgecolor': '#BDCAD7', 'svg.fonttype': 'path',
                         'figure.facecolor': 'white', 'axes.facecolor': 'white'})


def canvas(title, subtitle, source, note, panels=1):
    fig = plt.figure(figsize=(16, 9))
    fig.text(.06, .945, title, fontsize=25, weight='bold', va='top')
    fig.text(.06, .888, subtitle, fontsize=13, color=COLORS['muted'], va='top')
    fig.text(.06, .085, note, fontsize=11, color=COLORS['muted'], va='top')
    fig.text(.06, .035, '자료: ' + source, fontsize=9, color=COLORS['muted'], va='bottom')
    if panels == 1:
        axes = fig.add_axes([.12, .21, .79, .60])
    else:
        axes = [fig.add_axes([.09 + i * .47, .23, .39, .54]) for i in range(panels)]
    return fig, axes


def number_axis(ax, axis='y'):
    getattr(ax, axis + 'axis').set_major_formatter(ticker.StrMethodFormatter('{x:,.0f}'))
    ax.grid(axis=axis, color=COLORS['grid'], zorder=0)
    ax.set_axisbelow(True)


def write_chart(fig, stem, title, takeaway, scope, source, points, output, charts):
    png_tmp = output / f'{stem}.tmp.png'
    svg_tmp = output / f'{stem}.tmp.svg'
    fig.savefig(png_tmp, dpi=180, facecolor='white')
    fig.savefig(svg_tmp, facecolor='white')
    png_tmp.replace(output / f'{stem}.png')
    svg_tmp.replace(output / f'{stem}.svg')
    plt.close(fig)
    points.to_csv(output / 'chart_data' / f'{stem}.csv', index=False, encoding='utf-8-sig')
    charts.append({'id': stem, 'title': title, 'takeaway': takeaway, 'scope': scope, 'source': source})


def make_charts(data_dir, output):
    output.mkdir(parents=True, exist_ok=True)
    (output / 'chart_data').mkdir(exist_ok=True)
    schemas = json.loads((data_dir / 'column_schema.json').read_text(encoding='utf-8'))
    source_notes = json.loads((data_dir / 'source_notes.json').read_text(encoding='utf-8'))
    manifest_columns = ['export_order', 'table_name', 'output_file_name', 'table_role', 'actual_rows',
                        'expected_rows', 'column_count', 'row_count_status', 'export_version', 'captured_at_kst']
    with (data_dir / 'kream_full_export_manifest_v1.csv').open(encoding='utf-8', newline='') as stream:
        values = [parse_mysql_line(line) for line in stream]
    if len(values) != 28 or any(len(r) != 10 for r in values):
        raise ValueError('기준 목록은 28행·10컬럼이어야 합니다.')
    manifest = pd.DataFrame(values, columns=manifest_columns).set_index('table_name')
    if not manifest.index.is_unique:
        raise ValueError('기준 목록의 테이블 이름이 중복됐습니다.')
    audit = {'source_zip': source_notes['source_zip'], 'source_files': [], 'checks': []}
    tables = {t: load_table(data_dir, t, schemas, manifest, audit) for t in schemas}
    configure_font()
    charts = []
    save = lambda fig, stem, title, take, scope, source, points: write_chart(
        fig, stem, title, take, scope, source, points, output, charts)

    # 1. 검수 원천 한 파일만 분류 건수에 사용한다.
    distribution = pd.DataFrame({'분류': ['Silver', 'Excluded', 'Quarantine'],
        '건수': [int(manifest.loc[t, 'actual_rows']) for t in
                 ['silver_inspection', 'excluded_inspection', 'quarantine_inspection']]})
    assert distribution['건수'].sum() == 335000
    distribution['비율_pct'] = distribution['건수'] / 335000 * 100
    fig, ax = canvas('335,000행을 정상·제외·격리로 분류', '검수 원천 기준 · 조인 통합본을 더해 중복 집계하지 않음',
                     '내보내기 기준 목록 / 검수 원천 분류',
                     'Excluded에는 동일 중복과 정상 이전 개정이 포함됩니다. 분류 비율을 오염률로 해석하지 않습니다.')
    colors = [COLORS['blue'], COLORS['amber'], COLORS['red']]
    bars = ax.barh(distribution['분류'][::-1], distribution['건수'][::-1], color=colors[::-1], height=.52)
    ax.set_xlim(0, 335000); ax.set_xlabel('행 수'); number_axis(ax, 'x')
    for bar, (_, row) in zip(bars, distribution.iloc[::-1].iterrows()):
        ax.text(bar.get_width()+3500, bar.get_y()+bar.get_height()/2,
                f'{row["건수"]:,}행  ({row["비율_pct"]:.2f}%)', va='center', fontsize=15)
    save(fig, '01_disposition', '정상·제외·격리 분류', '전체 원본 335,000행을 빠짐없이 분류했다.',
         '최종 검수 상태. 제외가 모두 오염을 뜻하지 않음.', 'export_manifest', distribution)

    # 2. 배상금 상위 상품. 전체 값은 Decimal로 합산하고 그림에서만 억 원으로 환산한다.
    products = tables['gold_product_risk_summary_v1']
    assert int(products['inspection_rows'].sum()) == 271787
    assert int(products['fake_pass_claim_rows'].sum()) == 19414
    total_loss = sum(products['compensation_loss_krw'], Decimal(0))
    assert total_loss == Decimal('154502066956.5000')
    top = products.sort_values('compensation_loss_krw', ascending=False).head(10).copy()
    top['배상금_억원'] = top['compensation_loss_krw'].map(lambda d: float(d / Decimal(100000000)))
    fig, ax = canvas('배상금 부담은 고가 상품에 집중', '최종 유효 검수 271,787건 · 배상금 상위 10개 상품',
                     'gold_product_risk_summary_v1',
                     '배상금은 가품 오판정 거래가의 3배입니다. 총액 순위는 오류 빈도 순위와 다릅니다. 레고는 정상 관측 없음.')
    ax.set_position([.34, .20, .56, .62])
    plotted = top.iloc[::-1]
    labels = [n if len(n) <= 28 else n[:27]+'…' for n in plotted['standard_item_name']]
    bars = ax.barh(labels, plotted['배상금_억원'], color=COLORS['blue'], height=.64)
    ax.set_xlim(0, max(top['배상금_억원'])*1.18); ax.set_xlabel('배상금 합계 (억 원)'); number_axis(ax, 'x')
    for bar, value in zip(bars, plotted['배상금_억원']):
        ax.text(value+2, bar.get_y()+bar.get_height()/2, f'{value:,.1f}', va='center', fontsize=12)
    save(fig, '02_product_loss', '상품별 배상금 상위 10개', '상품 가격을 함께 고려해 배상금 위험을 해석한다.',
         '현재 최종 상태 전체. 정상 관측 없는 상품을 위험 0으로 해석하지 않음.',
         'gold_product_risk_summary_v1', top)

    # 3. 서로 다른 기간과 선택 과정을 가진 집단임을 명시한다.
    cross = tables['gold_risk_cross_summary_v1']
    cohort_specs = [('최초 개정 최종 상태\n연속 관측 기간', 'FIRST_REVISION_FINAL', 'CONTINUOUS_PERIOD'),
                    ('재검수 개정 최종 상태\n10월 집중 처리 기간', 'REINSPECTION_FINAL', 'REINSPECTION_BATCH_PERIOD')]
    cohort_rows = []
    for label, revision, period in cohort_specs:
        part = cross[(cross['final_revision_type'] == revision) & (cross['analysis_period'] == period)]
        n, claims = int(part['inspection_rows'].sum()), int(part['fake_pass_claim_rows'].sum())
        cohort_rows.append({'집단': label, '건수': n, '가품오판정': claims, '비율_pct': claims/n*100})
    cohort = pd.DataFrame(cohort_rows)
    assert list(cohort['건수']) == [243454, 21656]
    fig, axes = canvas('전체 비율만 보면 집단 차이가 가려짐', '최종 개정 유형과 분석 기간을 구분한 관측 결과',
                       'gold_risk_cross_summary_v1',
                       '기간과 대상 선택 과정이 다릅니다. 재검수의 효과나 직원 역량에 대한 인과관계는 확인하지 않았습니다.', panels=2)
    for ax, key, label in zip(axes, ['건수', '비율_pct'], ['검수 건수', '가품 오판정 비율 (%)']):
        bars = ax.bar(cohort['집단'], cohort[key], color=[COLORS['teal'], COLORS['red']], width=.5)
        ax.set_ylabel(label); ax.set_ylim(0, 300000 if key == '건수' else 100); number_axis(ax)
        for bar, value in zip(bars, cohort[key]):
            text = f'{value:,.0f}건' if key == '건수' else f'{value:.4f}%'
            ax.annotate(text, (bar.get_x()+bar.get_width()/2, bar.get_height()), xytext=(0, 8),
                        textcoords='offset points', ha='center', fontsize=15)
    save(fig, '03_revision_cohorts', '최초 개정·재검수 집단 비교', '약 1.00%와 78.02%를 같은 집단의 성과처럼 비교하지 않는다.',
         '연속 기간 최초 개정 최종 상태와 10월 재검수 최종 상태의 관측 비교.',
         'gold_risk_cross_summary_v1', cohort)

    # 4. 관측 날짜 전체로 나눠 시간대별 일평균 완료 건수를 계산한다.
    hourly = tables['gold_inspection_workload_hourly_v1']
    selected = hourly[(hourly['analysis_period'] == 'CONTINUOUS_PERIOD') &
                      (hourly['event_type'] == 'FIRST_INSPECTION')].copy()
    days = selected['done_date_kst'].nunique()
    assert days == 1704 and int(selected['inspection_event_rows'].sum()) == 262833
    matrix = selected.pivot_table(index='department_name', columns='done_hour_kst',
                                  values='inspection_event_rows', aggfunc='sum', fill_value=0)
    matrix = matrix.reindex(columns=list(range(24)), fill_value=0).astype(float) / days
    matrix = matrix.loc[matrix.sum(axis=1).sort_values(ascending=False).index]
    fig, ax = canvas('시간대·부서별 완료 작업량을 구분', '2022-01-01~2026-08-31 · 정상 최초 검수 262,833건 / 관측 1,704일',
                     'gold_inspection_workload_hourly_v1',
                     '검수 완료 시각 기준입니다. 현재 마스터 부서를 사용하며 실제 출근·가동률·대기 주문량을 뜻하지 않습니다.')
    ax.set_position([.19, .24, .65, .53])
    image = ax.imshow(matrix.to_numpy(), aspect='auto', cmap='Blues', vmin=0)
    ax.set_xticks(list(range(24)), [str(h) for h in range(24)]); ax.set_xlabel('검수 완료 시간대 (KST)')
    ax.set_yticks(list(range(len(matrix))), matrix.index)
    fig.colorbar(image, ax=ax, fraction=.04, pad=.025, label='일평균 완료 건수')
    save(fig, '04_hour_department', '시간대·부서별 작업량', '완료 작업량 분포를 기준으로 운영 검토 지점을 찾는다.',
         '연속 기간 최초 검수만 포함. 시간별 합계를 전체 관측 1,704일로 나눔.',
         'gold_inspection_workload_hourly_v1', matrix.rename_axis('부서').reset_index())

    # 5. 연속 기간의 모든 월을 포함한다. 2010 고립 기간과 부분 월은 범위를 분리한다.
    daily = tables['gold_inspection_workload_daily_v1']
    monthly_source = daily[(daily['analysis_period'] == 'CONTINUOUS_PERIOD') &
                           (daily['event_type'] == 'FIRST_INSPECTION')].copy()
    monthly_source['월'] = monthly_source['done_date_kst'].str[:7]
    monthly = monthly_source.groupby('월', as_index=False).agg(최초검수건수=('inspection_event_rows', 'sum'))
    assert len(monthly) == 56 and int(monthly['최초검수건수'].sum()) == 262833
    fig, ax = canvas('연속 관측 기간의 월별 최초 검수 작업량', '2022년 1월~2026년 8월 · 월별 실제 관측 합계',
                     'gold_inspection_workload_daily_v1',
                     '월별 일수 차이를 포함한 합계입니다. 2010 고립 기록, 9월 부분 월과 10월 재검수는 이 그림에서 분리했습니다.')
    ax.plot(range(len(monthly)), monthly['최초검수건수'].astype(float), color=COLORS['blue'], linewidth=2, marker='o', markersize=3)
    ticks = sorted(set(list(range(0, len(monthly), 6))+[len(monthly)-1]))
    ax.set_xticks(ticks, monthly['월'].iloc[ticks], rotation=30, ha='right')
    ax.set_ylim(0, float(monthly['최초검수건수'].max())*1.2); ax.set_ylabel('최초 검수 건수'); number_axis(ax)
    save(fig, '05_monthly_workload', '월별 최초 검수 작업량', '관측 기간을 분리해 작업량 흐름을 해석한다.',
         '2022-01~2026-08의 56개월 전체. 부분 기간과 재검수 제외.',
         'gold_inspection_workload_daily_v1', monthly)

    # 6. 실제 7일 결과와 예측을 직접 비교한다.
    evaluation = tables['gold_workload_forecast_evaluation_v1']
    assert len(evaluation) == 14
    actual = tables['gold_prediction_actual_daily_v1'].sort_values('inspection_date')
    assert int(actual['actual_inspection_rows'].sum()) == 2012
    assert sum(actual['actual_duration_min'], Decimal(0)) == Decimal(30443)
    dates = sorted(evaluation['forecast_date'].unique()); date_labels = [d[5:].replace('-', '/') for d in dates]
    fig, axes = canvas('다음 7일의 실제값과 예측값 비교', '입력: 2026-08-04~08-31 / 평가: 2026-09-01~09-07 · 최초 검수',
                       'gold_workload_forecast_evaluation_v1',
                       '기준일 이후 추출된 입력 6행은 제외했습니다. EXTRACTED_AT은 실제 수신 시각과 구분하며 한 주 평가 결과입니다.', panels=2)
    for ax, actual_col, predicted_col, ylabel in zip(axes,
            ['actual_inspection_rows', 'actual_duration_min'],
            ['predicted_inspection_rows', 'predicted_duration_min'], ['검수 건수', '소요시간 합계 (분)']):
        a = evaluation[evaluation['forecast_method'] == 'RECENT_28_DAY_MEAN'].sort_values('forecast_date')
        ax.plot(range(7), a[actual_col].astype(float), label='실제값', color=COLORS['ink'], marker='o', linewidth=2.5)
        for method, color in zip(METHODS, [COLORS['blue'], COLORS['teal']]):
            f = evaluation[evaluation['forecast_method'] == method].sort_values('forecast_date')
            ax.plot(range(7), f[predicted_col].astype(float), label=METHODS[method], color=color,
                    linestyle='--', marker='s', markersize=4, linewidth=1.8)
        ax.set_xticks(range(7), date_labels); ax.set_ylabel(ylabel); ax.set_ylim(bottom=0)
        number_axis(ax); ax.legend(fontsize=10, loc='lower left')
    save(fig, '06_forecast_actual', '실제값과 예측값', '예측을 실제값과 분리해 저장하고 같은 날짜로 비교했다.',
         '정상 최초 검수의 완료 작업량. 미래 주문 유입 예측과 구분.',
         'gold_workload_forecast_evaluation_v1', evaluation)

    # 7. 서로 다른 단위를 한 축에 섞지 않는다.
    summary = tables['gold_workload_forecast_summary_v1'].set_index('forecast_method').loc[list(METHODS)].reset_index()
    for _, row in summary.iterrows():
        e = evaluation[evaluation['forecast_method'] == row['forecast_method']]
        for metric, absolute, actual_name in [('inspection_wape_pct', 'inspection_abs_error', 'actual_inspection_rows'),
                                               ('duration_wape_pct', 'duration_abs_error_min', 'actual_duration_min')]:
            computed = sum(e[absolute], Decimal(0))*100/sum((Decimal(str(v)) for v in e[actual_name]), Decimal(0))
            assert computed.quantize(Decimal('.0001'), rounding=ROUND_HALF_UP) == row[metric]
    fig, axes = canvas('건수와 소요시간에서 우수한 방법이 다름', 'WAPE = 절대 오차 합계 / 실제값 합계 × 100 · 낮을수록 오차가 작음',
                       'gold_workload_forecast_summary_v1',
                       '건수는 같은 요일 평균, 소요시간은 최근 28일 평균의 오차가 작았습니다. 한 주 평가로 일반 성능을 확정하지 않습니다.', panels=2)
    for ax, key, label in zip(axes, ['inspection_wape_pct', 'duration_wape_pct'], ['검수 건수 WAPE (%)', '소요시간 WAPE (%)']):
        vals = summary[key].astype(float)
        bars = ax.bar([METHODS[m] for m in summary['forecast_method']], vals,
                      color=[COLORS['blue'], COLORS['teal']], width=.5)
        ax.set_ylabel(label); ax.set_ylim(0, max(vals)*1.3); number_axis(ax)
        for bar, value in zip(bars, vals):
            ax.annotate(f'{value:.4f}%', (bar.get_x()+bar.get_width()/2, value),
                        xytext=(0, 8), textcoords='offset points', ha='center', fontsize=16)
    save(fig, '07_forecast_error', '두 예측 방법의 오차', '단순한 방법도 검증하고 지표별 차이를 확인한다.',
         '2026-09-01~09-07 한 주 평가. WAPE를 정확도로 표현하지 않음.',
         'gold_workload_forecast_summary_v1', summary)

    # 8. 인력 추정값은 가정별 필요 인원이며 추가 채용 인원이 아니다.
    staff = tables['gold_staffing_scenario_v1']
    assert len(staff) == 42 and set(staff['available_minutes_per_person'].astype(int)) == {240, 360, 480}
    fig, axes = canvas('한 명의 검수 가능 시간에 따라 필요 인원이 달라짐', '최초 검수 예측 소요시간 / 가정한 한 명의 가용 시간 → 올림',
                       'gold_staffing_scenario_v1',
                       '240·360·480분은 실제 근무시간이 아닌 가정입니다. 재검수·교대·휴가·담당 자격을 반영한 채용 계획이 아닙니다.', panels=2)
    for ax, method in zip(axes, METHODS):
        for minutes, color in zip([240, 360, 480], [COLORS['red'], COLORS['blue'], COLORS['teal']]):
            p = staff[(staff['forecast_method'] == method) &
                      (staff['available_minutes_per_person'] == minutes)].sort_values('forecast_date')
            ax.plot(range(7), p['estimated_required_people'].astype(int), marker='o',
                    label=f'한 명당 {minutes}분 가정', color=color, linewidth=2)
        ax.set_title(METHODS[method], fontsize=15); ax.set_ylim(0, 23)
        ax.set_xticks(range(7), date_labels); ax.set_ylabel('필요 인원 추정 (명)')
        ax.yaxis.set_major_locator(ticker.MultipleLocator(5)); number_axis(ax)
        ax.legend(fontsize=10, loc='lower left')
    save(fig, '08_staffing_scenarios', '인력 배치 시나리오', '실제 가용 시간이 없으므로 가정을 명시해 운영 검토에 연결한다.',
         '정상 최초 검수만 포함. 현재 재직 인원과 실제 출근 인원을 대조하지 않음.',
         'gold_staffing_scenario_v1', staff)

    # 9. 상대팀 기준은 별도 답변에서 받은 값임을 표시한다.
    benchmark = pd.DataFrame({'분류': ['Silver', 'Excluded', 'Quarantine'],
        '상대팀_기준': [source_notes['supplier_counts'][k] for k in ['SILVER', 'EXCLUDED', 'QUARANTINE']],
        '현재_결과': distribution['건수'].tolist()})
    benchmark['차이_현재_기준'] = benchmark['현재_결과']-benchmark['상대팀_기준']
    fig, ax = canvas('전체 건수는 같지만 분류별 기준 건수와 차이 존재', '상대팀 Q2 답변의 기준과 현재 명세서·확정 정책 적용 결과 비교',
                     '상대팀 Q2 답변 / 내보내기 기준 목록',
                     '기준을 맞추기 위해 임의로 정상 처리하지 않았습니다. 상대팀의 행별 분류·정제 SQL이 없어 원인은 확정하지 않았습니다.')
    y = list(range(3))
    ax.barh([i+.18 for i in y], benchmark['상대팀_기준'], height=.32, color='#BCCDDD', label='상대팀 기준')
    ax.barh([i-.18 for i in y], benchmark['현재_결과'], height=.32, color=COLORS['blue'], label='현재 결과')
    ax.set_yticks(y, benchmark['분류']); ax.invert_yaxis(); ax.set_xlim(0, 335000)
    ax.set_xlabel('행 수'); number_axis(ax, 'x'); ax.legend(loc='lower right')
    for i, row in benchmark.iterrows():
        ax.text(float(max(row['상대팀_기준'], row['현재_결과']))+4500, i,
                f'차이 {row["차이_현재_기준"]:+,}행', va='center', fontsize=14)
    save(fig, '09_supplier_comparison', '상대팀 기준과의 차이', '총수 보존과 분류 기준 차이를 구분해 개선 항목으로 남긴다.',
         source_notes['supplier_count_source'], '상대팀 Q2 답변 / export_manifest', benchmark)

    audit['checks'] = ['선택 CSV 12개 기준 행 수·컬럼 수 확인', '분류 합계 335000',
        '상품 집계 정상 271787·가품 오판정 19414·배상금 합계 확인',
        '연속 기간 최초 검수 262833·관측 1704일·월별 56개 기간 확인',
        '평가 실제값 2012건·30443분 확인', 'WAPE 독립 재계산', '인력 시나리오 42행 확인']
    audit['status'] = 'PASS'
    audit['limits'] = ['최종 집계 CSV에서 시각화. 최초 Bronze 전체와의 재대조 아님.',
                       '그림의 원 단위 금액을 Decimal로 검증한 후 억 원 표시에서만 float 변환.',
                       '별도 환경 전체 재현 검증은 아직 진행 중.']
    (output / 'validation.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding='utf-8')
    (output / 'chart_index.json').write_text(json.dumps(charts, ensure_ascii=False, indent=2), encoding='utf-8')
    gallery = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>KREAM 발표용 시각화</title><style>body{font:16px/1.7 'Malgun Gothic',Arial,sans-serif;margin:0;background:#f1f5fa;color:#213547}main{max-width:1250px;margin:auto;padding:28px}section{background:white;border-radius:14px;padding:24px;margin:24px 0}img{width:100%;height:auto}a{color:#2457a6}h1{font-size:30px}h2{font-size:22px}.scope{color:#596b7e;font-size:14px}</style><main><h1>KREAM 발표용 시각화</h1><p>검증된 최종 CSV를 사용한 발표용 그래프 9개. 실제 DB와 SQL은 변경하지 않습니다.</p><p>재현 상태: 최종 파일 검증 완료 / 별도 DB의 전체 재현 검증 진행 중.</p>'''
    guide = ['# 발표용 그래프 설명과 사용 순서\n', '각 PNG는 2880×1620이며 SVG도 함께 제공합니다. 모든 수치표는 chart_data 폴더에 있습니다.\n']
    for c in charts:
        e = html.escape
        gallery += f'<section><h2>{e(c["title"])}</h2><p>{e(c["takeaway"])}</p><img src="{c["id"]}.png" alt="{e(c["title"])}"><p class="scope">범위: {e(c["scope"])}</p><p class="scope">자료: {e(c["source"])}</p><a href="{c["id"]}.svg">SVG</a> · <a href="chart_data/{c["id"]}.csv">수치표 CSV</a></section>'
        guide += [f'## {c["title"]}\n', f'- 핵심: {c["takeaway"]}\n- 범위: {c["scope"]}\n- 근거: {c["source"]}\n- 파일: {c["id"]}.png / .svg\n']
    gallery += '</main></html>'
    if re.search(r'[\u3400-\u4dbf\u4e00-\u9fff\u3040-\u30ff]', gallery):
        raise ValueError('안내 문구에 한국어·영어 이외의 문자가 포함됐습니다.')
    (output / 'gallery.html').write_text(gallery, encoding='utf-8')
    (output / '발표_설명.md').write_text('\n'.join(guide), encoding='utf-8')
    print(f'완료: {output}\n그래프 9개, PNG·SVG·수치표와 검증 기록 생성')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='KREAM 발표용 시각화 생성')
    parser.add_argument('--data-dir', type=Path, default=ROOT / 'data')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'outputs')
    args = parser.parse_args()
    make_charts(args.data_dir.resolve(), args.output_dir.resolve())
