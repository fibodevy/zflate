unit crc32;

{$mode objfpc}

{
  crc32.c -- compute the CRC-32 of a data stream
  Copyright (C) 1995-1998 Mark Adler

  Pascal tranlastion
  Copyright (C) 1998 by Jacques Nomssi Nzali
  For conditions of distribution and use, see copyright notice in readme.txt
}

interface

function crc32(crc: cardinal; buf: Pbyte; len: cardinal): cardinal;
function get_crc32_table: Pcardinal;

implementation

const
  Poly32Rev = uint32($EDB88320); { 0,1,2,4,5,7,8,10,11,12,16,22,23,26 }

const
  crc32_table_empty: boolean = TRUE;

var
  crc32_table: array[Byte] of Longword;

procedure make_crc32_table;
var
 c    : cardinal;
 n,k  : integer;
begin
  for n := 0 to 255 do
  begin
    c := cardinal(n);
    for k := 0 to 7 do
    begin
      if (c and 1) <> 0 then
        c := (c shr 1) xor Poly32Rev
      else
        c := (c shr 1);
    end;
    crc32_table[n] := c;
  end;
  crc32_table_empty := FALSE;
end;

function get_crc32_table : {const} Pcardinal; [public,alias:'get_crc32_table'];
begin
  if (crc32_table_empty) then
    make_crc32_table;

  get_crc32_table :=  {const} Pcardinal(@crc32_table);
end;

function crc32 (crc : cardinal; buf : Pbyte; len : cardinal): cardinal;
begin
  if buf = nil then
    exit(0);

  if crc32_table_empty then
    make_crc32_table;

  crc := crc xor $FFFFFFFF;
  while (len >= 4) do
  begin
    crc := crc32_table[(crc xor buf[0]) and $ff] xor (crc shr 8);
    crc := crc32_table[(crc xor buf[1]) and $ff] xor (crc shr 8);
    crc := crc32_table[(crc xor buf[2]) and $ff] xor (crc shr 8);
    crc := crc32_table[(crc xor buf[3]) and $ff] xor (crc shr 8);
    inc(buf, 4);
    dec(len, 4);
  end;

  while (len > 0) do
  begin
    crc := crc32_table[(crc xor buf^) and $ff] xor (crc shr 8);
    inc(buf);
    dec(len);
  end;

  result := crc xor $FFFFFFFF;
end;

end.
