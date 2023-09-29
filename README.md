# zflate

This unit allows you to easily compress and decompress buffers and strings like in PHP. Main goal of this unit is to be as small as possible.

- compiled demo is ~80 kB in size
- adding unit to uses section increases binary size by ~45 kB, even less if you already use zlib units for other things

### Compression
| Function | Format | Status |
|-|-|-|
| gzdeflate() | DEFLATE | ✔ |
| gzcompress() | ZLIB | ✔ |
| gzencode() |  GZIP | ✔ |

### Decompression
| Function | Format | Status |
|-|-|-|
| gzinflate() | DEFLATE | ✔ |
| gzuncompress() | ZLIB | ✔ |
| gzdecode() |  GZIP | ✔ |

## Usage
```pascal
compressed := gzencode('any string');
decompressed := gzdecode(compressed);
```
