#! /bin/sh
# Live CI checks for a running handshake-volume-resolver container.
#
# Usage:
#   CONTAINER_NAME=hvr-ci ./ci/run-tests.sh
#   DNS_HOST=127.0.0.8 DNS_PORT=53 ./ci/run-tests.sh
#
# dig flags are always explicit (+rec/+norec, +tcp/+notcp, +dnssec, +adflag).
# Tests never use real is-this-you zone data.
#
# Handshake TLD lookups need an hsd node and are skipped here. In CI,
# HSD_MASTERS is pointed at ICANN f-root and c-root so the root_proxy
# fallback still answers ICANN names, and a made-up TLD must return
# NXDOMAIN (not SERVFAIL) through the internal-root then external-root
# path. .eth lookups need ethereum-dns-gateway and are also skipped.

set -eu

DNS_HOST=${DNS_HOST:-}
DNS_PORT=${DNS_PORT:-53}
CONTAINER_NAME=${CONTAINER_NAME:-hvr-ci}
WAIT_FOR_ZONE=${WAIT_FOR_ZONE:-180}
DIG_TIME=${DIG_TIME:-5}
DIG_TRIES=${DIG_TRIES:-2}
# Made-up TLD used to exercise root_proxy's NXDOMAIN fallback.
FAKE_TLD=${FAKE_TLD:-test.xyz-not-a-tld.}
# Synthetic auth zone served from ci/auth_zones (mounted at start).
AUTH_ZONE=${AUTH_ZONE:-ci-auth.test}
AUTH_ADDR=${AUTH_ADDR:-192.0.2.1}

passed=0
failed=0
skipped=0
warned=0

pass() {
	passed=$((passed + 1))
	printf 'PASS  %s\n' "$*"
}

fail() {
	failed=$((failed + 1))
	printf 'FAIL  %s\n' "$*"
}

skip() {
	skipped=$((skipped + 1))
	printf 'SKIP  %s\n' "$*"
}

warn() {
	warned=$((warned + 1))
	printf 'WARN  %s\n' "$*"
}

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1
	then
		printf 'ERROR  required command not found: %s\n' "$1" >&2
		exit 2
	fi
}

# ---------------------------------------------------------------------------
# dig helpers — flags are always explicit, never implied
# Remaining arguments are name, type, and any extra dig options.
# ---------------------------------------------------------------------------
dig_query() {
	_rd=$1
	_tcp=$2
	_dnssec=$3
	_ad=$4
	shift 4
	dig @"${DNS_HOST}" -p "${DNS_PORT}" \
		+time="${DIG_TIME}" +tries="${DIG_TRIES}" \
		"${_rd}" "${_tcp}" "${_dnssec}" "${_ad}" \
		+nocmd +nostats \
		"$@"
}

# Passed by name into check_fake_nxdomain (and dig_norec is also
# called directly). shellcheck 0.9 reports SC2317; 0.11 reports
# SC2329 for the indirect call.
# shellcheck disable=SC2317,SC2329
dig_rec() {
	dig_query +rec +notcp +dnssec +adflag "$@"
}

# shellcheck disable=SC2317,SC2329
dig_norec() {
	dig_query +norec +notcp +dnssec +adflag "$@"
}

# Capture stdout+stderr without tripping set -e.
dig_capture() {
	_out=$1
	shift
	if _buf=$("$@" 2>&1)
	then
		eval "${_out}=\"\${_buf}\""
		return 0
	else
		_rc=$?
		eval "${_out}=\"\${_buf}\""
		return "${_rc}"
	fi
}

dig_header_status() {
	printf '%s\n' "$1" | awk '
		/status:/ {
			if (match($0, /status:[[:space:]]*[A-Z]+/)) {
				s = substr($0, RSTART, RLENGTH)
				sub(/status:[[:space:]]*/, "", s)
				print s
				exit
			}
		}
	'
}

dig_header_flags() {
	printf '%s\n' "$1" | awk '
		/flags:/ {
			if (match($0, /flags:[[:space:]]*[^;]*/)) {
				s = substr($0, RSTART, RLENGTH)
				sub(/flags:[[:space:]]*/, "", s)
				print s
				exit
			}
		}
	'
}

flags_has() {
	_flags=$1
	_tok=$2
	printf '%s\n' "${_flags}" | awk -v t="${_tok}" '
		{
			n = split($0, a, /[[:space:]]+/)
			found = 1
			for (i = 1; i <= n; i++) if (a[i] == t) found = 0
			exit found
		}
	'
}

dig_count_field() {
	_label=$1
	_text=$2
	printf '%s\n' "${_text}" | awk -v lab="${_label}" '
		{
			pat = lab ":[[:space:]]*[0-9]+"
			if (match($0, pat)) {
				s = substr($0, RSTART, RLENGTH)
				sub(/.*:[[:space:]]*/, "", s)
				print s
				exit
			}
		}
	'
}

section_has_type() {
	_text=$1
	_section=$2
	_type=$3
	printf '%s\n' "${_text}" | awk -v sec="${_section}" -v typ="${_type}" '
		BEGIN { insec = 0; found = 1 }
		$0 ~ (";; " sec " SECTION:") { insec = 1; next }
		/^;;/ { if (insec) insec = 0 }
		insec && $4 == typ { found = 0; exit }
		END { exit found }
	'
}

# ---------------------------------------------------------------------------
# docker helpers
# ---------------------------------------------------------------------------
container_ok() {
	docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -qx true
}

ctr() {
	docker exec "${CONTAINER_NAME}" "$@"
}

container_ip() {
	docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
		"${CONTAINER_NAME}"
}

# Busybox ps inside the image. Prints USER, PID, ARGS (or COMMAND).
ctr_ps() {
	ctr ps w 2>/dev/null || ctr ps aux
}

# Read one /proc field for the first process whose comm matches $1.
proc_field() {
	_comm=$1
	_field=$2
	# $1/$2 are expanded inside the container by the inner shell,
	# from the arguments passed after the script text.
	# shellcheck disable=SC2016
	ctr sh -c '
		comm="$1"; field="$2"
		for d in /proc/[0-9]*
		do
			c=$(cat "$d/comm" 2>/dev/null) || continue
			if test "$c" = "$comm"
			then
				case "$field" in
				root) readlink -f "$d/root"; exit 0 ;;
				uid)
					# Uid: real effective saved fs
					awk "/^Uid:/{print \$2; exit}" "$d/status"
					exit 0
					;;
				limits)
					cat "$d/limits"
					exit 0
					;;
				cmdline)
					tr "\0" " " < "$d/cmdline"
					printf "\n"
					exit 0
					;;
				esac
			fi
		done
		exit 1
	' sh "${_comm}" "${_field}"
}

wait_for_cmd() {
	_secs=$1
	_what=$2
	shift 2
	_n=0
	while test "${_n}" -lt "${_secs}"
	do
		if "$@" >/dev/null 2>&1
		then
			return 0
		fi
		_n=$((_n + 1))
		sleep 1
	done
	printf 'timed out after %ss waiting for %s\n' "${_secs}" "${_what}" >&2
	return 1
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
need_cmd dig
need_cmd curl
need_cmd awk

if test -z "${DNS_HOST}"
then
	need_cmd docker
	if ! container_ok
	then
		printf 'ERROR  container %s is not running\n' "${CONTAINER_NAME}" >&2
		exit 2
	fi
	DNS_HOST=$(container_ip)
	if test -z "${DNS_HOST}"
	then
		printf 'ERROR  could not read IP of %s\n' "${CONTAINER_NAME}" >&2
		exit 2
	fi
	printf 'Using container %s at %s:%s\n' "${CONTAINER_NAME}" "${DNS_HOST}" "${DNS_PORT}"
else
	printf 'Using DNS_HOST %s:%s\n' "${DNS_HOST}" "${DNS_PORT}"
fi

# ---------------------------------------------------------------------------
# Container still running, named-checkconf, processes, chroot, ulimit
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && container_ok
then
	if wait_for_cmd 60 "named-checkconf config" \
		ctr test -f /run/named/etc/bind/named.conf
	then
		if ctr named-checkconf -t /run/named
		then
			pass "named-checkconf -t /run/named"
		else
			fail "named-checkconf -t /run/named"
		fi
	else
		fail "named config did not appear under /run/named within 60s"
	fi

	# Give init time to spawn the rest of the supervised processes.
	wait_for_cmd 30 "named process" ctr sh -c "ps w | grep -v grep | grep -q '/usr/sbin/named'" || true
	ps_out=$(ctr_ps) || ps_out=

	printf '%s\n' "${ps_out}" | sed 's/^/  ps: /'

	if printf '%s\n' "${ps_out}" | grep -E -q 'named'
	then
		pass "named process is running"
	else
		fail "named process is not running"
	fi
	if printf '%s\n' "${ps_out}" | grep -E -q 'root_proxy'
	then
		pass "root_proxy process is running"
	else
		fail "root_proxy process is not running"
	fi
	if printf '%s\n' "${ps_out}" | grep -E -q 'dnsdist'
	then
		pass "dnsdist process is running"
	else
		fail "dnsdist process is not running"
	fi
	if printf '%s\n' "${ps_out}" | grep -E -q 'haproxy'
	then
		pass "haproxy process is running"
	else
		fail "haproxy process is not running"
	fi
	if printf '%s\n' "${ps_out}" | grep -E -q 'bind_exporter|prometheus-bind'
	then
		pass "bind_exporter process is running"
	else
		fail "bind_exporter process is not running"
	fi

	named_uid=$(proc_field named uid || true)
	if test -n "${named_uid}" && test "${named_uid}" != 0
	then
		pass "named runs unprivileged (uid ${named_uid})"
	else
		fail "named is running as root or uid could not be read (${named_uid:-unset})"
	fi

	named_root=$(proc_field named root || true)
	named_cmd=$(proc_field named cmdline || true)
	printf '  named root=%s cmdline=%s\n' "${named_root}" "${named_cmd}"
	if printf '%s\n' "${named_root}" "${named_cmd}" | grep -q '/run/named'
	then
		pass "named is chrooted to /run/named"
	else
		fail "named chroot is not /run/named (root=${named_root})"
	fi

	proxy_uid=$(proc_field root_proxy uid || true)
	if test -n "${proxy_uid}" && test "${proxy_uid}" != 0
	then
		pass "root_proxy runs unprivileged (uid ${proxy_uid}, expected daemon)"
	else
		fail "root_proxy is running as root or uid could not be read (${proxy_uid:-unset})"
	fi

	haproxy_uid=$(proc_field haproxy uid || true)
	if test -n "${haproxy_uid}" && test "${haproxy_uid}" != 0
	then
		pass "haproxy runs unprivileged (uid ${haproxy_uid})"
	else
		fail "haproxy is running as root or uid could not be read (${haproxy_uid:-unset})"
	fi
	haproxy_root=$(proc_field haproxy root || true)
	printf '  haproxy root=%s\n' "${haproxy_root}"
	case "${haproxy_root}" in
	*/var/lib/haproxy*)
		pass "haproxy is chrooted to /var/lib/haproxy"
		;;
	*)
		# The chroot is in haproxy.cfg even if /proc/PID/root still
		# looks like / because some builds drop after opening files.
		if ctr grep -q 'chroot /var/lib/haproxy' /usr/local/etc/haproxy.cfg
		then
			warn "haproxy /proc/root is ${haproxy_root:-unset}, but config requests chroot /var/lib/haproxy"
		else
			fail "haproxy chroot could not be confirmed (root=${haproxy_root})"
		fi
		;;
	esac

	dnsdist_uid=$(proc_field dnsdist uid || true)
	if test -n "${dnsdist_uid}" && test "${dnsdist_uid}" != 0
	then
		pass "dnsdist runs unprivileged (uid ${dnsdist_uid})"
	elif test -n "${dnsdist_uid}"
	then
		warn "dnsdist is running as root (start_dnsdist does not drop privileges)"
	else
		warn "dnsdist uid could not be read"
	fi

	exporter_uid=$(proc_field bind_exporter uid || true)
	if test -z "${exporter_uid}"
	then
		# Alpine package may use a shorter comm.
		exporter_uid=$(proc_field prometheus-bind-exporter uid || true)
	fi
	if test -n "${exporter_uid}" && test "${exporter_uid}" != 0
	then
		pass "bind_exporter runs unprivileged (uid ${exporter_uid})"
	elif test -n "${exporter_uid}"
	then
		warn "bind_exporter is running as root (start_exporter does not drop privileges)"
	else
		warn "bind_exporter uid could not be read"
	fi

	named_limits=$(proc_field named limits || true)
	nofile=$(printf '%s\n' "${named_limits}" | awk '
		/Max open files/ { print $4; exit }
	')
	if test -n "${nofile}" && test "${nofile}" -ge 15000 2>/dev/null
	then
		pass "named Max open files is ${nofile} (>= 15000)"
	else
		fail "named Max open files is ${nofile:-unset}, expected >= 15000"
	fi
else
	skip "process, chroot, named-checkconf and ulimit checks (no running container)"
fi

# ---------------------------------------------------------------------------
# Wait for the ICANN root zone to load (rd=0 SOA for .)
# ---------------------------------------------------------------------------
printf 'Waiting up to %ss for the root zone to load...\n' "${WAIT_FOR_ZONE}"
zone_ready=0
n=0
while test "${n}" -lt "${WAIT_FOR_ZONE}"
do
	if out=$(dig_norec . SOA 2>/dev/null)
	then
		st=$(dig_header_status "${out}")
		ans=$(dig_count_field ANSWER "${out}")
		if test "${st}" = "NOERROR" && test "${ans:-0}" -ge 1
		then
			zone_ready=1
			break
		fi
	fi
	n=$((n + 1))
	sleep 1
done

if test "${zone_ready}" = 1
then
	pass "root zone loaded after ${n}s (rd=0 . SOA is NOERROR with an answer)"
else
	fail "root zone did not load within ${WAIT_FOR_ZONE}s"
	# Remaining DNS checks will likely fail; still run them for the log.
fi

# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
curl_ok() {
	_url=$1
	shift
	curl -fsS --max-time 5 "$@" "${_url}"
}

if mets=$(curl_ok "http://${DNS_HOST}:9119/metrics")
then
	if printf '%s\n' "${mets}" | grep -q '^bind_'
	then
		pass "BIND exporter on :9119/metrics serves bind_ metrics"
	else
		fail "BIND exporter on :9119/metrics responded but had no bind_ metrics"
	fi
else
	fail "BIND exporter on :9119/metrics did not respond"
fi

if mets=$(curl_ok "http://${DNS_HOST}:8405/metrics")
then
	if printf '%s\n' "${mets}" | grep -Ei -q 'haproxy_|# TYPE'
	then
		pass "HAProxy prometheus exporter on :8405 serves metrics"
	else
		fail "HAProxy :8405 responded but did not look like prometheus metrics"
	fi
else
	fail "HAProxy prometheus exporter on :8405 did not respond"
fi

# dnsdist metrics are enabled in CI with DNSDIST_STATS_KEY/ACL.
if mets=$(curl_ok "http://${DNS_HOST}:8083/metrics" -H "X-API-Key: stats") \
	|| mets=$(curl_ok "http://${DNS_HOST}:8083/metrics" -u "stats:stats")
then
	if printf '%s\n' "${mets}" | grep -Ei -q 'dnsdist_|pdns_dnsdist'
	then
		pass "dnsdist metrics on :8083/metrics responded"
	else
		fail "dnsdist :8083/metrics responded but had no dnsdist metrics"
	fi
else
	fail "dnsdist metrics on :8083/metrics did not respond (needs DNSDIST_STATS_KEY and DNSDIST_STATS_ACL)"
fi

# ---------------------------------------------------------------------------
# Logs: no setrlimit warnings
# SYSLOG_STDOUT=Y sends syslog to container stdout. named itself logs
# at severity error only, so a warning-level setrlimit message might
# never appear; the ulimit check above is the stronger guard.
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && container_ok
then
	logs=$(docker logs "${CONTAINER_NAME}" 2>&1 || true)
	if printf '%s\n' "${logs}" | grep -Ei -q 'setrlimit'
	then
		fail "container logs contain a setrlimit warning"
		printf '%s\n' "${logs}" | grep -Ei 'setrlimit' | sed 's/^/  /'
	else
		pass "container logs have no setrlimit warnings"
	fi
else
	skip "setrlimit log check (no running container)"
fi

# ---------------------------------------------------------------------------
# Live ICANN tests
# ---------------------------------------------------------------------------
# rd=1 google.com: NOERROR with an answer.
if dig_capture out dig_rec google.com A
then
	st=$(dig_header_status "${out}")
	ans=$(dig_count_field ANSWER "${out}")
	if test "${st}" = "NOERROR" && test "${ans:-0}" -ge 1
	then
		pass "rd=1 google.com A is NOERROR with an answer (ANSWER=${ans})"
	else
		fail "rd=1 google.com A expected NOERROR with an answer, got status=${st} ANSWER=${ans:-0}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	fi
else
	fail "rd=1 google.com A query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

# dnssec-validation is deliberately off: an ICANN-style validator
# cannot validate Handshake names, so validation is left to the
# client or a downstream validating resolver. +dnssec still asks
# for RRSIGs (the DO bit). The ad flag must not be set.
# google.com is not DNSSEC-signed, so this query checks AD only.
if dig_capture out dig_rec google.com A
then
	st=$(dig_header_status "${out}")
	flags=$(dig_header_flags "${out}")
	if test "${st}" != "NOERROR"
	then
		fail "rd=1 google.com A +dnssec +adflag expected NOERROR, got status=${st} flags=${flags}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	elif flags_has "${flags}" ad
	then
		fail "rd=1 google.com A +dnssec +adflag must not set the ad flag (validation is left to the client); flags=${flags}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	else
		pass "rd=1 google.com A +dnssec +adflag does not set the ad flag (flags: ${flags})"
	fi
else
	fail "rd=1 google.com A +dnssec +adflag query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

# google.com has no DNSSEC signatures. isc.org is signed, so a
# recursive query with the DO bit must still return RRSIGs even
# though validation is off.
if dig_capture out dig_rec isc.org A
then
	st=$(dig_header_status "${out}")
	if test "${st}" != "NOERROR"
	then
		fail "rd=1 isc.org A +dnssec expected NOERROR, got status=${st}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	elif section_has_type "${out}" ANSWER RRSIG
	then
		pass "rd=1 isc.org A +dnssec returns RRSIGs in the answer"
	else
		fail "rd=1 isc.org A +dnssec expected RRSIGs in the answer (DO bit should still be honoured)"
		printf '%s\n' "${out}" | sed 's/^/  /'
	fi
else
	fail "rd=1 isc.org A +dnssec query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

# rd=0 behaviour as designed for this resolver (authoritative root,
# not a recursive answer):
#   . SOA     — NOERROR, SOA in the answer, aa
#   com. NS   — referral: NOERROR, empty answer, NS in AUTHORITY.
#               BIND treats the delegation as a zone cut, so the parent
#               does not return those NS records in the answer section.
#   google.com A — referral: NOERROR, no A in ANSWER, NS in AUTHORITY
if dig_capture out dig_norec . SOA
then
	st=$(dig_header_status "${out}")
	flags=$(dig_header_flags "${out}")
	ans=$(dig_count_field ANSWER "${out}")
	if test "${st}" = "NOERROR" && test "${ans:-0}" -ge 1 && flags_has "${flags}" aa
	then
		pass "rd=0 . SOA is NOERROR, authoritative, with an answer"
	else
		fail "rd=0 . SOA expected NOERROR+aa with an answer, got status=${st} flags=${flags} ANSWER=${ans:-0}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	fi
else
	fail "rd=0 . SOA query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

if dig_capture out dig_norec com. NS
then
	st=$(dig_header_status "${out}")
	ans=$(dig_count_field ANSWER "${out}")
	if test "${st}" = "NOERROR" \
		&& test "${ans:-0}" -eq 0 \
		&& section_has_type "${out}" AUTHORITY NS \
		&& ! section_has_type "${out}" ANSWER NS
	then
		pass "rd=0 com. NS is a referral (NOERROR, no NS in ANSWER, NS in AUTHORITY)"
	else
		fail "rd=0 com. NS expected a referral, got status=${st} ANSWER=${ans:-0}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	fi
else
	fail "rd=0 com. NS query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

if dig_capture out dig_norec google.com A
then
	st=$(dig_header_status "${out}")
	ans=$(dig_count_field ANSWER "${out}")
	if test "${st}" = "NOERROR" \
		&& test "${ans:-0}" -eq 0 \
		&& section_has_type "${out}" AUTHORITY NS \
		&& ! section_has_type "${out}" ANSWER A
	then
		pass "rd=0 google.com A is a referral (NOERROR, no A in ANSWER, NS in AUTHORITY)"
	else
		fail "rd=0 google.com A expected a referral, got status=${st} ANSWER=${ans:-0}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	fi
else
	fail "rd=0 google.com A query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

# ---------------------------------------------------------------------------
# Internal-root then external-root fallback:
# a made-up TLD must be NXDOMAIN, not SERVFAIL, on both rd=0 and rd=1.
# Path: dnsdist -> root_proxy -> local BIND root view (NXDOMAIN) ->
# HSD_MASTERS (f-root / c-root, also NXDOMAIN) -> client.
# If the second hop is missing or silent, rd=0 times out and rd=1
# typically SERVFAILs.
# ---------------------------------------------------------------------------
check_fake_nxdomain() {
	_rd=$1
	_fn=$2
	if dig_capture out "${_fn}" "${FAKE_TLD}" A
	then
		st=$(dig_header_status "${out}")
		if test "${st}" = "NXDOMAIN"
		then
			pass "${_rd} ${FAKE_TLD} A is NXDOMAIN (internal then external root fallback)"
		elif test "${st}" = "SERVFAIL"
		then
			fail "${_rd} ${FAKE_TLD} A returned SERVFAIL, expected NXDOMAIN (fallback path to HSD_MASTERS / ICANN root did not complete)"
			printf '%s\n' "${out}" | sed 's/^/  /'
		else
			fail "${_rd} ${FAKE_TLD} A expected NXDOMAIN, got status=${st}"
			printf '%s\n' "${out}" | sed 's/^/  /'
		fi
	else
		st=$(dig_header_status "${out}")
		if test "${st}" = "NXDOMAIN"
		then
			pass "${_rd} ${FAKE_TLD} A is NXDOMAIN (internal then external root fallback)"
		else
			fail "${_rd} ${FAKE_TLD} A did not complete (status=${st:-none}); expected NXDOMAIN, not a timeout or SERVFAIL"
			printf '%s\n' "${out}" | sed 's/^/  /'
		fi
	fi
}

check_fake_nxdomain "rd=0" dig_norec
check_fake_nxdomain "rd=1" dig_rec

# ---------------------------------------------------------------------------
# Synthetic auth zone (ci-auth.test) — not real is-this-you data
# ---------------------------------------------------------------------------
if dig_capture out dig_norec "${AUTH_ZONE}" A
then
	st=$(dig_header_status "${out}")
	if test "${st}" = "NOERROR" && printf '%s\n' "${out}" | grep -q "${AUTH_ADDR}"
	then
		pass "rd=0 ${AUTH_ZONE} A is NOERROR with synthetic address ${AUTH_ADDR}"
	else
		fail "rd=0 ${AUTH_ZONE} A expected NOERROR with ${AUTH_ADDR}, got status=${st}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	fi
else
	fail "rd=0 ${AUTH_ZONE} A query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

if dig_capture out dig_rec "${AUTH_ZONE}" A
then
	st=$(dig_header_status "${out}")
	if test "${st}" = "NOERROR" && printf '%s\n' "${out}" | grep -q "${AUTH_ADDR}"
	then
		pass "rd=1 ${AUTH_ZONE} A is NOERROR with synthetic address ${AUTH_ADDR}"
	else
		fail "rd=1 ${AUTH_ZONE} A expected NOERROR with ${AUTH_ADDR}, got status=${st}"
		printf '%s\n' "${out}" | sed 's/^/  /'
	fi
else
	fail "rd=1 ${AUTH_ZONE} A query failed to complete"
	printf '%s\n' "${out}" | sed 's/^/  /'
fi

# ---------------------------------------------------------------------------
# Skipped paths that need other services
# ---------------------------------------------------------------------------
skip "Handshake TLD resolution (needs an hsd node; HSD_MASTERS in CI is f-root/c-root so only ICANN names are served)"
skip ".eth resolution (needs ethereum-dns-gateway via ETH_MASTERS, which is unset in this CI)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d skipped, %d warnings\n' \
	"${passed}" "${failed}" "${skipped}" "${warned}"

if test "${failed}" -ne 0
then
	exit 1
fi
exit 0
