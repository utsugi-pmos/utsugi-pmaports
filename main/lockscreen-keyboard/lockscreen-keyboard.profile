# The patched lock screen lives in /usr/share/lockscreen-keyboard/xdg-data, which
# has to be AHEAD of /usr/share in the environment KWin and plasmashell start
# with. Set here and not in environment.d for the reason keepalive found: the
# mobile session is started from a login shell and startplasma-wayland pushes
# that environment over the one environment.d built.
case ":${XDG_DATA_DIRS:-}:" in
	*:/usr/share/lockscreen-keyboard/xdg-data:*) ;;
	*) export XDG_DATA_DIRS="/usr/share/lockscreen-keyboard/xdg-data:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" ;;
esac
