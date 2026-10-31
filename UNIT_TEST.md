# Unit Test

- [English](#english)
- [Bahasa Indonesia](#bahasa-indonesia)

---

## English

Unit tests use **FPCUnit** (part of the Free Pascal FCL) with the console test runner.
Each test project is a standalone console program, so it can be run without installing the FastPlaz package into the Lazarus IDE.

### Available test projects

| Project | Location | What is tested |
| --- | --- | --- |
| `regex_tester_test` | `tools/src/test` | `regex_tester_lib` – logic behind the *Regex Tester* tool and the `REGEX_*` constants |
| `fastplaz_test` | `FastPlaz/test` | `datetime_lib` – `DateTimeHuman()`, `DateTimeHumanAt()` and the date string parser `TryParseHumanDate()`<br>`redis_lib` – `TRedisLib`: configuration, RESP replies, SET/GET, timeout and reconnect (see [Redis tests](#redis-tests))<br>`json_lib` – `TJSONUtil`: loading, path access, typed values, arrays and items<br>`config_lib` – `TMyConfig`: `ValidateFile()`, `Value[]`, `GetObject()` and `SetDataValue()`<br>`common` – base64, `HTMLDecode()`, `StripHTML()`, `RandomString()`, `isIPAddress()` and string helpers |

### Prerequisites

* FPC / Free Pascal Compiler, version 3.2.2
* Lazarus (for `lazbuild`), optional when using `instantfpc`
* A Redis server for the `TRedisLibServerTest` suite, optional (see [Redis tests](#redis-tests))

### Quick run with instantfpc

The fastest way: compile and run the tests in one command, without `lazbuild` and without the Lazarus IDE.
`instantfpc` is shipped with FPC (Windows: `C:\lazarus\fpc\3.2.2\bin\x86_64-win64\instantfpc.exe`).

Windows (can be called from any directory):

```bat
tools\src\test\run_tests.bat
FastPlaz\test\run_tests.bat
```

Linux / macOS:

```bash
sh tools/src/test/run_tests.sh
sh FastPlaz/test/run_tests.sh
```

Without arguments all tests are run (`-a`). Runner options can be passed directly, for example:

```bat
tools\src\test\run_tests.bat --suite=TestEmailRegex
tools\src\test\run_tests.bat --format=xml --file=result.xml
```

Notes:

* The scripts set the unit search paths through the `INSTANTFPCOPTIONS` environment variable. `instantfpc` 1.3 does not handle `-Fu` with a path separator on its own command line (the option is passed to the test program and fails with `Invalid option ... "F"`).
* `-B` is always used, because the `instantfpc` cache only checks the main program (`.lpr`); without it changes in other units would not be recompiled.
* The compiled program is stored in the `instantfpc` cache (`instantfpc --get-cache`), not in the repository.
* On Windows, if `instantfpc` is not in `PATH`, `run_tests.bat` uses `C:\lazarus\fpc\3.2.2\bin\x86_64-win64`.
* `FastPlaz/test/run_tests.*` adds the unit paths of the `fastplaz_runtime` package, because `datetime_lib` depends on `language_lib` and `common`.

### Redis tests

`test_redis_lib` has two suites:

* `TRedisLibOfflineTest` needs no server: defaults, port validation, `BulkPayload()`, master configuration, connection refused, connect timeout, IPv6 literal forms, unreachable IPv6 address, unresolvable host, deprecated `Synch`.
* `TRedisLibServerTest` talks to a real Redis server: SET/GET, special characters, code page tagged values, large values, INFO, numeric and multi bulk replies, error replies, inline commands, read timeout and reconnect, host name lookup, IPv6 loopback (`::1`, ignored when the server is IPv4 only), write to master.

The server defaults to `127.0.0.1:6379`. When it is not reachable the whole `TRedisLibServerTest` suite is reported as *ignored*, not as failed, so the run still passes. Another server can be set through environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `FASTPLAZ_TEST_REDIS_HOST` | `127.0.0.1` | IP address or host name |
| `FASTPLAZ_TEST_REDIS_PORT` | `6379` | port |
| `FASTPLAZ_TEST_REDIS_PASSWORD` | *(empty)* | sent with `AUTH` when set |

Every key written by the tests starts with `fastplaz:test:` and is deleted in `TearDown`; the database is never flushed. Run only the Redis tests with `--suite=TRedisLibServerTest`.

### Build

Windows:

```bat
cd tools\src\test
C:\lazarus\lazbuild.exe regex_tester_test.lpi
```

Linux / macOS (`lazbuild` in `PATH`):

```bash
cd tools/src/test
lazbuild regex_tester_test.lpi
```

The same applies to `FastPlaz/test/fastplaz_test.lpi`. That project requires the `fastplaz_runtime` package (`tools/fastplaz_runtime.lpk`), which has to be known to Lazarus / `lazbuild`; register it once with `lazbuild --add-package-link tools/fastplaz_runtime.lpk` if it is not.

Compiled units go to `lib/<cpu>-<os>/`. Build output is ignored by `.gitignore`.

### Run

Windows:

```bat
regex_tester_test.exe -a
```

Linux / macOS:

```bash
./regex_tester_test -a
```

Example output:

```
Number of run tests: 16
Number of errors:    0
Number of failures:  0
```

The program exits with code `0` when all tests pass and a non-zero code when a test fails, so it can be used in scripts or CI.

### Runner options

| Option | Description |
| --- | --- |
| `-a`, `--all` | run all tests |
| `-l`, `--list` | list registered tests |
| `--suite=NAME` | run a single test class or test method, e.g. `--suite=TestEmailRegex` |
| `--format=FMT` | output format: `plain` (default for this project), `plainnotiming`, `xml`, `latex` |
| `--sparse` | show only errors and failures |
| `--file=FILE` | write the result to a file, e.g. `--format=xml --file=result.xml` |
| `-h` | show all options |

### Running from the Lazarus IDE

1. Open `tools/src/test/regex_tester_test.lpi` or `FastPlaz/test/fastplaz_test.lpi` (*Project → Open Project*).
2. Set the parameter in *Run → Run Parameters* → *Command line parameters*: `-a`.
3. Press **F9**.

### Adding a new test

1. Put the logic to be tested in a unit **without** dependencies on LCL forms or the IDE (`IDEIntf`, `PackageIntf`, …), for example `xxx_lib.pas`.
2. Create a test unit next to the matching test project (`tools/src/test` for the Lazarus tools, `FastPlaz/test` for the framework library), e.g. `test_xxx_lib.pas`:

   ```pascal
   unit test_xxx_lib;

   {$mode objfpc}{$H+}

   interface

   uses
     xxx_lib, Classes, SysUtils, fpcunit, testregistry;

   type
     TXxxLibTest = class(TTestCase)
     published
       procedure TestSomething;
     end;

   implementation

   procedure TXxxLibTest.TestSomething;
   begin
     AssertEquals(2, 1 + 1);
   end;

   initialization
     RegisterTest(TXxxLibTest);

   end.
   ```

3. Add the unit to the `uses` clause of the test program (`.lpr`) and to the project (`.lpi`).
4. Build and run again.

---

## Bahasa Indonesia

Unit test menggunakan **FPCUnit** (bagian dari FCL Free Pascal) dengan *console test runner*.
Setiap project test adalah program console mandiri, sehingga bisa dijalankan tanpa perlu meng-install package FastPlaz ke Lazarus IDE.

### Project test yang tersedia

| Project | Lokasi | Yang diuji |
| --- | --- | --- |
| `regex_tester_test` | `tools/src/test` | `regex_tester_lib` – logika di balik tool *Regex Tester* dan konstanta `REGEX_*` |
| `fastplaz_test` | `FastPlaz/test` | `datetime_lib` – `DateTimeHuman()`, `DateTimeHumanAt()` dan parser string tanggal `TryParseHumanDate()`<br>`redis_lib` – `TRedisLib`: konfigurasi, balasan RESP, SET/GET, timeout dan reconnect (lihat [Test Redis](#test-redis))<br>`json_lib` – `TJSONUtil`: load, akses path, nilai bertipe, array dan item<br>`config_lib` – `TMyConfig`: `ValidateFile()`, `Value[]`, `GetObject()` dan `SetDataValue()`<br>`common` – base64, `HTMLDecode()`, `StripHTML()`, `RandomString()`, `isIPAddress()` dan helper string |

### Prasyarat

* FPC / Free Pascal Compiler, versi 3.2.2
* Lazarus (untuk `lazbuild`), opsional jika memakai `instantfpc`
* Server Redis untuk suite `TRedisLibServerTest`, opsional (lihat [Test Redis](#test-redis))

### Jalankan cepat dengan instantfpc

Cara tercepat: compile dan jalankan test dalam satu perintah, tanpa `lazbuild` dan tanpa Lazarus IDE.
`instantfpc` sudah disertakan bersama FPC (Windows: `C:\lazarus\fpc\3.2.2\bin\x86_64-win64\instantfpc.exe`).

Windows (bisa dipanggil dari direktori mana saja):

```bat
tools\src\test\run_tests.bat
FastPlaz\test\run_tests.bat
```

Linux / macOS:

```bash
sh tools/src/test/run_tests.sh
sh FastPlaz/test/run_tests.sh
```

Tanpa argumen, semua test dijalankan (`-a`). Opsi runner bisa langsung diberikan, contoh:

```bat
tools\src\test\run_tests.bat --suite=TestEmailRegex
tools\src\test\run_tests.bat --format=xml --file=result.xml
```

Catatan:

* Script mengatur path pencarian unit lewat variabel lingkungan `INSTANTFPCOPTIONS`. `instantfpc` 1.3 tidak bisa menangani `-Fu` yang berisi pemisah path di command line-nya (opsi tersebut malah diteruskan ke program test dan gagal dengan `Invalid option ... "F"`).
* `-B` selalu dipakai, karena cache `instantfpc` hanya memeriksa program utama (`.lpr`); tanpa `-B` perubahan di unit lain tidak akan di-compile ulang.
* Program hasil compile disimpan di cache `instantfpc` (`instantfpc --get-cache`), bukan di repositori.
* Di Windows, jika `instantfpc` tidak ada di `PATH`, `run_tests.bat` memakai `C:\lazarus\fpc\3.2.2\bin\x86_64-win64`.
* `FastPlaz/test/run_tests.*` menambahkan path unit dari package `fastplaz_runtime`, karena `datetime_lib` bergantung pada `language_lib` dan `common`.

### Test Redis

`test_redis_lib` berisi dua suite:

* `TRedisLibOfflineTest` tidak butuh server: nilai default, validasi port, `BulkPayload()`, konfigurasi master, koneksi ditolak, timeout connect, bentuk literal IPv6, alamat IPv6 tak terjangkau, host tidak dikenal, `Synch` yang sudah deprecated.
* `TRedisLibServerTest` memakai server Redis sungguhan: SET/GET, karakter khusus, nilai ber-codepage, nilai besar, INFO, balasan numerik dan multi bulk, balasan error, perintah inline, timeout baca dan reconnect, lookup nama host, loopback IPv6 (`::1`, di-ignore jika server hanya IPv4), tulis ke master.

Server default `127.0.0.1:6379`. Jika tidak bisa dihubungi, seluruh suite `TRedisLibServerTest` dilaporkan sebagai *ignored*, bukan gagal, sehingga run tetap lulus. Server lain bisa diatur lewat variabel lingkungan:

| Variabel | Default | Keterangan |
| --- | --- | --- |
| `FASTPLAZ_TEST_REDIS_HOST` | `127.0.0.1` | alamat IP atau nama host |
| `FASTPLAZ_TEST_REDIS_PORT` | `6379` | port |
| `FASTPLAZ_TEST_REDIS_PASSWORD` | *(kosong)* | dikirim dengan `AUTH` jika diisi |

Semua key yang ditulis test diawali `fastplaz:test:` dan dihapus di `TearDown`; database tidak pernah di-flush. Untuk menjalankan test Redis saja: `--suite=TRedisLibServerTest`.

### Build

Windows:

```bat
cd tools\src\test
C:\lazarus\lazbuild.exe regex_tester_test.lpi
```

Linux / macOS (`lazbuild` ada di `PATH`):

```bash
cd tools/src/test
lazbuild regex_tester_test.lpi
```

Hal yang sama berlaku untuk `FastPlaz/test/fastplaz_test.lpi`. Project itu membutuhkan package `fastplaz_runtime` (`tools/fastplaz_runtime.lpk`) yang harus sudah dikenal oleh Lazarus / `lazbuild`; jika belum, daftarkan sekali dengan `lazbuild --add-package-link tools/fastplaz_runtime.lpk`.

Hasil kompilasi unit disimpan di `lib/<cpu>-<os>/`. Hasil build sudah diabaikan oleh `.gitignore`.

### Menjalankan

Windows:

```bat
regex_tester_test.exe -a
```

Linux / macOS:

```bash
./regex_tester_test -a
```

Contoh output:

```
Number of run tests: 16
Number of errors:    0
Number of failures:  0
```

Program keluar dengan kode `0` jika semua test lulus, dan kode selain `0` jika ada test yang gagal, sehingga bisa dipakai di script atau CI.

### Opsi runner

| Opsi | Keterangan |
| --- | --- |
| `-a`, `--all` | jalankan semua test |
| `-l`, `--list` | tampilkan daftar test yang terdaftar |
| `--suite=NAMA` | jalankan satu class test atau satu method test saja, contoh `--suite=TestEmailRegex` |
| `--format=FMT` | format output: `plain` (default di project ini), `plainnotiming`, `xml`, `latex` |
| `--sparse` | hanya tampilkan error dan failure |
| `--file=FILE` | simpan hasil ke file, contoh `--format=xml --file=result.xml` |
| `-h` | tampilkan semua opsi |

### Menjalankan dari Lazarus IDE

1. Buka `tools/src/test/regex_tester_test.lpi` atau `FastPlaz/test/fastplaz_test.lpi` (*Project → Open Project*).
2. Isi parameter di *Run → Run Parameters* → *Command line parameters*: `-a`.
3. Tekan **F9**.

### Menambah test baru

1. Letakkan logika yang akan diuji di unit yang **tidak** bergantung pada form LCL maupun IDE (`IDEIntf`, `PackageIntf`, …), misalnya `xxx_lib.pas`.
2. Buat unit test di samping project test yang sesuai (`tools/src/test` untuk tools Lazarus, `FastPlaz/test` untuk library framework), misalnya `test_xxx_lib.pas` (lihat contoh kode di bagian [English](#adding-a-new-test)).
3. Tambahkan unit tersebut ke `uses` program test (`.lpr`) dan ke project (`.lpi`).
4. Build dan jalankan ulang.
