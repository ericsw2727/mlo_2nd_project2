-- 작업 71-1: 교차 분석 테이블 존재 여부 확인

SELECT COUNT(*) AS existing_tables
FROM information_schema.tables
WHERE table_schema = 'kream_project'
  AND table_name = 'gold_risk_cross_summary_v1';


-- 작업 71-2: 상품, 부서, 최종 검수 차수와 기간별 분석 테이블 생성

CREATE TABLE kream_project.gold_risk_cross_summary_v1 (
    item_std_code VARCHAR(50) NOT NULL,
    standard_item_name VARCHAR(150) NOT NULL,
    department_name VARCHAR(100) NOT NULL,
    final_revision_type VARCHAR(32) NOT NULL,
    analysis_period VARCHAR(40) NOT NULL,
    inspection_rows BIGINT UNSIGNED NOT NULL,
    fake_pass_claim_rows BIGINT UNSIGNED NOT NULL,
    total_trade_price_krw DECIMAL(24,4) NOT NULL,
    compensation_loss_krw DECIMAL(24,4) NOT NULL,
    claim_rate_pct DECIMAL(9,4) NOT NULL,
    loss_to_trade_pct DECIMAL(9,4),
    first_done_kst DATETIME NOT NULL,
    last_done_kst DATETIME NOT NULL,
    rule_version VARCHAR(32) NOT NULL,

    PRIMARY KEY (
        item_std_code,
        department_name,
        final_revision_type,
        analysis_period
    )
)
ENGINE = InnoDB
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_0900_bin;


-- 작업 71-3: 최종 정상 상태의 교차 분석 저장
-- 검수 작업량 기록과 달리 주문별 최종 상태만 사용
-- 재검수 비율 차이를 재검수가 오류의 원인이라는 뜻으로 해석하지 않음

INSERT INTO kream_project.gold_risk_cross_summary_v1 (
    item_std_code,
    standard_item_name,
    department_name,
    final_revision_type,
    analysis_period,
    inspection_rows,
    fake_pass_claim_rows,
    total_trade_price_krw,
    compensation_loss_krw,
    claim_rate_pct,
    loss_to_trade_pct,
    first_done_kst,
    last_done_kst,
    rule_version
)
WITH risk_base AS (
    SELECT
        ITEM_STD_CODE,
        ITEM_NM,
        INSPECTOR_DEPT_NM,
        INSP_RESULT,
        TRADE_PRICE_KRW,
        COMPENSATION_LOSS_KRW,
        INSP_DONE_DT,

        CASE
            WHEN REV_NO = 1
                THEN 'FIRST_REVISION_FINAL'
            ELSE 'REINSPECTION_FINAL'
        END AS final_revision_type,

        CASE
            WHEN DATE(INSP_DONE_DT) < '2022-01-01'
                THEN 'ISOLATED_EARLY_PERIOD'
            WHEN DATE(INSP_DONE_DT) >= '2026-10-01'
                THEN 'REINSPECTION_BATCH_PERIOD'
            WHEN DATE(INSP_DONE_DT) >= '2026-09-01'
                THEN 'PARTIAL_BOUNDARY_MONTH'
            ELSE 'CONTINUOUS_PERIOD'
        END AS analysis_period

    FROM kream_project.silver_inspection_join_ready
)
SELECT
    ITEM_STD_CODE,
    ITEM_NM,
    INSPECTOR_DEPT_NM,
    final_revision_type,
    analysis_period,
    COUNT(*),

    SUM(
        CASE WHEN INSP_RESULT = 'CLAIM_FAKE_PASS'
             THEN 1 ELSE 0 END
    ),

    SUM(TRADE_PRICE_KRW),
    SUM(COMPENSATION_LOSS_KRW),

    ROUND(
        SUM(
            CASE WHEN INSP_RESULT = 'CLAIM_FAKE_PASS'
                 THEN 1 ELSE 0 END
        ) * 100.0 / COUNT(*),
        4
    ),

    ROUND(
        SUM(COMPENSATION_LOSS_KRW) * 100.0
            / NULLIF(SUM(TRADE_PRICE_KRW), 0),
        4
    ),

    MIN(INSP_DONE_DT),
    MAX(INSP_DONE_DT),
    '20261014_v2'

FROM risk_base
GROUP BY
    ITEM_STD_CODE,
    ITEM_NM,
    INSPECTOR_DEPT_NM,
    final_revision_type,
    analysis_period;

SHOW WARNINGS;


-- 작업 71-4: 교차 분석의 전체 합계 확인

SELECT
    COUNT(*) AS saved_groups,
    SUM(inspection_rows) AS inspection_rows,
    SUM(fake_pass_claim_rows) AS fake_pass_claim_rows,
    SUM(total_trade_price_krw) AS total_trade_price_krw,
    SUM(compensation_loss_krw) AS compensation_loss_krw
FROM kream_project.gold_risk_cross_summary_v1;


-- 작업 71-5: 최종 검수 차수와 기간별 오판정 비율 확인
-- 비율의 평균이 아니라 건수를 합산해 비율을 다시 계산

SELECT
    final_revision_type,
    analysis_period,
    SUM(inspection_rows) AS inspection_rows,
    SUM(fake_pass_claim_rows) AS fake_pass_claim_rows,

    ROUND(
        SUM(fake_pass_claim_rows) * 100.0
            / SUM(inspection_rows),
        4
    ) AS claim_rate_pct,

    SUM(compensation_loss_krw) AS compensation_loss_krw

FROM kream_project.gold_risk_cross_summary_v1
GROUP BY
    final_revision_type,
    analysis_period
ORDER BY
    final_revision_type,
    analysis_period;


-- 작업 71-6: 배상금 상위 상품 3개의 부서별 비교
-- 연속 관측 기간이며 최초 검수가 최종 상태인 주문만 비교
-- 전체 교차 분석 데이터는 모두 보존하며 조회 대상만 선택

WITH priority_products AS (
    SELECT item_std_code
    FROM kream_project.gold_product_risk_summary_v1
    WHERE observation_status = 'OBSERVED'
    ORDER BY compensation_loss_krw DESC, item_std_code
    LIMIT 3
)
SELECT
    c.item_std_code,
    c.standard_item_name,
    c.department_name,
    SUM(c.inspection_rows) AS inspection_rows,
    SUM(c.fake_pass_claim_rows) AS fake_pass_claim_rows,

    ROUND(
        SUM(c.fake_pass_claim_rows) * 100.0
            / SUM(c.inspection_rows),
        4
    ) AS claim_rate_pct,

    SUM(c.compensation_loss_krw) AS compensation_loss_krw

FROM kream_project.gold_risk_cross_summary_v1 AS c

JOIN priority_products AS p
  ON p.item_std_code = c.item_std_code

WHERE c.analysis_period = 'CONTINUOUS_PERIOD'
  AND c.final_revision_type = 'FIRST_REVISION_FINAL'

GROUP BY
    c.item_std_code,
    c.standard_item_name,
    c.department_name

ORDER BY
    c.item_std_code,
    inspection_rows DESC;


-- 작업 71-7: 기존 상품별, 부서별 분석과 교차 분석 대조
-- different_summary_groups는 양쪽 모두 0이어야 함

WITH product_rollup AS (
    SELECT
        item_std_code,
        SUM(inspection_rows) AS inspection_rows,
        SUM(fake_pass_claim_rows) AS claim_rows,
        SUM(total_trade_price_krw) AS trade_price,
        SUM(compensation_loss_krw) AS loss_krw
    FROM kream_project.gold_risk_cross_summary_v1
    GROUP BY item_std_code
),
department_rollup AS (
    SELECT
        department_name,
        SUM(inspection_rows) AS inspection_rows,
        SUM(fake_pass_claim_rows) AS claim_rows,
        SUM(total_trade_price_krw) AS trade_price,
        SUM(compensation_loss_krw) AS loss_krw
    FROM kream_project.gold_risk_cross_summary_v1
    GROUP BY department_name
)
SELECT
    'PRODUCT' AS comparison_scope,
    COUNT(*) AS checked_groups,

    SUM(
        CASE
            WHEN p.inspection_rows <> COALESCE(r.inspection_rows, 0)
              OR p.fake_pass_claim_rows <> COALESCE(r.claim_rows, 0)
              OR p.total_trade_price_krw <> COALESCE(r.trade_price, 0)
              OR p.compensation_loss_krw <> COALESCE(r.loss_krw, 0)
            THEN 1 ELSE 0
        END
    ) AS different_summary_groups

FROM kream_project.gold_product_risk_summary_v1 AS p

LEFT JOIN product_rollup AS r
  ON r.item_std_code = p.item_std_code

UNION ALL

SELECT
    'DEPARTMENT',
    COUNT(*),

    SUM(
        CASE
            WHEN p.inspection_rows <> COALESCE(r.inspection_rows, 0)
              OR p.fake_pass_claim_rows <> COALESCE(r.claim_rows, 0)
              OR p.total_trade_price_krw <> COALESCE(r.trade_price, 0)
              OR p.compensation_loss_krw <> COALESCE(r.loss_krw, 0)
            THEN 1 ELSE 0
        END
    )

FROM kream_project.gold_department_risk_summary_v1 AS p

LEFT JOIN department_rollup AS r
  ON r.department_name = p.department_name;