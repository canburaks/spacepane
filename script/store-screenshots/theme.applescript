-- Finds a color scheme tile on the companion's Theme page and returns the screen point of its middle as "x y".
-- usage: osascript theme.applescript <scheme tile number>
-- Tiles are numbered in page order: the five light schemes first (Standard, GitHub Light, Solarized Light,
-- One Light, Paper), then the dark ones (Standard is 6, GitHub Dark 7). The tiles are the first buttons of the
-- page. Builds up to 1.0.0 (1) ignored an accessibility press on a tile (fixed 2026-10-12), so the caller
-- clicks the returned point with the mouse, which works on every build.
property counter : 0
property wanted : 0
property answer : ""

on find(e)
	if answer is not "" then return
	tell application "System Events"
		set r to ""
		try
			set r to role of e as text
		end try
		if r is "AXButton" then
			set counter to counter + 1
			if counter is wanted then
				set p to position of e
				set s to size of e
				set answer to (((item 1 of p) + (item 1 of s) / 2) as integer as text) & " " & (((item 2 of p) + (item 2 of s) / 2) as integer as text)
				return
			end if
		end if
		set children to {}
		try
			set children to UI elements of e
		end try
	end tell
	repeat with c in children
		my find(c)
		if answer is not "" then return
	end repeat
end find

on run argv
	set counter to 0
	set answer to ""
	set wanted to (item 1 of argv) as integer
	tell application "System Events" to tell process "SpacePane"
		set frontmost to true
		click menu item "Theme" of menu "View" of menu bar 1
		delay 0.8
		set content to first UI element of window 1
	end tell
	my find(content)
	return answer
end run
