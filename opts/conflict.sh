g_conflict() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        -h|--help)
            echo "Usage: g conflict {ls|resolve|diff|<branch>}" >&2
            echo "  g conflict           # show conflicts in current tree" >&2
            echo "  g conflict ls [file] # list conflicts / show markers in file" >&2
            echo "  g conflict resolve [file] # interactive resolve helper" >&2
            return 0
            ;;
        ""|"HEAD")
            local current_branch
            current_branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "HEAD")
            local files
            files=$(command git diff --name-only --diff-filter=U)
            if [ -z "$files" ]; then
                echo "No merge conflicts in current working tree (branch: $current_branch)."
            else
                echo "Current working tree on '$current_branch' has conflicts in:"
                printf '  %s\n' $files
            fi
            ;;
        ls)
            if [ -z "$1" ]; then
                local files
                files=$(command git diff --name-only --diff-filter=U)
                if [ -z "$files" ]; then
                    echo "No files with conflicts."
                else
                    printf '%s\n' $files
                fi
            else
                local file="$1"
                if [ ! -f "$file" ]; then
                    echo "File '$file' not found." >&2
                    return 1
                fi
                if ! grep -q '^<<<<<<< ' "$file"; then
                    echo "No conflict markers found in '$file'."
                    return 0
                fi
                awk '
                    BEGIN { c = 0; showing = 0 }
                    /^<<<<<<< / {
                        c++
                        printf "===== Conflict %d (start line %d) =====\n", c, NR
                        showing = 1
                    }
                    showing { print }
                    /^>>>>>>> / {
                        printf "===== End of conflict %d (line %d) =====\n\n", c, NR
                        showing = 0
                    }
                ' "$file"
            fi
            ;;
        resolve)
            local git_dir
            git_dir=$(command git rev-parse --git-dir 2>/dev/null) || {
                echo "Not inside a git repository." >&2
                return 1
            }

            local state_file="$git_dir/g-edit-state"
            if [ ! -f "$state_file" ]; then
                local current_branch
                current_branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
                if [ -z "$current_branch" ]; then
                    echo "You must be on a branch (not detached HEAD) to start 'g conflict resolve' session." >&2
                    return 1
                fi

                local old_commit_hash
                old_commit_hash=$(command git rev-parse HEAD)

                local has_rebase=0 has_merge=0
                [ -d "$git_dir/rebase-apply" ] || [ -d "$git_dir/rebase-merge" ] && has_rebase=1
                [ -f "$git_dir/MERGE_HEAD" ] && has_merge=1

                if [ "$has_rebase" -eq 1 ]; then
                    echo "A rebase is in progress; moving it to a temp branch safely is not supported yet." >&2
                    echo "Finish/abort the rebase, or resolve conflicts in-place." >&2
                    return 1
                fi

                if [ "$has_merge" -eq 1 ]; then
                    local merge_head merge_msg
                    merge_head=$(cat "$git_dir/MERGE_HEAD" 2>/dev/null || echo "")
                    merge_msg=$(cat "$git_dir/MERGE_MSG" 2>/dev/null || echo "")

                    if [ -z "$merge_head" ]; then
                        echo "MERGE_HEAD not readable; cannot relocate merge to temp branch." >&2
                        return 1
                    fi

                    echo "A merge is in progress on '$current_branch'."
                    echo "To resolve it on a temporary branch, this will:"
                    echo "  - abort the current merge on '$current_branch'"
                    echo "  - create temp branch 'g-edit-${old_commit_hash:0:7}' from '$current_branch' (at $old_commit_hash)"
                    echo "  - re-run the same merge there"
                    echo "Any uncommitted changes and current conflict contents on '$current_branch'"
                    echo "will be discarded and recreated on the temp branch."
                    read -r -p "Proceed? [y/N] " ans
                    case "$ans" in
                        [Yy]*)
                            ;;
                        *)
                            echo "Aborted."
                            return 1
                            ;;
                    esac

                    {
                        printf '%s\n' "$current_branch"
                        printf '%s\n' "$old_commit_hash"
                    } > "$state_file"

                    local short_hash=${old_commit_hash:0:7}
                    local work_branch="g-edit-${short_hash}"

                    echo "Aborting merge on '$current_branch'..."
                    if ! command git merge --abort; then
                        echo "Failed to abort merge on '$current_branch'." >&2
                        rm -f "$state_file"
                        return 1
                    fi

                    echo "Creating temporary merge-resolve branch '$work_branch' from '$current_branch'..."
                    if ! command git branch "$work_branch" "$old_commit_hash"; then
                        echo "Failed to create temporary branch '$work_branch'." >&2
                        rm -f "$state_file"
                        return 1
                    fi
                    if ! command git checkout "$work_branch"; then
                        echo "Failed to checkout temporary branch '$work_branch'." >&2
                        rm -f "$state_file"
                        return 1
                    fi

                    echo "Re-running merge into '$work_branch'..."
                    if [ -n "$merge_msg" ]; then
                        command git merge -m "$merge_msg" "$merge_head" || true
                    else
                        command git merge "$merge_head" || true
                    fi

                    echo "Now on temporary branch '$work_branch' with the merge in progress."
                    echo "Resolve conflicts here (e.g. with 'g conflict resolve <file>'),"
                    echo "commit the result when done, then run 'g apply -d' to move it back to '$current_branch'."

                else
                    {
                        printf '%s\n' "$current_branch"
                        printf '%s\n' "$old_commit_hash"
                    } > "$state_file"

                    local short_hash=${old_commit_hash:0:7}
                    local work_branch="g-edit-${short_hash}"

                    echo "Creating temporary conflict-resolve branch '$work_branch' from '$current_branch'..."
                    if ! command git branch "$work_branch" "$current_branch"; then
                        echo "Failed to create temporary branch '$work_branch'." >&2
                        rm -f "$state_file"
                        return 1
                    fi
                    if ! command git checkout "$work_branch"; then
                        echo "Failed to checkout temporary branch '$work_branch'." >&2
                        rm -f "$state_file"
                        return 1
                    fi

                    echo "Now on temporary branch '$work_branch'."
                    echo "Resolve conflicts here (e.g. with 'g conflict resolve <file>'),"
                    echo "commit your changes, then run 'g apply -d' to apply them back."
                fi
            else
                local original_branch old_commit_hash
                {
                    read -r original_branch
                    read -r old_commit_hash
                } < "$state_file"
                local expected_branch="g-edit-${old_commit_hash:0:7}"
                local current_branch
                current_branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
                if [ "$current_branch" != "$expected_branch" ]; then
                    echo "Conflict/edit session expects branch '$expected_branch', but you are on '$current_branch'." >&2
                    echo "Switch to '$expected_branch' or delete '$state_file' to start a new session." >&2
                    return 1
                fi
            fi

            if [ -z "$1" ]; then
                local files
                files=$(command git diff --name-only --diff-filter=U)
                if [ -z "$files" ]; then
                    echo "No files with conflicts to resolve."
                    return 0
                fi
                if ! command -v fzf >/dev/null 2>&1; then
                    echo "fzf is required for interactive selection (g conflict resolve)." >&2
                    printf '%s\n' $files
                    return 1
                fi
                local selected
                selected=$(printf '%s\n' $files | \
                    fzf --multi --prompt="Select files to resolve: " \
                        --height=40% --layout=reverse --border)
                [ -z "$selected" ] && { echo "No files selected."; return 1; }

                local f
                for f in $selected; do
                    g conflict resolve "$f" || return 1
                done
            else
                local file="$1"
                if [ ! -f "$file" ]; then
                    echo "File '$file' not found." >&2
                    return 1
                fi
                if ! grep -q '^<<<<<<< ' "$file"; then
                    echo "No conflict markers found in '$file'."
                    return 0
                fi

                local tmp_out tmp_ours tmp_theirs
                tmp_out=$(mktemp)
                tmp_ours=$(mktemp)
                tmp_theirs=$(mktemp)

                local in_conflict=0 side=""
                local -a block_lines ours_lines theirs_lines

                while IFS= read -r line || [ -n "$line" ]; do
                    if [ "$in_conflict" -eq 0 ]; then
                        case "$line" in
                            "<<<<<<< "*)
                                in_conflict=1
                                side="ours"
                                block_lines=("$line")
                                ours_lines=()
                                theirs_lines=()
                                ;;
                            *)
                                printf '%s\n' "$line" >> "$tmp_out"
                                ;;
                        esac
                    else
                        case "$side" in
                            ours)
                                if [ "$line" = "=======" ]; then
                                    block_lines+=("$line")
                                    side="theirs"
                                else
                                    block_lines+=("$line")
                                    ours_lines+=("$line")
                                fi
                                ;;
                            theirs)
                                block_lines+=("$line")
                                case "$line" in
                                    ">>>>>>> "*)
                                        printf '%s\n' "${ours_lines[@]}" > "$tmp_ours"
                                        printf '%s\n' "${theirs_lines[@]}" > "$tmp_theirs"

                                        local plus_file minus_file
                                        plus_file=$(mktemp "/tmp/plus-XXXX")
                                        minus_file=$(mktemp "/tmp/minus-XXXX")
                                        cp "$tmp_ours" "$plus_file"
                                        cp "$tmp_theirs" "$minus_file"

                                        echo
                                        echo "========================================"
                                        echo "Conflict in $file"
                                        echo "----------------------------------------"
                                        command git --no-pager diff --no-index --color \
                                            "$plus_file" "$minus_file" || true
                                        echo "----------------------------------------"
                                        echo "plus  = current branch (ours)  -> $plus_file"
                                        echo "minus = other branch (theirs) -> $minus_file"
                                        while true; do
                                            if ! read -r -p "Choose [+] plus, [-] minus, [+-] or [-+], [Enter=skip], [q/quit]: " ans </dev/tty; then
                                                echo "Input closed; aborting conflict resolution for '$file'." >&2
                                                rm -f "$tmp_out" "$tmp_ours" "$tmp_theirs" "$plus_file" "$minus_file"
                                                return 1
                                            fi
                                            case "$ans" in
                                                "+")
                                                    printf '%s\n' "${ours_lines[@]}" >> "$tmp_out"
                                                    rm -f "$plus_file" "$minus_file"
                                                    break
                                                    ;;
                                                "-")
                                                    printf '%s\n' "${theirs_lines[@]}" >> "$tmp_out"
                                                    rm -f "$plus_file" "$minus_file"
                                                    break
                                                    ;;
                                                "+-")
                                                    printf '%s\n' "${ours_lines[@]}" >> "$tmp_out"
                                                    printf '%s\n' "${theirs_lines[@]}" >> "$tmp_out"
                                                    rm -f "$plus_file" "$minus_file"
                                                    break
                                                    ;;
                                                "-+")
                                                    printf '%s\n' "${theirs_lines[@]}" >> "$tmp_out"
                                                    printf '%s\n' "${ours_lines[@]}" >> "$tmp_out"
                                                    rm -f "$plus_file" "$minus_file"
                                                    break
                                                    ;;
                                                "")
                                                    printf '%s\n' "${block_lines[@]}" >> "$tmp_out"
                                                    rm -f "$plus_file" "$minus_file"
                                                    break
                                                    ;;
                                                q|Q|quit|QUIT)
                                                    rm -f "$tmp_out" "$tmp_ours" "$tmp_theirs" "$plus_file" "$minus_file"
                                                    echo "Aborted conflict resolution for '$file'."
                                                    return 1
                                                    ;;
                                                *)
                                                    echo "Please answer with +, -, +-, -+, Enter, or q/quit."
                                                    ;;
                                            esac
                                        done

                                        in_conflict=0
                                        side=""
                                        block_lines=()
                                        ours_lines=()
                                        theirs_lines=()
                                        ;;
                                    *)
                                        theirs_lines+=("$line")
                                        ;;
                                esac
                                ;;
                        esac
                    fi
                done < "$file"

                rm -f "$tmp_ours" "$tmp_theirs"

                if [ "$in_conflict" -ne 0 ]; then
                    rm -f "$tmp_out"
                    echo "Parsing error: unterminated conflict markers in '$file'." >&2
                    return 1
                fi

                mv "$tmp_out" "$file"
                echo "Updated '$file' with resolved conflicts on temporary branch."
                echo "Remember to stage and commit when you are satisfied, then run 'g apply -d' to apply to the original branch."
            fi
            ;;
        diff)
            local file="$1"
            local tmp_ours tmp_theirs
            tmp_ours=$(mktemp) ; tmp_theirs=$(mktemp)
            if ! command git show ":2:$file" >"$tmp_ours" 2>/dev/null ||
               ! command git show ":3:$file" >"$tmp_theirs" 2>/dev/null; then
                rm -f "$tmp_ours" "$tmp_theirs"
                echo "Could not extract ours/theirs for '$file'. Is it in conflict?" >&2
                return 1
            fi
            vimdiff "$tmp_ours" "$tmp_theirs"
            local status=$?
            rm -f "$tmp_ours" "$tmp_theirs"
            return $status
            ;;
        *)
            local target_branch="$sub"
            if ! command git rev-parse --verify "$target_branch" >/dev/null 2>&1; then
                echo "Branch or ref '$target_branch' not found." >&2
                return 1
            fi
            local current_branch
            current_branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "HEAD")
            local base
            if ! base=$(command git merge-base HEAD "$target_branch" 2>/dev/null); then
                echo "No merge base between HEAD and '$target_branch'; cannot determine conflicts." >&2
                return 1
            fi
            local out
            out=$(command git merge-tree "$base" HEAD "$target_branch") || true
            if printf '%s\n' "$out" | grep -q '^<<<<<<< '; then
                echo "Merging '$target_branch' into '$current_branch' WOULD produce conflicts."
            else
                echo "Merging '$target_branch' into '$current_branch' would NOT produce conflicts."
            fi
            ;;
    esac
}
