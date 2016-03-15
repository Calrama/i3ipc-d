
module i3ipc;

import std.format : format;

import std.json : JSONValue, JSON_TYPE, parseJSON;

import std.exception : enforce;
import std.algorithm : map, joiner, each;
import std.array : array;
import std.socket : Socket, UnixAddress;
import std.typecons : Nullable, Tuple;
import std.traits : EnumMembers;

import i3ipc.protocol;
import i3ipc.socket;

Connection connect()
{
	import std.process : execute;

	auto result = execute(["i3", "--get-socketpath"]);
	enforce(0 == result.status);
	return Connection(new UnixAddress(result.output[0 .. $-1]));
}

Connection connect(UnixAddress address)
{
	return Connection(address);
}

struct Rectangle
{
	long x, y, width, height;

	this(JSONValue json)
	{
		x = json["x"].integer;
		y = json["y"].integer;
		width = json["width"].integer;
		height = json["height"].integer;
	}
}

struct CommandStatus
{
	bool success;
	Nullable!string error;

	this(JSONValue json)
	{
		success = JSON_TYPE.TRUE == json["success"].type;
		if ("error" in json) error = json["error"].str;
	}

	string toString()
	{
		return "CommandStatus(%s, \"%s\")".format(success, error);
	}
}

struct Workspace
{
	long num;
	string name;
	bool visible, focused, urgent;
	Rectangle rect;
	string output;

	this(JSONValue json)
	{
		num = json["num"].integer;
		name = json["name"].str;
		urgent = JSON_TYPE.TRUE == json["visible"].type;
		visible = JSON_TYPE.TRUE == json["focused"].type;
		focused = JSON_TYPE.TRUE == json["urgent"].type;
		rect = Rectangle(json["rect"]);
		output = json["output"].str;
	}
}

struct Output
{
	string name;
	bool active;
	Nullable!string current_workspace;
	Rectangle rect;

	this(JSONValue json)
	{
		name = json["name"].str;
		active = JSON_TYPE.TRUE == json["active"].type;
		if (!json["current_workspace"].isNull) current_workspace = json["current_workspace"].str;
		rect = Rectangle(json["rect"]);
	}

	string toString()
	{
		return "Output(\"%s\", %s, \"%s\", %s)".format(name, active, current_workspace, rect);
	}
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
		rect = Rectangle(json["rect"]);
		window_rect = Rectangle(json["window_rect"]);
		deco_rect = Rectangle(json["deco_rect"]);
		geometry = Rectangle(json["geometry"]);
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

	this(JSONValue json)
	{
		major = json["major"].integer;
		minor = json["minor"].integer;
		patch = json["patch"].integer;
		human_readable = json["human_readable"].str;
		loaded_config_file_name = json["loaded_config_file_name"].str;
	}
}

enum WorkspaceChange
{
	Focus,
	Init,
	Empty,
	Urgent
}

T fromJSON(T)(JSONValue json) if (is(T == WorkspaceChange))
{
	switch (json.str) {
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

T fromJSON(T)(JSONValue json) if (is(T == OutputChange))

{
	switch (json.str) {
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

T fromJSON(T)(JSONValue json) if (is(T == WindowChange))
{
	switch (json.str) {
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

T fromJSON(T)(JSONValue json) if (is(T == BindingChange))
{
	switch (json.str) {
		case "run": return BindingChange.Run;
		default: assert(0);
	}
}

enum InputType
{
	Keyboard,
	Mouse
}

T fromJSON(T)(JSONValue json) if (is(T == InputType))
{
	switch (json.str) {
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

	this(JSONValue json)
	{
		command = json["command"].str;
		event_state_mask = map!(json => json.str)(json["event_state_mask"].array).array;
		input_code = json["input_code"].integer;
		if (!json["symbol"].isNull) symbol = json["symbol"].str;
		input_type = fromJSON!InputType(json["input_type"]);
	}

	string toString()
	{
		return "Binding(\"%s\", %s, %u, \"%s\", %s)".format(command, event_state_mask, input_code, symbol, input_type);
	}
}

template EventCallback(alias T) if (T == EventType.Workspace)
{ alias EventCallback = void delegate(WorkspaceChange, Container, Nullable!Container); }
template EventCallback(alias T) if (T == EventType.Output)
{ alias EventCallback = void delegate(OutputChange); }
template EventCallback(alias T) if (T == EventType.Mode)
{ alias EventCallback = void delegate(string, bool); }
template EventCallback(alias T) if (T == EventType.Window)
{ alias EventCallback = void delegate(WindowChange, Container); }
template EventCallback(alias T) if (T == EventType.BarConfigUpdate)
{ alias EventCallback = void delegate(BarConfig); }
template EventCallback(alias T) if (T == EventType.Binding)
{ alias EventCallback = void delegate(BindingChange, Binding); }

struct Connection
{
private:
	import core.sync.mutex : Mutex;
	import std.variant : Variant;

	import std.typecons : RefCounted, RefCountedAutoInitialize;
	import std.socket : AddressFamily, SocketType;

	Fiber eventFiber;
	Mutex mutex;

	struct _Payload
	{
		Socket requestSocket, eventSocket;

		shared (Variant[][EventType]) eventCallbacks;

		~this()
		{
			requestSocket.close;
			eventSocket.close;
		}

		@disable this(this);
		void opAssign(_Payload) { assert(false); }
	}
	alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
	Payload p;

	this(UnixAddress address)
	{
		mutex = new Mutex();

		auto requestSocket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		requestSocket.connect(address);

		auto eventSocket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		eventSocket.blocking = false;
		eventSocket.connect(address);

		p = Payload(requestSocket, eventSocket);

		eventFiber = new EventListener(this);
	}

	JSONValue request(RequestType type, immutable(void)[] message = [])
	{
		p.requestSocket.sendMessage(type, message);

		auto responseHeader = p.requestSocket.receiveExactly!Header;
		auto response = p.requestSocket.receiveExactly(new ubyte[responseHeader.size]);

		// This is valid only because corresponding request and response types match uint values
		enforce(type == responseHeader.responseType);
		return parseJSON(response);
	}

public:

	void spin()
	{
		eventFiber.call();
	}

	auto execute(string command)
	{
		return map!(json => CommandStatus(json))(request(RequestType.Command, command).array);
	}

	auto workspaces() @property
	{
		return map!(json => Workspace(json))(request(RequestType.GetWorkspaces).array);
	}

	mixin((cast(EventType[]) [ EnumMembers!EventType ])
		.map!((EventType eventType) => ("
			void subscribe(string eventType)(EventCallback!(EventType.%1$s) callback)
				if (\"%1$s\" == eventType)
			{
				synchronized (mutex) {
					if (EventType.%1$s !in p.eventCallbacks) {
						p.eventSocket.sendMessage(RequestType.Subscribe, JSONValue([EventType.%1$s.toString]).toString);
					}
					p.eventCallbacks[EventType.%1$s] ~= cast(shared(Variant[])) [Variant(callback)];
				}
			}").format(eventType)).joiner.array);

	auto outputs() @property
	{
		return map!(json => Output(json))(request(RequestType.GetOutputs).array);
	}

	Container tree() @property
	{
		return Container(request(RequestType.GetTree));
	}

	auto marks() @property
	{
		return map!(json => json.str)(request(RequestType.GetMarks).array);
	}

	auto configuredBars() @property
	{
		return map!(json => json.str)(request(RequestType.GetBarConfig).array);
	}

	auto getBarConfig(string id)
	{
		return BarConfig(request(RequestType.GetBarConfig, id));
	}

	Version version_() @property
	{
		return Version(request(RequestType.GetVersion));
	}
}

class EventListener : Fiber
{
	import std.variant : Variant;

	this(Connection connection) {
		super(&run);
		this.connection = connection;
	}

private:
	Connection connection;

	void run()
	{
		while (true) {
			auto header = connection.p.eventSocket.receiveExactly!Header;
			auto json = parseJSON(connection.p.eventSocket.receiveExactly(new ubyte[header.size]));
			if (ResponseType.Subscribe == header.responseType) {
				continue;
			}
			switch (header.eventType) {
				case EventType.Workspace:
					auto change = fromJSON!WorkspaceChange(json["change"]);
					auto current = Container(json["current"]);
					Nullable!Container old;
					if (!json["old"].isNull) old = Container(json["old"]);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Workspace]) {
						auto callback = cb.get!(EventCallback!(EventType.Workspace));
						callback(change, current, old);
					}
					break;
				case EventType.Output:
					auto change = fromJSON!OutputChange(json["change"]);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Output]) {
						auto callback = cb.get!(EventCallback!(EventType.Output));
						callback(change);
					}
					break;
				case EventType.Mode:
					auto change = json["change"].str;
					auto pango_markup = JSON_TYPE.TRUE == json["pango_markup"].type;

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Mode]) {
						auto callback = cb.get!(EventCallback!(EventType.Mode));
						callback(change, pango_markup);
					}
					break;
				case EventType.Window:
					auto change = fromJSON!WindowChange(json["change"]);
					auto container = Container(json["container"]);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Window]) {
						auto callback = cb.get!(EventCallback!(EventType.Window));
						callback(change, container);
					}
					break;
				case EventType.BarConfigUpdate:
					auto barConfig = BarConfig(json);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.BarConfigUpdate]) {
						auto callback = cb.get!(EventCallback!(EventType.BarConfigUpdate));
						callback(barConfig);
					}
					break;
				case EventType.Binding:
					auto change = fromJSON!BindingChange(json["change"]);
					auto binding = Binding(json["binding"]);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Binding]) {
						auto callback = cb.get!(EventCallback!(EventType.Binding));
						callback(change, binding);
					}
					break;
				default: assert(0);
			}
		}
	}
}
