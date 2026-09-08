#!/bin/bash
# Creates a new GitHub Release for SharpFocus using a git tag.
# Usage:
#   ./Scripts/release.sh 0.3.0              # bump, commit, tag, build locally, create GH release
#   ./Scripts/release.sh v0.3.0 --ci        # bump, commit, tag, push — CI builds & publishes
#   ./Scripts/release.sh 0.3.0 --dry-run    # show what would happen without pushing
#
# Requirements: git, gh (authenticated), swift toolchain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$APP_DIR/.." && pwd)"
cd "$APP_DIR"

# --- helpers ---
red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold() { printf "\033[1m%s\033[0m\n" "$*"; }
die() { red "error: $*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./Scripts/release.sh <version> [options]

  <version>    Semver like 0.3.0 or v0.3.0 (leading v is stripped)

Options:
  --ci         Tag & push only — let GitHub Actions build and publish the release
  --dry-run    Do everything except git push / gh release create
  --no-bump    Don't update version files (use current files as-is)
  --notes <text>  Custom release notes (otherwise auto-generated from git log)
  -h, --help   Show this help

Examples:
  ./Scripts/release.sh 0.3.0
  ./Scripts/release.sh v0.3.0 --ci
  ./Scripts/release.sh 0.3.0 --dry-run

What it does (default / local mode):
  1. Validates version + checks git/gh state
  2. Bumps version in SharpFocus-Info.plist, project.pbxproj, Scripts/bundle.sh
  3. Commits the bump (if files changed)
  4. Builds SharpFocus.app via Scripts/bundle.sh
  5. Zips to build/SharpFocus-<version>.zip (+ .sha256)
  6. Creates tag v<version>, pushes commit + tag
  7. Creates GitHub Release with the zip attached (gh release create)

CI mode (--ci) stops after step 6 — .github/workflows/release.yml builds and
attaches the asset so the release is reproducible on a clean runner.
USAGE
}

VERSION_RAW=""
CI_MODE=0
DRY_RUN=0
NO_BUMP=0
CUSTOM_NOTES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ci|--tag-only|--push-only) CI_MODE=1; shift ;;
    --dry-run|--dry) DRY_RUN=1; shift ;;
    --no-bump) NO_BUMP=1; shift ;;
    --notes) CUSTOM_NOTES="$2"; shift 2 ;;
    --notes=*) CUSTOM_NOTES="${1#*=}"; shift ;;
    v*) VERSION_RAW="$1"; shift ;;
    [0-9]*) VERSION_RAW="$1"; shift ;;
    *) die "Unknown arg: $1 (see --help)" ;;
  esac
done

[[ -z "$VERSION_RAW" ]] && { usage; echo ""; die "Version argument is required."; }

# strip leading v
VERSION="${VERSION_RAW#v}"

# validate semver (allows prerelease like 1.0.0-beta.1)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  die "Invalid version '$VERSION' — expected semver like 0.3.0 or 1.0.0-beta.1"
fi

TAG="v${VERSION}"
ZIP_NAME="SharpFocus-${VERSION}.zip"
ZIP_PATH="build/${ZIP_NAME}"
SHA_PATH="${ZIP_PATH}.sha256"

# --- preflight ---
command -v git >/dev/null || die "git not found"
command -v gh >/dev/null || die "gh CLI not found — install from https://cli.github.com/ (brew install gh)"
if ! gh auth status >/dev/null 2>&1; then
  die "gh not authenticated — run: gh auth login"
fi

# git state
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Not a git repository"
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  die "Tag $TAG already exists locally"
fi
if git ls-remote --tags origin | grep -q "refs/tags/${TAG}$"; then
  die "Tag $TAG already exists on origin"
fi

# warn if working tree dirty (except untracked build artifacts)
if ! git diff --quiet || ! git diff --cached --quiet; then
  yellow "Working tree has unstaged/uncommitted changes:"
  git status --short
  echo ""
  read -rp "Continue anyway? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "Aborted (stash or commit first)"
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
  yellow "Warning: on branch '$BRANCH' (not main). Tag will still be created from here."
fi

# check origin exists
git remote get-url origin >/dev/null 2>&1 || die "No git remote 'origin'"

# resolve previous tag for notes
PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"

bold "Releasing $TAG"
echo "  Mode:     $([[ $CI_MODE == 1 ]] && echo "CI (tag & push, workflow builds)" || echo "local (build + gh release)")"
[[ $DRY_RUN == 1 ]] && yellow "  Dry-run:  ON (no push / no release)"
[[ -n "$PREV_TAG" ]] && echo "  Previous: $PREV_TAG" || echo "  Previous: (no previous tag)"
echo "  Branch:   $BRANCH"
echo "  App dir:  $APP_DIR"
echo ""

# --- bump version files ---
if [[ $NO_BUMP == 0 ]]; then
  echo "→ Bumping version to $VERSION ..."

  # 1) Scripts/bundle.sh default
  #    VERSION="${SHARPFOCUS_VERSION:-0.2.0}"
  if grep -q 'SHARPFOCUS_VERSION:-' Scripts/bundle.sh; then
    # portable sed: macOS needs '' after -i, GNU doesn't — detect
    if sed --version >/dev/null 2>&1; then
      # GNU
      sed -i "s/SHARPFOCUS_VERSION:-[^}]*}/SHARPFOCUS_VERSION:-${VERSION}}/g" Scripts/bundle.sh
    else
      # BSD/macOS
      sed -i '' "s/SHARPFOCUS_VERSION:-[^}]*}/SHARPFOCUS_VERSION:-${VERSION}}/g" Scripts/bundle.sh
    fi
    green "  updated Scripts/bundle.sh"
  fi

  # 2) SharpFocus-Info.plist (CFBundleShortVersionString + CFBundleVersion)
  if [[ -f SharpFocus-Info.plist ]]; then
    if sed --version >/dev/null 2>&1; then
      sed -i -E "s|<string>[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?</string>|<string>${VERSION}</string>|g" SharpFocus-Info.plist
    else
      sed -i '' -E "s|<string>[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?</string>|<string>${VERSION}</string>|g" SharpFocus-Info.plist
    fi
    # The plist has two version strings (Short + Version) — both updated above.
    # Verify:
    grep -q "<string>${VERSION}</string>" SharpFocus-Info.plist || yellow "  warning: plist update may have failed"
    green "  updated SharpFocus-Info.plist"
  fi

  # 3) SharpFocus.xcodeproj/project.pbxproj MARKETING_VERSION
  PBX="SharpFocus.xcodeproj/project.pbxproj"
  if [[ -f "$PBX" ]]; then
    if sed --version >/dev/null 2>&1; then
      sed -i -E "s/MARKETING_VERSION = [0-9.]+(-[A-Za-z0-9.-]+)?;/MARKETING_VERSION = ${VERSION};/g" "$PBX"
    else
      sed -i '' -E "s/MARKETING_VERSION = [0-9.]+(-[A-Za-z0-9.-]+)?;/MARKETING_VERSION = ${VERSION};/g" "$PBX"
    fi
    green "  updated $PBX"
  fi

  # show diff
  echo ""
  git diff --stat
  echo ""
  git diff | head -n 100 || true
  echo ""
else
  yellow "Skipping version bump (--no-bump)"
fi

# --- commit bump if needed ---
NEEDS_COMMIT=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  NEEDS_COMMIT=1
fi

# --- build (unless CI mode) ---
if [[ $CI_MODE == 0 ]]; then
  echo "→ Building SharpFocus.app (SHARPFOCUS_VERSION=$VERSION) ..."
  SHARPFOCUS_VERSION="$VERSION" ./Scripts/bundle.sh
  echo ""

  echo "→ Creating zip ..."
  rm -f "$ZIP_PATH" "$SHA_PATH"
  # ditto preserves resource forks / quarantine correctly for .app
  ditto -c -k --sequesterRsrc --keepParent build/SharpFocus.app "$ZIP_PATH"
  # checksum
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"
  else
    sha256sum "$ZIP_PATH" > "$SHA_PATH"
  fi
  ls -lh "$ZIP_PATH" "$SHA_PATH"
  green "  created $ZIP_PATH"
  echo ""
else
  yellow "CI mode: skipping local build (workflow will build on tag push)"
  echo ""
fi

# --- generate release notes ---
NOTES_FILE="$(mktemp)"
if [[ -n "$CUSTOM_NOTES" ]]; then
  printf "%s\n" "$CUSTOM_NOTES" > "$NOTES_FILE"
else
  {
    echo "SharpFocus $TAG"
    echo ""
    if [[ -n "$PREV_TAG" ]]; then
      echo "Changes since $PREV_TAG:"
      echo ""
      git log "${PREV_TAG}..HEAD" --pretty=format:"- %s (%h)" --no-merges | head -n 100
      echo ""
      echo ""
      echo "**Full changelog:** https://github.com/AC40/sharpfocus/compare/${PREV_TAG}...${TAG}"
    else
      echo "Initial release."
      echo ""
      git log --pretty=format:"- %s (%h)" --no-merges | head -n 100
      echo ""
    fi
    echo ""
    echo "### Install"
    echo "Download \`$ZIP_NAME\`, unzip, and move \`SharpFocus.app\` to \`/Applications\`."
    echo "The app is ad-hoc signed. On first launch: System Settings → Privacy & Security → Open Anyway,"
    echo "or run \`xattr -cr /Applications/SharpFocus.app\`."
    echo ""
    # if local build, include checksum
    if [[ $CI_MODE == 0 && -f "$SHA_PATH" ]]; then
      echo "### Checksum"
      echo "\`\`\`"
      cat "$SHA_PATH"
      echo "\`\`\`"
    fi
  } > "$NOTES_FILE"
fi

echo "→ Release notes preview:"
echo "---"
cat "$NOTES_FILE"
echo "---"
echo ""

if [[ $DRY_RUN == 1 ]]; then
  yellow "Dry-run: not committing, tagging, or pushing."
  if [[ $CI_MODE == 0 ]]; then
    echo "Would have run:"
    echo "  git add Scripts/bundle.sh SharpFocus-Info.plist SharpFocus.xcodeproj/project.pbxproj"
    echo "  git commit -m \"chore: bump version to $VERSION\""
    echo "  git tag $TAG -m \"$TAG\""
    echo "  git push origin $BRANCH && git push origin $TAG"
    echo "  gh release create $TAG --title \"$TAG\" --notes-file $NOTES_FILE $ZIP_PATH ${SHA_PATH:+$SHA_PATH}"
  else
    echo "Would have run:"
    echo "  git add ... && git commit -m \"chore: bump version to $VERSION\""
    echo "  git tag $TAG && git push origin $BRANCH && git push origin $TAG"
    echo "  (GitHub Actions would then build & publish)"
  fi
  echo ""
  echo "Artifacts retained at: $ZIP_PATH"
  rm -f "$NOTES_FILE"
  exit 0
fi

# --- commit, tag, push ---
if [[ $NEEDS_COMMIT == 1 ]]; then
  echo "→ Committing version bump ..."
  git add Scripts/bundle.sh SharpFocus-Info.plist SharpFocus.xcodeproj/project.pbxproj 2>/dev/null || true
  # only commit if staged changes exist
  if ! git diff --cached --quiet; then
    git commit -m "chore: bump version to $VERSION"
    green "  committed"
  else
    yellow "  nothing to commit (files already staged/clean)"
  fi
else
  echo "→ No version files changed — skipping commit"
fi

echo "→ Creating tag $TAG ..."
git tag -a "$TAG" -m "$TAG"
green "  tagged $TAG"

echo "→ Pushing ..."
# push branch first (so commit is on remote), then tag
if [[ $NEEDS_COMMIT == 1 ]]; then
  git push origin "$BRANCH"
fi
git push origin "$TAG"
green "  pushed $TAG to origin"

# --- create GitHub Release (local mode only) ---
if [[ $CI_MODE == 0 ]]; then
  echo "→ Creating GitHub Release $TAG ..."
  # gh release create will fail if release already exists
  if gh release view "$TAG" >/dev/null 2>&1; then
    yellow "Release $TAG already exists — uploading assets instead"
    gh release upload "$TAG" "$ZIP_PATH" ${SHA_PATH:+$SHA_PATH} --clobber
  else
    gh release create "$TAG" \
      --title "$TAG" \
      --notes-file "$NOTES_FILE" \
      --verify-tag \
      "$ZIP_PATH" ${SHA_PATH:+$SHA_PATH}
  fi
  green "  release created: https://github.com/AC40/sharpfocus/releases/tag/$TAG"
else
  echo "→ CI mode: not creating release locally."
  echo "  GitHub Actions will create the release when it sees tag $TAG."
  echo "  Watch: https://github.com/AC40/sharpfocus/actions"
fi

rm -f "$NOTES_FILE"
echo ""
green "Done — $TAG"
