-- Opens the outline rows of the Quick Look preview whose key matches an argument, bottom to top.
-- usage: osascript expand.applescript <key> [<key> ...]
on run argv
	tell application "System Events" to tell process "Finder"
		set q to first window whose subrole is "Quick Look"
		set o to first outline of (first scroll area of q)
		set opened to {}
		repeat with i from (count of rows of o) to 1 by -1
			set r to row i of o
			set label to ""
			try
				set label to (value of first static text of (first UI element of r)) as text
			end try
			if argv contains label then
				try
					set value of attribute "AXDisclosing" of r to true
					set end of opened to label
					delay 0.2
				end try
			end if
		end repeat
		set AppleScript's text item delimiters to ","
		return "opened: " & (opened as text)
	end tell
end run
