# iotest.sh

Simple script to generate specific IO patterns against a file and produce a report.

## Usage

Requirements:
- dd
- ioping
- fio

```shell
cd path/to/test/drive
path/to/iotest.sh
```

Get the results in `path/to/iotest.sh/result/${TIMESTAMP}`.

## Known Issues

- Does not work well
- Does not work on WSL1 (`fio` returns `func=io_queue_init, error=Function not implemented`)
