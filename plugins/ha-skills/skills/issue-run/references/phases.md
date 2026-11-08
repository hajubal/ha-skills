# issue-run 단계별 계약

실행자가 보는 요약본이다. 프로젝트마다 다른 것(기본 브랜치, 검증 명령, 함정 목록, 관례)은 대상 레포의 `.claude/issue-run/project.md` 에 있다 — 템플릿은 `project-template.md`.

| 단계 | 실행자 | 입력 | 출력(경로) | 통과 기준 | 상한 / 실패 시 |
|---|---|---|---|---|---|
| triage | `ha-skills:issue-triage` | 이슈 번호 | `<runs>/triage.md` | 모든 지적에 `파일:라인` | 보류/닫기 → GATE 1 |
| plan | `ha-skills:plan-writer` | triage.md | `<계획서 위치>/N-<slug>-plan.md` | 경로가 세션 내 확인된 것, 태스크마다 검증 명령 | Spikes 로 분리, 추측 금지 |
| plan-rev | `ha-skills:plan-reviewer` | 계획서 경로만 | `<runs>/plan-review-<n>.md` | Blocker 0 | ×2, 수렴 시 종료 → unresolved |
| GATE 1 | 사용자 | 요약 + 경로 | 승인/수정/보류/닫기 | — | 정정안 댓글은 승인 후 |
| impl | 메인(ponytail) | 승인 계획서의 이번 PR 몫 | worktree 커밋 | 계획 파일 목록 안에서만, 테스트 파일 수정은 계획에 명시된 것만 | — |
| verify | `ha-skills:verifier` | 계획서, worktree, 기본 브랜치 | `<runs>/verify-<part>-<n>.md` | ① 검증 명령 전부 exit 0 ② 계획 vs diff Missing/Extra 없음 ③ 디렉터리 CLAUDE.md 함정 없음 ④ 변조 가드 통과 | 실패 → impl 수정 1회 → 재실패 → 사용자 질문 |
| review | `Skill code-review --fix` | diff | 적용된 수정 + 커밋 | finding 0 또는 수렴 | ×2 |
| pr | `Skill ha-skills:pr` → `codex review --base origin/<기본>` | 브랜치 | draft PR, `<runs>/codex-review-<part>.md` → `gh pr comment` | PR URL | codex 실패 시 PR 본문에 기록 |
| autofix | **사용자** | — | — | — | "`/autofix-pr` 입력하세요" 안내 후 다음 PR 몫 또는 대기 |
| GATE 2 (3차) | `/loop` + 사용자 | PR | 알림 → 머지 승인 | `gh pr view --json reviewDecision` = APPROVED && `gh pr checks --json bucket` 전부 pass | 세션 생존 필요 |
| close (3차) | 메인 + `ha-skills:explain-diff-html` | 머지 PR, 계획서, 이슈 | `<보고서 위치>/YYYY-MM-DD-issue-N.html`, 이슈 댓글, close | 댓글에 PR·보고서 경로·요약 | 보고서 실패는 로그만, close 는 진행 |

`<runs>` = `~/issue-runs/<owner>/<repo>/N/` (`gh repo view --json nameWithOwner` 기준, 레포 밖). `<계획서 위치>` 는 project.md 에 적힌 레포 상대 경로, 없으면 `<runs>`.

## 분할 PR

계획서가 PR 을 나눴으면(예: "PR-A = T1–T6, PR-B = T7–T8") 상태 파일 `parts` 에 `[{"label":"A","tasks":"T1–T6","branch":null,"pr":null,"done":false}, …]` 로 적고, **PR 몫 하나씩** impl→verify→review→pr 을 돈다. 각 몫은 기본 브랜치에서 새로 분기한다(앞 몫에 의존한다고 계획서가 명시한 경우만 앞 몫 브랜치에서 분기). 마지막 몫의 PR 본문만 `Closes #N`, 나머지는 `Refs #N`.

## 핸드오프 파일 규칙

- 서브에이전트에는 **경로**를 준다. 메인이 본문을 붙여 넣지 않는다.
- 리뷰어·검증자에게 작성 과정·대화·이전 라운드 산출물을 주지 않는다. 재검증 때는 "이전 라운드 지적 파일"만 추가로 준다(수렴 판정용).
- 에이전트의 "완료" 보고는 주장이다. 파일 존재·diff·명령 출력으로 메인이 확인한다.
- `resume` 때 `ListAgents` 로 아직 돌고 있는 서브에이전트가 있으면 결과를 기다리거나 `TaskStop` 으로 정리한 뒤 이어간다(노트북을 닫았다 열면 고아가 남는다).
