#!/bin/bash
# Builds media/social-preview.png (1280x640), the image GitHub shows when the
# repo's link is shared: the lockup and tagline on the left, the README's hero
# (media/hero-themed-text.png) on the right, and the bar itself
# (media/bar.png) along the bottom edge. Upload it by hand in the repo's
# Settings > Social preview; GitHub has no API for it. Same layout as Sash's
# (github.com/cwilliams5/omarchy-sash), its sister project.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B="$HERE/../branding/crossbar"
hero=$(magick "$HERE/hero-themed-text.png" -resize 1344x png:- | base64 -w0)
bar=$(base64 -w0 "$HERE/bar.png")
lockup=$(rsvg-convert -w 720 "$B/lockup-dark.svg" | base64 -w0)
cat >"$HERE/social-preview.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1280" height="640" viewBox="0 0 1280 640" font-family="JetBrainsMono Nerd Font, Liberation Mono, monospace">
  <rect width="1280" height="640" fill="#2E3440"/>
  <image x="60" y="130" width="400" height="77" xlink:href="data:image/png;base64,$lockup"/>
  <text x="62" y="292" fill="#ECEFF4" font-size="31">A Windows-style taskbar</text>
  <text x="62" y="332" fill="#ECEFF4" font-size="31">for Omarchy</text>
  <text x="62" y="392" fill="#ECEFF4" fill-opacity="0.72" font-size="19">Start button, quick launch, this</text>
  <text x="62" y="420" fill="#ECEFF4" fill-opacity="0.72" font-size="19">workspace's windows, tray, show</text>
  <text x="62" y="448" fill="#ECEFF4" fill-opacity="0.72" font-size="19">desktop.</text>
  <rect x="62" y="486" width="56" height="6" rx="3" fill="#88C0D0"/>
  <defs><clipPath id="r"><rect x="556" y="74" width="672" height="448" rx="14"/></clipPath></defs>
  <rect x="550" y="68" width="684" height="460" rx="18" fill="#000" fill-opacity="0.35"/>
  <image x="556" y="74" width="672" height="448" preserveAspectRatio="xMidYMid slice" clip-path="url(#r)" xlink:href="data:image/png;base64,$hero"/>
  <rect x="556" y="74" width="672" height="448" rx="14" fill="none" stroke="#ECEFF4" stroke-opacity="0.18" stroke-width="2"/>
  <image x="0" y="598" width="1280" height="30" preserveAspectRatio="none" xlink:href="data:image/png;base64,$bar"/>
</svg>
SVG
rsvg-convert -w 1280 -h 640 -o "$HERE/social-preview.png" "$HERE/social-preview.svg"
rm "$HERE/social-preview.svg"
echo "Wrote $HERE/social-preview.png"
