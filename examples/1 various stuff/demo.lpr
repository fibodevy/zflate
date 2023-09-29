program demo;

uses Windows, zflate;

function file_get_contents(path: string): string;
var
  h: hwnd;
  d: dword;
begin
  result := '';
  h := _lopen(pchar(path), OF_READ);
  if h = 0 then exit;
  d := GetFileSize(h, nil);
  setlength(result, d);
  _lread(h, @result[1], d);
  _lclose(h);
end;

procedure file_put_contents(path, data: string);
var
  h: hwnd;
begin
  h := _lcreat(pchar(path), OF_WRITE);
  if h = 0 then begin
    writeln('FILE PUT CONTENTS FAILED');
    exit;
  end;
  _lwrite(h, @data[1], length(data));
  _lclose(h);
end;

procedure file_delete(path: string);
begin
  SetFileAttributes(pchar(path), 0);
  DeleteFile(pchar(path));
end;

//GZIP compress string and save it to file
procedure demo1;
var
  s: string;
begin
  writeln('** demo 1 **');

  //create gzipped file
  s := 'gzip compressed content';
  s := gzencode(s, 9, 'some file name.txt', 'some comment');

  writeln('GZIP compressed size = ', length(s));

  //delete old file if exists
  file_delete('compressed.gz');

  //save new file
  file_put_contents('compressed.gz', s);

  writeln('saved as compressed.gz');
end;

//ZLIB compress string and save it to file
procedure demo2;
var
  s: string;
begin
  writeln('** demo 2 **');

  //create gzipped file
  s := 'zlib compressed content';
  s := gzcompress(s);

  writeln('ZLIB compressed size = ', length(s));

  //delete old file if exists
  file_delete('compressed.zlib');

  //save new file
  file_put_contents('compressed.zlib', s);

  writeln('saved as compressed.zlib');
end;

procedure demo3;
var
  s: string;
begin
  writeln('** demo 3: decompress PHP output files **');

  s := 'php_gzdeflate';
  writeln('attempting to decompress "', s, '" file');
  writeln('result = "', zdecompress(file_get_contents(s)), '"');
  writeln;
  s := 'php_gzcompress';
  writeln('attempting to decompress "', s, '" file');
  writeln('result = "', zdecompress(file_get_contents(s)), '"');
  writeln;
  s := 'php_gzencode';
  writeln('attempting to decompress "', s, '" file');
  writeln('result = "', zdecompress(file_get_contents(s)), '"');
end;

procedure demo4;
begin       
  writeln('** demo 4 **');
  writeln('decompress 1 = ', zdecompress(file_get_contents('php_gzdeflate')));
  writeln('decompress 1 = ', gzinflate(file_get_contents('php_gzdeflate')));
  writeln('decompress 2 = ', zdecompress(file_get_contents('php_gzcompress')));
  writeln('decompress 2 = ', gzuncompress(file_get_contents('php_gzcompress')));
  writeln('decompress 3 = ', zdecompress(file_get_contents('php_gzencode')));
  writeln('decompress 3 = ', gzdecode(file_get_contents('php_gzencode')));
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

