#!/usr/bin/env python3
"""Write the iOS client's API and Cognito configuration.

``ForgeSwift/ForgeSwift/Info-Add.plist`` carries the five FORGE* keys that
``ForgeAuthConfig.fromInfoDictionary`` reads at launch. The committed values
are the Dummy-offline / TestFlight-safe path: no apiBaseUrl, no Cognito ids,
``FORGEEnvironment=dummy``. That ships Dummy ARIA without a live stack and
without embedding 127.0.0.1 / localhost in the binary. It does not enable
Bedrock (``aria_bedrock_enabled`` stays false; this script never touches it).

Live / local API builds still consume Terraform ``client_configuration``
(apiBaseUrl, cognito.region, cognito.iosClientId, cognito.userPoolId) when
you pass stack outputs. Dummy-offline needs none of those. Hex roadmap
gates (provider routing, editable memory, RMSSD) stay off-by-absence in
the Dummy plist; ``--check`` refuses them if they are later added ``true``.
The generator never copies ``ai_provider_secret_arn`` or identity-pool ids.

Usage:

    # Dummy-offline / TestFlight-safe (zero stack outputs)
    scripts/generate_client_config.py --dummy-offline

    terraform -chdir=backend/infra output -json > out.json
    scripts/generate_client_config.py --from out.json --environment prod

    # or let it call Terraform itself
    scripts/generate_client_config.py --terraform-dir backend/infra --environment prod

    # CI: verify what is committed is internally consistent
    scripts/generate_client_config.py --check

The plist is edited in place by replacing single <string> values, not rewritten
through plistlib, so the comments explaining each key survive.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import plistlib
import re
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
PLIST = REPO_ROOT / "ForgeSwift" / "ForgeSwift" / "Info-Add.plist"
WATCH_PLIST = REPO_ROOT / "ForgeSwift" / "ForgeWatch" / "Info-Add.plist"

PRODUCTION_LIKE = {"prod", "production", "staging", "stage"}
# Dummy-offline / TestFlight-safe. No live API, no Cognito, no stack outputs.
DUMMY_OFFLINE = {"dummy"}
KNOWN_ENVIRONMENTS = PRODUCTION_LIKE | DUMMY_OFFLINE | {
    "local",
    "dev",
    "development",
    "test",
    "ci",
}

DUMMY_OFFLINE_VALUES = {
    "FORGEAPIBaseURL": "",
    "FORGECognitoRegion": "",
    "FORGECognitoClientId": "",
    "FORGECognitoUserPoolId": "",
    "FORGEEnvironment": "dummy",
}

# Matches ForgeAuthConfig.defaultLocalAPI and anything else that cannot leave
# the developer's machine.
LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "0.0.0.0", "::1")

KEYS = (
    "FORGEAPIBaseURL",
    "FORGECognitoRegion",
    "FORGECognitoClientId",
    "FORGECognitoUserPoolId",
    "FORGEEnvironment",
)

# Hex roadmap. Off-by-absence is Dummy-offline-safe. If a later PR adds these
# Info.plist keys, Dummy / TestFlight must keep them false so the archive
# still needs no live Cognito, API, provider secret, or stack outputs.
ROADMAP_FLAG_KEYS = (
    "FORGEProviderRoutingEnabled",
    "FORGEEditableMemoryEnabled",
    "FORGERMSSDEnabled",
)
TRUTHY_FLAGS = {"1", "true", "yes", "on"}

# Never copy these Terraform fields into the iOS plist. identityPoolId /
# webClientId are the other frontends; the secret ARN is Lambda-only.
TERRAFORM_CLIENT_BLOCKLIST = (
    "ai_provider_secret_arn",
    "identityPoolId",
    "webClientId",
    "uploadsBucket",
)

SECRET_KEY_MARKERS = (
    "API_KEY",
    "SECRET",
    "PASSWORD",
    "PRIVATE_KEY",
    "ACCESS_TOKEN",
    "AI_PROVIDER",
    "ELEVENLABS",
    "ANTHROPIC",
    "OPENAI",
)
SECRET_VALUE_MARKERS = (
    "arn:aws:secretsmanager",
    "arn:aws:bedrock",
    "akia",
)


class ConfigError(Exception):
    pass


def _value_pattern(key: str) -> re.Pattern[str]:
    """Match the <string> element that follows <key>key</key>.

    Both the empty form (<string></string>) and the self-closed form
    (<string/>) appear in hand-edited plists, so both are accepted.
    """
    return re.compile(
        r"(<key>" + re.escape(key) + r"</key>\s*\n\s*<string)(/>|>.*?</string>)",
        re.DOTALL,
    )


def parse_plist(text: str) -> dict:
    """Parse the file the way Xcode will.

    Worth doing even though the values are then read by name: an Info.plist that
    does not parse fails the build, and a regex read is perfectly happy with a
    file no XML parser will accept. This caught a real one -- an explanatory
    comment containing "--check", which is illegal inside an XML comment.
    """
    try:
        return plistlib.loads(text.encode("utf-8"))
    except Exception as exc:  # plistlib raises several unrelated types
        raise ConfigError(f"{PLIST.name} is not a valid plist: {exc}") from exc


def read_plist_values(text: str) -> dict[str, str]:
    parsed = parse_plist(text)
    values: dict[str, str] = {}
    for key in KEYS:
        if key not in parsed:
            raise ConfigError(f"{PLIST.name} has no <key>{key}</key> entry.")
        value = parsed[key]
        if not isinstance(value, str):
            raise ConfigError(f"{PLIST.name}: {key} must be a <string>, found {type(value).__name__}.")
        values[key] = value
    return values


def write_plist_values(text: str, values: dict[str, str]) -> str:
    """Replace the five values in place.

    Deliberately not a plistlib round trip: rewriting the file would drop the
    comments that explain what each key is for and why the placeholders are
    dangerous, which is most of that file's value.
    """
    parse_plist(text)  # refuse to edit something already broken

    for key, value in values.items():
        pattern = _value_pattern(key)
        if pattern.search(text) is None:
            raise ConfigError(f"{PLIST.name} has no <key>{key}</key> entry.")
        escaped = (
            value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        )
        text = pattern.sub(lambda m: f"{m.group(1)}>{escaped}</string>", text, count=1)

    # And refuse to leave one broken: confirm the edit round-trips to exactly
    # the values asked for before any of it reaches disk.
    written = parse_plist(text)
    for key, value in values.items():
        if written.get(key) != value:
            raise ConfigError(
                f"{PLIST.name}: {key} read back as {written.get(key)!r} after writing {value!r}."
            )
    return text


def is_loopback(url: str) -> bool:
    return any(host in url for host in LOOPBACK_HOSTS)


def _flag_is_on(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if not isinstance(value, str):
        return False
    return value.strip().lower() in TRUTHY_FLAGS


def _stringify(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _walk_strings(payload: object, prefix: str = "") -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    if isinstance(payload, dict):
        for key, value in payload.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            found.extend(_walk_strings(value, path))
    elif isinstance(payload, list):
        for index, value in enumerate(payload):
            found.extend(_walk_strings(value, f"{prefix}[{index}]"))
    elif isinstance(payload, (str, bool, int, float)):
        found.append((prefix, _stringify(payload)))
    return found


def secret_leak_problems(parsed: dict, *, source: str) -> list[str]:
    """Refuse credentials, provider ARNs, and API keys in a shipped plist."""
    problems: list[str] = []
    for path, value in _walk_strings(parsed):
        key_upper = path.upper()
        if any(marker in key_upper for marker in SECRET_KEY_MARKERS):
            problems.append(
                f"{source}: {path} looks like a credential or provider secret. "
                "Dummy-offline ships none of these; ai_provider stays on the Lambda."
            )
            continue
        lowered = value.lower()
        if any(marker in lowered for marker in SECRET_VALUE_MARKERS):
            problems.append(
                f"{source}: {path} embeds {value!r}. Provider ARNs and access keys "
                "must not ship in client config."
            )
    return problems


def roadmap_flag_problems(parsed: dict, *, dummy: bool) -> list[str]:
    """Dummy-offline must not enable live Hex roadmap gates."""
    if not dummy:
        return []
    problems: list[str] = []
    for key in ROADMAP_FLAG_KEYS:
        if key in parsed and _flag_is_on(parsed[key]):
            problems.append(
                f"Dummy-offline must keep {key} off (found {_stringify(parsed[key])!r}). "
                "Provider routing, editable memory, and RMSSD stay local / flagged-off "
                "so TestFlight needs no live Cognito, API, or ai_provider secret."
            )
    return problems


def watch_plist_problems(parsed: dict) -> list[str]:
    problems: list[str] = []
    for key in KEYS:
        if key in parsed:
            problems.append(
                f"{WATCH_PLIST.name} must not carry {key}; phone Info-Add.plist is "
                "the ForgeAuthConfig contract."
            )
    problems.extend(secret_leak_problems(parsed, source=WATCH_PLIST.name))
    return problems


def _cognito_fields(values: dict[str, str]) -> dict[str, str]:
    return {
        key: values[key].strip()
        for key in ("FORGECognitoRegion", "FORGECognitoClientId", "FORGECognitoUserPoolId")
    }


def validate(values: dict[str, str]) -> list[str]:
    """Consistency rules. Dummy-offline is empty on purpose; a lying live config is not."""
    problems: list[str] = []
    environment = values["FORGEEnvironment"].strip().lower()
    api = values["FORGEAPIBaseURL"].strip()
    cognito = _cognito_fields(values)
    cognito_set = {key: value for key, value in cognito.items() if value}

    if environment not in KNOWN_ENVIRONMENTS:
        problems.append(
            f"FORGEEnvironment '{environment}' is not one of "
            f"{', '.join(sorted(KNOWN_ENVIRONMENTS))}. ForgeAuthConfig treats an "
            "unrecognised name as non-production, which is the permissive side."
        )

    # Loopback is unreachable from a device and must never ship in Info.plist,
    # including a Dummy / TestFlight archive that skipped generate-from-terraform.
    if is_loopback(api):
        problems.append(
            f"FORGEAPIBaseURL is {api!r}. Loopback (127.0.0.1 / localhost) must "
            "not ship in client config; Dummy-offline leaves this empty, and a "
            "live build takes apiBaseUrl from stack outputs."
        )

    if environment in DUMMY_OFFLINE:
        if api:
            problems.append(
                f"FORGEAPIBaseURL is {api!r} in Dummy-offline. That path has no "
                "live API; leave it empty so TestFlight does not embed a host."
            )
        if cognito_set:
            problems.append(
                "Dummy-offline must not ship Cognito ids (empty region / client / "
                "pool is the offline signal; filled fields look like live auth). "
                + ", ".join(f"{key}={value!r}" for key, value in cognito_set.items())
            )
        return problems

    if environment in PRODUCTION_LIKE:
        if not api:
            problems.append("FORGEAPIBaseURL is empty in a production-like build.")
        elif not api.startswith("https://"):
            problems.append(
                f"FORGEAPIBaseURL is {api!r}; a production build must use https."
            )

        for key, value in cognito.items():
            if not value:
                problems.append(f"{key} is empty in a production-like build; sign-in cannot work.")
        return problems

    # local / dev / test / ci: either a real https + Cognito stack, or empty
    # placeholders that do not impersonate live auth. Partial Cognito (a region
    # with no client id) is the shape that looks configured and then fails.
    if api:
        if not api.startswith("https://"):
            problems.append(
                f"FORGEAPIBaseURL is {api!r}; a non-loopback client URL must use https."
            )
        for key, value in cognito.items():
            if not value:
                problems.append(
                    f"{key} is empty while FORGEAPIBaseURL is set; that looks like "
                    "live auth with forgotten Cognito ids."
                )
    elif cognito_set:
        problems.append(
            "Cognito fields are set without FORGEAPIBaseURL; Dummy-offline leaves "
            "both empty, and a live build fills both from client_configuration."
        )

    return problems


def hygiene_problems(parsed: dict, values: dict[str, str], *, source: str) -> list[str]:
    """Secrets, ARNs, and Dummy-offline roadmap flags — beyond the five FORGE keys."""
    environment = values["FORGEEnvironment"].strip().lower()
    dummy = environment in DUMMY_OFFLINE
    return (
        secret_leak_problems(parsed, source=source)
        + roadmap_flag_problems(parsed, dummy=dummy)
    )


def audit_committed_plists() -> list[str]:
    problems: list[str] = []
    phone_text = PLIST.read_text(encoding="utf-8")
    phone = parse_plist(phone_text)
    values = read_plist_values(phone_text)
    problems.extend(hygiene_problems(phone, values, source=PLIST.name))
    if WATCH_PLIST.exists():
        watch = parse_plist(WATCH_PLIST.read_text(encoding="utf-8"))
        problems.extend(watch_plist_problems(watch))
    return problems


def from_terraform_outputs(outputs: dict, environment: str) -> dict[str, str]:
    """Pull the five values out of the `client_configuration` output.

    Dummy-offline never calls this. Live mapping is allow-listed: apiBaseUrl plus
    iOS Cognito ids. ``ai_provider_secret_arn``, identity pool, web client id,
    and bucket names stay out of Info.plist even when present in the JSON.
    """
    root = outputs.get("client_configuration")
    if root is None:
        raise ConfigError(
            "Terraform outputs have no 'client_configuration'. Run this against "
            "`terraform -chdir=backend/infra output -json` from an applied stack."
        )
    # `terraform output -json` wraps each output as {"value": ..., "type": ...};
    # a bare object is accepted too so a hand-written fixture works.
    config = root.get("value", root) if isinstance(root, dict) else root
    if not isinstance(config, dict):
        raise ConfigError("client_configuration is not an object.")
    cognito = config.get("cognito") or {}
    if not isinstance(cognito, dict):
        cognito = {}

    values = {
        "FORGEAPIBaseURL": str(config.get("apiBaseUrl") or ""),
        "FORGECognitoRegion": str(cognito.get("region") or ""),
        # The iOS client id, not the web one: only the iOS pool client has
        # generate_secret = false and SRP enabled.
        "FORGECognitoClientId": str(cognito.get("iosClientId") or ""),
        "FORGECognitoUserPoolId": str(cognito.get("userPoolId") or ""),
        "FORGEEnvironment": environment,
    }
    for value in values.values():
        lowered = value.lower()
        if "secretsmanager" in lowered or lowered.startswith("arn:aws:"):
            raise ConfigError(
                "client_configuration mapping leaked a provider ARN into iOS "
                f"plist values: {value!r}"
            )
    return values


def load_outputs(args: argparse.Namespace) -> dict:
    if args.from_file:
        return json.loads(pathlib.Path(args.from_file).read_text(encoding="utf-8"))
    result = subprocess.run(
        ["terraform", f"-chdir={args.terraform_dir}", "output", "-json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ConfigError(f"terraform output failed:\n{result.stderr.strip()}")
    return json.loads(result.stdout)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="validate the committed plist and exit")
    parser.add_argument(
        "--dummy-offline",
        action="store_true",
        help="write Dummy-offline / TestFlight-safe values (no Terraform, no Cognito, no loopback)",
    )
    parser.add_argument("--from", dest="from_file", help="read `terraform output -json` from this file")
    parser.add_argument("--terraform-dir", default="backend/infra", help="run terraform output here")
    parser.add_argument("--environment", help="value for FORGEEnvironment (required unless --check or --dummy-offline)")
    parser.add_argument("--dry-run", action="store_true", help="print the result without writing")
    args = parser.parse_args(argv)

    try:
        text = PLIST.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"generate_client_config: cannot read {PLIST}: {exc}", file=sys.stderr)
        return 2

    environment = (args.environment or "").strip().lower()
    dummy_offline = args.dummy_offline or environment in DUMMY_OFFLINE

    try:
        if args.check:
            values = read_plist_values(text)
        elif dummy_offline:
            if args.from_file:
                parser.error("--dummy-offline / --environment dummy does not take stack outputs")
            if environment and environment not in DUMMY_OFFLINE:
                parser.error("--dummy-offline cannot be combined with a live --environment")
            values = dict(DUMMY_OFFLINE_VALUES)
            if environment:
                values["FORGEEnvironment"] = environment
        else:
            if not environment:
                parser.error("--environment is required unless --check or --dummy-offline is given")
            values = from_terraform_outputs(load_outputs(args), environment)
    except ConfigError as exc:
        print(f"generate_client_config: {exc}", file=sys.stderr)
        return 2

    problems = validate(values)
    if args.check:
        try:
            parsed = parse_plist(text)
        except ConfigError as exc:
            print(f"generate_client_config: {exc}", file=sys.stderr)
            return 2
        problems.extend(hygiene_problems(parsed, values, source=PLIST.name))
        if WATCH_PLIST.exists():
            try:
                watch = parse_plist(WATCH_PLIST.read_text(encoding="utf-8"))
            except ConfigError as exc:
                print(f"generate_client_config: {exc}", file=sys.stderr)
                return 2
            problems.extend(watch_plist_problems(watch))
    if problems:
        print("generate_client_config: refusing this configuration:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    if args.check:
        env = values["FORGEEnvironment"] or "(unset)"
        api = values["FORGEAPIBaseURL"] or "(unset)"
        print(f"generate_client_config: {PLIST.name} consistent (environment={env}, api={api})")
        return 0

    updated = write_plist_values(text, values)
    if args.dry_run:
        print(json.dumps(values, indent=2))
        return 0

    PLIST.write_text(updated, encoding="utf-8")
    print(f"generate_client_config: wrote {PLIST.relative_to(REPO_ROOT)}")
    for key in KEYS:
        print(f"  {key} = {values[key] or '(empty)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
