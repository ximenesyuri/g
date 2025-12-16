g_stage() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        -h|--help|"")
            echo "Usage: g stage {add|ls|rm}" >&2
            return 0
            ;;
        add)
            local selected
            selected=$(git status --porcelain | \
                awk '{if ($1 ~ /^[MARCU?]/) print $2}' | \
                fzf --multi --prompt="Add file to stage: " --height=30%)
            [ -n "$selected" ] && command git add $selected
            ;;
        list|ls)
            command git diff --cached --name-only
            ;;
        rm)
            if [ "$#" -eq 0 ]; then
                local repo_root current_dir staged
                repo_root=$(git rev-parse --show-toplevel)
                current_dir=$(pwd)
                staged=$(git diff --cached --name-only | \
                    fzf --multi --prompt="Unstage file: " --height=30%)
                if [ -n "$staged" ]; then
                    readarray -t files_to_unstage <<< "$staged"
                    local files_for_reset=()
                    local file
                    for file in "${files_to_unstage[@]}"; do
                        local abs_from_root="$repo_root/$file"
                        local rel_from_cwd
                        rel_from_cwd=$(realpath --relative-to="$current_dir" "$abs_from_root" 2>/dev/null)
                        if [ -n "$rel_from_cwd" ] && [ -e "$rel_from_cwd" ]; then
                            files_for_reset+=("$rel_from_cwd")
                        else
                            files_for_reset+=("$file")
                        fi
                    done
                    if [ "${#files_for_reset[@]}" -eq 0 ]; then
                        echo "No selected files exist to unstage."
                        return 1
                    fi
                    if git reset HEAD -- "${files_for_reset[@]}" > /dev/null; then
                        echo "Unstaged files:"
                        local f
                        for f in "${files_to_unstage[@]}"; do
                            echo "- $f"
                        done
                    else
                        echo "Error unstaging files." >&2
                    fi
                fi
            else
                if git reset HEAD -- "$@" > /dev/null; then
                    echo "Unstaged files:"
                    local f
                    for f in "$@"; do
                        echo "- $f"
                    done
                else
                    echo "Error unstaging files." >&2
                fi
            fi
            ;;
        *)
            echo "Usage: g stage {add|ls|rm}" >&2
            return 1
            ;;
    esac
}
