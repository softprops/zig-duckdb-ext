bootstrap:
    @git submodule update --init --recursive

fetch-libduckdb:
    @curl -sL --output lib/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v0.9.2/libduckdb-osx-universal.zip
    @unzip -o lib/duckdb.zip -d lib

build: fetch-libduckdb
    @zig build

test: build
    @duckdb -unsigned -s "LOAD 'zig-out/lib/quack.duckdb_extension'; select quack('test')"