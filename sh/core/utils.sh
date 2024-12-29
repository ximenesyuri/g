function deps_ {
    local dependencies=("curl" "fzf" "yq" "jq")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "error: '$cmd' is not installed. Please install it before using this script."
            return 1
        fi
    done
}

function input_ {
    function editor_ {
        local file="$1"

        local editor="${EDITOR:-$(command -v vim || echo 'error: No suitable editor found.')}"
        if [[ "$editor" == "error:"* ]]; then
            echo "$editor"
            return 1
        fi

        "$editor" "$file"
    }

    local prompt="> "
    local extension="txt"
    local var="_input"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--prompt)
                prompt="$2"
                shift 2
                ;;
            -e|--ext|--extension)
                extension="$2"
                shift 2
                ;;
            -v|--var)
                var="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local tmp_file
    tmp_file="$(mktemp --suffix=.$extension)"
    local input=""

    exec 3<&0
    exec < /dev/tty

    trap "" SIGINT SIGTSTP # do nothing with Ctrl+C (SIGINT) and Ctrl+Z (SIGTSTP)
    stty -echo
    echo -n "$prompt"

    while true; do
        IFS= read -r -s -n1 char
        case "$char" in
            $'\t'|$'\x09')
                stty echo
                if ! editor_ "$tmp_file"; then
                    rm -f "$tmp_file"
                    return 1
                fi
                input=$(<"$tmp_file")
                input=$(echo "$input" | jq -R -s .)
                rm -f "$tmp_file"
                cd - > /dev/null
                break
                ;;
            '')
                echo
                break
                ;;
            $'\x08'|$'\x7f')
                if [ -n "$input" ]; then
                    input="${input%?}"
                    echo -ne "\b \b"
                fi
                ;;
            $'\x1b'|$'\x04') # ESC and Ctrl+D
                echo
                stty echo
                exec 0<&3 3<&-
                return 0
                ;;
            *)
                input+="$char"
                echo -n "$char"
                ;;
        esac
    done

    stty echo
    exec 0<&3 3<&-
    declare -g "$var"="$input"
}

function is_hex_ {
    local color="$1"
    if [[ $color =~ ^[0-9A-Fa-f]{6}$ ]]; then
        return 0
    else
        return 1
    fi
}

function get_hex_() {
    local color_name="$1"
    case $color_name in
        r|red) echo "$LABEL_RED" ;;
        g|green) echo "$LABEL_GREEN" ;;
        b|blue) echo "$LABEL_BLUE" ;;
        y|yellow) echo "$LABEL_YELLOW" ;;
        c|cyan) echo "$LABEL_CYAN" ;;
        m|magenta) echo "$LABEL_MAGENTA" ;;
        w|white) echo "$LABEL_WHITE" ;;
        b|black) echo "$LABEL_BLACK" ;;
        *)
            if is_hex_ "$color_name"; then
                echo "$color_name"
            else
                error_ "Invalid color input. Use a named color or a valid HEX code." >&2
                return 1
            fi
            ;;
    esac
}

function hex_to_rgb_(){
    r_=$((16#${1:0:2}))
    g_=$((16#${1:2:2}))
    b_=$((16#${1:4:2}))
}

function bg_(){
    hex_to_rgb_ $1
    echo "\033[48;2;${r_};${g_};${b_}m"
}

function fg_(){
    hex_to_rgb_ $1
    echo "\033[38;2;${r_};${g_};${b_}m"
}

function fold_(){
    if [[ -z "$1" ]]; then
        fold -s -w $TEXT_WIDTH
    else
        echo "$1" | fold -s -w $TEXT_WIDTH
    fi
}

function response_() {
    local response="$1"

    if [[ -z "$response" ]]; then
        error_ "Empty response received."
        return 1
    fi

    local message=$(echo "$response" | jq -r '.message // empty' > /dev/null 2>&1)
    
    if [[ ! "$?" == "0" ]]; then
        return 0
    fi
    if [[ -n "$message" ]]; then 
        return 1
    fi

    if [[ -n "$message" ]]; then
        error_ "API Error: $message"
        return 1
    fi

    return 0
}
