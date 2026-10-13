# Lightweight Mixbox login environment. Mixbox commands load their own full helper.
# Preserve native loader defaults; Entware programs use their own loader/runpath.
mbroot=$(/sbin/uci -c /etc/mixbox/mbdb -q get mixbox.main.path)
[ -n "$mbroot" ] || mbroot=/etc/mixbox
_sc_profilepath=$(/sbin/uci -c /etc/mixbox/mbdb -q get mixbox.main.profilepath)
appname=tools
uciname=profile
export PATH="${mbroot}/bin${_sc_profilepath}:$PATH:${mbroot}/bin"
# Older generated profiles forced stock libraries ahead of Entware libraries.
# Clear that known generated value, without replacing an explicit custom value.
case "${LD_LIBRARY_PATH:-}" in
 ""|/usr/lib:/lib|/usr/lib:/lib:*) unset LD_LIBRARY_PATH;;
esac
export TERM=xterm
alias ll='ls -l'
unset _sc_profilepath
