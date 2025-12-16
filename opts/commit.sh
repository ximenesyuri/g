g_commit() {
    local cmd="$1"
    shift || true

    case "$cmd" in
        new)
            local msg=""
            if [ $# -eq 0 ]; then
                read -e -p "Commit message: " msg
            else
                msg="$*"
            fi
            [ -z "$msg" ] && { echo "No message provided."; return 1; }
            command git commit -m "$msg"
            ;;
        list|ls)
            command git log --oneline --decorate --graph -n "${1:-10}"
            ;;
        rm)
            local targets=()

            if [ "$#" -eq 0 ]; then
                local selected
                selected=$(command git log --oneline | \
                    fzf --multi --prompt="Select commits to delete (oldest to newest): " --height=50%)
                [ -z "$selected" ] && { echo "No commit selected."; return 1; }

                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    local short="${line%% *}"
                    local hash
                    if hash=$(command git rev-parse --verify "$short" 2>/dev/null); then
                        targets+=("$hash")
                    fi
                done <<< "$selected"
            else
                local arg
                for arg in "$@"; do
                    local ref hash
                    if [[ "$arg" =~ ^[0-9]+$ ]]; then
                        local n="$arg"
                        if [ "$n" -lt 1 ]; then
                            echo "Numeric position '$n' must be >= 1." >&2
                            return 1
                        fi
                        if [ "$n" -eq 1 ]; then
                            ref="HEAD"
                        else
                            ref="HEAD~$n"
                        fi
                    else
                        ref="$arg"
                    fi

                    if ! hash=$(command git rev-parse --verify "$ref" 2>/dev/null); then
                        echo "Commit '$arg' (resolved as '$ref') not found." >&2
                        return 1
                    fi
                    targets+=("$hash")
                done
            fi

            if [ "${#targets[@]}" -eq 0 ]; then
                echo "No commits selected." >&2
                return 1
            fi

            local uniq_targets=()
            local h s seen
            for h in "${targets[@]}"; do
                seen=0
                for s in "${uniq_targets[@]}"; do
                    if [ "$s" = "$h" ]; then
                        seen=1
                        break
                    fi
                done
                [ "$seen" -eq 0 ] && uniq_targets+=("$h")
            done

            local head_hash
            head_hash=$(command git rev-parse HEAD)
            for h in "${uniq_targets[@]}"; do
                if ! command git merge-base --is-ancestor "$h" "$head_hash" 2>/dev/null; then
                    echo "Commit $h is not an ancestor of HEAD; cannot remove it with 'g rm'." >&2
                    return 1
                fi
            done

            local base_commit=""
            while IFS= read -r c; do
                for h in "${uniq_targets[@]}"; do
                    if [ "$h" = "$c" ]; then
                        base_commit="$h"
                        break 2
                    fi
                done
            done < <(command git rev-list --reverse "$head_hash" 2>/dev/null)

            if [ -z "$base_commit" ]; then
                echo "Could not determine base commit for rebase." >&2
                return 1
            fi

            local parent_hash
            if ! parent_hash=$(command git rev-parse "${base_commit}^" 2>/dev/null); then
                echo "Cannot remove the root commit with this helper." >&2
                return 1
            fi

            echo "About to remove the following commits (this rewrites history):"
            for h in "${uniq_targets[@]}"; do
                command git log --oneline -1 "$h"
            done
            read -r -p "Proceed with removing these commits? [y/n] " answer
            case "$answer" in
                [Yy]*)
                    ;;
                *)
                    echo "Aborted."
                    return 1
                    ;;
            esac

            local git_dir
            git_dir=$(command git rev-parse --git-dir 2>/dev/null) || {
                echo "Not inside a git repository." >&2
                return 1
            }

            local seq_editor="$git_dir/g-rm-sequence-editor.sh"

            cat > "$seq_editor" <<'EOF'
#!/bin/sh
file="$1"
tmp="$file.tmp"
targets=" $G_RM_COMMITS_FULL "
: > "$tmp"

while IFS= read -r line; do
    case "$line" in
        pick\ *|edit\ *|reword\ *|fixup\ *|squash\ *)
            set -- $line
            cmd="$1"
            hash="$2"
            full_hash=$(command git rev-parse --verify "$hash" 2>/dev/null || echo "")
            if [ -n "$full_hash" ]; then
                case "$targets" in
                    *" $full_hash "*)
                        # Drop this commit
                        echo "drop ${line#* }" >> "$tmp"
                        continue
                        ;;
                esac
            fi
            echo "$line" >> "$tmp"
            ;;
        *)
            echo "$line" >> "$tmp"
            ;;
    esac
done < "$file"

mv "$tmp" "$file"
EOF
            chmod +x "$seq_editor"

            export G_RM_COMMITS_FULL="${uniq_targets[*]}"

            GIT_SEQUENCE_EDITOR="$seq_editor" command git rebase -i "$parent_hash"
            ;;
        edit)
            local target="$1"
            shift || true

            local commit_to_edit
            if [ -z "$target" ]; then
                local selected
                selected=$(command git log --pretty=format:'%h %s [%an]' | \
                    fzf --prompt="Select commit to edit: " --height=50%)
                [ -z "$selected" ] && { echo "No commit selected."; return 1; }
                commit_to_edit=$(awk '{print $1}' <<< "$selected")
            else
                if [[ "$target" =~ ^[0-9]+$ ]]; then
                    commit_to_edit="HEAD~$target"
                else
                    commit_to_edit="$target"
                fi
            fi

            local commit_hash
            if ! commit_hash=$(command git rev-parse --verify "$commit_to_edit" 2>/dev/null); then
                echo "Commit '$commit_to_edit' not found." >&2
                return 1
            fi

            local parent_hash
            if ! parent_hash=$(command git rev-parse "${commit_hash}^" 2>/dev/null); then
                echo "Editing the root commit in this non-interactive mode is not supported." >&2
                echo "You would need an interactive rebase for that specific case." >&2
                return 1
            fi

            local current_branch
            current_branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null)
            if [ -z "$current_branch" ]; then
                echo "You are not on a branch (detached HEAD). Aborting." >&2
                return 1
            fi

            local git_dir
            git_dir=$(command git rev-parse --git-dir 2>/dev/null) || {
                echo "Not inside a git repository." >&2
                return 1
            }

            local state_file="$git_dir/g-edit-state"
            if [ -f "$state_file" ]; then
                echo "There is already an edit in progress (state file: $state_file)." >&2
                echo "Finish it with 'g apply' or delete the state file manually before starting a new edit." >&2
                return 1
            fi

            {
                printf '%s\n' "$current_branch"
                printf '%s\n' "$commit_hash"
            } > "$state_file"

            local short_hash=${commit_hash:0:7}
            local work_branch="g-edit-${short_hash}"

            echo "Creating temporary work branch '$work_branch' from '$current_branch'..."
            command git branch "$work_branch" "$current_branch" || return 1
            command git checkout "$work_branch" || return 1

            command git reset --hard "$commit_hash" || return 1
            command git reset --soft "$parent_hash" || return 1

            cat <<EOF
Commit ${short_hash} has been opened for editing on temporary branch '$work_branch'.

1. Modify files as needed.
2. Commit your changes (one or more commits) on '$work_branch'.

When you are satisfied, run 'g apply' or 'g apply -d/--delete' to delete the temporary branch.
EOF
            ;;
        join)
            local git_dir
            git_dir=$(command git rev-parse --git-dir 2>/dev/null) || {
                echo "Not inside a git repository." >&2
                return 1
            }

            if ! command git diff-index --quiet HEAD --; then
                echo "Working tree is not clean. Commit or stash your changes before using 'g join'." >&2
                return 1
            fi

            local head_full
            head_full=$(command git rev-parse HEAD)

            local root_hash root_short
            root_hash=$(command git rev-list --max-parents=0 HEAD 2>/dev/null | head -n1 || true)
            root_short=""
            if [ -n "$root_hash" ]; then
                root_short=$(command git rev-parse --short "$root_hash" 2>/dev/null || true)
            fi

            local commits=()
            local message=""

            if [ $# -eq 0 ]; then
                local selected
                selected=$(command git log --pretty=format:'%h %s [%an]' | \
                    awk -v r="$root_short" 'r=="" || $1 != r' | \
                    fzf --multi --prompt="Select commits to squash: " --height=50%)
                [ -z "$selected" ] && { echo "No commits selected."; return 1; }

                readarray -t short_hashes <<< "$(printf '%s\n' "$selected" | awk '{print $1}')"

                local h full
                for h in "${short_hashes[@]}"; do
                    full=$(command git rev-parse "$h" 2>/dev/null) || {
                        echo "Invalid commit reference: $h" >&2
                        return 1
                    }
                    if [ -n "$root_hash" ] && [ "$full" = "$root_hash" ]; then
                        echo "Skipping root commit $h; it cannot be squashed." >&2
                        continue
                    fi
                    commits+=( "$full" )
                done

                read -r -p "Squash commit message: " message
                [ -z "$message" ] && { echo "No message provided."; return 1; }
            else
                while [ $# -gt 0 ]; do
                    case "$1" in
                        -m|--message)
                            shift
                            message="$*"
                            break
                            ;;
                        *)
                            local full
                            full=$(command git rev-parse "$1" 2>/dev/null) || {
                                echo "Invalid commit reference: $1" >&2
                                return 1
                            }
                            if [ -n "$root_hash" ] && [ "$full" = "$root_hash" ]; then
                                echo "Root commit ($1) cannot be squashed; aborting." >&2
                                return 1
                            fi
                            commits+=( "$full" )
                            shift
                            ;;
                    esac
                done

                if [ "${#commits[@]}" -lt 1 ]; then
                    echo "No commits specified for 'g join'." >&2
                    return 1
                fi

                if [ -z "$message" ]; then
                    read -r -p "Squash commit message: " message
                    [ -z "$message" ] && { echo "No message provided."; return 1; }
                fi
            fi

            if [ "${#commits[@]}" -lt 2 ]; then
                echo "Select/specify at least two non-root commits to squash." >&2
                return 1
            fi

            local c
            for c in "${commits[@]}"; do
                if ! command git merge-base --is-ancestor "$c" "$head_full" 2>/dev/null; then
                    echo "Commit $c is not an ancestor of HEAD. Aborting." >&2
                    return 1
                fi
            done

            local oldest=""
            local max_dist=-1
            local dist
            for c in "${commits[@]}"; do
                if command git rev-parse "${c}^" >/dev/null 2>&1; then
                    dist=$(command git rev-list --count "${c}^..HEAD")
                else
                    dist=$(command git rev-list --count "${c}..HEAD")
                fi
                if [ "$dist" -gt "$max_dist" ]; then
                    max_dist=$dist
                    oldest="$c"
                fi
            done

            local parent_oldest
            if ! parent_oldest=$(command git rev-parse "${oldest}^" 2>/dev/null); then
                echo "Cannot squash including the root commit with this helper. Use an interactive rebase instead." >&2
                return 1
            fi

            local oldest_short=${oldest:0:7}
            echo "About to squash all commits from ${oldest_short} up to HEAD into a single commit."
            echo "New commit message:"
            echo "  $message"
            read -r -p "Proceed? This rewrites history. [y/N] " answer2
            case "$answer2" in
                [Yy]*)
                    ;;
                *)
                    echo "Aborted."
                    return 1
                    ;;
            esac

            command git reset --soft "$parent_oldest" || return 1
            command git commit -m "$message" || return 1

            echo "Squashed commits from ${oldest_short}..HEAD into a single commit."
            ;;
        update)
            # update commit message
            local target_ref=""
            local commit_hash=""
            local new_message=""

            if [ "$#" -eq 0 ]; then
                local selected
                selected=$(command git log --pretty=format:'%h %s [%an]' | \
                    fzf --prompt="Select commit to update: " --height=50% --layout=reverse --border)
                [ -z "$selected" ] && { echo "No commit selected."; return 1; }
                target_ref=$(awk '{print $1}' <<< "$selected")
            else
                target_ref="$1"
                shift

                if [[ "$target_ref" =~ ^[0-9]+$ ]]; then
                    target_ref="HEAD~$target_ref"
                fi

                while [ "$#" -gt 0 ]; do
                    case "$1" in
                        -m|--message)
                            shift
                            new_message="$*"
                            break
                            ;;
                        *)
                            echo "Unknown option for 'g update': $1" >&2
                            return 1
                            ;;
                    esac
                done
            fi

            if ! commit_hash=$(command git rev-parse --verify "$target_ref" 2>/dev/null); then
                echo "Commit '$target_ref' not found." >&2
                return 1
            fi

            if [ -z "$new_message" ]; then
                local old_message
                old_message=$(command git log -1 --pretty=%B "$commit_hash")
                echo "Current commit message:"
                echo "-----------------------"
                echo "$old_message"
                echo "-----------------------"
                read -r -p "New commit message: " new_message
                [ -z "$new_message" ] && { echo "No new message provided."; return 1; }
            fi

            local head_hash
            head_hash=$(command git rev-parse HEAD)

            if [ "$commit_hash" = "$head_hash" ]; then
                command git commit --amend -m "$new_message"
                return $?
            fi

            local parent_hash2
            if ! parent_hash2=$(command git rev-parse "${commit_hash}^" 2>/dev/null); then
                echo "Cannot update the root commit with this helper." >&2
                return 1
            fi

            local git_dir2
            git_dir2=$(command git rev-parse --git-dir 2>/dev/null) || {
                echo "Not inside a git repository." >&2
                return 1
            }

            local seq_editor="$git_dir2/g-rename-sequence-editor.sh"
            local msg_editor="$git_dir2/g-rename-msg-editor.sh"

            if [ ! -x "$seq_editor" ]; then
                cat > "$seq_editor" <<'EOF'
#!/bin/sh
file="$1"
tmp="$file.tmp"
: > "$tmp"
target="$G_RENAME_TARGET"
while IFS= read -r line; do
    case "$line" in
        "pick $target "*)
            echo "reword ${line#pick }" >> "$tmp"
            ;;
        *)
            echo "$line" >> "$tmp"
            ;;
    esac
done < "$file"
mv "$tmp" "$file"
EOF
                chmod +x "$seq_editor"
            fi

            if [ ! -x "$msg_editor" ]; then
                cat > "$msg_editor" <<'EOF'
#!/bin/sh
file="$1"
printf '%s\n' "$G_RENAME_NEW_MESSAGE" > "$file"
EOF
                chmod +x "$msg_editor"
            fi

            export G_RENAME_TARGET="$commit_hash"
            export G_RENAME_NEW_MESSAGE="$new_message"

            GIT_SEQUENCE_EDITOR="$seq_editor" GIT_EDITOR="$msg_editor" command git rebase -i "$parent_hash2"
            ;;
        send)
            local force_flag=0
            local target_ref="HEAD"

            while [ $# -gt 0 ]; do
                case "$1" in
                    -f|--force)
                        force_flag=1
                        ;;
                    *)
                        target_ref="$1"
                        ;;
                esac
                shift
            done

            if [ "$force_flag" -eq 1 ]; then
                command git push --force origin "$target_ref"
            else
                command git push origin "$target_ref"
            fi
            ;;
        diff)
            if [ $# -eq 0 ]; then
                git diff
                return
            fi
            git difftool -t vimdiff -y "$@"
            ;;
        *)
            if [ -n "$cmd" ] && [[ "$cmd" == *: ]]; then
                local msg
                if [ $# -gt 0 ]; then
                    msg="$cmd $*"
                else
                    msg="$cmd"
                fi
                command git commit -m "$msg"
                return
            fi

            echo "Option not defined for 'g'." >&2
            return 1
            ;;
    esac
}
