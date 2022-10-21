#!/bin/sh

: ${plist:=/etc/libccid_Info.plist}

plist_to_usbids() {
  xsltproc --nonet - "$1" <<EOF
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="text"/>
    <xsl:template match="/">
        <xsl:for-each select="//key[.='ifdVendorID']/following-sibling::array[1]/string">
            <xsl:variable name="position" select="count(preceding-sibling::*)+1" />
            <xsl:value-of select="substring(text(),3)" />:<xsl:value-of select="substring(parent::array/parent::dict/key[.='ifdProductID']/following-sibling::array[1]/string[position()=\$position]/text(),3)" />
            <xsl:text>&#10;</xsl:text>
        </xsl:for-each>
    </xsl:template>
</xsl:stylesheet>
EOF
}

plist_add() {
  local plist="$1" usb_id="$2" description="$3"
  local vendor_id="${usb_id%:*}"
  local product_id="${usb_id#*:}"
  xsltproc --nonet - "$plist" <<EOF
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml"/>
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="/plist/dict/array">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <xsl:choose>
        <xsl:when test="preceding-sibling::key[1][.='ifdVendorID']">
          <string><xsl:text>0x$vendor_id</xsl:text></string>
        </xsl:when>
          <xsl:when test="preceding-sibling::key[1][.='ifdProductID']">
          <string><xsl:text>0x$product_id</xsl:text></string>
        </xsl:when>
        <xsl:when test="preceding-sibling::key[1][.='ifdFriendlyName']">
          <string><xsl:text>$description</xsl:text></string>
        </xsl:when>
      </xsl:choose>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
EOF
}

set -e

test -n "$1" || {
  echo "This script will add an USB token with specific USB id to libccid token list" >&2
  echo "Usage: ${0##*/} <usb_id1> <description1> [<usb_id2> <description2>..]" >&2
  exit 1
}

while test -n "$1";do
  usb_id="$1"
  description="$2"
  shift 2
  plist_to_usbids "$plist" | grep -qiFx "$usb_id" || {
    echo "Adding $usb_id - $description"
    new_plist="$(mktemp "$plist.new.XXXXXX")"
    plist_add "$plist" "$usb_id" "$description" >$new_plist
    cat "$new_plist" >"$plist"
    rm -f "$new_plist"
  }
done
