-- kream_project_repro 스키마용 재현 SQL (저장된 재현 산출물 비교 근거: evidence/export_comparison.json).
-- 실행 환경·미검증 규칙 및 재현 범위: docs/REPRODUCE.md.
-- 재실행 전 기존 스키마·입력 파일과 실행 순서를 확인한다.
-- 작업 70-1: 분석 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project_repro'
  AND table_name IN (
      'gold_product_risk_summary_v1',
      'gold_department_risk_summary_v1'
  );


-- 작업 70-2: 상품별 위험 분석 테이블 생성
-- 정상 관측이 없는 상품도 사전 기준으로 표시
-- 관측이 없으면 비율은 NULL로 보존

CREATE TABLE kream_project_repro.gold_product_risk_summary_v1 (
    item_std_code VARCHAR(50) NOT NULL,
    standard_item_name VARCHAR(150) NOT NULL,
    inspection_rows BIGINT UNSIGNED NOT NULL,
    fake_pass_claim_rows BIGINT UNSIGNED NOT NULL,
    total_trade_price_krw DECIMAL(24,4) NOT NULL,
    compensation_loss_krw DECIMAL(24,4) NOT NULL,
    claim_rate_pct DECIMAL(9,4),
    loss_to_trade_pct DECIMAL(9,4),
    observation_status VARCHAR(32) NOT NULL,
    first_done_kst DATETIME,
    last_done_kst DATETIME,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (item_std_code)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 70-3: 상품별 최종 결과와 배상금 집계
-- 배상금 비율은 거래가 합계 대비 배상금 합계
-- 배상금이 거래가의 3배이므로 비율이 100을 넘을 수 있음

INSERT INTO kream_project_repro.gold_product_risk_summary_v1 (
    item_std_code,
    standard_item_name,
    inspection_rows,
    fake_pass_claim_rows,
    total_trade_price_krw,
    compensation_loss_krw,
    claim_rate_pct,
    loss_to_trade_pct,
    observation_status,
    first_done_kst,
    last_done_kst,
    rule_version
)
WITH product_stats AS (
    SELECT
        ITEM_STD_CODE,
        COUNT(*) AS inspection_rows,

        SUM(
            CASE WHEN INSP_RESULT = 'CLAIM_FAKE_PASS'
                 THEN 1 ELSE 0 END
        ) AS fake_pass_claim_rows,

        SUM(TRADE_PRICE_KRW) AS total_trade_price_krw,
        SUM(COMPENSATION_LOSS_KRW) AS compensation_loss_krw,
        MIN(INSP_DONE_DT) AS first_done_kst,
        MAX(INSP_DONE_DT) AS last_done_kst

    FROM kream_project_repro.silver_inspection_join_ready
    GROUP BY ITEM_STD_CODE
)
SELECT
    d.STD_CODE,
    d.STD_KOR_NM,
    COALESCE(p.inspection_rows, 0),
    COALESCE(p.fake_pass_claim_rows, 0),
    COALESCE(p.total_trade_price_krw, 0),
    COALESCE(p.compensation_loss_krw, 0),

    ROUND(
        p.fake_pass_claim_rows * 100.0
            / NULLIF(p.inspection_rows, 0),
        4
    ),

    ROUND(
        p.compensation_loss_krw * 100.0
            / NULLIF(p.total_trade_price_krw, 0),
        4
    ),

    CASE
        WHEN p.inspection_rows IS NULL
            THEN 'NO_VALID_OBSERVATIONS'
        ELSE 'OBSERVED'
    END,

    p.first_done_kst,
    p.last_done_kst,
    '20261014_v2'

FROM kream_project_repro.silver_product_std_dict AS d

LEFT JOIN product_stats AS p
  ON p.ITEM_STD_CODE = d.STD_CODE

WHERE d.CODE_TYPE = 'ITEM_MODEL'
  AND d.BANNED_WORD_YN = 'N';

SHOW WARNINGS;


-- 작업 70-4: 부서별 위험 분석 테이블 생성
-- 부서는 현재 정규 마스터에 연결된 부서 기준

CREATE TABLE kream_project_repro.gold_department_risk_summary_v1 (
    department_name VARCHAR(100) NOT NULL,
    inspection_rows BIGINT UNSIGNED NOT NULL,
    fake_pass_claim_rows BIGINT UNSIGNED NOT NULL,
    total_trade_price_krw DECIMAL(24,4) NOT NULL,
    compensation_loss_krw DECIMAL(24,4) NOT NULL,
    claim_rate_pct DECIMAL(9,4),
    loss_to_trade_pct DECIMAL(9,4),
    observation_status VARCHAR(32) NOT NULL,
    first_done_kst DATETIME,
    last_done_kst DATETIME,
    department_basis VARCHAR(40) NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (department_name)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 70-5: 부서별 최종 결과와 배상금 집계

INSERT INTO kream_project_repro.gold_department_risk_summary_v1 (
    department_name,
    inspection_rows,
    fake_pass_claim_rows,
    total_trade_price_krw,
    compensation_loss_krw,
    claim_rate_pct,
    loss_to_trade_pct,
    observation_status,
    first_done_kst,
    last_done_kst,
    department_basis,
    rule_version
)
WITH known_departments AS (
    SELECT DISTINCT DEPT_NM
    FROM kream_project_repro.silver_inspector_master
),
department_stats AS (
    SELECT
        INSPECTOR_DEPT_NM,
        COUNT(*) AS inspection_rows,

        SUM(
            CASE WHEN INSP_RESULT = 'CLAIM_FAKE_PASS'
                 THEN 1 ELSE 0 END
        ) AS fake_pass_claim_rows,

        SUM(TRADE_PRICE_KRW) AS total_trade_price_krw,
        SUM(COMPENSATION_LOSS_KRW) AS compensation_loss_krw,
        MIN(INSP_DONE_DT) AS first_done_kst,
        MAX(INSP_DONE_DT) AS last_done_kst

    FROM kream_project_repro.silver_inspection_join_ready
    GROUP BY INSPECTOR_DEPT_NM
)
SELECT
    k.DEPT_NM,
    COALESCE(p.inspection_rows, 0),
    COALESCE(p.fake_pass_claim_rows, 0),
    COALESCE(p.total_trade_price_krw, 0),
    COALESCE(p.compensation_loss_krw, 0),

    ROUND(
        p.fake_pass_claim_rows * 100.0
            / NULLIF(p.inspection_rows, 0),
        4
    ),

    ROUND(
        p.compensation_loss_krw * 100.0
            / NULLIF(p.total_trade_price_krw, 0),
        4
    ),

    CASE
        WHEN p.inspection_rows IS NULL
            THEN 'NO_VALID_OBSERVATIONS'
        ELSE 'OBSERVED'
    END,

    p.first_done_kst,
    p.last_done_kst,
    'CURRENT_MASTER',
    '20261014_v2'

FROM known_departments AS k

LEFT JOIN department_stats AS p
  ON p.INSPECTOR_DEPT_NM = k.DEPT_NM;

SHOW WARNINGS;


-- 작업 70-6: 두 분석 테이블의 합계 확인
-- 양쪽 모두 정상 검수 건수와 배상금 합계가 같아야 함

SELECT
    'PRODUCT' AS analysis_scope,
    COUNT(*) AS saved_groups,
    SUM(inspection_rows) AS inspection_rows,
    SUM(fake_pass_claim_rows) AS fake_pass_claim_rows,
    SUM(total_trade_price_krw) AS total_trade_price_krw,
    SUM(compensation_loss_krw) AS compensation_loss_krw
FROM kream_project_repro.gold_product_risk_summary_v1

UNION ALL

SELECT
    'DEPARTMENT',
    COUNT(*),
    SUM(inspection_rows),
    SUM(fake_pass_claim_rows),
    SUM(total_trade_price_krw),
    SUM(compensation_loss_krw)
FROM kream_project_repro.gold_department_risk_summary_v1;


-- 작업 70-7: 정상 관측이 없는 상품 확인
-- 이 상품의 비율을 0으로 해석하지 않음

SELECT
    item_std_code,
    standard_item_name,
    inspection_rows,
    claim_rate_pct,
    loss_to_trade_pct,
    observation_status
FROM kream_project_repro.gold_product_risk_summary_v1
WHERE observation_status = 'NO_VALID_OBSERVATIONS'
ORDER BY item_std_code;


-- 작업 70-8: 배상금 합계가 큰 상품 확인

SELECT
    item_std_code,
    standard_item_name,
    inspection_rows,
    fake_pass_claim_rows,
    claim_rate_pct,
    compensation_loss_krw,
    loss_to_trade_pct
FROM kream_project_repro.gold_product_risk_summary_v1
WHERE observation_status = 'OBSERVED'
ORDER BY compensation_loss_krw DESC
LIMIT 10;


-- 작업 70-9: 부서별 오판정 비율과 배상금 확인
-- 상품 구성 차이가 있으므로 이 비율만으로 숙련도를 판단하지 않음

SELECT
    department_name,
    inspection_rows,
    fake_pass_claim_rows,
    claim_rate_pct,
    compensation_loss_krw,
    loss_to_trade_pct
FROM kream_project_repro.gold_department_risk_summary_v1
ORDER BY compensation_loss_krw DESC;