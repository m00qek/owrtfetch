OPENWRT_ARCH    ?= x86_64
OPENWRT_VERSION ?= 25.12.5

TEST_IMAGE := owrtfetch-test:$(OPENWRT_ARCH)-$(OPENWRT_VERSION)
SDK_IMAGE  := ghcr.io/openwrt/sdk:$(OPENWRT_ARCH)-$(OPENWRT_VERSION)
PKG_DIR    := /builder/package/owrtfetch

.PHONY: test test-feed image package feed-makefile

test: image
	@docker run --rm --user $$(id -u):$$(id -g) --tmpfs /tmp:mode=1777 -v $(CURDIR):/owrtfetch $(TEST_IMAGE) \
		utest -c test/utest.config.uc $(if $(FILTER),-f '$(FILTER)') test/unit

# The feed Makefile generator's own tests; offline, on the host.
test-feed:
	@sh test/feed/feed_makefile_test.sh

image:
	@docker build -q -t $(TEST_IMAGE) --build-arg OPENWRT_ARCH=$(OPENWRT_ARCH) \
		--build-arg OPENWRT_VERSION=$(OPENWRT_VERSION) devenv >/dev/null

# fakeroot's faked closes every descriptor up to the open-file limit when it starts;
# where the daemon's limit is unbounded (about a billion) each start takes minutes.
package:
	@mkdir -p bin && chmod a+rwx bin
	docker run --rm --ulimit nofile=1024:524288 \
		-v $(CURDIR)/openwrt/owrtfetch/Makefile:$(PKG_DIR)/Makefile:ro \
		-v $(CURDIR)/src:$(PKG_DIR)/src:ro \
		-v $(CURDIR)/files:$(PKG_DIR)/files:ro \
		-v $(CURDIR)/bin:/artifacts \
		$(SDK_IMAGE) sh -c 'make defconfig >/dev/null && make package/owrtfetch/compile && \
			find bin -name "owrtfetch*" -exec cp {} /artifacts/ \;'

# The owrtfetch Makefile for the packages.ucode.dev feed, built from the v$(VERSION)
# release tarball: it downloads the tarball unless TARBALL=<path> or HASH=<sha256>
# is given. Writes to OUT, or to standard output.
feed-makefile:
	@sh devenv/scripts/gen-feed-makefile.sh \
		$(if $(TARBALL),--tarball '$(TARBALL)') \
		$(if $(HASH),--hash '$(HASH)') \
		$(if $(OUT),-o '$(OUT)') \
		'$(VERSION)'
