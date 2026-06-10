//! Internationalization (I18n) - translation system.
//! Ported from locale/I18n.h, I18n.cpp
//!
//! Loads .lang files (key=value per line) and provides lookup.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Locale manager - loads translation files and looks up strings
pub const I18n = struct {
    strings: std.StringHashMap([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) I18n {
        return .{
            .strings = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *I18n) void {
        var it = self.strings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.strings.deinit();
        self.* = undefined;
    }

    /// Get a translated string. Returns the key if not found.
    pub fn get(self: *const I18n, id: []const u8) []const u8 {
        return self.strings.get(id) orelse id;
    }

    /// Check if a translation exists
    pub fn contains(self: *const I18n, id: []const u8) bool {
        return self.strings.contains(id);
    }

    /// Load translations from a .lang file (key=value format, one per line)
    pub fn loadLangData(self: *I18n, data: []const u8, overwrite: bool) !void {
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '#') continue; // comment

            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            if (key.len == 0) continue;

            if (!overwrite and self.strings.contains(key)) continue;

            const owned_key = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(owned_key);
            const owned_value = try self.allocator.dupe(u8, value);

            // Remove old entry if overwriting
            if (self.strings.getEntry(key)) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }

            try self.strings.put(owned_key, owned_value);
        }
    }

    /// Load translations from a file path
    pub fn loadLangFile(self: *I18n, path: []const u8, overwrite: bool) !void {
        const data = try std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024);
        defer self.allocator.free(data);
        try self.loadLangData(data, overwrite);
    }

    /// Load the default en_US + specified language
    pub fn loadLanguage(self: *I18n, base_path: []const u8, language_code: []const u8) !void {
        // Always load English first
        const en_path = try std.fmt.allocPrint(self.allocator, "{s}/en_US.lang", .{base_path});
        defer self.allocator.free(en_path);
        self.loadLangFile(en_path, true) catch {};

        // Load requested language on top
        if (!std.mem.eql(u8, language_code, "en_US")) {
            const lang_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.lang", .{ base_path, language_code });
            defer self.allocator.free(lang_path);
            self.loadLangFile(lang_path, true) catch {};
        }
    }
};

test "i18n basic" {
    const allocator = std.testing.allocator;
    var i18n = I18n.init(allocator);
    defer i18n.deinit();

    const data =
        \\item.apple.name=Apple
        \\item.swordIron.name=Iron Sword
        \\tile.grass.name=Grass Block
    ;
    try i18n.loadLangData(data, true);

    try std.testing.expectEqualStrings("Apple", i18n.get("item.apple.name"));
    try std.testing.expectEqualStrings("Iron Sword", i18n.get("item.swordIron.name"));
    try std.testing.expectEqualStrings("Grass Block", i18n.get("tile.grass.name"));
    try std.testing.expectEqualStrings("missing.key", i18n.get("missing.key"));
}
