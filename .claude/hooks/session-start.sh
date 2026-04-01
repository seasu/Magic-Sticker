#!/bin/bash
# SessionStart Hook: 每次 Session 啟動時，自動把目前 branch rebase 到最新的 main
# 避免 PR 因為 branch 落後 main 而產生 conflict。

set -euo pipefail

# 只在 Claude Code on the web (remote) 環境執行
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

# 確認在 git repo 內
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "[session-start] 不在 git repo 內，略過 rebase。"
  exit 0
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 若在 main/master 上就不 rebase
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "[session-start] 目前在 $CURRENT_BRANCH，略過 rebase。"
  exit 0
fi

echo "[session-start] 目前分支：$CURRENT_BRANCH"

# 若有未 commit 的變更，stash 起來
STASHED=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "[session-start] 偵測到未提交變更，先 stash。"
  git stash push -m "session-start-hook auto stash" --include-untracked
  STASHED=true
fi

# Fetch latest main（最多重試 3 次）
for i in 1 2 3; do
  if git fetch origin main 2>&1; then
    break
  fi
  echo "[session-start] fetch 失敗，第 $i 次重試..."
  sleep $((i * 2))
done

# Rebase onto origin/main
echo "[session-start] 對 origin/main 執行 rebase..."
if git rebase origin/main; then
  echo "[session-start] rebase 成功。"

  # 若 local 與 remote tracking branch 有 diverge（rebase 改變了 SHA），
  # 自動 force push 讓 PR head 保持同步，避免之後 push 被 reject。
  TRACKING=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)
  if [ -n "$TRACKING" ]; then
    LOCAL_SHA=$(git rev-parse HEAD)
    REMOTE_SHA=$(git rev-parse "$TRACKING" 2>/dev/null || true)
    if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
      REMOTE_NAME=$(echo "$TRACKING" | cut -d'/' -f1)
      REMOTE_BRANCH=$(echo "$TRACKING" | cut -d'/' -f2-)
      echo "[session-start] 偵測到 SHA 不一致，force push 同步 remote..."
      if git push "$REMOTE_NAME" HEAD:"$REMOTE_BRANCH" --force-with-lease 2>&1; then
        echo "[session-start] remote branch 已同步。"
      else
        echo "[session-start] force push 失敗，請手動處理。"
      fi
    else
      echo "[session-start] local 與 remote SHA 一致，無需 push。"
    fi
  fi
else
  echo "[session-start] rebase 失敗，中止並還原（conflict 需手動處理）。"
  git rebase --abort 2>/dev/null || true
fi

# 還原 stash
if [ "$STASHED" = "true" ]; then
  echo "[session-start] 還原 stash。"
  git stash pop || true
fi

echo "[session-start] 完成。目前分支 $CURRENT_BRANCH 已同步 origin/main。"
