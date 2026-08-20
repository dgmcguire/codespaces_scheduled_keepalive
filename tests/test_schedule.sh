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

assert_eq() {
	got=$1
	want=$2
	msg=$3
	[ "$got" = "$want" ] || fail "$msg (got $got want $want)"
}

cfg_minute=0
cfg_hours=7-17
cfg_weekdays=1-5
validate_policy

# Thursday 08:00 — %w Thursday = 4
assert_ok "thu 08:00 in work hours" policy_matches_at 0 8 4
assert_ok "thu 07:00 start" policy_matches_at 0 7 4
assert_ok "thu 17:00 end" policy_matches_at 0 17 4
assert_fail "thu 06:00 before" policy_matches_at 0 6 4
assert_fail "thu 18:00 after" policy_matches_at 0 18 4
assert_fail "thu 08:01 not hourly" policy_matches_at 1 8 4
assert_fail "sunday 10:00" policy_matches_at 0 10 0

cfg_hours='*'
cfg_weekdays='*'
validate_policy
assert_ok "hourly any hour any day" policy_matches_at 0 3 3
assert_fail "hourly not on 30" policy_matches_at 30 3 3

cfg_hours=8
cfg_weekdays=4
validate_policy
assert_ok "single hour and weekday" policy_matches_at 0 8 4
assert_fail "wrong hour" policy_matches_at 0 9 4
assert_fail "wrong weekday" policy_matches_at 0 8 5

assert_eq "$(unpad 08)" 8 "unpad 08"
assert_eq "$(unpad 00)" 0 "unpad 00"
assert_eq "$(policy_crontab)" "0 8 * * 4" "policy_crontab"

cfg_minute=0
cfg_hours=7-17
cfg_weekdays=1-5
validate_policy
assert_eq "$(policy_crontab)" "0 7-17 * * 1-5" "work-hours crontab"

if (cfg_minute=99; validate_policy) 2>/dev/null; then
	fail "minute 99 should be rejected"
fi
if (cfg_hours='7,12,17'; validate_policy) 2>/dev/null; then
	fail "hour lists should be rejected"
fi
if (cfg_weekdays=7; validate_policy) 2>/dev/null; then
	fail "weekday 7 should be rejected"
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
pp=":$(path_prefix):"
case $pp in
*':.:'*) fail "path_prefix must not include ." ;;
*':/:'*) fail "path_prefix must not include / as a PATH component" ;;
esac
_old_path=$PATH
PATH=".:/tmp:/usr/bin:/bin"
_got=$(path_prefix)
PATH=$_old_path
case ":$_got:" in
*':.:'*) fail "path_prefix must skip relative PATH entries" ;;
esac

assert_eq "$(xml_escape 'a&b<c>"')" 'a&amp;b&lt;c&gt;&quot;' "xml_escape"
assert_eq "$(sh_quote foo)" "'foo'" "sh_quote plain"
assert_eq "$(sh_quote "it's")" "'it'\\''s'" "sh_quote apostrophe"
assert_eq "$(absolute_path /tmp/x)" /tmp/x "absolute_path already absolute"

got=$(printf 'keep me\nCRON_TZ=UTC  # %s\n0 8 * * * true  # %s\n' "$MARKER" "$MARKER" | crontab_without_marker)
assert_eq "$got" "keep me" "crontab_without_marker"

validate_codespace_name automatic-funicular-5vxw679j7w2vjvx
validate_timezone America/Chicago
if (validate_codespace_name 'evil/name') 2>/dev/null; then
	fail "codespace name with slash should be rejected"
fi
if (validate_timezone 'UTC;id') 2>/dev/null; then
	fail "timezone with metacharacters should be rejected"
fi

oldcfg=$tmp/old.config
printf 'name=automatic-funicular-5vxw679j7w2vjvx\nschedule=0 7-17 * * 1-5\n' >"$oldcfg"
if (load_config "$oldcfg") 2>/dev/null; then
	fail "legacy schedule= should be rejected"
fi

printf 'ok\n'
