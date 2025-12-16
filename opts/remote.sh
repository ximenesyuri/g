g_remote() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        -h|--help)
            echo "Usage: g remote {new|ls|rm|update}" >&2
            echo "Aliases: ls == list" >&2
            return 0
            ;;
        new)
            local name=""
            local url=""

            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --name)
                        shift
                        name="$1"
                        ;;
                    --url)
                        shift
                        url="$1"
                        ;;
                    *)
                        if [ -z "$name" ]; then
                            name="$1"
                        elif [ -z "$url" ]; then
                            url="$1"
                        else
                            echo "Unexpected argument for 'g remote new': $1" >&2
                            return 1
                        fi
                        ;;
                esac
                shift
            done

            if [ -z "$name" ]; then
                echo "Remote name is required. Usage: g remote new <name> <url> or g remote new --name <name> --url <url>" >&2
                return 1
            fi
            if [ -z "$url" ]; then
                echo "Remote URL is required. Usage: g remote new <name> <url> or g remote new --name <name> --url <url>" >&2
                return 1
            fi

            command git remote add "$name" "$url"
            ;;
        list|ls)
            command git remote -v | awk '{
                key = $1 " " $2;
                if (!seen[key]++) {
                    printf "%-20s %s\n", $1, $2;
                }
            }'
            ;;
        rm)
            local targets=()

            if [ "$#" -eq 0 ]; then
                local remotes
                remotes=$(command git remote -v 2>/dev/null | awk '{print $1 "\t" $2}' | sort -u)
                [ -z "$remotes" ] && { echo "No remotes configured."; return 1; }

                local selected
                selected=$(printf '%s\n' "$remotes" | \
                    fzf --multi --prompt="Remotes to delete: " \
                        --height=40% --layout=reverse --border)
                [ -z "$selected" ] && { echo "No remotes selected."; return 1; }

                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    local name="${line%%$'\t'*}"
                    targets+=("$name")
                done <<< "$selected"
            else
                local arg
                for arg in "$@"; do
                    if command git remote get-url "$arg" >/dev/null 2>&1; then
                        targets+=("$arg")
                    else
                        local by_url
                        by_url=$(command git remote -v | awk -v u="$arg" '$2==u {print $1}' | sort -u)
                        if [ -z "$by_url" ]; then
                            echo "No remote found matching '$arg'." >&2
                        else
                            while IFS= read -r name; do
                                [ -n "$name" ] && targets+=("$name")
                            done <<< "$by_url"
                        fi
                    fi
                done
            fi

            if [ "${#targets[@]}" -eq 0 ]; then
                echo "No remotes to delete." >&2
                return 1
            fi

            local uniq_targets=()
            local t u skip
            for t in "${targets[@]}"; do
                skip=0
                for u in "${uniq_targets[@]}"; do
                    if [ "$u" = "$t" ]; then
                        skip=1
                        break
                    fi
                done
                [ "$skip" -eq 0 ] && uniq_targets+=("$t")
            done

            echo "Remotes to delete: ${uniq_targets[*]}"
            read -r -p "Are you sure you want to delete these remotes? [y/N] " ans
            case "$ans" in
                [Yy]*)
                    ;;
                *)
                    echo "Aborted."
                    return 1
                    ;;
            esac

            local r
            for r in "${uniq_targets[@]}"; do
                command git remote remove "$r"
            done
            ;;
        update)
            local remote_name="$1"
            shift || true
            [ -z "$remote_name" ] && {
                echo "Usage: g remote update <remote> --name <new_name> --url <new_url>" >&2
                return 1
            }

            local new_name=""
            local new_url=""

            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --name)
                        shift
                        new_name="$1"
                        ;;
                    --url)
                        shift
                        new_url="$1"
                        ;;
                    *)
                        echo "Unknown option for 'g remote update': $1" >&2
                        return 1
                        ;;
                esac
                shift
            done

            if [ -z "$new_name" ] && [ -z "$new_url" ]; then
                echo "Provide at least one of --name or --url." >&2
                return 1
            fi

            if ! command git remote get-url "$remote_name" >/dev/null 2>&1; then
                echo "Remote '$remote_name' does not exist." >&2
                return 1
            fi

            if [ -n "$new_name" ] && [ "$new_name" != "$remote_name" ]; then
                command git remote rename "$remote_name" "$new_name" || return 1
                remote_name="$new_name"
            fi

            if [ -n "$new_url" ]; then
                command git remote set-url "$remote_name" "$new_url" || return 1
            fi
            ;;
        *)
            echo "Usage: g remote {new|ls|rm|update}" >&2
            return 1
            ;;
    esac
}
