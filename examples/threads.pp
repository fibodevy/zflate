program threads;

{ zuse_threads splits compression across worker threads. Each chunk becomes its
  own DEFLATE block on its own core, and the blocks are written back in order,
  so the result is an ordinary gzip stream that any decoder reads.
  Build: fpc -Fu../src threads.pp }

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

begin
  // ~96 MB of text-like payload
  writeln('building test data...');
  RandSeed := 3;
  var chunk := '';
  while length(chunk) < 1024*1024 do
    chunk := chunk + 'the quick brown fox jumps over the lazy dog ' + IntToStr(Random(1000)) + ' ';
  setlength(chunk, 1024*1024);
  src := '';
  setlength(src, 96*1024*1024);
  for var i := 0 to 95 do Move(chunk[1], src[1 + i*1024*1024], 1024*1024);

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
