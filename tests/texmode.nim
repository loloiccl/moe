import terminal, unittest
import moepkg/editorstatus, moepkg/exmode, moepkg/unicodeext, moepkg/gapbuffer

test "Change theme command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  status.resize(terminalHeight(), terminalWidth())
  
  block:
    const command = @[ru"theme", ru"vivid"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"dark"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"light"]
    status.exModeCommand(command)

  block:
    const command = @[ru"theme", ru"config"]
    status.exModeCommand(command)
