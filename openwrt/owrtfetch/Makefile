include $(TOPDIR)/rules.mk

PKG_NAME:=owrtfetch
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=António Mora <m00qek@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/owrtfetch
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Neofetch-like system summary for OpenWrt
  DEPENDS:=+ucode +ucode-mod-fs +ucode-mod-ubus
  PKGARCH:=all
endef

define Package/owrtfetch/description
  Prints the OpenWrt logo beside what a router is running on and doing:
  release, board, SoC and temperature, memory, disks, the addresses of each
  network, each SSID with its channel and clients, and DHCP leases; or all
  of it as JSON with --json.
endef

define Build/Compile
endef

define Package/owrtfetch/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/owrtfetch $(1)/usr/bin/owrtfetch
	$(INSTALL_DIR) $(1)/usr/share/ucode
	$(INSTALL_DATA) ./src/owrtfetch.uc $(1)/usr/share/ucode/owrtfetch.uc
endef

$(eval $(call BuildPackage,owrtfetch))
