program basic;

{ Compressing and decompressing strings, bytes and raw buffers, in all three
  formats, plus auto-detection. Build: fpc -Fu../src basic.pp }

{$mode unleashed}

uses sysutils, zflate;

procedure strings;
begin
  writeln('-- strings --');
  var s := 'the quick brown fox jumps over the lazy dog, and does it again and again and again';

  var raw := gzdeflate(s);      // DEFLATE
  var zlib := gzcompress(s);    // ZLIB
  var gzip := gzencode(s);      // GZIP

  writeln('original : ', length(s), ' bytes');
  writeln('gzdeflate: ', length(raw), ' bytes -> ', gzinflate(raw) = s);
  writeln('gzcompress: ', length(zlib), ' bytes -> ', gzuncompress(zlib) = s);
  writeln('gzencode : ', length(gzip), ' bytes -> ', gzdecode(gzip) = s);
  writeln;
end;

procedure autodetect;
begin
  writeln('-- zdecompress detects the format for you --');
  for var packed_ in [gzdeflate('detect me'), gzcompress('detect me'), gzencode('detect me')] do begin
    var (kind, at, footer) := stream_info(pointer(packed_), length(packed_));
    var name := match kind of
      ZFLATE_GZIP: 'GZIP';
      ZFLATE_ZLIB: 'ZLIB';
      _: 'DEFLATE';
    end;
    writeln(name:8, ': stream at ', at, ', footer ', footer, ' bytes -> "', zdecompress(packed_), '"');
  end;
  writeln;
end;

procedure levels;
begin
  writeln('-- compression levels --');
  // something with long repeats, so the levels have room to differ
  var s := '';
  for var i := 1 to 20_000 do s := s + 'lorem ipsum dolor sit amet ' + IntToStr(i mod 100) + ' ';

  writeln('original: ', length(s), ' bytes');
  for var lv := 0 to 9 do
    writeln('level ', lv, ': ', length(gzencode(s, lv)):8, ' bytes');
  writeln('(level 0 stores, 1 is fastest, 9 compresses best, 4 is the default)');
  writeln;
end;

procedure bytesandbuffers;
begin
  writeln('-- TBytes and raw pointers --');
  var b: TBytes;
  setlength(b, 50_000);
  for var i := 0 to high(b) do b[i] := i mod 64;
  writeln('TBytes  : ', length(b), ' -> ', length(gzencode(b)), ' bytes, roundtrip = ', gzdecode(gzencode(b)) = b);

  // the pointer form returns the error code and hands out a heap buffer
  var s := 'compress me through a pointer';
  var p: pointer; var n: dword;
  if gzencode(pointer(s), length(s), p, n) = ZFLATE_OK then begin
    var p2: pointer; var n2: dword;
    if gzdecode(p, n, p2, n2) = ZFLATE_OK then begin
      var back: string;
      setlength(back, n2);
      Move(p2^, back[1], n2);
      writeln('pointer : ', length(s), ' -> ', n, ' bytes, roundtrip = ', back = s);
      FreeMem(p2);
    end;
    FreeMem(p);   // the caller owns the buffer
  end;
  writeln;
end;

procedure errors;
begin
  writeln('-- errors are codes, never exceptions --');
  var junk := 'this is definitely not a compressed stream';
  var p: pointer; var n: dword;
  writeln('gzdecode(junk)     = ', zflate_error_str(gzdecode(pointer(junk), length(junk), p, n)));

  var good := gzencode('hello');
  good[length(good)-5] := chr(ord(good[length(good)-5]) xor $ff);   // break the crc32
  gzdecode(good);
  writeln('corrupted checksum = ', zflate_error_str(zlasterror));
  writeln;
end;

begin
  strings;
  autodetect;
  levels;
  bytesandbuffers;
  errors;
  writeln('done');
end.
