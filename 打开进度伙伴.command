#!/bin/zsh
cd "${0:A:h}"
if [[ -x "/Applications/Questlog.app/Contents/MacOS/Questlog" ]]; then
  open "/Applications/Questlog.app"
  exit
fi
if [[ -x "$HOME/Applications/Questlog.app/Contents/MacOS/Questlog" ]]; then
  open "$HOME/Applications/Questlog.app"
  exit
fi
if [[ ! -x "Questlog.app/Contents/MacOS/Questlog" ]]; then
  python3 build_app.py || exit 1
fi
open "Questlog.app"
