program file_progress;

{ Compressing a file with a live progressbar, throughput and ETA, then
  decompressing it back and verifying. Pass a file to work on, or let the
  example generate one. Build: fpc -Fu../src file_progress.pp }

{$mode unleashed}

uses sysutils, zflate, zflatefiles;

const
  BARWIDTH = 34;

var
  started: qword;
  lastdraw: qword = 0;
  caption: string;
  showratio: boolean = false;   // output/input only means something while compressing

function human(bytes: qword): string;
begin
  if bytes >= 1024*1024*1024 then result := format('%.1f GB', [bytes / (1024*1024*1024)])
  else if bytes >= 1024*1024 then result := format('%.1f MB', [bytes / (1024*1024)])
  else if bytes >= 1024 then result := format('%.1f KB', [bytes / 1024])
  else result := format('%d B', [bytes]);
end;

// one progressbar line, redrawn in place; force draws the final 100% line
procedure draw(position, totalsize, outputsize: qword; force: boolean);
begin
  var now_ := GetTickCount64;
  if (not force) and (now_ - lastdraw < 50) then exit;   // 20 fps is plenty
  lastdraw := now_;

  var elapsed := (now_ - started) / 1000;
  if elapsed <= 0 then elapsed := 0.001;
  var speed := position / elapsed;                        // bytes per second
  var frac := if totalsize > 0 then position / totalsize else 0;
  var filled := round(frac * BARWIDTH);

  var eta := '--';
  if (speed > 0) and (totalsize > position) then eta := format('%.1fs', [(totalsize - position) / speed]);

  var ratio := '';
  if showratio and (position > 0) and (outputsize > 0) then ratio := format('  ratio %.0f%%', [outputsize / position * 100]);

  write(#13, caption, ' [', StringOfChar('#', filled), StringOfChar('-', BARWIDTH - filled), '] ',
    format('%5.1f%%', [frac * 100]), '  ', human(round(speed)):9, '/s  ',
    human(position), '/', human(totalsize), '  ETA ', eta:5, ratio, '   ');
end;

// the callback zflate calls; returning false would abort the operation
function onprogress(position, totalsize, outputsize: qword): boolean;
begin
  draw(position, totalsize, outputsize, false);
  result := true;
end;

procedure makedemofile(const path: string; mb: integer);
begin
  writeln('generating a ', mb, ' MB demo file: ', path);
  var f: file;
  assign(f, path);
  rewrite(f, 1);
  var chunk: string := '';
  RandSeed := 7;
  while length(chunk) < 1024*1024 do
    chunk := chunk + 'zflate demo payload line ' + IntToStr(Random(10_000)) + ', mostly repetitive text' + sLineBreak;
  setlength(chunk, 1024*1024);
  for var i := 1 to mb do blockwrite(f, chunk[1], length(chunk));
  system.close(f);
end;

function filesize_(const path: string): qword;
var f: file;
begin
  result := 0;
  assign(f, path);
  {$I-} reset(f, 1); {$I+}
  if IOResult <> 0 then exit;
  result := system.filesize(f);
  system.close(f);
end;

var
  src: string;

begin
  if ParamCount >= 1 then src := ParamStr(1)
  else begin
    src := 'demo_payload.bin';
    if filesize_(src) = 0 then makedemofile(src, 64);
  end;

  if filesize_(src) = 0 then begin
    writeln('no such file: ', src);
    halt(1);
  end;

  var insize := filesize_(src);
  writeln('input: ', src, '  (', human(insize), ')');
  writeln('threads: ', zuse_threads, ' (set zuse_threads to fan out across cores)');
  writeln;

  // ---- compress ----
  caption := 'compress  ';
  showratio := true;
  started := GetTickCount64;
  var code := gzencode_file(src, src + '.gz', ZFLATE_BEST, @onprogress);
  draw(insize, insize, filesize_(src + '.gz'), true);
  writeln;
  if code <> ZFLATE_OK then begin
    writeln('failed: ', zflate_error_str(code));
    halt(1);
  end;
  var took := (GetTickCount64 - started) / 1000;
  var gzsize := filesize_(src + '.gz');
  writeln(format('compressed %s -> %s (%.1f%%) in %.2fs, %s/s', [human(insize), human(gzsize),
    gzsize / insize * 100, took, human(round(insize / took))]));
  writeln;

  // ---- decompress ----
  caption := 'decompress';
  showratio := false;
  started := GetTickCount64;
  lastdraw := 0;
  code := zdecompress_file(src + '.gz', src + '.out', @onprogress);
  draw(gzsize, gzsize, insize, true);
  writeln;
  if code <> ZFLATE_OK then begin
    writeln('failed: ', zflate_error_str(code));
    halt(1);
  end;
  took := (GetTickCount64 - started) / 1000;
  writeln(format('decompressed back to %s in %.2fs', [human(filesize_(src + '.out')), took]));
  writeln;

  writeln('size matches original: ', filesize_(src + '.out') = insize);
  writeln('(gzip integrity is verified by the crc32 + size footer during decompression)');
end.
