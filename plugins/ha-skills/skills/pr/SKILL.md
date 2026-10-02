---
name: pr
description: Use when the user asks to create, write, update, or improve a pull request ("PR 올려줘", "PR 본문 써줘", "PR 설명 보강해줘", create/open a PR). Writes a short, scannable PR body (요약·배경·변경 요약·확인 포인트) and moves all detailed explanation into an explain-diff-html deep-dive posted as a PR comment. Opens PRs as draft.
---

# PR 작성

목표는 두 가지다.

1. **PR 본문 — 짧게**: 리뷰어가 30초 안에 "무엇을, 왜 바꿨고, 무엇을 봐줘야 하는지" 파악할 수 있는 요점만.
2. **심층 설명 — 코멘트로**: `ha-skills:explain-diff-html` 스킬로 만든 상세 설명을 PR 코멘트(또는 링크)로 붙인다.

**역할 분담이 이 스킬의 핵심이다.** 코드 워크스루, 파일별 해설, 데이터 흐름, 대안 검토 과정 같은 긴 설명은 **전부 심층 설명 쪽**이다. 본문에 옮겨 적지 않는다. 본문에 같은 내용을 반복하면 둘 다 안 읽힌다.

본문의 합격선은 "이것만 읽고도 리뷰를 시작할 수 있다"이지 "이것만 읽고도 전부 이해한다"가 아니다. 단, **승인 판단을 가르는 정보**(호환성 파괴, 배포 순서, 롤백, 보안·개인정보 영향)는 짧게라도 반드시 본문에 남긴다 — 코멘트에 묻히면 안 되는 종류다.

## 1. 대상과 컨텍스트 파악

먼저 무엇에 대한 PR인지 확정한다. 사용자가 PR 번호를 줬으면 기존 PR 수정, 아니면 현재 브랜치로 신규 생성이다.

```bash
git rev-parse --abbrev-ref HEAD                     # 현재 브랜치
git status --short                                   # 커밋 안 된 변경 확인
gh repo view --json nameWithOwner,visibility,defaultBranchRef
gh pr status --json number,title,baseRefName,url     # 이 브랜치에 이미 PR이 있는지
```

- 현재 브랜치가 기본 브랜치면 **멈추고** 사용자에게 알린다. 기본 브랜치에서 PR을 만들 수는 없다.
- 커밋되지 않은 변경이 있으면 그 사실을 알리고, 커밋할지 제외할지 확인한다. 사용자가 명시적으로 요청하지 않았다면 임의로 커밋·푸시하지 않는다.
- 기존 PR이 있으면 새로 만들지 말고 `gh pr edit`으로 본문을 갱신한다.

## 2. 변경 내용을 실제로 이해한다

diff만 보고 쓰면 "무엇을 바꿨는지"만 나열한 PR이 된다. 목적과 구현 방향을 쓰려면 주변 코드를 읽어야 한다.

```bash
BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null \
       || gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch origin "$BASE" --quiet
MB=$(git merge-base HEAD "origin/$BASE")
git diff --stat "$MB"..HEAD
git log --reverse --format='%h %s%n%b' "$MB"..HEAD
git diff "$MB"..HEAD
```

`..`가 아니라 merge-base 기준으로 봐야 base 브랜치의 다른 커밋이 섞이지 않는다. diff가 커서 한 번에 안 읽히면 `git diff "$MB"..HEAD -- <path>`로 파일별로 나눠 읽는다.

그다음 반드시 할 것:

- 변경된 함수·클래스의 **호출부와 정의부를 원본 파일에서** 읽어, 이 코드가 시스템에서 어떤 역할인지 파악한다.
- 브랜치명·커밋 메시지·연결된 이슈(`gh issue view`)에서 의도를 수집한다. 의도가 코드에서 읽히지 않으면 추측해서 쓰지 말고 사용자에게 묻는다.
- 자동 생성/포매팅/의존성 lock 등 **리뷰가 필요 없는 파일**을 따로 분류해 둔다. 리뷰 가이드에서 "이건 넘겨도 된다"고 알려주기 위함이다.

## 3. 본문 작성

템플릿과 섹션별 작성 규칙은 `references/body-template.md`를 읽고 따른다.
더 좋은 PR을 위한 추가 가이드(제목 규칙, 대안 검토, 롤백 계획, 셀프 리뷰 체크리스트 등)는 `references/writing-guide.md`에 있다. 해당 상황에 맞는 항목만 골라 반영한다.

**분량 기준: 스크롤 없이 한 화면. 본문 전체 40줄 이내를 목표로 하고, 넘으면 넘긴 만큼 심층 설명으로 내린다.** 초과가 정당한 경우는 조건부 섹션(호환성·배포·롤백)이 실제로 필요할 때뿐이다.

간결하게 쓰는 방법:

- 한 항목은 한 줄. 불릿 밑에 하위 불릿을 달기 시작하면 심층 설명으로 내려야 한다는 신호다.
- 배경은 문제 진술 2~3문장이면 충분하다. 문제의 역사·조사 과정은 심층 설명으로.
- "왜 이렇게 구현했나"는 **한 줄 결론만** 쓴다. 근거·대안 비교는 심층 설명에 있으니 "자세한 내용은 아래 코멘트"로 넘긴다.
- 변경 내용은 파일 나열이 아니라 논리 단위 3~6개 불릿. 파일이 20개여도 불릿이 20개가 되면 안 된다.
- 코드 블록은 본문에 넣지 않는다(설정값·명령어 한 줄 예외). diff 조각은 심층 설명 몫이다.

독자는 **"이 저장소를 처음 보는 동료"**다. 이건 분량과 무관하게 유지한다:

- 사내 약어·팀 은어·내부 시스템명은 첫 등장에서 한 줄로 풀어 쓴다.
- "Slack에서 논의한 대로" 같은 표현은 금지. 결론을 본문에 옮겨 적는다.
- 파일은 경로까지 쓰고(`src/auth/session.ts`), 코드를 인용할 때는 커밋 SHA로 고정된 permalink를 쓴다.
- 빈 섹션을 남기지 않는다. 해당 없는 섹션은 통째로 삭제한다.
- 저장소의 기존 PR 몇 개를 확인해 언어(한국어/영어)와 형식을 맞춘다. `.github/pull_request_template.md`가 있으면 그 구조를 우선한다.

본문은 파일로 저장해 `--body-file`로 넘긴다. 셸 이스케이프 문제를 피할 수 있다.

```bash
BODY=<scratchpad>/pr-body.md   # 세션 스크래치패드 사용
```

## 4. 심층 설명 HTML 생성

`ha-skills:explain-diff-html` 스킬을 호출해서(Skill 도구, `skill: "ha-skills:explain-diff-html"`) 이 변경에 대한 HTML을 만든다.
사용 가능한 스킬 목록에 없으면 이 파일 기준 상대 경로 `../explain-diff-html/SKILL.md`(플러그인 루트 기준 `${CLAUDE_PLUGIN_ROOT}/skills/explain-diff-html/SKILL.md`)를 읽고 그 지침을 그대로 수행한다.

- 대상은 2단계에서 파악한 diff 범위(`$MB`..HEAD)다.
- **퀴즈 섹션은 만들지 않는다.** explain-diff-html 지침의 Quiz 항목은 이 스킬에서 호출할 때 건너뛴다. PR 코멘트에서는 채점이 안 되고 리뷰어에게 필요한 정보도 아니다.
- 파일 경로 규칙은 그 스킬의 지침을 따른다(오늘 날짜 `YYYY-MM-DD-` 접두사, 저장소 밖 경로).
- 생성된 절대 경로를 기억해 둔다. 5단계에서 쓴다.
- 비공개 저장소라면 5단계에서 이 내용을 Markdown으로 옮겨 PR 코멘트로 올린다. HTML 파일은 인터랙티브 원본으로 함께 남긴다.

## 5. 리뷰어가 볼 수 있게 붙이기

전제 두 가지를 알고 골라야 한다(실측 근거는 `references/attachment.md`).

- `.html`은 GitHub 첨부 허용 확장자다. **zip으로 감쌀 필요 없다.**
- 하지만 첨부 파일은 `Content-Disposition: attachment`로 서빙되므로 **클릭하면 렌더가 아니라 다운로드된다.** 즉 "클릭 즉시 열람"은 첨부로는 불가능하고, 렌더되는 링크가 필요하다. 첨부 업로드 자체도 API로는 안 되고 웹 UI 드래그뿐이다.

| 방식 | 클릭 즉시 렌더 | 접근 범위 | 자동 처리 |
|---|---|---|---|
| A. Markdown으로 PR 코멘트 게시 | **O** | 저장소 권한자 | O |
| B. Artifact(claude.ai) | **O** | 기본 비공개, 팀 공유 필요(외부) | O |
| C. secret gist + gistpreview | **O** | **URL 아는 누구나**(외부) | O |
| D. HTML 파일 직접 첨부 | X (다운로드 후 열기) | 저장소 권한자 | X (사용자 드래그) |
| E. PR 브랜치에 커밋 | X (다운로드 후 열기) | 저장소 권한자 | O |

기본 동작:

1. `gh repo view --json visibility`로 공개 여부를 확인한다.
2. **비공개/내부 저장소 → A.** HTML 내용을 Markdown으로 옮겨 `gh pr comment`로 올린다. 다이어그램은 mermaid 코드블록, 콜아웃은 `> [!NOTE]`로 바꾼다. 전체 인터랙티브 버전이 필요하면 HTML 경로를 함께 안내해 D로 첨부하게 한다.
   외부 업로드(B·C)는 사용자가 명시적으로 허용했을 때만 한다. secret gist는 이름만 secret이고 URL을 아는 누구나 열 수 있다.
3. **공개 저장소 → C.** HTML 원본을 그대로 즉시 렌더할 수 있다.
4. 어느 방식을 썼는지, 공개 범위가 어떻게 되는지, 사용자가 직접 할 일이 남았는지 분명히 보고한다.

**순서 주의**: A(코멘트)는 PR이 있어야 올릴 수 있다. 신규 PR이면 6단계에서 **생성 → 코멘트 게시 → 코멘트 URL을 본문 "상세 설명"에 반영** 순으로 처리한다. C(링크)는 PR 생성 전에 URL이 나오므로 본문에 미리 넣는다.

본문은 요점만 쓰되, 이 링크·코멘트가 사라져도 **무엇을 왜 바꿨는지는 본문만으로 남아 있어야 한다**. 상세 설명이 대신하는 것은 "깊이"이지 "요지"가 아니다.

## 6. PR 생성 또는 갱신

```bash
# 신규 — 사용자 전역 규칙: 항상 draft, assignee는 항상 본인
gh pr create --draft --base "$BASE" --title "<제목>" --body-file "$BODY" --assignee @me

# 기존
gh pr edit <번호> --body-file "$BODY" --add-assignee @me

# 심층 설명을 코멘트로 게시하고(A안), 그 URL을 본문 "상세 설명"에 반영
gh pr comment <번호> --body-file <심층설명.md>
gh pr edit <번호> --body-file "$BODY"
```

- 푸시되지 않은 커밋이 있으면 `gh pr create`가 푸시를 물어본다. 사용자가 푸시를 요청하지 않았다면 먼저 확인한다.
- 올리기 전에 `wc -l "$BODY"`로 분량을 확인한다. 40줄을 넘으면 넘긴 부분을 심층 설명으로 내리고 다시 줄인다(조건부 섹션 때문에 넘은 경우는 예외).
- **신규 PR은 항상 draft(`--draft`)로 올린다.** 사용자가 "바로 리뷰 요청", "ready로", "draft 말고" 처럼 명시적으로 요구했을 때만 draft를 뺀다. 준비가 되면 사용자가 GitHub UI나 `gh pr ready <번호>`로 전환한다 — 임의로 ready 전환하지 않는다.
- reviewer는 사용자가 지정하거나 CODEOWNERS가 있을 때만 `--reviewer`로 넣는다. 임의로 사람을 호출하지 않는다.

## 7. 마무리 보고

사용자에게 다음을 한 번에 알린다: PR URL, 본문에 넣은 섹션 요약, HTML 파일 경로와 첨부 방식(그리고 공개 범위), 사용자가 직접 해야 하는 남은 동작(zip 드래그, gist 공유 등), 그리고 본문에서 추측으로 채운 부분이 있다면 그 목록.
