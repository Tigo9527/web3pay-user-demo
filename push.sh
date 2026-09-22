#!/usr/bin/env bash
set -euo pipefail

BRANCH="$(git branch --show-current)"
if [ -z "$BRANCH" ]; then
  echo "Cannot detect current branch (detached HEAD?)." >&2
  exit 1
fi

ORIGIN_URL="$(git remote get-url origin)"
if [ -z "$ORIGIN_URL" ]; then
  echo "Cannot detect origin URL." >&2
  exit 1
fi

REPO_PATH="$(printf '%s' "$ORIGIN_URL" | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
if [ -z "$REPO_PATH" ] || [ "$REPO_PATH" = "$ORIGIN_URL" ]; then
  echo "Only GitHub origin URLs are supported. Current origin: $ORIGIN_URL" >&2
  exit 1
fi

SAFE_URL="https://github.com/${REPO_PATH}.git"

# 1) Remove tokenized URL from repo config
  git remote set-url origin "$SAFE_URL"

  # 2) Ensure branch upstream uses origin (not a raw URL)
  git config --local "branch.${BRANCH}.remote" origin
  git config --local "branch.${BRANCH}.merge" "refs/heads/${BRANCH}"

  # 3) Optional: remove any persisted GitHub auth header in local config
  git config --local --unset-all http.https://github.com/.extraheader 2>/dev/null || true

  # 4) Verify no inline credential remains in local config
  if git config --local -l | grep -Eq 'https://[^ ]+@github\.com'; then
    echo "Found embedded GitHub credentials in local git config. Please clean before push." >&2
    exit 1
  fi

#  Then push without persisting token:

  read -r -p "GitHub username (empty = use existing git auth): " GH_USER
  read -r -s -p "GitHub token (empty = use existing git auth): " GH_TOKEN; echo

  if { [ -n "${GH_USER}" ] && [ -z "${GH_TOKEN}" ]; } || { [ -z "${GH_USER}" ] && [ -n "${GH_TOKEN}" ]; }; then
    echo "Provide both username and token, or leave both empty." >&2
    exit 1
  fi

  if [ -z "${GH_USER}" ] && [ -z "${GH_TOKEN}" ]; then
    git push -u origin "$BRANCH"
    exit 0
  fi

  ASKPASS_SCRIPT="$(mktemp)"
  trap 'rm -f "$ASKPASS_SCRIPT"; unset GH_TOKEN GH_USER ASKPASS_SCRIPT' EXIT
  cat > "$ASKPASS_SCRIPT" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "$GH_USER" ;;
  *Password*) printf '%s\n' "$GH_TOKEN" ;;
  *) printf '\n' ;;
esac
EOF
  chmod 700 "$ASKPASS_SCRIPT"

  GIT_ASKPASS="$ASKPASS_SCRIPT" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= -c core.askPass="$ASKPASS_SCRIPT" push -u origin "$BRANCH"
