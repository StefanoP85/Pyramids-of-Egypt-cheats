program Cheat;
{$A+,B+,E-,F-,G+,I-,P+,Q-,R-,S-,T-,V-,X+}
{$M 2048, 0, 0}
uses Dos, Strings;
const
	{ Valid .EXE files have the ID field set to this magic value. In string }
	{ form, this reads 'MZ', which is apparently the initials of Mark       }
	{ Zbikowski, one of the designers behind MS-DOS 2.0 way back in 1983.   }
	ValidEXESignature  = $5A4D;
	ProgramFileSpec    = 'PYRAMIDS.EXE';
	ProgramCommandLine = '';

type
	{ .EXE file header structure }
	TEXEHeader = record
		ID: Word;               { Signature field, must be $5A4D }
		ImageLengthLow: Word;   { File length modulo 512 }
		ImageLengthHigh: Word;  { File length divided by 512, rounded up }
		NumRelocs: Word;        { Number of relocation entries }
		HeaderSize: Word;       { Size of header divided by 16 }
		MinParagraphs: Word;    { Min # of paragraphs needed to run program }
		MaxParagraphs: Word;    { Desired # of paragraps program would like }
		InitSS: Word;           { Initial stack segment offset }
		InitSP: Word;           { Initial SP register value }
		Checksum: Word;         { Checksum of header, or zero }
		InitIP: Word;           { Initial code entry point offset }
		InitCS: Word;           { Initial code segment offset }
		FirstRelocOffset: Word; { Offset in header of relocation table }
		OverlayNumber: Word;    { Overlay number, zero for main program }
	end;
	{ Structure required for DOS INT 21H/4BH Exec call }
	TExec = record
		{ Segment of environment block to inherit for child process }
		Environment: Word;
		{ Pointer to command line arguments for child process }
		CommandLine: Pointer;
		{ Pointer to FCB structures for child process }
		FCB: array[1..2] of Pointer;
		{ Contains the initial SS:SP of the child process on return }
		Stack: Pointer;
		{ Contains the initial CS:IP of the child process on return }
		Code: Pointer;
	end;
	{ Structure used to access 16-bit components of a 32-bit doubleword in }
	{ memory. }
	MemLong = record
		Lo, Hi: Word;
	end;
	{ Structure used to access 16-bit segment/offset components of a 32-bit }
	{ real mode pointer in memory. }
	MemPtr = record
		MemOfs, MemSeg: Word;
	end;
	PByte = ^Byte;

var
	SaveSS, SaveSP, SaveBP : Word;
	Base, Code, Stack      : Pointer;
	PatchPointer           : PByte;

{ Returns load image size for given executable file, 0 if not a valid .EXE. }
{ FileName contains the file name of the executable file to examine.        }
function GetLoadImageSize(const FileName: string): Longint;
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
	Assign(InputFile, FileName);
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
			end
			else
				{ The executable doesn't have the required magic value in }
				{ its header ID field, so it isn't a valid .EXE file. }
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
function LoadExecutable(const FileName, CommandLine: string; var Base, Code, Stack: Pointer): Boolean;
var
	{ Paragraph address of child Program Segment Prefix (PSP) }
	ChildPrefixSeg: Word;
	{ The executable file name, as a null-terminated string }
	ASCIIZProgramName: array[0..63] of Char;
	{ The command line arguments, as a null-terminated string }
	ASCIIZCommandLine: array[0..127] of Char;
	{ Structure used for the DOS INT 21H/4BH Exec call }
	ProgramExec: TExec;
begin
	{ Convert the executable file name and command line arguments into }
	{ null-terminated strings so they can be passed to DOS }
	StrPCopy(ASCIIZProgramName, FileName);
	StrPCopy(ASCIIZCommandLine, CommandLine);
	{ Let the child process inherit our own environment and FCB structures }
	ProgramExec.Environment := 0;
	ProgramExec.CommandLine := @ASCIIZCommandLine;
	ProgramExec.FCB[1] := Ptr(PrefixSeg, $005C);
	ProgramExec.FCB[2] := Ptr(PrefixSeg, $006C);
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
		MOV AX, SS
		MOV DS, AX
		MOV ES, AX
		LEA DX, ASCIIZProgramName
		LEA BX, ProgramExec
		MOV AX, $4B01
		INT $21
		POP DS
		JNC @NoError
	@Error:
		MOV DOSError, AX
		JMP @Done
	@NoError:
		MOV DOSError, 0
	@Done:
	end;
	{ Check if the load operation succeeded }
	if DOSError = 0 then
	begin
		asm
			{ Get the prefix segment of the child process }
			MOV AH, $62
			INT $21
			MOV ChildPrefixSeg, BX
			{ Set current prefix segment back to our own }
			MOV BX, PrefixSeg
			MOV AH, $50
			INT $21
		end;
		{ Obtain the base, code and stack pointers }
		Base := Ptr(ChildPrefixSeg + $10, $0000);
		Code := ProgramExec.Code;
		Stack := ProgramExec.Stack;
		LoadExecutable := True;
	end
	else
		{ There was an error while loading the executable }
		LoadExecutable := False;
end;
{ Runs loaded executable image in memory. Base, Code and Stack contain the  }
{ image start, code entry point and initial stack location respectively.    }
procedure RunExecutable(Base, Code, Stack: Pointer); assembler;
asm
	{ Set active process back to child }
	MOV BX, MemPtr(Base).MemSeg
	SUB BX, $0010
	MOV AH, $50
	INT $21
	{ Set INT 22 return address for child process. ES will contain the }
	{ segment address of the child process PSP. }
	MOV BX, MemPtr(Base).MemSeg
	SUB BX, $0010
	MOV ES, BX
	MOV MemPtr(ES:[$000A]).MemOfs, OFFSET @ReturnPoint
	MOV MemPtr(ES:[$000A]).MemSeg, SEG @ReturnPoint
	{ Turbo Pascal expects the SS, SP and BP registers to be preserved }
	MOV SaveBP, BP
	MOV SaveSS, SS
	MOV SaveSP, SP
	{ Switch the stack over to the one used by the child process. Push the }
	{ entry point of the child process onto the new stack, so we can use a }
	{ far return instruction to jump to the child process entry point. }
	MOV AX, MemPtr(Stack).MemOfs
	MOV DX, MemPtr(Stack).MemSeg
	MOV CX, MemPtr(Code).MemOfs
	MOV BX, MemPtr(Code).MemSeg
	MOV SS, DX
	MOV SP, AX
	PUSH BX
	PUSH CX
	{ Set DS to point to the PSP segment of the child process, which ES }
	{ already contains. Zero out all the other registers, since all DOS }
	{ programs expect the registers to be set to zero when launched. Then }
	{ jump (or is that return?) to the child process entry point. }
	MOV AX, ES
	MOV DS, AX
	XOR AX, AX
	XOR BX, BX
	XOR CX, CX
	XOR DX, DX
	XOR SI, SI
	XOR DI, DI
	XOR BP, BP
	RETF
	{ --- Child program will return here when it terminates --- }
@ReturnPoint:
	{ Restore the DS, SS, SP and BP registers to satisfy Turbo Pascal }
	MOV AX, SEG @Data
	MOV DS, AX
	MOV BP, SaveBP
	MOV SS, SaveSS
	MOV SP, SaveSP
end;
{ Unloads executable from memory (only call if it hasn't executed yet).     }
{ Base points to the start of the executable image in memory.               }
procedure UnloadExecutable(Base: Pointer); assembler;
asm
	{ Free the memory block owned by the child process }
	MOV AX, MemPtr(Base).MemSeg
	SUB AX, $0010
	MOV ES, AX
	MOV AH, $49
	INT $21
end;

{ Returns PatcherBase+Offset as a normalised pointer. This function }
{ computes the memory location that is LinearOffset bytes beyond }
{ PatcherBase, then normalises the pointer for convenience. }
function PointerOffset(LinearOffset: Longint): Pointer; assembler;
asm
	{ Convert PatcherBase to a linear memory offset in DX:AX }
	MOV AX, 16
	MUL MemPtr(Base).MemSeg
	ADD AX, MemPtr(Base).MemOfs
	ADC DX, $0000
	{ Add LinearOffset to DX:AX }
	ADD AX, MemLong(LinearOffset).Lo
	ADC DX, MemLong(LinearOffset).Hi
	{ Convert DX:AX to a normalised segment:offset index }
	AND DX, $000F
	MOV BX, AX
	AND BX, $000F
	MOV CX, 16
	DIV CX
	MOV DX, AX
	MOV AX, BX
end;

begin
	if GetLoadImageSize(ProgramFileSpec) = 107056 then
	begin
		{ Tell Dos unit to release its interrupt handlers since we will be }
		{ launching off child processes. }
		SwapVectors;
		{ Attempt to load game executable into memory }
		LoadExecutable(ProgramFileSpec, ProgramCommandLine, Base, Code, Stack);

		PatchPointer := PointerOffset($2353);
		PatchPointer^ := $C3;
		
		{ Jump to the image entry point to run the game }
		RunExecutable(Base, Code, Stack);
		{ Restore the Dos unit's interrupt handlers, so it can unhook them }
		{ properly on exit. }
		SwapVectors;
	end;
end.
