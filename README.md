# iotest.sh

Simple script to generate specific IO patterns against a file and produce a report.

Requirements:
- dd
- ioping
- fio

Usage:

```shell
cd path/to/test/drive
path/to/iotest.sh
```

Get the results in `path/to/iotest.sh/result/${TIMESTAMP}`.
