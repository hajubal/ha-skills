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

업데이트는 `/plugin update` 또는 `claude plugin marketplace update ha-skills`.

## 포함된 스킬

| 스킬 | 호출 이름 | 하는 일 |
|---|---|---|
| PR 작성 | `ha-skills:pr` | PR 본문은 40줄 이내로 짧게 쓰고, 코드 워크스루·대안 검토 같은 긴 설명은 심층 설명으로 분리해 PR 코멘트로 붙인다. 신규 PR은 항상 draft + assignee 본인. |
| 심층 설명 | `ha-skills:explain-diff-html` | 코드 변경을 배경 → 직관 → 코드 워크스루 → 퀴즈 순서의 자체 완결형 HTML 한 장으로 만든다. |

`pr` 스킬이 `explain-diff-html` 스킬을 호출하므로 둘은 한 플러그인에 함께 있다.

## 구조

```
.claude-plugin/marketplace.json      마켓플레이스 정의
plugins/ha-skills/
├─ .claude-plugin/plugin.json        플러그인 메타 (name/version/description)
└─ skills/
   ├─ pr/{SKILL.md,references/}
   └─ explain-diff-html/SKILL.md
```

## 스킬을 추가할 때

1. `plugins/ha-skills/skills/<이름>/SKILL.md` 를 만든다(frontmatter에 `name`, `description` 필수).
2. 다른 스킬을 호출하는 부분이 있으면 **플러그인 접두사를 붙인다** — `ha-skills:<이름>`. 플러그인으로 설치되면 스킬 이름에 접두사가 붙기 때문이다.
3. 파일 경로는 홈 디렉터리를 하드코딩하지 말고 `${CLAUDE_PLUGIN_ROOT}` 기준이나 SKILL.md 기준 상대 경로로 쓴다. 장비마다 홈 경로가 다르다.
4. `plugins/ha-skills/.claude-plugin/plugin.json` 의 `version` 을 올리고 push 한다.
