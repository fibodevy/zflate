unit zflate;

{$mode ObjFPC}{$H+}

interface

uses ZBase, ZInflate, ZDeflate;

type
  tzflate = record
    z: z_stream;
    buffer: array of byte;
  end;

function zdeflateinit(var z: tzflate; level: dword=9): boolean;
function zdeflatewrite(var z: tzflate; data: pointer; size: dword): dword;
//function zdeflateread(var z: tzflate): dword;
function zdeflatefinish(var z: tzflate): boolean;

implementation

// -- deflate chunks ----------------------

function zdeflateinit(var z: tzflate; level: dword=9): boolean;
var
  i: integer;
begin
  result := false;
  i := deflateInit(z.z, level);
  if i <> Z_OK then exit;
  setlength(z.buffer, 1024*32);
  result := true;
end;

function zdeflatewrite(var z: tzflate; data: pointer; size: dword): dword;
begin
  result := 0;
end;

//function zdeflateread(var z: tzflate): dword;
//begin
//end;

function zdeflatefinish(var z: tzflate): boolean;
begin
end;

// -- inflate chunks ----------------------

function zinflateinit(var z: tzflate; compressionlevel: dword=9): boolean;
begin
end;

function zinflatewrite(var z: tzflate): dword;
begin
end;

function zinflateread(var z: tzflate): dword;
begin
end;

function zinflatefinish(var z: tzflate): boolean;
begin
end;

// -- deflate -----------------------------

function gzdeflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
begin
end;

function gzdeflate(str: string): string;
begin
end;

// -- inflate -----------------------------

function gzinflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
begin
end;

function gzinflate(str: string): string;
begin
end;

// -- ZLIB compress -----------------------

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

