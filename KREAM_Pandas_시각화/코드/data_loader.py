"""새 폴더 안의 분석용 CSV만 읽는다. 원천 파일에는 쓰지 않는다."""
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]

def load_analysis_data():
    return pd.read_csv(ROOT / '데이터/clean_kream_inspection_joined.csv', low_memory=False)

def load_staff_data():
    return pd.read_csv(ROOT / '데이터/inspector_master.csv', low_memory=False)

def load_workload_ratio():
    work = pd.read_csv(ROOT / '데이터/valid_workload_counts.csv', index_col=0)
    ratio = work.div(work.sum(axis=1), axis=0) * 100
    ratio = ratio.reindex(columns=['FIRST_INSPECTION', 'REINSPECTION'])
    ratio.columns = ['1차_작업량(%)', '2차_작업량(%)']
    return ratio.round(2)
