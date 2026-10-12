-- Opens the demo folder in its own clean Finder window: list view, no sidebar, tab bar, path bar, status bar
-- or preview pane. usage: osascript stage.applescript <folder path>   (restore.applescript undoes it)
on tabCount(windowName)
	tell application "System Events" to tell process "Finder"
		try
			return count of (radio buttons of (first tab group of (first window whose name is windowName)))
		on error
			return 0
		end try
	end tell
end tabCount

on run argv
	set folderPath to item 1 of argv
	set priorID to missing value
	tell application "Finder"
		activate
		-- A new window joins the front window's tabs when the user prefers tabs. Remember that window so it
		-- can be put back exactly where it was once the new tab has a window of its own.
		try
			set priorID to id of front Finder window
			set priorBounds to bounds of front Finder window
		end try
		set harbor to (POSIX file folderPath as alias)
		set w to make new Finder window to harbor
		set windowName to name of w
		set current view of w to list view
		set toolbar visible of w to true
		set pathbar visible of w to false
		set statusbar visible of w to false
	end tell
	repeat 4 times
		delay 0.7
		if my tabCount(windowName) is less than 2 then exit repeat
		tell application "System Events" to tell process "Finder"
			set frontmost to true
			delay 0.3
			try
				click menu item "Move Tab to New Window" of menu "Window" of menu bar 1
			end try
		end tell
	end repeat
	if my tabCount(windowName) is greater than 1 then error "The demo folder is still a tab of another Finder window."
	tell application "Finder"
		if priorID is not missing value then
			try
				set bounds of (first Finder window whose id is priorID) to priorBounds
			end try
		end if
		set w to first Finder window whose name is windowName
		set index of w to 1
		set sidebar width of w to 0
		set bounds of w to {120, 110, 1140, 730}
	end tell
	delay 0.4
	tell application "System Events" to tell process "Finder"
		set frontmost to true
		delay 0.3
		repeat with n in {"Hide Preview", "Hide Tab Bar"}
			try
				click menu item (n as text) of menu "View" of menu bar 1
				delay 0.4
			end try
		end repeat
	end tell
	return windowName & " tabs " & (my tabCount(windowName))
end run
