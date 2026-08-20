#!/bin/sh
set -eu

export KEEPALIVE_LIB=1
# Dynamic path; the script is linted on its own.
# shellcheck disable=SC1091
. "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/bin/codespaces-keepalive"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_ok() {
	msg=$1
	shift
	if "$@"; then
		return 0
	fi
	fail "$msg"
}

assert_fail() {
	msg=$1
	shift
	if "$@"; then
		fail "$msg"
	fi
}

work='0 7-17 * * 1-5'

# cron_matches_at EXPR MIN HOUR DOM MONTH DOW
# Thursday 08:00 — %w Thursday = 4
assert_ok "thu 08:00 in work hours" cron_matches_at "$work" 0 8 20 8 4
assert_ok "thu 07:00 start" cron_matches_at "$work" 0 7 20 8 4
assert_ok "thu 17:00 end" cron_matches_at "$work" 0 17 20 8 4
assert_fail "thu 06:00 before" cron_matches_at "$work" 0 6 20 8 4
assert_fail "thu 18:00 after" cron_matches_at "$work" 0 18 20 8 4
assert_fail "thu 08:01 not hourly" cron_matches_at "$work" 1 8 20 8 4
assert_fail "sunday 10:00" cron_matches_at "$work" 0 10 20 8 0

assert_ok "hourly any hour" cron_matches_at '0 * * * *' 0 3 1 1 3
assert_fail "hourly not on 30" cron_matches_at '0 * * * *' 30 3 1 1 3

assert_ok "list hours" cron_matches_at '0 7,12,17 * * 1-5' 0 12 20 8 4
assert_fail "list hours miss" cron_matches_at '0 7,12,17 * * 1-5' 0 13 20 8 4

assert_ok "step minutes" cron_matches_at '*/15 * * * *' 0 8 20 8 4
assert_ok "step minutes 45" cron_matches_at '*/15 * * * *' 45 8 20 8 4
assert_fail "step minutes 16" cron_matches_at '*/15 * * * *' 16 8 20 8 4

assert_ok "dow 7 is sunday" cron_matches_at '0 10 * * 7' 0 10 1 1 0
assert_ok "dow names" cron_matches_at '0 8 * * mon-fri' 0 8 20 8 4
assert_fail "dow names sunday" cron_matches_at '0 8 * * mon-fri' 0 8 20 8 0

assert_eq() {
	got=$1
	want=$2
	msg=$3
	[ "$got" = "$want" ] || fail "$msg (got $got want $want)"
}

assert_eq "$(unpad 08)" 8 "unpad 08"
assert_eq "$(unpad 00)" 0 "unpad 00"

validate_schedule '0 7-17 * * 1-5'
validate_schedule '0 * * * mon-fri'

if (validate_schedule '0 7-17 * *') 2>/dev/null; then
	fail "4-field schedule should be rejected"
fi

if (validate_schedule '99 * * * *') 2>/dev/null; then
	fail "minute 99 should be rejected"
fi

assert_eq "$(expand_path "$HOME/logs")" "$HOME/logs" "expand absolute"
# shellcheck disable=SC2088
assert_eq "$(expand_path '~/logs')" "$HOME/logs" "expand ~/"
assert_eq "$(expand_path '~')" "$HOME" "expand ~"
assert_eq "$(parse_bool true)" 1 "parse_bool true"
assert_eq "$(parse_bool false)" 0 "parse_bool false"

log_file=
debug=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
log_file="$tmp/keepalive.log"
log "hello-file"
debug "should-not-appear"
debug=1
debug "debug-line"
grep hello-file "$tmp/keepalive.log" >/dev/null || fail "log did not write file"
grep should-not-appear "$tmp/keepalive.log" >/dev/null && fail "debug logged while off"
grep debug-line "$tmp/keepalive.log" >/dev/null || fail "debug did not write file"

case ":$(path_prefix):" in
*:/bin:* | *:/usr/bin:*) ;;
*) fail "path_prefix should keep POSIX bin dirs from this host" ;;
esac

printf 'ok\n'
