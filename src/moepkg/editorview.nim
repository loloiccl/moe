import deques, strutils, math, strformat
import gapbuffer, ui, unicodeext, highlight, independentutils

type EditorView* = object
  height*, width*, widthOfLineNum*: int
  lines*: Deque[seq[Rune]]
  originalLine*, start*, length*: Deque[int]
  updated*: bool

type ViewLine = object
  line: seq[Rune]
  originalLine, start, length: int

proc loadSingleViewLine[T](view: EditorView, buffer: T, originalLine, start: int): ViewLine =
  result.line = ru""
  result.originalLine = originalLine
  result.start = start
  let bufferLine = buffer[originalLine]
  template isRemaining: bool = start+result.length < bufferLine.len
  template calcNextWidth: int =
    if isRemaining(): unicodeext.width(bufferLine[start+result.length]) else: 0
  var
    totalWidth = 0
    nextWidth = calcNextWidth()
  while isRemaining() and totalWidth+nextWidth <= view.width:
    result.line.add(bufferLine[start+result.length])
    result.length.inc
    totalWidth += nextWidth
    nextWidth = calcNextWidth

proc reload*[T](view: var EditorView, buffer: T, topLine: int) =
  ## topLineがEditorViewの一番上のラインとして表示されるようにバッファからEditorViewに対してリロードを行う.
  ## EditorView全体を更新するため計算コストはやや高め.バッファの内容とEditorViewの内容を同期させる時やEditorView全体が全く異なるような内容になるような処理をした後等に使用することが想定されている.

  view.updated = true

  let
    height = view.height
    width = view.width

  const empty = ru""
  for x in view.originalLine.mitems: x = -1
  for s in view.lines.mitems: s = empty
  for x in view.length.mitems: x = 0

  var
    lineNumber = topLine
    start = 0
  for y in 0 ..< height:
    if lineNumber >= buffer.len: break
    if buffer[lineNumber].len == 0:
      view.originalLine[y] = lineNumber
      view.start[y] = 0
      view.length[y] = 0
      inc(lineNumber)
      continue

    let singleLine = loadSingleViewLine(view, buffer, lineNumber, start)
    view.lines[y] = singleLine.line
    view.originalLine[y] = singleLine.originalLine
    view.start[y] = singleLine.start
    view.length[y] = singleLine.length

    start += view.length[y]
    if start >= buffer[lineNumber].len:
      inc(lineNumber)
      start = 0

proc initEditorView*[T](buffer: T, height, width: int): EditorView =
  ## width/heightでEditorViewを初期化し,バッファの0行0文字目からロードする.widthは画面幅ではなくEditorViewの1ラインの文字数である(従って行番号分の長さは考慮しなくてよい).

  result.height = height
  result.width = width
  result.widthOfLineNum = buffer.len.intToStr.len+1

  result.lines = initDeque[seq[Rune]]()
  for i in 0..height-1: result.lines.addLast(ru"")

  result.originalLine = initDeque[int]()
  for i in 0..height-1: result.originalLine.addLast(-1)
  result.start = initDeque[int]()
  for i in 0..height-1: result.start.addLast(-1)
  result.length = initDeque[int]()
  for i in 0..height-1: result.length.addLast(-1)

  result.reload(buffer, 0)

proc resize*[T](view: var EditorView, buffer: T, height, width, widthOfLineNum: int) =
  ## 指定されたwidth/heightでEditorViewを更新する.表示される部分はなるべくリサイズ前と同じになるようになっている.

  let topline = view.originalLine[0]

  view.lines = initDeque[seq[Rune]]()
  for i in 0..height-1: view.lines.addlast(ru"")

  view.height = height
  view.width = width
  view.widthOfLineNum = widthOfLineNum

  view.originalLine = initDeque[int]()
  for i in 0..height-1: view.originalLine.addlast(-1)
  view.start = initDeque[int]()
  for i in 0..height-1: view.start.addlast(-1)
  view.length = initDeque[int]()
  for i in 0..height-1: view.length.addlast(-1)

  view.updated = true
  view.reload(buffer, topLine)

proc scrollUp*[T](view: var EditorView, buffer: T) =
  ## EditorView表示を1ライン上にずらす

  view.updated = true

  view.lines.popLast
  view.originalLine.popLast
  view.start.popLast
  view.length.popLast

  var originalLine, last: int
  if view.start[0] > 0:
    originalLine = view.originalLine[0]
    last = view.start[0]-1
  else:
    originalLine = view.originalLine[0]-1
    last = buffer[originalLine].high

  var start = 0
  while true:
    let singleLine = loadSingleViewLine(view, buffer, originalLine, start)
    start += singleLine.length
    if start > last:
      view.lines.addFirst(singleLine.line)
      view.originalLine.addFirst(singleLine.originalLine)
      view.start.addFirst(singleLine.start)
      view.length.addFirst(singleLine.length)
      break

proc scrollDown*[T](view: var EditorView, buffer: T) =
  ## EditorViewの表示を1ライン下にずらす

  view.updated = true

  let height = view.height
  view.lines.popFirst
  view.originalLine.popFirst
  view.start.popFirst
  view.length.popFirst
  
  var originalLine, start: int
  if view.start[height-2]+view.length[height-2] == buffer[view.originalLine[height-2]].len:
    originalLine =  if view.originalLine[height-2] == -1 or view.originalLine[height-2]+1 == buffer.len: -1 else: view.originalLine[height-2]+1
    start = 0
  else:
    originalLine = view.originalLine[height-2]
    start = view.start[height-2]+view.length[height-2]
    
  if originalLine == -1:
    view.lines.addLast(ru"")
    view.originalLine.addLast(-1)
    view.start.addLast(0)
    view.length.addLast(0)
  else:
    let singleLine = loadSingleViewLine(view, buffer, originalLine, start)
    view.lines.addLast(singleLine.line)
    view.originalLine.addLast(singleLine.originalLine)
    view.start.addLast(singleLine.start)
    view.length.addLast(singleLine.length)

proc writeLineNum(view: EditorView, win: var Window, y, line: int, colorPair: EditorColorPair) =
  win.write(y, 0, strutils.align($(line+1), view.widthOfLineNum-1), colorPair, false)

proc write(view: EditorView, win: var Window, y, x: int, str: seq[Rune], color: EditorColorPair) =
  # TODO: use settings file
  const tab = "    "
  win.write(y, x, ($str).replace("\t", tab), color, false)

proc writeAllLines*[T](view: var EditorView, win: var Window, lineNumber, currentLineNumber, cursorLine, currentWin, isVisualMode: bool, buffer: T, highlight: Highlight, currentLine, startSelectedLine, endSelectedLine: int) =
  win.erase
  view.widthOfLineNum = if lineNumber: buffer.len.numberOfDigits + 1 else: 0

  let
    start = (view.originalLine[0], view.start[0])
    useHighlight = highlight.len > 0 and (highlight[0].firstRow, highlight[0].firstColumn) <= start and start <= (highlight[^1].firstRow, highlight[^1].firstColumn)
  var i = if useHighlight: highlight.index(view.originalLine[0], view.start[0]) else: -1
  for y in 0 ..< view.height:
    if view.originalLine[y] == -1: break

    let isCurrentLine = view.originalLine[y] == currentLine
    if lineNumber and view.start[y] == 0:
      view.writeLineNum(win, y, view.originalLine[y], if isCurrentLine and currentWin and currentLineNumber: EditorColorPair.currentLineNum else: EditorColorPair.lineNum)

    var x = view.widthOfLineNum
    if view.length[y] == 0:
      if isVisualMode and (view.originalLine[y] >= startSelectedLine and endSelectedLine >= view.originalLine[y]):
        view.write(win, y, x, ru" ", EditorColorPair.visualMode)
      else: view.write(win, y, x, view.lines[y], EditorColorPair.defaultChar)
      continue

    while i < highlight.len and highlight[i].firstRow < view.originalLine[y]: inc(i)
    while i < highlight.len and highlight[i].firstRow == view.originalLine[y]:
      if (highlight[i].firstRow, highlight[i].firstColumn) > (highlight[i].lastRow, highlight[i].lastColumn) : break # skip an empty segment
      let
        first = max(highlight[i].firstColumn-view.start[y], 0)
        last = min(highlight[i].lastColumn-view.start[y], view.lines[y].high)

      if first > last: break
      
      block:
        let
          firstStr = $first
          lastStr = $last
          lineStr = $view.lines[y]
        assert(last <= view.lines[y].high, fmt"last = {lastStr}, view.lines[y] = {lineStr}")
        assert(first <= last, fmt"first = {first}, last = {last}")
      
      let str = view.lines[y][first .. last]
      if isCurrentLine and cursorLine:
        win.attron(Attributes.underline)
        view.write(win, y, x, str, highlight[i].color)
        win.attroff(Attributes.underline)
      else: view.write(win, y, x, str, highlight[i].color)
      x += width(str)
      if last == highlight[i].lastColumn - view.start[y]: inc(i) # consumed a whole segment
      else: break

  win.refresh

proc update*[T](view: var EditorView, win: var Window, lineNumber, currentLineNumber, cursorLine, currentWin, isVisualMode: bool, buffer: T, highlight: Highlight, currentLine, startSelectedLine, endSelectedLine: int) =
  let widthOfLineNum = buffer.len.intToStr.len + 1
  if lineNumber and widthOfLineNum != view.widthOfLineNum: view.resize(buffer, view.height, view.width + view.widthOfLineNum - widthOfLineNum, widthOfLineNum)
  view.writeAllLines(win, lineNumber, currentLineNumber, cursorLine, currentWin, isVisualMode, buffer, highlight, currentLine, startSelectedLine, endSelectedLine)
  view.updated = false

proc seekCursor*[T](view: var EditorView, buffer: T, currentLine, currentColumn: int) =
  while currentLine < view.originalLine[0] or (currentLine == view.originalLine[0] and view.length[0] > 0 and currentColumn < view.start[0]): view.scrollUp(buffer)
  while (view.originalLine[view.height - 1] != -1 and currentLine > view.originalLine[view.height - 1]) or (currentLine == view.originalLine[view.height - 1] and view.length[view.height - 1] > 0 and currentColumn >= view.start[view.height - 1]+view.length[view.height - 1]): view.scrollDown(buffer)
