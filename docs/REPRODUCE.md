# 환경과 재현 실행 안내

## 저장된 재현 결과와 확인 범위

2026-10-15에 저장된 최종본과 재실행본의 비교 기록은 `evidence/export_comparison.json`에 있습니다. 이 수치는 저장된 산출물 간 비교 결과이며 모든 환경에서의 재현을 새로 보장하지 않습니다.

| 비교 항목 | 기록된 결과 |
| --- | --- |
| 비교 대상 CSV | 29개 |
| 바이트 단위 일치 | 27개 |
| 차이가 있는 CSV | 2개 |
| `data_quality_check_results_v1.csv` | `checked_at_kst` |
| `export_manifest_v1.csv` | `output_file_name`, `captured_at_kst` |

점검 구간 규칙은 필수 기간과 판정 조건이 없어 `NOT_CHECKED`로 유지합니다. 상대팀 분류 기준과의 차이는 `RECORDED_DIFFERENCE`로 기록합니다. 어느 항목도 `PASS`로 간주하지 않습니다.

입력 데이터 또는 처리 SQL이 변경되면 해당 조건에서 재현 검증을 다시 수행해야 합니다. `sql/repro/` 파일은 기존 스키마에 무조건 반복 실행하지 않습니다.

## 확인한 환경과 입력

- MySQL 8.4 계열과 Workbench를 사용했다. 실제 환경 확인 기록은 8.4.11을 기준으로 대조했다.
- Python 검증은 Pandas 2.2.3을 사용한다. 그래프 재생성은 Matplotlib 3.10.8을 사용한다.
- 원본 CSV 5개는 공급 순서를 보존한다. 원본 행 번호가 추적 키에 사용되므로 정렬·중간 삭제 후 적재하지 않는다.
- 최종 결과 ZIP과 원본 CSV는 서로 다른 입력이다. 최종 결과를 Bronze 적재용 원본 대신 사용하지 않는다.

## 1. 읽기 전용 환경 확인

```sql
SELECT VERSION();
SELECT @@secure_file_priv, @@session.sql_mode;
SELECT table_schema, COUNT(*) AS table_count
FROM information_schema.tables
WHERE table_schema IN ('kream_project', 'kream_project_repro')
GROUP BY table_schema;
```

재현용 파일은 kream_project_repro를 대상으로 한다. 기존 검증 결과가 있는 스키마에 CREATE·LOAD를 통째로 다시 실행하지 않는다. 원본과 출력 경로는 서버의 secure_file_priv 허용 경로와 일치해야 한다.

## 2. 입력 CSV 경로

제공 SQL의 경로는 Windows MySQL 서버의 `C:/ProgramData/MySQL/MySQL Server 8.4/Uploads/`를 사용한다. 다른 환경에서는 실제 허용 경로로 바꿔야 한다. 서버에서 읽는 LOAD DATA INFILE이므로 클라이언트 PC 경로와 서버 파일 경로를 혼동하지 않는다.

`src/profile_bronze.py`로 파일별 건수·해시·헤더를 먼저 확인한다. 원본 예상 건수는 32 / 1,050 / 3,150 / 335,000 / 335,000이다.

## 3. SQL 파일 구분

| 위치 | 의미 | 실행 대상 |
| --- | --- | --- |
| sql/archive | 사용자 보관 원본 87개 | 작업 이력과 원문 비교용 |
| sql/repro | 별도 스키마용 재현 파일 85개 | execution_order 순서로 실행 |
| sql/execution_order.txt | 파일 이름의 정확한 순서 | 54A~54E 포함 |
| sql/change_log.json | 원본 대비 조정·분리·복원 이유 | 경로·구간 변경 근거 |
| sql/83_check_reproduction_environment.sql | 재현 환경 조회 | 먼저 상태 확인 |

49·77·78·79번은 확보한 실제 정의와 자료로 보완했다. 조건부 복구와 중복 적재 구간을 기본 흐름에서 분리한 것이며 업무 정제 규칙을 줄인 것이 아니다.

## 4. 실행 순서

1. 00~07: 환경, 원본 테이블, 원본 적재와 건수.
2. 08~25: 사전·마스터·검수 기초 진단, 날짜·ID·수치 검사.
3. 26~38: 진단 결과 저장과 키·참조 검사.
4. 39~45: 정상 사전·직원·카테고리와 마스터 격리·제외.
5. 46~53: 검수 참조와 통합 검사.
6. 54 → 54A → 54B → 54C → 54D → 54E: 최초 분류, 기준 차이 조사, 코드 근거 복구와 재분류.
7. 55~65: 최종 검수, 격리·제외, 재조인, 원본 대응과 정제 로그, 품질 결과.
8. 66~71: 분석 범위, 최종 결과·작업 이력·상품·부서·교차 집계.
9. 72~75: 예측 입력, 예측, 평가와 가용시간 시나리오.
10. 76~79, 81: 구조·컬럼·제약조건 목록, 출력 기준 목록, 전체 내보내기.

12번 당시 복구와 80번 초기 출력은 기본 재현 순서에서 분리했다. 자세한 파일 순서는 execution_order.txt를 따른다.

## 5. 재시작 판단

- CREATE와 LOAD가 이미 성공한 경우 해당 구간을 다시 실행하지 않는다.
- 같은 키를 다시 INSERT하면 중복키 오류가 날 수 있다. 먼저 현재 행 수와 직전 성공 구간을 확인한다.
- 오래 걸리는 쿼리를 중단한 경우 작업 완료 여부와 생성된 결과를 확인한 뒤 재시작 범위를 정한다.
- 기존 테이블 삭제나 전역 옵션 변경을 기본 복구 방법으로 사용하지 않는다.
- 생성·적재와 읽기 전용 진단을 구분한다.

## 6. CSV 내보내기

화면에 보이는 결과 제한과 DB 실제 행 수를 구분한다. 전체 내보내기에는 명시적 전체 LIMIT와 OUTFILE 경로를 적용했다. MySQL OUTFILE은 이미 존재하는 같은 이름의 파일에 덮어쓰지 않으므로 새 출력 위치나 파일 이름을 사용한다.

최종 ZIP은 CSV 29개다. 28개 출력 데이터와 내보내기 목록 1개로 구성된다. 헤더가 없고 NULL은 `\N`이다. Excel이나 일반 CSV 자동 추론 결과로 전체 건수와 NULL 의미를 판단하지 않는다.

## 7. Python 검증

```bash
python -m pip install -r requirements.txt
python src/profile_bronze.py --raw-dir data/raw --output reports/bronze
python src/profile_standard_gap.py --raw-dir data/raw
python src/audit_bronze.py --raw-dir data/raw --final-zip data/exports/KREAM_Repro_Final_Data_Full_20261015.zip
python src/verify_final.py --source data/exports/KREAM_Repro_Final_Data_Full_20261015.zip
python src/verify_team_analysis.py --source data/exports/KREAM_Repro_Final_Data_Full_20261015.zip
python src/verify_forecast.py --source data/exports/KREAM_Repro_Final_Data_Full_20261015.zip
python src/build_documents.py
python src/build_team_docs.py
```

두 ZIP 비교:

```bash
python src/verify_export_comparison.py --original data/exports/KREAM_Final_Data_Full_20261015.zip --repro data/exports/KREAM_Repro_Final_Data_Full_20261015.zip
```

기존 Gold 시각화 코드는 `visualization/pipeline/README.md`의 실행 방법을 따른다. 팀원이 제공한 운영 분석 PNG 10개는 원본을 보존하고 재계산 CSV를 별도로 제공한다.

## 8. 통과 기준

- 원본 335,000행이 정상·격리·제외로 일대일 분류.
- 정상 271,787 / 격리 33,854 / 제외 29,359.
- 검수원 정상 2,960 / 카테고리 정상 970 / 사전 32.
- 현재 상태·작업 이력·배상금·분석·예측의 업무 결과 일치.
- 원본과 정상 값, 격리·제외의 원본 근거 일치.
- 점검 구간의 미검증 상태와 상대팀 기준 차이는 통과 0건으로 바꾸지 않고 보존.
- 원본 최종본과 재실행 최종본의 업무 CSV 27개 동일. 나머지 2개는 허용된 실행 시각·파일 정보만 차이.
