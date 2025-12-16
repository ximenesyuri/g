g_help() {
    cat <<'EOF'
Usage: g <command> [options]

Top-level commands:
  info          Show last commit and status
  undo          Undo commits or restore paths
  new           Create a commit
  ls, list      List recent commits
  rm            Remove commits (interactive rebase)
  edit          Edit a past commit on a temp branch
  update        Update a commit message
  join          Squash commits
  send          Push commits
  diff          Show diffs

Command groups:
  branch        Branch-related commands (new/ls/rm/send/rename/rebase/ff/merge)
  tag           Tag-related commands (new/ls/rm/send/update)
  stage         Staging area commands (add/ls/rm)
  conflict      Conflict inspection / resolution (ls/resolve/diff)
  remote        Remote management (new/ls/rm/update)

Run:
  g <group> -h      for group-specific help, e.g. 'g tag -h'
EOF
}

g_general() {
    local cmd="$1"
    shift || true

    case "$cmd" in
        undo)
            if [ $# -eq 0 ]; then
                echo "Usage: g undo <number>  OR  g undo <path> [<path>...]" >&2
                return 1
            fi

            if [ $# -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
                local steps="$1"
                local target_ref="HEAD~$steps"

                if ! command git rev-parse --verify "$target_ref" >/dev/null 2>&1; then
                    echo "Target commit '$target_ref' does not exist." >&2
                    return 1
                fi

                echo "This will run: git reset --hard $target_ref"
                read -r -p "Are you sure you want to discard all uncommitted changes and move HEAD back $steps commit(s)? [y/N] " answer
                case "$answer" in
                    [Yy]*)
                        command git reset --hard "$target_ref"
                        ;;
                    *)
                        echo "Aborted."
                        return 1
                        ;;
                esac
            else
                command git restore -- "$@"
            fi
            ;;
        info)
            command git log -1 --oneline
            command git status
            ;;
        apply)
            # original 'apply' implementation
            local delete_temp_branch=0
            while [ $# -gt 0 ]; do
                case "$1" in
                    -d|--delete)
                        delete_temp_branch=1
                        ;;
                    *)
                        echo "Unknown option for 'g apply': $1" >&2
                        echo "Usage: g apply [-d|--delete]" >&2
                        return 1
                        ;;
                esac
                shift
            done

            local git_dir
            git_dir=$(command git rev-parse --git-dir 2>/dev/null) || {
                echo "Not inside a git repository." >&2
                return 1
            }

            local state_file="$git_dir/g-edit-state"
            if [ ! -f "$state_file" ]; then
                echo "No pending edit state found. Run 'g edit <hash|number>' first." >&2
                return 1
            fi

            local original_branch old_commit_hash
            {
                read -r original_branch
                read -r old_commit_hash
            } < "$state_file"

            if [ -z "$original_branch" ] || [ -z "$old_commit_hash" ]; then
                echo "Edit state file '$state_file' is invalid. Delete it and run 'g edit' again." >&2
                return 1
            fi

            if ! command git rev-parse --verify "$original_branch" >/dev/null 2>&1; then
                echo "Original branch '$original_branch' not found. Aborting." >&2
                return 1
            fi

            if ! command git rev-parse --verify "$old_commit_hash" >/dev/null 2>&1; then
                echo "Old commit '$old_commit_hash' (recorded by g edit) not found. Aborting." >&2
                return 1
            fi

            echo "Applying edited history onto original branch '$original_branch'..."
            echo "Running: git rebase --onto HEAD ${old_commit_hash} ${original_branch}"
            command git rebase --onto HEAD "$old_commit_hash" "$original_branch" || return 1

            rm -f "$state_file"

            if [ "$delete_temp_branch" -eq 1 ]; then
                local short_hash=${old_commit_hash:0:7}
                local temp_branch="g-edit-${short_hash}"
                if command git show-ref --verify --quiet "refs/heads/$temp_branch"; then
                    echo "Deleting temporary branch '$temp_branch'..."
                    command git branch -D "$temp_branch"
                else
                    echo "No temporary branch '$temp_branch' found to delete."
                fi
            fi

            echo
            echo "Rebase completed successfully."
            echo "You are now on branch '$original_branch' with the edited history applied."
            if [ "$delete_temp_branch" -eq 0 ]; then
                echo "If you created a temporary 'g-edit-<hash>' branch, you may delete it manually:"
                echo "  git branch -D g-edit-<hash>"
            fi
            ;;
        .)
            if [ -z "$1" ]; then
               g info
            elif [[ "$1" == "." ]]; then
                if command git add .; then
                    echo "All modified files in \"$PWD\" added to stage."
                else
                    echo "Error adding all changes in \"$PWD\" to the staging area." >&2
                fi
            elif [ "$1" = "all" ]; then
                local repo_root
                repo_root=$(command git rev-parse --show-toplevel || pwd)
                pushd "$repo_root" > /dev/null || return 1
                if command git add .; then
                    echo "All modified files added to stage."
                else
                    echo "Error adding all changes to the staging area." >&2
                fi
                popd > /dev/null || return 1
            else
                if command git add -- "$@"; then
                    local staged_now
                    staged_now=$(git diff --cached --name-only -- "$@" 2>/dev/null | sed '/^$/d')
                    if [ -z "$staged_now" ]; then
                        echo "No changes added to stage for given paths."
                        return 0
                    fi
                    echo "Files added to stage:"
                    local i
                    for i in $staged_now; do
                        if [ -d "$i" ]; then
                            echo "- $i/*"
                        else
                            echo "- $i"
                        fi
                    done
                else
                    echo "Error adding specified files to the staging area." >&2
                fi
            fi
            ;;
        ,)
            if [[ -z "$1" ]]; then
                g branch
                return
            fi
            local branches branch
            branches=$(command git branch --format="%(refname:short)")
            for branch in $branches; do
                if [[ "$1" == "$branch" ]]; then
                    g branch "$branch"
                    return
                fi
            done
            g branch new "$1"
            ;;
        ..)
            if [ "$#" -eq 0 ]; then
                g stage rm
            else
                g stage rm "$@"
            fi
            ;;
        ,.|.,)
            g stage ls
            ;;
        git)
            command git "$@"
            ;;
        -h|--help|"")
            g_help
            ;;
        *)
            echo "Unknown general command: $cmd" >&2
            return 1
            ;;
    esac
}
