{ zflate - self-contained DEFLATE (RFC 1951) compressor and decompressor with
  zlib (RFC 1950) and gzip (RFC 1952) containers. No dependencies beyond the
  system unit (plus cthreads on unix, for the threaded path).

  Every operation returns an integer code: ZFLATE_OK (0) on success, ZFLATE_E*
  otherwise. No exception ever escapes this unit. Codec state belongs to the
  call, not to the unit, so independent threads may compress/decompress at the
  same time without interfering. zcompress_stream additionally splits the work
  across zuse_threads worker threads. }

{ Copyright (c) 2023-2026 @fibodevy / https://github.com/fibodevy
  MIT licensed (see LICENSE). Free to use and modify; keep this notice
  and the link when you redistribute the sources. }

unit zflate;

{$mode unleashed}
{$R-}{$Q-}
{$codealign proc=1}

// comment out to disable error translation
// if disabled, zflate_error_str will return the error code as string
{$define ZFLATE_ERROR_TRANSLATION}

interface

type
  // progress callback used by all compress/decompress functions when zprogress
  // is set; position/totalsize track the deflate stream input, outputsize the
  // bytes produced so far; return false to abort with ZFLATE_EABORTED
  tzprogress = reference to function(position, totalsize, outputsize: qword): boolean;

  // streaming input: fill buf with up to maxlen bytes, return the byte count, 0 = end of input
  tzreader = reference to function(buf: pointer; maxlen: dword): dword;
  // streaming output: receive a produced block, return false to abort
  tzwriter = reference to function(data: pointer; size: dword): boolean;

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
  ZFLATE_RAW  = 0;
  ZFLATE_ZLIB = 1;
  ZFLATE_GZIP = 2;

  // compression levels: 0 stores, 1 is fastest, 9 compresses best; 5 is the default
  ZFLATE_STORE   = 0;
  ZFLATE_FASTEST = 1;
  ZFLATE_DEFAULT = 5;
  ZFLATE_BEST    = 9;

  ZFLATE_OK           = 0;
  ZFLATE_EDEFLATE     = 101; // 'deflate failed'
  ZFLATE_EINFLATE     = 102; // 'inflate failed'
  ZFLATE_EZLIBINVALID = 103; // 'invalid zlib header'
  ZFLATE_EGZIPINVALID = 104; // 'invalid gzip header'
  ZFLATE_ECHECKSUM    = 105; // 'invalid checksum'
  ZFLATE_EOUTPUTSIZE  = 106; // 'output size doesnt match gzip footer'
  ZFLATE_EABORTED     = 107; // 'aborted by callback'
  ZFLATE_ENODATA      = 108; // 'no input data'
  ZFLATE_EFILEREAD    = 109; // 'cannot read file'
  ZFLATE_EFILEWRITE   = 110; // 'cannot write file'

threadvar
  // last error of the most recent operation on this thread (also returned
  // directly by the pointer overloads)
  zlasterror: integer;
  // optional progress hook; nil = no callbacks
  zprogress: tzprogress;
  // worker threads zcompress_stream splits the work across; 0 or 1 = sequential
  // (the default), N > 1 = N workers. per-thread setting
  zuse_threads: integer;

// RAW: compress whole buffer/string/bytes to DEFLATE at once
function gzdeflate(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
function gzdeflate(const str: string; level: dword = ZFLATE_DEFAULT): string;
function gzdeflate(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
// RAW: decompress whole DEFLATE buffer/string/bytes at once
function gzinflate(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function gzinflate(const str: string): string;
function gzinflate(const bytes: TBytes): TBytes;

// ZLIB: compress whole buffer/string/bytes to ZLIB at once
function gzcompress(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
function gzcompress(const str: string; level: dword = ZFLATE_DEFAULT): string;
function gzcompress(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
// ZLIB: decompress whole ZLIB buffer/string/bytes at once, verify adler32
function gzuncompress(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function gzuncompress(const str: string): string;
function gzuncompress(const bytes: TBytes): TBytes;

// GZIP: compress whole buffer/string/bytes to GZIP at once
function gzencode(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
function gzencode(const str: string; level: dword = ZFLATE_DEFAULT): string;
function gzencode(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
// GZIP: decompress whole GZIP buffer/string/bytes at once, verify crc32 + size
function gzdecode(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function gzdecode(const str: string): string;
function gzdecode(const bytes: TBytes): TBytes;

// detect the stream type and decompress accordingly
function zdecompress(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function zdecompress(const str: string): string;
function zdecompress(const bytes: TBytes): TBytes;

// streaming: input is pulled from reader, output pushed to writer, memory use
// stays constant. totalsize is only used for progress reporting (0 = unknown)
function gzdeflate_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
function gzcompress_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
function gzencode_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
// detect the container, decompress and verify checksums: reader -> inflate -> writer
function zdecompress_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0): integer;

// read and validate a zlib header
function read_zlib_header(data: pointer; size: dword; out info: tzlibinfo): boolean;
// read and validate a gzip header; filename/comment point into data when present
function read_gzip_header(data: pointer; size: dword; out info: tgzipinfo): boolean;
// detect the stream type: ZFLATE_GZIP, ZFLATE_ZLIB, or ZFLATE_RAW as fallback
function stream_info(data: pointer; size: dword): (streamtype, streamat, footerlen: dword);

// translate error code to message
function zflate_error_str(code: integer): string;

// compute crc32b checksum (start with crc = 0)
function crc32b(crc: dword; data: pbyte; len: dword): dword;
// compute adler32 checksum (start with adler = 1)
function adler32(adler: dword; data: pbyte; len: dword): dword;

implementation

{$ifdef unix}
uses cthreads;   // installs the threading manager for the parallel path
{$endif}

const
  // length/distance base values and extra-bit counts (RFC 1951 3.2.5)
  LB: array[29] of word = (3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258);
  LE: array[29] of byte = (0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0);
  DB: array[30] of word = (1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12_289,16_385,24_577);
  DE: array[30] of byte = (0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13);
  CO: array[19] of byte = (16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15); // code-length order

  HB = 15;            // hash bits
  HS = 1 shl HB;      // hash table size
  HM = HS - 1;        // hash mask
  WS = 32_768;        // window size = max back-reference distance
  WM = WS - 1;

  // per compression level (0 = store only): hash-chain walk limit, match length
  // that ends the search early, the length past which an already-found match cuts
  // the walk to a quarter, and whether to use lazy matching. zlib's tuning table
  LVCHAIN: array[10] of word    = (0, 4, 8, 32, 16, 32, 128, 256, 1024, 4096);
  LVNICE: array[10] of word     = (0, 8, 16, 32, 16, 32, 128, 128, 258, 258);
  LVGOOD: array[10] of word     = (0, 4, 4, 4, 4, 8, 8, 8, 32, 32);
  LVLAZY: array[10] of boolean  = (false, false, false, false, true, true, true, true, true, true);

  ZSCHUNK = 1_048_576;  // encoder input chunk: one chunk = one DEFLATE block
  ZSINBUF = 262_144;    // streaming: decoder input buffer
  ZSOUTMAX = 1_048_576; // streaming: decoder output flush threshold

  // LZ token: literal 0..255, or a match with the flag set
  TOKMATCH = dword($80000000);   // bit 31 = match; bits 16..24 length, bits 0..15 distance

var
  // filled once at startup; read-only afterwards so every thread can share them
  LENSYM: array[259] of byte;    // length 3..258 -> lit/len code index 0..28
  DISTSYM: array[512] of byte;   // distance -> code index, zlib's two-range split
  CRCTAB: array[256] of dword;   // crc32 of each byte value, the standard table

// ----- checksums -----

// one table lookup per byte instead of eight shift/xor steps; the table costs 1 kB
// and makes gzip's footer roughly eight times cheaper to compute
function crc32b(crc: dword; data: pbyte; len: dword): dword;
begin
  crc := not crc;
  while len > 0 do begin
    crc := CRCTAB[(crc xor data^) and $ff] xor (crc shr 8);
    inc(data); dec(len);
  end;
  result := not crc;
end;

function adler32(adler: dword; data: pbyte; len: dword): dword;
begin
  var a := adler and $ffff; var b := adler shr 16;
  while len > 0 do begin a := (a + data^) mod 65_521; b := (b + a) mod 65_521; inc(data); dec(len); end;
  result := (b shl 16) or a;
end;

// ----- deflate encoder -----

type
  // encoder state. one record per compression job, so the hot loops read fields
  // through a register instead of a TLS lookup, and the parallel path simply
  // gives every worker its own record. too big for the stack (the hash chains
  // alone are 256 kB), so it is heap allocated
  tzdefl = record
    level, chain, nice, good: longint;             // search effort for the active level
    lazy: boolean;
    aborted: boolean;                              // progress callback requested abort
    usecb: boolean;
    sp: pbyte;
    slen, op, cap, mst: longint;                   // mst: match start from fm
    bb: qword;                                     // bit accumulator, LSB-first
    bc: longint;
    buf: pointer;
    toks: pdword;                                  // LZ tokens of the current block
    tokn, tokcap: longint;
    progbase, progtotal: qword;                    // progress reporting across chunks
    head: array[HS] of longint;                    // LZ77 hash chains
    prev: array[WS] of longint;
    fl: array[288] of longint;                     // lit/len + dist frequencies
    fd: array[32] of longint;
    llen, dlen: array[288] of byte;                // active code lengths (dyn or fixed)
    lcode, dcode: array[288] of word;              // active codes (LSB-first)
    FIXL: array[288] of byte;                      // fixed-Huffman code lengths
    FIXD: array[32] of byte;
    cf: array[19] of longint;                      // code-length alphabet
    cllen: array[19] of byte;
    clcode: array[19] of word;
    lcount, dcount, numCL, rlen: longint;
    clsym, clext, clxb: array[320] of byte;        // RLE'd code-length stream
    comb: array[320] of byte;
    hsym: array[288] of word;                      // Huffman builder scratch
    hfrq: array[576] of longint;
    hdad, hdep: array[576] of word;
    hbl: array[17] of word;
  end;
  pzdefl = ^tzdefl;

threadvar
  // the record is a quarter of a megabyte, so each thread keeps one warm rather
  // than allocating and releasing it per call. same footprint the per-thread
  // arrays had before
  zdcache: pzdefl;

// encoder ready for a new job. only the scalars are initialised: every array is
// filled before it is read, and zeroing 256 kB of hash chains per call would
// cost more than the compression of a short string
function znew: pzdefl;
begin
  result := zdcache;
  if result = nil then begin
    result := GetMem(sizeof(tzdefl));
    result^.buf := nil; result^.cap := 0;
    result^.toks := nil; result^.tokcap := 0;
  end else
    zdcache := nil;
  with result^ do begin
    level := 0; chain := 0; nice := 0; good := 0; lazy := false;
    aborted := false; usecb := false;
    sp := nil; slen := 0; op := 0; mst := 0;
    bb := 0; bc := 0; tokn := 0;
    progbase := 0; progtotal := 0;
    lcount := 0; dcount := 0; numCL := 0; rlen := 0;
  end;
end;

procedure zfree(e: pzdefl);
begin
  if e^.buf <> nil then FreeMem(e^.buf);
  e^.buf := nil; e^.cap := 0;                   // the buffer may also have been handed to the caller
  if zdcache = nil then zdcache := e            // keep it warm for the next call
  else begin
    if e^.toks <> nil then FreeMem(e^.toks);
    FreeMem(e);
  end;
end;

// pick the search effort for a compression level
procedure setLevel(var e: tzdefl; level: dword);
begin
  if level > 9 then level := 9;
  e.level := level;
  e.chain := LVCHAIN[level];
  e.nice := LVNICE[level];
  e.good := LVGOOD[level];
  e.lazy := LVLAZY[level];
end;

// reverse the low n bits (canonical codes are MSB-first, DEFLATE writes LSB-first)
function rev(v, n: longint): longint;
begin
  result := 0;
  for var i := 0 to n-1 do begin result := (result shl 1) or (v and 1); v := v shr 1; end;
end;

// make room for n more output bytes
procedure ensure(var e: tzdefl; n: longint);
begin
  if e.op + n <= e.cap then exit;
  if e.cap = 0 then e.cap := 4096;
  while e.cap < e.op + n do e.cap := e.cap * 2;
  ReAllocMem(e.buf, e.cap);
end;

// append one output byte
procedure ob1(var e: tzdefl; b: longint);
begin
  ensure(e, 1);
  pbyte(e.buf)[e.op] := b; inc(e.op);
end;

// append n raw bytes; only valid when the bit buffer sits on a byte boundary
procedure obn(var e: tzdefl; p: pointer; n: longint);
begin
  ensure(e, n);
  if n > 0 then Move(p^, (pbyte(e.buf) + e.op)^, n);
  inc(e.op, n);
end;

// write n bits, LSB-first. the accumulator empties four bytes at a time, so a
// token's four writes cost one store instead of six
procedure put(var e: tzdefl; v, n: longint); inline;
begin
  e.bb := e.bb or (qword(dword(v)) shl e.bc);
  inc(e.bc, n);
  if e.bc >= 32 then begin
    if e.op + 4 > e.cap then ensure(e, 4);
    PDword(pbyte(e.buf) + e.op)^ := dword(e.bb);
    inc(e.op, 4);
    e.bb := e.bb shr 32; dec(e.bc, 32);
  end;
end;

procedure flush(var e: tzdefl);
begin
  ensure(e, 8);
  while e.bc > 0 do begin
    pbyte(e.buf)[e.op] := byte(e.bb); inc(e.op);
    e.bb := e.bb shr 8; dec(e.bc, 8);
  end;
  e.bb := 0; e.bc := 0;
end;

// length-limited Huffman code lengths for f[0..n-1] (>= 2 leaves forced so the
// code is always complete); o[] receives the bit lengths. Two-queue Huffman with
// zlib-style overflow redistribution capped at mx.
procedure mkhuff(var e: tzdefl; f: PLongint; n, mx: longint; o: PByte);
begin
  for var i := 0 to n-1 do o[i] := 0;
  var L := 0;
  for var i := 0 to n-1 do if f[i] > 0 then begin e.hsym[L] := i; e.hfrq[L] := f[i]; inc(L); end;
  var t := 0;
  while L < 2 do begin if f[t] = 0 then begin e.hsym[L] := t; e.hfrq[L] := 1; inc(L); end; inc(t); end;
  // insertion sort leaves ascending by frequency
  for var a := 1 to L-1 do begin
    var ff := e.hfrq[a]; var ss := e.hsym[a]; var b := a-1;
    while (b >= 0) and (e.hfrq[b] > ff) do begin e.hfrq[b+1] := e.hfrq[b]; e.hsym[b+1] := e.hsym[b]; dec(b); end;
    e.hfrq[b+1] := ff; e.hsym[b+1] := ss;
  end;
  // two-queue Huffman: leaf queue [lo..L) merged with internal queue [iq..ni)
  var lo := 0; var iq := L; var ni := L;
  for var c := 1 to L-1 do begin
    var a, b: longint;
    if (lo < L) and ((iq >= ni) or (e.hfrq[lo] <= e.hfrq[iq])) then begin a := lo; inc(lo); end else begin a := iq; inc(iq); end;
    if (lo < L) and ((iq >= ni) or (e.hfrq[lo] <= e.hfrq[iq])) then begin b := lo; inc(lo); end else begin b := iq; inc(iq); end;
    e.hfrq[ni] := e.hfrq[a] + e.hfrq[b]; e.hdad[a] := ni; e.hdad[b] := ni; inc(ni);
  end;
  // bit length = node depth; a parent always has a higher index than its children
  e.hdep[ni-1] := 0;
  for var i := ni-2 downto 0 do e.hdep[i] := e.hdep[e.hdad[i]] + 1;
  var mxb := 0;
  for var i := 0 to L-1 do if e.hdep[i] > mxb then mxb := e.hdep[i];
  if mxb > mx then begin
    for var b := 0 to mx do e.hbl[b] := 0;
    var ov := 0;
    for var i := 0 to ni-1 do begin
      if e.hdep[i] > mx then begin e.hdep[i] := mx; inc(ov); end;
      if i < L then inc(e.hbl[e.hdep[i]]);
    end;
    repeat
      var q := mx-1;
      while e.hbl[q] = 0 do dec(q);
      dec(e.hbl[q]); inc(e.hbl[q+1], 2); dec(e.hbl[mx]); dec(ov, 2);
    until ov <= 0;
    // least-frequent leaves (front) take the longest codes
    var k := 0;
    for var b := mx downto 1 do while e.hbl[b] > 0 do begin e.hdep[k] := b; inc(k); dec(e.hbl[b]); end;
  end;
  for var i := 0 to L-1 do o[e.hsym[i]] := e.hdep[i];
end;

// assign canonical codes from bit lengths ln[0..n-1] into co[] (LSB-first)
procedure mkcodes(ln: PByte; n: longint; co: PWord);
var bl, nx: array[16] of longint;
begin
  for var i := 0 to 15 do bl[i] := 0;
  for var i := 0 to n-1 do inc(bl[ln[i]]);
  bl[0] := 0;
  var c := 0;
  for var i := 1 to 15 do begin c := (c + bl[i-1]) shl 1; nx[i] := c; end;
  for var i := 0 to n-1 do
    if ln[i] <> 0 then begin co[i] := rev(nx[ln[i]], ln[i]); inc(nx[ln[i]]); end
    else co[i] := 0;
end;

// map a value to its code index: largest i with t[i] <= v (length or distance table)
function sym(v: longint; t: PWord; hi: longint): longint;
begin for var i := hi downto 0 do if v >= t[i] then exit(i); result := 0; end;

// distance -> code index, through DISTSYM (zlib's split: exact below 257, then
// grouped in 128-wide buckets that all share one code)
function dsym(dist: longint): longint; inline;
begin
  if dist <= 256 then result := DISTSYM[dist-1] else result := DISTSYM[256 + ((dist-1) shr 7)];
end;

// record one literal
procedure tlit(var e: tzdefl; b: longint); inline;
begin
  inc(e.fl[b]);
  e.toks[e.tokn] := b; inc(e.tokn);
end;

// record one (length, distance) match
procedure tmatch(var e: tzdefl; ln, dist: longint); inline;
begin
  inc(e.fl[257 + LENSYM[ln]]); inc(e.fd[dsym(dist)]);
  e.toks[e.tokn] := TOKMATCH or (dword(ln) shl 16) or dword(dist); inc(e.tokn);
end;

// replay the recorded tokens through the active Huffman codes
procedure emitTokens(var e: tzdefl);
begin
  var tk := e.toks;
  var lc: pword := @e.lcode[0]; var ll: pbyte := @e.llen[0];
  var dc: pword := @e.dcode[0]; var dl: pbyte := @e.dlen[0];
  for var i := 0 to e.tokn-1 do begin
    var t := tk[i];
    if t < TOKMATCH then put(e, lc[t], ll[t])
    else begin
      var ln := longint((t shr 16) and $1ff);
      var dist := longint(t and $ffff);
      var li := LENSYM[ln]; var di := dsym(dist);
      put(e, lc[257+li], ll[257+li]);
      if LE[li] > 0 then put(e, ln - LB[li], LE[li]);
      put(e, dc[di], dl[di]);
      if DE[di] > 0 then put(e, dist - DB[di], DE[di]);
    end;
  end;
end;

// insert positions lo..hi-1 into the hash chains, skipping any that lack the 3
// bytes of lookahead the hash needs. runs once per byte a match covers, so the
// state is hoisted out of the loop
procedure insRange(var e: tzdefl; lo, hi: longint);
begin
  var s: pbyte := e.sp;
  var ph: plongint := @e.head[0];
  var pp: plongint := @e.prev[0];
  var top := e.slen - 3;                           // last position with lookahead
  if hi > top + 1 then hi := top + 1;
  var q := lo;
  while q < hi do begin
    var h := ((s[q] shl 10) xor (s[q+1] shl 5) xor s[q+2]) and HM;
    pp[q and WM] := ph[h]; ph[h] := q;
    inc(q);
  end;
end;

// longest match for position p (needs 3 bytes lookahead); inserts p into the hash
// chains, returns the length (>= 3) or 2 if none, and sets mst to the match start.
// prevlen is the match already in hand at p-1, 0 when there is none
function fm(var e: tzdefl; p, prevlen: longint): longint;
begin
  // the chain walk below runs up to chain times per call, so everything it
  // touches is hoisted into locals up front
  var s: pbyte := e.sp;
  var ph: plongint := @e.head[0];
  var pp: plongint := @e.prev[0];
  var chain := e.chain;
  var nice := e.nice;
  // already sitting on a decent match: spend a quarter of the effort looking for
  // a better one (zlib's good_length)
  if prevlen >= e.good then chain := chain shr 2;

  var h := ((s[p] shl 10) xor (s[p+1] shl 5) xor s[p+2]) and HM;
  var cand := ph[h];
  pp[p and WM] := cand; ph[h] := p;
  var best := 2;
  var bestst := 0;
  var mx := e.slen - p; if mx > 258 then mx := 258;
  var cw := 0;
  while (cand >= 0) and (cw < chain) do begin
    if p - cand >= WS then break;                  // distance bounded by the window
    if (s[cand+best] = s[p+best]) and (s[cand] = s[p]) then begin
      // compare 8 bytes per step; both reads stay inside the input because
      // l+8 <= mx <= slen-p and cand < p. the first differing byte is the low
      // set bit of the xor, so its position gives the match length directly
      var l := 0;
      while l + 8 <= mx do begin
        var x := PQWord(s + cand + l)^ xor PQWord(s + p + l)^;
        if x <> 0 then begin inc(l, BsfQWord(x) shr 3); break; end;
        inc(l, 8);
      end;
      while (l < mx) and (s[cand+l] = s[p+l]) do inc(l);   // tail
      // a match at least nice long is good enough, stop walking the chain
      if l > best then begin best := l; bestst := cand; if (l >= mx) or (l >= nice) then break; end;
    end;
    cand := pp[cand and WM]; inc(cw);
  end;
  if best > 2 then e.mst := bestst;                // only meaningful for a real match
  result := best;
end;

// LZ77 over the whole input, recording tokens and their frequencies in one pass.
// Above level 3 a match at i is held back one byte to see if i+1 starts a longer
// one (zlib's lazy heuristic), below it every match is taken as found.
procedure lz(var e: tzdefl);
begin
  FillChar(e.head, sizeof(e.head), $FF);
  e.tokn := 0;
  var s: pbyte := e.sp;                                    // stable for the whole pass
  var n := e.slen;
  var lazy := e.lazy;
  var i := 0; var pl := 2; var ps := 0; var avail := 0;    // pl/ps: match deferred from i-1
  var nx := 0;
  while i < n do begin
    if (i >= nx) and e.usecb then begin
      inc(nx, 65_536);
      if not zprogress(e.progbase + i, e.progtotal, e.op) then begin e.aborted := true; exit; end;
    end;
    var ml := 2;
    // pl is the match deferred from i-1 in lazy mode, 2 (i.e. none) otherwise
    if i + 3 <= n then ml := fm(e, i, pl);                 // best match at i (inserts i)
    if not lazy then begin
      // greedy: emit the match at i straight away
      if ml >= 3 then begin
        tmatch(e, ml, i - e.mst);
        var en := i + ml; inc(i);
        insRange(e, i, en);
        i := en;
      end else begin tlit(e, s[i]); inc(i); end;
      continue;
    end;
    if (pl >= 3) and (ml <= pl) then begin
      // i-1's match is not beaten: emit it and skip the bytes it covers
      tmatch(e, pl, (i-1) - ps);
      var en := (i-1) + pl; inc(i);
      insRange(e, i, en);
      i := en; pl := 2; avail := 0;
    end else begin
      // defer i; the byte at i-1 (if any) could not do better, so emit it literally
      if avail = 1 then tlit(e, s[i-1]);
      pl := ml; ps := e.mst; avail := 1; inc(i);
    end;
  end;
  if avail = 1 then tlit(e, s[i-1]);                       // trailing literal
end;

// append one entry to the RLE'd code-length stream
procedure addrle(var e: tzdefl; s, x, xb: longint);
begin e.clsym[e.rlen] := s; e.clext[e.rlen] := x; e.clxb[e.rlen] := xb; inc(e.cf[s]); inc(e.rlen); end;

// RLE-encode the lit+dist code lengths into the code-length alphabet (RFC 1951 3.2.7)
procedure hdrRLE(var e: tzdefl);
begin
  for var i := 0 to e.lcount-1 do e.comb[i] := e.llen[i];
  for var i := 0 to e.dcount-1 do e.comb[e.lcount+i] := e.dlen[i];
  var tot := e.lcount + e.dcount;
  FillChar(e.cf, sizeof(e.cf), 0); e.rlen := 0;
  var i := 0;
  while i < tot do begin
    var cur := e.comb[i]; var j := i+1;
    while (j < tot) and (e.comb[j] = cur) do inc(j);
    var run := j - i;
    if cur = 0 then begin
      while run >= 11 do begin var take := run; if take > 138 then take := 138; addrle(e, 18, take-11, 7); dec(run, take); end;
      while run >= 3 do begin var take := run; if take > 10 then take := 10; addrle(e, 17, take-3, 3); dec(run, take); end;
      while run > 0 do begin addrle(e, 0, 0, 0); dec(run); end;
    end else begin
      addrle(e, cur, 0, 0); dec(run);
      while run >= 3 do begin var take := run; if take > 6 then take := 6; addrle(e, 16, take-3, 2); dec(run, take); end;
      while run > 0 do begin addrle(e, cur, 0, 0); dec(run); end;
    end;
    i := j;
  end;
end;

// total bit cost of the LZ tokens (+ end-of-block) under the given code lengths
function tokbits(var e: tzdefl; ll, dl: PByte): int64;
begin
  result := 0;
  for var i := 0 to 285 do result := result + int64(e.fl[i]) * ll[i];
  for var i := 0 to 29 do result := result + int64(e.fd[i]) * dl[i];
  for var i := 0 to 28 do result := result + int64(e.fl[257+i]) * LE[i];   // length extra
  for var i := 0 to 29 do result := result + int64(e.fd[i]) * DE[i];       // distance extra
end;

// emit the whole input as byte-aligned stored blocks (<= 65535 each)
procedure emitStored(var e: tzdefl; final: boolean);
begin
  var p := 0;
  while p < e.slen do begin
    if e.usecb and (not zprogress(e.progbase + p, e.progtotal, e.op)) then begin e.aborted := true; exit; end;
    var n := e.slen - p; if n > 65_535 then n := 65_535;
    if p + n >= e.slen then put(e, ord(final), 1) else put(e, 0, 1);  // BFINAL on the last block
    put(e, 0, 2); flush(e);                          // BTYPE = 00, align to byte
    ob1(e, n and $FF); ob1(e, (n shr 8) and $FF);
    ob1(e, (not n) and $FF); ob1(e, ((not n) shr 8) and $FF);
    obn(e, e.sp + p, n);                             // the block is byte-aligned, copy it in one go
    inc(p, n);
  end;
end;

// compress sp/slen as one DEFLATE block (smallest of stored/fixed/dynamic)
procedure compressBlock(var e: tzdefl; final: boolean);
begin
  if e.level = 0 then begin emitStored(e, final); exit; end;   // level 0: no compression at all

  FillChar(e.FIXL[0], 144, 8); FillChar(e.FIXL[144], 112, 9); FillChar(e.FIXL[256], 24, 7); FillChar(e.FIXL[280], 8, 8);
  FillChar(e.FIXD[0], 30, 5);

  // one LZ pass: records the tokens and their frequencies. the emit pass below
  // replays the tokens, so the match finder runs once per block, not twice
  FillChar(e.fl, sizeof(e.fl), 0); FillChar(e.fd, sizeof(e.fd), 0);
  if e.tokcap < e.slen + 1 then begin              // at most one token per input byte
    e.tokcap := e.slen + 1;
    ReAllocMem(e.toks, e.tokcap * sizeof(dword));
  end;
  lz(e);
  inc(e.fl[256]);
  if e.aborted then exit;

  // dynamic lit/len + distance Huffman from the frequencies
  mkhuff(e, @e.fl[0], 286, 15, @e.llen[0]);
  mkhuff(e, @e.fd[0], 30, 15, @e.dlen[0]);
  e.lcount := 286; while (e.lcount > 257) and (e.llen[e.lcount-1] = 0) do dec(e.lcount);
  e.dcount := 30;  while (e.dcount > 1) and (e.dlen[e.dcount-1] = 0) do dec(e.dcount);

  // code-length alphabet for the dynamic header
  hdrRLE(e);
  mkhuff(e, @e.cf[0], 19, 7, @e.cllen[0]);
  e.numCL := 19; while (e.numCL > 4) and (e.cllen[CO[e.numCL-1]] = 0) do dec(e.numCL);

  // canonical codes for all three alphabets
  mkcodes(@e.llen[0], 286, @e.lcode[0]);
  mkcodes(@e.dlen[0], 30, @e.dcode[0]);
  mkcodes(@e.cllen[0], 19, @e.clcode[0]);

  // candidate sizes: dynamic vs fixed (one block) vs stored (chunked, byte-aligned)
  var hbits: int64 := 5 + 5 + 4 + 3 * e.numCL;
  for var i := 0 to e.rlen-1 do hbits := hbits + e.cllen[e.clsym[i]] + e.clxb[i];
  var dynBits := 3 + hbits + tokbits(e, @e.llen[0], @e.dlen[0]);
  var fixBits := 3 + tokbits(e, @e.FIXL[0], @e.FIXD[0]);
  var nb := (e.slen + 65_534) div 65_535;
  var storedBytes: int64 := int64(nb) * 5 + e.slen;

  var nonStored := dynBits; var dyn := true;
  if fixBits < dynBits then begin nonStored := fixBits; dyn := false; end;

  if storedBytes < (nonStored + 7) div 8 then
    emitStored(e, final)
  else begin
    // the block's exact bit cost is known, so reserve it once and let the emit
    // loop write without a capacity check per token
    ensure(e, longint((nonStored + 7) div 8) + 16);
    put(e, ord(final), 1);                           // BFINAL
    if dyn then begin
      put(e, 2, 2);                                  // BTYPE = 10 (dynamic)
      put(e, e.lcount - 257, 5); put(e, e.dcount - 1, 5); put(e, e.numCL - 4, 4);
      for var i := 0 to e.numCL-1 do put(e, e.cllen[CO[i]], 3);
      for var i := 0 to e.rlen-1 do begin
        put(e, e.clcode[e.clsym[i]], e.cllen[e.clsym[i]]);
        if e.clxb[i] > 0 then put(e, e.clext[i], e.clxb[i]);
      end;
    end else begin
      put(e, 1, 2);                                  // BTYPE = 01 (fixed)
      Move(e.FIXL[0], e.llen[0], 288); Move(e.FIXD[0], e.dlen[0], 30);
      mkcodes(@e.llen[0], 288, @e.lcode[0]); mkcodes(@e.dlen[0], 30, @e.dcode[0]);
    end;
    emitTokens(e);                                   // replay pass 1's tokens
    put(e, e.lcode[256], e.llen[256]);               // end of block
  end;
end;

// container header (fmt: ZFLATE_RAW / ZFLATE_ZLIB / ZFLATE_GZIP); the level is
// advertised in the header, as zlib FLEVEL and gzip XFL
procedure packHeader(var e: tzdefl; fmt: longint; level: dword);
begin
  if fmt = ZFLATE_ZLIB then begin
    ob1(e, $78);                                 // CM=8 (deflate), CINFO=7 (32k window)
    // FLG carries FLEVEL and an FCHECK that makes the 2 bytes a multiple of 31
    var flg := match level of
      0, 1: $01;
      2..5: $5e;
      6:    $9c;
      _:    $da;
    end;
    ob1(e, flg);
  end else if fmt = ZFLATE_GZIP then begin
    ob1(e, $1f); ob1(e, $8b); ob1(e, 8);          // magic, deflate
    for var i := 0 to 4 do ob1(e, 0);             // no flags, mtime 0
    var xfl := match level of
      9: 2;                                       // best compression
      0, 1: 4;                                    // fastest
      _: 0;
    end;
    ob1(e, xfl);
    ob1(e, $ff);                                  // OS unknown
  end;
end;

// container footer from checksums of the source data
procedure packFooter(var e: tzdefl; fmt: longint; crc, adler, isize: dword);
begin
  if fmt = ZFLATE_ZLIB then begin
    // adler32, big-endian
    ob1(e, adler shr 24); ob1(e, (adler shr 16) and $ff); ob1(e, (adler shr 8) and $ff); ob1(e, adler and $ff);
  end else if fmt = ZFLATE_GZIP then begin
    // crc32 then size, little-endian
    ob1(e, crc and $ff); ob1(e, (crc shr 8) and $ff); ob1(e, (crc shr 16) and $ff); ob1(e, crc shr 24);
    ob1(e, isize and $ff); ob1(e, (isize shr 8) and $ff); ob1(e, (isize shr 16) and $ff); ob1(e, isize shr 24);
  end;
end;

// compress one chunk into a self-contained, byte-aligned DEFLATE fragment: a
// non-final block followed by an empty stored block that flushes to a byte
// boundary, so fragments from different threads concatenate into a valid stream
procedure compressFragment(src: pbyte; len: dword; level: dword; out frag: TBytes);
begin
  var e := znew;                                 // the worker's own state
  try
    setLevel(e^, level);
    e^.sp := src; e^.slen := len;
    compressBlock(e^, false);
    put(e^, 0, 1); put(e^, 0, 2); flush(e^);      // empty non-final stored block: BFINAL=0 BTYPE=00, align
    ob1(e^, 0); ob1(e^, 0); ob1(e^, $ff); ob1(e^, $ff);   // LEN=0, NLEN=FFFF
    frag := nil;
    setlength(frag, e^.op);
    if e^.op > 0 then Move(e^.buf^, frag[0], e^.op);
  finally
    zfree(e);
  end;
end;

// compress data across nt workers and append the fragments to the output, in
// order. the whole input is already in memory, so the chunks are compressed
// straight out of it with no copying; a batch at a time keeps the progress
// callback and its abort responsive. leaves the stream open: the caller emits
// the final block. must be called on a byte boundary
procedure packParallel(var e: tzdefl; data: pointer; len: dword; level: dword; nt: longint);
begin
  var frags: array of TBytes := nil;
  setlength(frags, nt);
  var cb := zprogress;
  var at: qword := 0;
  while at < len do begin
    var cnt := 0;
    while (cnt < nt) and (at + qword(cnt) * ZSCHUNK < len) do inc(cnt);
    for parallel(nt) var s := 0 to cnt-1 do begin
      var off := at + qword(s) * ZSCHUNK;
      var n := len - off;
      if n > ZSCHUNK then n := ZSCHUNK;
      compressFragment(pbyte(data) + off, n, level, frags[s]);
    end;
    for var s := 0 to cnt-1 do begin
      obn(e, pointer(frags[s]), length(frags[s]));
      frags[s] := nil;
    end;
    at := at + qword(cnt) * ZSCHUNK;
    if at > len then at := len;
    if (cb <> nil) and (not cb(at, len, e.op)) then begin e.aborted := true; break; end;
  end;
  if not e.aborted then begin put(e, 1, 1); put(e, 1, 2); put(e, 0, 7); end;   // final empty block: the fragments are all non-final
end;

// fmt: ZFLATE_RAW / ZFLATE_ZLIB / ZFLATE_GZIP. header + deflate stream + checksum footer
function pack(fmt: longint; data: pointer; len: dword; out outbuf: pointer; out outlen: dword; level: dword): integer;
begin
  outbuf := nil; outlen := 0;
  if ((data = nil) and (len <> 0)) or (len > $7FFFFFFF) then exit(ZFLATE_EDEFLATE);
  var nt := zuse_threads;
  if nt < 1 then nt := 1;
  if nt > 64 then nt := 64;
  var e := znew;
  setLevel(e^, level);
  e^.progtotal := len;
  e^.usecb := zprogress <> nil;
  result := ZFLATE_EDEFLATE;
  try
    packHeader(e^, fmt, level);
    if len = 0 then begin put(e^, 1, 1); put(e^, 1, 2); put(e^, 0, 7); end     // empty: final fixed, just EOB
    else if nt > 1 then begin
      e^.usecb := false;                                                       // packParallel drives the callback itself
      packParallel(e^, data, len, level, nt);
    end else
      // one block per chunk, so the token buffer stays bounded on huge inputs
      for var at: dword := 0 to (len - 1) div ZSCHUNK do begin
        e^.progbase := qword(at) * ZSCHUNK;
        e^.sp := pbyte(data) + e^.progbase;
        e^.slen := len - e^.progbase;
        if e^.slen > ZSCHUNK then e^.slen := ZSCHUNK;
        compressBlock(e^, e^.progbase + dword(e^.slen) >= len);
        if e^.aborted then break;
      end;
    if e^.aborted then result := ZFLATE_EABORTED
    else begin
      flush(e^);
      var c: dword := 0; var a: dword := 1;
      if fmt = ZFLATE_ZLIB then a := adler32(1, data, len)
      else if fmt = ZFLATE_GZIP then c := crc32b(0, data, len);
      packFooter(e^, fmt, c, a, len);
      if zprogress <> nil then zprogress(len, len, e^.op);
      outbuf := e^.buf; outlen := e^.op;
      e^.buf := nil;                              // handed to the caller
      result := ZFLATE_OK;
    end;
  except
    result := ZFLATE_EDEFLATE;
  end;
  zfree(e);
end;

// single-threaded streaming compressor: one chunk = one bit-contiguous block
function zcompress_stream_seq(streamtype: dword; reader: tzreader; writer: tzwriter; totalsize: qword; level: dword): integer;
begin
  var e := znew;
  setLevel(e^, level);
  var cb := zprogress;                           // the per-block sites see chunk-local numbers, keep them quiet
  var bufA: pbyte := GetMem(ZSCHUNK);
  var bufB: pbyte := GetMem(ZSCHUNK);
  var crc: dword := 0; var adler: dword := 1;
  var total, wrote: qword := 0;
  result := ZFLATE_EDEFLATE;
  try
    packHeader(e^, streamtype, level);
    var cur := reader(bufA, ZSCHUNK);
    if cur = 0 then begin put(e^, 1, 1); put(e^, 1, 2); put(e^, 0, 7); end   // empty input: final fixed, just EOB
    else
      repeat
        var nxt := reader(bufB, ZSCHUNK);                        // look ahead to spot the last chunk
        if streamtype = ZFLATE_ZLIB then adler := adler32(adler, bufA, cur)
        else if streamtype = ZFLATE_GZIP then crc := crc32b(crc, bufA, cur);
        total := total + cur;
        e^.sp := bufA; e^.slen := cur;
        compressBlock(e^, nxt = 0);                              // back-references never cross chunks
        if e^.op > 0 then begin
          wrote := wrote + e^.op;
          if not writer(e^.buf, e^.op) then begin e^.aborted := true; break; end;
          e^.op := 0;
        end;
        if (cb <> nil) and (not cb(total, totalsize, wrote)) then begin e^.aborted := true; break; end;
        SwapValues(bufA, bufB);
        cur := nxt;
      until cur = 0;
    if e^.aborted then result := ZFLATE_EABORTED
    else begin
      flush(e^);
      packFooter(e^, streamtype, crc, adler, total and $ffffffff);
      wrote := wrote + e^.op;
      if (e^.op > 0) and (not writer(e^.buf, e^.op)) then result := ZFLATE_EABORTED
      else begin
        if cb <> nil then cb(total, totalsize, wrote);
        result := ZFLATE_OK;
      end;
    end;
  except
    result := ZFLATE_EDEFLATE;
  end;
  zfree(e);
  FreeMem(bufA); FreeMem(bufB);
end;

// multi-threaded streaming compressor: reads batches of nt chunks, compresses
// them across nt workers, writes the fragments back in order
function zcompress_stream_par(streamtype: dword; reader: tzreader; writer: tzwriter; totalsize: qword; level: dword; nt: longint): integer;
begin
  var e := znew;
  setLevel(e^, level);                           // for the header/footer written on this thread
  var cb := zprogress;
  var inbuf: array of pbyte := nil; setlength(inbuf, nt);
  for var i := 0 to nt-1 do inbuf[i] := GetMem(ZSCHUNK);
  var inlen: array of dword := nil; setlength(inlen, nt);
  var frags: array of TBytes := nil; setlength(frags, nt);
  var crc: dword := 0; var adler: dword := 1;
  var total, wrote: qword := 0;
  result := ZFLATE_EDEFLATE;
  try
    packHeader(e^, streamtype, level);
    if e^.op > 0 then begin
      wrote := wrote + e^.op;
      if not writer(e^.buf, e^.op) then e^.aborted := true;
      e^.op := 0;
    end;
    var eof := false;
    while (not eof) and (not e^.aborted) do begin
      // fill up to nt chunks for this batch
      var cnt := 0;
      while cnt < nt do begin
        var got := reader(inbuf[cnt], ZSCHUNK);
        if got = 0 then begin eof := true; break; end;
        inlen[cnt] := got; inc(cnt);
      end;
      if cnt = 0 then break;
      // compress the batch: each worker owns its encoder state
      for parallel(nt) var s := 0 to cnt-1 do
        compressFragment(inbuf[s], inlen[s], level, frags[s]);
      // write fragments in order, updating checksums and progress on this thread
      for var s := 0 to cnt-1 do begin
        if streamtype = ZFLATE_ZLIB then adler := adler32(adler, inbuf[s], inlen[s])
        else if streamtype = ZFLATE_GZIP then crc := crc32b(crc, inbuf[s], inlen[s]);
        total := total + inlen[s];
        wrote := wrote + length(frags[s]);
        if (length(frags[s]) > 0) and (not writer(pointer(frags[s]), length(frags[s]))) then begin e^.aborted := true; break; end;
        frags[s] := nil;
        if (cb <> nil) and (not cb(total, totalsize, wrote)) then begin e^.aborted := true; break; end;
      end;
    end;
    if e^.aborted then result := ZFLATE_EABORTED
    else begin
      // final empty block (BFINAL=1) plus the footer; reuse this thread's buffer
      e^.op := 0; e^.bb := 0; e^.bc := 0;
      put(e^, 1, 1); put(e^, 1, 2); put(e^, 0, 7); flush(e^);
      packFooter(e^, streamtype, crc, adler, total and $ffffffff);
      wrote := wrote + e^.op;
      if (e^.op > 0) and (not writer(e^.buf, e^.op)) then result := ZFLATE_EABORTED
      else begin
        if cb <> nil then cb(total, totalsize, wrote);
        result := ZFLATE_OK;
      end;
    end;
  except
    result := ZFLATE_EDEFLATE;
  end;
  zfree(e);
  for var i := 0 to nt-1 do FreeMem(inbuf[i]);
end;

// fmt: ZFLATE_RAW / ZFLATE_ZLIB / ZFLATE_GZIP; picks the sequential or the
// threaded path depending on zuse_threads
function zcompress_stream(streamtype: dword; reader: tzreader; writer: tzwriter; totalsize: qword; level: dword): integer;
begin
  if (reader = nil) or (writer = nil) then exit(ZFLATE_EDEFLATE);
  var nt := zuse_threads;
  if nt < 1 then nt := 1;
  if nt > 64 then nt := 64;
  if nt = 1 then result := zcompress_stream_seq(streamtype, reader, writer, totalsize, level)
  else result := zcompress_stream_par(streamtype, reader, writer, totalsize, level, nt);
end;

function gzdeflate_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
begin result := zcompress_stream(ZFLATE_RAW, reader, writer, totalsize, level); end;

function gzcompress_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
begin result := zcompress_stream(ZFLATE_ZLIB, reader, writer, totalsize, level); end;

function gzencode_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
begin result := zcompress_stream(ZFLATE_GZIP, reader, writer, totalsize, level); end;

// ----- inflate decoder -----

const
  IFAST = 9;                     // huffman fast-table bits
  IFASTSIZE = 1 shl IFAST;
  IFASTMASK = IFASTSIZE - 1;
  ISLACK = 8;                    // copy overshoot the output buffer must tolerate

type
  // one canonical huffman table: counts/symbols for the exact walk, plus a lookup
  // that resolves every code of at most IFAST bits in a single step
  tzhuff = record
    cnt: array[16] of word;
    sym: array[288] of word;
    fast: array[IFASTSIZE] of word;   // (code length shl 9) or symbol, 0 = not filled
  end;

  // decoder state. plain data only, so it lives on the caller's stack: the hot
  // loop reads locals instead of paying a TLS lookup per bit, and two threads
  // decoding at the same time simply own two records
  tzinfl = record
    rp: pbyte;                        // input buffer
    si, sl: longint;
    bitbuf: qword;                    // bit accumulator, LSB-first
    bitcnt: longint;
    ob: pbyte;                        // output buffer
    rop, rcap: longint;
    er: longint;                      // hard error
    aborted: boolean;
    usereader, usewriter, usecb: boolean;   // the callbacks themselves stay in threadvars
    fmt: dword;                       // detected container, picks which checksum to maintain
    total: qword;                     // total input size for progress (0 = unknown)
    inpos, outpos: qword;             // input consumed / output flushed
    crc, adler: dword;                // running checksums of the flushed output
    lit, dist: tzhuff;
    lens: array[320] of byte;
  end;

// streaming hooks; read once per refill or per token, never per byte
threadvar
  zsreader: tzreader;
  zswriter: tzwriter;
  zscb: tzprogress;

// refill the streaming input buffer; false when the source is dry
function zrefill(var st: tzinfl): boolean;
begin
  result := false;
  if not st.usereader then exit;
  st.sl := zsreader(st.rp, ZSINBUF);
  st.si := 0;
  if st.sl = 0 then exit;
  st.inpos := st.inpos + st.sl;
  if st.usecb and (not zscb(st.inpos, st.total, st.outpos)) then begin st.aborted := true; exit; end;
  result := true;
end;

// one input byte; refills in streaming mode, flags an error when input runs dry
function nb(var st: tzinfl): longint;
begin
  if st.si >= st.sl then
    if not zrefill(st) then begin st.er := 1; exit(0); end;
  result := st.rp[st.si]; inc(st.si);
end;

// top up the bit accumulator to at least 57 bits, eight at a time where the
// input allows it. a dry input is not an error here: the caller checks bitcnt
// against the bits it actually consumes
procedure zfill(var st: tzinfl);
begin
  if st.bitcnt > 56 then exit;
  // bits above bitcnt are whatever the last bulk read pulled in past the byte it
  // counted; drop them, the bytes they came from are read again below
  st.bitbuf := st.bitbuf and ((qword(1) shl st.bitcnt) - 1);
  if st.si + 8 <= st.sl then begin
    st.bitbuf := st.bitbuf or (PQWord(st.rp + st.si)^ shl st.bitcnt);
    inc(st.si, (63 - st.bitcnt) shr 3);
    st.bitcnt := st.bitcnt or 56;
    exit;
  end;
  repeat
    while (st.bitcnt <= 56) and (st.si < st.sl) do begin
      st.bitbuf := st.bitbuf or (qword(st.rp[st.si]) shl st.bitcnt);
      inc(st.si); inc(st.bitcnt, 8);
    end;
    if st.bitcnt > 56 then break;
  until not zrefill(st);
end;

// n bits, LSB-first
function gn(var st: tzinfl; n: longint): longint;
begin
  if n = 0 then exit(0);
  if st.bitcnt < n then zfill(st);
  if st.bitcnt < n then begin st.er := 1; exit(0); end;
  result := longint(st.bitbuf and ((qword(1) shl n) - 1));
  st.bitbuf := st.bitbuf shr n; dec(st.bitcnt, n);
end;

// one bit
function gb(var st: tzinfl): longint;
begin
  if st.bitcnt < 1 then zfill(st);
  if st.bitcnt < 1 then begin st.er := 1; exit(0); end;
  result := longint(st.bitbuf and 1);
  st.bitbuf := st.bitbuf shr 1; dec(st.bitcnt);
end;

// drop the partial bits, leaving the accumulator on a byte boundary
procedure zalign(var st: tzinfl);
begin
  var drop := st.bitcnt and 7;
  st.bitbuf := st.bitbuf shr drop;
  dec(st.bitcnt, drop);
end;

// huffman decode: one table lookup for codes up to IFAST bits, canonical walk
// for the rest
function hd(var st: tzinfl; var t: tzhuff): longint;
begin
  if st.bitcnt < 15 then zfill(st);
  var e := t.fast[longint(st.bitbuf) and IFASTMASK];
  if e <> 0 then begin
    var n := longint(e shr 9);
    if st.bitcnt < n then begin st.er := 1; exit(0); end;
    st.bitbuf := st.bitbuf shr n; dec(st.bitcnt, n);
    exit(e and 511);
  end;
  var code := 0; var first := 0; var idx := 0;
  for var k := 1 to 15 do begin
    code := code or longint((st.bitbuf shr (k-1)) and 1);
    var c := t.cnt[k];
    if code - c < first then begin
      if st.bitcnt < k then begin st.er := 1; exit(0); end;
      st.bitbuf := st.bitbuf shr k; dec(st.bitcnt, k);
      exit(t.sym[idx + code - first]);
    end;
    idx := idx + c; first := (first + c) shl 1; code := code shl 1;
  end;
  st.er := 1;                                     // 15 bits, no valid code
  result := 0;
end;

// build one huffman table from the code lengths L[0..n-1]
procedure mk(var t: tzhuff; L: pbyte; n: longint);
begin
  FillChar(t.cnt, sizeof(t.cnt), 0);
  for var i := 0 to n-1 do inc(t.cnt[L[i]]);
  var ofs: array[17] of word;
  ofs[1] := 0;
  for var i := 1 to 15 do ofs[i+1] := ofs[i] + t.cnt[i];
  for var i := 0 to n-1 do
    if L[i] <> 0 then begin t.sym[ofs[L[i]]] := i; inc(ofs[L[i]]); end;
  // fast lookup: a code of k bits owns every index whose low k bits match it,
  // and the stream reads bits LSB-first, so the canonical code goes in reversed
  FillChar(t.fast, sizeof(t.fast), 0);
  var code := 0; var idx := 0;
  for var k := 1 to 15 do begin
    if (k <= IFAST) and (t.cnt[k] > 0) then
      for var j := 0 to t.cnt[k]-1 do begin
        var q := rev(code + j, k);
        var v := word((k shl 9) or t.sym[idx + j]);
        while q < IFASTSIZE do begin t.fast[q] := v; inc(q, 1 shl k); end;
      end;
    idx := idx + t.cnt[k];
    code := (code + t.cnt[k]) shl 1;
  end;
end;

// make room for n more output bytes
procedure zneed(var st: tzinfl; n: longint);
begin
  if st.rop + n <= st.rcap then exit;
  if st.rcap = 0 then st.rcap := 4096;
  while st.rcap < st.rop + n do st.rcap := st.rcap * 2;
  ReAllocMem(st.ob, st.rcap);
end;

// flush decoder output to the sink, keeping the back-reference window unless last
procedure oflush(var st: tzinfl; last: boolean);
begin
  var n := st.rop;
  if not last then n := st.rop - WS;
  if n <= 0 then exit;
  if st.fmt = ZFLATE_GZIP then st.crc := crc32b(st.crc, st.ob, n)
  else if st.fmt = ZFLATE_ZLIB then st.adler := adler32(st.adler, st.ob, n);
  st.outpos := st.outpos + n;
  if not zswriter(st.ob, n) then begin st.aborted := true; st.er := 1; exit; end;
  if not last then Move(st.ob[n], st.ob^, st.rop - n);
  st.rop := st.rop - n;
end;

// report progress; one-shot reports its own buffer positions, streaming the
// totals accumulated across refills and flushes
function zprog(var st: tzinfl): boolean;
begin
  if st.usereader then result := zscb(st.inpos, st.total, st.outpos)
  else result := zscb(st.si, st.sl, st.rop);
  if not result then begin st.aborted := true; st.er := 1; end;
end;

// copy n stored bytes to the output: whatever whole bytes sit in the bit
// accumulator first, then straight out of the input buffer
procedure zstored(var st: tzinfl; n: longint);
begin
  zneed(st, n);
  while n > 0 do begin
    if st.bitcnt >= 8 then begin
      st.ob[st.rop] := byte(st.bitbuf); inc(st.rop);
      st.bitbuf := st.bitbuf shr 8; dec(st.bitcnt, 8);
      dec(n);
    end else begin
      if st.si >= st.sl then
        if not zrefill(st) then begin st.er := 1; exit; end;
      var k := st.sl - st.si; if k > n then k := n;
      Move(st.rp[st.si], st.ob[st.rop], k);
      inc(st.si, k); inc(st.rop, k); dec(n, k);
    end;
  end;
end;

// decode DEFLATE blocks until the final one
procedure inflateLoop(var st: tzinfl);
begin
  var final := 0;
  repeat
    final := gb(st);
    var bt := gn(st, 2);
    if bt = 3 then st.er := 1;                    // reserved block type
    if st.er <> 0 then break;
    if st.usecb and (not zprog(st)) then break;
    if bt = 0 then begin
      zalign(st);
      var n := gn(st, 16);                      // LEN then one's-complement check
      var m := gn(st, 16);
      if (st.er <> 0) or ((n xor m) <> $FFFF) then begin st.er := 1; break; end;
      if st.usewriter and (st.rop >= ZSOUTMAX) then oflush(st, false);
      zstored(st, n);
      if st.er <> 0 then break;
    end else begin
      if bt = 1 then begin
        FillChar(st.lens[0], 144, 8); FillChar(st.lens[144], 112, 9); FillChar(st.lens[256], 24, 7); FillChar(st.lens[280], 8, 8);
        mk(st.lit, @st.lens[0], 288);
        FillChar(st.lens[0], 30, 5);
        mk(st.dist, @st.lens[0], 30);
      end else begin
        // dynamic header: build the code-length table, then the lit+dist lengths
        var hlit := gn(st, 5) + 257;
        var hdist := gn(st, 5) + 1;
        var hclen := gn(st, 4) + 4;
        if (hlit > 286) or (hdist > 30) then begin st.er := 1; break; end;
        FillChar(st.lens[0], 19, 0);
        for var i := 0 to hclen-1 do st.lens[CO[i]] := gn(st, 3);
        if st.er <> 0 then break;
        mk(st.lit, @st.lens[0], 19);
        var i := 0;
        while (i < hlit + hdist) and (st.er = 0) do begin
          var s := hd(st, st.lit);
          if st.er <> 0 then break;
          if s < 16 then begin st.lens[i] := s; inc(i); end
          else begin
            var r := 0; var v := 0;
            if s = 16 then begin
              if i = 0 then begin st.er := 1; break; end;
              r := gn(st, 2)+3; v := st.lens[i-1];
            end else if s = 17 then r := gn(st, 3)+3
            else r := gn(st, 7)+11;
            if i + r > hlit + hdist then begin st.er := 1; break; end;
            FillChar(st.lens[i], r, v); inc(i, r);
          end;
        end;
        if st.er <> 0 then break;
        mk(st.dist, @st.lens[hlit], hdist);
        mk(st.lit, @st.lens[0], hlit);
      end;
      // symbol loop: literals and (length, distance) matches until end-of-block
      var nx := 0;
      repeat
        if st.usewriter and (st.rop >= ZSOUTMAX) then oflush(st, false);
        if st.usecb and (st.rop >= nx) then begin
          nx := st.rop + 65_536;
          if not zprog(st) then break;
        end;
        zneed(st, 258 + ISLACK);
        var s := hd(st, st.lit);
        if st.er <> 0 then break;
        if s < 256 then begin
          st.ob[st.rop] := s; inc(st.rop);
        end else if s = 256 then break
        else begin
          s := s - 257;
          if s > 28 then begin st.er := 1; break; end;
          var ln := LB[s] + gn(st, LE[s]);
          var d := hd(st, st.dist);
          if st.er <> 0 then break;
          var dist := DB[d] + gn(st, DE[d]);
          if (st.er <> 0) or (dist > st.rop) then begin st.er := 1; break; end;  // before stream start
          var src := st.ob + st.rop - dist;
          var dst := st.ob + st.rop;
          inc(st.rop, ln);
          // 8 bytes at a time once the source is far enough back for the chunks
          // not to overlap; the slack in the buffer covers the overshoot
          if dist >= 8 then
            while ln > 0 do begin PQWord(dst)^ := PQWord(src)^; inc(dst, 8); inc(src, 8); dec(ln, 8); end
          else
            while ln > 0 do begin dst^ := src^; inc(dst); inc(src); dec(ln); end;
        end;
      until false;
    end;
  until (final <> 0) or (st.er <> 0);
end;

// set up a decoder over a whole input buffer, no streaming hooks
procedure zinit(out st: tzinfl; data: pointer; size: dword);
begin
  st.rp := data; st.sl := size; st.si := 0;
  st.bitbuf := 0; st.bitcnt := 0;
  st.ob := nil; st.rop := 0; st.rcap := 0;
  st.er := 0; st.aborted := false;
  st.usereader := false; st.usewriter := false;
  st.fmt := ZFLATE_RAW;
  st.total := size; st.inpos := 0; st.outpos := 0;
  st.crc := 0; st.adler := 1;
  zscb := zprogress;
  st.usecb := zscb <> nil;
end;

// decompress a raw DEFLATE stream; handles every block type (stored, fixed, dynamic)
function unpackRaw(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin
  output := nil; outputsize := 0;
  if (data = nil) or (size = 0) then exit(ZFLATE_EINFLATE);
  var st: tzinfl;
  zinit(st, data, size);
  // the output size is unknown up front, but four bytes out per byte in is a
  // fair first guess and saves most of the doubling
  var guess: int64 := int64(size) * 4;
  if guess > 16*1024*1024 then guess := 16*1024*1024;
  zneed(st, longint(guess));
  try
    inflateLoop(st);
  except
    st.er := 1;
  end;
  if st.er <> 0 then begin
    if st.ob <> nil then FreeMem(st.ob);
    if st.aborted then exit(ZFLATE_EABORTED);
    exit(ZFLATE_EINFLATE);
  end;
  if st.usecb then zscb(st.sl, st.sl, st.rop);
  if st.rop > 0 then ReAllocMem(st.ob, st.rop);   // hand back the guess that went unused
  output := st.ob; outputsize := st.rop;
  result := ZFLATE_OK;
end;

// consume the container header sequentially (streaming)
procedure skipHeader(var st: tzinfl);
begin
  if st.fmt = ZFLATE_ZLIB then gn(st, 16)
  else if st.fmt = ZFLATE_GZIP then begin
    gn(st, 24);
    var flags := gn(st, 8);
    gn(st, 24); gn(st, 24);                                   // mtime, xfl, os
    // extra field
    if (flags and $04) <> 0 then begin
      var n := gn(st, 16);
      for var i := 1 to n do begin
        gn(st, 8);
        if st.er <> 0 then exit;
      end;
    end;
    if (flags and $08) <> 0 then while (gn(st, 8) <> 0) and (st.er = 0) do ;   // filename
    if (flags and $10) <> 0 then while (gn(st, 8) <> 0) and (st.er = 0) do ;   // comment
    if (flags and $02) <> 0 then gn(st, 16);                                   // header crc16
  end;
end;

// read and verify the container footer against the running checksums (streaming)
function checkFooter(var st: tzinfl): integer;
begin
  result := ZFLATE_OK;
  zalign(st);                                     // footer starts at the next byte
  if st.fmt = ZFLATE_ZLIB then begin
    // adler32, big-endian
    var a: dword := 0;
    for var i := 1 to 4 do a := (a shl 8) or dword(gn(st, 8));
    if st.er <> 0 then exit(ZFLATE_EINFLATE);
    if a <> st.adler then result := ZFLATE_ECHECKSUM;
  end else if st.fmt = ZFLATE_GZIP then begin
    // crc32 then size, little-endian
    var c: dword := 0;
    for var i := 0 to 3 do c := c or (dword(gn(st, 8)) shl (8*i));
    var isize: dword := 0;
    for var i := 0 to 3 do isize := isize or (dword(gn(st, 8)) shl (8*i));
    if st.er <> 0 then exit(ZFLATE_EINFLATE);
    if isize <> dword(st.outpos) then exit(ZFLATE_EOUTPUTSIZE);
    if c <> st.crc then result := ZFLATE_ECHECKSUM;
  end;
end;

function zdecompress_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0): integer;
begin
  if (reader = nil) or (writer = nil) then exit(ZFLATE_EINFLATE);
  var st: tzinfl;
  var inbuf: pbyte := GetMem(ZSINBUF);
  zinit(st, inbuf, 0);
  st.usereader := true; st.usewriter := true;
  st.total := totalsize;
  zsreader := reader; zswriter := writer;
  result := ZFLATE_EINFLATE;
  try
    // buffer enough bytes to sniff the container type
    while st.sl < 3 do begin
      var got := reader(inbuf + st.sl, ZSINBUF - st.sl);
      if got = 0 then break;
      inc(st.sl, got);
    end;
    st.inpos := st.sl;
    if (st.sl >= 3) and (inbuf[0] = $1f) and (inbuf[1] = $8b) and (inbuf[2] = 8) then st.fmt := ZFLATE_GZIP
    else if (st.sl >= 2) and ((inbuf[0] and $0f) = 8) and ((inbuf[0] shr 4) <= 7) and ((inbuf[1] and $20) = 0) and ((inbuf[0]*256 + inbuf[1]) mod 31 = 0) then st.fmt := ZFLATE_ZLIB;
    skipHeader(st);
    if st.er = 0 then inflateLoop(st);
    if st.er = 0 then oflush(st, true);
    if st.er = 0 then result := checkFooter(st);
  except
    st.er := 1; result := ZFLATE_EINFLATE;
  end;
  if st.aborted then result := ZFLATE_EABORTED;
  if (result = ZFLATE_OK) and st.usecb then zscb(st.inpos, st.total, st.outpos);
  if st.ob <> nil then FreeMem(st.ob);
  FreeMem(inbuf);
  zsreader := nil; zswriter := nil; zscb := nil;
end;

// ----- container wrappers -----

function packRaw(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword): integer;
begin result := pack(ZFLATE_RAW, data, size, output, outputsize, level); end;

function packZlib(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword): integer;
begin result := pack(ZFLATE_ZLIB, data, size, output, outputsize, level); end;

function packGzip(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword): integer;
begin result := pack(ZFLATE_GZIP, data, size, output, outputsize, level); end;

function unpackZlib(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin
  output := nil; outputsize := 0;
  var info: tzlibinfo;
  if not read_zlib_header(data, size, info) then exit(ZFLATE_EZLIBINVALID);
  var p := pbyte(data);
  result := unpackRaw(p + info.streamat, size - info.streamat - info.footerlen, output, outputsize);
  if result <> ZFLATE_OK then exit;
  // footer: adler32 of the decompressed data, big-endian
  var a: dword := (dword(p[size-4]) shl 24) or (dword(p[size-3]) shl 16) or (dword(p[size-2]) shl 8) or p[size-1];
  if adler32(1, output, outputsize) <> a then begin
    if output <> nil then FreeMem(output);
    output := nil; outputsize := 0;
    result := ZFLATE_ECHECKSUM;
  end;
end;

function unpackGzip(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin
  output := nil; outputsize := 0;
  var info: tgzipinfo;
  if not read_gzip_header(data, size, info) then exit(ZFLATE_EGZIPINVALID);
  var p := pbyte(data);
  result := unpackRaw(p + info.streamat, size - info.streamat - info.footerlen, output, outputsize);
  if result <> ZFLATE_OK then exit;
  // footer: crc32 then original size, little-endian
  var c: dword := p[size-8] or (p[size-7] shl 8) or (p[size-6] shl 16) or (dword(p[size-5]) shl 24);
  var isize: dword := p[size-4] or (p[size-3] shl 8) or (p[size-2] shl 16) or (dword(p[size-1]) shl 24);
  var err := ZFLATE_OK;
  if outputsize <> isize then err := ZFLATE_EOUTPUTSIZE
  else if crc32b(0, output, outputsize) <> c then err := ZFLATE_ECHECKSUM;
  if err <> ZFLATE_OK then begin
    if output <> nil then FreeMem(output);
    output := nil; outputsize := 0;
    result := err;
  end;
end;

function unpackAuto(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin
  result := match stream_info(data, size).streamtype of
    ZFLATE_GZIP: unpackGzip(data, size, output, outputsize);
    ZFLATE_ZLIB: unpackZlib(data, size, output, outputsize);
    _: unpackRaw(data, size, output, outputsize);
  end;
end;

// ----- headers -----

function read_zlib_header(data: pointer; size: dword; out info: tzlibinfo): boolean;
begin
  result := false;
  info := default(tzlibinfo);
  if (data = nil) or (size < 6) then exit;        // 2 header + 4 adler footer
  var p := pbyte(data);
  // CM = 8 (deflate), CINFO <= 7, no preset dictionary, (b0*256+b1) mod 31 = 0
  if ((p[0] and $0f) <> 8) or ((p[0] shr 4) > 7) or ((p[1] and $20) <> 0) or ((p[0]*256 + p[1]) mod 31 <> 0) then exit;
  info.streamat := 2;
  info.footerlen := 4;
  result := true;
end;

function read_gzip_header(data: pointer; size: dword; out info: tgzipinfo): boolean;
begin
  result := false;
  info := default(tgzipinfo);
  if (data = nil) or (size < 18) then exit;       // 10 header + 8 footer
  var p := pbyte(data);
  if (p[0] <> $1f) or (p[1] <> $8b) or (p[2] <> 8) then exit;
  Move(p[4], info.modtime, 4);
  var flags := p[3];
  var at: dword := 10;
  // extra field
  if (flags and $04) <> 0 then begin
    if at + 2 > size then exit;
    at := at + 2 + (p[at] or (p[at+1] shl 8));
  end;
  // filename
  if (flags and $08) <> 0 then begin
    if at >= size then exit;
    info.filename := pchar(@p[at]);
    while (at < size) and (p[at] <> 0) do inc(at);
    inc(at);
  end;
  // comment
  if (flags and $10) <> 0 then begin
    if at >= size then exit;
    info.comment := pchar(@p[at]);
    while (at < size) and (p[at] <> 0) do inc(at);
    inc(at);
  end;
  // crc16 of the header, skip
  if (flags and $02) <> 0 then at := at + 2;
  if at + 8 > size then exit;
  info.streamat := at;
  info.footerlen := 8;
  result := true;
end;

function stream_info(data: pointer; size: dword): (streamtype, streamat, footerlen: dword);
begin
  var gzip: tgzipinfo;
  if read_gzip_header(data, size, gzip) then exit(ZFLATE_GZIP, gzip.streamat, gzip.footerlen);
  var zlib: tzlibinfo;
  if read_zlib_header(data, size, zlib) then exit(ZFLATE_ZLIB, zlib.streamat, zlib.footerlen);
  result := (ZFLATE_RAW, 0, 0);
end;

// ----- public API -----

type
  tzunpack = function(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
  tzpack = function(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword): integer;

// store the code in zlasterror and pass it through
function zret(code: integer): integer;
begin
  zlasterror := code;
  result := code;
end;

// run a decompressor, return the output as string ('' on error)
function zstr(fn: tzunpack; const src: string): string;
begin
  result := '';
  var p: pointer; var n: dword;
  if zret(fn(pointer(src), length(src), p, n)) <> ZFLATE_OK then exit;
  setlength(result, n);
  if n > 0 then Move(p^, result[1], n);
  if p <> nil then FreeMem(p);
end;

// run a decompressor, return the output as TBytes (nil on error)
function zbytes(fn: tzunpack; const src: TBytes): TBytes;
begin
  result := nil;
  var p: pointer; var n: dword;
  if zret(fn(pointer(src), length(src), p, n)) <> ZFLATE_OK then exit;
  setlength(result, n);
  if n > 0 then Move(p^, result[0], n);
  if p <> nil then FreeMem(p);
end;

// run a compressor, return the output as string ('' on error)
function zstrp(fn: tzpack; const src: string; level: dword): string;
begin
  result := '';
  var p: pointer; var n: dword;
  if zret(fn(pointer(src), length(src), p, n, level)) <> ZFLATE_OK then exit;
  setlength(result, n);
  if n > 0 then Move(p^, result[1], n);
  if p <> nil then FreeMem(p);
end;

// run a compressor, return the output as TBytes (nil on error)
function zbytesp(fn: tzpack; const src: TBytes; level: dword): TBytes;
begin
  result := nil;
  var p: pointer; var n: dword;
  if zret(fn(pointer(src), length(src), p, n, level)) <> ZFLATE_OK then exit;
  setlength(result, n);
  if n > 0 then Move(p^, result[0], n);
  if p <> nil then FreeMem(p);
end;

function gzdeflate(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
begin result := zret(packRaw(data, size, output, outputsize, level)); end;

function gzdeflate(const str: string; level: dword = ZFLATE_DEFAULT): string;
begin result := zstrp(@packRaw, str, level); end;

function gzdeflate(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
begin result := zbytesp(@packRaw, bytes, level); end;

function gzinflate(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin result := zret(unpackRaw(data, size, output, outputsize)); end;

function gzinflate(const str: string): string;
begin result := zstr(@unpackRaw, str); end;

function gzinflate(const bytes: TBytes): TBytes;
begin result := zbytes(@unpackRaw, bytes); end;

function gzcompress(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
begin result := zret(packZlib(data, size, output, outputsize, level)); end;

function gzcompress(const str: string; level: dword = ZFLATE_DEFAULT): string;
begin result := zstrp(@packZlib, str, level); end;

function gzcompress(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
begin result := zbytesp(@packZlib, bytes, level); end;

function gzuncompress(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin result := zret(unpackZlib(data, size, output, outputsize)); end;

function gzuncompress(const str: string): string;
begin result := zstr(@unpackZlib, str); end;

function gzuncompress(const bytes: TBytes): TBytes;
begin result := zbytes(@unpackZlib, bytes); end;

function gzencode(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
begin result := zret(packGzip(data, size, output, outputsize, level)); end;

function gzencode(const str: string; level: dword = ZFLATE_DEFAULT): string;
begin result := zstrp(@packGzip, str, level); end;

function gzencode(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
begin result := zbytesp(@packGzip, bytes, level); end;

function gzdecode(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin result := zret(unpackGzip(data, size, output, outputsize)); end;

function gzdecode(const str: string): string;
begin result := zstr(@unpackGzip, str); end;

function gzdecode(const bytes: TBytes): TBytes;
begin result := zbytes(@unpackGzip, bytes); end;

function zdecompress(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin result := zret(unpackAuto(data, size, output, outputsize)); end;

function zdecompress(const str: string): string;
begin result := zstr(@unpackAuto, str); end;

function zdecompress(const bytes: TBytes): TBytes;
begin result := zbytes(@unpackAuto, bytes); end;

// ----- error translation -------------------

function zflate_error_str(code: integer): string;
begin
  {$ifdef ZFLATE_ERROR_TRANSLATION}
  result := case code of
    ZFLATE_OK          : 'ok';
    ZFLATE_EDEFLATE    : 'deflate failed';
    ZFLATE_EINFLATE    : 'inflate failed';
    ZFLATE_EZLIBINVALID: 'invalid zlib header';
    ZFLATE_EGZIPINVALID: 'invalid gzip header';
    ZFLATE_ECHECKSUM   : 'invalid checksum';
    ZFLATE_EOUTPUTSIZE : 'output size doesnt match gzip footer';
    ZFLATE_EABORTED    : 'aborted by callback';
    ZFLATE_ENODATA     : 'no input data';
    ZFLATE_EFILEREAD   : 'cannot read file';
    ZFLATE_EFILEWRITE  : 'cannot write file';
  else
    'unknown';
  {$else}
  system.Str(code, result);
  {$endif}
end;

initialization
  // value -> code index tables, built once and read-only from then on
  for var ln := 3 to 258 do LENSYM[ln] := sym(ln, @LB[0], 28);
  // distances 1..256 map one to one, above that each 128-wide bucket shares a code
  for var d := 1 to 256 do DISTSYM[d-1] := sym(d, @DB[0], 29);
  for var d := 257 to 32_768 do DISTSYM[256 + ((d-1) shr 7)] := sym(d, @DB[0], 29);
  // crc32 table: the bitwise reduction of each byte value, done once
  for var i := 0 to 255 do begin
    var c := dword(i);
    for var k := 0 to 7 do if c and 1 <> 0 then c := (c shr 1) xor $edb88320 else c := c shr 1;
    CRCTAB[i] := c;
  end;

finalization
  // this thread's warm encoder; other threads release theirs when they end
  if zdcache <> nil then begin
    if zdcache^.buf <> nil then FreeMem(zdcache^.buf);
    if zdcache^.toks <> nil then FreeMem(zdcache^.toks);
    FreeMem(zdcache);
    zdcache := nil;
  end;

end.
