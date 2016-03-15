
module i3ipc.data;

import std.typecons : Nullable, Tuple;
import std.algorithm : map, joiner, each;
import std.array : array;

import std.format : format;
import std.json : JSONValue, JSON_TYPE;


struct Rectangle
{
	long x, y, width, height;
}

T fromJSON(T)(JSONValue v) if (is(T == Rectangle))
{
	return Rectangle(
		v["x"].integer,
		v["y"].integer,
		v["width"].integer,
		v["height"].integer,
	);
}

struct CommandStatus
{
	bool success;
	Nullable!string error;

	string toString()
	{
		return "CommandStatus(%s, \"%s\")".format(success, error);
	}
}

T fromJSON(T)(JSONValue v) if (is(T == CommandStatus))
{
	return CommandStatus(
		JSON_TYPE.TRUE == v["success"].type,
		"error" in v ? Nullable!string(v["error"].str) : Nullable!string.init
	);
}

struct Workspace
{
	long num;
	string name;
	bool visible, focused, urgent;
	Rectangle rect;
	string output;
}

T fromJSON(T)(JSONValue v) if (is(T == Workspace))
{
	return Workspace(
		v["num"].integer,
		v["name"].str,
		JSON_TYPE.TRUE == v["visible"].type,
		JSON_TYPE.TRUE == v["focused"].type,
		JSON_TYPE.TRUE == v["urgent"].type,
		fromJSON!Rectangle(v["rect"]),
		v["output"].str,
	);
}

struct Output
{
	string name;
	bool active;
	Nullable!string current_workspace;
	Rectangle rect;

	string toString()
	{
		return "Output(\"%s\", %s, \"%s\", %s)".format(name, active, current_workspace, rect);
	}
}

T fromJSON(T)(JSONValue v) if (is(T == Output))
{
	return Output(
		v["name"].str,
		JSON_TYPE.TRUE == v["active"].type,
		v["current_workspace"].isNull ? Nullable!string.init : Nullable!string(v["current_workspace"].str),
		fromJSON!Rectangle(v["rect"])
	);
}

struct Container
{
	long id;
	Type type;
	Nullable!string name;
	Border border;
	long current_border_width;
	Layout layout;
	Nullable!double percent;
	Rectangle rect, window_rect, deco_rect, geometry;
	Nullable!long window;
	bool urgent, focused;

	Container[] nodes;

	this(JSONValue json)
	{
		id = json["id"].integer;
		if (!json["name"].isNull) name = json["name"].str;
		switch (json["type"].str) {
			case "root": type = Type.Root; break;
			case "output": type = Type.Output; break;
			case "con": type = Type.Normal; break;
			case "floating_con": type = Type.Floating; break;
			case "workspace": type = Type.Workspace; break;
			case "dockarea": type = Type.Dockarea; break;
			default: assert(0);
		}
		switch (json["border"].str) {
			case "normal": border = Border.Normal; break;
			case "none": border = Border.None; break;
			case "pixel": border = Border.Pixel; break;
			default: assert(0);
		}
		current_border_width = json["current_border_width"].integer;
		switch (json["layout"].str) {
			case "splith": layout = Layout.Columns; break;
			case "splitv": layout = Layout.Rows; break;
			case "stacked": layout = Layout.Stacked; break;
			case "tabbed": layout = Layout.Tabbed; break;
			case "dockarea": layout = Layout.Dockarea; break;
			case "output": layout = Layout.Output; break;
			default: assert(0);
		}
		if (!json["percent"].isNull) percent = Nullable!double(json["percent"].floating);
		rect = fromJSON!Rectangle(json["rect"]);
		window_rect = fromJSON!Rectangle(json["window_rect"]);
		deco_rect = fromJSON!Rectangle(json["deco_rect"]);
		geometry = fromJSON!Rectangle(json["geometry"]);
		if (!json["window"].isNull) window = Nullable!long(json["window"].integer);
		urgent = JSON_TYPE.TRUE == json["urgent"].type;
		focused = JSON_TYPE.TRUE == json["focused"].type;

		nodes = map!(json => Container(json))(json["nodes"].array).array;
	}

	enum Type
	{
		Root,
		Output,
		Normal,
		Floating,
		Workspace,
		Dockarea
	}

	enum Border
	{
		Normal,
		None,
		Pixel
	}

	enum Layout
	{
		Rows,
		Columns,
		Stacked,
		Tabbed,
		Dockarea,
		Output
	}

	string toString()
	{
		return "Container(%s %s \"%s\" %s %s %s %s %s %s %s %s %s %s %s [%s])".format(
			id,
			type,
			name,

			border,
			current_border_width,
			layout,
			percent,
			rect, window_rect, deco_rect, geometry,

			window,
			urgent, focused,

			map!(node => node.toString)(nodes).joiner(", "));
	}
}

struct BarConfig
{
	string id, status_command, font;
	Mode mode;
	Position position;
	bool workspace_buttons, binding_mode_indicator, verbose;

	enum Mode
	{
		Dock,
		Hide
	}

	enum Position
	{
		Bottom,
		Top
	}

	private enum ConfigurableColors = [
		"background",
		"statusline",
		"separator",
		"focused_workspace_text",
		"focused_workspace_bg",
		"focused_workspace_border",
		"active_workspace_text",
		"active_workspace_bg",
		"active_workspace_border",
		"inactive_workspace_text",
		"inactive_workspace_bg",
		"inactive_workspace_border",
		"urgent_workspace_text",
		"urgent_workspace_bg",
		"urgent_workspace_border",
		"binding_mode_text",
		"binding_mode_bg",
		"binding_mode_border"];

	mixin("Tuple!("
		~ ConfigurableColors.map!((string x) => "Nullable!string, \"%s\"".format(x)).joiner(",").array
		~ ") colors;");

	this(JSONValue json)
	{
		id = json["id"].str;
		switch (json["mode"].str) {
			case "dock": mode = Mode.Dock; break;
			case "hide": mode = Mode.Hide; break;
			default: assert(0);
		}
		switch (json["position"].str) {
			case "top": position = Position.Top; break;
			case "bottom": position = Position.Bottom; break;
			default: assert(0);
		}
		status_command = json["status_command"].str;
		font = json["font"].str;

		workspace_buttons = JSON_TYPE.TRUE == json["workspace_buttons"].type;
		binding_mode_indicator = JSON_TYPE.TRUE == json["binding_mode_indicator"].type;
		verbose = JSON_TYPE.TRUE == json["verbose"].type;

		auto colors_json = json["colors"];
		mixin(ConfigurableColors.map!(x => "if (\"%1$s\" in colors_json) colors.%1$s = colors_json[\"%1$s\"].str;\n".format(x)).joiner.array);
	}

	string toString()
	{
		import std.range : repeat;
		mixin(
			"return \"BarConfig(" ~ "%s".repeat(26).joiner(" ").array ~ ")\".format(
				id, status_command, font,
				mode,
				position,
				workspace_buttons, binding_mode_indicator, verbose,"
			~ ConfigurableColors.map!(x => "colors.%s".format(x)).joiner(",\n").array
			~ ");");
	}
}

struct Version
{
	long major, minor, patch;
	string human_readable, loaded_config_file_name;
}

T fromJSON(T)(JSONValue v) if (is(T == Version))
{
	return Version(
		v["major"].integer,
		v["minor"].integer,
		v["patch"].integer,
		v["human_readable"].str,
		v["loaded_config_file_name"].str
	);
}

enum WorkspaceChange
{
	Focus,
	Init,
	Empty,
	Urgent
}

T fromJSON(T)(JSONValue v) if (is(T == WorkspaceChange))
{
	switch (v.str) {
		case "focus": return WorkspaceChange.Focus;
		case "init": return WorkspaceChange.Init;
		case "empty": return WorkspaceChange.Empty;
		case "urgent": return WorkspaceChange.Urgent;
		default: assert(0);
	}
}

enum OutputChange
{
	Unspecified
}

T fromJSON(T)(JSONValue v) if (is(T == OutputChange))
{
	switch (v.str) {
		case "unspecified": return OutputChange.Unspecified;
		default: assert(0);
	}
}

enum WindowChange
{
	New,
	Close,
	Focus,
	Title,
	Fullscreen,
	Move,
	Floating,
	Urgent
}

T fromJSON(T)(JSONValue v) if (is(T == WindowChange))
{
	switch (v.str) {
		case "new": return WindowChange.New;
		case "close": return WindowChange.Close;
		case "focus": return WindowChange.Focus;
		case "title": return WindowChange.Title;
		case "fullscreen_mode": return WindowChange.Fullscreen;
		case "move": return WindowChange.Move;
		case "floating": return WindowChange.Floating;
		case "urgent": return WindowChange.Urgent;
		default: assert(0);
	}
}

enum BindingChange
{
	Run
}

T fromJSON(T)(JSONValue v) if (is(T == BindingChange))
{
	switch (v.str) {
		case "run": return BindingChange.Run;
		default: assert(0);
	}
}

enum InputType
{
	Keyboard,
	Mouse
}

T fromJSON(T)(JSONValue v) if (is(T == InputType))
{
	switch (v.str) {
		case "keyboard": return InputType.Keyboard;
		case "mouse": return InputType.Mouse;
		default: assert(0);
	}
}

struct Binding
{
	string command;
	string[] event_state_mask;
	long input_code;
	Nullable!string symbol;
	InputType input_type;

	string toString()
	{
		return "Binding(\"%s\", %s, %u, \"%s\", %s)".format(command, event_state_mask, input_code, symbol, input_type);
	}
}

T fromJSON(T)(JSONValue v) if (is(T == Binding))
{
	return Binding(
		v["command"].str,
		map!(v => v.str)(v["event_state_mask"].array).array,
		v["input_code"].integer,
		v["symbol"].isNull ? Nullable!string.init : Nullable!string(v["symbol"].str),
		fromJSON!InputType(v["input_type"])
	);
}
