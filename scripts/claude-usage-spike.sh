#!/usr/bin/env bash
#
# claude-usage-spike.sh
#
# Phase 3 feasibility spike for BarTab's Claude usage tile (see PRD.md §6.3, §9, §10).
#
# Reads Claude Code's own OAuth credential (read-only — never refreshes or writes it)
# and probes the unofficial usage endpoint that backs Claude Code's `/usage` screen.
#
# SECRET HYGIENE (do not weaken these):
#   - The access/refresh tokens are read into shell variables ONLY, never written to
#     any file, never printed, never logged.
#   - All JSON parsing strips secret fields before anything is echoed. Only field
#     NAMES, lengths, prefixes (yes/no), and non-secret values (timestamps,
#     percentages, scopes, subscription tier) are printed.
#   - This script is safe to commit publicly and safe to re-run: it performs a
#     handful of GET requests and nothing else. It never calls a refresh/token
#     endpoint.
#
# Usage: ./scripts/claude-usage-spike.sh
# Exit code: 0 if the usage endpoint returned 200 with a parseable body, 1 otherwise.

set -uo pipefail

USER_AGENT="claude-code/2.0.0"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"
PROFILE_URL="https://api.anthropic.com/api/oauth/profile"

echo "== BarTab Claude usage spike =="
echo

# --- 1. Locate and read the credential -------------------------------------

TOKEN=""
CRED_SOURCE=""

# Primary: macOS Keychain generic password item written by Claude Code.
# NOTE: the first read in a session may trigger a macOS Keychain consent prompt.
if security find-generic-password -s "Claude Code-credentials" -w >/tmp/.bartab_spike_cred.$$ 2>/dev/null; then
    CRED_SOURCE="keychain"
else
    rm -f /tmp/.bartab_spike_cred.$$
fi

if [ -n "$CRED_SOURCE" ]; then
    # Parse into TOKEN without ever echoing the raw JSON or the token itself.
    TOKEN=$(python3 -c "
import sys, json
with open('/tmp/.bartab_spike_cred.$$') as f:
    raw = f.read()
try:
    data = json.loads(raw)
    print(data.get('claudeAiOauth', {}).get('accessToken', ''), end='')
except Exception:
    pass
")
    # Print non-secret structure/metadata only.
    python3 -c "
import sys, json, datetime
with open('/tmp/.bartab_spike_cred.$$') as f:
    data = json.loads(f.read())
oauth = data.get('claudeAiOauth', {})
print('Credential source: macOS Keychain, service \"Claude Code-credentials\"')
print('Top-level keys:', list(data.keys()))
print('claudeAiOauth fields:', list(oauth.keys()))
at = oauth.get('accessToken', '')
print(f'  accessToken: string(len={len(at)}), sk-ant- prefix: {at.startswith(\"sk-ant-\")}')
print(f'  refreshToken: present={\"refreshToken\" in oauth}')
exp = oauth.get('expiresAt')
if exp:
    dt = datetime.datetime.fromtimestamp(exp/1000, datetime.UTC)
    now = datetime.datetime.now(datetime.UTC)
    print(f'  expiresAt: {exp} epoch-ms => {dt.isoformat()} ({\"EXPIRED\" if dt < now else \"valid\"})')
print('  scopes:', oauth.get('scopes'))
print('  subscriptionType:', oauth.get('subscriptionType'))
print('  rateLimitTier:', oauth.get('rateLimitTier'))
"
    # Securely discard the temp file immediately; never leave credential JSON on disk.
    rm -f /tmp/.bartab_spike_cred.$$
else
    echo "Keychain item \"Claude Code-credentials\" not found or unreadable."
    echo "Falling back to ~/.claude/.credentials.json ..."
    FALLBACK="$HOME/.claude/.credentials.json"
    if [ -f "$FALLBACK" ]; then
        CRED_SOURCE="file:$FALLBACK"
        TOKEN=$(python3 -c "
import json
with open('$FALLBACK') as f:
    data = json.load(f)
print(data.get('claudeAiOauth', data).get('accessToken', ''), end='')
" 2>/dev/null)
        echo "Credential source: $FALLBACK"
    else
        echo "No fallback credential file found at $FALLBACK either."
    fi
fi

echo
if [ -z "$TOKEN" ]; then
    echo "RESULT: no usable access token found. Cannot probe the usage endpoint."
    exit 1
fi

echo "Loaded access token into memory only (length ${#TOKEN} chars). Not printed."
echo

# --- 2. Probe the usage endpoint --------------------------------------------

echo "== Probing $USAGE_URL =="
HTTP_STATUS=$(curl -sS -o /tmp/.bartab_spike_resp.$$ -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    -H "User-Agent: $USER_AGENT" \
    "$USAGE_URL")
echo "HTTP status: $HTTP_STATUS"

RESULT=1
if [ "$HTTP_STATUS" = "200" ]; then
    echo "Response shape (secrets/ids redacted):"
    python3 -c "
import json

def redact(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            kl = k.lower()
            if isinstance(v, str) and ('id' in kl or 'email' in kl or 'org' in kl or 'account' in kl) and len(v) > 4:
                out[k] = v[:4] + '...REDACTED'
            else:
                out[k] = redact(v)
        return out
    if isinstance(obj, list):
        return [redact(x) for x in obj]
    return obj

with open('/tmp/.bartab_spike_resp.$$') as f:
    data = json.load(f)

print(json.dumps(redact(data), indent=2))
"
    RESULT=0
else
    echo "Body:"
    cat /tmp/.bartab_spike_resp.$$
    echo
fi
rm -f /tmp/.bartab_spike_resp.$$

# Unset the token as soon as we're done with it.
unset TOKEN

echo
if [ "$RESULT" -eq 0 ]; then
    echo "RESULT: usage endpoint reachable and returned 200. See SPIKE.md for field mapping."
else
    echo "RESULT: usage endpoint did not return 200 (see status/body above)."
    echo "Common cause: the stored access token is expired (Claude Code access tokens are"
    echo "short-lived and normally auto-refresh only when the local Claude Code CLI/Desktop"
    echo "app actively runs). This script deliberately does NOT refresh the token."
fi

exit $RESULT
