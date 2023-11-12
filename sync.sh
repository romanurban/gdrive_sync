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

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Source the configuration file from the same directory as the script
source "$SCRIPT_DIR/sync_settings.conf"

# Use variables from config file
local_folder="$LOCAL_FOLDER"
drive_base_folder="$DRIVE_BASE_FOLDER"
drive_folder_name="$DRIVE_FOLDER_NAME"
ignore_list=($IGNORE_LIST) # Convert space-separated list to array
drive_folder="$drive_base_folder/$drive_folder_name"

log() {
    local message="$1"
    if [ "$verbose" -eq 1 ]; then
        echo "$message"
    fi
}
# Function to initialize progress
init_progress() {
    total_items=$(count_items "$drive_folder")
    current_item=0
	toggle=0
    echo "Starting synchronization..."
    echo "Total items to synchronize: $total_items"
}

# Function to count items recursively
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

# Function to update progress
update_progress() {
    if [ "$verbose" -eq 0 ]; then
        # Increment the item counter
        ((current_item++))

        # Toggle the symbol
        if [ "$toggle" -eq 0 ]; then
            symbol="/"
            toggle=1
        else
            symbol="\\"
            toggle=0
        fi

        # Display progress with the symbol
        printf "\rProcessed $current_item/$total_items items $symbol"

        # Print a new line every 50 items or at the end
        if ((current_item % 50 == 0)) || [ "$current_item" -eq "$total_items" ]; then
            echo ""
        fi
    fi
}

# Function to check if a directory is in the ignore list
is_ignored() {
    local item=$1
    for ignored_item in "${ignore_list[@]}"; do
        if [[ "$item" == "$ignored_item" ]]; then
            return 0 # True, item is ignored
        fi
    done
    return 1 # False, item is not ignored
}

# Function to copy a file
copy_file() {
    local source="$1"
    local target="$2"
    if [ "$verbose" -eq 1 ]; then
        log "Copying file from '$source' to '$target'"
    fi
    gio copy "$source" "$target"
}

# Function to get the display name using gio info
get_display_name() {
    local path="$1"
    gio info "$path" | grep "display name:" | cut -d' ' -f3-
}

# Function to recursively process items
process_directory() {
    local source_dir="$1"
    local target_dir="$2"

    log "Processing directory: $source_dir"

    # Create the target directory
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

# Start the sync process
init_progress
start_time=$(date +%s)

process_directory "$drive_folder" "$local_folder"

# End of the sync process
end_time=$(date +%s)
elapsed=$((end_time - start_time))

hours=$((elapsed / 3600))
minutes=$(( (elapsed % 3600) / 60 ))
seconds=$((elapsed % 60))

echo -e "\nSynchronization completed in $hours hours, $minutes minutes, and $seconds seconds."
