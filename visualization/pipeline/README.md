# KREAM 발표용 시각화 프로젝트

검증된 최종 데이터에서 발표용 그래프 9개를 만듭니다. SQL·DB에 연결하거나 원본 데이터를 수정하지 않습니다.

## 바로 보기

`outputs/gallery.html`을 브라우저에서 열면 완성된 그래프와 해석을 볼 수 있습니다. 코드 실행이나 별도 설치 없이 열립니다.

발표 슬라이드에는 `outputs`의 PNG를 삽입하세요. 크기는 2880×1620입니다. 확대가 필요하면 같은 이름의 SVG를 사용하세요. SVG는 한글 표시를 유지하도록 글자를 벡터 경로로 저장합니다.

## VS Code에서 다시 실행

1. ZIP 전체를 압축 해제합니다. 파일 하나만 꺼내면 데이터·글꼴 경로를 찾지 못합니다.
2. VS Code에서 `visualization/pipeline` 폴더를 엽니다.
3. Python 3.10 이상을 사용합니다. 확인한 실행 환경은 Python 3.12입니다.
4. VS Code의 터미널에서 프로젝트 루트 기준으로 실행합니다.

```shell
python -m venv .venv
```

Windows에서는 터미널 프로필을 Command Prompt로 선택한 뒤 다음을 실행할 수 있습니다.

```bat
.venv\Scripts\activate.bat
python -m pip install -r requirements.txt
python src\make_charts.py
```

가상 환경을 활성화하지 않고 직접 실행하려면 다음처럼 실행해도 됩니다.

```bat
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe src\make_charts.py
```

macOS 또는 Linux에서는 다음을 사용합니다.

```shell
source .venv/bin/activate
python -m pip install -r requirements.txt
python src/make_charts.py
```

VS Code의 Python 인터프리터도 생성한 `.venv`로 선택하세요. 터미널에서 `python`을 찾지 못하면 먼저 Python 설치·인터프리터 설정을 확인하세요.

## 폴더 구성

- `src/make_charts.py`: CSV 형식 해석, 행 수 검증, 집계, 그래프 저장 코드.
- `data`: 시각화용 Gold CSV 12개, 내보내기 기준 목록 1개, 컬럼 구조와 출처 메모.
- `fonts`: 나눔고딕 OFL 라이선스 안내. 글꼴 파일은 배포 묶음에 포함하지 않으므로 시스템에 Nanum Gothic 또는 한글 글꼴 설치 필요.
- `outputs`: PNG 9개, SVG 9개, 그림별 수치표 9개, 갤러리, 발표 설명, 검증 기록.
- `requirements.txt`: 실행에 사용한 pandas·matplotlib 버전.

## 그래프 순서

1. 정상·제외·격리 분류: 검수 원본 한 파일만 기준으로 335,000행을 계산.
2. 상품별 배상금 상위 10개: 고가 상품의 금액 부담을 설명.
3. 최초 개정 최종 상태와 재검수 최종 상태: 기간·선택 과정이 다른 집단을 구분.
4. 시간대·부서별 작업량: 연속 기간 최초 검수 262,833건을 관측 1,704일로 나눈 일평균.
5. 월별 작업량: 2022년 1월~2026년 8월의 56개월 전체.
6. 실제값과 예측값: 2026년 9월 1~7일, 건수와 분 단위를 별도 축에서 비교.
7. 예측 오차: 건수·소요시간 WAPE를 분리. 낮을수록 오차가 작음.
8. 인력 시나리오: 한 명당 하루 검수 가능 시간을 240·360·480분으로 가정.
9. 상대팀 기준 건수와 현재 분류 차이: 개선 항목 설명용.

## 데이터와 계산의 주의점

- 원본은 `KREAM_Final_Data_Full_20261015.zip`입니다. ZIP SHA-256은 `data/source_notes.json`에 기록했습니다. 처음의 1,001행으로 잘린 ZIP을 사용하지 않습니다.
- 포함한 CSV는 최종 데이터 28개 중 발표에 필요한 집계 12개와 기준 목록만 선택한 것입니다. 전체 최종 데이터 ZIP의 대체본이 아닙니다.
- 원본 CSV는 헤더 없는 MySQL OUTFILE 형식입니다. 일반 `pd.read_csv`의 기본 옵션으로 읽지 않습니다. 컬럼 구조를 연결하고 NULL, 쉼표, 따옴표와 역슬래시 이스케이프를 구분합니다.
- 코드 실행 시 각 선택 CSV의 행 수와 컬럼 수를 기준 목록에 대조합니다. 잘린 파일이면 그래프를 만들기 전에 중단합니다.
- 금액·소요시간은 Decimal로 읽고 합계를 검증한 후 그래프 표시에서만 실수로 바꿉니다. 그림의 억 원 표시는 반올림된 표시입니다.
- 수치표는 별도 UTF-8 BOM과 헤더를 가진 표준 CSV로 저장합니다. `outputs/chart_data`는 발표 수치 확인용이고, 원본 MySQL 적재 파일을 대신하지 않습니다.
- Excluded에는 정상 이전 개정이 있어 모두 오염으로 해석하면 안 됩니다. 정상 이전 개정은 작업량 이력에 포함될 수 있습니다.
- 부서는 현재 마스터 기준입니다. 완료 시간대는 실제 출근·근무표·가동률을 뜻하지 않습니다.
- 재검수 집단의 높은 비율을 재검수 효과 또는 직원 역량의 인과관계로 해석하지 않습니다.
- 정상 관측이 없는 레고의 비율은 NULL입니다. 거래가 없거나 위험이 0이라는 뜻이 아닙니다.
- 예측은 한 주만 평가했습니다. 100-WAPE를 검증된 정확도라고 표현하지 않습니다.
- 인력의 가용 분 수는 명세서의 실제 근무시간이 아닌 가정입니다. 필요 인원은 추가 채용 인원과 다릅니다.
- 상대팀 기준은 사용자가 대화에 공유한 Q2 답변의 숫자입니다. 실제 행별 분류 원인을 확정할 수 있는 상대팀 SQL은 확보하지 않았습니다.
- 저장된 최종본·재실행본 비교 기록에서 CSV 29개 중 27개는 바이트 단위로 일치하며, 나머지 2개는 기록 시각·출력 파일명 관련 컬럼만 다릅니다. 이 결과가 모든 업무 규칙의 검증 완료를 의미하지는 않습니다. `docs/REPRODUCE.md`와 `evidence/export_comparison.json`을 참고하세요.

## 확인한 실행

선택 CSV 12개에서 기준 행 수·컬럼 수를 검사하고, 분류 합계·가품 오판정·배상금 합계·작업량 범위·평가 실제값 합계와 WAPE를 재계산했습니다. MySQL OUTFILE 파서의 쉼표·따옴표·NULL·빈 문자열·개행·역슬래시·소수 표기도 확인했습니다. 실행 결과는 `outputs/validation.json`에 있습니다.

한글 폰트: 시스템에 설치된 Nanum Gothic을 우선 사용합니다. Google Fonts의 Nanum Gothic은 SIL Open Font License로 배포됩니다. 원본 주소: https://github.com/google/fonts/tree/main/ofl/nanumgothic . 라이선스 전문은 `fonts/OFL.txt`에 포함했습니다.
