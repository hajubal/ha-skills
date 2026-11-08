---
name: issue-run
description: GitHub 이슈 1건을 상태 머신으로 처리한다 — triage → 계획 → 계획 심사 → GATE 1(사용자 승인) → 구현·검증·리뷰·draft PR·Codex 리뷰 → GATE 2(머지 승인, 3차) → 보고서·종료(3차). 사람은 게이트에서만 개입한다. 사용법 /ha-skills:issue-run <이슈번호> [resume|abort|status]
argument-hint: "<issue-number> [resume|abort|status]"
arguments: [issue, action]
disable-model-invocation: true
---

# /ha-skills:issue-run $issue $action

이슈 **#$issue** 를 처리한다. 동작: `$action` (비어 있으면 `resume` 과 같다 — 상태 파일이 없으면 처음부터, 있으면 `phase` 에서 이어간다).
단계별 계약은 `references/phases.md`, 프로젝트별 설정·전제·검증 명령은 대상 레포의 `.claude/issue-run/project.md`(없으면 `references/project-template.md` 를 안내하고 기본값으로 진행). 이 문서는 **메인 컨텍스트에서** 실행한다 — 게이트 질문(`AskUserQuestion`)은 서브에이전트가 못 하기 때문이다.

## 어느 레포를 다루는가 — 시작할 때 한 번 구한다

이 스킬은 **지금 작업 디렉터리가 속한 git 레포**의 이슈를 처리한다. 레포 이름을 어디에도 하드코딩하지 않는다.

- `root` = `dirname $(git rev-parse --path-format=absolute --git-common-dir)` — 레포의 본체 루트. worktree(`.claude/worktrees/…`) 안에서 실행해도 같은 값이 나온다. 이 명령이 실패하면(git 레포가 아님) "git 레포 안에서 실행해 주세요" 라고 알리고 멈춘다.
- `key` = `gh repo view --json nameWithOwner -q .nameWithOwner` (예: `ininext/sgt`). 실패하면 `git remote get-url origin` 에서 마지막 두 경로 조각(`.git` 제거). 그것도 없으면 `basename $root`. 상태·산출물을 레포별로 격리하는 열쇠다 — 이름이 같은 레포가 다른 조직에 있어도 섞이지 않는다.
- `base` = `$root/.claude/issue-run/project.md` 의 `기본 브랜치`, 없으면 `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
- `runs` = `~/issue-runs/$key/$issue/`, 상태 파일 = `~/issue-runs/$key/$issue.json`. 레포 밖에 두므로 레포에 흔적을 남기지 않는다.
- `plan_dir` = project.md 의 `계획서 위치`(레포 상대 경로, 예: `docs/temp/`). **없으면 `$runs/`** — 레포에 계획서 관례가 없으면 레포 안에 파일을 만들지 않는다.

project.md 는 **항상 `$root`(본체) 에서** 읽는다. worktree 는 기본 브랜치에서 분기하므로, 아직 머지되지 않은 project.md 가 worktree 에는 없을 수 있다. 서브에이전트에도 `$root` 경로를 넘겨 같은 파일을 읽게 한다.

## 불변 규칙

1. **단계 작업은 서브에이전트에, 상태는 메인에.** 메인은 상태 파일과 산출물 경로만 들고 있고, 산출물 본문을 컨텍스트에 길게 싣지 않는다(요약만). 예외는 impl — 코드는 메인이 ponytail 모드로 직접 쓴다.
2. **리뷰어·검증자는 fresh 컨텍스트.** `subagent_type: "fork"` 금지. 리뷰어·검증자에게는 산출물 **파일 경로만** 준다 — 작성 과정·대화 내용을 주지 않는다.
3. **루프 상한 2회 + 수렴 감지.** 같은 지적이 반복되면 중단하고 잔여 항목을 다음 게이트에 올린다.
4. **GitHub 에 쓰는 행위(댓글·PR·머지·close)는 게이트 승인 뒤에만.** 읽기는 자유. GATE 1 승인은 "정정안 댓글 + 구현 + draft PR + Codex 리뷰 댓글"까지를 승인한 것이다. 머지는 절대 자동으로 하지 않는다.
5. 각 단계 진입·종료 시 상태 파일을 갱신한다. 중간에 죽어도 `resume` 으로 이어가야 한다.
6. 단계가 끝날 때마다 사용자에게 **한 줄**로 진행을 알린다(산출물 경로 포함). 설명은 게이트에서만 길게.
7. **사용자가 읽는 글은 전부 처음 읽는 사람이 한 번에 이해하는 문장으로 쓴다.** 진행 알림, 게이트 설명, `AskUserQuestion` 의 질문·선택지·설명, 상태 표, 종료 보고, 이슈 댓글, PR 본문 모두 해당한다. phase 값·훅 이름·도구 이름 같은 내부 식별자를 설명 없이 쓰지 않고, 무엇이 끝났고(또는 무엇을 기다리고) 사용자가 지금 무엇을 결정하면 되는지를 주어와 동사가 있는 문장으로 적는다. 선택지에는 그걸 고르면 다음에 무슨 일이 일어나는지를 붙인다.
8. **에이전트 보고는 주장이다.** 파일이 생겼다는 말은 `ls` 로, 테스트가 통과했다는 말은 verifier 의 실행 로그로, PR 이 생겼다는 말은 `gh pr view` 로 확인한다.

## 상태 파일

처음이면 `mkdir -p $runs` 후 생성:

```json
{ "issue": $issue, "repo": "<key>", "root": "<root>", "base": "<base>", "phase": "triage",
  "plan": null, "parts": null, "part": null,
  "worktree": null, "branch": null, "pr": null,
  "loops": {"plan-rev": 0, "verify": 0, "review": 0},
  "unresolved": [], "history": [] }
```

`history` 에는 `{"phase","at","result"}` 를 단계마다 추가. `phase` 값: `triage` → `plan` → `plan-rev` → `awaiting-plan-approval` → `impl` → `verify` → `review` → `pr` → (다음 PR 몫이 있으면 `impl` 로) → `awaiting-merge-approval` → `close` → `done` | `aborted` | `held`.
분할 PR 이면 `parts` 에 몫 목록을, `part` 에 지금 도는 몫의 label 을 둔다(`references/phases.md` "분할 PR").

## $action 분기

- `status`: 상태 파일을 읽어 단계·반복 횟수·남은 지적·산출물 경로·PR 을 표로 보여주고 끝낸다. 표 머리글은 내부 키가 아니라 한국어 설명으로.
- `abort`: 사용자에게 한 번 확인(`AskUserQuestion`) 후 — worktree 가 있으면 `ExitWorktree(remove)`(미커밋 변경이 있으면 보고하고 다시 확인), draft PR 이 있으면 닫을지 묻고, `phase: aborted` 로 마감. 이슈·브랜치는 건드리지 않는다.
- `resume`/빈값: 먼저 `ListAgents` 로 돌고 있는 서브에이전트가 있는지 본다 — 있으면 그 결과를 기다리거나 `TaskStop` 한 뒤, 아래 단계를 `phase` 부터 실행. `worktree` 가 적혀 있으면 그 디렉터리가 실제로 있는지 확인하고, 없으면 impl 을 처음부터 다시 한다고 알린다.

## 단계

### triage  (`phase: triage`)
1. `gh issue view $issue --json state,title` 로 열린 이슈인지 확인. 닫혀 있으면 멈추고 보고.
2. `Agent(subagent_type: "ha-skills:issue-triage")` 에 다음만 준다: 이슈 번호, `$root`(프로젝트 전제 파일을 여기서 읽으라고 명시). 반환 본문을 `$runs/triage.md` 에 **그대로** 저장한다(에이전트는 Write 가 없다).
3. 판정을 읽는다.
   - `진행` → `phase: plan`.
   - `보류`/`닫기` → `phase: awaiting-plan-approval` 로 바로 가서 GATE 1 에서 사용자가 결정한다(계획은 쓰지 않는다). 사용자가 "범위를 바꿔 진행"을 고르면 결정을 `$runs/user-decisions.md` 에 적고 `phase: plan` 으로 — 이 경로에서는 GATE 1 이 **두 번** 열린다(한 번은 진행 여부, 한 번은 계획 승인).

### plan  (`phase: plan`)
1. `Agent(subagent_type: "ha-skills:plan-writer")` 에 준다: 이슈 번호, `$root`, `$runs/triage.md` 경로, 있으면 `$runs/user-decisions.md` 경로, 저장 위치(`$plan_dir/$issue-<slug>-plan.md` 를 절대 경로로).
2. 반환된 저장 경로를 상태 파일 `plan` 에 기록. 파일이 실제로 있는지 `ls` 로 확인. → `phase: plan-rev`.

### plan-rev  (`phase: plan-rev`, 최대 2회)
1. `loops.plan-rev += 1`. `Agent(subagent_type: "ha-skills:plan-reviewer")` 에 **계획서 경로·이슈 번호·`$root` 만** 준다(2회차면 1회차 리뷰 파일 경로도 — 수렴 판정용). 결과를 `$runs/plan-review-<n>.md` 에 저장.
2. 판정 `승인` → `phase: awaiting-plan-approval`.
3. `수정 필요` 이고 `loops.plan-rev < 2` → `Agent(subagent_type: "ha-skills:plan-writer")` 에 계획서 경로 + 리뷰 파일 경로를 주고 **Blocker/Important 만 반영해 같은 파일을 갱신**하게 한 뒤 1 로.
4. 2회째도 `수정 필요`, 또는 2회의 Blocker 목록이 동일(수렴) → 잔여 지적을 `unresolved` 에 넣고 `phase: awaiting-plan-approval`.

### GATE 1  (`phase: awaiting-plan-approval`)
사용자에게 **이것만** 보여준다(파일 본문을 붙이지 말고 경로 + 요약). 처음 읽는 사람이 무엇을 결정해야 하는지 알 수 있게 쓴다:
- triage 가 무엇을 판정했고 이슈의 어떤 주장이 코드와 달랐는지(건수와 가장 중요한 1–2건), `$runs/triage.md`
- 계획서 경로, 어떤 종류의 변경인지, 태스크 수, PR 을 몇 개로 나누는지, 사용자가 정해야 할 결정 포인트 목록(각 권장값과 그 이유 한 줄)
- 계획 심사의 최종 판정과 아직 안 풀린 지적(`unresolved`)이 무엇을 뜻하는지
- 이슈 댓글로 올릴 **정정안 초안**(triage 의 사실·범위 정정을 요약한 3–8줄)

그다음 `AskUserQuestion` 한 번:
- `승인 — 구현을 시작하고 draft PR 까지 자동으로 만든다` / `수정 지시 — 계획서를 고친 뒤 다시 보여 준다` / `보류 — 여기서 멈추고 나중에 재개한다` / `닫기 — 이슈를 닫는다`
- 결정 포인트가 있으면 같은 호출에 질문으로 함께 묻는다(최대 4개, 넘으면 중요한 순). 선택지마다 그걸 고르면 무엇이 달라지는지 한 줄.

처리:
- 승인 → 결정 내용을 `$runs/user-decisions.md` 에 추가. 결정 포인트 값이 계획서의 자리표시자를 채워야 하면 plan-writer 에게 계획서 갱신을 한 번 더 시키고 `ls`·`grep` 으로 자리표시자가 남지 않았는지 확인. 정정안이 있으면 `gh issue comment $issue --body-file` 로 게시(사용자가 "댓글은 빼라"고 하면 생략). 계획서가 PR 을 나눴으면 `parts` 를 채우고 `part` 를 첫 몫으로. `phase: impl`.
- 수정 지시 → 지시 내용을 `$runs/user-feedback-<n>.md` 에 저장하고 `loops.plan-rev = 0` 으로 리셋한 뒤 `phase: plan` 의 갱신 경로(plan-writer 에 계획서 + 피드백 파일)로 돌아간다.
- 보류 → `phase: held`, 이유를 history 에 기록.
- 닫기 → 사유를 묻고 `gh issue close $issue -c "<사유>"` 전에 한 번 더 확인. `phase: done`.

### impl  (`phase: impl`) — 메인이 ponytail 모드로 직접 구현
1. **worktree.** `worktree` 가 비어 있으면: 이미 다른 worktree 안이면(앞 PR 몫) 먼저 `ExitWorktree(action: "keep")` — worktree 안에서는 새 worktree 를 만들 수 없다. `git fetch origin $base --quiet` 후 `EnterWorktree(name: "issue-$issue<-part 소문자>")`. **`EnterWorktree` 는 레포 기본 브랜치가 아니라 `origin/HEAD`(보통 main)에서 분기한다.** 들어간 뒤 `git merge-base --is-ancestor origin/$base HEAD` 가 실패하면 커밋이 없으므로 `git reset --hard origin/$base` 로 맞춘다(커밋이 있으면 `git rebase origin/$base`). 브랜치를 `<접두사>issue-$issue<-part>-<slug>` 로 `git branch -m` 하고, worktree 경로와 브랜치를 상태 파일에 기록한다.
   - worktree 세션에서는 Bash 가드가 "복잡한 명령"(heredoc 스크립트, 변수로 만든 PATH, 긴 `gh` 인자)을 거부한다. 상태 파일 갱신은 작은 스크립트 파일을 `python3 -I <파일> …` 로 부르고, 명령은 단순하게 쪼갠다. 본체 레포의 파일(project.md, 계획서)은 worktree 안에서 Edit 할 수 없다 — 계획서 자리표시자 갱신은 `ExitWorktree` 뒤에 한다.
2. **구현.** 계획서를 Read 하고 이번 몫의 태스크를 순서대로 구현한다. 규칙:
   - 계획서의 "변경 파일 목록" 밖의 파일은 건드리지 않는다. 꼭 필요하면 왜 필요한지 커밋 메시지에 적고 verifier 가 Extra 로 잡을 것을 감수한다.
   - 테스트는 계획서가 지정한 파일·케이스를 추가한다. 기존 테스트의 단언을 지우거나 비활성화하지 않는다.
   - 태스크마다 계획서의 `검증:` 명령을 실행해 통과를 본 뒤 **태스크 단위로 커밋**한다. 메시지 형식은 project.md 를 따른다.
   - 계획서가 Spike(확인 후 결정) 를 남겼으면 그 자리에서 확인하고 결과를 계획서의 자리표시자에 채워 넣는다(계획서 수정 커밋 포함).
   - 막히면(계획서와 코드가 다름, 계획대로 하면 테스트가 깨짐) 임의로 설계를 바꾸지 말고 `AskUserQuestion` 으로 묻는다. 질문에는 "계획서는 A 라고 했는데 코드는 B 다. 선택지 1/2 를 고르면 각각 이렇게 된다"를 쓴다.
3. 끝나면 `git status --short` 가 비어 있는지 확인(남은 변경은 커밋하거나 버린다). → `phase: verify`.

### verify  (`phase: verify`, 몫당 최대 2회)
1. `loops.verify += 1`. `Agent(subagent_type: "ha-skills:verifier")` 에 준다: worktree 경로, `$root`(프로젝트 전제·검증 명령은 여기서 읽는다), 계획서 경로, 이번 몫 label 과 태스크 범위, `$base`. 2회차면 1회차 verify 파일 경로도. 결과를 `$runs/verify-<part>-<n>.md` 에 저장.
2. `PASS` → `loops.verify = 0`, `phase: review`.
3. `FAIL` 이고 `loops.verify < 2` → "구현자에게" 목록을 메인이 ponytail 로 고치고(원인 분석 → 최소 수정 → 해당 검증 명령 재실행 → 커밋) 1 로.
4. 2회째도 `FAIL` → 멈추고 `AskUserQuestion`: 남은 실패를 요약하고 `한 번 더 고친다(실패 목록을 보여 주고 지시를 받는다)` / `이대로 PR 을 만든다(실패를 PR 본문에 적는다)` / `보류`. 선택대로 진행.

### review  (`phase: review`, 몫당 최대 2회)
1. `loops.review += 1`. worktree 에서 `Skill(skill: "code-review", args: "--fix")` 를 실행한다. 리뷰어는 fresh 컨텍스트라 불변 규칙 2 를 만족한다.
2. 적용된 수정이 있으면(`git status --short` 비어 있지 않음): 바뀐 디렉터리의 project.md 검증 명령(없으면 계획서 태스크의 `검증:` 명령)을 **메인이 직접** 다시 실행해 통과를 확인하고 `review: <한 줄>` 커밋. 통과하지 않으면 수정을 되돌리고(`git checkout -- .`) 그 finding 을 `unresolved` 에 적는다.
3. finding 0 → `phase: pr`. finding 이 있었고 `loops.review < 2` → 1 로. 2회째 finding 의 과반이 1회째와 같으면(수렴) 잔여를 `unresolved` 에 넣고 `phase: pr`. 리뷰어는 계획서를 모르므로 "계획서가 이미 결정한 것"(범위 밖, 수용한 리스크, pre-existing)을 매번 다시 지적한다 — 라운드마다 `$runs/code-review-<part>-<n>.md` 에 지적별 처리(적용 / 계획 결정 / pre-existing / 사실과 다름)를 표로 남기고, 진짜 미해결만 `unresolved` 로 올린다. 이 표가 PR 확인 포인트의 재료다.

### pr  (`phase: pr`)
1. `git push -u origin <branch>`.
2. `Skill(skill: "ha-skills:pr")` 로 draft PR 을 만든다. 넘길 정보: 이슈 번호(마지막 몫이면 `Closes #$issue`, 아니면 `Refs #$issue` 와 "PR <label>/<몫 수>"), 계획서 경로, verify 결과 파일 경로, `unresolved`(있으면 "확인 포인트"에 적는다). 제목은 project.md 의 이슈 제목 규칙을 따른다. PR URL 을 `gh pr view --json url -q .url` 로 확인해 상태 파일 `pr`(분할이면 `parts[].pr`)에 기록.
3. **Codex 리뷰.** worktree 에서 `codex review --base origin/$base > $runs/codex-review-<part>.md 2>&1` (타임아웃 10분, 백그라운드 가능). 출력에는 진행 로그(수백 KB)가 섞여 있다 — **마지막 `\ncodex\n` 마커 뒤의 본문만** 뽑아(`$runs/codex-review-<part>-final.md`) 머리말 "Codex 자동 리뷰(`codex review --base origin/$base`, 기준: 레포 루트 AGENTS.md)" 를 붙여 `gh pr comment <pr> --body-file` 로 게시. AGENTS.md 는 worktree 에 없어도 Codex 가 상위 디렉터리에서 읽는다. Codex 가 실제 결함(P1/P2)을 찾았고 수정이 한두 줄이면 메인이 바로 고쳐 테스트·커밋·푸시하고 댓글에 "커밋 <sha> 에서 반영" 을 적는다; 그 밖은 사용자의 `/autofix-pr` 몫이다. 실패하면 게시하지 않고 PR 본문 끝에 "Codex 리뷰 실행 실패: <이유 한 줄>" 을 `gh pr edit --body` 로 덧붙인다.
4. 사용자에게 알린다(한 문단): PR 주소, verify·review 결과 한 줄, 그리고 **"이 PR 에 대해 `/autofix-pr` 을 직접 입력해 주세요. 이 명령은 자동화에서 호출할 수 없어 사람이 한 번 실행해야 합니다."**
5. 다음 몫이 남아 있으면 `part` 를 다음으로, `worktree`/`branch` 를 비우고 `loops` 를 0 으로 → `phase: impl`. 남은 몫이 없으면 → `phase: awaiting-merge-approval`.

### GATE 2 · close  (`phase: awaiting-merge-approval` 이후)
**3차에서 구현.** 이 단계에 도달하면 "모든 PR 이 만들어졌습니다. 리뷰 승인과 CI 통과 뒤 머지는 아직 사람이 합니다. 머지 후 `/ha-skills:issue-run $issue` 를 다시 실행하면 보고서와 이슈 종료를 진행합니다(3차 구현 후)." 라고 알리고 멈춘다. 계약은 `references/phases.md` 에 미리 적혀 있다.

## 실패 처리

- 서브에이전트가 형식에 안 맞는 출력을 내면 한 번 재요청(형식 위반 부분을 지적해서). 두 번째도 실패하면 원문을 저장하고 사용자에게 보고.
- `gh`·`git push`·`codex` 실패(인증·네트워크)는 즉시 멈추고 보고. 재시도 루프를 돌리지 않는다. codex 만은 PR 생성 자체를 막지 않는다(위 pr-3) — `codex` 가 설치돼 있지 않으면 "Codex 리뷰 생략(미설치)" 으로 PR 본문에 적는다.
- `code-review` 스킬이 없으면(공식 `code-review` 플러그인 미설치) review 단계를 건너뛰고 그 사실을 PR 본문과 사용자 알림에 적는다.
- 상태 파일이 손상되어 있으면 사용자에게 보여주고 `triage` 부터 다시 할지 묻는다.
- worktree 가 상태 파일에는 있는데 디스크에 없으면 impl 을 처음부터 다시 한다고 알리고 진행한다(브랜치가 원격에 있으면 그 브랜치로 worktree 를 다시 만든다).
