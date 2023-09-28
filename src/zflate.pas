{ MIT License

  Copyright (c) 2023 fibodevy https://github.com/fibodevy

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
}

unit zflate;

{$mode ObjFPC}{$H+}

interface

uses ZBase, ZInflate, ZDeflate, crc, adler;

type
  tzflate = record
    z: z_stream;
    totalout: qword;
    bytesavailable: dword;
    buffer: array[0..1024*32-1] of byte;
    error: string;
  end;

  tzlibinfo = record
    streamat: dword;
    footerlen: dword;
  end;

  tgzipinfo = record
    modtime: dword;
    filename: pchar;
    comment: pchar;
    streamat: dword;  
    footerlen: dword;
  end;

const
  ZSTREAM_ZLIB = 1;
  ZSTREAM_GZIP = 2;

//deflate chunks
function zdeflateinit(var z: tzflate; level: dword=9): boolean;
function zdeflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): boolean;

//inflate chunks
function zinflateinit(var z: tzflate): boolean;
function zinflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): boolean;

//read zlib header
function zreadzlibheader(data: pointer; var info: tzlibinfo): boolean;
//read gzip header
function zreadgzipheader(data: pointer; var info: tgzipinfo): boolean;
//find out where deflate stream starts and what is its size
function zfindstream(data: pointer; size: dword; var streamtype: dword; var startsat: dword; var streamsize: dword): boolean;
//get stream basic info; by reading just few first bytes you will know the stream type, where is deflate start and how many bytes are trailing bytes (footer)
function zstreambasicinfo(data: pointer; var streamtype: dword; var startsat: dword; var trailing: dword): boolean;

//compress whole DEFLATE buffer at once
function gzdeflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//compress whole DEFLATE string at once
function gzdeflate(str: string): string;
//decompress whole DEFLATE buffer at once
function gzinflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//decompress whole DEFLATE string at once
function gzinflate(str: string): string;

//make ZLIB header
function makezlibheader(compressionlevel: integer): string;
//make ZLIB footer
function makezlibfooter(adler: dword): string;
//compress whole ZLIB buffer at once
function gzcompress(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9): boolean;
//compress whole ZLIB string at once
function gzcompress(str: string; level: dword=9): string;
//dempress whole ZLIB buffer at once
function gzuncompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//dempress whole ZLIB string at once
function gzuncompress(str: string): string;

//make GZIP header
function makegzipheader(compressionlevel: integer; filename: string=''; comment: string=''): string;
//make GZIP footer
function makegzipfooter(originalsize: dword; crc: dword): string;
//compress whole GZIP buffer at once
function gzencode(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9; filename: string=''; comment: string=''): boolean;
//compress whole GZIP string at once
function gzencode(str: string; level: dword=9; filename: string=''; comment: string=''): string;
//decompress whole GZIP buffer at once
function gzdecode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//decompress whole GZIP string at once
function gzdecode(str: string): string;

implementation

function zerror(var z: tzflate; msg: string): boolean;
begin
  z.error := msg;
  result := false;
end;

// -- deflate chunks ----------------------

function zdeflateinit(var z: tzflate; level: dword=9): boolean;
begin
  result := false;     
  fillchar(z, sizeof(z), 0);
  if deflateInit2(z.z, level, Z_DEFLATED, -MAX_WBITS, DEF_MEM_LEVEL, 0) <> Z_OK then exit;
  result := true;
end;

function zdeflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): boolean;
var
  i: integer;
begin
  result := false;

  //try
  if size > 1024*32 then exit(zerror(z, 'max single chunk size is 32k'));

  z.z.next_in := data;
  z.z.avail_in := size;
  z.z.next_out := @z.buffer[0];
  z.z.avail_out := length(z.buffer);

  if lastchunk then
    i := deflate(z.z, Z_FINISH)
  else
    i := deflate(z.z, Z_NO_FLUSH);

  if i = Z_BUF_ERROR then exit(zerror(z, 'buffer error'));
  if i = Z_STREAM_ERROR then exit(zerror(z, 'stream error'));
  if i = Z_DATA_ERROR then exit(zerror(z, 'data error'));

  if (i = Z_OK) or (i = Z_STREAM_END) then begin
    z.bytesavailable := z.z.total_out-z.totalout;
    z.totalout += z.bytesavailable;
    result := true;
  end;

  if lastchunk then begin
    i := deflateEnd(z.z);
    result := i = Z_OK;
  end;

  //todo: check if this is how it should be done

  //finally
  //  if not result then deflateEnd(z.z);
  //end;
end;

// -- inflate chunks ----------------------

function zinflateinit(var z: tzflate): boolean;
begin
  result := false;
  fillchar(z, sizeof(z), 0);
  if inflateInit2(z.z, -MAX_WBITS) <> Z_OK then exit;
  result := true;
end;

function zinflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): boolean;
var
  i: integer;
begin
  result := false;

  z.z.next_in := data;
  z.z.avail_in := size;
  z.z.next_out := @z.buffer[0];
  z.z.avail_out := length(z.buffer);

  if lastchunk then
    i := inflate(z.z, Z_FINISH)
  else
    i := inflate(z.z, Z_NO_FLUSH);

  if i = Z_BUF_ERROR then exit(zerror(z, 'buffer error'));
  if i = Z_STREAM_ERROR then exit(zerror(z, 'stream error'));
  if i = Z_DATA_ERROR then exit(zerror(z, 'data error'));

  if (i = Z_OK) or (i = Z_STREAM_END) then begin
    z.bytesavailable := z.z.total_out-z.totalout;
    z.totalout += z.bytesavailable;
    result := true;
  end;

  if lastchunk then begin
    i := inflateEnd(z.z);
    result := i = Z_OK;
  end;
end;

function zreadzlibheader(data: pointer; var info: tzlibinfo): boolean;
begin
  fillchar(info, sizeof(info), 0);
  result := (pbyte(data)^ = $78) and (pbyte(data+1)^ in [$01, $5e, $9c, $da]);
  if not result then exit; 
  info.footerlen := 4;
  info.streamat := 2;
end;

function zreadgzipheader(data: pointer; var info: tgzipinfo): boolean;
var
  flags: byte;
  w: word;
begin          
  fillchar(info, sizeof(info), 0);
  result := false;
  if not ((pbyte(data)^ = $1f) and (pbyte(data+1)^ = $8b)) then exit;
  info.footerlen := 8;

  //mod time
  move((data+4)^, info.modtime, 4);

  //stream position
  info.streamat := 10;

  //flags
  flags := pbyte(data+3)^;

  //extra
  if (flags and $04) <> 0 then begin
    w := pword(data+info.streamat)^;
    info.streamat += 2+w;
  end;

  //filename
  if (flags and $08) <> 0 then begin
    info.filename := pchar(data+info.streamat);
    info.streamat += length(info.filename)+1;
  end;

  //comment
  if (flags and $10) <> 0 then begin
    info.comment := pchar(data+info.streamat);
    info.streamat += length(info.comment)+1;
  end;

  //crc16?
  if (flags and $02) <> 0 then begin
    info.streamat += 2;
  end;

  result := true;
end;

function zfindstream(data: pointer; size: dword; var streamtype: dword; var startsat: dword; var streamsize: dword): boolean;
var
  zlib: tzlibinfo;
  gzip: tgzipinfo;
begin
  result := false;
  streamtype := 0;

  if zreadzlibheader(data, zlib) then begin
    streamtype := ZSTREAM_ZLIB;
    startsat := zlib.streamat;
    streamsize := size-startsat-4; //footer: adler32
    exit(true);
  end;

  if zreadgzipheader(data, gzip) then begin
    streamtype := ZSTREAM_GZIP;
    startsat := gzip.streamat;
    streamsize := size-startsat-8; //footer: crc32 + original file size
    exit(true);
  end;
end;

function zstreambasicinfo(data: pointer; var streamtype: dword; var startsat: dword; var trailing: dword): boolean;
var
  zlib: tzlibinfo;
  gzip: tgzipinfo;
begin
  result := false;
  streamtype := 0;

  if zreadzlibheader(data, zlib) then begin
    streamtype := ZSTREAM_ZLIB;
    startsat := zlib.streamat;
    trailing := 4; //footer: adler32
    exit(true);
  end;

  if zreadgzipheader(data, gzip) then begin
    streamtype := ZSTREAM_GZIP;
    startsat := gzip.streamat;
    trailing := 8; //footer: crc32 + original file size
    exit(true);
  end;
end;

// -- deflate -----------------------------

function gzdeflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
var
  z: tzflate;
begin
  result := false;
  if not zdeflateinit(z, 9) then exit;
  if not zdeflatewrite(z, data, size, true) then exit;
  output := getmem(z.bytesavailable);
  move(z.buffer[0], output^, z.bytesavailable);
  outputsize := z.bytesavailable;
  result := true;
end;

function gzdeflate(str: string): string;
var
  p: pointer;
  d: dword;
begin
  result := '';
  if not gzdeflate(@str[1], length(str), p, d) then exit;
  setlength(result, d);
  move(p^, result[1], d);
  freemem(p);
end;

// -- inflate -----------------------------

function gzinflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
var
  z: tzflate;
begin
  result := false;
  if not zinflateinit(z) then exit;
  if not zinflatewrite(z, data, size, true) then exit;
  output := getmem(z.bytesavailable);
  move(z.buffer[0], output^, z.bytesavailable);
  outputsize := z.bytesavailable;
  result := true;
end;

function gzinflate(str: string): string;
var
  p: pointer;
  d: dword;
begin
  result := '';
  if not gzinflate(@str[1], length(str), p, d) then exit;
  setlength(result, d);
  move(p^, result[1], d); 
  freemem(p);
end;

// -- ZLIB compress -----------------------

function makezlibheader(compressionlevel: integer): string;
begin
  result := #$78;

  case compressionlevel of
    1: result += #$01;
    2: result += #$5e;
    3: result += #$5e;
    4: result += #$5e;
    5: result += #$5e;
    6: result += #$9c;
    7: result += #$da;
    8: result += #$da;
    9: result += #$da;
  else
    result += #$da;
  end;
end;

function makezlibfooter(adler: dword): string;
begin
  setlength(result, 4);
  move(adler, result[1], 4);
end;

function gzcompress(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9): boolean;
var
  z: tzflate;
  header, footer: string;
begin
  result := false;
  if not zdeflateinit(z) then exit;
  if not zdeflatewrite(z, data, size, true) then exit;

  header := makezlibheader(level);
  footer := makezlibfooter(adler32(0, data, size));

  outputsize := length(header)+z.bytesavailable+length(footer);
  output := getmem(outputsize);

  move(header[1], output^, length(header));
  move(z.buffer[0], (output+length(header))^, z.bytesavailable);
  move(footer[1], (output+length(header)+z.bytesavailable)^, length(footer));

  result := true;
end;

function gzcompress(str: string; level: dword=9): string;
var
  p: pointer;
  d: dword;
begin
  result := '';
  if not gzcompress(@str[1], length(str), p, d, level) then exit;
  setlength(result, d);
  move(p^, result[1], d);
end;

// -- ZLIB decompress ---------------------

function gzuncompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
begin   
  //TODO
end;

function gzuncompress(str: string): string;
begin
  //TODO
end;

// -- GZIP compress -----------------------

function makegzipheader(compressionlevel: integer; filename: string=''; comment: string=''): string;
var
  flags: byte;
  modtime: dword;
begin
  setlength(result, 10);
  result[1] := #$1f; //signature
  result[2] := #$8b; //signature
  result[3] := #$08; //deflate algo

  //modification time
  modtime := 0;
  move(modtime, result[5], 4);

  result[9] := #$00; //compression level
  if compressionlevel = 9 then result[9] := #$02; //best compression
  if compressionlevel = 1 then result[9] := #$04; //best speed

  result[10] := #$FF; //file system (00 = FAT?)
  //result[10] := #$00;

  //optional headers
  flags := 0;

  //filename
  if filename <> '' then begin
    flags := flags or $08;
    result += filename;
    result += #$00;
  end;

  //comment
  if comment <> '' then begin
    flags := flags or $10;
    result += comment;
    result += #00;
  end;

  result[4] := chr(flags);
end;

function makegzipfooter(originalsize: dword; crc: dword): string;
begin
  setlength(result, 8);
  move(crc, result[1], 4);
  move(originalsize, result[1+4], 4);
end;

function gzencode(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9; filename: string=''; comment: string=''): boolean;
var
  z: tzflate;
  header, footer: string;
begin
  result := false;
  if not zdeflateinit(z) then exit;
  if not zdeflatewrite(z, data, size, true) then exit;

  header := makegzipheader(level, filename, comment);
  footer := makegzipfooter(size, crc32(0, data, size));

  outputsize := length(header)+z.bytesavailable+length(footer);
  output := getmem(outputsize);

  move(header[1], output^, length(header));
  move(z.buffer[0], (output+length(header))^, z.bytesavailable);
  move(footer[1], (output+length(header)+z.bytesavailable)^, length(footer));

  result := true;
end;

function gzencode(str: string; level: dword=9; filename: string=''; comment: string=''): string;
var
  p: pointer;
  d: dword;
begin
  result := '';
  if not gzencode(@str[1], length(str), p, d, level, filename, comment) then exit;
  setlength(result, d);
  move(p^, result[1], d);
  freemem(p);
end;

// -- GZIP decompress ---------------------

function gzdecode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
var
  gzip: tgzipinfo;
  z: tzflate;
  originalsize: dword;
  checksum: dword;
begin
  result := false;
  if not zreadgzipheader(data, gzip) then exit;
  if not zinflateinit(z) then exit;
  if not zinflatewrite(z, data+gzip.streamat, size-gzip.streamat-8, true) then exit;
  originalsize := pdword(data+size-4)^;
  if originalsize <> z.bytesavailable then exit; //invalid size
  checksum := pdword(data+size-8)^;
  if crc32(0, @z.buffer[0], z.bytesavailable) <> checksum then exit; //invalid checsum
  outputsize := z.bytesavailable;
  output := getmem(outputsize);
  move(z.buffer[0], output^, outputsize);
  result := true;
end;

function gzdecode(str: string): string;
var
  p: pointer;
  d: dword;
begin
  result := '';
  if not gzdecode(@str[1], length(str), p, d) then exit;
  setlength(result, d);
  move(p^, result[1], d);
  freemem(p);
end;

end.

