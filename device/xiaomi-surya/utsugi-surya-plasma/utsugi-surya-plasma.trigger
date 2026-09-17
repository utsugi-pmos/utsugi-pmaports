#!/bin/sh
# New phones start the favourites bar with Firefox instead of Angelfish.
#
# The default comes from Plasma Mobile's look-and-feel, which writes it when the
# homescreen is created on the first login. apk puts that file back on every
# upgrade of plasma-mobile, and the upgrade touches this directory, so the
# trigger runs again. Firefox has to be there: a bar pointing at a browser that
# is not installed would show an empty slot. Phones set up before are handled
# by shell-defaults.
script=/usr/share/plasma/look-and-feel/org.kde.breeze.mobile/contents/plasmoidsetupscripts/org.kde.plasma.mobile.homescreen.folio.js

if [ -e /usr/share/applications/firefox.desktop ] && [ -e "$script" ] &&
	grep -q '"org.kde.angelfish.desktop"' "$script"; then
	sed -i 's/"org\.kde\.angelfish\.desktop"/"firefox.desktop"/' "$script"
fi
exit 0
