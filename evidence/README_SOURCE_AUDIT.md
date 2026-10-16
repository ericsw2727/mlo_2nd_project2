# README 근거 더블 체크

첨부 발표 구성안과 시각화의 표현을 최종 데이터·명세·SQL·Pandas 실행 결과에 대조했다. 아래 검산은 문서 작성 과정의 별도 근거 점검이며 기존 정제 규칙을 변경하지 않는다.

| README 주장 | 근거 파일 | 확인 방법 |
| --- | --- | --- |
| 원본 5개·49개 컬럼 | reports/bronze/source_manifest.csv | 파일 헤더·행 수·원본 해시 재확인 |
| 충돌 2400그룹·4800행, 시간역전6056행 | reports/bronze/asis_audit_summary.json | 원본 직접 진단·격리 원본 추적 |
| 정상271787·격리33854·제외29359 | reports/bronze/asis_audit_summary.json | 행 분류 일대일 대사 |
| 제외 중복9598·과거유효19761 | reports/team_analysis/verification.json | 제외 사유별 재계산 |
| 표준149·189·43·32·393 | dictionaries/ 및 evidence/readme_audit.json | CSV별 행 수 직접 확인 |
| 문서화28테이블·393컬럼·제약54개 | metadata/catalog.json | 제약 이름 단위와 컬럼 단위 메타데이터 구분 |
| SQL14통과·1미검증·1차이 | reports/team_analysis/sql_quality_snapshot.csv | 상태별 재계산 |
| Pandas482검사 실패0 | reports/pandas_verification_summary.json | 최신 재실행 ZIP으로 코드 재실행 |
| 일반검수243454건 | reports/team_analysis/verification.json | REV_NO=1·2022.01~2026.08 필터 |
| 외주팀633건·59.20억원 | reports/team_analysis/general_department_risk.csv | 부서별 건수·Decimal 금액 표시값 비교 |
| 10분미만93.65%·다른부서28.78% | reports/team_analysis/general_duration_under10.csv | 일반검수의 행 단위 시간 재계산 |
| 재검수4804/3753·3733/2903 | reports/team_analysis/reinspection_department_risk.csv | 2026.10월 재검수 분모 재계산 |
| 8개팀·19종 | reports/team_analysis/product_department_counts.csv | 모든 부서의 양수 관측 상품 수 확인 |
| 등록인원2960명 | reports/team_analysis/department_position_counts.csv | 비재직 포함·부서와 직급 교차 합계 |
| 작업이력291548·최초269892·재검수21656 | reports/team_analysis/valid_workload_mix_counts.csv | 시간대별 Gold 합계 대사 |
| 입력8173건·126839분·실제2012건·30443분 | evidence/forecast_verification.json | 입력·실제 CSV 직접 합산 |
| WAPE4.2690/4.1128·7.1242/7.6594 | evidence/forecast_verification.json | 일별 예측·실제값에서 재계산 |
| 최종 CSV29개 중 업무27개 동일 | evidence/export_comparison.json | 바이트와 변경 컬럼 검사 |
| 시각화10개 원본 보존 | evidence/provided_assets.csv | 제공 ZIP과 포함 이미지 바이트 동일 |

## 첨부 자료에서 확인한 표현 조정

- 일반 검수·재검수·최종 상태·유효 작업량·등록 인원의 기간과 분모를 분리했다.
- 원천의 OK·PASSED는 각각 0건이었다. 허용 별칭 예시와 실제 정제 실적을 구분했다.
- 32행 공식 코드와 전체 표준 사전을 구분했다.
- 14개 SQL 통과와 482개 Pandas 검사는 서로 다른 범위로 설명했다.
- 실제 배상금 지급·개선 효과·인과·개인 능력을 판정 코드와 시간 분포만으로 확정하지 않았다.
- PNG 생성 메타데이터와 기존 코드에서 Matplotlib을 확인했고 미확인 라이브러리는 기술 목록에 추가하지 않았다.
- 팀명·팀원별 역할·공식 기간·저장소 URL은 자료에서 확정되지 않아 추측하지 않았다.

## 원본 첨부 해시

- 발표 구성안 PDF: `aa20aca4fe3ea2e4aa988078eb5c7e24e4815610648e4c27aacdfe32f6494c85`
- 시각화 ZIP: `cc50a5913de83f17ee984bc83aa8d72a25e9ef6de8c7575c6adfeebd967c25e4`

제공된 PDF와 PNG는 출처 자료다. 재계산 CSV와 스크립트는 이 저장소의 검증 근거다. 모든 이미지의 픽셀에 대해 자동 OCR 인증을 했다는 의미로 사용하지 않는다.