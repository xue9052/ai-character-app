#!/usr/bin/env bash
# Configure keychain + provisioning profile + Xcode Manual signing for CI ipa build.
set -euo pipefail

KC_PASS="${KEYCHAIN_PASSWORD:-ci-temp-pass}"
KEYCHAIN="${KEYCHAIN:-build.keychain}"
TEAM_ID="${TEAM_ID:-3B5Z385689}"
PROFILE_NAME="${PROFILE_NAME:-CharacterApp}"
PBX="ios/Runner.xcodeproj/project.pbxproj"

security list-keychains -d user -s "$KEYCHAIN" login.keychain
security default-keychain -s "$KEYCHAIN"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN"

PP="$HOME/Library/MobileDevice/Provisioning Profiles/profile.mobileprovision"
if [[ ! -f "$PP" ]]; then
  echo "missing provisioning profile at $PP"
  exit 1
fi

UUID=$(security cms -D -i "$PP" | plutil -extract UUID raw -)
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PP" "$HOME/Library/MobileDevice/Provisioning Profiles/${UUID}.mobileprovision"
echo "Installed profile UUID=${UUID}"

IDENTITY=""
while IFS= read -r line; do
  id=$(echo "$line" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+[A-F0-9]+[[:space:]]+"([^"]+)".*/\1/')
  if [[ -n "$id" ]]; then
    IDENTITY="$id"
    break
  fi
done < <(
  security find-identity -v -p codesigning "$KEYCHAIN" |
    grep -E 'Apple (Distribution|Development)|iPhone (Distribution|Developer)' || true
)
if [[ -z "$IDENTITY" ]]; then
  echo "No codesign identity found in $KEYCHAIN"
  security find-identity -v -p codesigning "$KEYCHAIN" || true
  exit 1
fi
echo "Using CODE_SIGN_IDENTITY=${IDENTITY}"

python3 - <<PY
import re
from pathlib import Path

pbx_path = Path("${PBX}")
text = pbx_path.read_text(encoding="utf-8")
team = "${TEAM_ID}"
profile = "${PROFILE_NAME}"
identity = """${IDENTITY}"""


def patch_block(block: str) -> str:
    if "PRODUCT_BUNDLE_IDENTIFIER = com.aichar.aiCharacterApp;" not in block:
        return block
    if "RunnerTests" in block:
        return block
    if "CODE_SIGN_STYLE = Manual;" in block:
        return block
    marker = "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;"
    if marker not in block:
        return block
    insert = (
        f'\t\t\t\tCODE_SIGN_IDENTITY = "{identity}";\n'
        f'\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "{identity}";\n'
        f"\t\t\t\tCODE_SIGN_STYLE = Manual;\n"
        f"\t\t\t\tDEVELOPMENT_TEAM = {team};\n"
        f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile}";\n'
    )
    return block.replace(marker + "\n", marker + "\n" + insert, 1)


pattern = re.compile(
    r"/\* (Release|Profile) \*/ = \{.*?name = (Release|Profile);\n\t\t\};",
    re.DOTALL,
)
new_text, n = pattern.subn(lambda m: patch_block(m.group(0)), text)
if n < 2:
    raise SystemExit(f"expected to patch Release+Profile Runner blocks, got {n}")
pbx_path.write_text(new_text, encoding="utf-8")
print(f"Patched {n} Runner build configurations")
PY
