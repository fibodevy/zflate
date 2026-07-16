# zflate

Compress and decompress buffers, strings and files like in PHP, in one line. The whole DEFLATE codec lives inside the unit: no zlib, no external libraries, nothing but the RTL (`uses` is empty on Windows, `cthreads` on unix for the threaded path). Adding [zflate.pas](src/zflate.pas) to a program grows the binary by about 35 kB.

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

Every compressing function takes a `level` from 0 to 9, defaulting to 5. Level 0 stores without compressing, 1 is the fastest, 9 squeezes hardest; the level drives the hash-chain search depth, the match length that ends a search early, and whether lazy matching runs. The level is also advertised in the container header (zlib `FLEVEL`, gzip `XFL`), exactly like zlib does.

```pascal
var plain := gzencode(data);                  // 5, the default
var fast := gzencode(data, ZFLATE_FASTEST);   // 1
var small := gzencode(data, ZFLATE_BEST);     // 9
var stored := gzencode(data, ZFLATE_STORE);   // 0, no compression
```

Named constants: `ZFLATE_STORE` (0), `ZFLATE_FASTEST` (1), `ZFLATE_DEFAULT` (5), `ZFLATE_BEST` (9). Compressing 4 MB of text-like data lands like this ([examples/basic.pp](examples/basic.pp) prints the same table for its own payload):

| level | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|--|--|--|--|--|--|--|--|--|--|--|
| KB out | 4096 | 718 | 679 | 600 | 642 | 586 | 543 | 526 | 519 | 519 |

The curve is not strictly monotonic - level 4 is the first lazy-matching level and can land slightly behind level 3's deeper greedy search, and 8 and 9 differ only in how long they keep searching. That is how zlib behaves too; the four knobs per level come from its tuning table.

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

Codec state is per-thread (`threadvar`), so different threads can compress and decompress independently with no locking. On top of that, the streaming compressors can split the work across worker threads. Set the `zuse_threads` threadvar before the call:

```pascal
zuse_threads := 4;                    // 0 or 1 = sequential (default), N = N workers
gzencode_stream(@reader, @writer, totalsize);
```

Each chunk is compressed on its own thread into an independent, byte-aligned block; the chunks are written in order, so the output is an ordinary gzip/zlib/deflate stream that any decoder reads. `zflatefiles` inherits this: set `zuse_threads` before `gzencode_file` or `TZFlateFile.compressToFile` and a large file compresses across all cores.

Measured on a 16-core desktop, 96 MB of text at level 9 ([examples/threads.pp](examples/threads.pp) reproduces it):

| threads | time | speed | speedup |
|--|--|--|--|
| 1 | 5.6 s | 17.3 MB/s | 1.0x |
| 2 | 3.1 s | 31.2 MB/s | 1.8x |
| 4 | 1.8 s | 52.1 MB/s | 3.0x |
| 8 | 1.3 s | 74.9 MB/s | 4.3x |

Decompression is inherently sequential (a generic DEFLATE stream has no block index) and always runs on one thread. On unix the parallel path needs threading support; `zflate` pulls in `cthreads` automatically under `{$ifdef unix}`.

## Performance

Single core, gzip, 32 MB of text-like data on a desktop x64:

| level | 1 | 6 | 9 | decompress |
|--|--|--|--|--|
| speed | 205 MB/s | 93 MB/s | 25 MB/s | 82 MB/s |

Where the speed comes from, in case you are porting or tuning this:

- the match finder runs once per block, not twice: the LZ pass records its tokens and the emit pass replays them
- candidate matches are compared 8 bytes at a time, taking the first differing byte from the low set bit of the xor
- the per-thread codec state is lifted into locals around the chain walk and the hash-chain inserts, which would otherwise pay a TLS lookup per iteration
- length and distance code indexes come from lookup tables rather than a scan over the RFC base tables
- crc32 is table-driven; the bitwise form was slower than the compressor it fed
- the level knobs (chain length, nice length, good length, lazy matching) are zlib's tuning table

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

Both checksums the containers need are exported, and run at roughly 500 MB/s and 440 MB/s:

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
- Codec state is per-thread (`threadvar`): safe to call from several threads at once, and `zuse_threads` fans the streaming compressors out across cores.
- Compression picks the smallest of stored / fixed / dynamic Huffman per block, with LZ77 over a 32 KiB window; the level tunes the search depth and lazy matching.

## License

MIT. Keep the notice from the top of the sources and the link when you redistribute them.
