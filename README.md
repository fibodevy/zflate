# zflate

The goal is to make these compression functions work exactly like in PHP

| Function | Format | Status |
|-|-|-|
| gzdeflate() |  pure deflate | ✔ |
| gzcompress() |  ZLIB | ✔ |
| gzencode() |  GZIP | ✔ |

And decompression
| Function | Format | Status |
|-|-|-|
| gzinflate() |  pure deflate | ✔ |
| gzuncompress() |  ZLIB | ✘ |
| gzdecode() |  GZIP | ✔ |

Also leaving possiblity to read big files by chunks easily

Unit must be as small as possible (compiled demo is less than 60 kB in size)
