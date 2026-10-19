#!/bin/bash


if command -v systemctl >/dev/null 2>&1; then
    exec systemctl --user restart caelestia-shell.service
fi

exit 1

