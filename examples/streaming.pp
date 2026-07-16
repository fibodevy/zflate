program streaming;

{ The streaming API: input is pulled from a reader callback, output is pushed to
  a writer callback, so memory use stays constant no matter how big the stream
  is. Here it gzips one file into another through plain file handles, without
  ever holding either in memory. Build: fpc -Fu../src streaming.pp }

{$mode unleashed}

uses sysutils, zflate;

var
  fin, fout: file;

// reader: hand zflate up to maxlen bytes, return how many; 0 means end of input
function reader(buf: pointer; maxlen: dword): dword;
begin
  blockread(fin, buf^, maxlen, result);
end;

// writer: take a produced block; return false to abort the operation
function writer(data: pointer; datasize: dword): boolean;
begin
  blockwrite(fout, data^, datasize);
  result := true;
end;

procedure makedemofile(const path: string);
begin
  var f: file;
  assign(f, path);
  rewrite(f, 1);
  for var i := 1 to 20_000 do begin
    var line := format('line %d: the streaming api never holds the whole file%s', [i, sLineBreak]);
    blockwrite(f, line[1], length(line));
  end;
  system.close(f);
end;

var
  src: string = 'streaming_demo.txt';

begin
  if ParamCount >= 1 then src := ParamStr(1) else makedemofile(src);

  // ---- compress: src -> src.gz, streamed ----
  assign(fin, src);
  {$I-} reset(fin, 1); {$I+}
  if IOResult <> 0 then begin writeln('cannot open ', src); halt(1); end;
  var insize := filesize(fin);

  assign(fout, src + '.gz');
  rewrite(fout, 1);

  // report progress as it goes; totalsize is only used for the percentage
  zprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    write(#13'compressing ', position, ' / ', totalsize, ' bytes -> ', outputsize, '   ');
    result := true;    // false would abort with ZFLATE_EABORTED
  end;

  var code := gzencode_stream(@reader, @writer, insize, ZFLATE_BEST);
  zprogress := nil;
  writeln;

  var gzsize := filesize(fout);
  system.close(fin);
  system.close(fout);

  if code <> ZFLATE_OK then begin writeln('failed: ', zflate_error_str(code)); halt(1); end;
  writeln(format('%s: %d -> %d bytes (%.1f%%)', [src, insize, gzsize, gzsize / insize * 100]));

  // ---- decompress: src.gz -> src.out, streamed, container auto-detected ----
  assign(fin, src + '.gz');
  reset(fin, 1);
  assign(fout, src + '.out');
  rewrite(fout, 1);

  code := zdecompress_stream(@reader, @writer, gzsize);

  var outsize := filesize(fout);
  system.close(fin);
  system.close(fout);

  if code <> ZFLATE_OK then begin writeln('failed: ', zflate_error_str(code)); halt(1); end;
  writeln(format('back to %d bytes, matches original: %s', [outsize, BoolToStr(outsize = insize, true)]));
  writeln;
  writeln('peak heap during all of this: ', GetFPCHeapStatus.MaxHeapUsed div 1024, ' KB');
end.
