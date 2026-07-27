# SPDX-License-Identifier: GPL-3.0-or-later

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Mobile-first family internet controls
LUCI_DEPENDS:=+luci-base +firewall4 +rpcd-mod-ucode +ucode-mod-uci +shadow-useradd +wget-ssl
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.0
PKG_RELEASE:=15
PKG_LICENSE:=GPL-3.0-or-later

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
