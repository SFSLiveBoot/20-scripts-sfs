#!/bin/sh

: "${wifis:=$(for i in /sys/class/net/*;do test ! -d $i/wireless || { echo -n "$_s${i##*/}";_s=" ";};done)}"
: "${wifi:=$(echo "$wifis" | cut -f1 -d" ")}"
: "${wifi:=wlan0}"

: "${dnsmasq_cfg:=/etc/dnsmasq.d/ipset.conf}"
: "${fw_log:=/var/log/kernel.log}"

: "${dns_ipset:=direct-ip}"

export LANG=C.UTF-8

set -e

run() {
  if test "x$1" = "xexec";then
    shift
    set -x; exec "$@"
  else
    (set -x; "$@")
  fi
}

name2mac() {
  local name="$1" new_mac="" octet
  for octet in $(echo -n "$name" | md5sum | fold -w2 | head -6);do
    if test -z "$new_mac";then
      new_mac="$(printf "%02x" $((0x$octet&0xfe|2)))"
    else
      new_mac="$new_mac:$octet"
    fi
  done
  echo "$new_mac"
}

do_command() {
  local cmd="$1"
  shift
  # CMDSTART
  case "$cmd" in
    quit|exit) # exit this program
      exit 0
      ;;
    reload) # reload this program
      run exec "$0"
      ;;
    addr) # show interface address info
      run ip addr
      ;;
    route) # show routing info
      case "$1" in
        dev) # dev <device>
          run ip route show table 0 dev "$2";;
        table) # table <tablename|nr>
          run ip route show table "$2";;
        get) # get <addr>
          run ip route get "$2";;
        *)
          run ip rule show
          echo "table main:"
          run ip route show table 0 | grep -vw table | sed -e 's/^/  /'
          for tbl in $(ip route show table 0 | grep -o ' table [^[:space:]]\+' | cut -f3 -d" " | sort -u);do
            echo "table $tbl:"
            ip route show table 0 | grep " table $tbl " | sed -e 's/^/  /'
          done
          ;;
      esac
     ;;
    ipset)
      case "$1" in
        add|del) # {add|del} <set> <value>
          run ipset -exist "$1" "$2" "$3"
          run ipset save "$2"
          ;;
        flush) # flush <set>
          run ipset flush "$2";;
        add-domain|del-domain)
          run ipset -exist create $dns_ipset hash:net
          case "$1" in
            add-domain)
              test -s "$dnsmasq_cfg" || echo "ipset=/$dns_ipset" >"$dnsmasq_cfg"
              run sed -e "/^ipset=.*\/$dns_ipset/s@=@=/$2@" -i "$dnsmasq_cfg";;
            del-domain)
              run sed -e "/^ipset=.*\/$dns_ipset/s@$2/@@" -i "$dnsmasq_cfg";;
          esac
          run grep '^ipset=' "$dnsmasq_cfg"
          run systemctl restart dnsmasq
        ;;
        *)
          run ipset save
          run iptables-save -c | grep -e "-m set" -e '^\*'
          run grep -r '^ipset=' "/etc/dnsmasq.d" || true
          ;;
      esac
      ;;
    wifi) # Show WiFi device info
      case "$1" in
        iface) # show/set primary WiFi interface
          test -z "$2" || wifi="$2"
          echo "wifi=$wifi"
          ;;
        save) # Save WiFi settings
          run wpa_cli "-i$wifi" save
          ;;
        *)
          echo "WiFi interfaces found: $wifis"
          run iw dev
          run wpa_cli "-i${wifi}" status || true
        ;;
      esac;;
    enable-network|disable-network|remove-network|list-networks|scan|scan-results|reassociate|set-network) # WiFi ops
      run wpa_cli "-i$wifi" "$(echo "$cmd" | tr - _)" "$@"
      ;;
    scan-dump) # dump last wifi scan results
      run iw dev "$wifi" scan dump -u;;
    add-network) # add-network <ssid> [<psk>|-] [<bssid>]
      nw_nr=$(wpa_cli "-i$wifi" add_network)
      echo "New network# $nw_nr"
      run wpa_cli "-i$wifi" set_network $nw_nr ssid "\"$1\""
      if test "x$2" = "x-";then
        run wpa_cli "-i$wifi" set_network $nw_nr key_mgmt NONE
      else
        psk="$(wpa_passphrase "$ssid" "$2" | grep '^[[:space:]]*psk=' | cut -f2 -d=)"
        run wpa_cli "-i$wifi" set_network $nw_nr psk "$psk"
      fi
      test -z "$3" ||
        run wpa_cli "-i$wifi" set_network $nw_nr bssid "$3"
      ;;
    rfkill) # RF kill-switch operations
      case "$1" in
        block)
          rfkill block "${2:-all}";;
        unblock)
          rfkill unblock "${2:-all}";;
        *) rfkill list;;
      esac
      ;;
    bridge) # show bridge information
      case "$1" in
        add) # bridge add <int0|ext0> <iface>
          run ip link set "$3" master "$2"
          run ip link set "$3" up
          run systemctl restart dnsmasq dhcpcd
          ;;
        *) run brctl show ;;
      esac
      ;;
    ping) # ping <host>
      run ping -c4 "$1";;
    dig|ipcalc)
      run $cmd "$@";;
    curl) # curl <url>
      run curl -v "$1";;
    whois) # whois <query> [<server>]
      run whois ${2+-h "$2"} "$1" | iconv -f iso-8859-1 ;;
    iptables)
      case "$1" in
        reload)
          run systemctl restart iptables;;
        nat|mangle|filter)
          run iptables-save -c -t "$1";;
        *) run iptables-save -c ;;
      esac;;
    rename-iface) # rename-iface <old> <new>
      wpa_pid="$(systemctl show "wpa_supplicant@$1" | grep ^ExecMainPID= | cut -f2 -d=)"
      test "x$wpa_pid" = "x0" || run systemctl stop "wpa_supplicant@$1"
      run ip link set "$1" down
      run ip link set "$1" name "$2"
      test "x$1" != "x$wifi" || wifi="$2"
      test "x$wpa_pid" = "x0" || {
        test -e "/etc/wpa_supplicant/wpa_supplicant-$2.conf" -o ! -e "/etc/wpa_supplicant/wpa_supplicant-$2.conf" ||
          run ln -s "wpa_supplicant-$1.conf" "/etc/wpa_supplicant/wpa_supplicant-$2.conf"
        run systemctl start "wpa_supplicant@$2"
      }
      ;;
    log)
      case "$1" in
        monitor) run exec tail -f "$fw_log";;
        *)
          run tail "$fw_log" || true
        ;;
      esac
      ;;
    dmesg)
      dmesg;;
    profile) # profile <name> [<interface>]
      iface="${2:-$wifi}"
      test -n "$1" && mac="$(name2mac "$1")" || mac="$(run ethtool -P "$iface" | sed -e 's/^Permanent address: //')"
      run ip link set "$iface" address "$mac"
      wpa_pid="$(systemctl show "wpa_supplicant@$iface" | grep ^ExecMainPID= | cut -f2 -d=)"
      test -z "$wpa_pid" -o "x$wpa_pid" = "x0" ||
        run systemctl restart "wpa_supplicant@$iface"
      test "x$(systemctl show dhcpcd | grep ^ExecMainPID= | cut -f2 -d=)" = "x0" ||
        run systemctl restart dhcpcd
      ;;
    poweroff|reboot) # reboot or power off this device
      run "$cmd" ;;
    svc) # system services
      case "$1" in
        reload) # reload service control daemon
          run systemctl daemon-reload;;
        enable|disable|stop|start|restart|status) # control a service
          run systemctl "$@" ;;
        "") run systemctl status "hostapd*" "wpa_supplicant*" "dhcpcd*" "dnsmasq*" "bluetooth*" "squid*" "NetworkManager*";;
      esac;;
    help|-h) # this help
      line1="$(grep -nw CMDSTART "$0" | head -1 | cut -f1 -d:)"
      line2="$(grep -nw CMDEND "$0" | head -1 | cut -f1 -d:)"
      echo "Available commands:"
      head -n"$line2" "$0" | tail -n+$line1 | grep '^ *[0-9a-z|_-]*)'
      ;;
    "") ;;
    *)
      echo "Invalid command: '$cmd'"
      ;;
  esac
  # CMDEND
}

if test -n "$1";then
    do_command "$@"
else
    while true;do
      echo -n "Command> "
      read cmd args
      set --
      while test -n "$args";do
        read arg1 args <<EOF
$args
EOF
        set -- "$@" "$arg1"
      done
      do_command "$cmd" "$@"
    done
fi
