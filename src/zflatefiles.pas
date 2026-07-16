{ zflatefiles - file compression on top of zflate. Open a file (or load a
  memory buffer), compress or decompress it to another file or to memory,
  with an optional progress callback for a progressbar. Files are processed
  in chunks through the zflate streaming API, so memory use stays constant
  no matter the file size. File access goes straight to WinAPI on Windows
  and libc on everything else; the only dependency is the zflate unit. No
  exception ever escapes this unit. }

{ Copyright (c) 2023-2026 @fibodevy / https://github.com/fibodevy
  MIT licensed (see LICENSE). Free to use and modify; keep this notice
  and the link when you redistribute the sources. }

unit zflatefiles;

{$mode unleashed}
{$R-}{$Q-}

interface

uses zflate;

type
  TZFlateFile = class
  private
    fdata: pointer;     // memory input (owned copy), nil in file mode
    ffile: TObject;     // file input (TZFile), nil in memory mode
    fsize: qword;
    floaded: boolean;
    ferror: integer;
    fprogress: tzprogress;
    function runStream(compressing: boolean; streamtype, level: dword; writer: tzwriter): integer;
    function runToBytes(compressing: boolean; streamtype, level: dword): TBytes;
    function runToFile(compressing: boolean; streamtype, level: dword; const dst: string): integer;
  public
    destructor Destroy; override;
    // open a file as the input; only a handle is kept, the content is streamed
    function openFile(const path: string): boolean;
    // release the input (file handle or memory copy)
    procedure closeFile;
    // load input from memory (a private copy is made)
    procedure loadFromMemory(data: pointer; datasize: dword);
    procedure loadFromMemory(const str: string);
    procedure loadFromMemory(const bytes: TBytes);
    // detected stream type of the input: ZFLATE_GZIP / ZFLATE_ZLIB / ZFLATE_RAW
    function streamType: dword;
    // compress/decompress the input to memory; nil on error (see error)
    function compress(streamtype: dword = ZFLATE_GZIP; level: dword = ZFLATE_DEFAULT): TBytes;
    function decompress: TBytes;
    // compress/decompress the input to a file, chunk by chunk; ZFLATE_OK or
    // error code, the output file is deleted on failure
    function compressToFile(const dst: string; streamtype: dword = ZFLATE_GZIP; level: dword = ZFLATE_DEFAULT): integer;
    function decompressToFile(const dst: string): integer;
    // input size
    property size: qword read fsize;
    // last error code
    property error: integer read ferror;
    // progress callback, return false to abort; anonymous functions welcome
    property onProgress: tzprogress read fprogress write fprogress;
  end;

// one-shot file helpers, fully streamed: src -> DEFLATE / ZLIB / GZIP -> dst
function gzdeflate_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
function gzcompress_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
function gzencode_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
// detect the container and decompress a file
function zdecompress_file(const src, dst: string; progress: tzprogress = nil): integer;

implementation

// ----- raw file access: winapi on windows, libc elsewhere -----

{$ifdef windows}

const
  GENERIC_READ          = dword($80000000);
  GENERIC_WRITE         = dword($40000000);
  FILE_SHARE_READ       = 1;
  CREATE_ALWAYS         = 2;
  OPEN_EXISTING         = 3;
  FILE_ATTRIBUTE_NORMAL = $80;
  FILE_BEGIN            = 0;
  INVALID_HANDLE        = ptruint(-1);

function CreateFileA(name: pchar; access, share: dword; sec: pointer; disp, flags: dword; template: ptruint): ptruint; stdcall; external 'kernel32';
function ReadFile(h: ptruint; buf: pointer; n: dword; var got: dword; ovl: pointer): longbool; stdcall; external 'kernel32';
function WriteFile(h: ptruint; buf: pointer; n: dword; var put: dword; ovl: pointer): longbool; stdcall; external 'kernel32';
function CloseHandle(h: ptruint): longbool; stdcall; external 'kernel32';
function GetFileSizeEx(h: ptruint; var fsize: int64): longbool; stdcall; external 'kernel32';
function SetFilePointerEx(h: ptruint; dist: int64; newpos: pointer; method: dword): longbool; stdcall; external 'kernel32';
function DeleteFileA(name: pchar): longbool; stdcall; external 'kernel32';

{$else}

const
  O_RDONLY = 0;
  O_WRONLY = 1;
  O_CREAT  = &100;
  O_TRUNC  = &1000;
  SEEK_SET = 0;
  SEEK_END = 2;

function c_open(path: pchar; flags: longint; mode: longint): longint; cdecl; external 'c' name 'open';
function c_read(fd: longint; buf: pointer; n: ptruint): ptrint; cdecl; external 'c' name 'read';
function c_write(fd: longint; buf: pointer; n: ptruint): ptrint; cdecl; external 'c' name 'write';
function c_close(fd: longint): longint; cdecl; external 'c' name 'close';
{$ifdef cpu64}
function c_lseek(fd: longint; offset: int64; whence: longint): int64; cdecl; external 'c' name 'lseek';
{$else}
function c_lseek(fd: longint; offset: int64; whence: longint): int64; cdecl; external 'c' name 'lseek64';
{$endif}
function c_unlink(path: pchar): longint; cdecl; external 'c' name 'unlink';

{$endif}

type
  // minimal file handle wrapper shared by both backends
  TZFile = class
  private
    {$ifdef windows}
    fhandle: ptruint;
    {$else}
    fhandle: longint;
    {$endif}
    fisopen: boolean;
  public
    destructor Destroy; override;
    function openRead(const path: string): boolean;
    function createNew(const path: string): boolean;
    function fileSize: int64;
    function seek(pos: int64): boolean;
    // read up to maxlen bytes: the byte count, 0 = end of file, -1 = failure
    function readSome(buf: pointer; maxlen: dword): longint;
    function write(buf: pointer; n: dword): boolean;
    procedure close;
    class function deleteFile(const path: string): boolean;
  end;

destructor TZFile.Destroy;
begin
  close;
  inherited Destroy;
end;

function TZFile.openRead(const path: string): boolean;
begin
  close;
  {$ifdef windows}
  fhandle := CreateFileA(pchar(path), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  result := fhandle <> INVALID_HANDLE;
  {$else}
  fhandle := c_open(pchar(path), O_RDONLY, 0);
  result := fhandle >= 0;
  {$endif}
  fisopen := result;
end;

function TZFile.createNew(const path: string): boolean;
begin
  close;
  {$ifdef windows}
  fhandle := CreateFileA(pchar(path), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  result := fhandle <> INVALID_HANDLE;
  {$else}
  fhandle := c_open(pchar(path), O_WRONLY or O_CREAT or O_TRUNC, &644);
  result := fhandle >= 0;
  {$endif}
  fisopen := result;
end;

function TZFile.fileSize: int64;
begin
  result := -1;
  if not fisopen then exit;
  {$ifdef windows}
  if not GetFileSizeEx(fhandle, result) then result := -1;
  {$else}
  result := c_lseek(fhandle, 0, SEEK_END);
  if c_lseek(fhandle, 0, SEEK_SET) < 0 then result := -1;
  {$endif}
end;

function TZFile.seek(pos: int64): boolean;
begin
  if not fisopen then exit(false);
  {$ifdef windows}
  result := SetFilePointerEx(fhandle, pos, nil, FILE_BEGIN);
  {$else}
  result := c_lseek(fhandle, pos, SEEK_SET) >= 0;
  {$endif}
end;

function TZFile.readSome(buf: pointer; maxlen: dword): longint;
begin
  if not fisopen then exit(-1);
  {$ifdef windows}
  var got: dword := 0;
  if not ReadFile(fhandle, buf, maxlen, got, nil) then exit(-1);
  result := got;
  {$else}
  var r := c_read(fhandle, buf, maxlen);
  if r < 0 then exit(-1);
  result := r;
  {$endif}
end;

function TZFile.write(buf: pointer; n: dword): boolean;
begin
  result := false;
  if not fisopen then exit;
  while n > 0 do begin
    var put: dword := 0;
    {$ifdef windows}
    if not WriteFile(fhandle, buf, n, put, nil) then exit;
    {$else}
    var r := c_write(fhandle, buf, n);
    if r < 0 then exit;
    put := dword(r);
    {$endif}
    if put = 0 then exit;
    buf := pbyte(buf) + put;
    dec(n, put);
  end;
  result := true;
end;

procedure TZFile.close;
begin
  if not fisopen then exit;
  {$ifdef windows}
  CloseHandle(fhandle);
  {$else}
  c_close(fhandle);
  {$endif}
  fisopen := false;
end;

class function TZFile.deleteFile(const path: string): boolean;
begin
  {$ifdef windows}
  result := DeleteFileA(pchar(path));
  {$else}
  result := c_unlink(pchar(path)) = 0;
  {$endif}
end;

// ----- TZFlateFile -----

destructor TZFlateFile.Destroy;
begin
  closeFile;
  inherited Destroy;
end;

function TZFlateFile.openFile(const path: string): boolean;
begin
  result := false;
  closeFile;
  ferror := ZFLATE_EFILEREAD;
  var f := TZFile.Create;
  if not f.openRead(path) then begin f.Free; exit; end;
  var n := f.fileSize;
  if n < 0 then begin f.Free; exit; end;
  ffile := f;
  fsize := n;
  floaded := true;
  ferror := ZFLATE_OK;
  result := true;
end;

procedure TZFlateFile.closeFile;
begin
  if fdata <> nil then begin FreeMem(fdata); fdata := nil; end;
  if ffile <> nil then begin ffile.Free; ffile := nil; end;
  fsize := 0;
  floaded := false;
end;

procedure TZFlateFile.loadFromMemory(data: pointer; datasize: dword);
begin
  closeFile;
  if datasize > 0 then begin
    fdata := GetMem(datasize);
    Move(data^, fdata^, datasize);
  end;
  fsize := datasize;
  floaded := true;
  ferror := ZFLATE_OK;
end;

procedure TZFlateFile.loadFromMemory(const str: string);
begin
  loadFromMemory(pointer(str), length(str));
end;

procedure TZFlateFile.loadFromMemory(const bytes: TBytes);
begin
  loadFromMemory(pointer(bytes), length(bytes));
end;

function TZFlateFile.streamType: dword;
begin
  result := ZFLATE_RAW;
  if not floaded then exit;
  if ffile = nil then exit(stream_info(fdata, fsize).streamtype);
  // sniff the first bytes of the file
  var f := TZFile(ffile);
  var probe: array[512] of byte;
  if not f.seek(0) then exit;
  var got := f.readSome(@probe[0], sizeof(probe));
  if got > 0 then result := stream_info(@probe[0], got).streamtype;
end;

// stream the input through the codec into writer, with the progress hook installed
function TZFlateFile.runStream(compressing: boolean; streamtype, level: dword; writer: tzwriter): integer;
begin
  if not floaded then exit(ZFLATE_ENODATA);
  var rfail := false;
  var reader: tzreader := nil;
  if ffile <> nil then begin
    var f := TZFile(ffile);
    if not f.seek(0) then exit(ZFLATE_EFILEREAD);
    reader := function(buf: pointer; maxlen: dword): dword
    begin
      var got := f.readSome(buf, maxlen);
      if got < 0 then begin rfail := true; got := 0; end;
      result := got;
    end;
  end else begin
    var cursor: qword := 0;
    reader := function(buf: pointer; maxlen: dword): dword
    begin
      var left := fsize - cursor;
      if left > maxlen then left := maxlen;
      if left > 0 then Move((pbyte(fdata) + cursor)^, buf^, left);
      cursor := cursor + left;
      result := left;
    end;
  end;
  zprogress := fprogress;
  if compressing then
    result := match streamtype of
      ZFLATE_ZLIB: gzcompress_stream(reader, writer, fsize, level);
      ZFLATE_GZIP: gzencode_stream(reader, writer, fsize, level);
      _: gzdeflate_stream(reader, writer, fsize, level);
    end else result := zdecompress_stream(reader, writer, fsize);
  zprogress := nil;
  if rfail then result := ZFLATE_EFILEREAD;
end;

function TZFlateFile.runToBytes(compressing: boolean; streamtype, level: dword): TBytes;
begin
  result := nil;
  var acc: TBytes := nil;
  var used: qword := 0;
  ferror := runStream(compressing, streamtype, level, function(data: pointer; datasize: dword): boolean
  begin
    // grow geometrically, trim after the run
    if used + datasize > qword(length(acc)) then setlength(acc, (used + datasize) * 2);
    Move(data^, acc[used], datasize);
    used := used + datasize;
    result := true;
  end);
  if ferror <> ZFLATE_OK then exit;
  setlength(acc, used);
  result := acc;
end;

function TZFlateFile.runToFile(compressing: boolean; streamtype, level: dword; const dst: string): integer;
begin
  var f := autofree TZFile.Create;
  if not f.createNew(dst) then exit(ZFLATE_EFILEWRITE);
  var wfail := false;
  result := runStream(compressing, streamtype, level, function(data: pointer; datasize: dword): boolean
  begin
    result := f.write(data, datasize);
    if not result then wfail := true;
  end);
  if wfail then result := ZFLATE_EFILEWRITE;
  f.close;
  if result <> ZFLATE_OK then TZFile.deleteFile(dst);
end;

function TZFlateFile.compress(streamtype: dword = ZFLATE_GZIP; level: dword = ZFLATE_DEFAULT): TBytes;
begin
  result := runToBytes(true, streamtype, level);
end;

function TZFlateFile.decompress: TBytes;
begin
  result := runToBytes(false, 0, 0);
end;

function TZFlateFile.compressToFile(const dst: string; streamtype: dword = ZFLATE_GZIP; level: dword = ZFLATE_DEFAULT): integer;
begin
  result := runToFile(true, streamtype, level, dst);
  ferror := result;
end;

function TZFlateFile.decompressToFile(const dst: string): integer;
begin
  result := runToFile(false, 0, 0, dst);
  ferror := result;
end;

// ----- one-shot helpers -----

// open src, stream it through the codec into dst
function packFile(const src, dst: string; streamtype, level: dword; progress: tzprogress): integer;
begin
  var z := autofree TZFlateFile.Create;
  z.onProgress := progress;
  if not z.openFile(src) then exit(z.error);
  result := z.compressToFile(dst, streamtype, level);
end;

function gzdeflate_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
begin result := packFile(src, dst, ZFLATE_RAW, level, progress); end;

function gzcompress_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
begin result := packFile(src, dst, ZFLATE_ZLIB, level, progress); end;

function gzencode_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
begin result := packFile(src, dst, ZFLATE_GZIP, level, progress); end;

function zdecompress_file(const src, dst: string; progress: tzprogress = nil): integer;
begin
  var z := autofree TZFlateFile.Create;
  z.onProgress := progress;
  if not z.openFile(src) then exit(z.error);
  result := z.decompressToFile(dst);
end;

end.
