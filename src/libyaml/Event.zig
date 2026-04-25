const std = @import("std");
const clibyaml = @import("clibyaml");
const Event = @This();

inner: clibyaml.yaml_event_t,
data: Data,

pub fn init(raw: clibyaml.yaml_event_t) Event {
    const event_type: Type = @enumFromInt(raw.type);
    const data = switch (event_type) {
        .None => Data{ .None = {} },
        .StreamStart => Data{ .StreamStart = .{ .encoding = @enumFromInt(raw.data.stream_start.encoding) } },
        .StreamEnd => Data{ .StreamEnd = {} },
        .DocumentStart => blk: {
            const version_directive = if (raw.data.document_start.version_directive) |version_directive|
                VersionDirective{ .major = version_directive.*.major, .minor = version_directive.*.minor }
            else
                null;

            break :blk Data{ .DocumentStart = .{
                .version_directive = version_directive,
                .tag_directives = TagDirectives{ .start = raw.data.document_start.tag_directives.start, .end = raw.data.document_start.tag_directives.end },
                .implicit = raw.data.document_start.implicit == 1,
            } };
        },
        .DocumentEnd => Data{ .DocumentEnd = .{ .implicit = raw.data.document_end.implicit == 1 } },
        .Alias => Data{ .Alias = .{
            .anchor = std.mem.span(raw.data.alias.anchor),
        } },
        .Scalar => Data{ .Scalar = .{
            .anchor = if (raw.data.scalar.anchor) |anchor| std.mem.span(anchor) else null,
            .tag = if (raw.data.scalar.tag) |tag| std.mem.span(tag) else null,
            .value = raw.data.scalar.value[0..raw.data.scalar.length],
            .style = @enumFromInt(raw.data.scalar.style),
        } },
        .SequenceStart => Data{ .SequenceStart = .{
            .anchor = if (raw.data.alias.anchor) |anchor| std.mem.span(anchor) else null,
            .tag = if (raw.data.sequence_start.tag) |tag| std.mem.span(tag) else null,
            .implicit = raw.data.sequence_start.implicit == 1,
            .style = @enumFromInt(raw.data.sequence_start.style),
        } },
        .SequenceEnd => Data{ .SequenceEnd = {} },
        .MappingStart => Data{ .MappingStart = .{
            .anchor = if (raw.data.mapping_start.anchor) |anchor| std.mem.span(anchor) else null,
            .tag = if (raw.data.mapping_start.tag) |tag| std.mem.span(tag) else null,
            .implicit = raw.data.mapping_start.implicit == 1,
            .style = @enumFromInt(raw.data.mapping_start.style),
        } },
        .MappingEnd => Data{ .MappingEnd = {} },
    };

    return .{ .inner = raw, .data = data };
}

pub fn deinit(self: *Event) void {
    clibyaml.yaml_event_delete(&self.inner);
}

pub const Type = enum(c_int) {
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
    MappingStart: MappingStart,
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

pub const MappingStart = struct {
    anchor: ?[]const u8,
    tag: ?[]const u8,
    implicit: bool,
    style: MappingStyle,
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
    start: [*c]clibyaml.yaml_tag_directive_t,
    end: [*c]clibyaml.yaml_tag_directive_t,

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
                .handle = if (item.handle) |handle| std.mem.span(handle) else &.{},
                .prefix = if (item.prefix) |prefix| std.mem.span(prefix) else &.{},
            };
        }
    };

    pub fn iter(self: @This()) Iterator {
        return .{ .current = self.start, .end = self.end };
    }
};

pub const TagDirective = struct {
    handle: []const u8,
    prefix: []const u8,
};

pub const ScalarStyle = enum(c_int) {
    Plain = clibyaml.YAML_PLAIN_SCALAR_STYLE,
    SingleQuoted = clibyaml.YAML_SINGLE_QUOTED_SCALAR_STYLE,
    DoubleQuoted = clibyaml.YAML_DOUBLE_QUOTED_SCALAR_STYLE,
    Literal = clibyaml.YAML_LITERAL_SCALAR_STYLE,
    Folded = clibyaml.YAML_FOLDED_SCALAR_STYLE,
};

pub const SequenceStyle = enum(c_int) {
    Any = clibyaml.YAML_ANY_SEQUENCE_STYLE,
    Block = clibyaml.YAML_BLOCK_SEQUENCE_STYLE,
    Flow = clibyaml.YAML_FLOW_SEQUENCE_STYLE,
};

pub const MappingStyle = enum(c_int) {
    Any = clibyaml.YAML_ANY_MAPPING_STYLE,
    Block = clibyaml.YAML_BLOCK_MAPPING_STYLE,
    Flow = clibyaml.YAML_FLOW_MAPPING_STYLE,
};
