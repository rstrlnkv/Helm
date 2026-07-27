# How the disk image window is laid out.
#
# dmgbuild writes the .DS_Store itself rather than asking Finder to. That is the
# whole reason it is here: on macOS 26 Finder accepts the window's view options
# over AppleScript, reports them back correctly when asked, and then draws the
# default window anyway — checked twice, once with a hand-written script and
# once with Homebrew's create-dmg, which does the same dance.
#
# The numbers here and the ones in Scripts/design/make-dmg-background.swift are
# the same layout seen from two sides; change one and change the other.
import os

application = os.environ["HELM_APP"]
app_name = os.path.basename(application)

files = [application]
symlinks = {"Applications": "/Applications"}

# The volume's own icon, so a mounted Helm is a Helm and not a blank disk.
icon = os.environ["HELM_VOLUME_ICON"]

background = os.environ["HELM_BACKGROUND"]

# ((x, y), (width, height)). The height is the *window's*, and Finder counts the
# title bar in it — so the drawn background is 380 tall and the window is asked
# for 380 plus the bar, or the bottom of the artwork is cut off. Checked on the
# mounted image, where the DEV capsule sitting 24 pt off the bottom edge is the
# thing that goes missing first.
background_height = 380
title_bar = 28
window_rect = ((200, 160), (640, background_height + title_bar))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
# Finder has no way to turn the names off, so they are shrunk to the smallest
# value the .DS_Store will carry. Whether Finder honours it or clamps it back
# is checked on the mounted image, not assumed.
text_size = 10.0
# Centres, matching the two slots the background frames.
icon_locations = {app_name: (168, 178), "Applications": (472, 178)}

format = "UDZO"
compression_level = 9
