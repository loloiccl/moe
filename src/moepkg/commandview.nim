import terminal, strutils, sequtils, strformat, os
import editorstatus, editorview, ui, unicodeext, fileutils

type
  ExModeViewStatus = tuple[buffer: seq[Rune], prompt: string, cursorY, cursorX, currentPosition, startPosition: int]

const exCommandList = [
  ru"!",
  ru"b",
  ru"bd",
  ru"bfirst",
  ru"blast",
  ru"bnext",
  ru"bprev",
  ru"buf",
  ru"cursorLine",
  ru"e",
  ru"indent",
  ru"linenum",
  ru"livereload",
  ru"ls",
  ru"noh",
  ru"paren",
  ru"q",
  ru"q!",
  ru"qa",
  ru"qa!",
  ru"realtimesearch",
  ru"statusbar",
  ru"syntax",
  ru"tabstop",
  ru"theme",
  ru"vs",
  ru"wq",
  ru"wqa",
]

proc writeMessageOnCommandWindow(cmdWin: var Window, message: string, color: EditorColorPair) =
  cmdWin.erase
  cmdWin.write(0, 0, message, color)
  cmdWin.refresh

proc writeNoWriteError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: No write since last change"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeSaveError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Failed to save the file"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRemoveFileError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: can not remove file"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRemoveDirError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: can not remove directory"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeCopyFileError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: can not copy file"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeFileOpenError*(cmdWin: var Window, fileName: string, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: can not open: " & fileName
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeCreateDirError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: : can not create direcotry"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageDeletedFile*(cmdWin: var Window, filename: string, messageLog: var seq[seq[Rune]]) =
  let mess = "Deleted: " & filename
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeNoFileNameError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: No file name" 
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageYankedLine*(cmdWin: var Window, numOfLine: int, messageLog: var seq[seq[Rune]]) =
  let mess = fmt"{numOfLine} line yanked"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeMessageYankedCharactor*(cmdWin: var Window, numOfChar: int, messageLog: var seq[seq[Rune]]) =
  let mess = fmt"{numOfChar} charactor yanked"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeMessageAutoSave*(cmdWin: var Window, filename: seq[Rune], messageLog: var seq[seq[Rune]]) =
  let mess = fmt"Auto saved {filename}"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeNotEditorCommandError*(cmdWin: var Window, command: seq[seq[Rune]], messageLog: var seq[seq[Rune]]) =
  var cmd = ""
  for i in 0 ..< command.len: cmd = cmd & $command[i] & " "
  let mess = fmt"Error: Not an editor command: {cmd}" 
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageSaveFile*(cmdWin: var Window, filename: seq[Rune], messageLog: var seq[seq[Rune]]) =
  let mess = fmt"Saved {filename}"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc removeSuffix(r: seq[seq[Rune]], suffix: string): seq[seq[Rune]] =
  for i in 0 .. r.high:
    var string = $r[i]
    string.removeSuffix(suffix)
    if i == 0: result = @[string.toRunes]
    else: result.add(string.toRunes)

proc splitQout(s: string): seq[seq[Rune]]=
  result = @[ru""]
  var quotIn = false
  var backSlash = false

  for i in 0 .. s.high:
    if s[i] == '\\':
      backSlash = true
    elif backSlash:
      backSlash = false 
      result[result.high].add(($s[i]).toRunes)
    elif i > 0 and s[i - 1] == '\\':
      result[result.high].add(($s[i]).toRunes)
    elif not quotIn and s[i] == '"':
      quotIn = true
      result.add(ru"")
    elif quotIn and s[i] == '"':
      quotIn = false
      if i != s.high:  result.add(ru"")
    else:
      result[result.high].add(($s[i]).toRunes)

  return result.removeSuffix(" ")

proc splitCommand(command: string): seq[seq[Rune]] =
  if (command).contains('"'):
    return splitQout(command)
  else:
    return strutils.splitWhitespace(command).map(proc(s: string): seq[Rune] = toRunes(s))

proc writeExModeView(commandWindow: var Window, exStatus: ExModeViewStatus, color: EditorColorPair) =
  let buffer = ($exStatus.buffer).substr(exStatus.startPosition, exStatus.buffer.len)

  commandWindow.erase
  commandWindow.write(exStatus.cursorY, 0, fmt"{exStatus.prompt}{buffer}", color)
  commandWindow.moveCursor(0, exStatus.cursorX)
  commandWindow.refresh

proc initExModeViewStatus(prompt: string): ExModeViewStatus =
  result.buffer = ru""
  result.prompt = prompt
  result.cursorY = 0
  result.cursorX = 1

proc moveLeft(commandWindow: Window, exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition > 0:
    dec(exStatus.currentPosition)
    if exStatus.cursorX > exStatus.prompt.len: dec(exStatus.cursorX)
    else: dec(exStatus.startPosition)

proc moveRight(exStatus: var ExModeViewStatus) =
  if exStatus.currentPosition < exStatus.buffer.len:
    inc(exStatus.currentPosition)
    if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
    else: inc(exStatus.startPosition)

proc moveTop(exStatus: var ExModeViewStatus) =
  exStatus.cursorX = exStatus.prompt.len
  exStatus.currentPosition = 0
  exStatus.startPosition = 0

proc moveEnd(exStatus: var ExModeViewStatus) =
  exStatus.currentPosition = exStatus.buffer.len - 1
  if exStatus.buffer.len > terminalWidth():
    exStatus.startPosition = exStatus.buffer.len - terminalWidth()
    exStatus.cursorX = terminalWidth()
  else:
    exStatus.startPosition = 0
    exStatus.cursorX = exStatus.prompt.len + exStatus.buffer.len - 1

proc deleteCommandBuffer(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0:
    if exStatus.buffer.len < terminalWidth(): dec(exStatus.cursorX)
    exStatus.buffer.delete(exStatus.currentPosition - 1, exStatus.currentPosition - 1)
    dec(exStatus.currentPosition)

proc deleteCommandBufferCurrentPosition(exStatus: var ExModeViewStatus) =
  if exStatus.buffer.len > 0 and exStatus.currentPosition < exStatus.buffer.len:
    exStatus.buffer.delete(exStatus.cursorX - 1, exStatus.cursorX - 1)
    if exStatus.currentPosition > exStatus.buffer.len: dec(exStatus.currentPosition)

proc insertCommandBuffer(exStatus: var ExModeViewStatus, c: Rune) =
  exStatus.buffer.insert(c, exStatus.currentPosition)
  inc(exStatus.currentPosition)
  if exStatus.cursorX < terminalWidth() - 1: inc(exStatus.cursorX)
  else: inc(exStatus.startPosition)

proc getKeyword*(status: var EditorStatus, prompt: string): (seq[Rune], bool) =
  var
    exStatus = initExModeViewStatus(prompt)
    cancelSearch = false
  while true:
    writeExModeView(status.commandWindow, exStatus, EditorColorPair.commandBar)

    var key = getKey(status.commandWindow)

    if isEnterKey(key): break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize()
      status.update
    elif isLeftKey(key): moveLeft(status.commandWindow, exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key): deleteCommandBuffer(exStatus)
    elif isDcKey(key): deleteCommandBufferCurrentPosition(exStatus)
    else: insertCommandBuffer(exStatus, key)

  return (exStatus.buffer, cancelSearch)

proc getKeyOnceAndWriteCommandView*(status: var Editorstatus, prompt: string, buffer: seq[Rune]): (seq[Rune], bool, bool) =
  var
    exStatus = initExModeViewStatus(prompt)
    exitSearch = false
    cancelSearch = false
  for rune in buffer: exStatus.insertCommandBuffer(rune)

  while true:
    writeExModeView(status.commandWindow, exStatus, EditorColorPair.commandBar)

    var key = getKey(status.commandWindow)
    if isEnterKey(key):
      exitSearch = true
      break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize()
      status.update
    elif isLeftKey(key): moveLeft(status.commandWindow, exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key):
      deleteCommandBuffer(exStatus)
      break
    elif isDcKey(key):
      deleteCommandBufferCurrentPosition(exStatus)
      break
    else:
      insertCommandBuffer(exStatus, key)
      break

  writeExModeView(status.commandWindow, exStatus, EditorColorPair.commandBar)
  return (exStatus.buffer, exitSearch, cancelSearch)

proc suggestFilePath(exStatus: var ExModeViewStatus, cmdWin: var Window, key: var Rune) =
  var
    suggestIndex = 0
    suggestlist: seq[seq[Rune]] = @[]
  let inputPath = ($exStatus.buffer).substr(2)
  if inputPath.len == 0 or not inputPath.contains("/"):
    for kind, path in walkDir("./"):
      if ($path.toRunes.normalizePath).startsWith(inputPath): suggestlist.add(path.toRunes.normalizePath)
  elif ($inputPath).contains("/"):
    for kind, path in walkDir(($inputPath).substr(0, ($inputPath).rfind("/"))):
      if ($path.toRunes.normalizePath).startsWith(inputPath): suggestlist.add(path.toRunes.normalizePath)

  while isTabkey(key) and suggestlist.len > 0:
    exStatus.buffer = ru"e "
    exStatus.currentPosition = 2
    exStatus.cursorX = 3

    for rune in suggestlist[suggestIndex]: exStatus.insertCommandBuffer(rune)
    if suggestlist.len == 1:
      key = ru'/'
      return 
    writeExModeView(cmdWin, exStatus, EditorColorPair.commandBar)

    if suggestIndex < suggestlist.high: inc(suggestIndex)
    else: suggestIndex = 0

    key = getKey(cmdWin)

proc isExCommand(exBuffer: seq[Rune]): bool =
  result = false
  for i in 0 ..< exCommandList.len:
    if ($exBuffer).startsWith($exCommandList[i]):
      result = true
      break

proc suggestExCommandOption(exStatus: var ExModeViewStatus, cmdWin: var Window, key: var Rune) =
  var
    suggestIndex = 0
    suggestlist: seq[seq[Rune]] = @[]
    argList: seq[string] = @[]

  let
    command = (strutils.splitWhitespace($exStatus.buffer))[0]
    arg = if (strutils.splitWhitespace($exStatus.buffer)).len > 1: (strutils.splitWhitespace($exStatus.buffer))[1] else: ""

  case command:
    of "cursorLine", "indent", "linenum", "livereload", "realtimesearch", "statusbar", "syntax", "tabstop": argList = @["on", "off"]
    of "theme": argList= @["vivid", "dark", "light", "config"]
    of "e": suggestFilePath(exStatus, cmdWin, key)
    else: discard

  for i in 0 ..< argList.len:
    if argList[i].startsWith(arg): suggestlist.add(argList[i].toRunes)

  while isTabkey(key) and suggestlist.len > 0:
    exStatus.currentPosition = 0
    exStatus.cursorX = 1
    exStatus.buffer = ru""

    for rune in command.toRunes & ru' ':exStatus.insertCommandBuffer(rune)
    for rune in suggestlist[suggestIndex]: exStatus.insertCommandBuffer(rune)
    writeExModeView(cmdWin, exStatus, EditorColorPair.commandBar)

    if suggestIndex < suggestlist.high: inc(suggestIndex)
    else: suggestIndex = 0

    key = getKey(cmdWin)

proc suggestExCommand(exStatus: var ExModeViewStatus, cmdWin: var Window, key: var Rune) =

  var
    suggestIndex = 0
    suggestlist: seq[seq[Rune]] = @[]
  for runes in exCommandList:
    if exStatus.buffer.startsWith(runes): suggestlist.add(runes)

  while isTabkey(key) and suggestlist.len > 0:
    exStatus.buffer = ru""
    exStatus.currentPosition = 0
    exStatus.cursorX = 1

    for rune in suggestlist[suggestIndex]: exStatus.insertCommandBuffer(rune)
    writeExModeView(cmdWin, exStatus, EditorColorPair.commandBar)

    if suggestIndex < suggestlist.high: inc(suggestIndex)
    else: suggestIndex = 0

    key = getKey(cmdWin)

proc suggestMode(status: var Editorstatus, exStatus: var ExModeViewStatus, key: var Rune) =
 
  if exStatus.buffer.len > 0 and exStatus.buffer.isExCommand: exStatus.suggestExCommandOption(status.commandWindow, key)
  else: suggestExCommand(exStatus, status.commandWindow, key)
  
proc getCommand*(status: var EditorStatus, prompt: string): seq[seq[Rune]] =
  var exStatus = initExModeViewStatus(prompt)
  status.resize()

  while true:
    writeExModeView(status.commandWindow, exStatus, EditorColorPair.commandBar)

    var key = getKey(status.commandWindow)

    if isTabkey(key): suggestMode(status, exStatus, key)

    if isEnterKey(key): break
    elif isEscKey(key):
      status.commandWindow.erase
      return @[ru""]
    elif isResizeKey(key):
      status.resize()
      status.update
    elif isLeftKey(key): moveLeft(status.commandWindow, exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key): deleteCommandBuffer(exStatus)
    elif isDcKey(key): deleteCommandBufferCurrentPosition(exStatus)
    else: insertCommandBuffer(exStatus, key)

  return splitCommand($exStatus.buffer)
