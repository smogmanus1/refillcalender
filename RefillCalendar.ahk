#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; Refill Calendar  v1.0.0
;
; Tracks prescription refill dates and exports reminders as an .ics calendar
; file that Outlook, Google Calendar and Apple Calendar can import.
;
;   Hotkey:    Win+Alt+R        Hotstring:  ccrefill
;   Your data: %AppData%\RefillCalendar\RefillCalendar.ini  (never in the repo)
;
; Reminder tool only. Not medical advice. Confirm fill dates, refills left and
; the earliest allowed refill date with your pharmacy or prescriber.
; ============================================================================

APP_VERSION := "1.0.0"
DataDir := A_AppData "\RefillCalendar"
IniFile := DataDir "\RefillCalendar.ini"
Meds := []
Cfg := Map("end", "", "lead", 7, "hour", 9, "exportDir", "")
mainGui := ""
lv := ""
infoTxt := ""

if !DirExist(DataDir)
    DirCreate(DataDir)
LoadData()
BuildGui()
ShowMain()
A_TrayMenu.Add("Open Refill Calendar", (*) => ShowMain())
A_TrayMenu.Default := "Open Refill Calendar"
Hotstring("::ccrefill", (*) => ShowMain())

#!r::ShowMain()

; ---------------------------------------------------------------------------
; Dates. All dates are YYYYMMDD strings.
; ---------------------------------------------------------------------------
TodayYmd() {
    return SubStr(A_Now, 1, 8)
}

AddDays(ymd, n) {
    return SubStr(DateAdd(ymd "000000", n, "Days"), 1, 8)
}

DaysUntil(ymd) {
    return DateDiff(ymd "000000", TodayYmd() "000000", "Days")
}

Fmt(ymd) {
    return FormatTime(ymd "000000", "ddd M/d/yyyy")
}

IsWeekend(ymd) {
    wd := FormatTime(ymd "000000", "WDay")
    return (wd = 1 || wd = 7)
}

PrevWeekday(ymd) {
    while IsWeekend(ymd)
        ymd := AddDays(ymd, -1)
    return ymd
}

NextWeekday(ymd) {
    while IsWeekend(ymd)
        ymd := AddDays(ymd, 1)
    return ymd
}

ToInt(v, default) {
    return IsInteger(v) ? Integer(v) : default
}

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
LoadData() {
    global Meds, Cfg
    Meds := []
    Cfg["lead"] := ToInt(IniRead(IniFile, "Settings", "LeadDays", "7"), 7)
    Cfg["hour"] := ToInt(IniRead(IniFile, "Settings", "ReminderHour", "9"), 9)
    Cfg["end"] := IniRead(IniFile, "Settings", "EndDate", AddDays(TodayYmd(), 180))
    Cfg["exportDir"] := IniRead(IniFile, "Settings", "ExportDir", "")
    n := ToInt(IniRead(IniFile, "Settings", "Count", "0"), 0)
    loop n {
        sec := "Med" A_Index
        Meds.Push(Map(
            "name", IniRead(IniFile, sec, "Name", ""),
            "fill", IniRead(IniFile, sec, "LastFill", TodayYmd()),
            "days", ToInt(IniRead(IniFile, sec, "DaysSupply", "90"), 90),
            "left", IniRead(IniFile, sec, "RefillsLeft", ""),
            "notes", IniRead(IniFile, sec, "Notes", "")))
    }
}

SaveData() {
    try FileDelete(IniFile)
    IniWrite(Cfg["lead"], IniFile, "Settings", "LeadDays")
    IniWrite(Cfg["hour"], IniFile, "Settings", "ReminderHour")
    IniWrite(Cfg["end"], IniFile, "Settings", "EndDate")
    IniWrite(Cfg["exportDir"], IniFile, "Settings", "ExportDir")
    IniWrite(Meds.Length, IniFile, "Settings", "Count")
    for i, m in Meds {
        sec := "Med" i
        IniWrite(m["name"], IniFile, sec, "Name")
        IniWrite(m["fill"], IniFile, sec, "LastFill")
        IniWrite(m["days"], IniFile, sec, "DaysSupply")
        IniWrite(m["left"], IniFile, sec, "RefillsLeft")
        IniWrite(m["notes"], IniFile, sec, "Notes")
    }
}

NextDue(m) {
    return AddDays(m["fill"], m["days"])
}

StatusOf(m) {
    nxt := NextDue(m)
    d := DaysUntil(nxt)
    if (d < 0)
        txt := "OVERDUE " (-d) " days"
    else if (d = 0)
        txt := "Due today"
    else if (d <= Cfg["lead"])
        txt := "Due in " d " days"
    else
        txt := "OK, " d " days"
    return Map("next", nxt, "days", d, "text", txt)
}

SortMeds() {
    global Meds
    sorted := []
    for m in Meds {
        key := NextDue(m)
        pos := sorted.Length + 1
        for j, s in sorted {
            if (key < NextDue(s)) {
                pos := j
                break
            }
        }
        sorted.InsertAt(pos, m)
    }
    Meds := sorted
}

; ---------------------------------------------------------------------------
; Main window
; ---------------------------------------------------------------------------
BuildGui() {
    global mainGui, lv, infoTxt
    mainGui := Gui(, "Refill Calendar " APP_VERSION)
    mainGui.SetFont("s10", "Segoe UI")
    lv := mainGui.Add("ListView", "r14 w880 Grid -Multi NoSortHdr", ["Medication", "Last fill", "Days", "Next refill", "Status", "Refills left"])
    lv.OnEvent("DoubleClick", (ctrl, row) => row ? EditMed(row) : 0)
    mainGui.Add("Button", "xm w100", "Add").OnEvent("Click", (*) => EditMed(0))
    mainGui.Add("Button", "x+8 w100", "Edit").OnEvent("Click", (*) => EditSelected())
    mainGui.Add("Button", "x+8 w120", "Filled today").OnEvent("Click", (*) => FilledToday())
    mainGui.Add("Button", "x+8 w100", "Remove").OnEvent("Click", (*) => RemoveSelected())
    mainGui.Add("Button", "xm w180", "Export calendar (.ics)").OnEvent("Click", (*) => ExportIcs())
    mainGui.Add("Button", "x+8 w100", "Copy list").OnEvent("Click", (*) => CopyList())
    mainGui.Add("Button", "x+8 w100", "Settings").OnEvent("Click", (*) => SettingsDlg())
    infoTxt := mainGui.Add("Text", "xm w880 r3", "")
    mainGui.OnEvent("Close", (*) => ExitApp())
    RefreshList()
}

ShowMain() {
    mainGui.Show()
    WinActivate("ahk_id " mainGui.Hwnd)
}

RefreshList() {
    SortMeds()
    lv.Delete()
    for m in Meds {
        s := StatusOf(m)
        lv.Add("", m["name"], Fmt(m["fill"]), m["days"], Fmt(s["next"]), s["text"], (m["left"] = "") ? "?" : m["left"])
    }
    loop 6
        lv.ModifyCol(A_Index, "AutoHdr")
    infoTxt.Text := "Calendar export covers through " Fmt(Cfg["end"]) ". Request reminders start " Cfg["lead"] " days before each refill is due.`nYour data is stored only on this PC: " IniFile
}

SelectedRow() {
    row := lv.GetNext(0)
    if !row
        MsgBox("Select a prescription in the list first.", "Refill Calendar", "Icon!")
    return row
}

EditSelected() {
    row := SelectedRow()
    if row
        EditMed(row)
}

FilledToday() {
    row := SelectedRow()
    if !row
        return
    m := Meds[row]
    m["fill"] := TodayYmd()
    if (IsInteger(m["left"]) && Integer(m["left"]) > 0)
        m["left"] := Integer(m["left"]) - 1
    SaveData()
    RefreshList()
}

RemoveSelected() {
    global Meds
    row := SelectedRow()
    if !row
        return
    if (MsgBox("Remove " Meds[row]["name"] " from the list?", "Refill Calendar", "YesNo Icon?") != "Yes")
        return
    Meds.RemoveAt(row)
    SaveData()
    RefreshList()
}

CopyList() {
    out := ""
    for m in Meds {
        s := StatusOf(m)
        out .= m["name"] " - next refill " Fmt(s["next"]) " (" s["text"] ")`r`n"
    }
    A_Clipboard := out
    MsgBox("List copied to the clipboard.", "Refill Calendar", "Iconi T2")
}

; ---------------------------------------------------------------------------
; Add / edit dialog
; ---------------------------------------------------------------------------
EditMed(idx) {
    isNew := (idx = 0)
    m := isNew ? Map("name", "", "fill", TodayYmd(), "days", 90, "left", "", "notes", "") : Meds[idx]
    dlg := Gui("+Owner" mainGui.Hwnd, isNew ? "Add prescription" : "Edit prescription")
    dlg.SetFont("s10", "Segoe UI")
    dlg.Add("Text", "w340", "Medication name")
    eName := dlg.Add("Edit", "w340", m["name"])
    dlg.Add("Text", "w340", "Last fill date")
    dFill := dlg.Add("DateTime", "w150 Choose" m["fill"])
    dlg.Add("Text", "w340", "Days supply (quantity divided by doses per day)")
    eDays := dlg.Add("Edit", "w100 Number", m["days"])
    dlg.Add("Text", "w340", "Refills left (leave blank if unknown)")
    eLeft := dlg.Add("Edit", "w100 Number", m["left"])
    dlg.Add("Text", "w340", "Notes (optional)")
    eNotes := dlg.Add("Edit", "w340", m["notes"])
    ok := dlg.Add("Button", "Default w100 xm y+16", "Save")
    cancel := dlg.Add("Button", "x+8 w100", "Cancel")
    ok.OnEvent("Click", (*) => SaveEdit(dlg, idx, eName, dFill, eDays, eLeft, eNotes))
    cancel.OnEvent("Click", (*) => CloseDlg(dlg))
    dlg.OnEvent("Close", (*) => CloseDlg(dlg))
    dlg.OnEvent("Escape", (*) => CloseDlg(dlg))
    mainGui.Opt("+Disabled")
    dlg.Show()
}

SaveEdit(dlg, idx, eName, dFill, eDays, eLeft, eNotes) {
    name := Trim(eName.Value)
    days := Trim(eDays.Value)
    left := Trim(eLeft.Value)
    if (name = "") {
        MsgBox("Enter a medication name.", "Refill Calendar", "Icon!")
        return
    }
    if !(IsInteger(days) && Integer(days) > 0) {
        MsgBox("Enter the days supply as a whole number above zero.", "Refill Calendar", "Icon!")
        return
    }
    m := Map("name", name, "fill", SubStr(dFill.Value, 1, 8), "days", Integer(days), "left", left, "notes", Trim(eNotes.Value))
    if (idx = 0)
        Meds.Push(m)
    else
        Meds[idx] := m
    SaveData()
    CloseDlg(dlg)
    RefreshList()
}

CloseDlg(dlg) {
    mainGui.Opt("-Disabled")
    dlg.Destroy()
    ShowMain()
}

; ---------------------------------------------------------------------------
; Settings dialog
; ---------------------------------------------------------------------------
SettingsDlg() {
    dlg := Gui("+Owner" mainGui.Hwnd, "Settings")
    dlg.SetFont("s10", "Segoe UI")
    dlg.Add("Text", "w340", "Keep me covered through this date")
    dEnd := dlg.Add("DateTime", "w150 Choose" Cfg["end"])
    dlg.Add("Text", "w340", "Request the refill this many days before it is due")
    eLead := dlg.Add("Edit", "w100 Number", Cfg["lead"])
    dlg.Add("Text", "w340", "Reminder time (hour, 0 to 22)")
    eHour := dlg.Add("Edit", "w100 Number", Cfg["hour"])
    ok := dlg.Add("Button", "Default w100 xm y+16", "Save")
    cancel := dlg.Add("Button", "x+8 w100", "Cancel")
    ok.OnEvent("Click", (*) => SaveSettings(dlg, dEnd, eLead, eHour))
    cancel.OnEvent("Click", (*) => CloseDlg(dlg))
    dlg.OnEvent("Close", (*) => CloseDlg(dlg))
    dlg.OnEvent("Escape", (*) => CloseDlg(dlg))
    mainGui.Opt("+Disabled")
    dlg.Show()
}

SaveSettings(dlg, dEnd, eLead, eHour) {
    lead := Trim(eLead.Value)
    hour := Trim(eHour.Value)
    if !(IsInteger(lead) && Integer(lead) >= 0 && Integer(lead) <= 60) {
        MsgBox("Enter days before as a number from 0 to 60.", "Refill Calendar", "Icon!")
        return
    }
    if !(IsInteger(hour) && Integer(hour) >= 0 && Integer(hour) <= 22) {
        MsgBox("Enter the reminder hour as a number from 0 to 22.", "Refill Calendar", "Icon!")
        return
    }
    Cfg["end"] := SubStr(dEnd.Value, 1, 8)
    Cfg["lead"] := Integer(lead)
    Cfg["hour"] := Integer(hour)
    SaveData()
    CloseDlg(dlg)
    RefreshList()
}

; ---------------------------------------------------------------------------
; Calendar export (.ics)
; ---------------------------------------------------------------------------
; Remembers the last export folder. First run: your Dropbox folder if found, else Desktop.
DefaultExportDir() {
    if (Cfg["exportDir"] != "" && DirExist(Cfg["exportDir"]))
        return Cfg["exportDir"]
    info := A_AppData "\..\Local\Dropbox\info.json"
    try {
        if FileExist(info) {
            txt := FileRead(info, "UTF-8")
            if RegExMatch(txt, '"path":\s*"([^"]+)"', &m) {
                d := StrReplace(StrReplace(m[1], "\\", "\"), "/", "\")
                if DirExist(d)
                    return d
            }
        }
    }
    return A_Desktop
}

ExportIcs() {
    if (Meds.Length = 0) {
        MsgBox("Add a prescription first.", "Refill Calendar", "Icon!")
        return
    }
    path := FileSelect("S16", DefaultExportDir() "\refill-reminders.ics", "Save calendar file", "Calendar (*.ics)")
    if (path = "")
        return
    SplitPath(path, , &outDir)
    Cfg["exportDir"] := outDir
    SaveData()
    if !RegExMatch(path, "i)\.ics$")
        path .= ".ics"
    r := BuildIcs()
    try {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(r["text"])
        f.Close()
    } catch as err {
        MsgBox("Could not save the file:`n" err.Message, "Refill Calendar", "Icon!")
        return
    }
    MsgBox("Saved " r["count"] " reminders to:`n" path "`n`nOpen the file to add them to Outlook or another calendar.", "Refill Calendar", "Iconi")
}

BuildIcs() {
    lines := []
    stamp := SubStr(A_NowUTC, 1, 8) "T" SubStr(A_NowUTC, 9, 6) "Z"
    hh := Format("{:02}", Cfg["hour"])
    lead := Cfg["lead"]
    endYmd := Cfg["end"]
    now := TodayYmd()
    count := 0
    lines.Push("BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Refill Calendar//EN", "CALSCALE:GREGORIAN", "X-WR-CALNAME:Refill reminders")
    for m in Meds {
        name := m["name"]
        days := m["days"]
        refills := IsInteger(m["left"]) ? Integer(m["left"]) : -1
        slug := RegExReplace(name, "[^A-Za-z0-9]", "")
        due := NextDue(m)
        if (due < now)
            due := now
        k := 0
        while (due <= endYmd && k < 60) {
            k += 1
            req := PrevWeekday(AddDays(due, -lead))
            pick := PrevWeekday(AddDays(due, -1))
            if (req <= now)
                req := NextWeekday(AddDays(now, 1))
            if (pick <= req)
                pick := NextWeekday(AddDays(req, 1))
            if (refills >= 0 && k > refills) {
                title := "Ask prescriber for new Rx: " name
                note := "No refills are left for this fill. Ask the prescriber for a new prescription. Supply ends about " Fmt(due) "."
            } else {
                title := "Request refill: " name
                note := "Supply ends about " Fmt(due) ". Allow time for the pharmacy to process the refill."
            }
            PushEvent(lines, "rc-" slug "-" k "-req-" req "@refillcalendar", stamp, req, hh, title, note)
            PushEvent(lines, "rc-" slug "-" k "-pick-" pick "@refillcalendar", stamp, pick, hh, "Pick up: " name " (supply ends " Fmt(due) ")", "Fill number " k ". Adjust the dates if the real fill date changes.")
            count += 2
            due := AddDays(due, days)
        }
    }
    lines.Push("END:VCALENDAR")
    text := ""
    for ln in lines
        text .= IcsFold(ln) "`r`n"
    return Map("text", text, "count", count)
}

PushEvent(lines, uid, stamp, ymd, hh, title, note) {
    lines.Push("BEGIN:VEVENT", "UID:" uid, "DTSTAMP:" stamp
        , "DTSTART:" ymd "T" hh "0000", "DTEND:" ymd "T" hh "3000"
        , "SUMMARY:" IcsEsc(title), "DESCRIPTION:" IcsEsc(note), "TRANSP:TRANSPARENT"
        , "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" IcsEsc(title), "TRIGGER:-P1D", "END:VALARM"
        , "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" IcsEsc(title), "TRIGGER:PT0S", "END:VALARM"
        , "END:VEVENT")
}

IcsEsc(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, ";", "\;")
    s := StrReplace(s, ",", "\,")
    s := StrReplace(s, "`r`n", "\n")
    s := StrReplace(s, "`n", "\n")
    return s
}

IcsFold(line) {
    out := ""
    while (StrLen(line) > 73) {
        out .= SubStr(line, 1, 73) "`r`n "
        line := SubStr(line, 74)
    }
    return out line
}
