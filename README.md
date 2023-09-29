# zflate

This unit allows you to easily compress and decompress buffers and strings like in PHP. Main goal of this unit is to be as small as possible.

- compiled demo is ~80 kB in size
- adding unit to uses section increases binary size by ~45 kB, even less if you already use zlib units for other things

### Compression
| Function | Format | Status |
|-|-|-|
| gzdeflate() | DEFLATE | 32k bytes limit (will be fixed soon) |
| gzcompress() | ZLIB | 32k bytes limit (will be fixed soon) |
| gzencode() | GZIP | 32k bytes limit (will be fixed soon) |

### Decompression
| Function | Format | Status |
|-|-|-|
| gzinflate() | DEFLATE | ✔ |
| gzuncompress() | ZLIB | ✔ |
| gzdecode() | GZIP | ✔ |
| zdecompress() | ANY | ✔ |

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
//compress whole buffer to DEFLATE at once
function gzdeflate(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9): boolean;
//compress whole string to DEFLATE at once
function gzdeflate(str: string; level: dword=9): string;
//decompress whole DEFLATE buffer at once
function gzinflate(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//decompress whole DEFLATE string at once
function gzinflate(str: string): string;

//compress whole buffer to ZLIB at once
function gzcompress(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9): boolean;
//compress whole string to ZLIB at once
function gzcompress(str: string; level: dword=9): string;
//dempress whole ZLIB buffer at once
function gzuncompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//dempress whole ZLIB string at once
function gzuncompress(str: string): string;

//compress whole buffer to GZIP at once
function gzencode(data: pointer; size: dword; var output: pointer; var outputsize: dword; level: dword=9; filename: string=''; comment: string=''): boolean;
//compress whole string to GZIP at once
function gzencode(str: string; level: dword=9; filename: string=''; comment: string=''): string;
//decompress whole GZIP buffer at once
function gzdecode(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//decompress whole GZIP string at once
function gzdecode(str: string): string;

//try to detect buffer format and decompress it at once
function zdecompress(data: pointer; size: dword; var output: pointer; var outputsize: dword): boolean;
//try to detect string format and decompress it at once
function zdecompress(str: string): string;
```
