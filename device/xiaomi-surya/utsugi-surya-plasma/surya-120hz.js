// The POCO X3 NFC panel is 1080x2400 at 120 Hz and has no other mode. Gecko
// does not detect the refresh rate in this Wayland session and falls back to
// 60, half of what the screen gives.
//
// Measured on 2026-08-24, same test page, 10 s windows:
//
//                        fps     p50
//     default           59.7   16.7 ms
//     with this line   115.8    9.2 ms
//
// Ruled out: 'layout.frame_rate' at -1, the factory value, which is supposed to
// mean "follow vsync" and here means 60.
//
// THE 120 IS PINNED ON PURPOSE. The phone runs at 120 Hz always -- switching
// the panel to 60 is not wired up on this device -- so 120 is the true number
// and not a guess. If that ever changes, this file has to change with it: at
// 60 Hz with this preference at 120, Gecko paints twice per displayed frame
// and spends battery on frames nobody sees.
pref("layout.frame_rate", 120);
