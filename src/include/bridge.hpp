
#pragma once

#include "duckdb.hpp"

extern "C" {
// exposed so zig call call into bridge
DUCKDB_EXTENSION_API char const *quack_version();
DUCKDB_EXTENSION_API void quack_init(duckdb::DatabaseInstance &db);
}

namespace duckdb {
class QuackExtension : public Extension {
public:
	void Load(DuckDB &db) override;
	std::string Name() override;
};
} // namespace duckdb