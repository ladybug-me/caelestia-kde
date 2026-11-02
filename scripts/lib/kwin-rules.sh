#!/usr/bin/env bash

# The KWin rule groups this project owns, in the order KWin evaluates them, with the keys
# each group writes. Sourced by the installer step and by the uninstaller, so that the
# names and keys are written down once: a group added to one list and not the other is
# either a rule that never applies or a group a revert quietly leaves behind.
#
# The order is load bearing. KWin resolves a forced key with the first matching rule, so
# the exemption for the shell's own windows has to be indexed before the catch-all opacity
# rule that forces the same keys.
CAELESTIA_RULE_KEYS=(
    "caelestia-shell-opacity|Description types wmclass wmclassmatch opacityinactive opacityinactiverule"
    "caelestia-xwaylandvideobridge|Description wmclass wmclassmatch types opacityactive opacityactiverule opacityinactive opacityinactiverule placement placementrule below belowrule skiptaskbar skiptaskbarrule skippager skippagerrule skipswitcher skipswitcherrule noborder noborderrule"
    "caelestia-pip|Description title titlematch above aboverule"
    "caelestia-dialogs|Description types placement placementrule"
    "caelestia-opacity|Description types opacityinactive opacityinactiverule"
)

CAELESTIA_RULE_GROUPS=()
for _caelestia_rule_entry in "${CAELESTIA_RULE_KEYS[@]}"; do
    CAELESTIA_RULE_GROUPS+=("${_caelestia_rule_entry%%|*}")
done
unset _caelestia_rule_entry
