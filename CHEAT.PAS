program Cheat;
{$A+,B+,E-,F-,G+,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2048, 0, 0}
uses Dos;
const
	{ Valid .EXE files have the ID field set to this magic value. In string }
	{ form, this reads 'MZ', which is apparently the initials of Mark       }
	{ Zbikowski, one of the designers behind MS-DOS 2.0 way back in 1983.   }
	ValidEXESignature  = $5A4D;
	CProgramFileSpec = 'PYRAMIDS.EXE';
	ProgramFileSpec: PChar = CProgramFileSpec;
type
	{ .EXE file header structure }
	TEXEHeader = record
		ID               : Word; { Signature field, must be $5A4D }
		ImageLengthLow   : Word; { File length modulo 512 }
		ImageLengthHigh  : Word; { File length divided by 512, rounded up }
		NumRelocs        : Word; { Number of relocation entries }
		HeaderSize       : Word; { Size of header divided by 16 }
		MinParagraphs    : Word; { Min # of paragraphs needed to run program }
		MaxParagraphs    : Word; { Desired # of paragraps program would like }
		InitSS           : Word; { Initial stack segment offset }
		InitSP           : Word; { Initial SP register value }
		Checksum         : Word; { Checksum of header, or zero }
		InitIP           : Word; { Initial code entry point offset }
		InitCS           : Word; { Initial code segment offset }
		FirstRelocOffset : Word; { Offset in header of relocation table }
		OverlayNumber    : Word; { Overlay number, zero for main program }
	end;
	{ Structure required for DOS INT 21H/4BH Exec call }
	TProgramExec = record
		{ Segment of environment block to inherit for child process }
		Environment  : Word;
		{ Pointer to command line arguments for child process }
		CommandLine  : Pointer;
		{ Pointer to FCB structures for child process }
		FCB          : array[0..1] of Pointer;
		{ Contains the initial SS:SP of the child process on return }
		StackPointer : Pointer;
		{ Contains the initial CS:IP of the child process on return }
		CodePointer  : Pointer;
	end;
	PByte = ^Byte;
var
	SaveSS         : Word;
	SaveSP         : Word;
	SaveBP         : Word;
	ChildPrefixSeg : Word;
	CodePointer    : Pointer;
	StackPointer   : Pointer;
	PatchPointer   : PByte;

{ Returns load image size for given executable file, 0 if not a valid .EXE. }
{ FileName contains the file name of the executable file to examine.        }
function GetLoadImageSize: Longint;
var
	{ Stores the .EXE file header }
	EXEHeader: TEXEHeader;
	{ Input file variable }
	InputFile: file;
begin
	{ Initially assume that the operation was not successful }
	GetLoadImageSize := 0;
	{ Open files for reading only }
	FileMode := 0;
	{ Open the executable file }
	Assign(InputFile, ProgramFileSpec);
	Reset(InputFile, 1);
	if IOResult = 0 then
	begin
		{ Read the header }
		BlockRead(InputFile, EXEHeader, SizeOf(TEXEHeader));
		{ Check if the header read operation succeeded }
		if IOResult = 0 then
		begin
			{ Check if the ID field matches the required magic value }
			if EXEHeader.ID = ValidEXESignature then
			begin
				{ Compute the size of the .EXE file image. This is done by }
				{ obtaining the supposed file length from the .EXE header }
				{ and subtracting the length of the header from it. }
				GetLoadImageSize := Longint(EXEHeader.ImageLengthHigh - 1) * 512
					+ Longint(EXEHeader.ImageLengthLow)
					- Longint(EXEHeader.HeaderSize * 16);
			end;
		end;
		{ Close the executable file }
		Close(InputFile);
	end;
end;
{ Loads executable into memory but does not execute. Returns pointers to    }
{ image start, code entry point and initial stack location in Base, Code    }
{ and Stack respectively. FileName contains the file name of the executable }
{ file to load. CommandLine contains the command line arguments to supply   }
{ to the executable.                                                        }
function LoadExecutable: Boolean;
label Error, Return;
var
	{ Structure used for the DOS INT 21H/4BH Exec call }
	ProgramExec : TProgramExec;
begin
	ProgramExec.Environment := 0;
	ProgramExec.CommandLine := nil;
	ProgramExec.FCB[0] := Ptr(PrefixSeg, $005C);
	ProgramExec.FCB[1] := Ptr(PrefixSeg, $006C);
	{ Load executable as child process into memory, but do not execute. }
	{ This is done using DOS interrupt 21H, service 4BH, subservice 01H }
	{ (load but don't execute). DS:DX points to the executable file name as }
	{ a null-terminated string. ES:BX points to the ProgramExec structure }
	{ that contains the command line arguments, environment block and FCB }
	{ structures for the child process, and will contain the initial entry }
	{ point and stack location of the child process on return. When the }
	{ call returns, the carry flag will be set if an error occured. If }
	{ there was one, then AX will contain the DOS error code. We will }
	{ record this error code in the DOSError global variable. If no error }
	{ occured, then DOSError will be set to zero. Note that Turbo Pascal }
	{ expects the DS register to be preserved so we have to save it on the }
	{ stack temporarily. }
	asm
		PUSH DS
		MOV  AX, SS
		MOV  ES, AX
		LDS  DX, ProgramFileSpec
		LEA  BX, ProgramExec
		MOV  AX, $4B01
		INT  $21
		POP  DS
		JC   Error
		{ Get the prefix segment of the child process }
		MOV  AH, $62
		INT  $21
		MOV  ChildPrefixSeg, BX
		{ Set current prefix segment back to our own }
		MOV  BX, PrefixSeg
		MOV  AH, $50
		INT  $21
	end;
	{ Obtain the base, code and stack pointers }
	CodePointer := ProgramExec.CodePointer;
	StackPointer := ProgramExec.StackPointer;
	LoadExecutable := True;
	goto Return;
Error:
	LoadExecutable := False;
Return:
end;
{ Runs loaded executable image in memory. Base, Code and Stack contain the  }
{ image start, code entry point and initial stack location respectively.    }
procedure RunExecutable; assembler;
asm
	{ Set active process back to child }
	MOV  BX, ChildPrefixSeg
	MOV  AH, $50
	INT  $21
	{ Set INT 22 return address for child process. ES will contain the }
	{ segment address of the child process PSP. }
	MOV  BX, ChildPrefixSeg
	MOV  ES, BX
	MOV  WORD PTR [ES:$000A], OFFSET @ReturnPoint
	MOV  WORD PTR [ES:$000C], SEG @ReturnPoint
	{ Turbo Pascal expects the SS, SP and BP registers to be preserved }
	MOV  SaveBP, BP
	MOV  SaveSS, SS
	MOV  SaveSP, SP
	{ Switch the stack over to the one used by the child process. Push the }
	{ entry point of the child process onto the new stack, so we can use a }
	{ far return instruction to jump to the child process entry point. }
	MOV  AX, WORD PTR [StackPointer + 0]
	MOV  DX, WORD PTR [StackPointer + 2]
	MOV  CX, WORD PTR [CodePointer + 0]
	MOV  BX, WORD PTR [CodePointer + 2]
	MOV  SS, DX
	MOV  SP, AX
	PUSH BX
	PUSH CX
	{ Set DS to point to the PSP segment of the child process, which ES }
	{ already contains. Zero out all the other registers, since all DOS }
	{ programs expect the registers to be set to zero when launched. Then }
	{ jump (through RETF) to the child process entry point. }
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
	{ --- Child program will return here when it terminates --- }
@ReturnPoint:
	{ Restore the DS, SS, SP and BP registers to satisfy Turbo Pascal }
	MOV  AX, SEG @data
	MOV  DS, AX
	MOV  BP, SaveBP
	MOV  SS, SaveSS
	MOV  SP, SaveSP
end;
{ Unloads executable from memory (only call if it hasn't executed yet).     }
{ Base points to the start of the executable image in memory.               }
procedure UnloadExecutable; assembler;
asm
	{ Free the memory block owned by the child process }
	MOV  AX, ChildPrefixSeg
	MOV  ES, AX
	MOV  AH, $49
	INT  $21
end;
{ Returns PatcherBase + Offset as a normalised pointer. This function }
{ computes the memory location that is LinearOffset bytes beyond }
{ PatcherBase, then normalises the pointer for convenience. }
function PointerOffset(LinearOffset: Longint): PByte; assembler;
asm
	{ Convert PatcherBase to a linear memory offset in DX:AX }
	MOV  CX, ChildPrefixSeg
	ADD  CX, $0010
	MOV  AX, 16
	MUL  CX
	{ Add LinearOffset to DX:AX }
	ADD  AX, WORD PTR [LinearOffset]
	ADC  DX, WORD PTR [LinearOffset + 2]
	{ Convert DX:AX to a normalised segment:offset index }
	AND  DX, $000F
	MOV  BX, AX
	AND  BX, $000F
	MOV  CX, 16
	DIV  CX
	MOV  DX, AX
	MOV  AX, BX
end;

begin
	if GetLoadImageSize = 107056 then
	begin
		{ Tell Dos unit to release its interrupt handlers since we will be }
		{ launching off child processes. }
		SwapVectors;
		{ Attempt to load game executable into memory }
		if LoadExecutable then
		begin
			PatchPointer := PointerOffset($2353);
			PatchPointer^ := $C3;
			{ Jump to the image entry point to run the game }
			RunExecutable;
		end;
		{ Restore the Dos unit's interrupt handlers, so it can unhook them }
		{ properly on exit. }
		SwapVectors;
	end;
end.
