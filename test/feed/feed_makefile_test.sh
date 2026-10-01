#!/bin/sh
# gen-feed-makefile.sh: the packages.ucode.dev Makefile for owrtfetch, and what it refuses.
# Runs offline on the host (make test-feed).

TOP=$(cd "$(dirname "$0")/../.." && pwd)
GEN=$TOP/devenv/scripts/gen-feed-makefile.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); }

check() {
	desc=$1
	shift
	if out=$("$@" 2>&1); then
		pass "$desc"
	else
		fail "$desc"
		[ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/     /'
	fi
}

# refuses PATTERN COMMAND...: fails, with PATTERN (a grep -E) in its stderr.
refuses() {
	pattern=$1
	shift
	err=$("$@" 2>&1 >/dev/null) && { echo "succeeded"; return 1; }
	printf '%s\n' "$err" | grep -Eq "$pattern" || { echo "got: $err"; return 1; }
}

HASH=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$TOP/openwrt/owrtfetch/Makefile")
gen() { sh "$GEN" "$@"; }

# The feed Makefile is the in-tree one plus the source lines, the license file
# and paths into the unpacked tarball, and nothing else.
feed_matches_tree() {
	gen --hash "$HASH" "$VERSION" > "$TMP/feed.mk" || return 1
	sed -e 's# \$(PKG_BUILD_DIR)/src/# ./src/#g' \
		-e 's# \$(PKG_BUILD_DIR)/files/# ./files/#g' "$TMP/feed.mk" \
		| grep -vE '^(PKG_SOURCE|PKG_SOURCE_URL|PKG_HASH|PKG_BUILD_DIR|PKG_LICENSE_FILES):=' > "$TMP/back.mk"
	# One blank line is added before the source lines.
	grep -c '' "$TMP/back.mk" | grep -qx "$(($(grep -c '' "$TOP/openwrt/owrtfetch/Makefile") + 1))" \
		|| { echo "line count"; return 1; }
	[ "$(awk 'NR == 6 && $0 == "" { next } { print }' "$TMP/back.mk")" = "$(cat "$TOP/openwrt/owrtfetch/Makefile")" ] \
		|| { echo "differs from the in-tree Makefile beyond the added lines and paths"; return 1; }
	grep -qx "PKG_HASH:=$HASH" "$TMP/feed.mk" || { echo "no PKG_HASH"; return 1; }
	grep -qx 'PKG_SOURCE_URL:=https://github.com/m00qek/owrtfetch/archive/refs/tags/' "$TMP/feed.mk" || { echo "no PKG_SOURCE_URL"; return 1; }
	grep -qx 'PKG_BUILD_DIR:=$(BUILD_DIR)/owrtfetch-$(PKG_VERSION)' "$TMP/feed.mk" || { echo "no PKG_BUILD_DIR"; return 1; }
	grep -qx 'PKG_LICENSE_FILES:=LICENSE' "$TMP/feed.mk" || { echo "no PKG_LICENSE_FILES"; return 1; }
}
check "the feed Makefile is the in-tree one plus the source lines and tarball paths" feed_matches_tree

# A source Makefile that differs from the in-tree one by SED_EXPR.
variant() {
	sed "$1" "$TOP/openwrt/owrtfetch/Makefile" > "$TMP/variant.mk"
}

check "a VERSION that is not the source's is refused" \
	refuses "source PKG_VERSION is '$VERSION', expected 9.9.9" gen --hash "$HASH" 9.9.9

variant 's/^PKG_RELEASE:=.*/&\nPKG_HASH:=skip/'
check "a source that already sets PKG_HASH is refused" \
	refuses "already sets PKG_HASH" gen --hash "$HASH" --source "$TMP/variant.mk" "$VERSION"

variant 's|^\t\$(INSTALL_DATA) \./src/owrtfetch\.uc .*|&\n\t$(CP) ./extra/thing $(1)/|'
check "a copy from a directory the generator does not rewrite is refused" \
	refuses "still use a path relative" gen --hash "$HASH" --source "$TMP/variant.mk" "$VERSION"

variant '/^\$(eval \$(call BuildPackage,owrtfetch))/d'
check "a package without its BuildPackage call is refused" \
	refuses "1 define Package/<name> blocks but 0 BuildPackage" gen --hash "$HASH" --source "$TMP/variant.mk" "$VERSION"

check "a bad hash is refused" refuses "64 lowercase hex" gen --hash abc "$VERSION"
check "a VERSION with a leading v is refused" refuses "no leading v" gen --hash "$HASH" "v$VERSION"

# A tarball shaped like GitHub's for the tag: everything under owrtfetch-<version>/.
tarball() {
	root=$TMP/tar/owrtfetch-$VERSION
	rm -rf "$TMP/tar"
	mkdir -p "$root/openwrt/owrtfetch"
	cp "$TOP/openwrt/owrtfetch/Makefile" "$root/openwrt/owrtfetch/"
	for d in "$@"; do
		mkdir -p "$(dirname "$root/$d")"
		cp -R "$TOP/$d" "$root/$d"
	done
	(cd "$TMP/tar" && tar -czf "$TMP/v$VERSION.tar.gz" "owrtfetch-$VERSION")
}

from_tarball_hashes_it() {
	tarball src files
	gen --tarball "$TMP/v$VERSION.tar.gz" -o "$TMP/out.mk" "$VERSION" || return 1
	sum=$(sha256sum "$TMP/v$VERSION.tar.gz" | cut -d' ' -f1)
	grep -qx "PKG_HASH:=$sum" "$TMP/out.mk" || { echo "PKG_HASH is not the tarball's sha256"; return 1; }
}
check "from a tarball, PKG_HASH is its sha256" from_tarball_hashes_it

no_output_on_failure() {
	tarball src
	rm -f "$TMP/out.mk"
	refuses "tarball lacks: files/usr/bin/owrtfetch" gen --tarball "$TMP/v$VERSION.tar.gz" -o "$TMP/out.mk" "$VERSION" || return 1
	[ ! -e "$TMP/out.mk" ] || { echo "wrote $TMP/out.mk anyway"; return 1; }
}
check "a tarball without the copied paths is refused, and nothing is written" no_output_on_failure

# The layer modules are copied with a glob; the check stands it for its directory.
without_layer_modules() {
	tarball src/owrtfetch.uc files
	refuses "tarball lacks: src/owrtfetch$" gen --tarball "$TMP/v$VERSION.tar.gz" -o "$TMP/out.mk" "$VERSION"
}
check "a tarball without the layer modules under src/owrtfetch/ is refused" without_layer_modules

exit $((failures > 0))
