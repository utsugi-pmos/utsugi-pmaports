# Venus decodes VP9 from libvpx bit-exact but YouTube's VP9 corrupt on every
# inter frame (see mpv.conf). mpv.conf keeps mpv off it; GStreamer needs this,
# because gst-plugins-good registers v4l2vp9dec one rank ABOVE the software
# decoders and every GStreamer application would pick it on its own. Rank NONE
# leaves the element usable by name and out of autoplugging, so decodebin falls
# back to software. H.264 and HEVC are untouched.
#
# In /etc/profile.d and not only in environment.d: startplasmamobile sources
# /etc/profile and startplasma-wayland pushes that environment over the one
# environment.d built (the same trap keepalive fell into on 2026-09-17).
case ",${GST_PLUGIN_FEATURE_RANK:-}," in
	*,v4l2vp9dec:*) ;;
	*) export GST_PLUGIN_FEATURE_RANK="${GST_PLUGIN_FEATURE_RANK:+$GST_PLUGIN_FEATURE_RANK,}v4l2vp9dec:NONE" ;;
esac
