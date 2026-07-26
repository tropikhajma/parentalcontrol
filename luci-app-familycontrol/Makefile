# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Mobile-first family internet controls
LUCI_DEPENDS:=+luci-base +firewall4 +rpcd-mod-ucode +ucode-mod-uci +shadow-useradd
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.0
PKG_RELEASE:=4
PKG_LICENSE:=Apache-2.0

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
