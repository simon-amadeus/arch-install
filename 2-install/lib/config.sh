#!/usr/bin/env bash
# Loads a host config YAML into shell variables via yq.
#
# Usage: load_host_config "$HOST_CONFIG_PATH"
# After load, the following globals are set:
#   CFG_HOSTNAME, CFG_KEYMAP, CFG_FONT, CFG_TIMEZONE, CFG_LOCALE
#   CFG_DISK, CFG_ESP_SIZE, CFG_SWAPFILE_SIZE
#   CFG_KERNEL, CFG_MICROCODE
#   CFG_USERNAME

require_cmd yq

load_host_config() {
    local path="$1"
    [[ -f "$path" ]] || die "host config not found: ${path}"

    CFG_HOSTNAME=$(yq -r '.hostname'        "$path")
    CFG_KEYMAP=$(yq   -r '.keymap'          "$path")
    CFG_FONT=$(yq     -r '.console_font'    "$path")
    CFG_TIMEZONE=$(yq -r '.timezone'        "$path")
    CFG_LOCALE=$(yq   -r '.locale'          "$path")

    CFG_DISK=$(yq          -r '.disk.device'         "$path")
    CFG_ESP_SIZE=$(yq      -r '.disk.esp_size'       "$path")
    CFG_SWAPFILE_SIZE=$(yq -r '.disk.swapfile_size'  "$path")

    CFG_KERNEL=$(yq    -r '.kernel'    "$path")
    CFG_MICROCODE=$(yq -r '.microcode' "$path")

    CFG_USERNAME=$(yq -r '.user.name' "$path")
    CFG_REFLECTOR_COUNTRY=$(yq -r '.reflector_country // "Germany"' "$path")

    local missing=()
    for v in CFG_HOSTNAME CFG_KEYMAP CFG_TIMEZONE CFG_LOCALE \
             CFG_DISK CFG_ESP_SIZE CFG_SWAPFILE_SIZE \
             CFG_KERNEL CFG_USERNAME; do
        local val; eval "val=\${${v}:-}"
        [[ -n "$val" && "$val" != "null" ]] || missing+=("$v")
    done
    if (( ${#missing[@]} > 0 )); then
        die "host config missing required keys: ${missing[*]}"
    fi

    log "loaded host config from ${path} (hostname=${CFG_HOSTNAME}, disk=${CFG_DISK})"
}

partition_path() {
    # Returns the kernel name for a given partition number on $CFG_DISK.
    # NVMe uses /dev/nvme0n1p1, SATA uses /dev/sda1.
    local n="$1"
    if [[ "$CFG_DISK" =~ nvme|mmcblk ]]; then
        echo "${CFG_DISK}p${n}"
    else
        echo "${CFG_DISK}${n}"
    fi
}
