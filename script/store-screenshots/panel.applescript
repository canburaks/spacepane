-- Selects a file in the staged Finder window, opens Quick Look if needed, places the panel and picks a view
-- mode. usage: osascript panel.applescript <window name> <file name> <mode or ""> [x y width height]
on run argv
	set windowName to item 1 of argv
	set fileName to item 2 of argv
	set wantedMode to item 3 of argv
	set frame to {560, 230, 1040, 680}
	if (count of argv) is 7 then set frame to {(item 4 of argv) as integer, (item 5 of argv) as integer, (item 6 of argv) as integer, (item 7 of argv) as integer}
	tell application "Finder"
		set w to first Finder window whose name is windowName
		set index of w to 1
		select (item fileName of (target of w))
	end tell
	delay 0.6
	tell application "System Events" to tell process "Finder"
		if not (exists (first window whose subrole is "Quick Look")) then
			set frontmost to true
			delay 0.4
			click (first menu item of menu "File" of menu bar 1 whose name starts with "Quick Look")
			delay 1.5
		end if
		set q to first window whose subrole is "Quick Look"
		set position of q to {item 1 of frame, item 2 of frame}
		set size of q to {item 3 of frame, item 4 of frame}
		delay 1.0
		set modes to {}
		if exists radio group 1 of q then
			repeat with b in (radio buttons of radio group 1 of q)
				set end of modes to (description of b as text) & "=" & (value of b as text)
			end repeat
			if wantedMode is not "" then
				click (first radio button of radio group 1 of q whose description is wantedMode)
				delay 0.8
			end if
		end if
		set AppleScript's text item delimiters to " | "
		return "modes: " & (modes as text)
	end tell
end run
