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
  writeln('saves as gzipped.gz');

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

begin
  try
    demo1; writeln;
    demo2; writeln;
    demo3; writeln;
  finally
    readln;
  end;
end.

