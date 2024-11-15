# zflate

This unit allows you to easily compress and decompress buffers and strings like in PHP. Main goal of this unit is to be as small as possible.

- compiled demo is ~80 kB in size
- adding unit to uses section increases binary size by ~45 kB, even less if you already use zlib units for other things

### Status
|Compression|Decompression|
|--|--|
|<table><tr><th>Function</th><th>Format</th><th>Status</th></tr><tr><td>gzdeflate()</td><td>DEFLATE</td><td>✔</td></tr><tr><td>gzcompress()</td><td>ZLIB</td><td>✔</td></tr><tr><td>gzencode()</td><td>GZIP</td><td>✔</td></tr></table>|<table><tr><th>Function</th><th>Format</th><th>Status</th></tr><tr><td>gzinflate()</td><td>DEFLATE</td><td>✔</td></tr><tr><td>gzuncompress()</td><td>ZLIB</td><td>✔</td></tr><tr><td>gzdecode()</td><td>GZIP</td><td>✔</td></tr><tr><td>zdecompress()</td><td>ANY</td><td>✔</td></tr></table>|

## Usage
```pascal
compressed := gzencode('some string');
decompressed := gzdecode(compressed);
```

Use `zdecompress()` to auto detect stream type and decompress:

```pascal
compressed := gzencode('some string');
decompressed := zdecompress(compressed);
```
## Functions

```pascal
// compress whole buffer to DEFLATE at once
function gzdeflate(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9): boolean;
// compress whole string to DEFLATE at once
function gzdeflate(str: string; level: dword=9): string;
// compress whole bytes to DEFLATE at once
function gzdeflate(bytes: TBytes; level: dword=9): TBytes;
// decompress whole DEFLATE buffer at once
function gzinflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
// decompress whole DEFLATE string at once
function gzinflate(str: string): string;
// decompress whole DEFLATE bytes at once
function gzinflate(bytes: TBytes): TBytes;

// compress whole string to ZLIB at once
function gzcompress(str: string; level: dword=9): string;
// compress whole buffer to ZLIB at once
function gzcompress(bytes: TBytes; level: dword=9): TBytes;
// decompress whole ZLIB buffer at once
function gzuncompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
// decompress whole ZLIB string at once
function gzuncompress(str: string): string;
// decompress whole ZLIB buffer at once
function gzuncompress(bytes: TBytes): TBytes;

// compress whole buffer to GZIP at once
function gzencode(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9; filename: string=''; comment: string=''): boolean;
// compress whole string to GZIP at once
function gzencode(str: string; level: dword=9; filename: string=''; comment: string=''): string;
// compress whole string to GZIP at once
function gzencode(bytes: TBytes; level: dword=9; filename: string=''; comment: string=''): TBytes;
// decompress whole GZIP buffer at once
function gzdecode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
// decompress whole GZIP string at once
function gzdecode(str: string): string;
// decompress whole GZIP string at once
function gzdecode(bytes: TBytes): TBytes;

// try to detect buffer format and decompress it at once
function zdecompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
// try to detect string format and decompress it at once
function zdecompress(str: string): string;
// try to detect bytes format and decompress it at once
function zdecompress(bytes: TBytes): TBytes;
```

## zflatefiles

Additional unit to handle bigger files. Read & write & compress/decompress by chunks.

### Status
|Compression|Decompression|
|--|--|
|<table><tr><th>Function</th><th>Format</th><th>Status</th></tr><tr><td>gzdeflate_file()</td><td>DEFLATE</td><td>❌</td></tr><tr><td>gzcompress_file()</td><td>ZLIB</td><td>❌</td></tr><tr><td>gzencode_file()</td><td>GZIP</td><td>✔</td></tr></table>|<table><tr><th>Function</th><th>Format</th><th>Status</th></tr><tr><td>gzinflate_file()</td><td>DEFLATE</td><td>❌</td></tr><tr><td>gzuncompress_file()</td><td>ZLIB</td><td>❌</td></tr><tr><td>gzdecode_file()</td><td>GZIP</td><td>✔</td></tr></table>|

## Functions

```pascal
// compress a file to GZIP
function gzencode_file(src, dst: string; level: dword=9; filename: string=''; comment: string=''; progresscb: tzprogresscb=nil; resolution: dword=100): boolean;
// decompress a GZIP file
function gzdecode_file(src, dst: string; progresscb: tzprogresscb=nil; resolution: dword=100): boolean;
```

A callback may be provided to these functions. Callback function may abort ongoing operation by returning false.
