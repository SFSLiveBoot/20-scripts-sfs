#!/bin/sh

prompt() { local x m="$1" d="${2:-}"; echo -n "$m: ${d:+[$d] }" >&2; read -r x; echo "${x:-$d}"; }
choose1() {
  case "$1" in
    *"
"*) echo "Available options: " >&2; echo "$1" | sed -e 's/^/  /' >&2; prompt "${2:-Your choice}";;
    "") prompt "$2" "$3";;
    *) echo "$1";;
  esac
}
run() { (set -x; "$@"); }

set -eu

while test -n "${1+set}";do
case "$1" in
  --[a-zA-Z]*=*) eval "${1#--}"; shift;;
  *)
    echo "Usage: ${0##*/} [<--env_var=value..>]" >&2
    # shellcheck disable=2016
    echo "  Recognized vars: $(grep -o '\${\w\+:[+=]' "$0" | cut -c3- | cut -f1 -d: | grep -v '^[0-9]' | sort -u | tr \\n ' ')" >&2
    exit 1
  ;;
esac
done

: "${ssid:=}"
: "${never_default:=}"

run nmcli radio wifi on
while test -z "$ssid";do
  run nmcli device wifi list
  echo "Unique SSIDs:"
  nmcli -t -f ssid device wifi list | grep -v '^--$' | sort -u | sed -e 's/^/  /'
  ssid="$(prompt "SSID (enter for rescan)")"
done
: "${cname:=$(prompt "Connection name" "$(echo "$ssid" | tr "[[:upper:]] " "[[:lower:]]_")")}"
if nmcli -t -f connection.type connection show "$cname";then op="modify"; else op="add type wifi con-name"; fi
echo "Signal Freq      BSSID              Security"
LANG=C.UTF-8 nmcli -m multiline -t -f ssid,signal,freq,bssid,security device wifi list | grep -A5 -Fx "SSID:$ssid" | grep -e SIGNAL -e FREQ -e BSSID -e SECURITY | cut -f2- -d: | xargs -d'\n' printf " %d    %s  %s  %s\n" | sort -n
: "${bssid:=$(prompt "BSSID")}"
if test -z "$bssid";then
  : "${security:=$(LANG=C.UTF-8 nmcli -m multiline -t -f ssid,security device wifi list | grep -A1 -Fx "SSID:$ssid" | grep ^SECURITY: | sort -u | cut -f2 -d:)}"
else
  : "${security:=$(LANG=C.UTF-8 nmcli -m multiline -t -f bssid,security device wifi list | grep -A1 -Fx "BSSID:$bssid" | grep ^SECURITY: | sort -u | cut -f2 -d:)}"
fi
case " $security " in
  *" WPA3 "*)
  : "${key_mgmt:=sae}"
  : "${wpa_psk:=$(prompt "Pre-shared key")}"
  ;;
  *" WPA1 "*|*" WPA2 "*)
  : "${key_mgmt:=wpa-psk}"
  : "${wpa_psk:=$(prompt "Pre-shared key")}"
  ;;
  "  ") echo "WARNING: no link-level security possible" >&2;;
  *) echo "WARNING: Unhandled security method: '$security'" >&2 ;;
esac

test -n "${lxc+set}" || case "$(prompt "Create container for access? [Y/n]")" in Y*|y*|"") lxc="$cname";; esac

test -z "${lxc:-}" || {
  # create lxc for access
  : "${lxc_name:=$(prompt "LXC container name" "$lxc")}"
  test -n "${ignore_auto_dns+set}" || ignore_auto_dns=1
  : "${rt_table:=$(prompt "Routing table" "1234")}"
  : "${rt_rules:=$(prompt "Routing rules" "priority 1234 iif lxcbr0 lookup $rt_table")}"
}

test -n "$never_default" || case "$(prompt "Use as default route? [Y/n]")" in Y*|y*|"") ;; *) never_default=1;; esac
test -n "${ignore_auto_dns+set}" || ignore_auto_dns="${never_default:-}"

run nmcli connection $op "$cname" \
  cloned-mac random \
  ssid "$ssid" \
  ifname "*" \
  ipv4.dhcp-send-hostname false \
  autoconnect no \
  ${bssid:+wifi.bssid "$bssid"} \
  ${never_default:+ipv4.never-default yes ipv6.never-default yes} \
  ${ignore_auto_dns:+ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes} \
  ${key_mgmt:+wifi-sec.key-mgmt $key_mgmt} ${wpa_psk:+wifi-sec.psk "$wpa_psk"} \
  ${rt_table:+ipv4.route-table $rt_table} \
  ${rt_rules:+ipv4.routing-rules "$rt_rules"}
run nmcli connection up "$cname"
: "${iface:=$(choose1 "$(run nmcli -t -f GENERAL.DEVICES connection show "$cname" | cut -f2- -d:)" "WiFi interface")}"
mac="$(run nmcli -t -f GENERAL.HWADDR device show "$iface" | cut -f2- -d:)"
echo "Fixating parameters (mac=$mac)"
run nmcli connection modify "$cname" cloned-mac "$mac"

test -z "${lxc:-}" || test -d "/var/lib/lxc/$lxc_name" || {
  test -n "${dns_srv+set}" ||
    dns_srv="$(nmcli -t -f DHCP4.OPTION connection show "$cname" | grep :domain_name_servers | cut -f3- -d" ")"
  run sudo lxc-create -n "$lxc_name" -t public-wifi -- ${dns_srv:+$(for srv in $dns_srv; do echo --net-dns "$srv";done)}
  run sudo lxc-start -F -n "$lxc_name"
  echo "Run container again with: sudo lxc-start -F -n '$lxc_name'"
  echo "OR delete container with: sudo lxc-destroy -n '$lxc_name'"
}

test -z "$never_default" || {
  gw="$(run nmcli -t -f DHCP4.OPTION connection show "$cname" | sed -n '/:routers = /{s/.* = //;p;q}')"
  run grep -hv '^127\.' /etc/hosts "$HOME/.config/hosts" | grep '^[0-9]' || true
  while true; do
    echo -n "Destination to route via $gw: "
    read -r dest || true
    test -n "$dest" || break
    if run sudo ip route add "$dest" via "$gw";then
      add_routes="${add_routes:+$add_routes,}$dest $gw"
    fi
  done
  test -z "$add_routes" || run nmcli connection modify "$cname" ipv4.routes "$add_routes"
}
