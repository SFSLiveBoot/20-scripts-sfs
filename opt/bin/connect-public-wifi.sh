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
run() { (set -x; "$@"); }

set -e
run nmcli radio wifi on
while test -z "$ssid";do
  run nmcli device wifi list
  echo "Unique SSIDs:"
  nmcli -t -f ssid device wifi list | grep -v '^--$' | sort -u | sed -e 's/^/  /'
  ssid="$(prompt "SSID (enter for rescan)")"
done
: "${cname:=$(prompt "Connection name" "$ssid")}"
if nmcli -t -f connection.type connection show "$cname";then op="modify"; else op="add"; fi
echo "Signal Freq      BSSID              Security"
nmcli -m multiline -t -f ssid,signal,freq,bssid,security device wifi list | grep -A5 -Fx "SSID:$ssid" | grep -e SIGNAL -e FREQ -e BSSID -e SECURITY | cut -f2- -d: | xargs -d'\n' printf " %d    %s  %s  %s\n" | sort -n
: "${bssid:=$(prompt "BSSID")}"
test -z "$bssid" || : "${security:=$(nmcli -m multiline -t -f bssid,security device wifi list | grep -A1 -Fx "BSSID:$bssid" | grep ^SECURITY: | sort -u | cut -f2 -d:)}"
case " $security " in
  *" WPA1 "*|*" WPA2 "*)
  : "${key_mgmt:=wpa-psk}"
  : "${wpa_psk:=$(prompt "Pre-shared key")}"
  ;;
  "  ") echo "WARNING: no link-level security possible" >&2;;
  *) echo "WARNING: Unhandled security method: '$security'" >&2 ;;
esac
test -n "$never_default" || case "$(prompt "Use as default route? [Y/n]")" in Y*|y*|"") ;; *) never_default=1;; esac
run nmcli connection $op \
  type wifi \
  con-name "$cname" \
  cloned-mac random \
  ssid "$ssid" \
  ifname "*" \
  ipv4.dhcp-send-hostname false \
  autoconnect no \
  ${bssid:+wifi.bssid "$bssid"} \
  ${never_default:+ipv4.never-default yes ipv4.ignore-auto-dns yes ipv6.never-default yes ipv6.ignore-auto-dns yes} \
  ${key_mgmt:+wifi-sec.key-mgmt $key_mgmt} ${wpa_psk:+wifi-sec.psk "$wpa_psk"}
run nmcli connection up "$cname"
: "${iface:=$(choose1 "$(run nmcli -t -f GENERAL.DEVICES connection show "$cname" | cut -f2- -d:)" "WiFi interface")}"
mac="$(run nmcli -t -f GENERAL.HWADDR device show "$iface" | cut -f2- -d:)"
echo "Fixating parameters (mac=$mac)"
run nmcli connection modify "$cname" cloned-mac "$mac"
