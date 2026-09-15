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
you pass stack outputs. Dummy-offline needs none of those.

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


def from_terraform_outputs(outputs: dict, environment: str) -> dict[str, str]:
    """Pull the five values out of the `client_configuration` output."""
    root = outputs.get("client_configuration")
    if root is None:
        raise ConfigError(
            "Terraform outputs have no 'client_configuration'. Run this against "
            "`terraform -chdir=backend/infra output -json` from an applied stack."
        )
    # `terraform output -json` wraps each output as {"value": ..., "type": ...};
    # a bare object is accepted too so a hand-written fixture works.
    config = root.get("value", root) if isinstance(root, dict) else root
    cognito = config.get("cognito") or {}

    return {
        "FORGEAPIBaseURL": str(config.get("apiBaseUrl") or ""),
        "FORGECognitoRegion": str(cognito.get("region") or ""),
        # The iOS client id, not the web one: only the iOS pool client has
        # generate_secret = false and SRP enabled.
        "FORGECognitoClientId": str(cognito.get("iosClientId") or ""),
        "FORGECognitoUserPoolId": str(cognito.get("userPoolId") or ""),
        "FORGEEnvironment": environment,
    }


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
