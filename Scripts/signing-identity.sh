#!/bin/bash
set -euo pipefail

# Prints the code-signing identity a build made on this Mac is signed with.
#
# A build signed ad-hoc ("-") is a new program to TCC and to the keychain every
# time it is rebuilt: its designated requirement is its cdhash, so every grant
# and every keychain "Always Allow" is lost and asked again, once per keychain
# item, per build, per app. A certificate kept in this Mac's login keychain
# makes the requirement the certificate, and both survive a rebuild.
#
# That certificate belongs to one Mac and never ships: `make-zip.sh` and
# `make-dmg.sh` refuse any bundle not signed ad-hoc, because a release signed
# with a key that lives on one machine resets every user's grants the day
# that machine or key is gone.
#
# In order:
#   HELM_SIGN_IDENTITY, when set at all — "-" or empty forces ad-hoc, which is
#   how a release is packaged on a Mac that has a local identity;
#   the first line of ~/.config/helm/signing-identity — a personal file outside
#   the repository, holding the certificate's name;
#   otherwise "-".
#
# Run: bash Scripts/signing-identity.sh

if [ -n "${HELM_SIGN_IDENTITY+set}" ]; then
  printf '%s\n' "${HELM_SIGN_IDENTITY:--}"
  exit 0
fi

CONFIG="$HOME/.config/helm/signing-identity"
if [ -f "$CONFIG" ]; then
  name=""
  IFS= read -r name < "$CONFIG" || true
  if [ -n "$name" ]; then
    printf '%s\n' "$name"
    exit 0
  fi
fi

printf '%s\n' "-"
