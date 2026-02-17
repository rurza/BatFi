#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

GIT_REPO="/Users/adam/Developer/BatFi"
XCCONFIG="$GIT_REPO/Supporting Files/Config.xcconfig"
ARCHIVES="/Users/adam/Dropbox/Developer/BatFi/Archives"
DOWNLOADS="$HOME/Downloads"
SEPARATOR='<!-- –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––– -->'

# Build 165 (v2.4.2, macOS 13 minimum) is permanently preserved
PRESERVED_BUILDS=(165)
KEEP_RECENT=3

DRY_RUN=false

# ─── Colors & output helpers ─────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}→${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

run() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[dry-run]${NC} $*"
    else
        "$@"
    fi
}

# ─── Utility functions ───────────────────────────────────────────────────────

find_sparkle_bin() {
    local sparkle_bin
    sparkle_bin=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path "*/BatFi-*/SourcePackages/artifacts/sparkle/Sparkle/bin" \
        -type d -print -quit 2>/dev/null)
    if [[ -z "$sparkle_bin" ]]; then
        die "Could not find Sparkle tools in DerivedData. Build BatFi in Xcode first."
    fi
    echo "$sparkle_bin"
}

read_version() {
    grep '^APP_VERSION' "$XCCONFIG" | sed 's/.*= *//'
}

write_version() {
    local new_version=$1
    if $DRY_RUN; then
        echo -e "${YELLOW}[dry-run]${NC} Would update APP_VERSION to $new_version in Config.xcconfig"
    else
        sed -i '' "s/^APP_VERSION = .*/APP_VERSION = $new_version/" "$XCCONFIG"
    fi
}

bump_version() {
    local version=$1 part=$2
    local major minor patch
    IFS='.' read -r major minor patch <<< "$version"
    case "$part" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        patch) echo "$major.$minor.$((patch + 1))" ;;
    esac
}

# Get the build number of the latest item in appcast for a given channel
get_current_build() {
    local channel=$1
    local appcast="$ARCHIVES/appcast.xml"

    if [[ ! -f "$appcast" ]]; then
        echo ""
        return
    fi

    if [[ "$channel" == "beta" ]]; then
        awk '/<item>/{in_item=1; version=""; is_beta=0}
             in_item && /<sparkle:version>/{gsub(/<[^>]*>/,""); gsub(/[[:space:]]/,""); version=$0}
             in_item && /<sparkle:channel>beta/{is_beta=1}
             /<\/item>/{if(in_item && is_beta && version!=""){print version; exit} in_item=0}' "$appcast"
    else
        awk '/<item>/{in_item=1; version=""; is_beta=0}
             in_item && /<sparkle:version>/{gsub(/<[^>]*>/,""); gsub(/[[:space:]]/,""); version=$0}
             in_item && /<sparkle:channel>/{is_beta=1}
             /<\/item>/{if(in_item && !is_beta && version!=""){print version; exit} in_item=0}' "$appcast"
    fi
}

# ─── bump subcommand ─────────────────────────────────────────────────────────

cmd_bump() {
    local part="patch"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --major) part="major"; shift ;;
            --minor) part="minor"; shift ;;
            --patch) part="patch"; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    local current_version new_version
    current_version=$(read_version)
    new_version=$(bump_version "$current_version" "$part")

    info "Bumping version: ${BOLD}$current_version${NC} → ${BOLD}$new_version${NC} ($part)"

    # Generate changelog from git commits since last bump
    local last_bump
    last_bump=$(git -C "$GIT_REPO" log --oneline --all --grep="Bump version" -1 --format="%H" 2>/dev/null || true)

    echo ""
    echo -e "${BOLD}Changelog since last bump:${NC}"
    echo "─────────────────────────"

    if [[ -n "$last_bump" ]]; then
        git -C "$GIT_REPO" log --oneline --no-merges "$last_bump..HEAD" \
            | grep -v "Bump version" \
            || echo "  (no commits)"
    else
        git -C "$GIT_REPO" log --oneline --no-merges -20 \
            | grep -v "Bump version" \
            || echo "  (no commits)"
    fi

    echo "─────────────────────────"
    echo ""

    # Confirm
    read -rp "Proceed with bump to $new_version? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        warn "Aborted."
        exit 0
    fi

    # Update Config.xcconfig
    write_version "$new_version"
    ok "Updated Config.xcconfig"

    # Git commit
    if $DRY_RUN; then
        echo -e "${YELLOW}[dry-run]${NC} Would commit with message: Bump version"
    else
        git -C "$GIT_REPO" add "$XCCONFIG"
        git -C "$GIT_REPO" commit -m "Bump version"
        ok "Created commit: Bump version"
    fi

    echo ""
    ok "Version bumped to ${BOLD}$new_version${NC}. Push to trigger Xcode Cloud build."
}

# ─── publish subcommand ──────────────────────────────────────────────────────

cmd_publish() {
    local channel="" zip_path="" export_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --beta)    channel="beta"; shift ;;
            --stable)  channel="stable"; shift ;;
            --zip)     export_dir="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    [[ -z "$channel" ]] && die "Must specify --beta or --stable"

    # ── Step 1: Locate the Xcode Cloud export zip ─────────────────────────

    local export_zip="$export_dir"

    if [[ -z "$export_zip" ]]; then
        info "No --zip specified, searching for Xcode Cloud exports..."
        export_zip=$(find "$DOWNLOADS" -path "*/Xcode Cloud Artifacts/*" -name "BatFi*developer-id*.zip" -type f 2>/dev/null \
            | xargs ls -t 2>/dev/null | head -1 || true)
        # Fallback: check for already-extracted folders
        if [[ -z "$export_zip" ]]; then
            local export_folder
            export_folder=$(ls -td "$DOWNLOADS"/BatFi*developer-id*/ 2>/dev/null | head -1 || true)
            if [[ -n "$export_folder" ]]; then
                # Find zip inside the folder
                export_zip=$(find "${export_folder%/}" -maxdepth 1 -name "*.zip" -type f -print -quit 2>/dev/null)
            fi
        fi
        [[ -z "$export_zip" ]] && die "No BatFi export found in ~/Downloads"
        info "Found: $export_zip"
    fi

    [[ -f "$export_zip" ]] || die "File not found: $export_zip"

    # ── Step 2: Extract export and read metadata ─────────────────────────

    # Use global so the EXIT trap can clean up after function returns
    _PUBLISH_TMP=$(mktemp -d)
    trap 'rm -rf "$_PUBLISH_TMP"' EXIT
    local tmp_dir="$_PUBLISH_TMP"

    info "Extracting $(basename "$export_zip")..."
    if ! $DRY_RUN; then
        unzip -q "$export_zip" -d "$tmp_dir"
    fi

    # The export zip contains: DistributionSummary.plist, inner app .zip, etc.
    local build_number version

    if $DRY_RUN; then
        # In dry-run, try to read plist if the export was already extracted nearby
        local nearby_dir="${export_zip%.zip}"
        if [[ -d "$nearby_dir" && -f "$nearby_dir/DistributionSummary.plist" ]]; then
            build_number=$(/usr/libexec/PlistBuddy -c "Print :BatFi:0:buildNumber" "$nearby_dir/DistributionSummary.plist")
            version=$(/usr/libexec/PlistBuddy -c "Print :BatFi:0:versionNumber" "$nearby_dir/DistributionSummary.plist")
        else
            build_number="???"
            version="???"
            warn "Cannot read metadata in dry-run without extracting"
        fi
    else
        local dist_plist
        dist_plist=$(find "$tmp_dir" -name "DistributionSummary.plist" -type f -print -quit)
        [[ -z "$dist_plist" ]] && die "DistributionSummary.plist not found in export"

        build_number=$(/usr/libexec/PlistBuddy -c "Print :BatFi:0:buildNumber" "$dist_plist")
        version=$(/usr/libexec/PlistBuddy -c "Print :BatFi:0:versionNumber" "$dist_plist")
    fi

    info "Version: ${BOLD}$version${NC}  Build: ${BOLD}$build_number${NC}  Channel: ${BOLD}$channel${NC}"

    # ── Step 3: Archive current latest ───────────────────────────────────

    local target_zip old_build
    if [[ "$channel" == "stable" ]]; then
        target_zip="$ARCHIVES/BatFi-latest.zip"
        old_build=$(get_current_build "stable")
    else
        target_zip="$ARCHIVES/BatFi-beta.zip"
        old_build=$(get_current_build "beta")
    fi

    if [[ -n "$old_build" && -f "$target_zip" ]]; then
        local archive_name="BatFi($old_build).zip"
        if [[ -f "$ARCHIVES/$archive_name" ]]; then
            warn "$archive_name already exists, skipping rename"
        else
            info "Archiving current $(basename "$target_zip") → $archive_name"
            run mv "$target_zip" "$ARCHIVES/$archive_name"
            ok "Renamed to $archive_name"
        fi
    elif [[ -f "$target_zip" ]]; then
        warn "Could not determine current build number from appcast, skipping archive"
    fi

    # ── Step 4: Re-zip build ─────────────────────────────────────────────

    info "Re-zipping build for Sparkle compatibility..."

    if $DRY_RUN; then
        echo -e "${YELLOW}[dry-run]${NC} Would re-zip BatFi.app with ditto → $(basename "$target_zip")"
    else
        # BatFi.app is directly in the extracted export
        local app_path
        app_path=$(find "$tmp_dir" -name "BatFi.app" -type d -maxdepth 3 -print -quit)
        [[ -z "$app_path" ]] && die "BatFi.app not found in export"

        ditto -c -k --keepParent "$app_path" "$target_zip"
        ok "Created $(basename "$target_zip") ($(du -h "$target_zip" | cut -f1))"
    fi

    # ── Step 5: Generate changelog ───────────────────────────────────────

    info "Generating changelog..."

    local changelog_items=""
    local -a last_two_bumps=()
    while IFS= read -r hash; do
        last_two_bumps+=("$hash")
    done < <(git -C "$GIT_REPO" log --oneline --all --grep="Bump version" -2 --format="%H" 2>/dev/null || true)

    local range=""
    if [[ ${#last_two_bumps[@]} -ge 2 ]]; then
        range="${last_two_bumps[1]}..${last_two_bumps[0]}"
    fi

    # Try AI-generated changelog from actual code changes
    if [[ -n "$range" ]] && command -v claude &>/dev/null; then
        info "Analyzing code changes with Claude..."

        local diff_text changelog_prompt
        diff_text=$(git -C "$GIT_REPO" diff --stat "$range" -- '*.swift' '*.strings' '*.xcconfig' 2>/dev/null || true)
        diff_text+=$'\n'
        diff_text+=$(git -C "$GIT_REPO" diff "$range" -- '*.swift' '*.strings' '*.xcconfig' 2>/dev/null | head -2000 || true)

        if [[ -n "$diff_text" ]]; then
            changelog_prompt="You are writing a changelog for BatFi, a macOS menu bar app for battery management.

Analyze the code diff below. Determine what changed from a user's perspective and write a changelog as HTML list items.

Rules:
- Output ONLY <li>...</li> lines, nothing else. No markdown, no code fences, no explanation.
- Each line must be indented with three tabs before the <li> tag.
- Focus on what changed from the USER's perspective (features, fixes, improvements).
- Ignore internal refactors, code style changes, or things users won't notice.
- Be concise — one short sentence per item.
- If there are no user-facing changes, output a single: <li>Bug fixes and improvements</li>

Code changes:
$diff_text"

            changelog_items=$(CLAUDECODE= claude -p \
                --model sonnet \
                --no-session-persistence \
                --dangerously-skip-permissions \
                "$changelog_prompt" 2>/dev/null || true)
        fi

        # Strip any non-<li> lines Claude might have added
        if [[ -n "$changelog_items" ]]; then
            changelog_items=$(echo "$changelog_items" | grep '<li>' || true)
        fi
    fi

    # Fallback: use commit messages directly
    if [[ -z "$changelog_items" && -n "$range" ]]; then
        warn "Claude not available or produced no output, falling back to commit messages"
        while IFS= read -r line; do
            local msg="${line#* }"
            [[ "$msg" == *"Bump version"* ]] && continue
            changelog_items+=$'\t\t\t'"<li>$msg</li>"$'\n'
        done < <(git -C "$GIT_REPO" log --oneline --no-merges "$range" 2>/dev/null)
    fi

    if [[ -z "$changelog_items" ]]; then
        changelog_items=$'\t\t\t'"<li>Bug fixes and improvements</li>"$'\n'
    fi

    # Remove trailing newline
    changelog_items="${changelog_items%$'\n'}"

    # Open in editor for review
    echo ""
    echo -e "${BOLD}Changelog items:${NC}"
    echo "$changelog_items"
    echo ""

    if ! $DRY_RUN; then
        local edit_file
        edit_file=$(mktemp /tmp/batfi-changelog-XXXXXX.html)
        echo "$changelog_items" > "$edit_file"

        read -rp "Edit changelog in \$EDITOR? [Y/n] " edit_confirm
        if [[ "$edit_confirm" != [nN] ]]; then
            "${EDITOR:-nano}" "$edit_file"
        fi

        changelog_items=$(cat "$edit_file")
        rm -f "$edit_file"
    fi

    # ── Step 6: Update changelog HTML ────────────────────────────────────

    local html_file version_label
    if [[ "$channel" == "stable" ]]; then
        html_file="$ARCHIVES/BatFi-latest.html"
        version_label="Version $version"
    else
        html_file="$ARCHIVES/BatFi-beta.html"
        version_label="Version $version BETA"
    fi

    info "Updating $(basename "$html_file")..."

    if $DRY_RUN; then
        echo -e "${YELLOW}[dry-run]${NC} Would prepend changelog section for $version_label"
    else
        local section_file
        section_file=$(mktemp "${TMPDIR:-/tmp}/batfi-section-XXXXXX.html")
        printf '\n\t\t<h2>%s</h2>\n\t\t<ul>\n%s\n\t\t</ul>\n\n\t\t%s' \
            "$version_label" "$changelog_items" "$SEPARATOR" > "$section_file"

        awk -v sfile="$section_file" '
            /^[[:space:]]*<\/footer>/ && !done {
                print
                while ((getline line < sfile) > 0) print line
                close(sfile)
                done = 1
                next
            }
            {print}
        ' "$html_file" > "$html_file.tmp" && mv "$html_file.tmp" "$html_file"
        rm -f "$section_file"
        ok "Updated $(basename "$html_file")"
    fi

    # ── Step 7: Run generate_appcast ─────────────────────────────────────

    local sparkle_bin
    sparkle_bin=$(find_sparkle_bin)
    info "Running generate_appcast..."

    if $DRY_RUN; then
        if [[ "$channel" == "beta" ]]; then
            echo -e "${YELLOW}[dry-run]${NC} Would run: $sparkle_bin/generate_appcast --channel beta $ARCHIVES/"
        else
            echo -e "${YELLOW}[dry-run]${NC} Would run: $sparkle_bin/generate_appcast $ARCHIVES/"
        fi
    else
        if [[ "$channel" == "beta" ]]; then
            "$sparkle_bin/generate_appcast" --channel beta "$ARCHIVES/"
        else
            "$sparkle_bin/generate_appcast" "$ARCHIVES/"
        fi
        ok "Appcast updated"
    fi

    # ── Step 8: Clean old builds ─────────────────────────────────────────

    info "Cleaning old builds..."

    # Collect all numbered builds
    local -a all_builds=()
    for f in "$ARCHIVES"/BatFi\(*\).zip; do
        [[ -f "$f" ]] || continue
        local num
        num=$(basename "$f" | sed 's/BatFi(\([0-9]*\))\.zip/\1/')
        all_builds+=("$num")
    done

    # Sort descending
    IFS=$'\n' all_builds=($(printf '%s\n' "${all_builds[@]}" | sort -rn)); unset IFS

    # Determine which builds to keep
    local -a keep_builds=("${PRESERVED_BUILDS[@]}")
    local kept=0
    for b in "${all_builds[@]}"; do
        # Skip preserved (already in keep list)
        local is_preserved=false
        for p in "${PRESERVED_BUILDS[@]}"; do
            [[ "$b" == "$p" ]] && is_preserved=true && break
        done
        $is_preserved && continue

        if (( kept < KEEP_RECENT )); then
            keep_builds+=("$b")
            kept=$((kept + 1))
        fi
    done

    # Create dated archive folder for old files
    local archive_date archive_dir
    archive_date=$(date +%Y-%m-%d)
    archive_dir="$ARCHIVES/archive/$archive_date"

    # Move builds not in keep list to dated archive folder
    local moved_count=0
    for b in "${all_builds[@]}"; do
        local should_keep=false
        for k in "${keep_builds[@]}"; do
            [[ "$b" == "$k" ]] && should_keep=true && break
        done

        if ! $should_keep; then
            # Move zip
            if [[ -f "$ARCHIVES/BatFi($b).zip" ]]; then
                if ! $DRY_RUN; then
                    mkdir -p "$archive_dir"
                fi
                info "Archiving BatFi($b).zip → archive/$archive_date/"
                run mv "$ARCHIVES/BatFi($b).zip" "$archive_dir/"
                moved_count=$((moved_count + 1))
            fi
            # Move deltas where this build is the "to" version
            for delta in "$ARCHIVES"/BatFi"$b"-*.delta; do
                [[ -f "$delta" ]] || continue
                if ! $DRY_RUN; then
                    mkdir -p "$archive_dir"
                fi
                info "Archiving $(basename "$delta") → archive/$archive_date/"
                run mv "$delta" "$archive_dir/"
            done
        fi
    done

    # Also archive orphaned deltas (where "to" build has no matching zip or latest/beta)
    # Get all valid "to" builds: kept builds + current latest + current beta
    local -a valid_targets=("${keep_builds[@]}")
    [[ -n "$build_number" ]] && valid_targets+=("$build_number")
    local latest_build beta_build
    latest_build=$(get_current_build "stable")
    beta_build=$(get_current_build "beta")
    [[ -n "$latest_build" ]] && valid_targets+=("$latest_build")
    [[ -n "$beta_build" ]] && valid_targets+=("$beta_build")

    for delta in "$ARCHIVES"/BatFi*-*.delta; do
        [[ -f "$delta" ]] || continue
        local delta_name delta_to
        delta_name=$(basename "$delta")
        delta_to=$(echo "$delta_name" | sed 's/BatFi\([0-9]*\)-.*/\1/')

        local is_valid=false
        for v in "${valid_targets[@]}"; do
            [[ "$delta_to" == "$v" ]] && is_valid=true && break
        done

        if ! $is_valid; then
            if ! $DRY_RUN; then
                mkdir -p "$archive_dir"
            fi
            info "Archiving orphaned delta: $delta_name → archive/$archive_date/"
            run mv "$delta" "$archive_dir/"
        fi
    done

    if (( moved_count == 0 )); then
        ok "No old builds to archive"
    else
        ok "Archived $moved_count old build(s) to archive/$archive_date/"
    fi

    # ── Step 9: Summary ──────────────────────────────────────────────────

    echo ""
    echo -e "${BOLD}═══ Release Summary ═══${NC}"
    echo -e "  Version:     ${BOLD}$version${NC}"
    echo -e "  Build:       ${BOLD}$build_number${NC}"
    echo -e "  Channel:     ${BOLD}$channel${NC}"
    echo -e "  Archive:     $(basename "$target_zip")"
    if [[ -n "$old_build" ]]; then
        echo -e "  Previous:    BatFi($old_build).zip"
    fi
    echo -e "  Changelog:   $(basename "$html_file")"
    echo -e "  Appcast:     appcast.xml"
    echo ""
    echo -e "  Kept builds: ${keep_builds[*]}"
    echo ""
    ok "Done! Files are in Dropbox and will sync automatically."
}

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
${BOLD}batfi-release.sh${NC} — BatFi release automation

${BOLD}USAGE${NC}
    batfi-release.sh bump [--major|--minor|--patch] [--dry-run]
    batfi-release.sh publish --beta|--stable [--zip <path>] [--dry-run]

${BOLD}COMMANDS${NC}
    bump       Bump the version in Config.xcconfig and commit.
               Default: --patch

    publish    Process an Xcode Cloud export and publish via Sparkle.
               Requires --beta or --stable.
               If --zip is omitted, searches ~/Downloads for the newest export.

${BOLD}OPTIONS${NC}
    --dry-run  Show what would happen without making changes.

${BOLD}EXAMPLES${NC}
    batfi-release.sh bump
    batfi-release.sh bump --minor
    batfi-release.sh publish --beta
    batfi-release.sh publish --stable --zip ~/Downloads/BatFi\ 3.0.3\ developer-id/
    batfi-release.sh publish --beta --dry-run
EOF
}

# ─── Main ────────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    bump)    shift; cmd_bump "$@" ;;
    publish) shift; cmd_publish "$@" ;;
    help|-h|--help) usage ;;
    *) die "Unknown command: $1. Use 'bump' or 'publish'." ;;
esac
