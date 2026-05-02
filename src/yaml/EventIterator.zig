const std = @import("std");
const clibyaml = @import("clibyaml");
const Error = @import("error.zig").Error;
const Self = @This();

inner: clibyaml.yaml_parser_t,
peek_event: ?clibyaml.yaml_event_t,
ended: bool,

pub const Event = struct {
    inner: clibyaml.yaml_event_t,

    pub fn deinit(self: *@This()) void {
        clibyaml.yaml_event_delete(&self.inner);
    }
};

pub fn init() Error!Self {
    var iter: Self = .{ .inner = undefined, .peek_event = null, .ended = false };
    if (clibyaml.yaml_parser_initialize(&iter.inner) == 0) {
        return Error.InitializeError;
    }

    return iter;
}

pub fn deinit(self: *Self) void {
    if (self.peek_event) |*event| {
        clibyaml.yaml_event_delete(event);
    }
    clibyaml.yaml_parser_delete(&self.inner);
}

pub fn set_input_string(self: *Self, input: []const u8) void {
    clibyaml.yaml_parser_set_input_string(&self.inner, input.ptr, input.len);
}

pub fn peek(self: *Self) Error!?clibyaml.yaml_event_t {
    if (self.peek_event) |event| {
        return event;
    }

    if (self.ended) {
        return null;
    }

    var event: clibyaml.yaml_event_t = undefined;
    if (clibyaml.yaml_parser_parse(&self.inner, &event) == 0) {
        std.debug.print("Problem: {s}\n", .{self.inner.problem});
        return Error.ParseError;
    }
    self.peek_event = event;

    if (event.type == clibyaml.YAML_NO_EVENT) {
        self.ended = true;
    }

    return self.peek_event;
}

pub fn next(self: *Self) Error!?Event {
    const event = try self.peek() orelse return null;
    self.peek_event = null;
    return .{ .inner = event };
}

pub fn skip(self: *Self) Error!void {
    var event = try self.next() orelse return;
    event.deinit();
}
