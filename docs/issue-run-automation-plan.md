# `/issue-run` — 이슈 처리 파이프라인 자동화 작업 계획서

작성일 2026-11-08 · 상태: 사용자 승인 대기 · 이 문서는 `docs/temp/` 규칙에 따라 작업 종료 시 `design/` 승격 또는 삭제

## 1. 목적

GitHub 이슈 1건을 "검토 → 계획 → 구현 → 검증 → PR → 머지 → 이슈 종료"까지 처리하는 과정에서
사람이 하는 **프롬프트 릴레이와 터미널 전환을 없애고**, 사람의 개입을 **판단이 필요한 2곳(게이트)** 으로 고정한다.

| 분류 | 현재(16단계 수동) | 목표 |
|---|---|---|
| 판단 개입 | 이슈 선택, 계획 검토, 머지 결정 | **GATE 1(계획 승인), GATE 2(머지 승인)** 2곳 + `/autofix-pr` 입력 1회 |
| 프롬프트 릴레이 | 검토→계획→검토→개발→리뷰→수정→PR 7회 입력 | `/issue-run <N>` 1회 |
| 도구 전환 | PR 링크 복사 → Codex 터미널 → 리뷰 → 댓글 지시 → 복귀 | `codex review` CLI 자동 호출 |
| 대기·마무리 | approve 확인 → 머지 → 이슈 댓글 → close | `/loop` 폴링 → 알림 → 승인 후 자동 |

## 2. 확정된 결정 (검증 근거 포함)

| # | 결정 | 근거 |
|---|---|---|
| D1 | 에이전트 간 "토론"이 아니라 **상태 머신 + 파일 핸드오프**. 통신은 파일·이슈 댓글·PR 댓글로만 | 재개·디버깅 가능, 컴팩션에 안전 |
| D2 | `/issue-run` 은 **메인 컨텍스트**에서 실행(`context: fork` 금지). 단계 작업만 서브에이전트에 위임 | 공식 문서: 서브에이전트는 `AskUserQuestion` 사용 불가 → 게이트 질문은 메인만 가능 |
| D3 | 리뷰어·검증자는 작성자와 **다른 fresh 컨텍스트**, 가능하면 다른 모델. fork 금지 | fork 는 자기 산출물을 확인해 주는 것으로 끝남 |
| D4 | 모든 반복 루프는 **2회 상한 + 동일 지적 반복 시 종료**, 미해결은 PR 본문에 기록 | 리뷰어-수정자 핑퐁 방지(OpenCode 워크플로 사례) |
| D5 | Codex 리뷰는 **`codex review --base origin/develop`** CLI (33초, 실행 검증). GitHub `@codex review` 앱은 조직 미설치(installations: slack, claude 뿐) | `--base` 와 커스텀 프롬프트는 상호 배타(공식 문서) → 리뷰 기준은 `AGENTS.md` |
| D6 | **`/autofix-pr` 은 사용자가 수동 입력**. `claude -p "/autofix-pr"` 불가("isn't available"), `claude --cloud` 는 PR 구독 단계가 없어 대체 불가 | 바이너리 분석: spawn + 서버측 subscribe 2단계 |
| D7 | 게이트 알림은 모델 판단이 아니라 **`Notification` 훅(`idle_prompt|permission_prompt`)** | 모델이 잊어도 발화 |
| D8 | 결과 보고서는 `ha-skills:explain-diff-html` 로 **close 단계에서 1회**, 입력 = 이슈 + 승인 계획서 + 최종 diff, 출력 = `~/sgt-reports/` + 이슈 댓글 요약. 실패해도 파이프라인 중단 안 함 | PR 시점 생성은 autofix 이후 diff 와 어긋남 |
| D9 | PR 생성은 `ha-skills:pr`(draft, 리뷰어 자동 요청 없음) | 사용자 전역 규칙이 이미 반영된 스킬 |
| D10 | 페르소나는 "이력서"가 아니라 **4블록 직무기술서**(전제·할 일·기준·출력). 규칙 블록은 andymai/claude-agent-team, obra/superpowers(MIT)에서 발췌·개작 | 범용 역량 나열형(wshobson, VoltAgent)은 행동을 바꾸지 않음 |
| D11 | 자동 머지 금지. GATE 2 는 알림 후 사용자 승인 | 되돌리기 비싼 행위 |
| D12 | worktree 는 `EnterWorktree(name)` 그대로 사용 | `gh repo view` 기본 브랜치 = `develop` → `fresh` 모드가 `origin/develop` 에서 분기 (이전 "main 분기" 우려는 오류였음) |
| D13 | 에이전트 기본 모델 **opus**(사용자 지정, 2026-11-08). plan-reviewer 도 opus — 독립성은 fresh 컨텍스트로, 모델 다양성은 PR 단계의 Codex 로 확보 | 승인 시 사용자 지시. 리뷰어를 sonnet 으로 낮추면 다양성보다 리뷰 품질 손실이 큼. 한 줄(`model:`)로 전환 가능 |
| D14 | 공통 전제는 `.claude/skills/sgt-context/SKILL.md`(숨김 스킬) 로 두고 에이전트 `skills:` 로 주입. `.claude/agents/_sgt-context.md` 는 에이전트로 파싱되므로 쓰지 않음 | 공식 문서: 서브에이전트 `skills` 필드는 시작 시 본문 전체 주입 |
| D15 | 1차 검증 이슈 **#958** (admin 단일 모듈, 비밀번호 복잡도·세션 타임아웃·업로드 상한) | 사용자 지정 |

## 3. 파이프라인

```
/issue-run <N>                      메인 컨텍스트 · disable-model-invocation
  triage     issue-triage 에이전트(fresh)      → 판정(진행/보류/닫기) + 정정안 초안
  plan       plan-writer 에이전트(fresh)       → docs/temp/<N>-<slug>-plan.md
  plan-rev   plan-reviewer 에이전트(fresh, 다른 model) ×2 상한
■ GATE 1     Notification 훅 → 알림 → 사용자: 승인 / 수정 지시 / 보류 / 닫기
  impl       EnterWorktree → ponytail 로 구현(메인 또는 implementer 에이전트)
  verify     verifier 에이전트(fresh): 실행 검증 + 계획 대비 drift + SGT 체크리스트 + 변조 가드
             실패 → impl 1회 재시도 → 재실패 → GATE 1 복귀(중간 수정 금지)
  review     Skill code-review --fix ×2 상한
  pr         Skill ha-skills:pr → codex review --base origin/develop > review.md
             → gh pr comment --body-file → "지금 /autofix-pr 을 입력하세요" 안내 후 대기
■ GATE 2     /loop: reviewDecision=APPROVED && gh pr checks 전부 pass → 알림 → 사용자 머지 승인
  close      gh pr merge → report-writer(explain-diff-html) → 이슈 댓글 → gh issue close
             → docs/temp 계획서 정리(design 승격/삭제 — 사용자 한 줄 확인) → 상태 파일 마감
```

### 상태 파일 `~/issue-runs/<owner>/<repo>/<N>.json`(D16 이전엔 `~/sgt-runs/<N>.json`)

```json
{ "issue": 1234, "phase": "awaiting-plan-approval", "worktree": ".claude/worktrees/issue-1234",
  "branch": "hajubal/issue-1234-...", "plan": "docs/temp/1234-xxx-plan.md", "pr": null,
  "loops": { "plan-rev": 1, "verify": 0, "review": 0 },
  "unresolved": [], "history": [ {"phase":"triage","at":"...","verdict":"진행"} ] }
```

`/issue-run <N>` 재실행 시 `phase` 에서 이어간다. `/issue-run <N> abort` 는 worktree·브랜치·draft PR 정리 후 `aborted` 로 마감.

## 4. 산출물 목록

| 경로 | 내용 | 차수 |
|---|---|---|
| `AGENTS.md` (레포 루트, 신규) | Codex 용. "CLAUDE.md 와 디렉터리별 CLAUDE.md 를 따른다" + 리뷰 가이드라인(P0/P1 만, 에어갭·호환성·내부망 관점) | 1 |
| `.claude/settings.json` | `Notification` 훅(`idle_prompt|permission_prompt`) → `scripts/notify.sh` | 1 |
| `scripts/notify.sh` (신규) | macOS 알림(osascript) + 선택적 Slack webhook(env 없으면 skip) | 1 |
| `.claude/agents/_sgt-context.md` (신규) | 공통 전제 블록. 각 에이전트 `skills` 또는 본문 include 로 주입 | 1 |
| `.claude/agents/issue-triage.md` | §6 | 1 |
| `.claude/agents/plan-writer.md` | §6 | 1 |
| `.claude/agents/plan-reviewer.md` | §6 | 1 |
| `.claude/skills/issue-run/SKILL.md` | 오케스트레이터. `arguments: [issue, action]`, 상태 머신, 게이트 | 1(triage→GATE 1) / 2 / 3 확장 |
| `.claude/skills/issue-run/references/phases.md` | 단계별 입출력 계약·상한·실패 시 동작(§5) | 1 |
| `.claude/agents/verifier.md` | §6 | 2 |
| `.claude/agents/report-writer.md` | explain-diff-html 호출 래퍼(독자: 처음 보는 동료) | 3 |
| `~/sgt-runs/`, `~/sgt-reports/` | 런타임 디렉터리(레포 밖) | 1 |

## 5. 단계별 명세

| 단계 | 실행자 | 입력 | 출력 | 통과 기준 | 상한 / 실패 시 |
|---|---|---|---|---|---|
| triage | issue-triage | `gh issue view N` 본문·댓글, 코드 | 판정 + 사실 정정(파일:라인) + 범위 정정 + 영향도 | 모든 지적에 코드 경로 | 보류/닫기 → GATE 1 에서 사용자 결정 |
| plan | plan-writer | triage 산출물, 이슈 | 계획서: 세션 형태, 파일 목록, 참조 구현, **완료 조건 + 검증 명령어 원문**, 리스크/Spikes, 결정 포인트 | 모든 파일 경로가 세션 내 Read/Grep 결과 | 미확인 사항은 Spikes 로, 추측 금지 |
| plan-rev | plan-reviewer | 계획서 **파일만** | Blocker/Important/Minor + 운영 리스크(마이그레이션·helm no-op·호환성) | Blocker 0 | ×2, 동일 지적 반복 시 종료, 잔여는 GATE 1 에 표시 |
| GATE 1 | 사용자 | 판정·정정안·계획서·잔여 지적 | 승인 / 수정 지시 / 보류 / 닫기 | — | 정정안은 승인 후에만 이슈 댓글로 게시 |
| impl | ponytail | 승인 계획서 | 커밋(worktree) | 계획 파일 목록 내 변경, 테스트 파일 수정 금지(계획에 명시된 경우 제외) | — |
| verify | verifier | 계획서, diff, worktree | 실행 로그 + 대조표 + 체크리스트 결과 | ①빌드·테스트·helm 렌더 exit 0 ②계획 vs diff Missing/Extra 없음 ③디렉터리 CLAUDE.md 항목 통과 ④삭제된 assert·`@Disabled`·skip 추가·범위 밖 파일 없음 | 실패 → impl 1회 → 재실패 → GATE 1 |
| review | `code-review --fix` | diff | 수정 적용 | 잔여 finding 0 또는 수렴 | ×2 |
| pr | `ha-skills:pr` + codex | 브랜치 | draft PR, Codex 리뷰 댓글 | PR URL 획득 | codex 실패 시 댓글 생략하고 PR 본문에 기록 |
| GATE 2 | `/loop` + 사용자 | PR | approve+green 알림 → 머지 승인 | `reviewDecision=APPROVED` && checks all pass | `/loop` 는 세션 생존 필요(3차에서 `schedule` 검토) |
| close | 메인 + report-writer | 머지된 PR, 계획서, 이슈 | HTML 보고서, 이슈 댓글, close | 댓글에 PR·보고서 경로·변경 요약 | 보고서 실패는 로그만 |

실행 명령 레퍼런스(verify): gateway/admin `./gradlew test` (`JAVA_HOME=/opt/homebrew/opt/openjdk@21`), owasp `poetry run pytest`, helm `helm template` + `scripts/check-*.sh`, SDK 변경 시 `npm run build:gateway`.

## 6. 에이전트 페르소나 (4블록 형식)

공통 전제 `_sgt-context.md` — 모든 에이전트에 주입:
- 에어갭 설치 제품. 배포는 고객 유지보수 창에서 수동, 롤백·핫픽스는 수주. 고객 로그를 볼 수 없다.
- 고객이 우리 API 위에 자체 연동을 만들었을 수 있다 → 공개 경로·계약 축소는 사용 확인 전까지 보수적으로.
- 위협 모델은 내부망: 일반 사용자 JWT 권한 상승, 클러스터 내 횡이동, 우발적 포트 노출. 기본 시크릿을 안 바꾼 고객이 있다.
- 외부 호출·모델 다운로드 불가. 새 의존성은 오프라인 패키징 확인.
- 디렉터리별 CLAUDE.md 가 함정 목록이다(Flyway V 파일 추가만, helm 노브의 silent no-op 가드, gateway 인증 경로 2곳, owasp 기본 sink 등). 건드리는 디렉터리의 것을 먼저 읽는다.

| 에이전트 | 역할 한 줄 | 할 일 | 기준(발췌 출처) | 출력 | tools / model |
|---|---|---|---|---|---|
| issue-triage | 이슈 심사관 — 제품 전체 영향도를 평가해 "그대로 작업 가능한 상태"인지 판정 | 사실 주장 전수 코드 대조, 범위 과소/과대, 설정별(minimal/full·백엔드) 영향 | 코드 경로 없는 지적 금지, 기존 문제·스타일·추측 제외, 코드 수정·계획 작성 금지 | 판정 3갈래 / 사실 정정 / 범위 정정 / 영향도 | Read, Grep, Glob, Bash(gh issue view, git log) / opus |
| plan-writer | 구현 설계자 — 최소 변경 계획 | 세션 형태 분류, 유사 구현 탐색, 태스크 분해(파일·참조·완료 조건·검증 명령), 리스크 | **증거 규칙**(세션 내 확인한 경로만), 낯선 사람 실행 가능 기준, 가장 위험한 태스크 선행, 코드 작성 금지 (andymai planner) | 계획서 고정 템플릿 | Read, Grep, Glob / opus |
| plan-reviewer | 설계 심사관 — 운영 리스크 관점 | 마이그레이션·helm·호환성·롤백 가능성, 완료 조건의 검증 가능성, 범위 | 확신은 버는 것(4단계), 60 미만 버림, Blocker/Important/Minor, "검토 안 한 범위" 명시 (andymai reviewer) | 판정 + 지적 목록 | Read, Grep, Glob / **sonnet 또는 opus 중 plan-writer 와 다른 것** |
| verifier | 검증관 — 증거 없이는 완료 아님 | 명령 실행·출력 판독, 계획 vs diff(Missing/Extra/Misunderstood), 체크리스트, 변조 가드 | 이 세션에서 실행 안 한 명령은 통과 주장 불가, 구현자 보고서는 미검증 주장, 읽기 전용, 서브에이전트 스폰 금지 (superpowers verification / task-reviewer) | 실행 로그 요약 + 대조표 + PASS/FAIL | Read, Grep, Bash / sonnet |
| report-writer | 기술 작가 — 처음 보는 동료 독자 | explain-diff-html 호출(퀴즈 포함 여부는 사용자 선택) | 이슈·계획서·diff 를 모두 입력, "하려던 것"이 아니라 "한 것" | HTML + 이슈 댓글용 요약 | Read, Bash, Skill / sonnet |

impl 은 ponytail 세션 모드가 페르소나를 담당하므로 별도 에이전트 없음. `~/.claude/settings.json` 의 `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` 기본값이 있으므로 opus 가 필요한 에이전트는 `model:` 을 명시한다.

## 7. 구현 순서와 완료 조건

| 차수 | 범위 | 완료 조건(검증 방법) |
|---|---|---|
| **1차** | `AGENTS.md`, 훅+`notify.sh`, 공통 전제, 에이전트 3개(triage/plan-writer/plan-reviewer), `/issue-run` triage→GATE 1, 상태 파일·재개·abort | 실제 열린 이슈 1건으로 실행 → GATE 1 알림 도착, 계획서에 완료 조건·검증 명령 존재, 세션 종료 후 `/issue-run N` 으로 재개됨, `codex review --commit` 가 `AGENTS.md` 를 읽는지 1회 확인 |
| **2차** | impl→verify→review→pr, verifier 에이전트 | 같은 이슈로 draft PR 생성, Codex 리뷰 댓글 자동 게시, verify 에 테스트 변조 1건 주입 시 FAIL 로 잡힘, `/autofix-pr` 안내 출력 |
| **3차** | GATE 2 `/loop` 폴링, close(report-writer·이슈 댓글·docs/temp 정리), `schedule` 대체 검토 | approve 후 알림, 머지 승인 시 HTML 보고서·이슈 댓글·close 까지 자동. 보고서 생성 실패 시에도 close 완료 |

각 차수 종료 시 `code-review` 로 스킬·에이전트 파일 자체를 리뷰하고, 이 계획서의 "결정 기록"에 변경 사항을 추가한다.

## 7-1. 1차 실행 기록 — #958 (2026-11-08)

| 완료 조건 | 결과 |
|---|---|
| 실제 이슈로 실행 → GATE 1 도달 | ✓ triage(2m43s) → **보류** 판정 → GATE 1(결정 4건) → plan(6m) → plan-rev ×2(4m+3m) → GATE 1 계획 승인(결정 4건) → 최종 갱신. 게이트 2회, 사용자 입력 2회 |
| 계획서에 완료 조건·검증 명령 | ✓ 314줄, 태스크 7개 모두 검증 명령 보유, 자리표시자는 Spike 결과 `<S1 결과 상태>` 만 |
| 세션 종료 후 재개 | △ 노트북 닫힘으로 첫 triage 에이전트가 고아 상태(48분 무응답) → 종료 후 상태 파일 기준 재실행으로 복구. **`resume` 시 running 서브에이전트 잔존 여부 확인 단계가 필요** |
| `codex review` 가 AGENTS.md 를 읽는지 | 미실측 — 2차 pr 단계의 실 PR 로 확인 |
| GATE 알림 훅 발화 | 스크립트 단독 실행은 exit 0. 실제 `idle_prompt` 발화는 사용자 확인 필요 |

배운 것 / 2차 반영:
- **새 에이전트·스킬은 핫 리로드됨**(첫 호출 실패 후 다음 턴에 등록). 세션 재시작 불필요.
- triage 가 이슈의 핵심 주장을 뒤집음(#985 로 이미 구현) — "이슈를 코드와 대조" 단계의 가치가 첫 실행에서 입증. 정정안 댓글은 승인 후 게시 규칙 준수.
- plan-rev 1회차 Important 2건(remember-me 미연결로 공허한 검증, 2FA AJAX 허용 누락), 2회차 Important 1건(동일 비밀번호 재사용 구멍) — 모두 fresh 리뷰어가 코드에서 찾은 것. 2회 상한이 적절했음(2회차는 승인 + 소수 지적으로 수렴).
- GATE 1 이 두 번 열릴 수 있다(triage 보류 → 결정, 계획 승인). 스킬 문서에 "보류 경로는 GATE 1 이 2회" 를 명시할 것.
- 비용: 서브에이전트 5회 호출, 합계 약 55만 토큰(opus), 벽시계 약 20분(대기 제외).
- `.gitignore` 가 `.claude/*` 를 막고 있어 새 에이전트·스킬 디렉터리를 allowlist 에 추가함.

## 7-2. 2차 구현 기록 — 플러그인 이관 (2026-11-08)

- **D16 스킬·에이전트·훅은 `hajubal/ha-skills` 플러그인에서 관리한다**(사용자 결정). 레포에는 프로젝트 전제 파일 `.claude/issue-run/project.md` 와 `AGENTS.md` 만 남긴다. 이유: 다른 레포에서도 같은 파이프라인을 쓰고, 플러그인 버전으로 배포·갱신한다.
  - 이관된 것: `.claude/skills/issue-run/` → `plugins/ha-skills/skills/issue-run/`, `.claude/agents/{issue-triage,plan-writer,plan-reviewer}.md` + 새 `verifier.md` → `plugins/ha-skills/agents/`, `scripts/notify.sh` + `settings.json` 훅 → `plugins/ha-skills/{scripts,hooks}/`. 숨김 스킬 `sgt-context` 는 폐기하고 그 내용을 `project.md` 로 옮겼다(에이전트가 시작할 때 Read).
  - 바뀐 이름: 호출은 `/ha-skills:issue-run`, 에이전트는 `ha-skills:issue-triage` 처럼 플러그인 접두사가 붙는다. 상태 파일은 `~/issue-runs/<owner>/<repo>/<N>.json`(기존 `~/sgt-runs/958*` 를 복사해 옮김).
  - 플러그인 갱신은 `claude plugin marketplace update ha-skills && claude plugin update ha-skills@ha-skills` 뒤 세션에서 `/reload-plugins`(또는 재시작). 에이전트 핫 리로드는 프로젝트 `.claude/agents/` 에만 문서화돼 있다.
- **2차 구현 내용**(플러그인 1.2.0): `impl`(메인 ponytail, worktree, 태스크 단위 커밋, 계획 밖 파일 금지), `verify`(verifier 에이전트, 몫당 2회, 2회 실패 시 사용자 질문), `review`(`code-review --fix` 2회, 수정 후 검증 명령 재실행), `pr`(push → `ha-skills:pr` draft → `codex review --base` → `gh pr comment` → `/autofix-pr` 안내), 분할 PR(`parts`/`part`) 지원. GATE 2·close 는 3차.
- 알림 문구를 한국어로 바꾸고, 게이트 대기 중이면 "이슈 #N 계획서 승인 대기 —" 를 앞에 붙인다(사용자 피드백: 사용자가 읽는 모든 글은 처음 읽는 사람이 이해하는 문장으로 — 스킬 불변 규칙 7).
- 2차 완료 조건(§7) 검증은 #958 PR-A/PR-B 실행으로 한다. 미실측: verify 에 테스트 변조 1건 주입 시 FAIL 로 잡히는지.

## 7-3. 2차 실행 기록 — #958 PR-A/PR-B (2026-11-08)

**결과**: draft PR 2개 생성, 각각 검증관 PASS·코드 리뷰 2회·Codex 리뷰 댓글.
- PR-A https://github.com/ininext/sgt/pull/1520 — 커밋 8개(태스크 5 + 리뷰 2 + Codex 1). verify 1회차 FAIL(docker 꺼짐 → 사용자가 OrbStack 기동) → 2회차 PASS(스키마 게이트 ①② OK, S3 재현 NULL 0건). code-review 1회차 9건/1건 적용, 2회차 8건/5건 반복(수렴)/1건 적용. **Codex 가 실제 결함 1건(P2) 발견** — 만료 계정 뒤 같은 세션으로 로그인한 정상 계정에 표시 잔존(`changeSessionId()` 가 속성 보존). 메인이 즉시 수정+테스트(h) 커밋.
- PR-B https://github.com/ininext/sgt/pull/1521 — 커밋 3개. verify 1회차 PASS(736 tests). code-review 1회차 5건/2건 적용, 2회차 5건/3건 반복(수렴)/1건 적용. Codex: 결함 없음. S1 실측: 상한 초과 = **500 + 9999**(계획 예측대로, 구조 변경 안 함). S4: `ServerProperties`=`org.springframework.boot.web.server.autoconfigure`, `MultipartProperties`=`org.springframework.boot.servlet.autoconfigure`.
- 2차 완료 조건(§7) 대조: draft PR 생성 ✓ / Codex 댓글 자동 게시 ✓ / `/autofix-pr` 안내 ✓ / "verify 에 테스트 변조 주입 시 FAIL" **미실측**(변조 가드 grep 은 두 verify 보고서에 모두 실행됨).

**배운 것 (스킬 1.2.2 에 반영)**
1. `EnterWorktree` 는 **origin/main**(origin/HEAD)에서 분기한다 — 레포 기본 브랜치가 develop 이어도. 커밋 전이면 `git reset --hard origin/$base`, 커밋 후면 `git rebase origin/$base`. (D12 의 처음 우려가 맞았다.)
2. worktree 안에서는 새 worktree 를 만들 수 없다 → 다음 PR 몫 전에 `ExitWorktree(keep)`.
3. worktree 세션의 Bash 가드가 "복잡한 명령"(heredoc python, 변수 PATH, 긴 gh 인자)을 거부한다 → 상태 파일 갱신은 스크립트 파일로, 명령은 단순하게 쪼갠다.
4. `scripts/check-admin-schema.sh` 는 셸의 `java` 로 jar 를 띄우므로 Java 21 을 PATH 앞에 둬야 한다(project.md 에 기록).
5. Codex 는 worktree 에 `AGENTS.md` 가 없어도 상위 디렉터리(`/Users/hajubal/project/sgt/AGENTS.md`)를 읽는다(로그 확인). 출력은 진행 로그 200KB 포함 — 마지막 `codex` 마커 뒤만 댓글로 쓴다.
6. 리뷰어(code-review)는 계획서를 모르므로 "계획 결정"을 매 라운드 다시 지적한다. 수렴 규칙이 없으면 끝나지 않는다. 지적 처리표(`code-review-<part>-<n>.md`)가 PR 확인 포인트의 재료가 됐다.
7. 비용: PR-A 약 2시간, PR-B 약 40분. 서브에이전트 verify 2×~85k, review 4×~80k 토큰.
8. 프로젝트 전제 파일·계획서가 본체 레포 전용 브랜치에만 있으면 worktree 안에서 Edit 도구로 못 고친다(계획서 자리표시자 갱신은 exit 후).

## 7-4. D17 — 레포별 설정은 플러그인 저장소에 (2026-11-08, 사용자 결정)

SGT 레포는 팀 공용이라 개인 스킬용 파일(전제 파일, AGENTS.md, 설계 문서, 계획서)을 커밋하지 않는다. 대신 이 저장소의 `plugins/ha-skills/projects/<owner>/<repo>/` 에 두어 플러그인과 함께 모든 장비에 배포한다. 스킬은 `${CLAUDE_PLUGIN_ROOT}/projects/$key/project.md` 를 찾고(레포 안 `.claude/issue-run/project.md` 가 있으면 그쪽 우선), `AGENTS.md` 는 pr 단계에서 worktree 에 임시 복사한다. 계획서 기본 위치는 레포 밖 `~/issue-runs/<key>/<N>/`. 이 결정으로 SGT 쪽 브랜치 `hajubal/issue-run-pipeline`(미푸시)은 삭제했고, SGT 레포에는 파이프라인 흔적이 남지 않는다.
`~/project/ha-skills` 체크아웃 위치는 스킬이 참조하지 않는다 — 참조는 항상 설치된 플러그인(`${CLAUDE_PLUGIN_ROOT}`) 기준이므로, 설정을 바꾸면 버전을 올리고 `claude plugin update` 해야 반영된다.

## 8. 사용자가 직접 할 일

1. 이 계획서 승인(수정 요청 가능).
2. 1차 검증에 쓸 **실제 이슈 번호 1개** 지정(코드 변경이 작고 서비스 1개에 국한된 것 권장).
3. Slack 알림을 원하면 webhook URL 을 `SLACK_WEBHOOK_URL` 로 셸 환경에 설정(없으면 macOS 알림만).
4. 2차부터: PR 생성 안내가 뜨면 `/autofix-pr` 입력.
5. (선택) claude.ai/code → 설정 → Claude Code → "풀 리퀘스트 자동 수정" 토글. 켜면 4번이 사라질 가능성이 있으나 로컬 생성 PR 에 적용되는지는 미확인이며 모든 PR 에 클라우드 세션이 붙어 토큰 비용이 늘어난다.

## 9. 리스크

| 리스크 | 완화 |
|---|---|
| 리뷰어를 작성자와 같은 컨텍스트로 두면 "검토 없는 파이프라인"으로 조용히 변질 | D3 를 스킬 본문에 명시, 리뷰어 에이전트는 `Agent` 도구 제외 |
| verify 없이 "green PR 을 빨리 만드는 파이프라인"이 됨 — 에어갭 고객사는 결함을 수주 뒤에 인지 | verify 를 impl 과 review 사이의 필수 단계로, 실패 시 GATE 1 복귀 |
| 페르소나에 형용사만 넣으면 지적 수가 늘어 루프가 매번 상한에 걸림 | 4블록 + 확신 4단계 + 60점 컷 |
| 정정안이 틀린 채 GitHub 에 게시됨 | GATE 1 승인 후에만 이슈 댓글 |
| `/loop` 는 터미널이 살아 있어야 함 | 3차에서 `schedule`(클라우드 루틴) 전환 검토 |
| 한 세션에 전 단계를 쌓으면 컴팩션으로 후반 품질 저하 | 단계별 서브에이전트, 메인은 상태 파일만 보유 |
| `codex review` 는 diff 만 보고 테스트를 실행하지 않음 | verify 가 실행 검증을 담당, Codex 는 교차 리뷰로만 취급 |

## 10. 미확인 사항 (작업 중 확인)

- `Notification` 훅 `idle_prompt` 의 정확한 발화 시점(문서는 매처 이름만) → 1차에서 실측.
- `codex review` 가 `AGENTS.md` 를 읽는다는 공식 문구 없음(번들 review-agent 스킬 본문에는 있음) → 1차에서 가이드라인 위반 1건으로 실측.
- explain-diff-html 퀴즈 섹션 포함 여부 → 사용자 선택(ha-skills `pr` 은 PR 코멘트용으로 제외함).

## 참고

- andymai/claude-agent-team (MIT) — planner·reviewer 규칙 블록
- obra/superpowers (MIT) — verification-before-completion, task-reviewer-prompt
- Claude Code 공식 문서 — skills(`arguments`, `disable-model-invocation`), sub-agents(fresh context, `AskUserQuestion` 불가, `isolation: worktree`), hooks(`Notification` 매처)
- Codex CLI 레퍼런스 — `codex review --base|--commit|--uncommitted`, 프롬프트와 상호 배타
