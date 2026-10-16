# 새 GitHub 저장소용 수정 반영본

이 자료는 2026-10-15 팀 프로젝트 GitHub 업로드 패키지를 기반으로 수정한 **새 저장소 업로드 준비본**입니다. 기존 GitHub 저장소에 직접 변경을 가하지 않았습니다.

## 포함된 수정

1. `src/verify_final.py`: 검사 실패 건수가 1개 이상이면 프로세스 종료 코드 1 반환.
2. `docs/REPRODUCE.md`: 저장된 CSV 재현 비교 범위와 미검증 항목 안내 추가.
3. `visualization/pipeline/README.md`: 오래된 재현 상태와 이전 폴더명 수정.
4. `sql/repro/*.sql`: 재현 후보라고 표기한 오래된 첫 줄 안내 주석 일괄 갱신. SQL 실행 로직은 변경하지 않았음.
5. `docs/PRESENTATION_CORRECTIONS.md`: 발표 구성안에 적용할 문구 정리(최종 PPT는 수정하지 않음).
6. `visualization/pipeline/src/make_charts.py`: 시스템 한글 글꼴 사용으로 변경. 배포 묶음에 글꼴 파일은 포함하지 않음.

## 주의

- 원본 데이터와 별도 MySQL 전체 파이프라인을 이번 준비 과정에서 다시 실행하지 않았습니다.
- 저장된 재현 비교 근거는 과거 실행 결과입니다. 작업자가 새로 실행한 검증 결과로 간주하지 마세요.
- 팀원별 기여, 상대팀 기준 차이의 행별 원인 등 미확인 사항은 임의로 확정하지 않았습니다.

## GitHub 웹에서 업로드

- 새 저장소 생성 시 README 자동 추가를 해제합니다.
- 파일 수 제한 때문에 제공한 다섯 ZIP을 각자 압축 해제하고, **각 묶음의 내용물을 원래 상대 경로 그대로** 업로드합니다.
- 새 저장소의 웹 `Add file > Upload files`를 이용하며, 한 번에 100개 미만 파일로 나누어 올립니다.
- 모든 파일이 올라간 뒤 `src/verify_final.py`, `docs/REPRODUCE.md`, `docs/PRESENTATION_CORRECTIONS.md`, `sql/repro/65_save_final_quality_checks.sql`을 확인합니다.
- 기존 저장소는 확인 전까지 삭제하지 마세요.
