#!/bin/sh

set -eu

: "${dpkg_status:=/var/lib/dpkg/status}"
: "${dpkg_arch:=/var/lib/dpkg/arch}"
: "${dpkg_info:=/var/lib/dpkg/info}"

pkglist="$(mktemp)"
on_exit() {
  rm -f "$pkglist"
}
trap on_exit EXIT INT

pkg_info() {
  awk -e '/^Package:/{ pkg=$2 }' -e '/^Architecture:/{ arch=$2 }' -e '/^$/{eol=1;print pkg ":" arch }' -e 'END{if(!eol) print pkg ":" arch}' "$@"
}

pkg_info "$dpkg_status" >"$pkglist"
archlist="$(cat "$dpkg_arch" | tr "\n" ":")"

for ctrl in $(find "$dpkg_info" -name "*.control"); do 
  pkg="$(pkg_info "$ctrl")"
  arch="${pkg#*:}"
  test "$arch" = "all" || case ":$archlist:" in *:"$arch":*) ;; *)
    echo "Adding arch $arch"
    echo "$arch" >>"$dpkg_arch"
    archlist="$archlist:$arch"
  ;; esac
  grep -qFx "$pkg" "$pkglist" || {
    echo "Adding $pkg"
    sed '/^Package:/a Status: install ok installed' "$ctrl" >> "$dpkg_status"
    echo >>"$dpkg_status"
  }
done
