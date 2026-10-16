"""연결된 원본 분석 사본을 실행하여 통계표·PNG·SVG·HTML 갤러리를 만든다."""
from pathlib import Path
from contextlib import redirect_stdout
from datetime import datetime, timezone, timedelta
import hashlib
import html
import io
import json
import runpy
import warnings
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from data_loader import ROOT, load_analysis_data, load_staff_data

OUT = ROOT / '결과'
BLUE, TEAL, RED, INK, MUTED = '#3265AD', '#158C88', '#D35A53', '#172B44', '#62748A'
PALETTE = ['#CBD8E9', '#9AB9DE', '#6597CD', '#3574B4', '#246780', '#178C88', '#E6AA4C']
GENERAL = '최종 유효 검수 중 REV_NO=1 · 2022.01–2026.08 · 243,454건'
TITLES = [
    '외주팀 품질 위험', '검수 소요시간 비교', '스니커즈팀 재검수 부담',
    '최신 상태와 누적 작업량', '팀별 품목 구성', '상품별 오판정률',
    '팀별 인원과 직급', '팀별 직급 구성비', '상품별 검수 대상 건수', '팀 내 상품 구성비']
NOTES = [GENERAL, GENERAL,
    '최종 유효 검수 중 REV_NO=2 · 21,656건 · 선택된 재검수 집단',
    '최신 상태 271,787건 / 유효 작업 이력 291,548건 · 서로 다른 분모', GENERAL, GENERAL,
    '정상 검수원 마스터 2,960명 · 재직·비재직 포함 · 현재 소속 기준',
    '정상 검수원 마스터 2,960명 · 부서별 구성비 합계 100%', GENERAL,
    GENERAL + ' · 각 부서(열) 합계 100%']
FILES = []

def setup():
    available = {f.name for f in font_manager.fontManager.ttflist}
    font = next((f for f in ['Malgun Gothic', 'NanumGothic', 'Noto Sans CJK KR', 'AppleGothic'] if f in available), None)
    if not font:
        raise RuntimeError('맑은 고딕 등 한글 글꼴이 필요합니다.')
    plt.rcParams.update({'font.family': font, 'axes.unicode_minus': False,
        'font.size': 11, 'axes.labelcolor': MUTED, 'text.color': INK,
        'xtick.color': MUTED, 'ytick.color': INK, 'axes.edgecolor': '#DEE5EE',
        'axes.spines.top': False, 'axes.spines.right': False, 'svg.fonttype': 'path',
        'figure.facecolor': '#FFFFFF', 'axes.facecolor': '#FFFFFF'})
    for name in ['그래프', '통계표', '실행로그']:
        (OUT / name).mkdir(parents=True, exist_ok=True)

def canvas(n, size=(18, 10), **kwargs):
    fig, axes = plt.subplots(figsize=size, **kwargs)
    fig.suptitle(f'{n:02d}  {TITLES[n-1]}', x=.04, y=.97, ha='left', fontsize=25, weight='bold')
    fig.text(.04, .918, NOTES[n-1], fontsize=11, color=MUTED)
    fig.text(.04, .025, 'KREAM  /  PANDAS ANALYSIS     |     합성 데이터 · 현재 마스터 소속 기준 · 배상액은 산식상 위험액',
             fontsize=9, color=MUTED)
    fig.subplots_adjust(left=.17, right=.95, top=.83, bottom=.22 if n in (4, 7, 8) else .13, wspace=.58)
    return fig, axes

def save(fig, n):
    stem = f'{n:02d}_{TITLES[n-1].replace(" ", "_")}'
    for ext in ['png', 'svg']:
        fig.savefig(OUT / '그래프' / f'{stem}.{ext}', dpi=180)
    plt.close(fig)
    FILES.append(stem)

def bar(ax, names, values, label, colors=None, fmt='.2f'):
    values = np.asarray(values, dtype=float)
    ax.barh(names, values, color=colors or BLUE, height=.63)
    ax.invert_yaxis(); ax.set_xlabel(label)
    ax.grid(axis='x', alpha=.15); ax.set_axisbelow(True)
    ax.set_xlim(0, max(values) * 1.24 if max(values) else 1)
    for y, value in enumerate(values):
        ax.text(value + max(values) * .015, y, format(value, fmt), va='center', fontsize=10)

def stacked(ax, table, percent=False):
    left = np.zeros(len(table))
    for i, column in enumerate(table.columns):
        vals = table[column].to_numpy(dtype=float)
        ax.barh(table.index, vals, left=left, label=column, color=PALETTE[i], height=.64)
        for y, (v, l) in enumerate(zip(vals, left)):
            if (v >= 6 if percent else v >= 32):
                ax.text(l+v/2, y, f'{v:.1f}%' if percent else f'{v:,.0f}',
                        ha='center', va='center', fontsize=9, color=INK if i < 3 or i == 6 else 'white')
        left += vals
    ax.invert_yaxis(); ax.set_xlabel('구성비 (%)' if percent else '등록 인원 (명)')
    ax.set_xlim(0, 100 if percent else max(left)*1.12)
    if not percent:
        for y, v in enumerate(left):
            ax.text(v+max(left)*.015, y, f'{v:,.0f}명', va='center', fontsize=10, weight='bold')
    ax.legend(loc='upper center', bbox_to_anchor=(.5, -.12), ncol=4, frameon=False, fontsize=10)

def heatmap(n, table, label, fmt, cmap):
    fig, ax = canvas(n, size=(19, 13))
    fig.subplots_adjust(left=.34, right=.90, bottom=.20, top=.85)
    vals = table.to_numpy(dtype=float)
    vmax = np.nanmax(vals)
    im = ax.imshow(vals, aspect='auto', cmap=cmap, vmin=0, vmax=vmax)
    ax.set_xticks(range(len(table.columns)), table.columns, rotation=32, ha='right', fontsize=10)
    ax.set_yticks(range(len(table.index)), table.index, fontsize=11)
    for y in range(len(table.index)):
        for x in range(len(table.columns)):
            value = vals[y, x]
            ax.text(x, y, format(value, fmt) if np.isfinite(value) else '—', ha='center', va='center',
                    fontsize=10, color='white' if value > vmax*.57 else INK)
    fig.colorbar(im, ax=ax, fraction=.035, pad=.03).set_label(label)
    save(fig, n)

def charts(results):
    a = results[1]['stat_table']
    fig, axes = canvas(1, ncols=2)
    colors = [RED if '외주' in x else BLUE for x in a.INSPECTOR_DEPT_NM]
    bar(axes[0], a.INSPECTOR_DEPT_NM, a['배상위험_억원'], '산식상 배상 위험액 (억 원)', colors)
    bar(axes[1], a.INSPECTOR_DEPT_NM, a['오판정률(%)'], 'CLAIM_FAKE_PASS / 검수 건수 (%)', colors)
    save(fig, 1)

    r = results[2]; t = r['dept_boxplot_df']
    fig, axes = canvas(2, ncols=2)
    bar(axes[0], ['외주야간검수팀', '타 부서 전체'], [r['outsource_ratio'], r['others_ratio']],
        '10분 미만 검수 비중 (%)', [RED, BLUE])
    boxes = [{'label': row.INSPECTOR_DEPT_NM, 'q1': row.Q1_25, 'med': row['중앙값_50'],
        'q3': row.Q3_75, 'whislo': row['최소값'], 'whishi': row['최대값']} for _, row in t.iterrows()]
    axes[1].bxp(boxes, orientation='horizontal', showfliers=False, patch_artist=True,
                boxprops={'facecolor': '#C7DDEE', 'edgecolor': BLUE}, medianprops={'color': RED})
    axes[1].invert_yaxis(); axes[1].set_xlabel('검수 소요시간 (분) · 수염은 최소–최대')
    axes[1].axvline(10, color=RED, linestyle='--', alpha=.5)
    axes[1].grid(axis='x', alpha=.15)
    save(fig, 2)

    r = results[3]; fig, axes = canvas(3, ncols=2)
    for ax, t, col, label, fmt in [
        (axes[0], r['chart_loss'], '배상위험_억원', '산식상 배상 위험액 (억 원)', '.2f'),
        (axes[1], r['chart_count'], '오판건수', '가품 오판정 확인 건수 (건)', ',.0f')]:
        colors = [TEAL if '스니커즈' in x else BLUE for x in t.INSPECTOR_DEPT_NM]
        bar(ax, t.INSPECTOR_DEPT_NM, t[col], label, colors, fmt)
    save(fig, 3)

    r = results[4]; fig, axes = canvas(4, ncols=2)
    for ax, t, title in [(axes[0], r['target_ratio'], '검수 ID별 최신 상태 · 271,787건'),
                         (axes[1], r['workload_ratio'], '유효 작업 이력 · 291,548건')]:
        stacked(ax, t, True); ax.set_title(title, pad=16, fontsize=14, weight='bold')
    save(fig, 4)

    r = results[5]; mix = r['item_composition']; counts = r['dept_totals']
    fig, axes = canvas(5, size=(21, 22), nrows=4, ncols=2)
    fig.subplots_adjust(left=.22, right=.96, top=.89, bottom=.065, wspace=.95, hspace=.38)
    item_order = mix.sum(axis=0).sort_values(ascending=False).index
    max_value = mix.to_numpy().max()
    for ax, dept in zip(axes.flat, counts.index):
        vals = mix.loc[dept, item_order]
        ax.barh(item_order, vals, color=TEAL, height=.7)
        ax.invert_yaxis(); ax.set_xlim(0, max_value*1.12)
        ax.set_title(f'{dept}  |  {counts[dept]:,}건', loc='left', fontsize=13, weight='bold')
        ax.set_xlabel('팀 내 상품 비중 (%)'); ax.tick_params(axis='y', labelsize=9)
        ax.grid(axis='x', alpha=.15)
    save(fig, 5)

    heatmap(6, results[6]['heatmap_matrix'], '오판정률 (%)', '.2f', 'YlOrRd')
    staff = results[7]['dept_emp_pivot'].drop(columns='등록인원(명)')
    fig, ax = canvas(7); stacked(ax, staff); save(fig, 7)
    fig, ax = canvas(8); stacked(ax, results[8]['dept_emp_ratio'], True); save(fig, 8)
    heatmap(9, results[9]['count_matrix'], '검수 대상 건수 (건)', ',.0f', 'Blues')
    heatmap(10, results[10]['ratio_matrix'], '팀 내 상품 구성비 (%)', '.1f', 'GnBu')

def verify(results, integrated):
    checks = []
    def check(name, actual, expected):
        passed = bool(actual == expected)
        checks.append({'name': name, 'actual': actual, 'expected': expected, 'passed': passed})
        if not passed:
            raise AssertionError(checks[-1])
    a = load_analysis_data(); staff = load_staff_data()
    check('최종 검수 행 수', len(a), 271787)
    check('최종 검수 ID 유일성', bool(a.INSP_ID.is_unique), True)
    check('최초 검수 분석 모수', len(results[1]['df_q1']), 243454)
    check('2차 재검수 모수', len(results[3]['df_rev2']), 21656)
    check('현재 개정 종류', sorted(a.REV_NO.unique().tolist()), [1, 2])
    t = results[1]['stat_table'].set_index('INSPECTOR_DEPT_NM')
    check('외주팀 배상위험 억원', float(t.loc['외주야간검수팀', '배상위험_억원']), 59.20)
    check('외주팀 오판정률', float(t.loc['외주야간검수팀', '오판정률(%)']), 2.28)
    check('외주팀 10분 미만', float(results[2]['outsource_ratio']), 93.65)
    check('타 부서 10분 미만', float(results[2]['others_ratio']), 28.78)
    check('검수원 마스터 인원', len(staff), 2960)
    check('검수원 사번 유일성', bool(staff.INSPECTOR_EMP_NO.is_unique), True)
    check('인원 집계 일치', int(results[7]['dept_emp_pivot']['등록인원(명)'].sum()), len(staff))
    check('상품별 대상 합계', int(results[9]['count_matrix'].to_numpy().sum()), 243454)
    check('팀 내 상품 구성비', bool(np.allclose(results[10]['ratio_matrix'].sum(), 100, atol=.3)), True)
    check('상품별 오판정률 행렬', list(results[6]['heatmap_matrix'].shape), [19, 8])
    work = pd.read_csv(ROOT / '데이터/valid_workload_counts.csv', index_col=0)
    check('유효 작업 이력 건수', int(work.to_numpy().sum()), 291548)
    check('유효 최초 작업', int(work.FIRST_INSPECTION.sum()), 269892)
    check('유효 재검수 작업', int(work.REINSPECTION.sum()), 21656)
    # 기존 검증 산출물과 별도로, 원자료에서 재계산하여 히트맵 전 셀을 비교한다.
    g = results[1]['df_q1'].copy()
    g['claim'] = (g.INSP_RESULT == 'CLAIM_FAKE_PASS').astype(int)
    independent = g.groupby(['ITEM_NM', 'INSPECTOR_DEPT_NM']).agg(n=('INSP_ID', 'size'), claims=('claim', 'sum'))
    count = independent.n.unstack().reindex_like(results[9]['count_matrix'])
    check('검수 건수 전체 셀 독립 대조', bool(count.equals(results[9]['count_matrix'])), True)
    rate = (independent.claims / independent.n * 100).unstack().reindex_like(results[6]['heatmap_matrix']).round(2)
    check('오판정률 전체 셀 독립 대조', bool(rate.equals(results[6]['heatmap_matrix'])), True)
    for n, key in [(1, 'stat_table'), (2, 'dept_boxplot_df'), (3, 'chart_loss'),
                   (4, 'final_ratio'), (5, 'item_composition'), (6, 'heatmap_matrix'),
                   (7, 'dept_emp_pivot'), (8, 'dept_emp_ratio'), (9, 'count_matrix'), (10, 'ratio_matrix')]:
        check('통합본·개별본 결과 일치 ' + key, bool(integrated[key].equals(results[n][key])), True)
    audit = json.loads((ROOT / '데이터/출처_및_연결기록.json').read_text(encoding='utf-8'))
    for entry in audit['extracted_files']:
        with (ROOT / '데이터' / entry['name']).open('rb') as f:
            check('데이터 사본 무결성 ' + entry['name'], hashlib.file_digest(f, 'sha256').hexdigest(), entry['sha256'])
    for entry in audit['source_files']:
        # 폴더를 다른 PC로 옮겨도 사본만으로 실행 가능하다.
        if Path(entry['path']).is_file():
            with Path(entry['path']).open('rb') as f:
                check('원천 보존 ' + entry['table'], hashlib.file_digest(f, 'sha256').hexdigest(), entry['sha256_before'])
    report = {'executed_at_kst': datetime.now(timezone(timedelta(hours=9))).isoformat(),
              'checks': checks, 'failed': sum(not c['passed'] for c in checks)}
    (OUT / '검증결과.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return report

def gallery(report):
    summaries = [
        '외주야간검수팀: 배상 위험액 59.20억 원, 오판정률 2.28%. 위험액은 실제 지급액이 아닙니다.',
        '10분 미만 비중: 외주야간검수팀 93.65%, 타 부서 전체 28.78%. 소요시간만으로 원인을 단정하지 않습니다.',
        '스니커즈검수1팀 298.88억 원, 2팀 223.50억 원. 재검수 대상으로 선택된 집단의 수치입니다.',
        '대상별 최신 상태와 실제 누적 작업은 분모가 다릅니다. 누적 작업에는 유효 이전 개정 작업을 포함합니다.',
        '각 팀에서 검수한 상품 비중을 동일 축으로 비교합니다. 모든 팀에서 19개 상품이 관측됩니다.',
        '셀 값은 상품·부서별 CLAIM_FAKE_PASS 건수 ÷ 해당 검수 건수 × 100입니다.',
        '검수원 마스터의 사번으로 집계합니다. 재직·비재직을 모두 포함하므로 가용 인력 수와 다릅니다.',
        '직급별 인원을 팀 전체 등록 인원으로 나눈 비율입니다. 반올림으로 합계에 미세한 차이가 날 수 있습니다.',
        '최초 개정 분석 대상 243,454건을 상품·부서로 나눕니다. 원자료의 중복 행을 합산하지 않습니다.',
        '각 부서 열의 합계가 약 100%가 되도록 계산합니다. 상품별 전체 시장 점유율과는 다릅니다.'
    ]
    cards = []
    for i, stem in enumerate(FILES, 1):
        cards.append(f'''<section id="chart{i}"><div class="eyebrow">{'과제' if i <= 5 else '부록'} · {i:02d}</div>
<h2>{html.escape(TITLES[i-1])}</h2><p>{html.escape(summaries[i-1])}</p>
<a href="그래프/{stem}.png" target="_blank"><img loading="lazy" src="그래프/{stem}.png" alt="{TITLES[i-1]}"></a>
<div class="downloads"><a href="그래프/{stem}.png" download>PNG 저장</a><a href="그래프/{stem}.svg" download>SVG 저장</a>
<span>{html.escape(NOTES[i-1])}</span></div></section>''')
    nav = ''.join(f'<a href="#chart{i}">{i:02d} {t}</a>' for i, t in enumerate(TITLES, 1))
    page = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>KREAM · Pandas 발표 시각화</title><style>
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#edf2f7;color:#172b44;font-family:'Malgun Gothic',sans-serif}
header{background:#172b44;color:white;padding:64px max(5vw,24px) 48px}header small{letter-spacing:3px;color:#8bcdcf}h1{font-size:42px;margin:18px 0}
header p{color:#c1cedd;line-height:1.8;max-width:850px}.metrics{display:flex;gap:18px;flex-wrap:wrap;margin-top:32px}.metric{padding:18px 24px;border:1px solid #476078;border-radius:12px;min-width:175px}.metric b{display:block;font-size:28px}.metric span{color:#bdcddd;font-size:13px}
main{max-width:1440px;margin:auto;padding:28px 24px}nav{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:28px}a{color:#3265ad;text-decoration:none}nav a{background:white;padding:10px 14px;border-radius:6px;font-size:13px}
section{background:white;border:1px solid #dfe7ef;border-radius:16px;margin:24px 0;padding:28px;scroll-margin-top:20px}.eyebrow{font-size:12px;letter-spacing:2px;color:#158c88}h2{margin:12px 0;font-size:27px}section p{color:#62748a;line-height:1.8}img{display:block;width:100%;height:auto;border:1px solid #edf2f7}.downloads{display:flex;align-items:center;gap:18px;flex-wrap:wrap;margin-top:18px;font-size:13px}.downloads a{font-weight:bold}.downloads span{color:#62748a}footer{padding:24px 0 48px;font-size:13px;color:#62748a;line-height:1.9}
@media(max-width:700px){h1{font-size:30px}section{padding:14px}main{padding:15px}.metric{min-width:135px}h2{font-size:22px}}
</style><header><small>KREAM / PANDAS VISUAL REPORT</small><h1>검수 운영을 데이터로 읽다</h1>
<p>보내주신 Pandas 분석 10개를 현재 최종 데이터에 연결한 발표용 시각화입니다. 기존 데이터를 유지하고, 이 폴더 안의 데이터 사본과 실행용 코드로 실행합니다. 합성 데이터 분석이며 실제 기업의 운영 실적이 아닙니다.</p>
<div class="metrics"><div class="metric"><b>243,454</b><span>최초 개정 분석 대상</span></div><div class="metric"><b>21,656</b><span>2차 재검수 대상</span></div><div class="metric"><b>2,960</b><span>마스터 등록 검수원</span></div><div class="metric"><b>10</b><span>발표용 그래프</span></div></div></header><main>'''
    page += '<nav>' + nav + '</nav>' + ''.join(cards)
    page += f'<footer>검증 {len(report["checks"])}개 통과 · 실패 {report["failed"]}개. 그림을 클릭하면 원본 PNG를 크게 볼 수 있습니다.<br>통계표 CSV는 결과/통계표, 분석 실행 출력은 결과/실행로그에 있습니다. 기간·분모가 다른 최초 검수와 재검수를 단순 비교하여 인과관계로 해석하지 않습니다.<br>인원·작업량 연결 변경과 출처는 데이터/출처_및_연결기록.json 및 안내문을 참고하세요.</footer></main></html>'
    (OUT / '시각화_모아보기.html').write_text(page, encoding='utf-8')

def main():
    setup(); results = {}
    for path in sorted((ROOT / '코드').glob('[0-9][0-9]_*.py')):
        n = int(path.name[:2])
        if n == 0:
            continue
        captured = io.StringIO()
        with redirect_stdout(captured):
            state = runpy.run_path(str(path), run_name='__main__')
        (OUT / '실행로그' / (path.stem + '.txt')).write_text(captured.getvalue(), encoding='utf-8')
        for name, value in state.items():
            if isinstance(value, (pd.DataFrame, pd.Series)) and not name.startswith('df') and name != 'emp_master':
                value.to_csv(OUT / '통계표' / f'{n:02d}_{name}.csv', encoding='utf-8-sig')
        results[n] = state
        print(f'{n:02d} 분석 완료', flush=True)
    assert len(results) == 10
    captured = io.StringIO()
    integrated_path = next((ROOT / '코드').glob('00_*.py'))
    with redirect_stdout(captured):
        integrated = runpy.run_path(str(integrated_path), run_name='__main__')
    (OUT / '실행로그' / (integrated_path.stem + '.txt')).write_text(captured.getvalue(), encoding='utf-8')
    report = verify(results, integrated)
    charts(results); gallery(report)
    print(f'그래프 {len(FILES)}종 PNG·SVG 생성 / 검증 {len(report["checks"])}개 통과')
    print(OUT / '시각화_모아보기.html')

if __name__ == '__main__':
    main()
