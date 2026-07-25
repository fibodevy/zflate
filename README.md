# zflate

Compress and decompress buffers, strings and files like in PHP, in one line. The whole DEFLATE codec lives inside the unit: no zlib, no external libraries, nothing but the RTL (`uses` is empty on Windows, `cthreads` on unix for the threaded path). Adding [zflate.pas](src/zflate.pas) to a program grows the binary by about 26 kB when you only call the one-shot functions, 45 kB with the streaming and threaded paths linked in as well - half of what the same program costs when it goes through FPC's paszlib instead, which it also outruns (see [against paszlib](#against-paszlib)).

> **Requires a compiler that understands `{$mode unleashed}`.** The units and the examples below lean on inline variables, tuples, match expressions, function references and parallel for, so a stock compiler will not build them.

- function names taken from PHP: `gzdeflate`/`gzinflate`, `gzcompress`/`gzuncompress`, `gzencode`/`gzdecode`
- three formats: raw DEFLATE (RFC 1951), ZLIB (RFC 1950), GZIP (RFC 1952)
- compression levels 0 to 9, like zlib
- every function returns an integer code: `ZFLATE_OK` (0) on success, `ZFLATE_E*` otherwise; no exception ever escapes
- decompression verifies headers and checksums (adler32 for ZLIB, crc32 + size for GZIP)
- auto-detection of the stream type with a fallback to raw DEFLATE
- streaming API with constant memory use, for files of any size
- optional progress callback with abort, for progressbars
- multithreaded compression across cores via `zuse_threads`
- output interoperates with zlib, .NET `GZipStream`/`DeflateStream`, PHP `gzencode`/`gzdeflate` and everything else that speaks DEFLATE

## Quick start

The functions are named after their PHP counterparts and behave the same way:

```pascal
uses zflate;

var zipped := gzencode('some string');   // GZIP, like PHP's gzencode()
var back := gzdecode(zipped);
```

Do not know (or care) what the stream is? `zdecompress()` detects GZIP and ZLIB by their headers and falls back to raw DEFLATE:

```pascal
var back := zdecompress(zipped);
```

## Functions

Each format has a compress and a decompress side, each with three overloads: raw buffer, `string`, `TBytes`. The pointer overloads return the error code directly and hand out a heap buffer (free it with `FreeMem`). The `string`/`TBytes` overloads return the data ('' / `nil` on error) and store the code in `zlasterror`.

```pascal
// RAW DEFLATE
function gzdeflate(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
function gzdeflate(const str: string; level: dword = ZFLATE_DEFAULT): string;
function gzdeflate(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
function gzinflate(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function gzinflate(const str: string): string;
function gzinflate(const bytes: TBytes): TBytes;

// ZLIB
function gzcompress(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
function gzcompress(const str: string; level: dword = ZFLATE_DEFAULT): string;
function gzcompress(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
function gzuncompress(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function gzuncompress(const str: string): string;
function gzuncompress(const bytes: TBytes): TBytes;

// GZIP
function gzencode(data: pointer; size: dword; out output: pointer; out outputsize: dword; level: dword = ZFLATE_DEFAULT): integer;
function gzencode(const str: string; level: dword = ZFLATE_DEFAULT): string;
function gzencode(const bytes: TBytes; level: dword = ZFLATE_DEFAULT): TBytes;
function gzdecode(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function gzdecode(const str: string): string;
function gzdecode(const bytes: TBytes): TBytes;

// detect the stream type and decompress accordingly
function zdecompress(data: pointer; size: dword; out output: pointer; out outputsize: dword): integer;
function zdecompress(const str: string): string;
function zdecompress(const bytes: TBytes): TBytes;
```

## Compression levels

Every compressing function takes a `level` from 0 to 9, defaulting to 4. Level 0 stores without compressing, 1 is the fastest, 9 squeezes hardest; the level drives the hash-chain search depth, the match length that ends a search early, the length past which an existing match cuts the search short, the length at which a match is good enough to stop working on, and whether lazy matching runs. The level is also advertised in the container header (zlib `FLEVEL`, gzip `XFL`), exactly like zlib does.

```pascal
var plain := gzencode(data);                  // 4, the default
var fast := gzencode(data, ZFLATE_FASTEST);   // 1
var small := gzencode(data, ZFLATE_BEST);     // 9
var stored := gzencode(data, ZFLATE_STORE);   // 0, no compression
```

Named constants: `ZFLATE_STORE` (0), `ZFLATE_FASTEST` (1), `ZFLATE_DEFAULT` (4), `ZFLATE_BEST` (9). Compressing 4 MB of text-like data lands like this ([examples/basic.pp](examples/basic.pp) prints the same table for its own payload):

| level | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|--|--|--|--|--|--|--|--|--|--|--|
| KB out | 4096 | 730 | 646 | 602 | 571 | 550 | 545 | 525 | 519 | 518 |

The five knobs behind each level were not copied from zlib, they were measured: every combination was run over text, source code, log records and half-random data, and the ten levels are points off the resulting speed/size Pareto front, spaced about 1.35x in time per step. Output therefore shrinks with every level on all four, with no level costing more time than the one below it for a worse result.

## Streaming

The functions above are one-shot: the whole input and output live in memory. For data too big for that there is a streaming pair; input is pulled from a reader callback, output is pushed to a writer callback, and memory use stays constant no matter the stream size:

```pascal
type
  // fill buf with up to maxlen bytes, return the byte count, 0 = end of input
  tzreader = reference to function(buf: pointer; maxlen: dword): dword;
  // receive a produced block, return false to abort
  tzwriter = reference to function(data: pointer; size: dword): boolean;

// reader -> DEFLATE / ZLIB / GZIP -> writer; totalsize is only for progress reporting
function gzdeflate_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
function gzcompress_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
function gzencode_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0; level: dword = ZFLATE_DEFAULT): integer;
// detect the container, decompress, verify checksums: reader -> inflate -> writer
function zdecompress_stream(reader: tzreader; writer: tzwriter; totalsize: qword = 0): integer;
```

Gzipping one file into another, without either ever being held in memory - the reader and the writer are the only glue you write:

```pascal
uses zflate;

var fin, fout: file;

function reader(buf: pointer; maxlen: dword): dword;
begin
  blockread(fin, buf^, maxlen, result);    // 0 bytes = end of input
end;

function writer(data: pointer; datasize: dword): boolean;
begin
  blockwrite(fout, data^, datasize);
  result := true;                          // false aborts with ZFLATE_EABORTED
end;

begin
  assign(fin, 'huge.bin'); reset(fin, 1);
  assign(fout, 'huge.bin.gz'); rewrite(fout, 1);

  zprogress := function(position, totalsize, outputsize: qword): boolean
  begin
    write(#13, position * 100 div totalsize, '%');
    result := true;
  end;

  if gzencode_stream(@reader, @writer, filesize(fin), ZFLATE_BEST) <> ZFLATE_OK then
    writeln('failed: ', zflate_error_str(zlasterror));

  zprogress := nil;
  close(fin); close(fout);
end.
```

Decompressing is the same shape with `zdecompress_stream(@reader, @writer)`, which sniffs the container itself. See [examples/streaming.pp](examples/streaming.pp) for the complete program.

The compressor takes the input in 1 MB chunks, each becomes its own DEFLATE block, so back-references never cross a chunk boundary (the ratio difference is negligible). The decompressor keeps just the 32 KiB back-reference window plus small buffers. Anything that speaks DEFLATE decodes the streamed output and vice versa.

## Multithreading

Codec state belongs to the call, not to the unit, so different threads can compress and decompress independently with no locking. On top of that, every compressing function can split the work across worker threads. Set the `zuse_threads` threadvar before the call:

```pascal
zuse_threads := 4;                    // 0 or 1 = sequential (default), N = N workers
var packed := gzencode(hugeString);   // one-shot, streaming and file APIs all honour it
```

Each 1 MB chunk is compressed on its own thread into an independent, byte-aligned block; the chunks are emitted in order, so the output is an ordinary gzip/zlib/deflate stream that any decoder reads. Inputs of a chunk or less never spawn anything, so leaving `zuse_threads` high costs nothing on small strings.

Measured on a 16-core desktop, 96 MB of text at level 9, compiled with `-O3` ([examples/threads.pp](examples/threads.pp) reproduces it):

| threads | time | speed | speedup | ratio |
|--|--|--|--|--|
| 1 | 6.9 s | 14.0 MB/s | 1.0x | 12.65% |
| 2 | 3.8 s | 25.6 MB/s | 1.8x | 12.66% |
| 4 | 2.1 s | 46.2 MB/s | 3.3x | 12.66% |
| 8 | 1.3 s | 74.9 MB/s | 5.4x | 12.66% |

The ratio column is what threading costs you: 461 bytes on 96 MB, or 0.0005%, for the markers that let the blocks be written independently.

The one-shot functions scale the same way, and a few percent better since they compress straight out of the caller's buffer with no copying. Level 0 is the exception - there is nothing to compress, so the threads only add batching overhead; leave `zuse_threads` at 1 for it.

Decompression is inherently sequential (a generic DEFLATE stream has no block index) and always runs on one thread. On unix the parallel path needs threading support; `zflate` pulls in `cthreads` automatically under `{$ifdef unix}`.

## Performance

Single core, gzip, the same 96 MB payload and `-O3` build as the table above:

| level | 0 | 1 | 2 | 3 | 4 (default) | 5 | 6 | 7 | 8 | 9 |
|--|--|--|--|--|--|--|--|--|--|--|
| compress | 384 MB/s | 158 MB/s | 131 MB/s | 102 MB/s | 73 MB/s | 49 MB/s | 36 MB/s | 24 MB/s | 18 MB/s | 14 MB/s |
| decompress | 342 MB/s | 219 MB/s | 228 MB/s | 237 MB/s | 237 MB/s | 246 MB/s | 246 MB/s | 256 MB/s | 246 MB/s | 246 MB/s |
| ratio | 100% | 17.8% | 15.8% | 14.7% | 14.0% | 13.4% | 13.3% | 12.8% | 12.7% | 12.7% |

That is the shape of the level knob: going from 1 to 9 costs 11x the time and buys 29% off the output. The default sits at 4, one step past the halfway point of the ratio the ladder can reach and still above 70 MB/s. Decompression barely cares about the level the data was written at; level 0 stores, so both sides are just a memory copy.

Compiler flags matter more than you would expect here: the same code without optimizations does about 40% less throughput on both sides. `-O2` and `-O3` land in the same place, so `-O2` is enough.

Where the speed comes from, in case you are porting or tuning this:

- codec state lives in a record owned by the call rather than in unit or thread variables, so the hot loops reach it through a register instead of paying a TLS lookup per access
- the decoder pulls bits out of a 64-bit accumulator refilled eight bytes at a time
- huffman codes of up to 9 bits resolve in one table lookup, longer ones fall back to the canonical walk
- back-references are copied eight bytes at a time whenever the distance allows it, and the bit writer empties four bytes at a time
- the match finder runs once per block, not twice: the LZ pass records its tokens and the emit pass replays them
- candidate matches are compared 8 bytes at a time, taking the first differing byte from the low set bit of the xor
- length and distance code indexes come from lookup tables rather than a scan over the RFC base tables
- crc32 is table-driven; the bitwise form was slower than the compressor it fed
- the level knobs (chain length, nice length, good length, lazy length, lazy matching) sit on a measured Pareto front rather than on a table borrowed from elsewhere

## Against paszlib

zflate started out as a wrapper over the zlib port that ships with FPC (`ZBase`, `ZInflate`, `ZDeflate`). The codec in this unit replaced it. Both versions linked into one program so the comparison runs on the same machine, the same build and the same payload: 32 MB of generated text, gzip, single thread.

| level | zflate | paszlib | zflate ratio | paszlib ratio | zflate decompress | paszlib decompress |
|--|--|--|--|--|--|--|
| 0 | 363 MB/s | 35 MB/s | 100.0% | 100.0% | 392 MB/s | 42 MB/s |
| 1 | 157 MB/s | 104 MB/s | 17.82% | 17.93% | 211 MB/s | 113 MB/s |
| 2 | 124 MB/s | 106 MB/s | 15.77% | 17.07% | 224 MB/s | 126 MB/s |
| 3 | 101 MB/s | 86 MB/s | 14.70% | 15.13% | 234 MB/s | 141 MB/s |
| 4 | 75 MB/s | 77 MB/s | 13.95% | 15.37% | 238 MB/s | 132 MB/s |
| 5 | 48 MB/s | 66 MB/s | 13.43% | 13.94% | 242 MB/s | 141 MB/s |
| 6 | 35 MB/s | 38 MB/s | 13.30% | 12.96% | 243 MB/s | 148 MB/s |
| 7 | 23 MB/s | 24 MB/s | 12.81% | 12.52% | 246 MB/s | 150 MB/s |
| 8 | 18 MB/s | 15 MB/s | 12.66% | 12.36% | 249 MB/s | 148 MB/s |
| 9 | 14 MB/s | 14 MB/s | 12.65% | 12.36% | 246 MB/s | 151 MB/s |

Decompression is 1.7x to 2.1x faster at every level, and the gap does not depend on the level the data was written at. Level 0 is 10x: paszlib still walks its whole deflate state machine to emit stored blocks, this one recognises there is nothing to do and copies. The bottom half of the ladder wins on both axes at once - level 2 to 4 produce output 5% to 9% smaller at comparable speed, because the levels here were measured rather than inherited.

From level 6 up paszlib still edges ahead on ratio, by 2.3% to 2.6% on this payload. That is the one place it is genuinely better: its match finder handles long matches more carefully than the plain 3-byte hash chain here does.

The same sweep over 32 MB of Pascal and markdown sources tells the same story with a wider low end (level 1 is 1.8x faster, levels 2 and 3 produce 8% smaller output) and almost no high end left: from level 6 up paszlib is ahead by 0.13% to 0.27%.

Every stream in both sweeps was decoded by both implementations, at every level, in both directions.

Linked binary, minimal program calling `gzencode` and `gzdecode`, `-O3 -XX -CX -Xs`:

| build | binary | added |
|--|--|--|
| baseline, no codec | 52 224 B | - |
| zflate | 78 848 B | **26 624 B** |
| paszlib-backed | 102 912 B | **50 688 B** |

Half the code, no dependencies, and streaming, threading and progress callbacks that the wrapper never had.

## Stream inspection

```pascal
// read and validate a zlib header
function read_zlib_header(data: pointer; size: dword; out info: tzlibinfo): boolean;
// read and validate a gzip header; filename/comment point into data when present
function read_gzip_header(data: pointer; size: dword; out info: tgzipinfo): boolean;
// detect the stream type: ZFLATE_GZIP, ZFLATE_ZLIB, or ZFLATE_RAW as fallback
function stream_info(data: pointer; size: dword): (streamtype, streamat, footerlen: dword);
```

`stream_info` returns a tuple, so destructuring reads nicely:

```pascal
var (kind, at, footer) := stream_info(pointer(zipped), length(zipped));
if kind = ZFLATE_GZIP then writeln('gzip, deflate stream starts at byte ', at);
```

## Progress callback

Set `zprogress` and every compress/decompress call reports its position; return `false` to abort the operation with `ZFLATE_EABORTED`:

```pascal
zprogress := function(position, totalsize, outputsize: qword): boolean
begin
  write(#13'progress: ', position * 100 div totalsize, '%');
  result := true; // false aborts
end;
```

## Error codes

| code | meaning |
|--|--|
| `ZFLATE_OK` | success (0) |
| `ZFLATE_EDEFLATE` | compression failed (bad arguments or out of memory) |
| `ZFLATE_EINFLATE` | decompression failed (malformed or truncated stream) |
| `ZFLATE_EZLIBINVALID` | invalid zlib header |
| `ZFLATE_EGZIPINVALID` | invalid gzip header |
| `ZFLATE_ECHECKSUM` | checksum mismatch |
| `ZFLATE_EOUTPUTSIZE` | output size doesnt match the gzip footer |
| `ZFLATE_EABORTED` | aborted by the progress callback |
| `ZFLATE_ENODATA` | no input loaded (zflatefiles) |
| `ZFLATE_EFILEREAD` | cannot read file (zflatefiles) |
| `ZFLATE_EFILEWRITE` | cannot write file (zflatefiles) |

`zflate_error_str(code)` translates a code to a message.

## Checksums

Both checksums the containers need are exported, and run at roughly 510 MB/s and 440 MB/s:

```pascal
function crc32b(crc: dword; data: pbyte; len: dword): dword;    // start with crc = 0
function adler32(adler: dword; data: pbyte; len: dword): dword; // start with adler = 1
```

## zflatefiles

[zflatefiles.pas](src/zflatefiles.pas) adds file compression on top of zflate. Files go through the streaming API chunk by chunk, so a multi-gigabyte file compresses in a few megabytes of memory. File access goes straight to WinAPI on Windows and libc elsewhere; its only dependency is the zflate unit.

```pascal
type
  TZFlateFile = class
    // open a file as the input; only a handle is kept, the content is streamed
    function openFile(const path: string): boolean;
    // release the input (file handle or memory copy)
    procedure closeFile;
    // load input from memory (a private copy is made)
    procedure loadFromMemory(data: pointer; datasize: dword);
    procedure loadFromMemory(const str: string);
    procedure loadFromMemory(const bytes: TBytes);
    // detected stream type of the input
    function streamType: dword;
    // compress/decompress the input to memory; nil on error (see error)
    function compress(streamtype: dword = ZFLATE_GZIP; level: dword = ZFLATE_DEFAULT): TBytes;
    function decompress: TBytes;
    // compress/decompress the input to a file, chunk by chunk; the output file is deleted on failure
    function compressToFile(const dst: string; streamtype: dword = ZFLATE_GZIP; level: dword = ZFLATE_DEFAULT): integer;
    function decompressToFile(const dst: string): integer;
    // input size and last error code
    property size: qword;
    property error: integer;
    // progress callback, return false to abort; anonymous functions welcome
    property onProgress: tzprogress;
  end;

// one-shot file helpers, fully streamed
function gzdeflate_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
function gzcompress_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
function gzencode_file(const src, dst: string; level: dword = ZFLATE_DEFAULT; progress: tzprogress = nil): integer;
// detect the container and decompress a file
function zdecompress_file(const src, dst: string; progress: tzprogress = nil): integer;
```

Compress a file to GZIP with a progressbar in a few lines, the callback is a plain anonymous function:

```pascal
uses zflate, zflatefiles;

begin
  var code := gzencode_file('data.bin', 'data.bin.gz', ZFLATE_BEST,
    function(position, totalsize, outputsize: qword): boolean
    begin
      write(#13, position * 100 div totalsize, '%');
      result := true;
    end);
  if code <> ZFLATE_OK then writeln('error: ', zflate_error_str(code));
end.
```

[examples/file_progress.pp](examples/file_progress.pp) builds this out into a real progressbar with throughput, ETA and live compression ratio.

Or through the class:

```pascal
var z := autofree TZFlateFile.Create;
if z.openFile('archive.gz') then begin
  writeln('stream type: ', z.streamType); // ZFLATE_GZIP
  var data := z.decompress;
  if z.error <> ZFLATE_OK then writeln(zflate_error_str(z.error));
end;
```

## Examples

Each file in [examples/](examples) is a self-contained program: `fpc -Fu../src <name>.pp` and run it.

| example | what it shows |
|--|--|
| [basic.pp](examples/basic.pp) | strings, `TBytes` and raw pointers in all three formats, auto-detection, every compression level, error codes |
| [file_progress.pp](examples/file_progress.pp) | compressing a file with a live progressbar, throughput, ETA and ratio |
| [streaming.pp](examples/streaming.pp) | the reader/writer streaming API over plain file handles, at constant memory |
| [threads.pp](examples/threads.pp) | `zuse_threads` scaling across cores, with a roundtrip check |
| [php_interop.pp](examples/php_interop.pp) | decoding the `php_gz*` files written by PHP, and writing files PHP reads back |

`php_gzdeflate`, `php_gzcompress` and `php_gzencode` are reference inputs produced by PHP's own functions, kept as proof the formats interoperate with a foreign implementation.

## Notes

- The buffer/string/TBytes functions are one-shot and keep everything in memory; the `*_stream` functions and zflatefiles process data in chunks with constant memory use.
- Codec state belongs to the call: safe to call from several threads at once, and `zuse_threads` fans the compressors out across cores.
- Compression picks the smallest of stored / fixed / dynamic Huffman per block, with LZ77 over a 32 KiB window; the level tunes the search depth and lazy matching.

## License

MIT. Keep the notice from the top of the sources and the link when you redistribute them.
