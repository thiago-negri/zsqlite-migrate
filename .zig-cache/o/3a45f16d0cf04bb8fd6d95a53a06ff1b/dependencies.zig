pub const packages = struct {
    pub const @"12208ecb28699b71d3f37e8616418f5a53891418f13772b59dcbe19a67ace9880ae8" = struct {
        pub const build_root = "C:\\Users\\Thiago\\AppData\\Local\\zig\\p\\12208ecb28699b71d3f37e8616418f5a53891418f13772b59dcbe19a67ace9880ae8";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"1220a9d4c8c23db1eb6a0bf7a7add2fdfc3069f7dfa79677f7b65f003a1a63c0ffda" = struct {
        pub const build_root = "C:\\Users\\Thiago\\AppData\\Local\\zig\\p\\1220a9d4c8c23db1eb6a0bf7a7add2fdfc3069f7dfa79677f7b65f003a1a63c0ffda";
        pub const build_zig = @import("1220a9d4c8c23db1eb6a0bf7a7add2fdfc3069f7dfa79677f7b65f003a1a63c0ffda");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "sqlite", "12208ecb28699b71d3f37e8616418f5a53891418f13772b59dcbe19a67ace9880ae8" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zsqlite-c", "1220a9d4c8c23db1eb6a0bf7a7add2fdfc3069f7dfa79677f7b65f003a1a63c0ffda" },
};
