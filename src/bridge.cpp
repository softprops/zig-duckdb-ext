#define DUCKDB_EXTENSION_MAIN

#include "include/bridge.hpp"

#include "duckdb.hpp"

extern "C" {

void quack_init_zig(void *db);
const char *quack_version_zig(void);

DUCKDB_EXTENSION_API void quack_init(duckdb::DatabaseInstance &db) {
	quack_init_zig((void *)&db);
}

DUCKDB_EXTENSION_API const char *quack_version() {
	return quack_version_zig();
}
};

#ifndef DUCKDB_EXTENSION_MAIN
#error DUCKDB_EXTENSION_MAIN not defined
#endif

void duckdb::QuackExtension::Load(DuckDB &db) {
	DuckDB *ptr = &db;
	quack_init_zig((void *)ptr);
}

std::string duckdb::QuackExtension::Name() {
	return "quack";
}