bootstrap:
    git submodule update --init --recursive

fetch-libduckdb:
    @curl -L --output lib/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v0.9.2/libduckdb-osx-universal.zip
    @unzip -o lib/duckdb.zip -d lib