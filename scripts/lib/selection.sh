#!/usr/bin/env bash
if [[ -z "${CAELESTIA_SELECTION_SOURCED:-}" ]]; then
CAELESTIA_SELECTION_SOURCED=1

select_indices() {
    local count="$1" input="$2"
    local -A picked=()
    local token

    if ((count <= 0)); then
        return 1
    fi

    for token in ${input//,/ }; do
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local from="${BASH_REMATCH[1]}" to="${BASH_REMATCH[2]}" n
            ((from = 10#$from, to = 10#$to))
            ((to > count)) && to="$count"
            for ((n = from < 1 ? 1 : from; n <= to; n++)); do
                picked[$((n - 1))]=1
            done
        elif [[ "$token" =~ ^[0-9]+$ ]]; then
            local n=$((10#$token))
            if ((n >= 1 && n <= count)); then
                picked[$((n - 1))]=1
            fi
        fi
    done

    if ((${#picked[@]} == 0)); then
        return 1
    fi

    printf '%s\n' "${!picked[@]}" | sort -n
}
fi
