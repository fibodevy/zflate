program demo;

uses Windows, zflate, zflatefiles;

function onprogress(position, totalsize, outputsize: dword): boolean;
var
  pc: dword;
begin
  pc := trunc(position/totalsize*100);
  writeln('progress = ', pc, '% , position = ', position, ', totalsize = ', totalsize, ', outsize = ', outputsize);

  //return true to continue
  result := true;

  //or false to abort
  //if pc >= 50 then result := false;
end;

var
  src, dst: string;
  q: qword;

begin
  src := 'vid.mp4';
  dst := src+'.gz';

  //compress file
  q := GetTickCount64;
  if gzencode_file(src, dst, 9, 'custom file name.mp4', '', @onprogress, 10) then begin
    writeln('file compressed to ', dst);
  end else begin
    writeln('error compressing');
    writeln('error: ', zflatetranslatecode(zlasterror));
  end;
  writeln('took ', GetTickCount64-q, ' ms');
  writeln;

  //and decompress
  q := GetTickCount64;
  if gzdecode_file(dst, src+'.out.mp4', @onprogress, 10) then begin
    writeln('file decompressed!');
  end else begin
    writeln('error decompressing');    
    writeln('error: ', zflatetranslatecode(zlasterror));
  end; 
  writeln('took ', GetTickCount64-q, ' ms');
  writeln;

  readln;
end.

