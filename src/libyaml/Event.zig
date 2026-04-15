const std = @import("std");
const clibyaml = @import("clibyaml");
const Event = @This();

inner: clibyaml.yaml_event_t,
type: Type,
data: Data,

pub fn init(self: *Event) void {
    self.type = @enumFromInt(self.inner.type);
    self.data = switch (self.type) {
        .None => Data{ .None = {} },
        .StreamStart => Data{ .StreamStart = .{ .encoding = @enumFromInt(self.inner.data.stream_start.encoding) } },
        .StreamEnd => Data{ .StreamEnd = {} },
        .DocumentStart => blk: {
            const version_directive = if (self.inner.data.document_start.version_directive != null)
                VersionDirective{ .major = self.inner.data.document_start.version_directive.*.major, .minor = self.inner.data.document_start.version_directive.*.minor }
            else
                null;

            break :blk Data{ .DocumentStart = .{
                .version_directive = version_directive,
                .tag_directives = TagDirectives{ ._start = self.inner.data.document_start.tag_directives.start, ._end = self.inner.data.document_start.tag_directives.end },
                .implicit = self.inner.data.document_start.implicit == 1,
            } };
        },
        .DocumentEnd => Data{ .DocumentEnd = .{ .implicit = self.inner.data.document_end.implicit == 1 } },
        .Alias => Data{ .Alias = .{
            .anchor = std.mem.span(self.inner.data.alias.anchor),
        } },
        .Scalar => Data{ .Scalar = .{
            .anchor = if (self.inner.data.scalar.anchor != null) std.mem.span(self.inner.data.scalar.anchor) else null,
            .tag = if (self.inner.data.scalar.tag != null) std.mem.span(self.inner.data.scalar.tag) else null,
            .value = self.inner.data.scalar.value[0..self.inner.data.scalar.length],
            .style = @enumFromInt(self.inner.data.scalar.style),
        } },
        .SequenceStart => Data{ .SequenceStart = .{
            .anchor = if (self.inner.data.alias.anchor != null) std.mem.span(self.inner.data.alias.anchor) else null,
            .tag = if (self.inner.data.sequence_start.tag != null) std.mem.span(self.inner.data.sequence_start.tag) else null,
            .implicit = self.inner.data.sequence_start.implicit == 1,
            .style = @enumFromInt(self.inner.data.sequence_start.style),
        } },
        .SequenceEnd => Data{ .SequenceEnd = {} },
        .MappingStart => Data{ .MappingStart = {} },
        .MappingEnd => Data{ .MappingEnd = {} },
    };
}

pub fn deinit(self: *Event) void {
    clibyaml.yaml_event_delete(&self.inner);
}

pub const Type = enum(i32) {
    None = clibyaml.YAML_NO_EVENT,
    StreamStart = clibyaml.YAML_STREAM_START_EVENT,
    StreamEnd = clibyaml.YAML_STREAM_END_EVENT,
    DocumentStart = clibyaml.YAML_DOCUMENT_START_EVENT,
    DocumentEnd = clibyaml.YAML_DOCUMENT_END_EVENT,
    Alias = clibyaml.YAML_ALIAS_EVENT,
    Scalar = clibyaml.YAML_SCALAR_EVENT,
    SequenceStart = clibyaml.YAML_SEQUENCE_START_EVENT,
    SequenceEnd = clibyaml.YAML_SEQUENCE_END_EVENT,
    MappingStart = clibyaml.YAML_MAPPING_START_EVENT,
    MappingEnd = clibyaml.YAML_MAPPING_END_EVENT,
};

pub const Data = union(Type) {
    None: void,
    StreamStart: StreamStart,
    StreamEnd: void,
    DocumentStart: DocumentStart,
    DocumentEnd: DocumentEnd,
    Alias: Alias,
    Scalar: Scalar,
    SequenceStart: SequenceStart,
    SequenceEnd: void,
    MappingStart: void,
    MappingEnd: void,
};

pub const StreamStart = struct {
    encoding: Encoding,
};

pub const DocumentStart = struct {
    version_directive: ?VersionDirective,
    tag_directives: TagDirectives,
    implicit: bool,
};

pub const DocumentEnd = struct {
    implicit: bool,
};

pub const Alias = struct {
    anchor: []const u8,
};

pub const Scalar = struct {
    anchor: ?[]const u8,
    tag: ?[]const u8,
    value: []const u8,
    style: ScalarStyle,
};

pub const SequenceStart = struct {
    anchor: ?[]const u8,
    tag: ?[]const u8,
    implicit: bool,
    style: SequenceStyle,
};

pub const Encoding = enum(u32) {
    Any = clibyaml.YAML_ANY_ENCODING,
    Utf8 = clibyaml.YAML_UTF8_ENCODING,
    Utf16le = clibyaml.YAML_UTF16LE_ENCODING,
    Utf16be = clibyaml.YAML_UTF16BE_ENCODING,
};

pub const VersionDirective = struct {
    major: i32,
    minor: i32,
};

pub const TagDirectives = struct {
    _start: [*c]clibyaml.yaml_tag_directive_t,
    _end: [*c]clibyaml.yaml_tag_directive_t,

    pub const Iterator = struct {
        current: [*c]clibyaml.yaml_tag_directive_t,
        end: [*c]clibyaml.yaml_tag_directive_t,

        pub fn next(self: *@This()) ?TagDirective {
            if (@intFromPtr(self.current) == @intFromPtr(self.end)) {
                return null;
            }

            const item = self.current[0];
            self.current += 1;

            return .{
                .handle = if (item.handle != null) std.mem.span(item.handle) else &.{},
                .prefix = if (item.prefix != null) std.mem.span(item.prefix) else &.{},
            };
        }
    };

    pub fn iter(self: @This()) Iterator {
        return .{ .current = self._start, .end = self._end };
    }
};

pub const TagDirective = struct {
    handle: []const u8,
    prefix: []const u8,
};

pub const ScalarStyle = enum(i32) {
    Plain = clibyaml.YAML_PLAIN_SCALAR_STYLE,
    SingleQuoted = clibyaml.YAML_SINGLE_QUOTED_SCALAR_STYLE,
    DoubleQuoted = clibyaml.YAML_DOUBLE_QUOTED_SCALAR_STYLE,
    Literal = clibyaml.YAML_LITERAL_SCALAR_STYLE,
    Folded = clibyaml.YAML_FOLDED_SCALAR_STYLE,
};

pub const SequenceStyle = enum(i32) {
    Any = clibyaml.YAML_ANY_SEQUENCE_STYLE,
    Block = clibyaml.YAML_BLOCK_SEQUENCE_STYLE,
    Flow = clibyaml.YAML_FLOW_SEQUENCE_STYLE,
};
