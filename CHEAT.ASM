IDEAL
P286
JUMPS
LOCALS
MODEL SMALL, PASCAL

MACRO MakeCString Id, Msg
  IFB <Id>
    DISPLAY "Must specify the Id of string in MakeCString"
    ERR
  ELSE
    IFB <Msg>
      DISPLAY "Must specify the Msg in MakeCString"
      ERR
    ELSE
      Id DB &Msg&
      DB 0
    ENDIF
  ENDIF
ENDM  MakeCString
MACRO MakePascalString Id, Msg
  LOCAL EndStr
  IFB <Id>
    DISPLAY "Must specify the Id of string in MakePascalString"
    ERR
  ELSE
    IFB <Msg>
      DISPLAY "Must specify the Msg in MakePascalString"
      ERR
    ELSE
      Id DB EndStr - Id - 1, &Msg&
      LABEL EndStr BYTE
    ENDIF
  ENDIF
ENDM  MakePascalString

; Valid .EXE files have the ID field set to this magic value. In string
; form, this reads 'MZ', which is apparently the initials of Mark
; Zbikowski, one of the designers behind MS-DOS 2.0 way back in 1983.
ValidEXESignature   = 5A4Dh
CProgramFileSpec    EQU 'PYRAMIDS.EXE'

; .EXE file header structure
STRUC TEXEHeader
  ID               DW ? ; Signature field, must be $5A4D
  ImageLengthLow   DW ? ; File length modulo 512
  ImageLengthHigh  DW ? ; File length divided by 512, rounded up
  NumRelocs        DW ? ; Number of relocation entries
  HeaderSize       DW ? ; Size of header divided by 16
  MinParagraphs    DW ? ; Min # of paragraphs needed to run program
  MaxParagraphs    DW ? ; Desired # of paragraps program would like
  InitSS           DW ? ; Initial stack segment offset
  InitSP           DW ? ; Initial SP register value
  Checksum         DW ? ; Checksum of header, or zero
  InitIP           DW ? ; Initial code entry point offset
  InitCS           DW ? ; Initial code segment offset
  FirstRelocOffset DW ? ; Offset in header of relocation table
  OverlayNumber    DW ? ; Overlay number, zero for main program
ENDS  TEXEHeader
; Structure required for DOS INT 21H/4BH Exec call
STRUC TProgramExec
  ; Segment of environment block to inherit for child process
  Environment  DW ?
  ; Pointer to command line arguments for child process
  CommandLine  DD ?
  ; Pointer to FCB structures for child process
  FCB0         DD ?
  FCB1         DD ?
  ; Contains the initial SS:SP of the child process on return
  StackPointer DD ?
  ; Contains the initial CS:IP of the child process on return
  CodePointer  DD ?
ENDS  TProgramExec

STACK

DATASEG
  MakeCString ProgramFileSpec, CProgramFileSpec

UDATASEG
  DOSError       DW ?
  PrefixSeg      DW ?
  SaveSS         DW ?
  SaveSP         DW ?
  SaveBP         DW ?
  ChildPrefixSeg DW ?
  CodePointer    DD ?
  StackPointer   DD ?
  PatchPointer   DD ?

CODESEG
; Returns load image size for given executable file, 0 if not a valid .EXE.
; FileName contains the file name of the executable file to examine.
PROC  GetLoadImageSize
LOCAL @@EXEHeader:TEXEHeader ; Stores the .EXE file header
LOCAL @@InputFile:WORD ; Input file handle
  ; Open files for reading only
  MOV  AX, 3D00h
  LEA  DX, [ProgramFileSpec]
  INT  21h
  JC   @@ErrorOpening
  MOV  [@@InputFile], AX
  ; Read the header
  PUSH DS
  MOV  DX, SS
  MOV  DS, DX
  MOV  AH, 3Fh
  MOV  BX, [@@InputFile]
  MOV  CX, SIZE TEXEHeader
  LEA  DX, [@@EXEHeader]
  INT  21h
  POP  DS
  ; Check if the header read operation succeeded
  JC   @@ErrorReading
  ; Check if the ID field matches the required magic value
  CMP  [@@EXEHeader.ID], ValidEXESignature
  JNE  @@ErrorReading
  ; Compute the size of the .EXE file image. This is done by
  ; obtaining the supposed file length from the .EXE header
  ; and subtracting the length of the header from it.
  MOV  CX, 512
  MOV  AX, [@@EXEHeader.ImageLengthHigh]
  DEC  AX
  IMUL CX
  ADD  AX, [@@EXEHeader.ImageLengthLow]
  ADC  DX, 0
  MOV  CX, [@@EXEHeader.HeaderSize]
  SHL  CX, 4
  SUB  AX, CX
  SBB  DX, 0
  JMP  @@ExitFunction
@@ErrorReading:
  MOV  AH, 3Eh
  MOV  BX, [@@InputFile]
  INT  21h
@@ErrorOpening:
  MOV  AX, 0
  MOV  DX, 0
@@ExitFunction:
  RET
ENDP  GetLoadImageSize
; Loads executable into memory but does not execute. Returns pointers to
; image start, code entry point and initial stack location in BasePtr, CodePtr
; and StackPtr respectively. FileName contains the file name of the executable
; file to load. CommandLine contains the command line arguments to supply
; to the executable.
PROC  LoadExecutable
LOCAL @@ProgramExec:TProgramExec
  MOV  BX, [PrefixSeg]
  MOV  [@@ProgramExec.Environment], 0
  MOV  [WORD LOW  @@ProgramExec.CommandLine], 0
  MOV  [WORD HIGH @@ProgramExec.CommandLine], 0
  MOV  [WORD LOW  @@ProgramExec.FCB0], 005Ch
  MOV  [WORD HIGH @@ProgramExec.FCB0], BX
  MOV  [WORD LOW  @@ProgramExec.FCB1], 006Ch
  MOV  [WORD HIGH @@ProgramExec.FCB1], BX
  ; Load executable as child process into memory, but do not execute.
  ; This is done using DOS interrupt 21H, service 4BH, subservice 01H
  ; (load but don't execute). DS:DX points to the executable file name as
  ; a null-terminated string. ES:BX points to the ProgramExec structure
  ; that contains the command line arguments, environment block and FCB
  ; structures for the child process, and will contain the initial entry
  ; point and stack location of the child process on return. When the
  ; call returns, the carry flag will be set if an error occured. If
  ; there was one, then AX will contain the DOS error code. We will
  ; record this error code in the DOSError global variable. If no error
  ; occured, then DOSError will be set to zero.
  MOV  AX, SS
  MOV  ES, AX
  LEA  DX, [ProgramFileSpec]
  LEA  BX, [@@ProgramExec]
  MOV  AX, 4B01h
  INT  21h
  JC   @@Error
  ; Get the prefix segment of the child process
  MOV  AH, 62h
  INT  21h
  MOV  [ChildPrefixSeg], BX
  ; Set current prefix segment back to our own
  MOV  BX, [PrefixSeg]
  MOV  AH, 50h
  INT  21h
  ; Obtain the base, code and stack pointers
  MOV  DX, [WORD LOW  @@ProgramExec.CodePointer]
  MOV  [WORD LOW  CodePointer], DX
  MOV  DX, [WORD HIGH @@ProgramExec.CodePointer]
  MOV  [WORD HIGH CodePointer], DX
  MOV  DX, [WORD LOW  @@ProgramExec.StackPointer]
  MOV  [WORD LOW  StackPointer], DX
  MOV  DX, [WORD HIGH @@ProgramExec.StackPointer]
  MOV  [WORD HIGH StackPointer], DX
  MOV  AL, NOT 00h
  JMP  @@Return
@@Error:
  MOV  AL, 00h
@@Return:
  RET
ENDP  LoadExecutable
; Runs loaded executable image in memory. Base, Code and Stack contain the
; image start, code entry point and initial stack location respectively.
PROC  RunExecutable
  ; Set active process back to child
  MOV  BX, [ChildPrefixSeg]
  MOV  AH, 50h
  INT  21h
  ; Set INT 22 return address for child process. ES will contain the
  ; segment address of the child process PSP.
  MOV  BX, [ChildPrefixSeg]
  MOV  ES, BX
  MOV  [WORD ES:000Ah], OFFSET @ReturnPoint
  MOV  [WORD ES:000Ch], SEG @ReturnPoint
  MOV  [SaveBP], BP
  MOV  [SaveSS], SS
  MOV  [SaveSP], SP
  ; Switch the stack over to the one used by the child process. Push the
  ; entry point of the child process onto the new stack, so we can use a
  ; far return instruction to jump to the child process entry point.
  MOV  AX, [WORD StackPointer + 0]
  MOV  DX, [WORD StackPointer + 2]
  MOV  CX, [WORD CodePointer + 0]
  MOV  BX, [WORD CodePointer + 2]
  MOV  SS, DX
  MOV  SP, AX
  PUSH BX
  PUSH CX
  ; Set DS to point to the PSP segment of the child process, which ES
  ; already contains. Zero out all the other registers, since all DOS
  ; programs expect the registers to be set to zero when launched. Then
  ; jump (through RETF) to the child process entry point.
  MOV  AX, ES
  MOV  DS, AX
  XOR  AX, AX
  XOR  BX, BX
  XOR  CX, CX
  XOR  DX, DX
  XOR  SI, SI
  XOR  DI, DI
  XOR  BP, BP
  RETF
  ; --- Child program will return here when it terminates ---
@ReturnPoint:
  MOV  AX, @data
  MOV  DS, AX
  MOV  BP, [SaveBP]
  MOV  SS, [SaveSS]
  MOV  SP, [SaveSP]
ENDP  RunExecutable
; Unloads executable from memory (only call if it hasn't executed yet).
; Base points to the start of the executable image in memory.
PROC  UnloadExecutable
  ; Free the memory block owned by the child process
  MOV  AX, [ChildPrefixSeg]
  MOV  ES, AX
  MOV  AH, 49h
  INT  21h
  RET
ENDP  UnloadExecutable
; Returns PatcherBase+Offset as a normalised pointer. This function
; computes the memory location that is LinearOffset bytes beyond
; PatcherBase, then normalises the pointer for convenience.
PROC  PointerOffset
ARG   @@LinearOffset:DWORD
  ; Convert PatcherBase to a linear memory offset in DX:AX
  MOV  CX, [ChildPrefixSeg]
  ADD  CX, 0010h
  MOV  AX, 16
  MUL  CX
  ; Add LinearOffset to DX:AX
  ADD  AX, [WORD LOW  @@LinearOffset]
  ADC  DX, [WORD HIGH @@LinearOffset]
  ; Convert DX:AX to a normalised segment:offset index
  AND  DX, 000Fh
  MOV  BX, AX
  AND  BX, 000Fh
  MOV  CX, 16
  DIV  CX
  MOV  DX, AX
  MOV  AX, BX
  RET
ENDP  PointerOffset

begin:
  MOV  AX, @data
  MOV  DS, AX
  MOV  AH, 62h
  INT  21h
  MOV  [PrefixSeg], BX
  MOV  ES, BX
  MOV  AH, 4Ah
  MOV  BX, 0080h
  INT  21h
  CALL GetLoadImageSize
  CMP  DX, 0001h
  JNE  @@Quit
  CMP  AX, 0A230h
  JNE  @@Quit
  ; Attempt to load game executable into memory
  CALL LoadExecutable
  CMP  AL, 00h
  JE   @@Quit
  CALL PointerOffset, 0000h 2353h
  MOV  [WORD HIGH PatchPointer], AX
  MOV  [WORD LOW  PatchPointer], DX
  PUSH DS
  MOV  DS, DX
  MOV  BX, AX
  MOV  [BYTE BX], 0C3h
  POP  DS
  CALL RunExecutable
@@Quit:
  MOV  AX, 4C00h
  INT  21h
END Begin
