import unittest
import moepkg/editorstatus, moepkg/exmode, moepkg/unicodeext

test "Change theme command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])
  
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
