# ha-skills

개인용 Claude Code 스킬을 플러그인으로 묶은 저장소다. 이 저장소 하나가 **마켓플레이스이자 플러그인**이다.

## 설치

```
/plugin marketplace add hajubal/ha-skills
/plugin install ha-skills@ha-skills
```

CLI로도 된다.

```bash
claude plugin marketplace add hajubal/ha-skills
claude plugin install ha-skills@ha-skills
```

## 업데이트

마켓플레이스를 갱신한 뒤 플러그인을 업데이트하고, Claude Code를 재시작한다. 마켓플레이스 갱신만으로는 플러그인이 바뀌지 않는다.

```bash
claude plugin marketplace update ha-skills
claude plugin update ha-skills@ha-skills
```

매번 하기 싫으면 `/plugin` → Marketplaces → ha-skills에서 자동 업데이트를 켠다(직접 추가한 마켓플레이스는 기본 꺼짐).

> 배포하는 쪽: 스킬을 고치면 `plugins/ha-skills/.claude-plugin/plugin.json`의 `version`을 반드시 올린다. 버전이 같으면 사용자 쪽에서 업데이트로 인식하지 않는다.

## 포함된 스킬

| 스킬 | 호출 이름 | 하는 일 |
|---|---|---|
| PR 작성 | `ha-skills:pr` | PR 본문은 40줄 이내로 짧게 쓴다. 심층 설명은 요청 시에만 PR 코멘트로 붙인다. 신규 PR은 항상 draft + assignee 본인 + 리뷰 가능한 전원에게 리뷰 요청. |
| 심층 설명 | `ha-skills:explain-diff-html` | 코드 변경을 배경 → 직관 → 코드 워크스루 → 퀴즈 순서의 자체 완결형 HTML 한 장으로 만든다. |
| 이슈 처리 | `/ha-skills:issue-run <번호> [resume\|abort\|status]` | GitHub 이슈 1건을 상태 머신으로 처리한다. 이슈를 코드와 대조(triage) → 계획서 작성 → 계획 심사(최대 2회) → **사용자 승인(GATE 1)** → 구현 → 검증 → `code-review --fix` → draft PR + Codex 리뷰 댓글. 사람은 게이트에서만 개입한다. 머지와 `/autofix-pr` 은 사람이 한다. |

`pr` 스킬은 사용자가 언급했을 때만 `explain-diff-html` 스킬을 호출한다.

### issue-run 을 쓰려면

1. 대상 레포에 `.claude/issue-run/project.md` 를 만든다. 템플릿은 `plugins/ha-skills/skills/issue-run/references/project-template.md`. 기본 브랜치, 브랜치 접두사, 계획서 위치, 제품 전제(배포 모델·위협 모델·절대 수정 금지 파일), **검증 명령 표**(바뀐 디렉터리 → 실행할 테스트 명령)를 채운다. 이 파일이 없으면 verify 단계가 실행할 명령을 모른다.
2. Codex 리뷰를 쓰려면 레포 루트에 `AGENTS.md`(Codex 가 읽는 리뷰 기준)를 두고 `codex` CLI 가 설치돼 있어야 한다. 없으면 PR 은 만들어지고 Codex 댓글만 빠진다.
3. 상태는 `~/issue-runs/<레포 이름>/<이슈번호>.json`, 산출물은 `~/issue-runs/<레포 이름>/<이슈번호>/` 에 쌓인다. 세션이 끊겨도 같은 명령으로 이어진다.
4. 에이전트 4개(`ha-skills:issue-triage`, `ha-skills:plan-writer`, `ha-skills:plan-reviewer`, `ha-skills:verifier`)는 모두 `model: opus` 다. 전역 `CLAUDE_CODE_SUBAGENT_MODEL` 보다 우선한다.
5. 플러그인 훅이 입력 대기·권한 요청 때 macOS 알림을 보낸다(`SLACK_WEBHOOK_URL` 이 있으면 Slack 에도). 레포의 `settings.json` 에 같은 훅을 두면 두 번 울린다.

## 구조

```
.claude-plugin/marketplace.json      마켓플레이스 정의
plugins/ha-skills/
├─ .claude-plugin/plugin.json        플러그인 메타 (name/version/description)
├─ agents/                           issue-run 서브에이전트 (issue-triage, plan-writer, plan-reviewer, verifier)
├─ hooks/hooks.json                  Notification 훅 (idle_prompt | permission_prompt → scripts/notify.sh)
├─ scripts/notify.sh                 macOS 알림 + Slack(선택)
└─ skills/
   ├─ pr/{SKILL.md,references/}
   ├─ explain-diff-html/SKILL.md
   └─ issue-run/{SKILL.md,references/phases.md,references/project-template.md}
```

## 스킬을 추가할 때

1. `plugins/ha-skills/skills/<이름>/SKILL.md` 를 만든다(frontmatter에 `name`, `description` 필수).
2. 다른 스킬을 호출하는 부분이 있으면 **플러그인 접두사를 붙인다** — `ha-skills:<이름>`. 플러그인으로 설치되면 스킬 이름에 접두사가 붙기 때문이다.
3. 파일 경로는 홈 디렉터리를 하드코딩하지 말고 `${CLAUDE_PLUGIN_ROOT}` 기준이나 SKILL.md 기준 상대 경로로 쓴다. 장비마다 홈 경로가 다르다.
4. `plugins/ha-skills/.claude-plugin/plugin.json` 의 `version` 을 올리고 push 한다.
