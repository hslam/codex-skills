# macOS Chrome Print Reference

## Example Coordinates

These coordinates are examples from one Retina macOS desktop. `cliclick` uses logical points, while screenshots may be Retina pixels. Re-measure on a new display, after moving windows, or after changing display scaling.

Example working coordinates when the Chrome print preview window is at `pos=335,122 size=1320,871`:

- Chrome print preview blue Save: `m:1582,949 w:500 dd:. w:300 du:.`
- macOS Save dialog Save button: `c:1118,612`
- Go to folder result row: `dc:991,527`

Coordinates may need adjustment if windows are moved or display scaling changes. Use:

```bash
cliclick p
screencapture -x /tmp/state.png
```

## Fragile Parts

Chrome print preview's blue Save is drawn inside Chrome. AppleScript often cannot see it in the accessibility tree. Use `cliclick` slow down/up instead of `click`.

The macOS Save dialog may remember the previous folder. If it is already in the desired folder, only type the file name and click Save. If not:

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
