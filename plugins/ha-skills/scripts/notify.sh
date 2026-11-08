#!/usr/bin/env bash
# Claude Code Notification 훅 — 게이트/입력 대기 시 사람을 부른다.
# stdin 으로 훅 JSON 이 들어온다. macOS 알림은 항상, Slack 은 SLACK_WEBHOOK_URL 이 있을 때만.
# 알림 문구는 사람이 바로 이해하도록 한국어로 쓰고, issue-run 이 게이트에서 기다리는 중이면 이슈 번호와 무엇을 기다리는지 붙인다.
# 상태 파일 위치는 issue-run 스킬과 같다: ~/issue-runs/<owner>/<repo>/<이슈번호>.json (origin 원격 URL 기준)
set -u
input=$(cat)
kind=$(printf '%s' "$input" | jq -r '.notification_type // ""' 2>/dev/null)
raw=$(printf '%s' "$input" | jq -r '.message // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
title="Claude Code${cwd:+ · ${cwd##*/}}"

case "$kind" in
  permission_prompt) msg="도구 실행 권한을 승인해 주세요. 터미널에서 허용/거부를 선택하면 작업이 이어집니다." ;;
  idle_prompt)       msg="질문에 답을 기다리고 있습니다. 터미널에서 답하기 전까지 작업이 멈춰 있습니다." ;;
  *)                 msg="${raw:-확인이 필요합니다.}" ;;
esac

# issue-run 이 사용자 결정을 기다리는 단계면 어떤 이슈의 어떤 게이트인지 앞에 붙인다.
# 레포 열쇠 = origin 의 owner/repo (스킬의 nameWithOwner 와 같은 값). worktree 안에서도 origin 은 같다. 없으면 본체 디렉터리 이름.
key=$(git -C "$cwd" remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')
[ -n "$key" ] || key=$(basename "$(dirname "$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$cwd/.git")")")
for f in "$HOME"/issue-runs/"$key"/*.json; do
  [ -f "$f" ] || continue
  phase=$(jq -r '.phase // ""' "$f" 2>/dev/null)
  case "$phase" in
    awaiting-plan-approval)  msg="이슈 #$(basename "$f" .json) 계획서 승인 대기 — $msg" ;;
    awaiting-merge-approval) msg="이슈 #$(basename "$f" .json) PR 머지 승인 대기 — $msg" ;;
  esac
done

if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"${msg//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"Glass\"" >/dev/null 2>&1 || true
fi
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  jq -nc --arg t "[$title] $msg" '{text:$t}' | curl -s -m 5 -X POST -H 'Content-Type: application/json' -d @- "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
fi
exit 0
