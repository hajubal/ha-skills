# SGT — issue-run 프로젝트 전제

ha-skills 플러그인의 `/ha-skills:issue-run` 과 그 에이전트(issue-triage, plan-writer, plan-reviewer, verifier)가 시작할 때 읽는 파일이다. 제품을 모르는 에이전트가 판단할 때 항상 깔고 가야 하는 전제와, 이 레포에서 쓰는 명령·관례를 적는다. **SGT 레포는 팀 공용이라 개인 스킬용 파일을 커밋하지 않는다** — 그래서 이 파일과 Codex 기준(`AGENTS.md`)은 플러그인 저장소의 `projects/ininext/sgt/` 에 둔다. 자세한 설계는 이 저장소의 `docs/issue-run-automation-plan.md`.

## 설정

- 기본 브랜치: `develop` (PR 대상). `main` 은 배포 브랜치라 직접 PR 을 내지 않는다.
- 브랜치 이름 접두사: `hajubal/`
- 계획서 위치: (비움 — 레포 밖 `~/issue-runs/ininext/sgt/<N>/` 에 쓴다. 레포의 `docs/temp/` 관례는 팀 작업용이고 이 파이프라인 산출물은 올리지 않는다)
- 산출물 보고서 위치: `~/issue-runs/ininext/sgt/<N>/`
- 이슈 생성: 반드시 `scripts/gh-issue.sh` (`gh issue create` 금지 — Type·Status·Module 을 못 채운다). 제목은 `type(scope): 증상 — 원인/할 일`.
- 커밋 메시지: 한국어, `type(scope): 요약 (#이슈)` 형식. 본문 마지막 줄에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- 결정 기록은 `docs/design/`, 작업 중 문서는 `docs/temp/` (코드나 CLAUDE.md 가 `temp/` 를 인용하면 안 된다).

## 제품 전제 — 판단할 때 항상 깔고 간다

- **에어갭 설치 제품, SaaS 아님.** 고객이 오프라인 패키지를 받아 유지보수 창에서 수동 설치한다. 롤백·핫픽스는 수일~수주. 우리는 고객 로그를 볼 수 없어 고객이 물어보기 전엔 장애를 모른다.
- **고객 자체 연동.** 고객이 우리 공개 API·helm values·env 위에 자기 연동을 만들었을 수 있고, 그걸 레포에서 grep 으로 알 수 없다. 공개 경로·계약·키 이름의 변경이나 축소는 실제 사용을 확인하기 전까지 보수적으로.
- **위협 모델은 내부망.** 인터넷 노출이 아니라 클러스터 내 횡이동, 일반 사용자 JWT 로의 권한 상승, 스코프 검사 누락, 우발적 포트 노출. 개발 기본 시크릿을 끝내 안 바꾸는 고객이 있다 — 기본값의 폭발 반경을 넓히는 변경은 경고나 검증을 동반해야 한다.
- **외부 호출 불가.** 모델 다운로드·레지스트리 풀·외부 API 모두 막힌다. 새 의존성은 오프라인 패키징(`docs/offline-package-guide.md`)에 포함되는지 먼저 확인.
- **DB 는 PostgreSQL 만.** admin 은 Flyway 로 기동 시 자체 마이그레이션 — 머지된 `sgt-admin/src/main/resources/db/migration/V*.sql` 을 고치면 체크섬 실패로 모든 고객사 admin 이 멈춘다. 스키마 변경은 항상 **새 V 파일**. 머지된 V 파일은 절대 수정 금지.
- **디렉터리별 `CLAUDE.md` 가 함정 목록이다.** 건드리는(또는 평가하는) 디렉터리의 것을 먼저 읽는다. 루트 `CLAUDE.md` 의 "Per-directory CLAUDE.md" 표에 대표 함정이 있다: owasp 기본 sink(#789), **gateway 인증 경로 2곳**(필터와 보호 경로 집합, #632 — 한 곳만 고치면 미인증 노출), admin `ddl-auto: none`, helm 노브의 silent no-op 가드, SDK 수정 후 `npm run build:gateway`, sgtctl values 우선순위.
- **minimal / full 두 배포 구성.** admin 미배포(minimal)와 full 에서 동작이 갈리는 기능(JWT 폐기, 탐지 이력, 모니터링)이 많다. 영향도는 두 구성 모두에 대해 말한다.

## 검증 명령 (verify 단계 — 바뀐 디렉터리별, 해당하는 것 전부 실행)

| 변경 디렉터리 | 명령 (해당 서비스 디렉터리에서) | 성공 기준 |
|---|---|---|
| `sgt-gateway/`, `sgt-admin/` | `JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew test` | exit 0 (셸 기본 Java 는 17 이라 JAVA_HOME 필수) |
| `sgt-owasp/` | `poetry run pytest` | exit 0 |
| `helm/` | `helm template sgt helm/ > /dev/null` 와 `scripts/check-conflict-markers.sh`; values 키를 추가했으면 템플릿에서 읽히는지 `grep` | exit 0, 새 키가 `templates/` 에서 참조됨 |
| `sgt-admin/src/main/resources/db/migration/` | `git diff --diff-filter=M origin/develop...HEAD -- 'sgt-admin/src/main/resources/db/migration/*'` | **출력이 비어 있어야 함**(기존 V 파일 수정 없음), 새 파일은 `--diff-filter=A` 로만 |
| `sgt-admin/src/main/resources/db/migration/` 또는 `sgt-admin/src/main/java/com/initech/sgt/domain/` | 레포 루트에서 `export PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH JAVA_HOME=/opt/homebrew/opt/openjdk@21; (cd sgt-admin && ./gradlew bootJar) && scripts/check-admin-schema.sh` | `① OK`, `② OK` 두 줄. docker(OrbStack) 필요. 스크립트가 셸의 `java` 로 jar 를 띄우므로 **Java 21 이 PATH 앞에** 있어야 한다(아니면 class version 65 오류) |
| `sgt-client/src/` | `npm run build:gateway` | exit 0, gateway 정적 번들이 diff 에 포함됨 |
| `sgt-ctl/` | `cd sgt-ctl && go test ./...` | exit 0 |
| `.github/workflows/` | `.github/CLAUDE.md` 의 로컬 재현 절차 | 해당 절차 통과 |

## 코드 리뷰 관점 (review·pr 단계, 같은 디렉터리의 `AGENTS.md` 와 같은 내용 — pr 단계에서 worktree 에 임시 복사된다)

호환성 파괴, Flyway V 파일 규칙, helm silent no-op, gateway 인증 경로 2곳, 기본값 변경의 폭발 반경, 내부망 위협, 외부 호출 추가 — 이 일곱 가지가 걸리면 Blocker 다.
