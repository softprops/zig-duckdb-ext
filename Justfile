ddb_version := "0.9.2"

bootstrap:
    # git clone -b v{{ddb_version}} --single-branch https://github.com/duckdb/duckdb.git
    @git submodule update --init --recursive

fetch-libduckdb:
    @curl -sL --output lib/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v{{ddb_version}}/libduckdb-osx-universal.zip
    @unzip -o lib/duckdb.zip -d lib

build: #fetch-libduckdb
    #@zig build -Doptimize=ReleaseSmall -freference-trace 
    @zig build -freference-trace 

test: build
    @duckdb -unsigned -s "LOAD './zig-out/lib/quack.duckdb_extension'; FROM quack(times = 5)"