# The patched task switcher lives in /usr/share/keepalive/xdg-data, which has to
# be AHEAD of /usr/share in the environment KWin starts with.
#
# environment.d alone never got it there. The mobile session is started by
# startplasmamobile, which sources /etc/profile; flatpak's profile script sets
# XDG_DATA_DIRS without our directory, and startplasma-wayland then pushes that
# environment into the systemd user manager over the one environment.d built.
# Measured on 2026-09-17: KWin ran with the stock effect, and every app on the
# always-alive list closed like any other.
case ":${XDG_DATA_DIRS:-}:" in
	*:/usr/share/keepalive/xdg-data:*) ;;
	*) export XDG_DATA_DIRS="/usr/share/keepalive/xdg-data:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" ;;
esac
