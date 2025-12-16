g_tag() {
    local sub="${1:-}"
    local all_args=("$@")
    shift || true

    case "$sub" in
        -h|--help)
            echo "Usage: g tag {new|ls|rm|send|update}" >&2
            return 0
            ;;
        new)
            local tagtype="$1"
            shift 1 || true
            local msg="$*"

            if [ -z "$tagtype" ]; then
                echo "Error: Missing tag type (patch, minor, or major)." >&2
                return 1
            fi
            local latest_tag
            latest_tag=$(command git describe --tags --abbrev=0 2>/dev/null)
            local new_tag
            if [ -z "$latest_tag" ]; then
                new_tag="v0.1.0"
            else
                local major minor patch
                IFS='.' read major minor patch <<< "${latest_tag#v}"
                case "$tagtype" in
                    patch) patch=$((patch + 1));;
                    minor) minor=$((minor + 1)); patch=0;;
                    major) major=$((major + 1)); minor=0; patch=0;;
                    *)
                        echo "Invalid tag type: $tagtype. Use patch, minor, or major." >&2
                        return 1
                        ;;
                esac
                new_tag="v$major.$minor.$patch"
            fi
            if [ -n "$msg" ]; then
                command git tag "$new_tag" -m "$msg"
            else
                command git tag "$new_tag"
            fi
            echo "Created new tag: $new_tag"
            ;;
        list|ls)
            command git tag --sort=-creatordate -n
            ;;
        rm)
            local selected tag
            if [ -z "$1" ]; then
                selected=$(command git tag --sort=-creatordate -l | \
                    fzf --multi --prompt="Tag to delete: " --height=30%)
                [ -n "$selected" ] && \
                    for tag in $selected; do command git tag -d "$tag"; done
            else
                command git tag -d "$1"
            fi
            ;;
        send)
            local latest_tag
            latest_tag=$(command git describe --tags --abbrev=0 2>/dev/null)
            [ -z "$latest_tag" ] && { echo "Error: No tags found to push."; return 1; }
            command git push origin "$latest_tag"
            ;;
        update)
            local tag=""
            if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
                tag="$1"
                shift
            fi

            if [ -z "$tag" ]; then
                local selected
                selected=$(command git tag --sort=-creatordate -n | \
                    fzf --prompt="Tag to update: " --height=30% | awk '{print $1}' | head -n1)
                [ -z "$selected" ] && { echo "No tag selected."; return 1; }
                tag="$selected"
            fi

            local new_name=""
            local new_desc=""

            while [ $# -gt 0 ]; do
                case "$1" in
                    --name)
                        shift
                        new_name="$1"
                        ;;
                    --desc|--message|-m)
                        shift
                        new_desc="$1"
                        ;;
                    *)
                        echo "Unknown option for 'g tag update': $1" >&2
                        return 1
                        ;;
                esac
                shift
            done

            local commit_ref
            commit_ref=$(command git rev-list -n 1 "$tag" 2>/dev/null) || {
                echo "Tag '$tag' not found." >&2
                return 1
            }

            local existing_desc
            existing_desc=$(command git for-each-ref "refs/tags/$tag" --format='%(contents)' 2>/dev/null)

            if [ -z "$new_name" ]; then
                read -rp "New tag name [$tag]: " new_name
                [ -z "$new_name" ] && new_name="$tag"
            fi

            if [ -z "$new_desc" ]; then
                if [ -n "$existing_desc" ]; then
                    echo "Current description:"
                    echo "---------------------"
                    echo "$existing_desc"
                    echo "---------------------"
                fi
                read -rp "New tag description (leave empty to keep current/none): " new_desc
                if [ -z "$new_desc" ] && [ -n "$existing_desc" ]; then
                    new_desc="$existing_desc"
                fi
            fi

            command git tag -d "$tag" >/dev/null 2>&1 || true

            if [ -n "$new_desc" ]; then
                if ! command git tag -a "$new_name" -m "$new_desc" "$commit_ref"; then
                    echo "Failed to create updated annotated tag." >&2
                    return 1
                fi
            else
                if ! command git tag "$new_name" "$commit_ref"; then
                    echo "Failed to create updated tag." >&2
                    return 1
                fi
            fi

            echo "Tag updated: $tag -> $new_name"
            ;;
        *)
            command git tag "${all_args[@]}"
            ;;
    esac
}
