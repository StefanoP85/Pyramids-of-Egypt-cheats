PRINT "Pyramids of Egypt level viewer"
CONST FileName = "PYRAMIDS.EXE" ' You can specify the path here!
OPEN FileName FOR BINARY AS #1
IF LOF(1) = 0 THEN
  PRINT "Couldn't find PYRAMIDS.EXE!"
  CLOSE #1
  KILL FileName
  END
ELSEIF LOF(1) = 66617 THEN
  PRINT "PYRAMIDS.EXE is compressed! Uncompress it with UNP.EXE."
  END
END IF
PRINT "Press left and right keys to change levels, ESC to exit."
PRINT "Press any key to continue..."
DO
LOOP WHILE INKEY$ = ""

SEEK #1, 16902
DIM Byte AS STRING * 1
DIM Temp(0 TO 15, 0 TO 9) AS INTEGER
DIM Temp2(0 TO 15, 0 TO 9) AS INTEGER
DIM Wall(65) AS INTEGER
DIM WetWall(65) AS INTEGER
DIM DryWall(65) AS INTEGER
DIM DryWallRight(65) AS INTEGER
DIM DryWallLeft(65) AS INTEGER
DIM Diamond(65) AS INTEGER
DIM YellowWall(65) AS INTEGER
DIM Door(65) AS INTEGER
DIM Gas(65) AS INTEGER
DIM Snake(65) AS INTEGER

DEF SEG = &HB800
FOR K% = 0 TO 22
  SCREEN 1
  OUT &H3C6, 0
  IF K% = 22 THEN SEEK #1, 17968
  GET #1, , iks%
  GET #1, , ei%
  FOR Y% = 0 TO 10
    FOR X% = 0 TO 3
      GET #1, , Byte
      POKE Y% * 80 + X%, ASC(Byte)
    NEXT X%
  NEXT Y%
  FOR Y% = 0 TO 9
    FOR X% = 0 TO 15
      Temp(X%, Y%) = POINT(X%, Y% * 2)
      IF Temp(X%, Y%) = 0 THEN Temp2(X%, Y%) = 0
      IF Temp(X%, Y%) = 1 THEN Temp2(X%, Y%) = 12
      IF Temp(X%, Y%) = 2 THEN Temp2(X%, Y%) = 14
      IF Temp(X%, Y%) = 3 THEN Temp2(X%, Y%) = 15
    NEXT X%
  NEXT Y%
  SCREEN 7, , 1, 0
  OUT &H3C6, 0
  FOR Y% = 0 TO 9
    FOR X% = 0 TO 15
      PSET (X%, Y%), Temp2(X%, Y%)
    NEXT X%
  NEXT Y%
  IF K% = 0 THEN GET (0, 0)-(15, 9), WetWall
  IF K% = 1 THEN GET (0, 0)-(15, 9), DryWall
  IF K% = 2 THEN GET (0, 0)-(15, 9), DryWallRight
  IF K% = 3 THEN GET (0, 0)-(15, 9), DryWallLeft
  IF K% = 4 THEN GET (0, 0)-(15, 9), Diamond
  IF K% = 9 THEN GET (0, 0)-(15, 9), YellowWall
  IF K% = 10 THEN GET (0, 0)-(15, 9), Door
  IF K% = 21 THEN GET (0, 0)-(15, 9), Gas
  IF K% = 22 THEN GET (0, 0)-(15, 9), Snake
NEXT K%
DEF SEG
OUT &H3C6, 255
Level% = 1

ShowLevel:
CLS
SEEK #1, 38276 + Level% * 512
FOR X% = 0 TO 19
  FOR Y% = 0 TO 15
    GET #1, , Byte
    IF ASC(Byte) = 1 THEN PUT (X% * 16, Y% * 10), DryWall
    IF ASC(Byte) = 2 THEN PUT (X% * 16, Y% * 10), Diamond
    IF ASC(Byte) = 3 THEN PUT (X% * 16, Y% * 10), Gas
    IF ASC(Byte) = 4 THEN PUT (X% * 16, Y% * 10), WetWall
    IF ASC(Byte) = 5 THEN PUT (X% * 16, Y% * 10), Door
    IF ASC(Byte) = 6 THEN PUT (X% * 16, Y% * 10), DryWallLeft
    IF ASC(Byte) = 7 THEN PUT (X% * 16, Y% * 10), YellowWall
    IF ASC(Byte) = 8 THEN PUT (X% * 16, Y% * 10), Snake
    IF ASC(Byte) = 9 THEN PUT (X% * 16, Y% * 10), DryWallRight
  NEXT Y%
NEXT X%
LINE (0, 160)-(319, 168), 12, BF
LOCATE 23, 1
PRINT "Level:"; Level%
PCOPY 1, 0

DO
  KeyPressed$ = INKEY$
  IF KeyPressed$ = CHR$(0) + "M" THEN
    GOSUB ClearKeyboardBuffer
    IF Level% < 30 THEN
      Level% = Level% + 1
      GOTO ShowLevel
    END IF
  ELSEIF KeyPressed$ = CHR$(0) + "K" THEN
    GOSUB ClearKeyboardBuffer
    IF Level% > 1 THEN
      Level% = Level% - 1
      GOTO ShowLevel
    END IF
  ELSEIF KeyPressed$ = CHR$(27) THEN
    GOTO CloseAndExit
  END IF
LOOP

CloseAndExit:
CLOSE #1
END

ClearKeyboardBuffer:
DEF SEG = &H40
POKE &H1A, PEEK(&H1C)
POKE &H1B, PEEK(&H1D)
DEF SEG
RETURN

