program test_zflatefiles;

{$mode unleashed}

uses zflate, zflatefiles;

var
  passed: integer = 0;
  failed: integer = 0;
  colors: boolean = false;

{$ifdef windows}
const
  STD_OUTPUT_HANDLE = dword(-11);
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = 4;

function GetStdHandle(nStdHandle: dword): ptruint; stdcall; external 'kernel32';
function GetConsoleMode(console: ptruint; var mode: dword): longbool; stdcall; external 'kernel32';
function SetConsoleMode(console: ptruint; mode: dword): longbool; stdcall; external 'kernel32';
{$endif}

// A double-clicked exe lands in the legacy console, which prints ANSI escapes
// literally unless virtual terminal processing is switched on; Windows Terminal
// has it on already. False means there is nothing to colour (output redirected,
// or a console too old to support it) and we print plain tags instead.
function enableColors: boolean;
begin
  {$ifdef windows}
  var mode: dword := 0;
  var h := GetStdHandle(STD_OUTPUT_HANDLE);
  result := GetConsoleMode(h, mode) and SetConsoleMode(h, mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);
  {$else}
  result := true;
  {$endif}
end;

procedure check(const name: string; ok: boolean);
begin
  var tag := if ok then '[ OK ]' else '[FAIL]';
  if colors then tag := (if ok then #27'[32m' else #27'[31m') + tag + #27'[0m';
  if ok then begin
    inc(passed);
    writeln(tag, ' ', name);
  end else begin
    inc(failed);
    writeln(tag, ' ', name);
  end;
end;

// compressible text mixed with pseudorandom bytes
function makedata(size: integer): string;
begin
  setlength(result, size);
  RandSeed := 1337;
  for var i := 1 to size do
    if i mod 3 = 0 then result[i] := chr(Random(256))
    else result[i] := chr(65 + (i mod 26));
end;

procedure savefile(const path, data: string);
var f: file;
begin
  assign(f, path);
  rewrite(f, 1);
  if length(data) > 0 then blockwrite(f, data[1], length(data));
  system.close(f);
end;

function loadfile(const path: string): string;
var f: file;
begin
  result := '';
  assign(f, path);
  {$I-} reset(f, 1); {$I+}
  if IOResult <> 0 then exit;
  setlength(result, filesize(f));
  if length(result) > 0 then blockread(f, result[1], length(result));
  system.close(f);
end;

function fileexists(const path: string): boolean;
var f: file;
begin
  assign(f, path);
  {$I-} reset(f, 1); {$I+}
  result := IOResult = 0;
  if result then system.close(f);
end;

function tostr(const b: TBytes): string;
begin
  setlength(result, length(b));
  if length(b) > 0 then Move(b[0], result[1], length(b));
end;

const
  INTEROP_TEXT = 'zflate interop test: the quick brown fox jumps over the lazy dog 1234567890';

begin
  colors := enableColors;
  writeln('=== zflatefiles tests ===');

  var data := makedata(8*1024*1024);
  savefile('files_src.bin', data);

  // one-shot compress with a progress callback (anonymous function)
  var calls := 0;
  var aborted := false;
  var cb: tzprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    inc(calls);
    result := true;
  end;
  check('gzencode_file gzip', gzencode_file('files_src.bin', 'files_src.bin.gz', 9, cb) = ZFLATE_OK);
  check('progress called', calls > 5);

  // one-shot decompress and compare
  check('zdecompress_file', zdecompress_file('files_src.bin.gz', 'files_out.bin') = ZFLATE_OK);
  check('roundtrip content', loadfile('files_out.bin') = data);

  // parallel file compression: setting zuse_threads makes gzencode_file fan out
  zuse_threads := 4;
  check('gzencode_file parallel', gzencode_file('files_src.bin', 'files_src.par.gz') = ZFLATE_OK);
  check('zdecompress_file parallel out', zdecompress_file('files_src.par.gz', 'files_par.bin') = ZFLATE_OK);
  check('parallel file roundtrip', loadfile('files_par.bin') = data);
  zuse_threads := 1;

  // the class, file input; the input file stays open while the class holds it
  var gzlen := length(loadfile('files_src.bin.gz'));
  var z := TZFlateFile.Create;
  check('openFile', z.openFile('files_src.bin.gz'));
  check('size', z.size = qword(gzlen));
  check('streamType gzip', z.streamType = ZFLATE_GZIP);
  check('decompress to memory', tostr(z.decompress) = data);

  // the class, memory input, all three loadFromMemory overloads
  z.loadFromMemory(INTEROP_TEXT);
  var packed_ := z.compress(ZFLATE_ZLIB);
  check('compress zlib from string', (z.error = ZFLATE_OK) and (length(packed_) > 0));
  z.loadFromMemory(packed_);
  check('streamType zlib', z.streamType = ZFLATE_ZLIB);
  check('decompress zlib from tbytes', tostr(z.decompress) = INTEROP_TEXT);
  z.loadFromMemory(pointer(data), length(data));
  check('compressToFile raw', z.compressToFile('files_src.bin.raw', ZFLATE_RAW) = ZFLATE_OK);
  check('zdecompress_file raw autodetect', zdecompress_file('files_src.bin.raw', 'files_out2.bin') = ZFLATE_OK);
  check('raw roundtrip content', loadfile('files_out2.bin') = data);

  // errors: no data loaded / missing file
  var e := TZFlateFile.Create;
  check('ENODATA', e.compressToFile('files_never.gz') = ZFLATE_ENODATA);
  check('EFILEREAD', (not e.openFile('files_no_such_file.bin')) and (e.error = ZFLATE_EFILEREAD));
  check('decompress garbage', (e.openFile('files_src.bin')) and (e.decompress = nil) and (e.error = ZFLATE_EINFLATE));
  e.Free;

  // abort from the callback deletes the output file
  z.loadFromMemory(data);
  z.onProgress := function(position, totalsize, outputsize: qword): boolean
  begin
    aborted := true;
    result := false;
  end;
  check('EABORTED', z.compressToFile('files_aborted.gz') = ZFLATE_EABORTED);
  check('abort callback ran', aborted);
  check('aborted file deleted', not fileexists('files_aborted.gz'));
  z.onProgress := nil;
  z.Free;

  // interop: gzip a known text for a foreign decoder, decode a foreign file if present
  var t := TZFlateFile.Create;
  t.loadFromMemory(INTEROP_TEXT);
  check('interop out', t.compressToFile('files_out.gz') = ZFLATE_OK);
  if fileexists('files_in.gz') then begin
    check('interop foreign gzip file', t.openFile('files_in.gz') and (tostr(t.decompress) = INTEROP_TEXT));
  end;
  t.Free;

  writeln('=== passed: ', passed, ', failed: ', failed, ' ===');
  if failed > 0 then ExitCode := 1;
  readln;
end.
