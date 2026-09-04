#!/usr/bin/env bash
#
# Enforces the partner-sharing privacy boundary as a build gate.
#
# `MenstrualCycleSnapshot` carries fertile score, ovulation day, cycle goal
# (including "trying to conceive"), two-week-wait state, health conditions, flow
# volume and every day-level log. `PartnerCycleDigest` is the redacted view a
# supporter is allowed to see, and `PartnerCycleDigest.init(redacting:)` is the
# single place the two meet.
#
# That design only holds while nobody hands a snapshot to supporter-facing code.
# The compiler cannot express "this file may not name that type", so this does.
# It is the difference between a privacy property and a privacy intention.
#
# Comments are stripped before matching — these files *should* discuss the
# snapshot in prose, and explaining why a boundary exists must not trip the
# check that enforces it.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FORBIDDEN='MenstrualCycleSnapshot'

# Everything a supporter's eyes reach, plus the Messages extension, which runs
# inside someone else's conversation and should hold the least of all.
SUPPORTER_FACING=(
    "ForgeSwift/ForgeSwift/Views/Menstrual/SupporterDigestView.swift"
    "ForgeSwift/ForgeSwift/Services/SupporterGuidance.swift"
)
while IFS= read -r f; do SUPPORTER_FACING+=("$f"); done < <(
    find ForgeSwift/ForgeMessagesExtension -name '*.swift' 2>/dev/null | sort
)

# Strip line comments and block comments so only real code is matched.
strip_comments() {
    sed -e 's://.*::' "$1" | sed -e '/\/\*/,/\*\//d'
}

status=0

for file in "${SUPPORTER_FACING[@]}"; do
    [ -f "$file" ] || continue
    if strip_comments "$file" | grep -n "$FORBIDDEN" >/dev/null 2>&1; then
        echo "✗ $file references $FORBIDDEN in code."
        strip_comments "$file" | grep -n "$FORBIDDEN" | sed 's/^/    /'
        status=1
    fi
done

# The redaction boundary itself: exactly one file may name both types, and only
# to convert between them. More than one crossing point means more than one
# place to audit, which is how these guarantees rot.
DIGEST="ForgeSwift/ForgeSwift/Models/PartnerCycleDigest.swift"
if [ -f "$DIGEST" ]; then
    # Deliberately does not require the parameter list to end here. #156 added a
    # `tier:` argument and this check failed main, reporting that the boundary
    # "moved or was removed" when it had done neither — the tier only ever
    # narrows what a supporter sees (.onPeriod collapses the phase to bleeding
    # or not-bleeding). A gate that cries wolf over a legitimate parameter is a
    # gate people start overriding, which costs more than it protects.
    if ! grep -q 'init(redacting snapshot: MenstrualCycleSnapshot' "$DIGEST"; then
        echo "✗ $DIGEST no longer declares init(redacting:) — the redaction boundary moved or was removed."
        status=1
    fi

    # The invariant the boundary actually rests on, which nothing checked until
    # now: the memberwise initialiser stays private, so init(redacting:) is the
    # only way a snapshot becomes a digest. A caller that can build a digest
    # field by field can put anything in it, and the redaction above becomes
    # decorative.
    if ! grep -q 'private init(phase:' "$DIGEST"; then
        echo "✗ $DIGEST: the memberwise init is no longer private — a digest can now be built"
        echo "  field by field, bypassing init(redacting:) entirely."
        status=1
    fi
    # A headline parameter used to exist and was a hole: a caller holding the
    # full snapshot could write the disclosure into prose the digest never checks.
    if grep -q 'init(redacting[^)]*headline' "$DIGEST"; then
        echo "✗ $DIGEST: init(redacting:) takes a headline again. It must be derived from the digest's own fields."
        status=1
    fi
fi

# The extension must not gain a purchase check. Sharing support with a partner
# is a cornerstone of the product, not an upsell, and a paywall added here would
# be easy to miss in review because it would look like ordinary feature gating.
#
# Comments are stripped here too — the files say in prose that they are ungated,
# and a check that fired on its own documentation would be worse than no check,
# because the first fix anyone reaches for is deleting the sentence.
PAYWALL='StoreKit|SKPayment|Product\.purchase|AppStore\.sync|isSubscribed|isPro\b|hasPro\b|entitlements\['
for file in $(find ForgeSwift/ForgeMessagesExtension -name '*.swift' 2>/dev/null | sort); do
    if strip_comments "$file" | grep -nE "$PAYWALL" >/dev/null 2>&1; then
        echo "✗ $file contains purchase gating. The Messages extension is not paywalled."
        strip_comments "$file" | grep -nE "$PAYWALL" | sed 's/^/    /'
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "✓ partner redaction boundary intact; Messages extension ungated"
fi
exit "$status"
