-- Zooms the Quick Look preview in with the app's own Command-plus shortcut. The zoom is temporary: a new
-- preview starts at actual size. The shortcut reaches the preview only when the panel has the keyboard, so the
-- script returns a point inside the preview for the caller to click first when asked with "point".
-- usage: osascript zoom.applescript point | osascript zoom.applescript <steps>
on run argv
	tell application "System Events" to tell process "Finder"
		set frontmost to true
		set q to first window whose subrole is "Quick Look"
		perform action "AXRaise" of q
		delay 0.3
		if (item 1 of argv) is "point" then
			set p to position of q
			set s to size of q
			-- The right margin of the content: inside the preview, clear of its buttons and copy controls.
			return (((item 1 of p) + (item 1 of s) * 0.9) as integer as text) & " " & (((item 2 of p) + (item 2 of s) * 0.55) as integer as text)
		end if
		repeat (item 1 of argv) as integer times
			keystroke "=" using command down
			delay 0.35
		end repeat
	end tell
end run
