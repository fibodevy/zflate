program demo;

uses Windows, zflate;

//detect compression type (ZLIB/GZIP) and decompress the file
procedure demo1;
var
  s: string;
  h: hwnd;
  d: dword;
  type_, start, size: dword;
  z: tzflate;
  gzip: tgzipinfo;
begin
  //get file contents
  h := _lopen('test.txt.gz', OF_READ);
  if h = 0 then begin
    writeln('cant open file');
    exit;
  end;
  d := GetFileSize(h, nil);
  setlength(s, d);
  _lread(h, @s[1], d);
  _lclose(h);

  writeln('input size = ', length(s));
  if length(s) = 0 then exit;

  //find stream type
  if zfindstream(@s[1], length(s), type_, start, size) then begin
    writeln('found stream');
    writeln('type  = ', type_);
    writeln('start = ', start);
    writeln('size  = ', size);
    writeln;

    if type_ = ZSTREAM_GZIP then begin
      writeln('stream is GZIP, reading header...');

      if zreadgzipheader(@s[1], gzip) then begin
        writeln('mod time = ', gzip.modtime);
        writeln('filename = ', gzip.filename);
        writeln;
      end;
    end;

    writeln('trying to decompress');
    writeln;

    zinflateinit(z);
    zinflatewrite(z, @s[1+start], size, true);

    writeln('decompressed data = ', pchar(@z.buffer[0]));
  end else begin
    writeln('no stream found, it may be pure deflated data');
  end;

  writeln('done demo 1');
end;

//GZIP compress string and save it to file
procedure demo2;
var
  h: hwnd;
  s: string;
begin
  //create gzipped file
  s := 'gzip compressed content';

  s := gzencode(s, 9, 'some file name.txt', 'some comment');
  writeln('compressed size = ', length(s));

  //delete old file if exists
  SetFileAttributes('gzipped.gz', 0);
  DeleteFile('gzipped.gz');

  //save new file
  h := _lcreat('gzipped.gz', OF_WRITE);
  _lwrite(h, @s[1], length(s));
  _lclose(h);
  writeln('saved as gzipped.gz');

  writeln('done demo 2');
end;

//ZLIB compress string and save it to file
procedure demo3;
var
  h: hwnd;
  s: string;
begin
  //create gzipped file
  s := 'zlib compressed content';

  s := gzcompress(s);
  writeln('compressed size = ', length(s));

  //delete old file if exists
  SetFileAttributes('compressed.zlib', 0);
  DeleteFile('compressed.zlib');

  //save new file
  h := _lcreat('compressed.zlib', OF_WRITE);
  _lwrite(h, @s[1], length(s));
  _lclose(h);
  writeln('saved as compressed.zlib');

  writeln('done demo 3');
end;

procedure decompressfile(path: string);
var
  h: hwnd;
  d: dword;
  s: string;
  streamtype, startsat, trailing: dword;
  size: dword;
  p: pchar;
begin
  writeln('file = ', path);

  //get file contents
  h := _lopen(pchar(path), OF_READ);
  if h = 0 then begin
    writeln('cant open file');
    exit;
  end;
  d := GetFileSize(h, nil);
  setlength(s, d);
  _lread(h, @s[1], d);
  _lclose(h);

  writeln('got ', length(s), ' bytes of compressed data');

  //if you call zstreambasicinfo make sure you have at least 10 bytes od data available!
  //get info about stream
  if (length(s) > 10) and zstreambasicinfo(@s[1], streamtype, startsat, trailing) then begin
    writeln('detected stream type ', streamtype);
    writeln('streams starts at ', startsat);
    writeln('stream trailing bytes is ', trailing);
    size := d-startsat-trailing;
  end else begin
    //unknown stream
    writeln('couldnt determine stream type');
    writeln('trying to decompress anyway');
    startsat := 0;
    size := d;
  end;

  //inflate stream
  if gzinflate(@s[1+startsat], size, p, d) then begin
    writeln('decompressed ', d, ' bytes');
    setlength(s, d);
    move(p^, s[1], d);
    writeln('decompressed data = "', s, '"');
  end else begin
    writeln('could NOT decompress data!');
  end;
end;

procedure demo4;
var
  s: string;
begin
  s := 'php_gzdeflate';
  writeln('attempting to decompress "', s, '" file');
  decompressfile(s);
  writeln;

  s := 'php_gzcompress';
  writeln('attempting to decompress "', s, '" file');
  decompressfile(s);
  writeln;

  s := 'php_gzencode';
  writeln('attempting to decompress "', s, '" file');
  decompressfile(s);
  writeln;

  writeln('done demo 4');
end;

begin
  try
    demo1; writeln;
    demo2; writeln;
    demo3; writeln;
    demo4; writeln;
  finally
    readln;
  end;
end.

