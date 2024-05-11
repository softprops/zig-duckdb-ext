ddb_version := "0.10.2"

update-ddb:
    @cd duckdb && git checkout v{{ddb_version}}
bootstrap:
    # git submodule add -b main --name duckdb https://github.com/duckdb/duckdb
    # git clone -b v{{ddb_version}} --single-branch https://github.com/duckdb/duckdb.git
    @git submodule update --init --recursive

fetch-libduckdb:
    @curl -sL --output lib/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v{{ddb_version}}/libduckdb-osx-universal.zip
    @unzip -o lib/duckdb.zip -d lib

build: #fetch-libduckdb
    @zig build -freference-trace

# see # https://github.com/duckdb/duckdb/discussions/12000, https://github.com/duckdb/duckdb/pull/11515 and https://github.com/duckdb/duckdb/blob/main/scripts/append_metadata.cmake
# also https://github.com/duckdb/duckdb/blob/d9efdd14270245c4369096e909acecea174d86cc/src/main/extension/extension_load.cpp#L190-L198
# tldr append 512 to end, 256 for metadata, 256 for signatures
# 4 slots of 32 bytes are used, 128 reserved for future use
# 1. "4" (metadata version)
# 2. {duckdb_platform} https://duckdb.org/docs/extensions/working_with_extensions#platforms
# 3. {duckdb_version}
# 4. {extension_version} (git ref|duckdb_version|custom)
append-metadata:
    @echo "todo: append ddb metadata to ext file"

test: build append-metadata
    @duckdb -unsigned -s "LOAD './zig-out/lib/quack.duckdb_extension'; FROM quack(times = 5)"