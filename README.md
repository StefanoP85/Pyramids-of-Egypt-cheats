# Pyramids-of-Egypt-cheats
Some utility for the game Pyramids of Egypt by John Romero (1987)

The game Pyramids of Egypt was developed by John Romero for the Apple II, and then ported to PC in year 1990, by Ideas From the Deep (the future ID Software) for Softdisk Publishing.
The game is very simple, and in less than 100 KB it contains both game logic, other code and data, including levels and graphics.
The goal is simple: you control Mike the Explorer as he makes his way through the treacherous Pyramids of Egypt, collecting diamonds and avoiding snakes.
You can find a reference here: https://rome.ro/subnodule.

The game is very hard; I used some debugging in real mode software, using Turbo Debugger, and I found out how to cheat, becoming invulnerable to the snakes.
The cheat is a "patcher program": a program written in Turbo Pascal, with some assembly routines, that loads the game into memory, patch a single instruction,
a RET instruction, with hex code C3, in the right place, and that bypasses the collision detection.
I created also a QBasic program, that displays the 30 levels of the game.
