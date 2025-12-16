#!/bin/bash

_g_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${_g_script_dir}/compl"
source "${_g_script_dir}/opts/general.sh"
source "${_g_script_dir}/opts/commit.sh"
source "${_g_script_dir}/opts/stage.sh"
source "${_g_script_dir}/opts/branch.sh"
source "${_g_script_dir}/opts/tag.sh"
source "${_g_script_dir}/opts/conflict.sh"
source "${_g_script_dir}/opts/remote.sh"

unset _g_script_dir

function g() {
    if ! command -v "awk" > /dev/null 2>&1; then
        echo "error: missing awk."
        return 1
    fi
    if ! command -v "fzf" > /dev/null 2>&1; then
        echo "error: missing fzf."
        return 1
    fi

    local cmd="${1:-}"

    case "$cmd" in
        -h|--help|"")
            g_help
            ;;
        info|undo|apply|.|..|","|",."|".,"|git)
            g_general "$@"
            ;;
        new|list|ls|rm|edit|update|join|send|diff)
            g_commit "$@"
            ;;
        branch)
            shift
            g_branch "$@"
            ;;
        tag|tags)
            shift
            g_tag "$@"
            ;;
        stage|staged)
            shift
            g_stage "$@"
            ;;
        conflict)
            shift
            g_conflict "$@"
            ;;
        remote)
            shift
            g_remote "$@"
            ;;
        *)
            g_commit "$@"
            ;;
    esac
}

