program demo;

uses SysUtils, zflate, Classes, Windows;

procedure rundemo;
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
  d := GetFileSize(h, nil);
  setlength(s, d);
  _lread(h, @s[1], d);
  _lclose(h);

  writeln('input size = ', length(s));

  //find streamtype
  if zfindstream(@s[1], length(s), type_, start, size) then begin
    writeln('found stream');
    writeln('type  = ', type_);
    writeln('start = ', start);
    writeln('size  = ', size);
    writeln('first byte = ', inttohex(pbyte(@s[1+start])^));
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
end;

begin
  try
    rundemo;
  finally
    readln;
  end;
end.

