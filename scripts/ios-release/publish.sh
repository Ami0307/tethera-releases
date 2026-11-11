#!/usr/bin/env bash
# Uploads a built IPA and updates a SideStore / AltStore source. Called by
# .github/workflows/ios-release.yml after the build and `sidestore.py inspect`;
# everything comes in through the environment (see the workflow's "Publish" step).
#
#   1. Optionally attaches the IPA to the release of the pushed tag in the calling
#      repository (ATTACH_TO_TAG_RELEASE).
#   2. Creates or updates the release <RELEASE_TAG_PREFIX><version> in RELEASE_REPO
#      and uploads the IPA (--clobber), marked latest only if MARK_LATEST is true.
#   3. Updates SOURCE_PATH on RELEASE_BRANCH of RELEASE_REPO, adds the icon next to
#      it if missing, commits and pushes.
#   4. Optionally deletes releases with the same tag prefix that fell out of the
#      source (PRUNE_RELEASES), and checks that "latest" did not move when it must not.
#
# Safe to run again for the same tag. DRY_RUN=true prints what would change and
# uploads, pushes and deletes nothing. Tokens are only ever passed to gh / git
# through GH_TOKEN and are never printed.
set -euo pipefail

die() { echo "publish.sh: $*" >&2; exit 1; }
need() { [ -n "${!1:-}" ] || die "$1 is not set"; }
for v in APP_NAME BUNDLE_ID IPA_PATH VERSION BUILD SIZE SHA256 SIDESTORE_NOTES RELEASE_NOTES \
         RELEASE_REPO RELEASE_BRANCH SOURCE_PATH SOURCE_REPO TAG TOOLS_DIR RELEASE_TOKEN CALLER_TOKEN; do
  need "$v"
done
for tool in gh git python3; do command -v "$tool" >/dev/null || die "needs $tool on the runner"; done

RELEASE_TAG_PREFIX="${RELEASE_TAG_PREFIX-v}"
default_asset='{app}-{version}.ipa'
ASSET_NAME_TEMPLATE="${ASSET_NAME_TEMPLATE:-$default_asset}"
KEEP_VERSIONS="${KEEP_VERSIONS:-0}"
DRY_RUN="${DRY_RUN:-false}"
MARK_LATEST="${MARK_LATEST:-false}"
PRUNE_RELEASES="${PRUNE_RELEASES:-false}"
ATTACH_TO_TAG_RELEASE="${ATTACH_TO_TAG_RELEASE:-false}"
case "$KEEP_VERSIONS" in ''|*[!0-9]*) die "keep-versions must be a whole number" ;; esac
case "$SOURCE_PATH" in /*|*..*) die "source-path must be relative to the release repository" ;; esac

asset="${ASSET_NAME_TEMPLATE//\{app\}/$APP_NAME}"
asset="${asset//\{version\}/$VERSION}"
asset="${asset//\{build\}/$BUILD}"
case "$asset" in */*|'') die "bad asset name: $asset" ;; esac
dist_tag="${RELEASE_TAG_PREFIX}${VERSION}"
download_url="https://github.com/$RELEASE_REPO/releases/download/$dist_tag/$asset"
source_dir=$(dirname "$SOURCE_PATH")
raw_base="https://raw.githubusercontent.com/$RELEASE_REPO/$RELEASE_BRANCH"
source_url="$raw_base/$SOURCE_PATH"
if [ "$source_dir" = "." ]; then icon_url="$raw_base/icon.png"; else icon_url="$raw_base/$source_dir/icon.png"; fi
same_release=false
[ "$RELEASE_REPO" = "$SOURCE_REPO" ] && [ "$dist_tag" = "$TAG" ] && same_release=true

dry() { [ "$DRY_RUN" = "true" ]; }
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ios-release-publish.XXXXXX")
trap 'rm -rf "$work"' EXIT

echo "== $APP_NAME $VERSION (build $BUILD), ${SIZE} bytes, sha256 $SHA256"
echo "== IPA release: $RELEASE_REPO $dist_tag / $asset"
echo "== source:      $source_url"
dry && echo "== dry run: nothing is uploaded, pushed or deleted"

# --- files to upload and release text ------------------------------------------
mkdir "$work/upload"
cp "$IPA_PATH" "$work/upload/$asset"
printf '%s  %s\n' "$SHA256" "$asset" > "$work/upload/$asset.sha256"
uploads=("$work/upload/$asset" "$work/upload/$asset.sha256")
if [ -n "${BUILD_INFO_PATH:-}" ] && [ -f "$BUILD_INFO_PATH" ]; then
  cp "$BUILD_INFO_PATH" "$work/upload/$asset.build-info.txt"
  uploads+=("$work/upload/$asset.build-info.txt")
fi
{
  cat "$RELEASE_NOTES"
  echo
  echo "## 安装包"
  echo "\`${asset}\`：${VERSION}（build ${BUILD}），ad-hoc 签名，用 SideStore / AltStore 安装时会用你自己的 Apple ID 重签。SideStore 源：${source_url}"
} > "$work/release-body.md"

# create_or_update <repo> <tag> <token> <latest:true|false|keep> <create-mode:target|verify-tag>
create_or_update() {
  local repo="$1" tag="$2" token="$3" latest="$4" mode="$5"
  local latest_flag
  latest_flag=()
  case "$latest" in
    true) latest_flag=(--latest) ;;
    false) latest_flag=(--latest=false) ;;
  esac
  if GH_TOKEN="$token" gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "-- $repo: release $tag exists, update notes and replace $asset"
    dry || GH_TOKEN="$token" gh release edit "$tag" --repo "$repo" --title "$APP_NAME $VERSION" \
      --notes-file "$work/release-body.md" ${latest_flag[@]+"${latest_flag[@]}"} >/dev/null
  else
    echo "-- $repo: create release $tag (latest: $latest)"
    local where
    where=(--target "$RELEASE_BRANCH")
    [ "$mode" = "verify-tag" ] && where=(--verify-tag)
    dry || GH_TOKEN="$token" gh release create "$tag" --repo "$repo" "${where[@]}" \
      --title "$APP_NAME $VERSION" --notes-file "$work/release-body.md" \
      ${latest_flag[@]+"${latest_flag[@]}"} >/dev/null
  fi
  dry || GH_TOKEN="$token" gh release upload "$tag" --repo "$repo" --clobber "${uploads[@]}"
}

# --- 1. release of the pushed tag in the calling repository --------------------
if [ "$ATTACH_TO_TAG_RELEASE" = "true" ] && [ "$same_release" = "false" ]; then
  create_or_update "$SOURCE_REPO" "$TAG" "$CALLER_TOKEN" keep verify-tag
fi

# --- 2. release that the source downloads from ----------------------------------
mode=target
[ "$same_release" = "true" ] && mode=verify-tag
create_or_update "$RELEASE_REPO" "$dist_tag" "$RELEASE_TOKEN" "$MARK_LATEST" "$mode"

# --- 3. source.json ---------------------------------------------------------------
export GH_TOKEN="$RELEASE_TOKEN"
git_auth=(-c credential.helper= -c 'credential.helper=!gh auth git-credential')
git "${git_auth[@]}" clone --quiet --depth 1 --branch "$RELEASE_BRANCH" \
  "https://github.com/$RELEASE_REPO.git" "$work/repo"
mkdir -p "$work/repo/$source_dir"
if [ ! -f "$work/repo/$source_dir/icon.png" ]; then
  if [ -n "${ICON_PATH:-}" ] && [ -f "$ICON_PATH" ]; then
    echo "-- add $source_dir/icon.png"
    cp "$ICON_PATH" "$work/repo/$source_dir/icon.png"
  else
    echo "-- warning: $source_dir/icon.png is missing and no icon-path was given" >&2
  fi
fi
template=""
[ -n "${APP_TEMPLATE_PATH:-}" ] && template="$work/repo/$APP_TEMPLATE_PATH"

python3 -I "$TOOLS_DIR/sidestore.py" update-source \
  --source "$work/repo/$SOURCE_PATH" --bundle-id "$BUNDLE_ID" --app-name "$APP_NAME" \
  --version "$VERSION" --build "$BUILD" --min-os "${MIN_OS:-}" --size "$SIZE" --sha256 "$SHA256" \
  --download-url "$download_url" --notes-file "$SIDESTORE_NOTES" --ipa "$IPA_PATH" \
  --icon-url "$icon_url" --now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --keep "$KEEP_VERSIONS" \
  --template "$template" --keep-out "$work/keep.txt"

cd "$work/repo"
git add -- "$SOURCE_PATH" "$source_dir"
if git diff --cached --quiet; then
  echo "-- source unchanged"
else
  git --no-pager diff --cached --stat
  if dry; then
    git --no-pager diff --cached -- "$SOURCE_PATH" | sed -n '1,160p'
  else
    git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit --quiet -m "SideStore: $APP_NAME $VERSION (build $BUILD)"
    pushed=false
    for attempt in 1 2 3; do
      if git "${git_auth[@]}" push --quiet origin "HEAD:$RELEASE_BRANCH"; then pushed=true; break; fi
      echo "-- push rejected (attempt $attempt), rebasing on $RELEASE_BRANCH" >&2
      git "${git_auth[@]}" fetch --quiet --depth 20 origin "$RELEASE_BRANCH"
      git -c user.name="github-actions[bot]" \
          -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
          rebase --quiet FETCH_HEAD
    done
    [ "$pushed" = "true" ] || die "could not push $SOURCE_PATH to $RELEASE_REPO"
    echo "-- pushed $SOURCE_PATH"
  fi
fi
cd - >/dev/null

# --- 4. prune old releases, check latest -----------------------------------------
if [ "$PRUNE_RELEASES" = "true" ] && [ "$KEEP_VERSIONS" -gt 0 ]; then
  [ -n "$RELEASE_TAG_PREFIX" ] || die "refusing to prune without a release-tag-prefix"
  while IFS= read -r t; do
    case "$t" in "$RELEASE_TAG_PREFIX"*) ;; *) continue ;; esac
    grep -qxF "${t#"$RELEASE_TAG_PREFIX"}" "$work/keep.txt" && continue
    [ "$t" = "$dist_tag" ] && continue
    echo "-- delete old release $t"
    dry || gh release delete "$t" --repo "$RELEASE_REPO" --yes --cleanup-tag
  done < <(gh release list --repo "$RELEASE_REPO" --limit 200 --json tagName --jq '.[].tagName')
fi

if [ "$MARK_LATEST" != "true" ] && ! dry; then
  latest=$(gh api "repos/$RELEASE_REPO/releases/latest" --jq .tag_name 2>/dev/null || true)
  echo "-- $RELEASE_REPO latest release: ${latest:-none}"
  [ "$latest" != "$dist_tag" ] || die "$RELEASE_REPO latest release is now $dist_tag although mark-latest is false"
  if [ -n "$RELEASE_TAG_PREFIX" ] && [ "$RELEASE_TAG_PREFIX" != "v" ]; then
    case "$latest" in
      "$RELEASE_TAG_PREFIX"*) die "$RELEASE_REPO latest release is $latest, an app release; mark the right one as latest" ;;
    esac
  fi
fi

echo "== source: $source_url"
echo "== IPA:    $download_url"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "download-url=$download_url"; echo "source-url=$source_url"; } >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### $APP_NAME $VERSION (build $BUILD)"
    dry && echo "_Dry run: nothing was uploaded or pushed._"
    echo "- IPA: $download_url"
    echo "- SideStore source: $source_url"
  } >> "$GITHUB_STEP_SUMMARY"
fi
