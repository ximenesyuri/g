g_branch() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        -h|--help)
            echo "Usage: g branch {new|ls|rm|send|rename|rebase|ff|merge}" >&2
            return 0
            ;;
        "")
            command git branch
            return 0
            ;;
        new)
            if [ -n "$1" ]; then
                command git checkout -b "$1"
            else
                echo "Error: Branch name required. Usage: g branch new <branch-name>" >&2
                return 1
            fi
            ;;
        list|ls)
            command git branch -a
            ;;
        rm)
            local selected branch
            if [ -z "$1" ]; then
                selected=$(command git branch --format="%(refname:short)" | \
                    fzf --multi --prompt="Branch to delete: " --height=30%)
                [ -n "$selected" ] && \
                    for branch in $selected; do command git branch -D "$branch"; done
            else
                command git branch -D "$1"
            fi
            ;;
        send)
            local branch_to_push="${1:-HEAD}"
            command git push origin "${branch_to_push}"
            ;;
        rename)
            local target_branch=""
            local new_name=""

            if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
                target_branch="$1"
                shift
            fi

            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --name)
                        shift
                        new_name="$1"
                        ;;
                    *)
                        echo "Unknown option for 'g branch rename': $1" >&2
                        return 1
                        ;;
                esac
                shift
            done

            if [ -z "$target_branch" ]; then
                local selected
                selected=$(command git branch --format="%(refname:short)" | \
                    fzf --prompt="Branch to rename: " --height=30% --layout=reverse --border)
                [ -z "$selected" ] && { echo "No branch selected."; return 1; }
                target_branch="$selected"
            else
                if ! command git show-ref --verify --quiet "refs/heads/$target_branch"; then
                    echo "Branch '$target_branch' does not exist." >&2
                    return 1
                fi
            fi

            if [ -z "$new_name" ]; then
                read -r -p "New name for branch '$target_branch': " new_name
                [ -z "$new_name" ] && { echo "No new branch name provided."; return 1; }
            fi

            command git branch -m "$target_branch" "$new_name"
            ;;
        rebase)
            local remote="origin"
            local branches=()

            while [ "$#" -gt 0 ]; do
                case "$1" in
                    -r|--remote)
                        shift
                        remote="${1:-origin}"
                        ;;
                    *)
                        branches+=("$1")
                        ;;
                esac
                shift
            done

            if [ -z "$remote" ]; then
                remote="origin"
            fi

            local current_branch
            current_branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null || true)

            if [ "${#branches[@]}" -eq 0 ]; then
                echo "Rebasing current HEAD from '$remote' (git pull $remote HEAD --rebase)..."
                if ! command git pull "$remote" HEAD --rebase; then
                    echo "Rebase failed." >&2
                    return 1
                fi
                return 0
            fi

            local start_branch="$current_branch"

            local b target_branch
            for b in "${branches[@]}"; do
                target_branch="$b"
                if [ "$b" = "./HEAD" ]; then
                    if [ -z "$current_branch" ]; then
                        echo "Cannot use ./HEAD when not on a branch." >&2
                        return 1
                    fi
                    target_branch="$current_branch"
                fi

                if ! command git show-ref --verify --quiet "refs/heads/$target_branch"; then
                    echo "Branch '$target_branch' does not exist; skipping." >&2
                    continue
                fi

                echo "Rebasing '$target_branch' from '$remote/$target_branch' (git pull $remote $target_branch --rebase)..."
                if ! command git checkout "$target_branch"; then
                    echo "Failed to checkout '$target_branch'; skipping." >&2
                    continue
                fi

                if ! command git pull "$remote" "$target_branch" --rebase; then
                    echo "Rebase of '$target_branch' failed." >&2
                    if [ -n "$start_branch" ]; then
                        command git checkout "$start_branch" >/dev/null 2>&1 || true
                    fi
                    return 1
                fi
            done

            if [ -n "$start_branch" ] && \
               command git show-ref --verify --quiet "refs/heads/$start_branch"; then
                command git checkout "$start_branch" >/dev/null 2>&1 || true
            fi
            ;;
        ff)
            local remote="origin"
            local branches=()

            while [ "$#" -gt 0 ]; do
                case "$1" in
                    -r|--remote)
                        shift
                        remote="${1:-origin}"
                        ;;
                    *)
                        branches+=("$1")
                        ;;
                esac
                shift
            done

            if [ -z "$remote" ]; then
                remote="origin"
            fi

            local current_branch
            current_branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null || true)

            if [ "${#branches[@]}" -eq 0 ]; then
                echo "Fast-forwarding current HEAD from '$remote' (git pull $remote HEAD --ff)..."
                if ! command git pull "$remote" HEAD --ff; then
                    echo "Fast-forward failed." >&2
                    return 1
                fi
                return 0
            fi

            local start_branch="$current_branch"

            local b target_branch
            for b in "${branches[@]}"; do
                target_branch="$b"
                if [ "$b" = "./HEAD" ]; then
                    if [ -z "$current_branch" ]; then
                        echo "Cannot use ./HEAD when not on a branch." >&2
                        return 1
                    fi
                    target_branch="$current_branch"
                fi

                if ! command git show-ref --verify --quiet "refs/heads/$target_branch"; then
                    echo "Branch '$target_branch' does not exist; skipping." >&2
                    continue
                fi

                echo "Fast-forwarding '$target_branch' from '$remote/$target_branch' (git pull $remote $target_branch --ff)..."
                if ! command git checkout "$target_branch"; then
                    echo "Failed to checkout '$target_branch'; skipping." >&2
                    continue
                fi

                if ! command git pull "$remote" "$target_branch" --ff; then
                    echo "Fast-forward of '$target_branch' failed." >&2
                    if [ -n "$start_branch" ]; then
                        command git checkout "$start_branch" >/dev/null 2>&1 || true
                    fi
                    return 1
                fi
            done

            if [ -n "$start_branch" ] && \
               command git show-ref --verify --quiet "refs/heads/$start_branch"; then
                command git checkout "$start_branch" >/dev/null 2>&1 || true
            fi
            ;;
        merge)
            local branches=()
            local message=""

            while [ "$#" -gt 0 ]; do
                case "$1" in
                    -m|--message)
                        shift
                        message="$*"
                        break
                        ;;
                    *)
                        branches+=("$1")
                        ;;
                esac
                shift
            done

            if [ "${#branches[@]}" -eq 0 ]; then
                local selected
                selected=$(command git branch --format="%(refname:short)" | \
                    fzf --multi --prompt="Branches to merge into current: " \
                        --height=40% --layout=reverse --border)
                [ -z "$selected" ] && { echo "No branches selected."; return 1; }
                read -r -a branches <<< "$selected"
            fi

            local b
            for b in "${branches[@]}"; do
                if ! command git show-ref --verify --quiet "refs/heads/$b"; then
                    echo "Branch '$b' does not exist; aborting merge." >&2
                    return 1
                fi
            done

            if [ -z "$message" ]; then
                echo "Merging branches into $(command git rev-parse --abbrev-ref HEAD): ${branches[*]}"
                read -r -p "Merge commit message: " message
                [ -z "$message" ] && { echo "No merge message provided."; return 1; }
            fi

            if ! command git merge "${branches[@]}" -m "$message"; then
                echo "Merge failed." >&2
                return 1
            fi
            ;;
        *)
            if command git show-ref --verify --quiet "refs/heads/$sub"; then
               command git checkout "$sub"
            else
                command git branch "$sub" "$@"
            fi
            ;;
    esac
}
