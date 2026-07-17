program threads;

{ zuse_threads splits compression across worker threads. Each chunk becomes its
  own DEFLATE block on its own core, and the blocks are written back in order,
  so the result is an ordinary gzip stream that any decoder reads.
  Build with optimizations, or the numbers are about a third lower:
  fpc -O2 -Fu../src threads.pp }

{$mode unleashed}

uses sysutils, zflate;

var
  src: string;
  spos: integer;
  acc: string;

function reader(buf: pointer; maxlen: dword): dword;
begin
  var left := length(src) - spos;
  if left > maxlen then left := maxlen;
  if left > 0 then Move(src[1+spos], buf^, left);
  spos := spos + left;
  result := left;
end;

function writer(data: pointer; datasize: dword): boolean;
begin
  var old := length(acc);
  setlength(acc, old + datasize);
  if datasize > 0 then Move(data^, acc[old+1], datasize);
  result := true;
end;

// Deterministic text-like payload. It must not repeat itself: the codec cuts
// the input into 1 MB blocks and compresses each on its own, so a payload built
// by copying one megabyte over and over would hand every block identical data
// and the levels would all land on the same ratio.
function maketext(size: integer): string;
const
  WORDS: array[12] of string = ('deflate', 'stream', 'compress', 'the quick brown fox', 'zflate',
    'lorem ipsum dolor sit amet', 'consectetur', 'adipiscing elit', 'huffman', 'window', 'match', 'literal');
begin
  RandSeed := 3;
  setlength(result, size);
  var p := 1;
  while p <= size do begin
    var w := WORDS[Random(12)] + ' ';
    if Random(8) = 0 then w := w + IntToStr(Random(100_000)) + ' ';
    if Random(20) = 0 then w := w + sLineBreak;
    var n := length(w);
    if p + n - 1 > size then n := size - p + 1;
    Move(w[1], result[p], n);
    inc(p, n);
  end;
end;

begin
  writeln('building test data...');
  src := maketext(96*1024*1024);

  writeln('input: ', length(src) div (1024*1024), ' MB, cores available: ', GetCPUCount);
  writeln;
  writeln('threads    time      speed      output     roundtrip');

  var basetime: double := 0;
  for var nt in [1, 2, 4, 8] do begin
    zuse_threads := nt;              // 0 or 1 = sequential, N = N workers
    spos := 0; acc := '';

    var t := GetTickCount64;
    var code := gzencode_stream(@reader, @writer, length(src), ZFLATE_BEST);
    var secs := (GetTickCount64 - t) / 1000;

    if code <> ZFLATE_OK then begin writeln('failed: ', zflate_error_str(code)); halt(1); end;
    if nt = 1 then basetime := secs;

    // the parallel output is a plain gzip stream: the ordinary decoder reads it
    var ok := gzdecode(acc) = src;

    writeln(format('%4d   %7.2fs   %6.1f MB/s   %5.1f MB   %s   %.2fx', [nt, secs,
      length(src) / (1024*1024) / secs, length(acc) / (1024*1024),
      BoolToStr(ok, 'identical', 'MISMATCH!'), basetime / secs]));
  end;

  zuse_threads := 1;
  writeln;
  writeln('decompression is always single-threaded: a generic DEFLATE stream');
  writeln('carries no block index, so it cannot be split up front.');
end.
