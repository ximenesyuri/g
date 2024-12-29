function cd_proj(){
    project_name="$1"
    path=$(get_proj "$project_name" ".local.path" | envsubst )
    if [[ -n "$path" ]]; then
        cd $path
    fi
}

function open_proj(){
    project_name="$1"
    provider=$(get_proj "$project_name" ".server.provider" | envsubst )
    repo=$(get_proj "$project_name" ".server.repo" | envsubst )
    if [[ -n "$path" ]]; then
        cd $path
    fi
}


function list_projs {
    local projects
    projects=$(get_ projects)
    if [[ -n "${projects}" ]]; then
        echo "Projects:"
        echo "$projects" | while read -r project; do
            echo "- $project"
        done
    else
        echo "No projects found."
    fi
}

function new_proj {
    echo "Enter new project name:"
    read -e -r -p "> " project_name
    if [[ -n "$project_name" ]]; then
        echo "Allow issues? (true/false)"
        read -e -r -p "> " issues
        echo "Enter custom labels for this project (comma-separated):"
        read -e -r -p "> " custom_labels

        yq e -i ".projects.${project_name}.issues = $issues" "$G_CONF"
        yq e -i ".projects.${project_name}.labels = [\"${custom_labels//,/\", \"}\"]" "$G_CONF"

        echo "Project '$project_name' added with custom labels '${custom_labels}'."
    else
        echo "Project name cannot be empty."
    fi
}

function edit_proj(){
    echo "TBA"
}

function delete_proj {
    local projects
    projects=$(g_get_projects)
    if [[ -n "${projects}" ]]; then
        local project_name
        project_name=$(echo "$projects" | fzf --prompt="Select a project to remove: $fzf_geometry") || return 1
        echo "Are you sure you want to delete the project '$project_name'? (y/n)"
        read -e -r -p "> " confirm
        if [[ "$confirm" == "y" ]]; then
            yq e -i "del(.projects.\"${project_name}\")" "$G_CONF"
            echo "Project '$project_name' removed."
        else
            echo "Project removal canceled."
        fi
    else
        echo "There are no projects to remove."
    fi
}
