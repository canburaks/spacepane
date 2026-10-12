-- Undoes stage.applescript: closes Quick Look and the demo window and shows the preview pane, path bar,
-- status bar and tab bar again. usage: osascript restore.applescript <window name>
on run argv
	set windowName to item 1 of argv
	tell application "Finder" to activate
	delay 0.4
	tell application "System Events" to tell process "Finder"
		set frontmost to true
		if exists (first window whose subrole is "Quick Look") then
			try
				click (first button of (first window whose subrole is "Quick Look") whose description is "close button")
			end try
			delay 0.5
		end if
	end tell
	tell application "Finder"
		try
			set w to first Finder window whose name is windowName
			set index of w to 1
			set pathbar visible of w to true
			set statusbar visible of w to true
		end try
	end tell
	delay 0.3
	tell application "System Events" to tell process "Finder"
		repeat with n in {"Show Preview", "Show Tab Bar"}
			try
				click menu item (n as text) of menu "View" of menu bar 1
				delay 0.3
			end try
		end repeat
	end tell
	tell application "Finder"
		try
			close (first Finder window whose name is windowName)
		end try
	end tell
end run
