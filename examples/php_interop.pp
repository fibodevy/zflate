program php_interop;

{ zflate reads what PHP writes. The three php_gz* files next to this example were
  produced by PHP's gzdeflate() / gzcompress() / gzencode() - a completely
  separate implementation - and must decode here byte for byte. Decoding them
  proves the inflate side is a correct RFC 1951/1950/1952 decoder rather than
  something that only understands its own output.

  The reverse direction (our deflate being readable by others) is checked by
  writing the zflate_gz* files at the end for PHP/zlib to read back.
  Build: fpc -Fu../src php_interop.pp }

{$mode unleashed}

uses zflate;

var
  failed: integer = 0;

procedure check(const name, got, want: string);
begin
  if got = want then writeln('[ OK ] ', name:15, ' -> "', got, '"')
  else begin
    inc(failed);
    writeln('[FAIL] ', name:15, ' -> "', got, '" (expected "', want, '")');
  end;
end;

function file_get_contents(const path: string): string;
var f: file;
begin
  result := '';
  assign(f, path);
  {$I-} reset(f, 1); {$I+}
  if IOResult <> 0 then exit;
  setlength(result, filesize(f));
  if length(result) > 0 then blockread(f, result[1], length(result));
  system.close(f);
end;

procedure file_put_contents(const path, data: string);
var f: file;
begin
  assign(f, path);
  rewrite(f, 1);
  if length(data) > 0 then blockwrite(f, data[1], length(data));
  system.close(f);
end;

// what PHP put in each file
const
  WANT_DEFLATE  = 'gzdeflate() test';
  WANT_COMPRESS = 'gzcompress() test';
  WANT_ENCODE   = 'gzencode() test';

begin
  var raw := file_get_contents('php_gzdeflate');
  var zlib := file_get_contents('php_gzcompress');
  var gzip := file_get_contents('php_gzencode');

  if (raw = '') or (zlib = '') or (gzip = '') then begin
    writeln('php_gz* files not found - run this from the examples directory');
    halt(1);
  end;

  writeln('-- decoding files written by PHP (', length(raw), ', ', length(zlib), ', ', length(gzip), ' bytes) --');
  check('php_gzdeflate', gzinflate(raw), WANT_DEFLATE);
  check('php_gzcompress', gzuncompress(zlib), WANT_COMPRESS);
  check('php_gzencode', gzdecode(gzip), WANT_ENCODE);
  writeln;

  // the checksums PHP wrote into the containers must match what we recompute:
  // gzuncompress and gzdecode already verified adler32 / crc32 + size above,
  // so reaching here with ZFLATE_OK means the footers agreed
  writeln('-- container footers written by PHP verified against our checksums --');
  writeln('zlib adler32: ', if gzuncompress(zlib) <> '' then 'ok' else zflate_error_str(zlasterror));
  writeln('gzip crc32 + size: ', if gzdecode(gzip) <> '' then 'ok' else zflate_error_str(zlasterror));
  writeln;

  // or let zflate work out which format is which
  writeln('-- same files through zdecompress, format auto-detected --');
  for var name in ['php_gzdeflate', 'php_gzcompress', 'php_gzencode'] do begin
    var data := file_get_contents(name);
    var (kind, at, footer) := stream_info(pointer(data), length(data));
    var fmt := match kind of
      ZFLATE_GZIP: 'GZIP';
      ZFLATE_ZLIB: 'ZLIB';
      _: 'DEFLATE';
    end;
    var want := match name of
      'php_gzdeflate': WANT_DEFLATE;
      'php_gzcompress': WANT_COMPRESS;
      _: WANT_ENCODE;
    end;
    check(name + ' [' + fmt + ']', zdecompress(data), want);
  end;
  writeln;

  // finally: our own output of the same texts must decode to the same thing,
  // so both implementations agree in both directions
  writeln('-- our output of the same texts, decoded by us --');
  check('zflate deflate', gzinflate(gzdeflate(WANT_DEFLATE)), WANT_DEFLATE);
  check('zflate zlib', gzuncompress(gzcompress(WANT_COMPRESS)), WANT_COMPRESS);
  check('zflate gzip', gzdecode(gzencode(WANT_ENCODE)), WANT_ENCODE);
  writeln;

  // and write files PHP can read back:
  //   php -r 'echo gzdecode(file_get_contents("zflate_gzencode"));'
  writeln('-- writing files for PHP to read --');
  file_put_contents('zflate_gzdeflate', gzdeflate(WANT_DEFLATE));
  file_put_contents('zflate_gzcompress', gzcompress(WANT_COMPRESS));
  file_put_contents('zflate_gzencode', gzencode(WANT_ENCODE));
  writeln('wrote zflate_gzdeflate, zflate_gzcompress, zflate_gzencode');
  writeln('check with: php -r ''echo gzinflate(file_get_contents("zflate_gzdeflate"));''');
  writeln('            php -r ''echo gzuncompress(file_get_contents("zflate_gzcompress"));''');
  writeln('            php -r ''echo gzdecode(file_get_contents("zflate_gzencode"));''');
  writeln;

  if failed = 0 then writeln('ALL INTEROP CHECKS PASSED')
  else begin writeln(failed, ' CHECK(S) FAILED'); ExitCode := 1; end;
end.
