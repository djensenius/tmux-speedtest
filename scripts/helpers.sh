#!/usr/bin/env bash

# Get tmux option with default fallback
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value

    option_value=$(tmux show-option -gqv "$option")
    if [[ -z "$option_value" ]]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# Set tmux option
set_tmux_option() {
    local option="$1"
    local value="$2"
    tmux set-option -gq "$option" "$value"
}

# Check if a speedtest command is the Ookla binary or sivel Python script
# Returns: "ookla", "sivel", or "unknown"
identify_speedtest_type() {
    local cmd="$1"

    # Check if it supports --format=json (Ookla-specific flag)
    if "$cmd" --help 2>&1 | grep -q -- '--format'; then
        echo "ookla"
    # Check if it supports --json (sivel-specific flag)
    elif "$cmd" --help 2>&1 | grep -q -- '--json'; then
        echo "sivel"
    else
        echo "unknown"
    fi
}

# Detect available speedtest CLI
# Returns: "ookla", "sivel", or "none"
detect_speedtest_cli() {
    local prefer
    prefer=$(get_tmux_option "@speedtest_prefer" "auto")

    # If user explicitly prefers one, try to find and verify it
    if [[ "$prefer" == "ookla" ]]; then
        if command -v speedtest &>/dev/null; then
            local type
            type=$(identify_speedtest_type speedtest)
            if [[ "$type" == "ookla" ]]; then
                echo "ookla"
                return
            fi
        fi
    elif [[ "$prefer" == "sivel" ]]; then
        # Check speedtest-cli first, then speedtest
        if command -v speedtest-cli &>/dev/null; then
            echo "sivel"
            return
        elif command -v speedtest &>/dev/null; then
            local type
            type=$(identify_speedtest_type speedtest)
            if [[ "$type" == "sivel" ]]; then
                echo "sivel"
                return
            fi
        fi
    fi

    # Auto-detect: check speedtest-cli first (unambiguous), then speedtest
    if command -v speedtest-cli &>/dev/null; then
        echo "sivel"
    elif command -v speedtest &>/dev/null; then
        # speedtest could be either - identify it
        identify_speedtest_type speedtest
    else
        echo "none"
    fi
}

# Format speed with auto-scaling (bps to Mbps/Gbps)
# Input: speed in bits per second (for sivel) or bytes per second (for ookla)
# Usage: format_speed <value> <source: ookla|sivel>
format_speed() {
    local value="$1"
    local source="$2"
    local mbps

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "?"
        return
    fi

    # Convert to Mbps based on source
    if [[ "$source" == "ookla" ]]; then
        # Ookla reports in bytes per second, convert to Mbps
        mbps=$(echo "scale=2; $value * 8 / 1000000" | bc)
    else
        # sivel reports in bits per second, convert to Mbps
        mbps=$(echo "scale=2; $value / 1000000" | bc)
    fi

    # Auto-scale to Gbps if >= 1000 Mbps
    local gbps
    gbps=$(echo "$mbps >= 1000" | bc)
    if [[ "$gbps" -eq 1 ]]; then
        local formatted
        formatted=$(echo "scale=2; $mbps / 1000" | bc)
        echo "${formatted} Gbps"
    else
        # Round to integer for cleaner display
        local rounded
        rounded=$(echo "scale=0; ($mbps + 0.5) / 1" | bc)
        echo "${rounded} Mbps"
    fi
}

# Format ping (round to integer)
format_ping() {
    local value="$1"

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "?"
        return
    fi

    local rounded
    rounded=$(echo "scale=0; ($value + 0.5) / 1" | bc)
    echo "${rounded}ms"
}

# Build result string from template
# Replaces #{download}, #{upload}, #{ping} in format string
build_result_string() {
    local format="$1"
    local download="$2"
    local upload="$3"
    local ping="$4"

    local result="$format"
    result="${result//\#\{download\}/$download}"
    result="${result//\#\{upload\}/$upload}"
    result="${result//\#\{ping\}/$ping}"

    echo "$result"
}
