# macOS Chrome Print Reference

## Save Button Targeting

Chrome print preview does not always expose its blue Save button through the macOS Accessibility tree. Prefer this order:

1. Read the print window bounds from Accessibility and click the Save location relative to the lower-right corner.
2. Retry the relative click a few times because Chrome can render the button before it is ready to accept a click.
3. Try Accessibility by button label.
4. Use `--save-click X,Y` only when the automatic target misses.

`cliclick` uses logical screen coordinates. macOS screenshots may be physical pixels on Retina displays, so screenshot coordinates are not always the same numbers as click coordinates.

## Example Coordinates

These coordinates are examples from one Retina macOS desktop. Re-measure on a new display, after moving windows, or after changing display scaling.

Example working coordinates when the Chrome print preview window is at `pos=335,122 size=1320,871`:

- Chrome print preview blue Save: `m:1582,949 w:500 dd:. w:300 du:.`
- macOS Save dialog Save button: `c:1118,612`
- Go to folder result row: `dc:991,527`

The script should no longer need these coordinates when the window is moved. Use these commands only for debugging or a temporary `--save-click` override:

```bash
cliclick p
screencapture -x /tmp/state.png
```

## Fragile Parts

Chrome print preview's blue Save is drawn inside Chrome. AppleScript often cannot see it in the accessibility tree. The script therefore targets the button relative to the print window bounds and uses a slow `cliclick` down/up sequence instead of a plain click.

The macOS Save dialog is a native dialog and is usually visible to Accessibility. If the script cannot click its Save button by label, use this manual recovery:

1. Press `Cmd-Shift-G`.
2. Type the directory path.
3. Double-click the single result row.
4. Click Save.

Pressing Enter in the Go to folder result may not enter the directory reliably.

## Recovery

If stuck in a dialog, take a screenshot before guessing:

```bash
screencapture -x /tmp/chrome-print-state.png
```

List Chrome windows:

```bash
osascript -e 'tell application "System Events" to tell process "Google Chrome" to repeat with i from 1 to count of windows
set w to window i
set p to position of w
set s to size of w
log (i as text) & ": " & (name of w as text) & " pos=" & (item 1 of p as text) & "," & (item 2 of p as text) & " size=" & (item 1 of s as text) & "," & (item 2 of s as text)
end repeat' 2>&1
```

If a file name already exists, remove the target first or expect a replace confirmation.
