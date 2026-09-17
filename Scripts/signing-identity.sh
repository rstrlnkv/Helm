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
# With --resolve, a name is turned into the SHA-1 of the identity to sign with.
# Xcode renews an Apple Development certificate by issuing a second one under
# the same name, and codesign refuses a name that matches two identities as
# ambiguous — measured 2026-09-17, the day Xcode added one. The newest to
# expire wins; the keychain and TCC trust both alike, because what they
# recorded is the certificate's name and its Apple chain, not the certificate.
#
# Run: bash Scripts/signing-identity.sh [--resolve]

resolve() {
  local name="$1"
  if [ "$name" = "-" ] || [ "${RESOLVE:-}" != 1 ]; then
    printf '%s\n' "$name"
    return
  fi
  # Every certificate carrying the name, each as its SHA-1 and its PEM.
  local best="" best_end=0 hash="" pem="" line end subject
  while IFS= read -r line; do
    case "$line" in
      "SHA-1 hash: "*) hash="${line#SHA-1 hash: }"; pem="" ;;
      *"BEGIN CERTIFICATE"*) pem="$line" ;;
      *"END CERTIFICATE"*)
        pem="$pem"$'\n'"$line"
        subject="$(printf '%s\n' "$pem" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
          | sed -n 's/^ *commonName *= *//p')"
        end="$(printf '%s\n' "$pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
        end="$(date -j -f '%b %e %T %Y %Z' "$end" +%s 2>/dev/null || echo 0)"
        if [ "$subject" = "$name" ] && [ "$end" -gt "$best_end" ]; then
          best="$hash"; best_end="$end"
        fi
        pem="" ;;
      *) [ -n "$pem" ] && pem="$pem"$'\n'"$line" ;;
    esac
  done < <(security find-certificate -a -c "$name" -Z -p 2>/dev/null || true)
  if [ -z "$best" ]; then
    echo "no certificate named \"$name\" in the keychain — fix" \
         "~/.config/helm/signing-identity, or sign ad-hoc with HELM_SIGN_IDENTITY=-" >&2
    exit 1
  fi
  printf '%s\n' "$best"
}

RESOLVE=0
[ "${1:-}" = "--resolve" ] && RESOLVE=1

if [ -n "${HELM_SIGN_IDENTITY+set}" ]; then
  resolve "${HELM_SIGN_IDENTITY:--}"
  exit 0
fi

CONFIG="$HOME/.config/helm/signing-identity"
if [ -f "$CONFIG" ]; then
  name=""
  IFS= read -r name < "$CONFIG" || true
  if [ -n "$name" ]; then
    resolve "$name"
    exit 0
  fi
fi

resolve "-"
