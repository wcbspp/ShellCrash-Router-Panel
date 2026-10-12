# Lightweight Mixbox login environment. Mixbox commands load their own full helper.
# Keep the original PATH/library order; avoid WAN/ubus and repeated mbdb calls at login.
mbroot=$(/sbin/uci -c /etc/mixbox/mbdb -q get mixbox.main.path)
[ -n "$mbroot" ] || mbroot=/etc/mixbox
_sc_profilepath=$(/sbin/uci -c /etc/mixbox/mbdb -q get mixbox.main.profilepath)
_sc_libpath=$(/sbin/uci -c /etc/mixbox/mbdb -q get mixbox.main.libpath)
appname=tools
uciname=profile
export PATH="${mbroot}/bin${_sc_profilepath}:$PATH:${mbroot}/bin"
if [ -z "${LD_LIBRARY_PATH:-}" ];then
 export LD_LIBRARY_PATH="/usr/lib:/lib${_sc_libpath}"
else
 export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}${_sc_libpath}"
fi
export TERM=xterm
alias ll='ls -l'
unset _sc_profilepath _sc_libpath
