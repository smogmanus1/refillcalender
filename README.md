# Refill Calendar

A small AutoHotkey v2 tool that tracks prescription refill dates and exports reminders to any calendar that imports `.ics` files (Outlook, Google Calendar, Apple Calendar).

**Reminder tool only. Not medical advice.** Always confirm fill dates, refills left and the earliest allowed refill date with your pharmacy or prescriber.

## What it does

- Keeps a list of medications with last fill date, days supply and refills left.
- Shows the next refill date and a status: OK, due soon, due today or overdue.
- **Filled today** resets the clock and uses up one refill.
- Exports a calendar file with two reminders per fill, from now until a date you choose:
  - a request reminder a set number of days before the refill is due
  - a pickup reminder the weekday before it runs out
- When refills left reach zero, the request reminder says to ask the prescriber for a new prescription.
- Weekend dates move to the nearest weekday. Holidays are not handled.

## Requirements

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)

## Use

1. Run `RefillCalendar.ahk`.
2. Choose **Add** and enter the name, last fill date, days supply (quantity divided by doses per day) and refills left.
3. Choose **Settings** to set the coverage end date, how many days ahead to request refills, and the reminder hour.
4. Choose **Export calendar (.ics)**, then open the saved file to add the reminders to your calendar.

Shortcuts: `Win+Alt+R` or type `ccrefill` to bring up the window.

## Your data stays private

Your list is saved on your own PC at `%AppData%\RefillCalendar\RefillCalendar.ini`. It is not stored in this folder, so it cannot be committed by accident. `RefillCalendar.example.ini` is made-up sample data that shows the file format.

If you fork or contribute, do not post real medication names, Rx numbers, pharmacy details, exported `.ics` files or screenshots of your list in issues, pull requests or commits. Anything committed stays in the repository history.

## Limits

- Dates assume each fill is picked up on time. If a fill slips, update **Last fill** and export again.
- Re-importing an exported file can duplicate events in some calendars. Delete the old import first, or import into a new calendar.
- The export dialog opens in your Dropbox folder the first time, then remembers the last folder you saved to. Keep exported files out of the repo folder.
- Exported events are timed events at the reminder hour, in your calendar's local time zone.
