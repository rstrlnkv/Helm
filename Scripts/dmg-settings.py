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

# ((x, y), (width, height)) — the size the background was drawn for.
window_rect = ((200, 160), (640, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
# Centres, matching the two slots the background frames.
icon_locations = {app_name: (168, 178), "Applications": (472, 178)}

format = "UDZO"
compression_level = 9
