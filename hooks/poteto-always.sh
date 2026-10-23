#!/bin/sh
# Pin poteto-mode on for every session, like Cursor's custom mode. On in headless runs too; PSTACK_POTETO=off is an escape hatch that skips it.
[ "$PSTACK_POTETO" = off ] && exit 0
skill=$(realpath "$(dirname "$0")/../skills/poteto-mode/SKILL.md")
printf 'poteto-mode is always on in this session, as if the user typed /poteto-mode before every message. Follow the skill below on every turn. Its file is %s; resolve its relative links from there, and read that file in full if the text below is cut off. If you are a delegate working from a brief, ignore this and follow the brief. The user turns it off for the session with "poteto-mode off".\n\n' "$skill"
cat "$skill"
