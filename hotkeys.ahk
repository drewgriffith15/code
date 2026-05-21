#Persistent ;Keeps the script running until it is closed manually
#SingleInstance force ;Only one instance open at one time
#NoEnv
#MaxMem
SendMode input

;############################################################################################################
;!! ATTENTION !! RUN THIS ON STARTUP. PLACE A SHORTCUT OF THE SCRIPT IN THE STARTUP FOLDER
;-> SCRIPT LOCATION: "C:\Users\wgriffith2\Dropbox (Liberty University)\Code\hotkeys.ahk"
;-> SHORTCUT GOES IN: "~\APPDATA\ROAMING\MICROSOFT\WINDOWS\START MENU\PROGRAMS\STARTUP"
;############################################################################################################

;############################################################################################################
; Run the following programs during work hours only
;############################################################################################################
SetTimer IdleChk, 60000 ; Checker runs every given number of milliseconds - divide the time value by 1000
IdleChk:
If (A_TimeIdle > 60000)
{
    Send {RShift}
    Return
}

; Work hours or business hours
Timestart = 0800 ; Time start 24H
Timeend = 1800 ; Time end in 24H
Daystart = 2
Dayend = 6
flag = 1
time := A_Hour A_Min
If time between %Timestart% and %Timeend%
If A_WDay between %Daystart% and %Dayend%
If (A_ComputerName = "5CG4114KYB")
{
    ; Execute during work hours and programs will be enabled to run.
    flag = 0
    IfWinNotExist, ahk_exe ms-teams.exe ; If Teams is NOT running, then run it
    {
        Run, msteams:
        Return
    }
    Else
    {
        Return
    }
}
; Execute during off-work hours and programs will be disabled.
If flag
IfWinExist, ahk_exe ms-teams.exe ; If Teams is running, then quit it
{
    Process, Close, ms-teams.exe
    Return
}
Else
{
    Return
}
Return
;############################################################################################################
; END - Program run
;############################################################################################################

::100,,::
{
    SendInput, exactly (hundred
    Return
}

::pb,,::
{
    ; Send first emoji code
    SendInput, (victory)
    Sleep, 50            ; Wait 50ms for Teams to show the suggestion menu
    SendInput, {Tab}     ; Confirm the suggestion

    ; Send second emoji code
    SendInput, (pray)
    Sleep, 50            ; Wait again for the menu
    SendInput, {Tab}     ; Confirm the suggestion
    Return
}

::imo,,::
{
    SendInput, in my opinion,
    Return
}

::btw,,::
{
    SendInput, by the way
    Return
}

::nbd,,::
{
    SendInput, no big deal
    Return
}

::wth,,::
{
    SendInput, what the heck!
    Return
}

::bc,,::
{
    SendInput, because
    Return
}

::yw,,::
{
    SendInput, you're welcome
    Return
}

::ty,,::
{
    SendInput, thank you
    Return
}

::omg,,::
{
SendInput, oh my goodness
Return
}

::tbh,,::
{
SendInput, to be honest,
Return
}

::jms,,::
{
SendInput, just making sure
Return
}

::jic,,::
{
SendInput, just in case
Return
}

::idc,,::
{
SendInput, I don't care
Return
}

::idk,,::
{
SendInput, I don't know
Return
}

::nm,,::
{
SendInput, never mind
Return
}

::irl,,::
{
SendInput, in real life
Return
}

::ikr,,::
{
SendInput, I know, right?
Return
}

::rn,,::
{
SendInput, right now
Return
}

::fr,,::
{
SendInput, for real
Return
}

::lmk,,::
{
SendInput, let me know
Return
}

::jk,,::
{
SendInput, just kidding
Return
}

::np,,::
{
SendInput, no problem!
Return
}

;############################################################################################################
; Skylight emails
;############################################################################################################

::kylesky,,::
{
SendInput, culpepperhouse@ourskylight.com
Return
}

::gigisky,,::
{
SendInput, rdculpepper@ourskylight.com
Return
}

::drewsky,,::
{
SendInput, griffith_family@ourskylight.com
Return
}

;############################################################################################################
; ServiceNOW template
;############################################################################################################
^!n:: ; service meow Ctrl+Alt+N to trigger
{
Clipboard =
(
Description:
Assigned to: wgriffith2
Assignment group: ADS Academics Leads
Item: Database Object Management
Configuration Item: [DB] DWH Databases
Requested for: Michael Shenkle
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################
; Take a list of strings and format them for a sql in string query ('EXAMPLE1','EXAMPLE2','EXAMPLE3')
;############################################################################################################
::spl,,::
StringReplace, clipboard, clipboard, `r`n`r`n, `r`n, All
clipall:= Clipboard
final:=
cnt = 0
loop, parse, clipall, `n
{
                cnt += 1
}
loop, parse, clipall, `n
                {
                                if line = ""
                                                continue
                                if A_index = %cnt%
                                                comma =
                                if A_index < %cnt%
                                                comma:= ","
                                StringReplace,line, A_loopfield,`n,,all
                                StringReplace,line, A_loopfield,`r,,all
                                final:= final . "'" . line . "'" . comma
                }
final:= "(" . final . ")"
Clipboard:= final
send {ctrldown}v{CtrlUp}
; Quick cleanup of white space
Send {Left}+{Left}+{Left}+{Left}
Send {Delete}
Return

;############################################################################################################
; ORACLE SQL
;############################################################################################################

::dup,,::
{
Clipboard =
(
-- duplicate check...
SELECT *
  FROM (SELECT chkdup.*,
               -- partition by all col constraints
               COUNT(1) over(PARTITION BY fld1, fld2) AS dupcnt
          FROM ( ) chkdup) WHERE dupcnt > 1
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################

::cte,,::
{
Clipboard =
(
WITH rec AS ( )
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################

::create,,::
{
Clipboard =
(
-- drop and recreate table
BEGIN
EXECUTE IMMEDIATE 'DROP TABLE WAG_TMP';
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE != -942 THEN
RAISE;
END IF;
END;
/ --

CREATE TABLE WAG_TMP AS
-- **SQL HERE** --

-- ADD TABLE COMMENT
comment on table WAG_TMP IS 'DO NOT DELETE UNTIL DREW SAYS SO';
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################

::grant,,::
{
Clipboard =
(
-- targeted select grant ...
GRANT SELECT on table_name_here TO zargos_q_role;
-- grant all objects in selected schema to ads_etl ...
BEGIN
FOR objects IN (SELECT 'GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, ALTER, INDEX, DEBUG, READ ON "' || owner || '"."' || object_name || '" TO ADS_ETL WITH GRANT OPTION' grantsql
                  FROM all_objects
                 WHERE owner = 'UTL_D_AA' -- <<< change the schema as needed
                   AND object_type = 'TABLE'
                   AND object_type NOT IN ('SYNONYM', 'INDEX', 'INDEX PARTITION', 'DATABASE LINK', 'LOB', 'TABLE PARTITION', 'TRIGGER') -- ungrantable objects
                 ORDER BY object_type,
                          object_name)
LOOP
BEGIN
EXECUTE IMMEDIATE objects.grantsql;
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE IN (-4063) THEN
NULL;
ELSE
raise_application_error(-20000, 'Problem with this statement: ' || objects.grantsql || chr(10) || SQLERRM);
END IF;
END;
END LOOP;
END;
/
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################

::listagg,,::
{
Clipboard =
(
listagg(distinct (), ', ') within GROUP(ORDER BY 1) as listed
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################

::rank,,::
{
Clipboard =
(
rank() over (partition by () order by ()) as ranking
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################

::search,,::
{
Clipboard =
(
-- Academics tables...
SELECT DISTINCT c.owner AS owner,
                c.table_name,
                c.column_name/*,
                c.data_type,
                c.char_length,
                c.column_id*/
  FROM all_tab_columns c
 WHERE c.owner IN ('UTL_D_LMS')
 ORDER BY 1,
          2;
-- table comments
/*
SELECT *
  FROM all_tab_comments c
 WHERE c.owner IN ('UTL_D_LMS')
 ORDER BY 1,
          2
*/
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################

::sf,,::
{
Clipboard =
(
select * from utl_d_
)
Sleep, 200
; Wait for clipboard contents to update.
ClipWait
; Send paste.
Send, ^v
; Allow time for clipboard to paste.
Sleep, 200
Clipboard := ; clear clipboard
Sleep, 200
Return
}

;############################################################################################################
; bitbucket repo in bash
;############################################################################################################
^!g:: ; Ctrl+Alt+G to trigger
    ; Ask the user: New or Update?
    MsgBox, 3, Git Action, Git Commit UPDATE?`n`nYES (UPDATE)`n`nNO (INITIAL)

    IfMsgBox, Cancel
        return ; Stop if user clicks Cancel

    IfMsgBox, Yes
    {
        ; ==========================================
        ;            UPDATE COMMIT LOGIC
        ; ==========================================

        ; 1. Get Folder
        InputBox, FOLDER, Repository, Paste the full path to your project folder:
        if ErrorLevel
            return

        ; CLEANUP: Remove double quotes and trailing slashes
        FOLDER := StrReplace(FOLDER, """")
        FOLDER := Trim(FOLDER, "\")
        ; FIX FOR BASH: Convert Windows backslashes to Linux forward slashes
        FOLDER := StrReplace(FOLDER, "\", "/")

        ; 2. Get Commit Message
        InputBox, MESSAGE, Commit Message, What changed?
        if ErrorLevel
            return

        ; FIX FOR BASH: Remove single quotes from the message so it doesn't break the Bash command string
        MESSAGE := StrReplace(MESSAGE, "'", "")

        ; Run it
        ; CHANGED: Explicitly pushing to 'origin HEAD:master' to match your working Bitbucket rules
        CMD = cd '%FOLDER%' && git add --all && git commit -m '%MESSAGE%' && git push origin HEAD:master ; read -p "Press Enter to close..."
        Run, "C:\Program Files\Git\git-bash.exe" -c "%CMD%"
    }
    Else IfMsgBox, No
    {
        ; ==========================================
        ;         NEW INITIAL COMMIT LOGIC
        ; ==========================================

        ; --- Configuration ---
        EnvFilePath := "C:\Users\wgriffith2\.claude\.env.work"

        ; 0. Step Zero: Reminder
        MsgBox, 1, Repository Check, Did you already create a repository in Bitbucket ADS Academics?
        IfMsgBox, Cancel
            return ; Stop if user clicks Cancel

        ; 1. Get Folder
        InputBox, FOLDER, Folder, Paste the full local file path to your project folder:
        if ErrorLevel
            return

        ; 2. AUTOMATICALLY Extract the Repo Name from the folder path
        FOLDER := StrReplace(FOLDER, """") ; Removes double quotes if "Copy as path" was used
        FOLDER := Trim(FOLDER, "\")        ; Removes trailing slash if you accidentally pasted one
        SplitPath, FOLDER, REPO            ; Grabs the last folder name (e.g., "CanvasAPI")

        ; FIX FOR BASH: Convert Windows slashes to Linux slashes (Must be done AFTER SplitPath)
        FOLDER := StrReplace(FOLDER, "\", "/")

        ; 3. Automatically construct the Commit Message
        MESSAGE := "Initial commit: " . REPO

        ; 4. Parse .env file
        FileRead, EnvContent, %EnvFilePath%
        Loop, Parse, EnvContent, `n, `r
        {
            if (RegExMatch(A_LoopField, "^(\w+)\s*=\s*(.*)$", var))
            {
                %var1% := Trim(var2, """' ") ; Removes quotes/whitespace
            }
        }

        ; Construct the command EXACTLY matching Bitbucket's working bash snippet
        CMD = cd '%FOLDER%' && git init && git add --all && git commit -m '%MESSAGE%' && git remote add origin 'https://%BB_USR%:%BB_TOK%@%BB_URL%/%REPO%.git' && git push -u origin HEAD:master ; read -p "Press Enter to close..."

        ; Run it
        Run, "C:\Program Files\Git\git-bash.exe" -c "%CMD%"
    }
return

;############################################################################################################
; Claude Code Environment Switcher - Copy Command to Clipboard
;############################################################################################################

^!w::  ; Ctrl+Alt+W for Work
{
    A_Clipboard := "cd ""C:\Users\wgriffith2\Dropbox (Liberty University)\Liberty University"" && . $HOME\.claude\set-work.ps1 && claude"
    Send, ^v
    ToolTip, Work command pasted!
    SetTimer, RemoveToolTip, 2000
    Return
}

RemoveToolTip:
SetTimer, RemoveToolTip, Off
ToolTip
return

;############################################################################################################
; CONSTRUCT Ingest - YouTube transcript fetch (Ctrl+Alt+Y)
;############################################################################################################
^!y::
{
    Run, powershell.exe -NoExit -Command "cd 'C:\Users\wgriffith2\Dropbox (Liberty University)\Code'; python ingest_youtube.py --playlist"
    Return
}

;############################################################################################################
; CONSTRUCT Ingest - Raw transcript classifier/wiki push (Ctrl+Alt+I)
;############################################################################################################
^!i::
{
    Run, powershell.exe -NoExit -Command "cd 'C:\Users\wgriffith2\Dropbox (Liberty University)\Code'; python ingest_raw.py --run"
    Return
}

;############################################################################################################
; Command Reference - Open help page in browser (Ctrl+Alt+H)
;############################################################################################################
^!h::
{
    Run, "C:\Users\wgriffith2\Dropbox (Liberty University)\Code\commands.html"
    Return
}

;############################################################################################################
; VoiceDictate - Launch system tray dictation app (Ctrl+Alt+V)
; Once running, use F9 to toggle mic on/off - text is injected at cursor
;############################################################################################################
^!v::
{
    Run, "C:\Users\wgriffith2\Dropbox (Liberty University)\Code\dictate.bat"
    Return
}