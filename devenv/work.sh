#!/usr/bin/env bash
# work.sh: set up this machine for Kalypso work, and save that work to GitHub.
# Built for machines that wipe your home folder at logout; works on a normal
# macOS or Linux machine too. Every step is safe to re-run.
#
# See devenv/README.md for usage.

set -euo pipefail

FORK_REPO="${FORK_REPO:-serial-optimizer/kalypso}"
UPSTREAM_REPO="${UPSTREAM_REPO:-Goodluck-hojae/Kalypso}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
WORK_BRANCH="${WORK_BRANCH:-shivansh/dev}"
WORK_DIR="${WORK_DIR:-$HOME/Kalypso}"
BIN_DIR="$HOME/bin"
XCODE_GIT="/Applications/Xcode.app/Contents/Developer/usr/bin/git"
MAX_FILE_MB=50

export PATH="$BIN_DIR:$PATH"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
usage: work <command>

  setup          install git/gh if needed, log in to GitHub, clone or refresh
                 $WORK_DIR on branch $WORK_BRANCH
  save ["msg"]   commit all changes and push them to $FORK_REPO
  sync           merge the latest $UPSTREAM_REPO $UPSTREAM_BRANCH into your branch
  status         show tools, GitHub login, and anything not yet pushed
EOF
}

git_works() { git --version >/dev/null 2>&1; }

ensure_git() {
  if git_works; then
    say "git: $(git --version)"
    return
  fi
  if [ -x "$XCODE_GIT" ]; then
    # /usr/bin/git is a launcher that refuses to run until the Xcode license
    # is accepted, which needs sudo. Xcode's own git binary runs without it.
    # This must be a wrapper, not a symlink: through a symlink git looks for
    # its helper programs next to the link and can't clone over https.
    mkdir -p "$BIN_DIR"
    printf '#!/bin/sh\nexec %s "$@"\n' "$XCODE_GIT" > "$BIN_DIR/git"
    chmod +x "$BIN_DIR/git"
    hash -r   # forget the /usr/bin/git that bash already found
    git_works || die "Xcode's git doesn't run either"
    say "git: using Xcode's git through $BIN_DIR/git"
    return
  fi
  die "no working git. Install it ('xcode-select --install' on macOS, your package manager on Linux) and re-run."
}

sha256_check() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -c -; else shasum -a 256 -c -; fi
}

ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    say "gh: $(gh --version | head -1)"
    return
  fi
  local os ext arch tag ver name tmp
  case "$(uname -s)" in
    Darwin) os=macOS; ext=zip ;;
    Linux)  os=linux; ext=tar.gz ;;
    *) die "unsupported OS $(uname -s); install gh from https://cli.github.com" ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch=arm64 ;;
    x86_64|amd64)  arch=amd64 ;;
    *) die "unsupported CPU $(uname -m); install gh from https://cli.github.com" ;;
  esac
  tag=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
        | sed -n 's/.*"tag_name": *"\(v[^"]*\)".*/\1/p' | head -1)
  [ -n "$tag" ] || die "couldn't look up the latest gh release"
  ver="${tag#v}"
  name="gh_${ver}_${os}_${arch}"
  tmp=$(mktemp -d)
  say "installing gh $ver into $BIN_DIR"
  curl -fsSL -o "$tmp/$name.$ext" "https://github.com/cli/cli/releases/download/$tag/$name.$ext"
  curl -fsSL -o "$tmp/sums.txt" "https://github.com/cli/cli/releases/download/$tag/gh_${ver}_checksums.txt"
  (cd "$tmp" && grep " $name.$ext\$" sums.txt | sha256_check >/dev/null) \
    || die "the gh download failed its checksum check"
  case "$ext" in
    zip)    unzip -q "$tmp/$name.$ext" -d "$tmp" ;;
    tar.gz) tar -xzf "$tmp/$name.$ext" -C "$tmp" ;;
  esac
  mkdir -p "$BIN_DIR"
  cp "$tmp/$name/bin/gh" "$BIN_DIR/gh"
  chmod +x "$BIN_DIR/gh"
  hash -r
  rm -rf "$tmp"
}

# Put ~/bin on PATH for new terminals, and install the `work` shortcut there.
ensure_shell() {
  local marker='# added by Kalypso devenv/work.sh'
  local line="export PATH=\"\$HOME/bin:\$PATH\"  $marker"
  local files="" f
  for f in .bash_profile .bashrc .zshrc .profile; do
    [ -f "$HOME/$f" ] && files="$files $f"
  done
  if [ -z "$files" ]; then
    case "$(basename "${SHELL:-bash}")" in
      zsh) files=".zshrc" ;;
      *)   files=".bash_profile .bashrc" ;;
    esac
  fi
  for f in $files; do
    grep -qsF "$marker" "$HOME/$f" || printf '\n%s\n' "$line" >> "$HOME/$f"
  done

  mkdir -p "$BIN_DIR"
  printf '#!/bin/sh\nexec bash "%s/devenv/work.sh" "$@"\n' "$WORK_DIR" > "$BIN_DIR/work"
  chmod +x "$BIN_DIR/work"
}

ensure_login() {
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    say "GitHub: logged in as $(gh api user --jq .login)"
  else
    say "logging in to GitHub: copy the code shown, then approve it in the browser"
    gh auth login --hostname github.com --web --git-protocol https
  fi
  gh auth setup-git --hostname github.com   # lets git push using this login
}

ensure_identity() {
  if [ -z "$(git config --global user.email || true)" ]; then
    local login id
    login=$(gh api user --jq .login)
    id=$(gh api user --jq .id)
    # GitHub's private noreply address still credits commits to your account.
    git config --global user.name "$login"
    git config --global user.email "$id+$login@users.noreply.github.com"
  fi
  say "commits will be authored as: $(git config --global user.name) <$(git config --global user.email)>"
}

ensure_repo() {
  if [ -d "$WORK_DIR/.git" ]; then
    say "repo: $WORK_DIR already exists, fetching updates"
  else
    gh repo view "$FORK_REPO" >/dev/null 2>&1 \
      || die "$FORK_REPO not found. Fork it first: gh repo fork $UPSTREAM_REPO --clone=false"
    say "cloning $FORK_REPO into $WORK_DIR"
    gh repo clone "$FORK_REPO" "$WORK_DIR"
  fi
  cd "$WORK_DIR"
  git remote get-url upstream >/dev/null 2>&1 \
    || git remote add upstream "https://github.com/$UPSTREAM_REPO.git"
  git fetch --all --prune --quiet

  if git show-ref --verify --quiet "refs/heads/$WORK_BRANCH"; then
    git switch --quiet "$WORK_BRANCH"
  elif git show-ref --verify --quiet "refs/remotes/origin/$WORK_BRANCH"; then
    git switch --quiet --track "origin/$WORK_BRANCH"
  else
    git switch --quiet -c "$WORK_BRANCH" "upstream/$UPSTREAM_BRANCH"
    git push --quiet -u origin "$WORK_BRANCH"
  fi
  git pull --ff-only --quiet \
    || warn "couldn't fast-forward $WORK_BRANCH; check 'git status' in $WORK_DIR"
  say "repo: on $(git rev-parse --abbrev-ref HEAD) at $(git log --oneline -1)"
}

enter_repo() {
  [ -d "$WORK_DIR/.git" ] || die "$WORK_DIR isn't set up yet. Run: work setup"
  git_works && command -v gh >/dev/null 2>&1 || die "git/gh missing (new session?). Run: work setup"
  cd "$WORK_DIR"
}

# Refuse to commit big files or likely secrets. Your fork is public.
check_staged() {
  local bad=0 f size
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    size=$(wc -c < "$f" | tr -d ' ')
    if [ "$size" -gt $((MAX_FILE_MB * 1024 * 1024)) ]; then
      warn "$f is $((size / 1024 / 1024)) MB; GitHub rejects files over 100 MB"
      bad=1
    fi
    case "$(basename "$f")" in
      .env.example|.env.sample|.env.template) ;;
      .env|.env.*|*.pem|*.key|id_rsa*|id_ed25519*|credentials*.json)
        warn "$f looks like a secret (API key, password, private key)"
        bad=1 ;;
    esac
  done < <(git diff --cached --name-only -z --diff-filter=AM)
  if [ "$bad" = 1 ]; then
    git reset --quiet
    die "nothing was committed. Add those files to .gitignore or delete them, then run save again."
  fi
}

cmd_setup() {
  ensure_git
  ensure_gh
  ensure_login
  ensure_identity
  ensure_repo
  ensure_shell
  echo
  say "all set. Open a new terminal (or run: export PATH=\"\$HOME/bin:\$PATH\"), then use:"
  echo "      work save \"what you did\"   # commit + push"
  echo "      work status                 # anything unsaved?"
}

cmd_save() {
  enter_repo
  local msg="${1:-WIP $(date '+%Y-%m-%d %H:%M')}"
  git add -A
  if git diff --cached --quiet; then
    say "no new changes to commit"
  else
    check_staged
    git commit --quiet -m "$msg"
    say "committed: $msg"
  fi
  git push --quiet -u origin HEAD
  say "pushed $(git rev-parse --abbrev-ref HEAD) to https://github.com/$FORK_REPO"
}

cmd_sync() {
  enter_repo
  { git diff --quiet && git diff --cached --quiet; } \
    || die "you have uncommitted changes. Run 'work save' first."
  git fetch --quiet upstream
  say "merging $UPSTREAM_REPO $UPSTREAM_BRANCH into $(git rev-parse --abbrev-ref HEAD)"
  git merge --no-edit "upstream/$UPSTREAM_BRANCH" \
    || die "merge conflict. Fix the files 'git status' lists, run 'git commit', then 'work save'."
  git push --quiet origin HEAD
  say "synced and pushed"
}

cmd_status() {
  printf 'git:    %s\n' "$(git --version 2>/dev/null || echo 'not working (run: work setup)')"
  if command -v gh >/dev/null 2>&1; then
    printf 'gh:     %s\n' "$(gh --version | head -1)"
    printf 'GitHub: %s\n' "$(gh api user --jq .login 2>/dev/null || echo 'not logged in (run: work setup)')"
  else
    printf 'gh:     not installed (run: work setup)\n'
  fi
  if [ -d "$WORK_DIR/.git" ] && git_works; then
    cd "$WORK_DIR"
    git fetch --quiet origin 2>/dev/null || true
    echo "repo:   $WORK_DIR"
    git status --short --branch
    local ahead
    ahead=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo "?")
    if [ "$ahead" != "0" ] || [ -n "$(git status --porcelain)" ]; then
      warn "you have work that isn't on GitHub yet. Run: work save \"msg\""
    else
      say "everything is pushed"
    fi
  else
    echo "repo:   $WORK_DIR not set up (run: work setup)"
  fi
}

case "${1:-}" in
  setup)  cmd_setup ;;
  save)   shift; cmd_save "$*" ;;
  sync)   cmd_sync ;;
  status) cmd_status ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
