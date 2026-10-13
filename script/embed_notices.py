#!/usr/bin/env python3
"""Embed the notices every build carries when the product has no CAD helper (PREV_INCLUDE_CAD = NO).

The "Embed CAD worker" script phase runs script/embed_cad_worker.py when the setting is YES, which copies the
helper and both notice folders. With NO that phase runs this script instead: it copies the colour-scheme palette
notice, which the app's About page shows, and nothing else. No .build/cad directory is read.

The user-script sandbox allows only the files script/notices-inputs.xcfilelist reads and
script/notices-outputs.xcfilelist writes; script/validate_project.py keeps both lists equal to the folder's files.
"""
import os
from pathlib import Path
import shutil

root = Path(os.environ['SRCROOT'])
resources = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']
# (folder under ThirdPartyNotices, folder inside Resources); script/build_cad_worker.NOTICE_FOLDERS owns the pair.
for source, name in (('ColorSchemes', 'ColorSchemes-Notices'),):
    shutil.copytree(root / 'ThirdPartyNotices' / source, resources / name, dirs_exist_ok=True)
