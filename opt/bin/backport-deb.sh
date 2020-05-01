#!/bin/sh

set -e

: "${source_repo:=http://cdn.debian.net/debian testing main contrib non-free}"
: "${deb_build_dir:=/usr/src/deb}"
: "${packages:=$deb_build_dir/./Packages}"
: "${list_dir:=/etc/apt/sources.list.d}"
: "${sources_list:=$list_dir/build-sources.list}"
: "${built_list:=$list_dir/usr-src-deb.list}"

echo "deb-src $source_repo" >"$sources_list"
( set -x; exec apt-get update )
mkdir -p "$deb_build_dir"
cd "$deb_build_dir"

echo "deb [trusted=yes] file://$deb_build_dir ./" >"$built_list"
deb_build_lst_name="$(echo "$packages" | tr / _)"
touch "$packages"
test -L "/var/lib/apt/lists/$deb_build_lst_name" ||
  ln -vfs "$packages" "/var/lib/apt/lists/$deb_build_lst_name"

for pkg_name;do
  ( set -x; exec apt-get -y build-dep "$pkg_name" )
  ( set -x; exec apt-get -y source --compile "$pkg_name" )
  dpkg-scanpackages --multiversion . >"$packages"

  if test -n "$build_i386";then
    ( set -x; exec apt-get -y install crossbuild-essential-i386 )
    ( set -x; exec apt-get -y build-dep -a i386 "$pkg_name" )

    pkg_src_dir="$(find "$deb_build_dir" -mindepth 1 -maxdepth 1 -type d -name "${pkg_name}-*" | sort -n | tail -1)"
    ( cd "$pkg_src_dir"; set -x; exec dpkg-buildpackage -a i386 -b -uc )
    dpkg-scanpackages --multiversion . >"$packages"
  fi
done
