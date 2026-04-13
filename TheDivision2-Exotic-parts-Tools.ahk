#Requires AutoHotkey v2.0
#UseHook
#SingleInstance Force

if !A_IsAdmin {
    Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

;=======Global Variables=========
;EDRSilencer path
global windowstite := "TheDivision2-Exotic-parts-Tools-1.0.3"
global pbPath := A_ScriptDir "\EDRSilencer\EDRSilencer.exe"
global stopLoop := false
global TheDivision2Path := IniRead(A_ScriptDir "\config.ini", "Game", "TheDivision2Path", "")
;Check network connection
global adapter := IniRead(A_ScriptDir "\config.ini", "Network", "Adapter", "")
SplitPath(TheDivision2Path, &fileName)  ; Extract file name
global gamefile := fileName
; Network disconnection method constants
global NET_FIREWALL := 1      ; Firewall rules
global NET_ADAPTER := 2       ; Disable network adapter
global NET_PROXYBRIDGE := 3   ; EDRSilencer
global configFile := A_ScriptDir "\config.ini"
global NetMethod := NET_FIREWALL
;Running status display
global iterationCount := 0
global numberOfErrors := 0
global netError := 0
; Check if file exists, extract if not
if !FileExist(pbPath) {
    ; Ensure target directory exists
    targetDir := A_ScriptDir "\EDRSilencer"
    if !DirExist(targetDir)
        DirCreate(targetDir)
    ; Try to extract file
    try {
        FileInstall "EDRSilencer\EDRSilencer.exe", pbPath, 1
    } catch as e {
        MsgBox "The program cannot read/write its directory. Please try running with administrator privileges, or move the program to another directory"
        ExitApp
    }
}

if !FileExist(pbPath){
    MsgBox "Program exited abnormally. Reason:`nEDRSilencer not found. Please confirm that EDRSilencer/EDRSilencer.exe exists in the script directory"
    ExitApp
}

; ========== Get Network Adapter List ==========
GetNetworkAdapters() {
    adapters := []
    try {
        wmi := ComObject("WbemScripting.SWbemLocator").ConnectServer("", "root\cimv2")
        query := "SELECT * FROM Win32_NetworkAdapter WHERE PhysicalAdapter=True AND NetEnabled=True"
        for adapter in wmi.ExecQuery(query) {
            if (adapter.NetConnectionID)
                adapters.Push(adapter.NetConnectionID)
        }
    }
    return adapters
}

; ========== GUI Callback Functions ==========
BrowseFile(*) {
    global editPath
    selected := FileSelect("3", , "Select TheDivision2.exe", "Executable Files (*.exe)")
    if selected != ""
        editPath.Value := selected
}

RefreshAdapterList() {
    global comboAdapter, savedAdapter
    adapters := GetNetworkAdapters()
    comboAdapter.Delete()
    for ad in adapters
        comboAdapter.Add([ad])
    if adapters.Length = 0
        comboAdapter.Add(["No available network adapters detected"])

    ; Restore previously saved adapter
    if savedAdapter {
        for i, ad in adapters {
            if ad = savedAdapter {
                comboAdapter.Choose(i)
                break
            }
        }
    }
}

; Check and close window (if configuration is valid)
CheckAndClose() {
    global editPath, comboAdapter, configFile, TheDivision2Path, NetworkAdapter,gamefile,NetMethod
    global comboNetMethod
    path := Trim(editPath.Value)
    adapter := Trim(comboAdapter.Text)
    if path = "" {
        MsgBox "Please select the game path first!", "Notice", 0x40
        return false
    }
    if adapter = "" || adapter = "No available network adapters detected" {
        MsgBox "Please select a valid network adapter first!", "Notice", 0x40
        return false
    }
    ; Save configuration
    IniWrite path, configFile, "Game", "TheDivision2Path"
    IniWrite adapter, configFile, "Network", "Adapter"
    ; Save network disconnection method
    IniWrite comboNetMethod.Value, configFile, "Settings", "NetMethod"
    ; Update global variables
    TheDivision2Path := path
    NetworkAdapter := adapter
    NetMethod := comboNetMethod.Value
    SplitPath(TheDivision2Path, &fileName)  ; Extract file name
    gamefile := fileName
    return true
}

; Window close event (top-right X button)
GuiClose(*) {
    if CheckAndClose() {
        mainGui.Destroy()
    }
    return true
}

; ========== GUI ==========
global mainGui, editPath, comboAdapter, savedAdapter
global TheDivision2Path, NetworkAdapter   ; Global variables used by main script

mainGui := Gui()
mainGui.Title := windowstite
mainGui.SetFont("s10")
; ========== Description Text ==========
mainGui.Add("Text", "x10 y260 w480 h30", "Use either Ethernet or WiFi. After saving, press F10 to run, F12 to force stop")
; Game path area
mainGui.Add("Text", "x10 y10 w300 h30", "Please select The Division 2 executable path:")
editPath := mainGui.Add("Edit", "x10 y50 w400 h25 ReadOnly")
btnBrowse := mainGui.Add("Button", "x420 y49 w80 h27", "Browse")

; Network adapter selection area
mainGui.Add("Text", "x10 y110 w300 h30", "Select current network adapter:")
comboAdapter := mainGui.Add("ComboBox", "x10 y150 w300 h200 Choose1")
btnRefresh := mainGui.Add("Button", "x320 y148 w80 h27", "Refresh")

; Close button
btnCancel := mainGui.Add("Button", "x10 y200 w80 h30", "Save and Close")

mainGui.Add("Text", "x10 y280 w300 h30", "Select network disconnection method:")
comboNetMethod := mainGui.Add("ComboBox", "x10 y310 w400 h200 Choose1", ["Firewall Rules (stable direct connection, fast)", "Disable Adapter (aggressive, requires adapter selection)", "EDRSilencer (WFP filter, works with VPN/accelerator)"])

; Load saved option, ensure it is a valid integer
savedMethod := IniRead(configFile, "Settings", "NetMethod", NET_FIREWALL)
savedMethod := savedMethod + 0   ; Convert to integer
if (savedMethod < 1 || savedMethod > 3)
    savedMethod := NET_FIREWALL
comboNetMethod.Choose(savedMethod)

; Load existing configuration (for display only)
savedPath := IniRead(configFile, "Game", "TheDivision2Path", "")
if savedPath
    editPath.Value := savedPath

savedAdapter := IniRead(configFile, "Network", "Adapter", "")
RefreshAdapterList()   ; Populate network adapter list

; Bind events
btnBrowse.OnEvent("Click", BrowseFile)
btnRefresh.OnEvent("Click", (*) => RefreshAdapterList())
btnCancel.OnEvent("Click", (*) => CheckAndClose() && mainGui.Destroy())
mainGui.OnEvent("Close", GuiClose)   ; Handle top-right X button

; Show window
mainGui.Show()

; Wait for user to close window
WinWaitClose windowstite

; ========== After window closes, read configuration from config file ==========
TheDivision2Path := IniRead(configFile, "Game", "TheDivision2Path", "")
NetworkAdapter := IniRead(configFile, "Network", "Adapter", "")
; Read network disconnection method, default to firewall rules
NetMethod := IniRead(configFile, "Settings", "NetMethod", NET_FIREWALL)

; Color detection function (supports retry, uses DllCall to get color)
; Parameters:
;   hwnd        - Window handle
;   percentX, percentY - Offset percentage relative to window top-left corner
;   targetColor - Expected color (hex, e.g. 0x136AFF)
;   variation   - Tolerance (0~255), recommended 10~30, default 20
;   maxRetries  - Maximum retry count, default 20
;   retryDelay  - Retry interval (milliseconds), default 200
;   debug       - Whether to show F10 debug info, default false
; Returns: true if matched, otherwise false
CheckColorWithRetry(hwnd, percentX, percentY, targetColor, variation := 20, maxRetries := 20, retryDelay := 200, debug := false) {
        ; Check if window handle is valid
        loop maxRetries {
            if !WinExist("ahk_id " hwnd){
                return false
            }
        WinGetPos(&winX, &winY, &winW, &winH, hwnd)
        ; Convert percentage to absolute coordinates
        screenX := winW * percentX
        screenY := winH * percentY

        if debug {
            ToolTip "Check color position: " screenX "," screenY "`nExpected: " Format("{:06X}", targetColor)
            SetTimer () => ToolTip(), -1000
        }

        ; Use DllCall to get color
        hDC := DllCall("GetDC", "Ptr", 0, "Ptr")
        actualColor := DllCall("GetPixel", "Ptr", hDC, "Int", screenX, "Int", screenY, "UInt")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)

        if debug {
            ToolTip "Actual color: " Format("{:06X}", actualColor)
            SetTimer () => ToolTip(), -1000
        }

        if ColorsMatch(actualColor, targetColor, variation) {
            return true
        }

        if (A_Index < maxRetries)
            Sleep retryDelay
    }
    return false
}


; Color matching helper function (unchanged)
ColorsMatch(color1, color2, variation) {
    r1 := (color1 >> 16) & 0xFF
    g1 := (color1 >> 8) & 0xFF
    b1 := color1 & 0xFF
    r2 := (color2 >> 16) & 0xFF
    g2 := (color2 >> 8) & 0xFF
    b2 := color2 & 0xFF
    return (Abs(r1 - r2) <= variation && Abs(g1 - g2) <= variation && Abs(b1 - b2) <= variation)
}

; Force close all TCP connections for a specified process
CloseTCPConnections(pid) {
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec('netstat -ano | findstr "' pid '"')
        output := exec.StdOut.ReadAll()

        lines := StrSplit(Trim(output), "`n", "`r")
        for line in lines {
            if !InStr(line, "TCP") || InStr(line, "LISTENING")
                continue

            ; Parse format: TCP  192.168.1.100:12345  1.2.3.4:80  ESTABLISHED  1234
            parts := StrSplit(Trim(line), " ", "`t")
            cleanParts := []
            for p in parts {
                if p != ""
                    cleanParts.Push(p)
            }
            if cleanParts.Length < 5
                continue

            localAddr := cleanParts[2]
            remoteAddr := cleanParts[3]

            localParts := StrSplit(localAddr, ":")
            remoteParts := StrSplit(remoteAddr, ":")
            if localParts.Length < 2 || remoteParts.Length < 2
                continue

            localIP := localParts[1]
            localPort := localParts[2]
            remoteIP := remoteParts[1]
            remotePort := remoteParts[2]

            ; Construct MIB_TCPROW
            row := Buffer(20, 0)
            ; State: 12 = MIB_TCP_STATE_DELETE_TCB
            NumPut("UInt", 12, row, 0)

            ; Local address (network byte order)
            ipParts := StrSplit(localIP, ".")
            localAddrBin := (ipParts[1] << 24) | (ipParts[2] << 16) | (ipParts[3] << 8) | ipParts[4]
            NumPut("UInt", localAddrBin, row, 4)

            ; Local port (network byte order)
            NumPut("UInt", (localPort << 8) | (localPort >> 8), row, 8)

            ; Remote address
            ipParts := StrSplit(remoteIP, ".")
            remoteAddrBin := (ipParts[1] << 24) | (ipParts[2] << 16) | (ipParts[3] << 8) | ipParts[4]
            NumPut("UInt", remoteAddrBin, row, 12)

            ; Remote port
            NumPut("UInt", (remotePort << 8) | (remotePort >> 8), row, 16)

            ; Call SetTcpEntry
            DllCall("iphlpapi\SetTcpEntry", "Ptr", row)
        }
        return true
    } catch {
        return false
    }
}

;==Disconnect Network==
DisableAdapter(adapterName) {
    global NetMethod, TheDivision2Path, pbPath
    if (NetMethod = NET_FIREWALL) {
        ; Firewall rules
        RunWait 'netsh advfirewall firewall add rule name="BlockGame_Out" dir=out action=block program="' TheDivision2Path '" enable=yes', , "Hide"
        RunWait 'netsh advfirewall firewall add rule name="BlockGame_In" dir=in action=block program="' TheDivision2Path '" enable=yes', , "Hide"
        ToolTip "Network disconnected (Firewall rules)"
        SetTimer () => ToolTip(), -2000
    } else if (NetMethod = NET_ADAPTER) {
        ; Disable network adapter
        RunWait 'netsh interface set interface "' adapterName '" admin=disable', , "Hide"
        ToolTip "Network disconnected (Adapter disabled)"
        SetTimer () => ToolTip(), -2000
    } else if (NetMethod = NET_PROXYBRIDGE) {
        ; EDRSilencer
        RunWait '*RunAs "' pbPath '" block "' TheDivision2Path '"', , "Hide"
         ; 2. Get game process PID
        SplitPath(TheDivision2Path, &gameExe)
        ; 3. Force close all existing TCP connections (optional)
        if ProcessExist(gameExe) {
            pid := WinGetPID("ahk_exe " gameExe)
            if pid {
                CloseTCPConnections(pid)
            }
        } else {
            ; Game not running, skip or notify
            ToolTip "Game not running, skipping closing old TCP connections"
        }
        ToolTip "Network disconnected (WFP filter)"
        SetTimer () => ToolTip(), -2000
    }
}
;========

;==Restore Network==
EnableAdapter(adapterName) {
    global NetMethod, pbPath
    if (NetMethod = NET_FIREWALL) {
        ; Delete firewall rules
        RunWait 'netsh advfirewall firewall delete rule name="BlockGame_Out"', , "Hide"
        RunWait 'netsh advfirewall firewall delete rule name="BlockGame_In"', , "Hide"
    } else if (NetMethod = NET_ADAPTER) {
        ; Enable network adapter
        RunWait 'netsh interface set interface "' adapterName '" admin=enable', , "Hide"
    } else if (NetMethod = NET_PROXYBRIDGE) {
        ; Delete EDRSilencer rules
        RunWait '*RunAs "' pbPath '" unblockall', , "Hide"
    }
}
;===========

; Create floating window
FloatingWindow := Gui("+AlwaysOnTop +ToolWindow -Caption +LastFound")
FloatingWindow.BackColor := "000000"
WinSetTransparent 180, FloatingWindow
WinSetExStyle "+0x20", FloatingWindow

; Add multi-line text control, manually specify position and width (ensure wide enough)
textCtrl := FloatingWindow.Add("Text", "cWhite x10 y10 w200 h100", "Cycles: 0`nError resets: 0`nDisconnect recoveries: 0")
textCtrl.SetFont("s12", "Microsoft YaHei")

; Manually set window size (adjust based on actual display)
winWidth := 220   ; Width slightly wider than text width
winHeight := 100   ; Height enough to display three lines (increase to 100, 110 if bottom part is not shown)

; Window position (top-right corner of screen, 10 pixels from right edge, 10 pixels from top edge)
xPos := A_ScreenWidth - winWidth - 10
yPos := 10

; Show window
FloatingWindow.Show("x" xPos " y" yPos " w" winWidth " h" winHeight " NoActivate")

; Timer to update display
SetTimer(UpdateDisplay, 1000)

UpdateDisplay() {
    global iterationCount, numberOfErrors, netError
    iter := IsSet(iterationCount) ? iterationCount : 0
    err := IsSet(numberOfErrors) ? numberOfErrors : 0
    net := IsSet(netError) ? netError : 0
    textCtrl.Value := "Cycles: " iter "`nError resets: " err "`nDisconnect recoveries: " net
}

;===========Start Reset Script============
reboot(){
    ToolTip "Reset process executing..."
    SetTimer () => ToolTip(), -2000
    global adapter
    global gamefile
    global numberOfErrors
    global netError
    global TheDivision2Path
    EnableAdapter(adapter)
    gamghwd := WinExist("ahk_exe" gamefile)
    Sleep 500
    ;Check for disconnection
    lopNbr := 0
    if gamghwd{
        loop 10{
            networkerror := CheckColorWithRetry(gamghwd,0.431640625,0.55625,0x3C3A93,30,10,500,false)
            if networkerror{
                SendInput "{Space down}"
                Sleep 100
                SendInput "{Space up}"
                Sleep 100
                SendInput "{Space down}"
                Sleep 100
                SendInput "{Space up}"
                Sleep 500
                mainObj := CheckColorWithRetry(gamghwd,0.50234375,0.936,0x136AFF,30,150,1000,false)
                if mainObj{
                    Sleep 1000
                    ToolTip "Recovered, watchdog process exiting"
                    SetTimer () => ToolTip(), -1500
                    netError += 1
                    RunAutomation()
                    return
                }else{
                    Sleep 10000
                }
            }
            lopNbr += 1
            ToolTip "Disconnection detection retry: " lopNbr "/10"
            Sleep 3000
        }
        ToolTip
    }else{
        ToolTip "Game crashed, executing restart steps"
        SetTimer () => ToolTip(), -1500
    }
    Sleep 5000
    re:
    if WinExist("ahk_exe" gamefile) {
        ToolTip "Game window exists, killing game process"
        SetTimer () => ToolTip(), -1500
        RunWait 'taskkill /f /im ' gamefile, , "Hide"
    } else {
        ToolTip "Game window not detected, checking game process"
        SetTimer () => ToolTip(), -1500
        if ProcessExist(gamefile) {
            ToolTip "Game is running, terminating game process"
            SetTimer () => ToolTip(), -1500
            RunWait 'taskkill /f /im ' gamefile, , "Hide"
        } else {
            ToolTip "Not running, executing startup"
        }
    }
    RunWait 'taskkill /f /im ' "upc.exe", , "Hide"
    Sleep 10000
    maxRetries := 60 ;Retry count
    retryCount := 0 ;Initialize counter
    found := false

    while !found && retryCount < maxRetries {
        retryCount += 1

    if ProcessExist(gamefile){
            ToolTip "Game running, retrying... (" retryCount "/" maxRetries ")"
            SetTimer () => ToolTip(), -1500
            RunWait 'taskkill /f /im ' gamefile, , "Hide"
            Sleep 10000   ; Wait 10 seconds before retrying
        } else {
            ToolTip "Starting game"
            SetTimer () => ToolTip(), -1500
            Run TheDivision2Path
            found := true
        }
    }

    if !found {
        ToolTip "Maximum retries exceeded, script exiting"
        SetTimer () => ToolTip(), -1500
        ExitApp
    }
    autto := 0

    loop 60{
    gamghwd := WinExist("ahk_exe" gamefile)
        if gamghwd {
        ToolTip "Game window captured"
        SetTimer () => ToolTip(), -2000
        break
        }
        Sleep 5000
    }
    if !gamghwd{
        ToolTip "Game window not found, restarting"
        SetTimer () => ToolTip(), -1500
        goto re
    }

    Sleep 2000
    WinActivate gamghwd               ; Activate (focus)
    WinMaximize gamghwd               ; Fullscreen
    ;Real mode selection check, remove this when feature is removed later
    found := CheckColorWithRetry(gamghwd,0.0791666666666667,0.8574074074074074,0xFFFFFF,10, 300,2000,false)
    if found{
        ToolTip "Entered main page, starting to check if at character selection screen"
        SendInput "{Space down}"
        Sleep 100
        SendInput "{Space up}"
        ;Enter main page
        ;Check if at character selection screen
        advertisement := true
        foundol := CheckColorWithRetry(gamghwd,0.50234375,0.9361,0x136AFF,20, 60,1000,false)
        found2 :=  CheckColorWithRetry(gamghwd,0.498046875,0.250694,0x136AFF,20, 30,1000,false)
        loop 30{
            if foundol{
                Sleep 1000
                ToolTip "Recovered, watchdog process exiting"
                SetTimer () => ToolTip(), -1500
                numberOfErrors += 1
                RunAutomation()
                return
            }else{
                if found2{
                    SendInput "{Space down}"
                    Sleep 50
                    SendInput "{Space up}"
                    Sleep 500
                }else{
                    advertisement := false
                }
            }
        }
        if !advertisement {
            goto re
        }
    }else{
        Sleep 10000
        goto re
    }
}
;==================================

;Main function
RunAutomation(){
    ToolTip "Starting..."
    SetTimer () => ToolTip(), -1500
    ;============Initialization==================
    global stopLoop
    stopLoop := false
    global adapter
    global gamefile
    global iterationCount
    gameHwnd := WinExist("ahk_exe " gamefile)
    Sleep 500
    ; Get game window handle
    if !gameHwnd {
        MsgBox "Game window not found. Please make sure the game is running`n" gamefile "`n" gameHwnd
        SetTimer () => ToolTip(), -1500
        return
    }
    ;===================================
    while !stopLoop {
        totalRetries := 3
        found := false
        ;Check if on main character
        mainObj := CheckColorWithRetry(gameHwnd,0.50234375,0.936,0x136AFF,30,150,1000,false)
        if mainObj{
            ToolTip "Main character detected, starting character switch"
            SetTimer () => ToolTip(), -1500
            loop totalRetries {
                SendMode "Input"
                Loop 5 {
                    SendInput "{c down}"
                    Sleep 30
                    SendInput "{c up}"
                    Sleep 100
                }
                Sleep 500

                ; Check switch to new character
                found := CheckColorWithRetry(gameHwnd,0.551953125,0.93125,0x136AFF,30,10,200,false)

                if found {
                    ToolTip "Control detected, preparing to disconnect network"
                    SetTimer () => ToolTip(), -1500
                    break   ; Button found, exit outer loop
                }
                ; Not found, wait a moment then retry the entire flow
                Sleep 3000
            }

            if found {
                next:
                Sleep 500
                SendInput "{Space down}"
                Sleep 30
                SendInput "{Space up}"
                ;Select campaign
                Sleep 800
                SendInput "{Space down}"
                Sleep 500
                SendInput "{Space up}"
                Sleep 1000
                ; Disconnect network
                DisableAdapter(adapter)
                foundSecond := CheckColorWithRetry(gameHwnd,0.431640625,0.55625,0x3C3A93,30,300,500,false)
                if foundSecond{
                    ToolTip "Control detected, restoring network"
                    SetTimer () => ToolTip(), -1500
                    ; Restore
                    EnableAdapter(adapter)
                    Sleep 30
                    SendInput "{Space down}"
                    Sleep 100
                    SendInput "{Space up}"
                    Sleep 1000
                    SendInput "{Space down}"
                    Sleep 100
                    SendInput "{Space up}"
                    ;Check switch to main character
                    nextEquipment:
                    foundtheer := CheckColorWithRetry(gameHwnd,0.50234375,0.936,0x136AFF,30,150,1000,false)
                    if foundtheer{
                        ToolTip "Control detected, continuing to dismantle parts on main character"
                        SetTimer () => ToolTip(), -1500
                        Sleep 1000
                        SendInput "{Space down}"
                        Sleep 50
                        SendInput "{Space up}"
                        foundf := CheckColorWithRetry(gameHwnd,0.029296875,0.9263889,0xFFFFFF,30,150,1000,false)
                        if foundf{
                            ToolTip "Control detected, confirmed entry into world, starting movement"
                            SetTimer () => ToolTip(), -2000
                            Sleep 1500
                            Send "{W down}{D down}"
                            Sleep 220
                            Send "{W up}"
                            Sleep 120
                            Send "{D up}"
                            Sleep 200
                            Send "{F down}"
                            Sleep 1800
                            Send "{F up}"
                            ;Enter equipment page
                            Sleep 500
                            equipment := CheckColorWithRetry(gameHwnd,0.725390625,0.240278,0x000000,0,5,500,false)
                            equipmentnd := CheckColorWithRetry(gameHwnd,0.029296875,0.9263889,0xFFFFFF,0,5,100,false)
                            if equipment && !equipmentnd{
                                ToolTip "Confirmed entry to equipment page"
                                SetTimer () => ToolTip(), -2000
                                SendInput "{E down}"
                                Sleep 50
                                SendInput "{E up}"
                                Sleep 100
                                equipment2 := CheckColorWithRetry(gameHwnd,0.68125,0.490278,0x000000,10, 30,500,false)
                                if equipment2 {
                                    ToolTip "Starting to collect weapons"
                                    SetTimer () => ToolTip(), -2000
                                    Sleep 700
                                    SendInput "{D down}"
                                    Sleep 50
                                    SendInput "{D up}"
                                    Sleep 100
                                    SendInput "{W down}"
                                    Sleep 50
                                    SendInput "{W up}"
                                    Sleep 100
                                    SendInput "{Space down}"
                                    Sleep 50
                                    SendInput "{Space up}"
                                    Sleep 1200
                                    SendInput "{X down}"
                                    Sleep 50
                                    SendInput "{X up}"
                                    Sleep 100
                                    SendInput "{S down}"
                                    Sleep 50
                                    SendInput "{S up}"
                                    Sleep 100
                                    SendInput "{Space down}"
                                    Sleep 50
                                    SendInput "{Space up}"
                                    Sleep 300
                                    Loop 4 {
                                        SendInput "{F down}"
                                        Sleep 50
                                        SendInput "{F up}"
                                        Sleep 300
                                    }
                                    Sleep 200
                                    Loop 3{
                                        SendInput "{Q down}"
                                        Sleep 50
                                        SendInput "{Q up}"
                                        Sleep 50
                                    }
                                        Sleep 450
                                        ToolTip "Starting dismantle"
                                        SetTimer () => ToolTip(), -2000
                                        SendInput "{Tab down}"
                                        Sleep 1800
                                        SendInput "{Tab up}"
                                        Sleep 10
                                        SendInput "{ESC down}"
                                        Sleep 1500
                                        SendInput "{ESC up}"
                                        Sleep 100
                                }else{
                                    SendInput "{ESC down}"
                                    Sleep 1500
                                    SendInput "{ESC up}"
                                    Sleep 100
                                }
                            }else{
                                SendInput "{ESC down}"
                                Sleep 50
                                SendInput "{ESC up}"
                                Sleep 500
                                SendInput "{G down}"
                                Sleep 50
                                SendInput "{G up}"
                                Sleep 500
                                SendInput "{Space down}"
                                Sleep 50
                                SendInput "{Space up}"
                                goto nextEquipment
                            }
                            ;Exit
                            SendInput "{ESC down}"
                            Sleep 50
                            SendInput "{ESC up}"
                            Sleep 500
                            Send "{G down}"
                            Sleep 50
                            Send "{G up}"
                            Sleep 500
                            SendInput "{Space down}"
                            Sleep 50
                            SendInput "{Space up}"
                            ToolTip "Preparing to start next cycle"
                            SetTimer () => ToolTip(), -1500
                            ;Confirm return to main screen
                            foundtheer := CheckColorWithRetry(gameHwnd,0.50234375,0.936,0x136AFF,30, 150,1000,false)
                            if foundtheer{
                                iterationCount += 1
                                goto End
                            }else{
                                reboot()
                                return
                            }
                        }else{
                            reboot()
                            return
                        }
                    }else{
                        reboot()
                        return
                    }
                }else{
                    EnableAdapter(adapter)
                    Sleep 10000
                    reboot()
                    return
                }
            } else {
                reboot()
                return
            }
            End:
        }else{
            reboot()
            return
        }
    }
}
;Terminate program
exitkill(){
    global adapter, pbPath
    RunWait 'netsh interface set interface "' adapter '" admin=enable', , "Hide"
    RunWait 'netsh advfirewall firewall delete rule name="BlockGame_Out"', , "Hide"
    RunWait 'netsh advfirewall firewall delete rule name="BlockGame_In"', , "Hide"
    RunWait '*RunAs "' pbPath '" unblockall', , "Hide"
}
;Exit handler
OnExit((*) => exitkill())

F11:: global stopLoop := true
F12:: {
    exitkill()
    ExitApp
}
F10:: RunAutomation()
F9:: reboot()