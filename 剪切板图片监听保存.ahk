;;AutoHotkey 2.0

#Include ImagePut.ahk
#Hotif WinActive("ahk_class CabinetWClass")  ;;这个热键只在资源管理器中(即文件夹目录)有效
#Hotif

;============================================================
; 剪贴板图片监听保存脚本说明
; 作用：
; 1. 监听系统剪贴板变化。
; 2. 当剪贴板中为图片时，自动保存到当前资源管理器目录或脚本目录。
; 3. 当剪贴板中为 URL / 文件路径 / 文本时，识别图片链接并保存，
;    其余内容追加到剪切板记录.txt，方便后续查看。
; 4. 通过 Utf-8 编码处理，避免中文日志乱码。
;============================================================
;2026-9-28

; 强制只允许一个脚本实例运行，避免重复监听导致重复保存或重复日志写入。
#singleinstance force

; 剪贴板发生变化时调用 addimge() 处理，统一入口用于后续判断处理逻辑。
OnClipboardChange addimge

; 启动提示：告知脚本已启动，减少排查时误判为“没有运行”。
ShowStatus("剪贴板图片监听已启动", 1500)
return
;============================================================
; 核心入口：处理剪贴板变化事件
; 参数 s 表示剪贴板变化类型；
; 目前主要用于判断是否是多行文本输入/替换，以便按行拆分处理。
;============================================================
addimge(s) {
    if !s
        return

    try {
        if ClipboardHasImage() {
            SaveClipboardImage()
            return
        }

        clipboardText := Trim(A_Clipboard)
        if clipboardText = ""
            return

        sources := s = 2 ? StrSplit(clipboardText, "`n", "`r") : [clipboardText]
        savedCount := 0
        textItems := []
        for source in sources {
            source := Trim(source, " `t`r`n" Chr(34))
            if source = ""
                continue

            extension := ImageExtension(source)
            isUrl := RegExMatch(source, "i)^https?://\S+$")
            isExistingFile := FileExist(source) && !InStr(FileExist(source), "D")
            if extension != "" && (isUrl || isExistingFile) {
                savePath := GetSaveDirectory() "\剪贴图片_" A_Now "_" A_TickCount "_" (savedCount + 1) ".png"
                ImagePutFile(source, savePath)
                savedCount++
            } else {
                textItems.Push(source)
            }
        }

        if textItems.Length
            AppendClipboardText(textItems, s = 2)

        if savedCount
            ShowStatus("图片已保存，共 " savedCount " 张。")
        else if textItems.Length
            ShowStatus("文本已追加到剪切板记录.txt")
    } catch as err {
        ShowStatus("处理剪切板失败：" err.Message, 8000)
    }
}

;============================================================
; 检测当前剪贴板是否为图片格式
; 通过 Windows 剪贴板格式枚举判断，常见图片格式包括 PNG / DIB / BMP 等。
;============================================================
ClipboardHasImage() {
    pngFormat := DllCall("RegisterClipboardFormat", "str", "png", "uint")
    return DllCall("IsClipboardFormatAvailable", "uint", pngFormat)
        || DllCall("IsClipboardFormatAvailable", "uint", 8)
        || DllCall("IsClipboardFormatAvailable", "uint", 17)
        || DllCall("IsClipboardFormatAvailable", "uint", 2)
}

;============================================================
; 保存当前剪贴板中的图片
; 这里用 ClipboardAll() 保留图片的完整格式数据，然后保存为 PNG 文件。
; 这样可以确保截图、复制图片等内容都能正常导出到文件中。
;============================================================
SaveClipboardImage() {
    savePath := GetSaveDirectory() "\剪切图片_" A_Now "_" A_TickCount ".png"
    ImagePutFile(ClipboardAll(), savePath)
    ShowStatus("图片已保存：`n" savePath)
}

;============================================================
; 识别字符串中的图片扩展名
; 例如：
;   "C:\\folder\\a.jpg" -> "jpg"
;   "https://xx.com/pic.png?x=1" -> "png"
;============================================================
ImageExtension(source) {
    sourcePath := RegExReplace(source, "[?#].*$")
    if RegExMatch(sourcePath, "i)\.(png|jpe?g|gif|bmp|tiff?|webp)$", &match)
        return StrLower(match[1])
    return ""
}

;============================================================
; 将文本内容追加到日志文件中
; isFileList 为 true 时，日志前缀会显示为 “文件路径”，
; 否则显示为 “文本”，方便区分不同来源。
;============================================================
AppendClipboardText(items, isFileList := false) {
    logPath := A_ScriptDir "\剪切板记录.txt"
    outputPath := logPath

    ; 若记录文件不是 UTF-8，则追加到旧编码日志文件，保留历史内容。
    if !EnsureUtf8Log(logPath) {
        outputPath := LegacyLogPath()
    }

    outputFile := outputPath = logPath
        ? FileOpen(logPath, "a", "UTF-8-RAW")
        : FileOpen(outputPath, "a")
    if !outputFile
        throw Error("无法打开剪切板记录文件：" outputPath)

    try {
        for item in items {
            prefix := isFileList ? "文件路径" : "文本"
            outputFile.Write("[" prefix "] " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n" item "`n------------------------------`n")
        }
    } finally {
        outputFile.Close()
    }
}

;============================================================
; 确保记录文件是 UTF-8 编码，避免中文乱码
; 如果目标文件存在但不是 UTF-8，则返回 false，并让调用方追加到
; “剪切板记录_旧编码_当前日期_周几.txt” 文件中，保留历史内容。
;============================================================
EnsureUtf8Log(logPath) {
    if FileExist(logPath) {
        inputFile := FileOpen(logPath, "r", "UTF-8-RAW")
        if !inputFile
            throw Error("无法检查剪切板记录文件编码。")

        bom := Buffer(3, 0)
        byteCount := inputFile.RawRead(bom, 3)
        inputFile.Close()
        hasUtf8Bom := byteCount = 3
            && NumGet(bom, 0, "uchar") = 0xEF
            && NumGet(bom, 1, "uchar") = 0xBB
            && NumGet(bom, 2, "uchar") = 0xBF

        if !hasUtf8Bom {
            return false
        }

        return true
    }

    outputFile := FileOpen(logPath, "w", "UTF-8-RAW")
    if !outputFile
        throw Error("无法创建剪切板记录文件：" logPath)
    try {
        bom := Buffer(3, 0)
        NumPut("uchar", 0xEF, bom, 0)
        NumPut("uchar", 0xBB, bom, 1)
        NumPut("uchar", 0xBF, bom, 2)
        outputFile.RawWrite(bom)
    } finally {
        outputFile.Close()
    }

    return true
}

; 生成旧编码日志文件名，格式示例：
; 剪切板记录_旧编码_2026_09_29_周二.txt
LegacyLogPath() {
    datePart := FormatTime(, "yyyy_MM_dd")
    weekdayPart := FormatTime(, "ddd")
    switch weekdayPart {
        case "Mon": weekdayPart := "周一"
        case "Tue": weekdayPart := "周二"
        case "Wed": weekdayPart := "周三"
        case "Thu": weekdayPart := "周四"
        case "Fri": weekdayPart := "周五"
        case "Sat": weekdayPart := "周六"
        case "Sun": weekdayPart := "周日"
    }
    return A_ScriptDir "\剪切板记录_旧编码_" datePart "_" weekdayPart ".txt"
}

;============================================================
; 获取适合保存图片的目录
; 优先返回当前活动资源管理器窗口对应的目录，
; 如果无法获取，则回退到脚本所在目录。
;============================================================
GetSaveDirectory() {
    try return biaoti()
    catch
        return A_ScriptDir
}

;============================================================
; 状态提示函数
; 用于在屏幕上悬浮显示提示信息，例如启动成功、保存成功、失败原因等。
;============================================================
ShowStatus(message, duration := 5000) {
    ToolTip message
    SetTimer ClearStatus, -duration
}

; 清理提示框，避免提示一直停留在屏幕上。
ClearStatus() {
    ToolTip()
}

;============================================================
; 获取当前活动资源管理器窗口对应的真实文件夹路径
; 这里通过 Shell.Application.Windows 逐个检查资源管理器窗口，
; 找到与当前活动窗口对应的目录，然后返回该目录，
; 这样图片会保存到当前文件夹，而不是固定写到脚本目录。
;============================================================
biaoti() {
    activeHwnd := WinExist("A")
    for explorerWindow in ComObject("Shell.Application").Windows {
        try {
            if explorerWindow.HWND = activeHwnd {
                folderPath := explorerWindow.Document.Folder.Self.Path
                if DirExist(folderPath)
                    return folderPath
            }
        }
    }
    throw Error("无法获取当前资源管理器目录。")
}
/*
ImagePutFile(Image)       ; 将图片存为文件
ImagePutClipboard(Image)  ; 将图片存入剪贴板
ImagePutWindow(Image)     ; 将图片显示出来
ImageShow(Image)          ; 将图片显示出来（无标题栏）
ImagePutBase64(Image)     ; 将图片转换为 base64 编码后的字符串
ImagePutURI(Image)        ; 将图片转换为 base64 编码后的字符串（带 URI 头）
ImagePutHex(Image)        ; 将图片转换为 16进制 编码后的字符串
ImagePutWallpaper(Image)  ; 将图片设为桌面壁纸
ImagePutDesktop(Image)    ; 将图片放在桌面壁纸前、桌面图标后的位置
ImagePutCursor(Image)     ; 将图片设为鼠标样式
ImageEqual(Images*)       ; 比较多张图片是否相同
ImageWidth(Image)         ; 返回图片宽度
ImageHeight(Image)        ; 返回图片高度
*/

/*
#HotIf WinActive("ahk_class CabinetWClass")
!n::  ;;这个热键只在资源管理器中有效
{
   标题 := WinGetTitle("A")
   时间 := %A_Now%  ;A_MM A_DD A_Hour A_Min A_Sec
   ;MsgBox(A_MM A_DD A_Hour A_Min A_Sec)
   ;MsgBox "这个 Control+Alt+C 组合键只在 Notepad2 中有效"
   FileAppend  "耳聪目明`n心情愉悦`n", 标题 "\" 时间 ".txt"
}
#HotIf
Return
*/
/*
标题1 := WinGetTitle("A")
类 := WinGetClass("A")
MsgBox Format("标题是: {1}`n类是: {2}", 标题1, 类)
if WinExist("ahk_class Notepad2")  ;;WinExist 判断指点窗口是否存在
    WinActivate  ;;激活找到的窗口
    MsgBox "The text is:`n" WinGetText()  ;;WinGetText() 获取里面的所有内容
exitapp
#HotIf WinActive("ahk_class Notepad2")
^!c::MsgBox "这个 Control+Alt+C 组合键只在 Notepad2 中有效"
#HotIf WinActive("ahk_class OpusApp")
^!c::MsgBox "这个 Control+Alt+C 组合键只在 Word 中有效"
#HotIf

Return
*/
