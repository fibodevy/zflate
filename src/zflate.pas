{ zflate - self-contained DEFLATE (RFC 1951) compressor and decompressor with
  zlib (RFC 1950) and gzip (RFC 1952) containers. No dependencies beyond the
  system unit (plus cthreads on unix, for the threaded path).

  Every operation returns an integer code: ZFLATE_OK (0) on success, ZFLATE_E*
  otherwise. No exception ever escapes this unit. Codec state is per-thread
  (threadvar), so independent threads may compress/decompress at the same time
  without interfering. zcompress_stream additionally splits the work across
  zuse_threads worker threads. }

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

threadvar
  abort: boolean;     // progress callback requested abort

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

// encoder state (per-thread: each worker of the parallel path owns a copy)
threadvar
  zlevel: longint;                               // active compression level, 0 = store
  zchain, znice, zgood: longint;                 // search limits derived from zlevel
  zlazy: boolean;                                // lazy matching derived from zlevel
  sp: PByte;
  slen, op, cap, bb, bc, mst: longint;           // mst: match start from fm
  buf: pointer;
  toks: pdword;                                  // LZ tokens of the current block
  tokn: longint;                                 // tokens recorded
  progbase, progtotal: qword;                    // progress reporting across chunks
  head: array[HS] of longint;               // LZ77 hash chains
  prev: array[WS] of longint;
  fl: array[288] of longint;                  // lit/len + dist frequencies
  fd: array[32] of longint;
  llen, dlen: array[288] of byte;             // active code lengths (dyn or fixed)
  lcode, dcode: array[288] of word;           // active codes (LSB-first)
  FIXL: array[288] of byte;                   // fixed-Huffman code lengths
  FIXD: array[32] of byte;
  cf: array[19] of longint;                   // code-length alphabet
  cllen: array[19] of byte;
  clcode: array[19] of word;
  lcount, dcount, numCL, rlen: longint;
  clsym, clext, clxb: array[320] of byte;     // RLE'd code-length stream
  comb: array[320] of byte;
  hsym: array[288] of word;                   // Huffman builder scratch
  hfrq: array[576] of longint;
  hdad, hdep: array[576] of word;
  hbl: array[17] of word;

// pick the search effort for a compression level; must run on the thread that
// will do the compressing, the settings are per-thread
procedure setLevel(level: dword);
begin
  if level > 9 then level := 9;
  zlevel := level;
  zchain := LVCHAIN[level];
  znice := LVNICE[level];
  zgood := LVGOOD[level];
  zlazy := LVLAZY[level];
end;

// reverse the low n bits (canonical codes are MSB-first, DEFLATE writes LSB-first)
function rev(v, n: longint): longint;
begin
  result := 0;
  for var i := 0 to n-1 do begin result := (result shl 1) or (v and 1); v := v shr 1; end;
end;

// append one output byte, doubling the heap buffer as needed
procedure ob1(b: longint);
begin
  if op >= cap then begin if cap = 0 then cap := 256 else cap := cap * 2; ReAllocMem(buf, cap); end;
  PByte(buf)[op] := b; inc(op);
end;

// append n raw bytes; only valid when the bit buffer sits on a byte boundary
procedure obn(p: pointer; n: longint);
begin
  if op + n > cap then begin
    if cap = 0 then cap := 256;
    while cap < op + n do cap := cap * 2;
    ReAllocMem(buf, cap);
  end;
  if n > 0 then Move(p^, (PByte(buf) + op)^, n);
  inc(op, n);
end;

// write n bits, LSB-first
procedure put(v, n: longint);
begin
  bb := bb or (v shl bc); inc(bc, n);
  while bc >= 8 do begin ob1(bb and $FF); bb := bb shr 8; dec(bc, 8); end;
end;

procedure flush;
begin
  if bc > 0 then begin ob1(bb and $FF); bb := 0; bc := 0; end;
end;

// length-limited Huffman code lengths for f[0..n-1] (>= 2 leaves forced so the
// code is always complete); o[] receives the bit lengths. Two-queue Huffman with
// zlib-style overflow redistribution capped at mx.
procedure mkhuff(f: PLongint; n, mx: longint; o: PByte);
begin
  for var i := 0 to n-1 do o[i] := 0;
  var L := 0;
  for var i := 0 to n-1 do if f[i] > 0 then begin hsym[L] := i; hfrq[L] := f[i]; inc(L); end;
  var t := 0;
  while L < 2 do begin if f[t] = 0 then begin hsym[L] := t; hfrq[L] := 1; inc(L); end; inc(t); end;
  // insertion sort leaves ascending by frequency
  for var a := 1 to L-1 do begin
    var ff := hfrq[a]; var ss := hsym[a]; var b := a-1;
    while (b >= 0) and (hfrq[b] > ff) do begin hfrq[b+1] := hfrq[b]; hsym[b+1] := hsym[b]; dec(b); end;
    hfrq[b+1] := ff; hsym[b+1] := ss;
  end;
  // two-queue Huffman: leaf queue [lo..L) merged with internal queue [iq..ni)
  var lo := 0; var iq := L; var ni := L;
  for var c := 1 to L-1 do begin
    var a, b: longint;
    if (lo < L) and ((iq >= ni) or (hfrq[lo] <= hfrq[iq])) then begin a := lo; inc(lo); end else begin a := iq; inc(iq); end;
    if (lo < L) and ((iq >= ni) or (hfrq[lo] <= hfrq[iq])) then begin b := lo; inc(lo); end else begin b := iq; inc(iq); end;
    hfrq[ni] := hfrq[a] + hfrq[b]; hdad[a] := ni; hdad[b] := ni; inc(ni);
  end;
  // bit length = node depth; a parent always has a higher index than its children
  hdep[ni-1] := 0;
  for var i := ni-2 downto 0 do hdep[i] := hdep[hdad[i]] + 1;
  var mxb := 0;
  for var i := 0 to L-1 do if hdep[i] > mxb then mxb := hdep[i];
  if mxb > mx then begin
    for var b := 0 to mx do hbl[b] := 0;
    var ov := 0;
    for var i := 0 to ni-1 do begin
      if hdep[i] > mx then begin hdep[i] := mx; inc(ov); end;
      if i < L then inc(hbl[hdep[i]]);
    end;
    repeat
      var q := mx-1;
      while hbl[q] = 0 do dec(q);
      dec(hbl[q]); inc(hbl[q+1], 2); dec(hbl[mx]); dec(ov, 2);
    until ov <= 0;
    // least-frequent leaves (front) take the longest codes
    var k := 0;
    for var b := mx downto 1 do while hbl[b] > 0 do begin hdep[k] := b; inc(k); dec(hbl[b]); end;
  end;
  for var i := 0 to L-1 do o[hsym[i]] := hdep[i];
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
procedure tlit(b: longint); inline;
begin
  inc(fl[b]);
  toks[tokn] := b; inc(tokn);
end;

// record one (length, distance) match
procedure tmatch(ln, dist: longint); inline;
begin
  inc(fl[257 + LENSYM[ln]]); inc(fd[dsym(dist)]);
  toks[tokn] := TOKMATCH or (dword(ln) shl 16) or dword(dist); inc(tokn);
end;

// replay the recorded tokens through the active Huffman codes
procedure emitTokens;
begin
  for var i := 0 to tokn-1 do begin
    var t := toks[i];
    if t < TOKMATCH then put(lcode[t], llen[t])
    else begin
      var ln := longint((t shr 16) and $1ff);
      var dist := longint(t and $ffff);
      var li := LENSYM[ln]; var di := dsym(dist);
      put(lcode[257+li], llen[257+li]);
      if LE[li] > 0 then put(ln - LB[li], LE[li]);
      put(dcode[di], dlen[di]);
      if DE[di] > 0 then put(dist - DB[di], DE[di]);
    end;
  end;
end;

// insert positions lo..hi-1 into the hash chains, skipping any that lack the 3
// bytes of lookahead the hash needs. runs once per byte a match covers, so the
// per-thread state is hoisted out of the loop
procedure insRange(lo, hi: longint);
begin
  var s: pbyte := sp;
  var ph: plongint := @head[0];
  var pp: plongint := @prev[0];
  var top := slen - 3;                             // last position with lookahead
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
function fm(p, prevlen: longint): longint;
begin
  // the per-thread state is hoisted into locals up front: the chain walk below
  // runs up to zchain times per call and must not pay a TLS lookup per iteration
  var s: pbyte := sp;
  var ph: plongint := @head[0];
  var pp: plongint := @prev[0];
  var chain := zchain;
  var nice := znice;
  // already sitting on a decent match: spend a quarter of the effort looking for
  // a better one (zlib's good_length)
  if prevlen >= zgood then chain := chain shr 2;

  var h := ((s[p] shl 10) xor (s[p+1] shl 5) xor s[p+2]) and HM;
  var cand := ph[h];
  pp[p and WM] := cand; ph[h] := p;
  var best := 2;
  var bestst := 0;
  var mx := slen - p; if mx > 258 then mx := 258;
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
  if best > 2 then mst := bestst;                  // only meaningful for a real match
  result := best;
end;

// LZ77 over the whole input, recording tokens and their frequencies in one pass.
// Above level 3 a match at i is held back one byte to see if i+1 starts a longer
// one (zlib's lazy heuristic), below it every match is taken as found.
procedure lz;
begin
  FillChar(head, sizeof(head), $FF);
  tokn := 0;
  var s: pbyte := sp;                                      // stable for the whole pass
  var n := slen;
  var lazy := zlazy;
  var i := 0; var pl := 2; var ps := 0; var avail := 0;    // pl/ps: match deferred from i-1
  var nx := 0;
  while i < n do begin
    if (zprogress <> nil) and (i >= nx) then begin
      inc(nx, 65_536);
      if not zprogress(progbase + i, progtotal, op) then begin abort := true; exit; end;
    end;
    var ml := 2;
    // pl is the match deferred from i-1 in lazy mode, 2 (i.e. none) otherwise
    if i + 3 <= n then ml := fm(i, pl);                    // best match at i (inserts i)
    if not lazy then begin
      // greedy: emit the match at i straight away
      if ml >= 3 then begin
        tmatch(ml, i - mst);
        var e := i + ml; inc(i);
        insRange(i, e);
        i := e;
      end else begin tlit(s[i]); inc(i); end;
      continue;
    end;
    if (pl >= 3) and (ml <= pl) then begin
      // i-1's match is not beaten: emit it and skip the bytes it covers
      tmatch(pl, (i-1) - ps);
      var e := (i-1) + pl; inc(i);
      insRange(i, e);
      i := e; pl := 2; avail := 0;
    end else begin
      // defer i; the byte at i-1 (if any) could not do better, so emit it literally
      if avail = 1 then tlit(s[i-1]);
      pl := ml; ps := mst; avail := 1; inc(i);
    end;
  end;
  if avail = 1 then tlit(s[i-1]);                          // trailing literal
end;

// append one entry to the RLE'd code-length stream
procedure addrle(s, e, x: longint);
begin clsym[rlen] := s; clext[rlen] := e; clxb[rlen] := x; inc(cf[s]); inc(rlen); end;

// RLE-encode the lit+dist code lengths into the code-length alphabet (RFC 1951 3.2.7)
procedure hdrRLE;
begin
  for var i := 0 to lcount-1 do comb[i] := llen[i];
  for var i := 0 to dcount-1 do comb[lcount+i] := dlen[i];
  var tot := lcount + dcount;
  FillChar(cf, sizeof(cf), 0); rlen := 0;
  var i := 0;
  while i < tot do begin
    var cur := comb[i]; var j := i+1;
    while (j < tot) and (comb[j] = cur) do inc(j);
    var run := j - i;
    if cur = 0 then begin
      while run >= 11 do begin var take := run; if take > 138 then take := 138; addrle(18, take-11, 7); dec(run, take); end;
      while run >= 3 do begin var take := run; if take > 10 then take := 10; addrle(17, take-3, 3); dec(run, take); end;
      while run > 0 do begin addrle(0, 0, 0); dec(run); end;
    end else begin
      addrle(cur, 0, 0); dec(run);
      while run >= 3 do begin var take := run; if take > 6 then take := 6; addrle(16, take-3, 2); dec(run, take); end;
      while run > 0 do begin addrle(cur, 0, 0); dec(run); end;
    end;
    i := j;
  end;
end;

// total bit cost of the LZ tokens (+ end-of-block) under the given code lengths
function tokbits(ll, dl: PByte): int64;
begin
  result := 0;
  for var i := 0 to 285 do result := result + int64(fl[i]) * ll[i];
  for var i := 0 to 29 do result := result + int64(fd[i]) * dl[i];
  for var i := 0 to 28 do result := result + int64(fl[257+i]) * LE[i];   // length extra
  for var i := 0 to 29 do result := result + int64(fd[i]) * DE[i];       // distance extra
end;

// emit the whole input as byte-aligned stored blocks (<= 65535 each)
procedure emitStored(final: boolean);
begin
  var p := 0;
  while p < slen do begin
    if (zprogress <> nil) and (not zprogress(progbase + p, progtotal, op)) then begin abort := true; exit; end;
    var n := slen - p; if n > 65_535 then n := 65_535;
    if p + n >= slen then put(ord(final), 1) else put(0, 1);  // BFINAL on the last block
    put(0, 2); flush;                                // BTYPE = 00, align to byte
    ob1(n and $FF); ob1((n shr 8) and $FF);
    ob1((not n) and $FF); ob1(((not n) shr 8) and $FF);
    obn(sp + p, n);                                  // the block is byte-aligned, copy it in one go
    inc(p, n);
  end;
end;

// compress sp/slen as one DEFLATE block (smallest of stored/fixed/dynamic)
procedure compressBlock(final: boolean);
begin
  if zlevel = 0 then begin emitStored(final); exit; end;   // level 0: no compression at all

  FillChar(FIXL[0], 144, 8); FillChar(FIXL[144], 112, 9); FillChar(FIXL[256], 24, 7); FillChar(FIXL[280], 8, 8);
  FillChar(FIXD[0], 30, 5);

  // one LZ pass: records the tokens and their frequencies. the emit pass below
  // replays the tokens, so the match finder runs once per block, not twice
  FillChar(fl, sizeof(fl), 0); FillChar(fd, sizeof(fd), 0);
  toks := GetMem((slen + 1) * sizeof(dword));   // at most one token per input byte
  try
    lz;
    inc(fl[256]);
    if abort then exit;

    // dynamic lit/len + distance Huffman from the frequencies
    mkhuff(@fl[0], 286, 15, @llen[0]);
    mkhuff(@fd[0], 30, 15, @dlen[0]);
    lcount := 286; while (lcount > 257) and (llen[lcount-1] = 0) do dec(lcount);
    dcount := 30;  while (dcount > 1) and (dlen[dcount-1] = 0) do dec(dcount);

    // code-length alphabet for the dynamic header
    hdrRLE;
    mkhuff(@cf[0], 19, 7, @cllen[0]);
    numCL := 19; while (numCL > 4) and (cllen[CO[numCL-1]] = 0) do dec(numCL);

    // canonical codes for all three alphabets
    mkcodes(@llen[0], 286, @lcode[0]);
    mkcodes(@dlen[0], 30, @dcode[0]);
    mkcodes(@cllen[0], 19, @clcode[0]);

    // candidate sizes: dynamic vs fixed (one block) vs stored (chunked, byte-aligned)
    var hbits: int64 := 5 + 5 + 4 + 3 * numCL;
    for var i := 0 to rlen-1 do hbits := hbits + cllen[clsym[i]] + clxb[i];
    var dynBits := 3 + hbits + tokbits(@llen[0], @dlen[0]);
    var fixBits := 3 + tokbits(@FIXL[0], @FIXD[0]);
    var nb := (slen + 65_534) div 65_535;
    var storedBytes: int64 := int64(nb) * 5 + slen;

    var nonStored := dynBits; var dyn := true;
    if fixBits < dynBits then begin nonStored := fixBits; dyn := false; end;

    if storedBytes < (nonStored + 7) div 8 then
      emitStored(final)
    else begin
      put(ord(final), 1);                            // BFINAL
      if dyn then begin
        put(2, 2);                                   // BTYPE = 10 (dynamic)
        put(lcount - 257, 5); put(dcount - 1, 5); put(numCL - 4, 4);
        for var i := 0 to numCL-1 do put(cllen[CO[i]], 3);
        for var i := 0 to rlen-1 do begin
          put(clcode[clsym[i]], cllen[clsym[i]]);
          if clxb[i] > 0 then put(clext[i], clxb[i]);
        end;
      end else begin
        put(1, 2);                                   // BTYPE = 01 (fixed)
        Move(FIXL[0], llen[0], 288); Move(FIXD[0], dlen[0], 30);
        mkcodes(@llen[0], 288, @lcode[0]); mkcodes(@dlen[0], 30, @dcode[0]);
      end;
      emitTokens;                                    // replay pass 1's tokens
      put(lcode[256], llen[256]);                    // end of block
    end;
  finally
    FreeMem(toks); toks := nil;
  end;
end;

// container header (fmt: ZFLATE_RAW / ZFLATE_ZLIB / ZFLATE_GZIP); the level is
// advertised in the header, as zlib FLEVEL and gzip XFL
procedure packHeader(fmt: longint; level: dword);
begin
  if fmt = ZFLATE_ZLIB then begin
    ob1($78);                                    // CM=8 (deflate), CINFO=7 (32k window)
    // FLG carries FLEVEL and an FCHECK that makes the 2 bytes a multiple of 31
    ob1(match level of
      0, 1: $01;
      2..5: $5e;
      6:    $9c;
      _:    $da;
    end);
  end else if fmt = ZFLATE_GZIP then begin
    ob1($1f); ob1($8b); ob1(8);                  // magic, deflate
    for var i := 0 to 4 do ob1(0);               // no flags, mtime 0
    ob1(match level of                           // XFL
      9: 2;                                      // best compression
      0, 1: 4;                                   // fastest
      _: 0;
    end);
    ob1($ff);                                    // OS unknown
  end;
end;

// container footer from checksums of the source data
procedure packFooter(fmt: longint; crc, adler, isize: dword);
begin
  if fmt = ZFLATE_ZLIB then begin
    // adler32, big-endian
    ob1(adler shr 24); ob1((adler shr 16) and $ff); ob1((adler shr 8) and $ff); ob1(adler and $ff);
  end else if fmt = ZFLATE_GZIP then begin
    // crc32 then size, little-endian
    ob1(crc and $ff); ob1((crc shr 8) and $ff); ob1((crc shr 16) and $ff); ob1(crc shr 24);
    ob1(isize and $ff); ob1((isize shr 8) and $ff); ob1((isize shr 16) and $ff); ob1(isize shr 24);
  end;
end;

// fmt: ZFLATE_RAW / ZFLATE_ZLIB / ZFLATE_GZIP. header + deflate stream + checksum footer
function pack(fmt: longint; data: pointer; len: dword; out outbuf: pointer; out outlen: dword; level: dword): integer;
begin
  outbuf := nil; outlen := 0; abort := false;
  if ((data = nil) and (len <> 0)) or (len > $7FFFFFFF) then exit(ZFLATE_EDEFLATE);
  setLevel(level);
  buf := nil; cap := 0; op := 0; bb := 0; bc := 0;
  progbase := 0; progtotal := len;
  result := ZFLATE_EDEFLATE;
  try
    packHeader(fmt, level);
    if len = 0 then begin put(1, 1); put(1, 2); put(0, 7); end                // empty: final fixed, just EOB
    else
      // one block per chunk, so the token buffer stays bounded on huge inputs
      for var at: dword := 0 to (len - 1) div ZSCHUNK do begin
        progbase := qword(at) * ZSCHUNK;
        sp := pbyte(data) + progbase;
        slen := len - progbase;
        if slen > ZSCHUNK then slen := ZSCHUNK;
        compressBlock(progbase + dword(slen) >= len);
        if abort then break;
      end;
    if abort then result := ZFLATE_EABORTED
    else begin
      flush;
      var c: dword := 0; var a: dword := 1;
      if fmt = ZFLATE_ZLIB then a := adler32(1, data, len)
      else if fmt = ZFLATE_GZIP then c := crc32b(0, data, len);
      packFooter(fmt, c, a, len);
      if zprogress <> nil then zprogress(len, len, op);
      outbuf := buf; outlen := op;
      result := ZFLATE_OK;
    end;
  except
    result := ZFLATE_EDEFLATE;
  end;
  if (result <> ZFLATE_OK) and (buf <> nil) then begin FreeMem(buf); buf := nil; end;
end;

// single-threaded streaming compressor: one chunk = one bit-contiguous block
function zcompress_stream_seq(streamtype: dword; reader: tzreader; writer: tzwriter; totalsize: qword; level: dword): integer;
begin
  abort := false;
  setLevel(level);
  buf := nil; cap := 0; op := 0; bb := 0; bc := 0;
  var cb := zprogress; zprogress := nil;         // the per-block sites see chunk-local numbers, keep them quiet
  var bufA: pbyte := GetMem(ZSCHUNK);
  var bufB: pbyte := GetMem(ZSCHUNK);
  var crc: dword := 0; var adler: dword := 1;
  var total, wrote: qword := 0;
  result := ZFLATE_EDEFLATE;
  try
    packHeader(streamtype, level);
    var cur := reader(bufA, ZSCHUNK);
    if cur = 0 then begin put(1, 1); put(1, 2); put(0, 7); end   // empty input: final fixed, just EOB
    else
      repeat
        var nxt := reader(bufB, ZSCHUNK);                        // look ahead to spot the last chunk
        if streamtype = ZFLATE_ZLIB then adler := adler32(adler, bufA, cur)
        else if streamtype = ZFLATE_GZIP then crc := crc32b(crc, bufA, cur);
        total := total + cur;
        sp := bufA; slen := cur;
        compressBlock(nxt = 0);                                  // back-references never cross chunks
        if op > 0 then begin
          wrote := wrote + op;
          if not writer(buf, op) then begin abort := true; break; end;
          op := 0;
        end;
        if (cb <> nil) and (not cb(total, totalsize, wrote)) then begin abort := true; break; end;
        SwapValues(bufA, bufB);
        cur := nxt;
      until cur = 0;
    if abort then result := ZFLATE_EABORTED
    else begin
      flush;
      packFooter(streamtype, crc, adler, total and $ffffffff);
      wrote := wrote + op;
      if (op > 0) and (not writer(buf, op)) then result := ZFLATE_EABORTED
      else begin
        if cb <> nil then cb(total, totalsize, wrote);
        result := ZFLATE_OK;
      end;
    end;
  except
    result := ZFLATE_EDEFLATE;
  end;
  if buf <> nil then begin FreeMem(buf); buf := nil; end;
  FreeMem(bufA); FreeMem(bufB);
  zprogress := cb;
end;

// compress one chunk into a self-contained, byte-aligned DEFLATE fragment: a
// non-final block followed by an empty stored block that flushes to a byte
// boundary, so fragments from different threads concatenate into a valid stream
procedure compressFragment(src: pbyte; len: dword; level: dword; out frag: TBytes);
begin
  setLevel(level);                               // runs on the worker thread, sets its own state
  buf := nil; cap := 0; op := 0; bb := 0; bc := 0;
  sp := src; slen := len;
  compressBlock(false);
  put(0, 1); put(0, 2); flush;                   // empty non-final stored block: BFINAL=0 BTYPE=00, align
  ob1(0); ob1(0); ob1($ff); ob1($ff);            // LEN=0, NLEN=FFFF
  frag := nil;
  setlength(frag, op);
  if op > 0 then Move(buf^, frag[0], op);
  FreeMem(buf); buf := nil; cap := 0;
end;

// multi-threaded streaming compressor: reads batches of nt chunks, compresses
// them across nt workers, writes the fragments back in order
function zcompress_stream_par(streamtype: dword; reader: tzreader; writer: tzwriter; totalsize: qword; level: dword; nt: longint): integer;
begin
  abort := false;
  setLevel(level);                               // for the header/footer written on this thread
  var cb := zprogress; zprogress := nil;
  var inbuf: array of pbyte := nil; setlength(inbuf, nt);
  for var i := 0 to nt-1 do inbuf[i] := GetMem(ZSCHUNK);
  var inlen: array of dword := nil; setlength(inlen, nt);
  var frags: array of TBytes := nil; setlength(frags, nt);
  var crc: dword := 0; var adler: dword := 1;
  var total, wrote: qword := 0;
  buf := nil; cap := 0; op := 0; bb := 0; bc := 0;
  result := ZFLATE_EDEFLATE;
  try
    packHeader(streamtype, level);
    if op > 0 then begin
      wrote := wrote + op;
      if not writer(buf, op) then abort := true;
      op := 0;
    end;
    var eof := false;
    while (not eof) and (not abort) do begin
      // fill up to nt chunks for this batch
      var cnt := 0;
      while cnt < nt do begin
        var got := reader(inbuf[cnt], ZSCHUNK);
        if got = 0 then begin eof := true; break; end;
        inlen[cnt] := got; inc(cnt);
      end;
      if cnt = 0 then break;
      // compress the batch: each worker owns its threadvar encoder state
      for parallel(nt) var s := 0 to cnt-1 do
        compressFragment(inbuf[s], inlen[s], level, frags[s]);
      // write fragments in order, updating checksums and progress on this thread
      for var s := 0 to cnt-1 do begin
        if streamtype = ZFLATE_ZLIB then adler := adler32(adler, inbuf[s], inlen[s])
        else if streamtype = ZFLATE_GZIP then crc := crc32b(crc, inbuf[s], inlen[s]);
        total := total + inlen[s];
        wrote := wrote + length(frags[s]);
        if (length(frags[s]) > 0) and (not writer(pointer(frags[s]), length(frags[s]))) then begin abort := true; break; end;
        frags[s] := nil;
        if (cb <> nil) and (not cb(total, totalsize, wrote)) then begin abort := true; break; end;
      end;
    end;
    if abort then result := ZFLATE_EABORTED
    else begin
      // final empty block (BFINAL=1) plus the footer; reuse this thread's buffer
      op := 0; bb := 0; bc := 0;
      put(1, 1); put(1, 2); put(0, 7); flush;
      packFooter(streamtype, crc, adler, total and $ffffffff);
      wrote := wrote + op;
      if (op > 0) and (not writer(buf, op)) then result := ZFLATE_EABORTED
      else begin
        if cb <> nil then cb(total, totalsize, wrote);
        result := ZFLATE_OK;
      end;
    end;
  except
    result := ZFLATE_EDEFLATE;
  end;
  if buf <> nil then begin FreeMem(buf); buf := nil; end;
  for var i := 0 to nt-1 do FreeMem(inbuf[i]);
  zprogress := cb;
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

// decoder state (per-thread). er: hard error
threadvar
  rp: PByte;
  si, sl, rbb, rbc, rop, rcap, er: longint;
  ob: pointer;
  lc, dc: array[16] of word;
  ls: array[288] of word;
  ds: array[32] of word;
  lens: array[320] of byte;
  // decoder streaming state (zdecompress_stream); zsreader/zswriter nil = one-shot
  zsreader: tzreader;
  zswriter: tzwriter;
  zscb: tzprogress;     // progress hook while streaming (zprogress is detached then)
  zsfmt: dword;         // detected container, picks which checksum to maintain
  zstotal: qword;       // total input size for progress (0 = unknown)
  zsin, zsout: qword;   // input consumed / output flushed
  zscrc, zsadler: dword;// running checksums of the flushed output

// refill the streaming input buffer; false when the source is dry
function refill: boolean;
begin
  result := false;
  if zsreader = nil then exit;
  sl := zsreader(rp, ZSINBUF);
  si := 0;
  if sl = 0 then exit;
  zsin := zsin + sl;
  if (zscb <> nil) and (not zscb(zsin, zstotal, zsout)) then begin abort := true; exit; end;
  result := true;
end;

// one input byte; refills in streaming mode, flags an error when input runs dry
function nb: longint;
begin
  if si >= sl then
    if not refill then begin er := 1; exit(0); end;
  result := rp[si]; inc(si);
end;

// one bit, LSB-first
function gb: longint;
begin
  if rbc = 0 then begin
    rbb := nb;
    if er <> 0 then exit(0);
    rbc := 8;
  end;
  result := rbb and 1; rbb := rbb shr 1; dec(rbc);
end;

// n bits
function gn(n: longint): longint;
begin
  result := 0;
  for var i := 0 to n-1 do result := result or (gb shl i);
end;

// canonical Huffman decode; dist picks the distance table, else lit/len
function hd(dist: boolean): longint;
begin
  var cp: PWord := @lc[0]; var yp: PWord := @ls[0];
  if dist then begin cp := @dc[0]; yp := @ds[0]; end;
  var code := 0; var first := 0; var idx := 0;
  for var k := 1 to 15 do begin
    code := code or gb;
    var c := cp[k];
    if code - c < first then exit(yp[idx + code - first]);
    idx := idx + c; first := (first + c) shl 1; code := code shl 1;
  end;
  er := 1;                                        // 15 bits, no valid code
  result := 0;
end;

// build count[]/symbol[] for the lit or dist table from lens[off..off+n-1]
procedure mk(dist: boolean; off, n: longint);
begin
  var cp: PWord := @lc[0]; var yp: PWord := @ls[0];
  if dist then begin cp := @dc[0]; yp := @ds[0]; end;
  var ofs: array[17] of word;
  for var i := 0 to 15 do cp[i] := 0;
  for var i := 0 to n-1 do inc(cp[lens[off+i]]);
  ofs[1] := 0;
  for var i := 1 to 15 do ofs[i+1] := ofs[i] + cp[i];
  for var i := 0 to n-1 do
    if lens[off+i] <> 0 then begin yp[ofs[lens[off+i]]] := i; inc(ofs[lens[off+i]]); end;
end;

// flush decoder output to the sink, keeping the back-reference window unless last
procedure oflush(last: boolean);
begin
  var n := rop;
  if not last then n := rop - WS;
  if n <= 0 then exit;
  if zsfmt = ZFLATE_GZIP then zscrc := crc32b(zscrc, ob, n)
  else if zsfmt = ZFLATE_ZLIB then zsadler := adler32(zsadler, ob, n);
  zsout := zsout + n;
  if not zswriter(ob, n) then begin abort := true; er := 1; exit; end;
  if not last then Move(PByte(ob)[n], ob^, rop - n);
  rop := rop - n;
end;

// append one output byte, doubling the heap buffer as needed
procedure em(b: longint);
begin
  if (zswriter <> nil) and (rop >= ZSOUTMAX) then oflush(false);
  if rop >= rcap then begin if rcap = 0 then rcap := 256 else rcap := rcap * 2; ReAllocMem(ob, rcap); end;
  PByte(ob)[rop] := b; inc(rop);
end;

// decode DEFLATE blocks until the final one, over the shared decoder state
procedure inflateLoop;
begin
  var nx := 0;
  var final := 0;
  repeat
    final := gb;
    var bt := gn(2);
    if bt = 3 then er := 1;                     // reserved block type
    if er <> 0 then break;
    if bt = 0 then begin
      if (zprogress <> nil) and (not zprogress(si, sl, rop)) then begin abort := true; er := 1; break; end;
      rbc := 0;                                 // align to byte boundary
      var lo := nb; var hi := nb;
      var n := lo or (hi shl 8);                // LEN then one's-complement check
      lo := nb; hi := nb;
      if (er <> 0) or ((n xor (lo or (hi shl 8))) <> $FFFF) then begin er := 1; break; end;
      for var k := 0 to n-1 do begin
        em(nb);
        if er <> 0 then break;
      end;
      if er <> 0 then break;
    end else begin
      if bt = 1 then begin
        FillChar(lens[0], 144, 8); FillChar(lens[144], 112, 9); FillChar(lens[256], 24, 7); FillChar(lens[280], 8, 8);
        mk(false, 0, 288);
        FillChar(lens[0], 30, 5);
        mk(true, 0, 30);
      end else begin
        // dynamic header: build the code-length table, then the lit+dist lengths
        var hlit := gn(5) + 257;
        var hdist := gn(5) + 1;
        var hclen := gn(4) + 4;
        if (hlit > 286) or (hdist > 30) then begin er := 1; break; end;
        FillChar(lens[0], 19, 0);
        for var i := 0 to hclen-1 do lens[CO[i]] := gn(3);
        if er <> 0 then break;
        mk(false, 0, 19);
        var i := 0;
        while (i < hlit + hdist) and (er = 0) do begin
          var s := hd(false);
          if er <> 0 then break;
          if s < 16 then begin lens[i] := s; inc(i); end
          else begin
            var r := 0; var v := 0;
            if s = 16 then begin
              if i = 0 then begin er := 1; break; end;
              r := gn(2)+3; v := lens[i-1];
            end else if s = 17 then r := gn(3)+3
            else r := gn(7)+11;
            if i + r > hlit + hdist then begin er := 1; break; end;
            FillChar(lens[i], r, v); inc(i, r);
          end;
        end;
        if er <> 0 then break;
        mk(true, hlit, hdist);
        mk(false, 0, hlit);
      end;
      // symbol loop: literals and (length, distance) matches until end-of-block
      repeat
        if (zprogress <> nil) and (rop >= nx) then begin
          nx := rop + 65_536;
          if not zprogress(si, sl, rop) then begin abort := true; er := 1; break; end;
        end;
        var s := hd(false);
        if er <> 0 then break;
        if s < 256 then em(s)
        else if s = 256 then break
        else begin
          s := s - 257;
          if s > 28 then begin er := 1; break; end;
          var ln := LB[s] + gn(LE[s]);
          var d := hd(true);
          if er <> 0 then break;
          var dist := DB[d] + gn(DE[d]);
          if (er <> 0) or (dist > rop) then begin er := 1; break; end;  // before stream start
          while ln > 0 do begin em(PByte(ob)[rop - dist]); dec(ln); end;
        end;
      until false;
    end;
  until (final <> 0) or (er <> 0);
end;

// decompress a raw DEFLATE stream; handles every block type (stored, fixed, dynamic)
function unpackRaw(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
begin
  output := nil; outputsize := 0; abort := false;
  if (data = nil) or (size = 0) then exit(ZFLATE_EINFLATE);
  rp := data; sl := size;
  si := 0; rbb := 0; rbc := 0; er := 0;
  ob := nil; rcap := 0; rop := 0;
  try
    inflateLoop;
  except
    er := 1;
  end;
  if er <> 0 then begin
    if ob <> nil then begin FreeMem(ob); ob := nil; end;
    if abort then exit(ZFLATE_EABORTED);
    exit(ZFLATE_EINFLATE);
  end;
  if zprogress <> nil then zprogress(sl, sl, rop);
  output := ob; outputsize := rop;
  result := ZFLATE_OK;
end;

// consume the container header sequentially (streaming)
procedure skipHeader;
begin
  if zsfmt = ZFLATE_ZLIB then begin nb; nb; end
  else if zsfmt = ZFLATE_GZIP then begin
    nb; nb; nb;
    var flags := nb;
    for var i := 1 to 6 do nb;                                // mtime, xfl, os
    // extra field
    if (flags and $04) <> 0 then begin
      var lo := nb; var hi := nb;
      for var i := 1 to lo or (hi shl 8) do begin
        nb;
        if er <> 0 then exit;
      end;
    end;
    if (flags and $08) <> 0 then while (nb <> 0) and (er = 0) do ;   // filename
    if (flags and $10) <> 0 then while (nb <> 0) and (er = 0) do ;   // comment
    if (flags and $02) <> 0 then begin nb; nb; end;                  // header crc16
  end;
end;

// read and verify the container footer against the running checksums (streaming)
function checkFooter: integer;
begin
  result := ZFLATE_OK;
  rbc := 0;                                       // footer starts at the next byte
  if zsfmt = ZFLATE_ZLIB then begin
    // adler32, big-endian
    var a: dword := 0;
    for var i := 1 to 4 do a := (a shl 8) or dword(nb);
    if er <> 0 then exit(ZFLATE_EINFLATE);
    if a <> zsadler then result := ZFLATE_ECHECKSUM;
  end else if zsfmt = ZFLATE_GZIP then begin
    // crc32 then size, little-endian
    var c: dword := 0;
    for var i := 0 to 3 do c := c or (dword(nb) shl (8*i));
    var isize: dword := 0;
    for var i := 0 to 3 do isize := isize or (dword(nb) shl (8*i));
    if er <> 0 then exit(ZFLATE_EINFLATE);
    if isize <> dword(zsout) then exit(ZFLATE_EOUTPUTSIZE);
    if c <> zscrc then result := ZFLATE_ECHECKSUM;
  end;
end;

function zdecompress_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0): integer;
begin
  if (reader = nil) or (writer = nil) then exit(ZFLATE_EINFLATE);
  abort := false;
  zsreader := reader; zswriter := writer;
  zscb := zprogress; zprogress := nil;            // the one-shot progress sites see buffer-local numbers
  zstotal := totalsize; zsin := 0; zsout := 0; zscrc := 0; zsadler := 1; zsfmt := ZFLATE_RAW;
  var inbuf: pbyte := GetMem(ZSINBUF);
  rp := inbuf; si := 0; sl := 0; rbb := 0; rbc := 0; er := 0;
  ob := nil; rcap := 0; rop := 0;
  result := ZFLATE_EINFLATE;
  try
    // buffer enough bytes to sniff the container type
    while sl < 3 do begin
      var got := reader(rp + sl, ZSINBUF - sl);
      if got = 0 then break;
      inc(sl, got);
    end;
    zsin := sl;
    if (sl >= 3) and (rp[0] = $1f) and (rp[1] = $8b) and (rp[2] = 8) then zsfmt := ZFLATE_GZIP
    else if (sl >= 2) and ((rp[0] and $0f) = 8) and ((rp[0] shr 4) <= 7) and ((rp[1] and $20) = 0) and ((rp[0]*256 + rp[1]) mod 31 = 0) then zsfmt := ZFLATE_ZLIB;
    skipHeader;
    if er = 0 then inflateLoop;
    if er = 0 then oflush(true);
    if er = 0 then result := checkFooter;
  except
    er := 1; result := ZFLATE_EINFLATE;
  end;
  if abort then result := ZFLATE_EABORTED;
  if (result = ZFLATE_OK) and (zscb <> nil) then zscb(zsin, zstotal, zsout);
  if ob <> nil then begin FreeMem(ob); ob := nil; end;
  FreeMem(inbuf);
  zsreader := nil; zswriter := nil; zsfmt := ZFLATE_RAW;
  zprogress := zscb; zscb := nil;
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

end.
