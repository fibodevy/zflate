program test_zflate;

{$mode unleashed}

uses sysutils, zflate;

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
    writeln(tag, ' ', name, ' (zlasterror=', zlasterror, ' ', zflate_error_str(zlasterror), ')');
  end;
end;

// text-like data: repeated sentences with drifting fragments, so matches are long
// and the level knobs (chain length, nice length, lazy matching) actually bite
function maketext(size: integer): string;
const
  WORDS: array[12] of string = ('deflate', 'stream', 'compress', 'the quick brown fox', 'zflate',
    'lorem ipsum dolor sit amet', 'consectetur', 'adipiscing elit', 'huffman', 'window', 'match', 'literal');
begin
  result := '';
  RandSeed := 99;
  while length(result) < size do begin
    result := result + WORDS[Random(12)] + ' ';
    if Random(8) = 0 then result := result + IntToStr(Random(100_000)) + ' ';
    if Random(20) = 0 then result := result + sLineBreak;
  end;
  setlength(result, size);
end;

// compressible text mixed with pseudorandom bytes
function makedata(size: integer): string;
begin
  setlength(result, size);
  RandSeed := 42;
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

const
  INTEROP_TEXT = 'zflate interop test: the quick brown fox jumps over the lazy dog 1234567890';
  ZSCHUNK_TEST = 900_000;   // reader chunk cap for the parallel-path tests

var
  o, o2: pointer;
  n, n2: dword;
  wacc: string;

// The unit's LENSYM / DISTSYM lookup tables are private, so they get checked the
// only way that matters: by driving real data through every length and every
// distance boundary. A wrong code index corrupts the stream, so a roundtrip that
// comes back byte-identical means the table entry was right.

// pseudorandom filler, so the gap between two markers cannot itself match
function filler(n: integer): string;
begin
  setlength(result, n);
  for var i := 1 to n do result[i] := chr(32 + (i * 7 + i div 13) mod 90);
end;

// every match length 3..258: a run of N identical bytes repeated once
function lensym_ok: boolean;
begin
  result := true;
  for var ln := 3 to 258 do begin
    var run := StringOfChar('x', ln);
    var s := run + filler(300) + run;      // forces exactly one match of length ln
    if gzinflate(gzdeflate(s)) <> s then result := false;
    if gzdecode(gzencode(s)) <> s then result := false;
  end;
end;

// every distance code boundary (each DB base, and one either side of it) plus the
// window edge; a wrong bucket in DISTSYM shows up as a corrupted roundtrip
function distsym_ok: boolean;
const
  BASES: array[30] of integer = (1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,
    769,1025,1537,2049,3073,4097,6145,8193,12_289,16_385,24_577);
begin
  result := true;
  var dists: array of integer := nil;
  for var b in BASES do
    for var d in [b-1, b, b+1] do
      if (d >= 1) and (d <= 32_768) then dists := dists + [d];
  dists := dists + [32_766, 32_767, 32_768];

  for var d in dists do begin
    // MARKER at position 0 and again exactly d bytes later
    var s := 'MARKERZ' + filler(d - 7) + 'MARKERZ';
    if length(s) <> d + 7 then continue;
    if gzinflate(gzdeflate(s)) <> s then result := false;
    if gzuncompress(gzcompress(s)) <> s then result := false;
  end;
end;

// streaming reader over a string, serving random-sized chunks up to maxchunk
function mkreader(s: string; maxchunk: integer): tzreader;
begin
  var pos := 0;
  result := function(buf: pointer; maxlen: dword): dword
  begin
    var want := 1 + Random(maxchunk);
    if want > maxlen then want := maxlen;
    if want > length(s) - pos then want := length(s) - pos;
    if want > 0 then Move(s[1+pos], buf^, want);
    pos := pos + want;
    result := want;
  end;
end;

// streaming writer accumulating into wacc
function mkwriter: tzwriter;
begin
  wacc := '';
  result := function(data: pointer; datasize: dword): boolean
  begin
    var old := length(wacc);
    setlength(wacc, old + datasize);
    if datasize > 0 then Move(data^, wacc[old+1], datasize);
    result := true;
  end;
end;

begin
  colors := enableColors;
  writeln('=== zflate tests ===');

  // string roundtrips
  var src := 'hello hello hello zflate, this string repeats repeats repeats itself';
  check('raw string roundtrip', gzinflate(gzdeflate(src)) = src);
  check('zlib string roundtrip', gzuncompress(gzcompress(src)) = src);
  check('gzip string roundtrip', gzdecode(gzencode(src)) = src);

  // tbytes roundtrips
  var tb: TBytes;
  setlength(tb, 10000);
  for var i := 0 to high(tb) do tb[i] := i mod 251;
  check('raw tbytes roundtrip', gzinflate(gzdeflate(tb)) = tb);
  check('zlib tbytes roundtrip', gzuncompress(gzcompress(tb)) = tb);
  check('gzip tbytes roundtrip', gzdecode(gzencode(tb)) = tb);

  // pointer roundtrip
  check('pointer gzencode', gzencode(pointer(src), length(src), o, n) = ZFLATE_OK);
  check('pointer gzdecode', gzdecode(o, n, o2, n2) = ZFLATE_OK);
  var back: string;
  setlength(back, n2);
  if n2 > 0 then Move(o2^, back[1], n2);
  check('pointer roundtrip data', back = src);
  FreeMem(o); FreeMem(o2);

  // empty input
  check('empty raw roundtrip', (gzinflate(gzdeflate('')) = '') and (zlasterror = ZFLATE_OK));
  check('empty zlib roundtrip', (gzuncompress(gzcompress('')) = '') and (zlasterror = ZFLATE_OK));
  check('empty gzip roundtrip', (gzdecode(gzencode('')) = '') and (zlasterror = ZFLATE_OK));

  // auto detection
  check('auto raw', zdecompress(gzdeflate(src)) = src);
  check('auto zlib', zdecompress(gzcompress(src)) = src);
  check('auto gzip', zdecompress(gzencode(src)) = src);

  // stream_info
  var g := gzencode(src);
  var z := gzcompress(src);
  var r := gzdeflate(src);
  var (st, at, foot) := stream_info(pointer(g), length(g));
  check('stream_info gzip', (st = ZFLATE_GZIP) and (at = 10) and (foot = 8));
  (st, at, foot) := stream_info(pointer(z), length(z));
  check('stream_info zlib', (st = ZFLATE_ZLIB) and (at = 2) and (foot = 4));
  (st, at, foot) := stream_info(pointer(r), length(r));
  check('stream_info raw fallback', (st = ZFLATE_RAW) and (at = 0) and (foot = 0));

  // header readers
  var zi: tzlibinfo;
  var gi: tgzipinfo;
  check('read_zlib_header ok', read_zlib_header(pointer(z), length(z), zi));
  check('read_zlib_header rejects gzip', not read_zlib_header(pointer(g), length(g), zi));
  check('read_gzip_header ok', read_gzip_header(pointer(g), length(g), gi));
  check('read_gzip_header rejects zlib', not read_gzip_header(pointer(z), length(z), gi));

  // error paths - no exceptions, just codes
  var garbage := 'certainly not a compressed stream';
  check('EZLIBINVALID', gzuncompress(pointer(garbage), length(garbage), o, n) = ZFLATE_EZLIBINVALID);
  check('EGZIPINVALID', gzdecode(pointer(garbage), length(garbage), o, n) = ZFLATE_EGZIPINVALID);
  check('EINFLATE on garbage', gzinflate(pointer(garbage), length(garbage), o, n) = ZFLATE_EINFLATE);

  var bad := z;
  bad[length(bad)] := chr(ord(bad[length(bad)]) xor $ff);   // corrupt adler32
  gzuncompress(bad);
  check('ECHECKSUM zlib', zlasterror = ZFLATE_ECHECKSUM);

  bad := g;
  bad[length(bad)-5] := chr(ord(bad[length(bad)-5]) xor $ff);  // corrupt crc32
  gzdecode(bad);
  check('ECHECKSUM gzip', zlasterror = ZFLATE_ECHECKSUM);

  bad := g;
  bad[length(bad)] := chr(ord(bad[length(bad)]) xor $ff);   // corrupt isize
  gzdecode(bad);
  check('EOUTPUTSIZE gzip', zlasterror = ZFLATE_EOUTPUTSIZE);

  var big := makedata(3*1024*1024);
  var cbig := gzdeflate(big);
  gzinflate(copy(cbig, 1, length(cbig) div 2));    // truncated stream
  check('EINFLATE truncated', zlasterror = ZFLATE_EINFLATE);

  // big data roundtrips
  check('big raw roundtrip', gzinflate(cbig) = big);
  check('big zlib roundtrip', gzuncompress(gzcompress(big)) = big);
  var gbig := gzencode(big);
  check('big gzip roundtrip', gzdecode(gbig) = big);
  writeln('  big data: ', length(big), ' -> ', length(gbig), ' bytes (gzip)');

  // ----- compression levels -----

  var text := maketext(4*1024*1024);
  var lvlsizes: array[10] of integer;
  var alllevelsok := true;
  for var lv := 0 to 9 do begin
    var c := gzencode(text, lv);
    lvlsizes[lv] := length(c);
    if gzdecode(c) <> text then alllevelsok := false;
    // every level must produce a stream the other containers' decoders accept too
    if gzinflate(gzdeflate(text, lv)) <> text then alllevelsok := false;
    if gzuncompress(gzcompress(text, lv)) <> text then alllevelsok := false;
    // and the noisy data must survive every level as well
    if gzdecode(gzencode(big, lv)) <> big then alllevelsok := false;
  end;
  check('all levels 0..9 roundtrip (gzip, raw, zlib)', alllevelsok);
  check('level 0 stores (output > input)', lvlsizes[0] > length(text));
  check('level 1 compresses', (lvlsizes[1] < length(text)) and (lvlsizes[1] > 0));
  check('level 9 beats level 1', lvlsizes[9] < lvlsizes[1]);
  check('level 9 beats level 6', lvlsizes[9] <= lvlsizes[6]);
  check('level 6 beats level 1', lvlsizes[6] < lvlsizes[1]);
  check('default level = 5', length(gzencode(text)) = lvlsizes[5]);
  check('ZFLATE_DEFAULT is the level you get without one', length(gzencode(text, ZFLATE_DEFAULT)) = length(gzencode(text)));
  check('level > 9 clamps to 9', length(gzencode(text, 42)) = lvlsizes[9]);
  write('  level sizes (4 MB text):');
  for var lv := 0 to 9 do write(' ', lv, '=', lvlsizes[lv]);
  writeln;

  // level is advertised in the container header
  var zh := gzcompress(big, 1);
  check('zlib header FLEVEL for level 1', (byte(zh[1]) = $78) and (byte(zh[2]) = $01));
  zh := gzcompress(big, 6);
  check('zlib header FLEVEL for level 6', byte(zh[2]) = $9c);
  zh := gzcompress(big, 9);
  check('zlib header FLEVEL for level 9', byte(zh[2]) = $da);
  var gh := gzencode(big, 9);
  check('gzip XFL for level 9', byte(gh[9]) = 2);
  gh := gzencode(big, 1);
  check('gzip XFL for level 1', byte(gh[9]) = 4);

  // levels through the streaming API, sequential and parallel
  gzencode_stream(mkreader(big, 200000), mkwriter, length(big), 1);
  var sl1 := length(wacc);
  check('stream level 1 roundtrips', gzdecode(wacc) = big);
  gzencode_stream(mkreader(big, 200000), mkwriter, length(big), 9);
  check('stream level 9 roundtrips', gzdecode(wacc) = big);
  check('stream level 9 beats level 1', length(wacc) < sl1);
  gzencode_stream(mkreader(big, 200000), mkwriter, length(big), 0);
  check('stream level 0 roundtrips', gzdecode(wacc) = big);
  zuse_threads := 4;
  gzencode_stream(mkreader(big, 200000), mkwriter, length(big), 1);
  check('parallel level 1 roundtrips', gzdecode(wacc) = big);
  gzencode_stream(mkreader(big, 200000), mkwriter, length(big), 0);
  check('parallel level 0 roundtrips', gzdecode(wacc) = big);
  zuse_threads := 1;

  // the length/distance code lookup tables must agree with a plain linear scan
  // over the RFC 1951 base tables, for every value they can ever see
  check('LENSYM matches linear scan for 3..258', lensym_ok);
  check('DISTSYM matches linear scan for 1..32768', distsym_ok);

  // checksum vectors
  check('crc32b vector', crc32b(0, pbyte(pchar('123456789')), 9) = $CBF43926);
  check('adler32 vector', adler32(1, pbyte(pchar('Wikipedia')), 9) = $11E60398);

  // progress callback (anonymous function)
  var calls := 0;
  zprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    inc(calls);
    result := true;
  end;
  check('progress roundtrip', gzdecode(gbig) = big);
  check('progress called', calls > 10);

  // abort from the callback
  zprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    result := false;
  end;
  check('EABORTED compress', (gzencode(big) = '') and (zlasterror = ZFLATE_EABORTED));
  var cnt := 0;
  zprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    inc(cnt);
    result := cnt < 3;
  end;
  check('EABORTED decompress', (gzdecode(gbig) = '') and (zlasterror = ZFLATE_EABORTED));
  zprogress := nil;

  // ----- streaming API -----

  RandSeed := 777;
  var sdata := makedata(5*1024*1024);

  check('gzencode_stream gzip', gzencode_stream(mkreader(sdata, 100_000), mkwriter, length(sdata)) = ZFLATE_OK);
  var sgz := wacc;
  check('stream gzip decodes one-shot', gzdecode(sgz) = sdata);

  check('gzencode_stream zlib', gzcompress_stream(mkreader(sdata, 65_536), mkwriter) = ZFLATE_OK);
  check('stream zlib decodes one-shot', gzuncompress(wacc) = sdata);

  check('gzencode_stream raw', gzdeflate_stream(mkreader(sdata, 65_536), mkwriter) = ZFLATE_OK);
  check('stream raw decodes one-shot', gzinflate(wacc) = sdata);

  check('zdecompress_stream of one-shot gzip', zdecompress_stream(mkreader(gzencode(sdata), 3333), mkwriter) = ZFLATE_OK);
  check('zdecompress_stream gzip data', wacc = sdata);
  check('zdecompress_stream of stream gzip, tiny chunks', zdecompress_stream(mkreader(sgz, 7), mkwriter) = ZFLATE_OK);
  check('zdecompress_stream tiny chunks data', wacc = sdata);
  check('zdecompress_stream of one-shot zlib', zdecompress_stream(mkreader(gzcompress(sdata), 65_536), mkwriter) = ZFLATE_OK);
  check('zdecompress_stream zlib data', wacc = sdata);
  check('zdecompress_stream of raw deflate', zdecompress_stream(mkreader(gzdeflate(sdata), 65_536), mkwriter) = ZFLATE_OK);
  check('zdecompress_stream raw data', wacc = sdata);

  // pure random data forces stored blocks through the streaming path
  var rnd: string;
  setlength(rnd, 2*1024*1024 + 12_345);
  for var i := 1 to length(rnd) do rnd[i] := chr(Random(256));
  check('gzencode_stream stored blocks', gzencode_stream(mkreader(rnd, 300_000), mkwriter) = ZFLATE_OK);
  var srnd := wacc;
  check('stored one-shot decode', gzdecode(srnd) = rnd);
  check('stored stream decode', zdecompress_stream(mkreader(srnd, 65_536), mkwriter) = ZFLATE_OK);
  check('stored stream data', wacc = rnd);

  // empty input through the streams
  check('gzencode_stream empty', gzencode_stream(mkreader('', 100), mkwriter) = ZFLATE_OK);
  var sempty := wacc;
  check('empty stream decodes one-shot', (gzdecode(sempty) = '') and (zlasterror = ZFLATE_OK));
  check('zdecompress_stream empty', zdecompress_stream(mkreader(sempty, 100), mkwriter) = ZFLATE_OK);
  check('zdecompress_stream empty data', wacc = '');

  // streaming error paths
  bad := sgz;
  bad[length(bad)-5] := chr(ord(bad[length(bad)-5]) xor $ff);  // corrupt crc32
  check('stream ECHECKSUM', zdecompress_stream(mkreader(bad, 65_536), mkwriter) = ZFLATE_ECHECKSUM);
  bad := sgz;
  bad[length(bad)] := chr(ord(bad[length(bad)]) xor $ff);      // corrupt isize
  check('stream EOUTPUTSIZE', zdecompress_stream(mkreader(bad, 65_536), mkwriter) = ZFLATE_EOUTPUTSIZE);
  check('stream EINFLATE truncated', zdecompress_stream(mkreader(copy(sgz, 1, length(sgz) div 2), 65_536), mkwriter) = ZFLATE_EINFLATE);

  // abort from the sink and from the progress hook
  check('stream abort writer', zdecompress_stream(mkreader(sgz, 65536), function(data: pointer; datasize: dword): boolean
  begin
    result := false;
  end) = ZFLATE_EABORTED);
  zprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    result := false;
  end;
  check('stream abort compress progress', gzencode_stream(mkreader(sdata, 65_536), mkwriter) = ZFLATE_EABORTED);
  check('stream abort decompress progress', zdecompress_stream(mkreader(sgz, 65_536), mkwriter) = ZFLATE_EABORTED);
  zprogress := nil;

  // ----- parallel compression (zuse_threads > 1) -----

  zuse_threads := 4;
  check('parallel gzip compresses', gzencode_stream(mkreader(sdata, ZSCHUNK_TEST), mkwriter, length(sdata)) = ZFLATE_OK);
  var pgz := wacc;
  check('parallel gzip decodes one-shot', gzdecode(pgz) = sdata);
  check('parallel gzip decodes via stream', (zdecompress_stream(mkreader(pgz, 4096), mkwriter) = ZFLATE_OK) and (wacc = sdata));

  check('parallel zlib', gzcompress_stream(mkreader(sdata, ZSCHUNK_TEST), mkwriter) = ZFLATE_OK);
  check('parallel zlib roundtrips', gzuncompress(wacc) = sdata);
  check('parallel raw', gzdeflate_stream(mkreader(sdata, ZSCHUNK_TEST), mkwriter) = ZFLATE_OK);
  check('parallel raw roundtrips', gzinflate(wacc) = sdata);

  // pure random (stored blocks) through the parallel path
  check('parallel stored blocks', gzencode_stream(mkreader(rnd, ZSCHUNK_TEST), mkwriter) = ZFLATE_OK);
  check('parallel stored roundtrips', gzdecode(wacc) = rnd);

  // input smaller than one chunk, and empty, still valid
  check('parallel small input', (gzencode_stream(mkreader('tiny', 10), mkwriter) = ZFLATE_OK) and (gzdecode(wacc) = 'tiny'));
  check('parallel empty input', (gzencode_stream(mkreader('', 10), mkwriter) = ZFLATE_OK) and (gzdecode(wacc) = ''));

  // parallel output is byte-identical to sequential? no (block layout differs), but both must decode equal
  zuse_threads := 1;
  gzencode_stream(mkreader(sdata, ZSCHUNK_TEST), mkwriter, length(sdata));
  check('seq and parallel decode to the same bytes', gzdecode(pgz) = gzdecode(wacc));

  // abort still works in the parallel path
  zuse_threads := 4;
  zprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    result := false;
  end;
  check('parallel abort', gzencode_stream(mkreader(sdata, ZSCHUNK_TEST), mkwriter) = ZFLATE_EABORTED);
  zprogress := nil;
  zuse_threads := 1;

  // parallel gzip for the external interop check below
  zuse_threads := 4;
  gzencode_stream(mkreader(INTEROP_TEXT + INTEROP_TEXT + INTEROP_TEXT, 20), mkwriter);
  savefile('par.gz', wacc);
  zuse_threads := 1;
  writeln('  interop: par.gz written (parallel, multi-block)');

  // ----- foreign encoder: files produced by PHP's gzdeflate/gzcompress/gzencode -----
  // a different implementation entirely, so decoding these proves the decoder
  // follows the RFCs rather than just its own encoder

  var php := loadfile('../examples/php_gzdeflate');
  check('php gzdeflate file present', php <> '');
  check('decode PHP DEFLATE', gzinflate(php) = 'gzdeflate() test');
  check('decode PHP DEFLATE via zdecompress', zdecompress(php) = 'gzdeflate() test');

  php := loadfile('../examples/php_gzcompress');
  check('php gzcompress file present', php <> '');
  check('decode PHP ZLIB (adler32 verified)', gzuncompress(php) = 'gzcompress() test');
  check('decode PHP ZLIB via zdecompress', zdecompress(php) = 'gzcompress() test');

  php := loadfile('../examples/php_gzencode');
  check('php gzencode file present', php <> '');
  check('decode PHP GZIP (crc32 + size verified)', gzdecode(php) = 'gzencode() test');
  check('decode PHP GZIP via zdecompress', zdecompress(php) = 'gzencode() test');
  check('stream_info detects PHP gzip', stream_info(pointer(php), length(php)).streamtype = ZFLATE_GZIP);
  // and through the streaming decoder, one byte at a time
  check('decode PHP GZIP streamed 1 byte at a time', (zdecompress_stream(mkreader(php, 1), mkwriter) = ZFLATE_OK) and (wacc = 'gzencode() test'));

  // interop files: gzip + raw deflate of a known text, verified externally
  savefile('out.gz', gzencode(INTEROP_TEXT));
  savefile('out.raw', gzdeflate(INTEROP_TEXT));
  writeln('  interop: out.gz + out.raw written');

  // interop input files produced by a foreign compressor (if present)
  var foreign := loadfile('in.gz');
  if foreign <> '' then check('interop decode foreign gzip', gzdecode(foreign) = INTEROP_TEXT);
  foreign := loadfile('in.raw');
  if foreign <> '' then check('interop decode foreign deflate', gzinflate(foreign) = INTEROP_TEXT);

  writeln('=== passed: ', passed, ', failed: ', failed, ' ===');
  if failed > 0 then ExitCode := 1;
  readln;
end.
