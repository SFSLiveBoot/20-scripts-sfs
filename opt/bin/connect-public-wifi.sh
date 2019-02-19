#!/bin/sh

prompt() { local x; echo -n "$1: ${2:+[$2] }" >&2; read x; echo "${x:-$2}"; }
choose1() {
  case "$1" in
    *"
"*) echo "Available options: " >&2; echo "$1" | sed -e 's/^/  /' >&2; prompt "${2:-Your choice}";;
    "") prompt "$2" "$3";;
    *) echo "$1";;
  esac
}

set -e
(set -x; nmcli radio wifi on)
while test -z "$ssid";do
  (set -x; nmcli device wifi list)
  echo "Unique SSIDs:"
  nmcli -t -f ssid device wifi list | grep -v '^--$' | sort -u | sed -e 's/^/  /'
  ssid="$(prompt "SSID (enter for rescan)")"
done
: "${cname:=$(prompt "Connection name" "$ssid")}"
echo "Signal Freq      BSSID"
nmcli -m multiline -t -f ssid,signal,freq,bssid device wifi list | grep -A4 -Fx "SSID:$ssid" | grep -e SIGNAL -e FREQ -e BSSID | cut -f2- -d: | xargs -d'\n' printf " %d    %s  %s\n" | sort -n
: "${bssid:=$(prompt "BSSID")}"
(set -x; nmcli device)
: "${iface:=$(choose1 "$(nmcli -t -f type,device device | grep ^wifi: | cut -f2- -d:)" "WiFi interface")}"
test -n "$never_default" || case "$(prompt "Use as default route? [Y/n]")" in Y*|y*|"") ;; *) never_default=1;; esac
(set -x; nmcli connection add \
  type wifi \
  con-name "$cname" \
  cloned-mac random \
  ssid "$ssid" \
  ifname "$iface" \
  ipv4.dhcp-send-hostname false \
  autoconnect no \
  ${bssid:+wifi.bssid "$bssid"} \
  ${never_default:+ipv4.never-default yes ipv4.ignore-auto-dns yes ipv6.never-default yes ipv6.ignore-auto-dns yes})
(set -x; nmcli connection up "$cname")
mac="$(nmcli -t -f GENERAL.HWADDR device show "$iface" | cut -f2- -d:)"
echo "Fixating parameters (mac=$mac)"
(set -x; nmcli connection modify "$cname" cloned-mac "$mac")
