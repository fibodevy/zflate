unit zflate;

{$mode ObjFPC}{$H+}

interface

uses ZBase, ZInflate, ZDeflate;

type
  tzflate = record
    z: z_stream;
    totalout: qword;
    buffer: array of byte;
    error: string;
  end;

//deflate chunks
function zdeflateinit(var z: tzflate; level: dword=9): boolean;
function zdeflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): dword;

//inflate chunks
function zinflateinit(var z: tzflate): boolean;
function zinflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): dword;

//compress (DEFLATE) whole buffer at once
function gzdeflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//compress (DEFLATE) whole string at once
function gzdeflate(str: string): string;
//decompress (DEFLATE) whole buffer at once
function gzinflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//decompress (DEFLATE) whole string at once
function gzinflate(str: string): string;

//compress (ZLIB) whole buffer at once
function gzcompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//compress (ZLIB) whole string at once
function gzcompress(str: string): string;
//decompress (ZLIB) whole buffer at once
function gzuncompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//decompress (ZLIB) whole string at once
function gzuncompress(str: string): string;

//compress (GZIP) whole buffer at once
function gzencode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//compress (GZIP) whole string at once
function gzencode(str: string): string;
//decompress (GZIP) whole buffer at once
function gcdecode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//decompress (GZIP) whole string at once
function gcdecode(str: string): string;

implementation

function zerror(var z: tzflate; msg: string): dword;
begin
  z.error := msg;
  result := 0;
end;

// -- deflate chunks ----------------------

function zdeflateinit(var z: tzflate; level: dword=9): boolean;
begin
  result := false;     
  fillchar(z, sizeof(z), 0);
  if deflateInit2(z.z, level, Z_DEFLATED, -MAX_WBITS, DEF_MEM_LEVEL, 0) <> Z_OK then exit;
  setlength(z.buffer, 1024*32);
  result := true;
end;

function zdeflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): dword;
var
  i: integer;
begin
  result := 0;

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
    result := z.z.total_out-z.totalout;
    z.totalout += result;
  end;
end;

// -- inflate chunks ----------------------

function zinflateinit(var z: tzflate): boolean;
begin
  result := false;
  fillchar(z, sizeof(z), 0);
  if inflateInit2(z.z, -MAX_WBITS) <> Z_OK then exit;
  setlength(z.buffer, 1024*32);
  result := true;
end;

function zinflatewrite(var z: tzflate; data: pointer; size: dword; lastchunk: boolean=false): dword;
var
  i: integer;
begin
  result := 0;

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
    result := z.z.total_out-z.totalout;
    z.totalout += result;
  end;
end;

function zinflatefinish(var z: tzflate): dword;
begin
  result := zinflatewrite(z, nil, 0);
end;

// -- deflate -----------------------------

function gzdeflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
var
  z: tzflate;
  d: dword;
begin
  result := false;
  if not zdeflateinit(z, 9) then exit;
  d := zdeflatewrite(z, data, size, true);
  output := getmem(d);
  move(z.buffer[0], output^, d);
  outputsize := d;
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
  d: dword;
begin
  result := false;
  if not zinflateinit(z) then exit;
  d := zinflatewrite(z, data, size, true);
  output := getmem(d);
  move(z.buffer[0], output^, d);
  outputsize := d;
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

function makezlibheader: string;
begin
end;

function makezlibfooter(adler: dword): string;
begin
end;

function gzcompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
begin
end;

function gzcompress(str: string): string;
begin
end;

// -- ZLIB decompress ---------------------

function gzuncompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
begin
end;

function gzuncompress(str: string): string;
begin
end;

// -- GZIP compress -----------------------

function makegzipheader(compressionlevel: integer; filename: string=''): string;
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

  result[10] := #$00; //file system

  //optional headerss

  //filename
  if filename <> '' then begin
    flags := flags and $08;
    result += filename;
    result += #$00;
  end;

  result[4] := chr(flags);
end;

function makegzipfooter(originalsize: dword; crc: dword): string;
begin
  //checksum, then filesize
end;

function gzencode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
begin
end;

function gzencode(str: string): string;
begin
end;

// -- GZIP decompress ---------------------

function gcdecode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
begin
end;

function gcdecode(str: string): string;
begin
end;

end.

