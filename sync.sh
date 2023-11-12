#!/bin/bash

verbose=0

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -v|--verbose) verbose=1 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source "$SCRIPT_DIR/sync_settings.conf"

# use variables from config file
local_folder="$LOCAL_FOLDER"
drive_base_folder="$DRIVE_BASE_FOLDER"
drive_folder_name="$DRIVE_FOLDER_NAME"
ignore_list=($IGNORE_LIST) # convert space-separated list to array
drive_folder="$drive_base_folder/$drive_folder_name"

log() {
    local message="$1"
    if [ "$verbose" -eq 1 ]; then
        echo "$message"
    fi
}

init_progress() {
	echo "Starting synchronization..."
	echo "Counting items to synchronize."
    total_items=$(count_items "$drive_folder")
    current_item=0
    echo "Total items to synchronize: $total_items"
}

count_items() {
    local dir="$1"
    local count=0

    for item in $(gio list "$dir"); do
        local full_path="$dir/$item"

        if is_ignored "$item"; then
            continue
        fi

        local item_type=$(gio info "$full_path" | grep "standard::type" | awk '{print $2}')
        if [ "$item_type" == "1" ]; then
            ((count++))
        elif [ "$item_type" == "2" ]; then
            count=$((count + $(count_items "$full_path")))
        fi
    done

    echo $count
}

# update on a progress in console
update_progress() {
    if [ "$verbose" -eq 0 ]; then
        ((current_item++))

		case $((current_item % 3)) in
			0) symbol="/" ;;
			1) symbol="|" ;;
			2) symbol="\\" ;;
		esac
		printf "\rProcessed $current_item/$total_items items $symbol"

    fi
}

is_ignored() {
    local item=$1
    for ignored_item in "${ignore_list[@]}"; do
        if [[ "$item" == "$ignored_item" ]]; then
            return 0 # item is ignored
        fi
    done
    return 1 # item is not ignored
}

copy_file() {
    local source="$1"
    local target="$2"
    if [ "$verbose" -eq 1 ]; then
        log "Copying file from '$source' to '$target'"
    fi
    gio copy "$source" "$target"
}

get_display_name() {
    local path="$1"
    gio info "$path" | grep "display name:" | cut -d' ' -f3-
}

process_directory() {
    local source_dir="$1"
    local target_dir="$2"

    log "Processing directory: $source_dir"

    # create the target dir if not exists
    mkdir -p "$target_dir"

    local item
    for item in $(gio list "$source_dir"); do
        local source_item="$source_dir/$item"
        local display_name=$(get_display_name "$source_item")
        local target_item="$target_dir/$display_name"

        if is_ignored "$display_name"; then
            log "Skipping ignored item: $display_name"
            continue
        fi

        local item_type=$(gio info "$source_item" | grep "standard::type" | awk '{print $2}')
        if [ "$item_type" == "1" ]; then
            copy_file "$source_item" "$target_item"
        elif [ "$item_type" == "2" ]; then
            process_directory "$source_item" "$target_item"
        else
            log "Unknown type for $source_item"
        fi

		update_progress
    done
}

display_elapsed_time() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    local hours=$((elapsed / 3600))
    local minutes=$(( (elapsed % 3600) / 60 ))
    local seconds=$((elapsed % 60))

    local time_string=""

    if [ "$hours" -gt 0 ]; then
        time_string="${hours} hours"
    fi

    if [ "$minutes" -gt 0 ]; then
        if [ -n "$time_string" ]; then
            time_string="${time_string}, "
        fi
        time_string="${time_string}${minutes} minutes"
    fi

    if [ "$seconds" -gt 0 ] || [ -z "$time_string" ]; then
        if [ -n "$time_string" ]; then
            time_string="${time_string}, and "
        fi
        time_string="${time_string}${seconds} seconds"
    fi

    echo -e "\nSynchronization completed in $time_string."
}

init_progress
start_time=$(date +%s)

process_directory "$drive_folder" "$local_folder"

display_elapsed_time $start_time