#!/bin/sh

# Update and show automatically launchers from .config/gnome-pie/auto-slices

pie_id=999
pie_name="AutoPie"
pie_key="<Control><Alt>s"
pie_icon="category-show-all"

conf="$HOME/.config/gnome-pie/pies.conf"
auto_slices="$HOME/.config/gnome-pie/auto-slices"

test -e "$conf" || exit 0

if pie_pid=$(ps h -o pid -C gnome-pie);then kill $pie_pid; fi

pie="/pies/pie[@id='$pie_id']"

tmp="$(mktemp)"
tmp2="$(mktemp)"

xmlstarlet ed -d "$pie" <"$conf" |
  xmlstarlet ed -s /pies -t elem -n pie -v "" |
  xmlstarlet ed -s "/pies/pie[last()]" -t attr -n id -v "$pie_id" |
  xmlstarlet ed -s "$pie" -t attr -n name -v "$pie_name"  |
  xmlstarlet ed -s "$pie" -t attr -n hotkey -v "[centered]$pie_key" |
  xmlstarlet ed -s "$pie" -t attr -n icon -v "$pie_icon" >"$tmp"

for f in "$auto_slices"/*.desktop;do
  test -e "$f" || continue
  name="$(grep -o "^Name=.*" "$f" | cut -f2- -d=)"
  icon="$(grep -o "^Icon=.*" "$f" | cut -f2- -d=)"
  command="$(grep -o "^Exec=.*" "$f" | cut -f2- -d=)"
  show_slice="$pie_id"
  cat "$tmp" |
    xmlstarlet ed -s "$pie" -t elem -n slice -v "" |
    xmlstarlet ed -s "$pie/slice[last()]" -t attr -n type -v app |
    xmlstarlet ed -s "$pie/slice[last()]" -t attr -n name -v "$name" |
    xmlstarlet ed -s "$pie/slice[last()]" -t attr -n command -v "$command" |
    xmlstarlet ed -s "$pie/slice[last()]" -t attr -n icon -v "$icon" >"$tmp2"

  cat "$tmp2" > "$tmp"
done

cat < "$tmp" >"$conf"
rm -f "$tmp" "$tmp2"

( sleep 1
  gnome-pie ${show_slice:+-o $show_slice} &
  sleep 1
  test -z "$show_slice" || notify-send -a Startup-menu -t 30 -i "$pie_icon" "Press $pie_key to show start menu pie again"
) &
