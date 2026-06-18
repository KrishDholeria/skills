#!/usr/bin/env bash
# Fetch a (possibly auth-walled) document as plain text on stdout.
# Google Docs/Sheets/Slides URLs are converted to their export endpoints;
# any other URL is fetched as-is.
#
# Auth: tries anonymously first; if that hits a Google sign-in wall, retries
# with the Netscape-format cookie file at $FETCH_DOC_COOKIES
# (default: ~/.claude/secrets/google-cookies.txt). One-time cookie setup is
# documented in the fetch-doc SKILL.md. Cookie contents are never printed.
#
# Exit codes: 0 ok · 2 cookies present but rejected/expired · 3 auth needed,
# no cookie file · 4 HTTP/network failure.
set -euo pipefail

URL="${1:?usage: fetch-doc.sh <url>}"
COOKIES="${FETCH_DOC_COOKIES:-$HOME/.claude/secrets/google-cookies.txt}"

to_export_url() {
  local u="$1"
  if [[ "$u" =~ docs\.google\.com/document/d/([a-zA-Z0-9_-]+) ]]; then
    echo "https://docs.google.com/document/d/${BASH_REMATCH[1]}/export?format=txt"
  elif [[ "$u" =~ docs\.google\.com/spreadsheets/d/([a-zA-Z0-9_-]+) ]]; then
    local gid=""
    [[ "$u" =~ [#\&?]gid=([0-9]+) ]] && gid="&gid=${BASH_REMATCH[1]}"
    echo "https://docs.google.com/spreadsheets/d/${BASH_REMATCH[1]}/export?format=csv${gid}"
  elif [[ "$u" =~ docs\.google\.com/presentation/d/([a-zA-Z0-9_-]+) ]]; then
    echo "https://docs.google.com/presentation/d/${BASH_REMATCH[1]}/export/txt"
  else
    echo "$u"
  fi
}

looks_like_login() {
  head -c 4000 "$1" | grep -qiE 'accounts\.google\.com|ServiceLogin|<title>[^<]*Sign in'
}

EXPORT_URL="$(to_export_url "$URL")"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

fetch() { # args: extra curl options
  curl -sL --max-time 30 "$@" -o "$TMP" -w "%{http_code}" "$EXPORT_URL" || echo "000"
}

CODE="$(fetch)"
if [[ "$CODE" == "200" ]] && ! looks_like_login "$TMP"; then
  cat "$TMP"
  exit 0
fi

if [[ -f "$COOKIES" ]]; then
  CODE="$(fetch -b "$COOKIES")"
  if [[ "$CODE" == "200" ]] && ! looks_like_login "$TMP"; then
    cat "$TMP"
    exit 0
  fi
  if [[ "$CODE" == "200" || "$CODE" == "302" || "$CODE" == "401" || "$CODE" == "403" ]]; then
    echo "fetch-doc: rejected even with cookie file ($COOKIES) — cookies likely expired or the doc isn't shared with this account. Re-export cookies (see fetch-doc SKILL.md)." >&2
    exit 2
  fi
  echo "fetch-doc: HTTP $CODE for $EXPORT_URL" >&2
  exit 4
fi

if looks_like_login "$TMP" || [[ "$CODE" == "401" || "$CODE" == "403" || "$CODE" == "302" ]]; then
  echo "fetch-doc: document requires authentication and no cookie file exists at $COOKIES. One-time setup: see fetch-doc SKILL.md." >&2
  exit 3
fi
echo "fetch-doc: HTTP $CODE for $EXPORT_URL" >&2
exit 4
