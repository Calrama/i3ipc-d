
module i3ipc;

import std.format : format;

import std.process : execute;
import std.json : JSONValue, JSON_TYPE, parseJSON;

import std.exception : enforce;
import std.algorithm : map, joiner, filter, each;
import std.array : array;
import std.socket : Socket, UnixAddress, SocketException;
import std.typecons : Nullable, Tuple;
import std.conv : to;

import std.stdio : writeln;

align(1) struct Header
{
	align (1):
    char[6] magic = Magic; /* 6 = strlen(Magic) */
    uint size;
    uint type;

    this(uint size, uint type)
    {
    	this.size = size;
    	this.type = type;
    }
}

/** Never change this, only on major IPC breakage (don’t do that) */
enum Magic = "i3-ipc";

enum RequestType : uint
{
	Command = 0,
	GetWorkspaces,
	Subscribe,
	GetOutputs,
	GetTree,
	GetMarks,
	GetBarConfig,
	GetVersion
}

enum ResponseType : uint
{
	Command = 0,
	Workspaces,
	Subscribe,
	Outputs,
	Tree,
	Marks,
	BarConfig,
	Version
}

enum reponseTypes = [
	RequestType.Command : ResponseType.Command,
	RequestType.GetWorkspaces : ResponseType.Workspaces,
	RequestType.Subscribe : ResponseType.Subscribe,
	RequestType.GetOutputs : ResponseType.Outputs,
	RequestType.GetTree : ResponseType.Tree,
	RequestType.GetMarks : ResponseType.Marks,
	RequestType.GetBarConfig : ResponseType.BarConfig,
	RequestType.GetVersion : ResponseType.Version
];

enum EventMask = (1 << 31);

enum EventType : uint
{
	Workspace       = (EventMask | 0),
	Output          = (EventMask | 1),
	Mode            = (EventMask | 2),
	Window          = (EventMask | 3),
	BarConfigUpdate = (EventMask | 4),
	Binding         = (EventMask | 5)
}

string toString(EventType type)
{
	switch (type) {
		case EventType.Workspace: return "workspace"; break;
		case EventType.Output: return "output"; break;
		case EventType.Mode: return "mode"; break;
		case EventType.Window: return "window"; break;
		case EventType.BarConfigUpdate: return "barconfig_update"; break;
		case EventType.Binding: return "binding"; break;
		default: assert(0);
	}
}

/+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++/

Connection connect()
{
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
		return "%s %s \"%s\" %s %s %s %s %s %s %s %s %s %s %s [%s]".format(
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

	Tuple!(
		Nullable!string, "background",
		Nullable!string, "statusline",
		Nullable!string, "separator",

		Nullable!string, "focused_workspace_text",
		Nullable!string, "focused_workspace_bg",
		Nullable!string, "focused_workspace_border",

		Nullable!string, "active_workspace_text",
		Nullable!string, "active_workspace_bg",
		Nullable!string, "active_workspace_border",

		Nullable!string, "inactive_workspace_text",
		Nullable!string, "inactive_workspace_bg",
		Nullable!string, "inactive_workspace_border",

		Nullable!string, "urgent_workspace_text",
		Nullable!string, "urgent_workspace_bg",
		Nullable!string, "urgent_workspace_border",

		Nullable!string, "binding_mode_text",
		Nullable!string, "binding_mode_bg",
		Nullable!string, "binding_mode_border") colors;

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
		if ("background" in colors_json) colors.background = colors_json["background"].str;
		if ("statusline" in colors_json) colors.statusline = colors_json["statusline"].str;
		if ("separator" in colors_json) colors.separator = colors_json["separator"].str;

		if ("focused_workspace_text" in colors_json) colors.focused_workspace_text = colors_json["focused_workspace_text"].str;
		if ("focused_workspace_bg" in colors_json) colors.focused_workspace_bg = colors_json["focused_workspace_bg"].str;
		if ("focused_workspace_border" in colors_json) colors.focused_workspace_border = colors_json["focused_workspace_border"].str;

		if ("active_workspace_text" in colors_json) colors.active_workspace_text = colors_json["active_workspace_text"].str;
		if ("active_workspace_bg" in colors_json) colors.active_workspace_bg = colors_json["active_workspace_bg"].str;
		if ("active_workspace_border" in colors_json) colors.active_workspace_border = colors_json["active_workspace_border"].str;

		if ("inactive_workspace_text" in colors_json) colors.inactive_workspace_text = colors_json["inactive_workspace_text"].str;
		if ("inactive_workspace_bg" in colors_json) colors.inactive_workspace_bg = colors_json["inactive_workspace_bg"].str;
		if ("inactive_workspace_border" in colors_json) colors.inactive_workspace_border = colors_json["inactive_workspace_border"].str;

		if ("urgent_workspace_text" in colors_json) colors.urgent_workspace_text = colors_json["urgent_workspace_text"].str;
		if ("urgent_workspace_bg" in colors_json) colors.urgent_workspace_bg = colors_json["urgent_workspace_bg"].str;
		if ("urgent_workspace_border" in colors_json) colors.urgent_workspace_border = colors_json["urgent_workspace_border"].str;

		if ("binding_mode_text" in colors_json) colors.binding_mode_text = colors_json["binding_mode_text"].str;
		if ("binding_mode_bg" in colors_json) colors.binding_mode_bg = colors_json["binding_mode_bg"].str;
		if ("binding_mode_border" in colors_json) colors.binding_mode_border = colors_json["binding_mode_border"].str;
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
	import core.thread : Thread;

	import std.typecons : RefCounted, RefCountedAutoInitialize;
	import std.socket : AddressFamily, SocketType;
	import std.variant : Variant;

	struct _Payload
	{
		Socket requestSocket, eventSocket;
		
		Mutex mutex;
		Thread eventThread;
		
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
		auto requestSocket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		requestSocket.connect(address);

		auto eventSocket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		eventSocket.connect(address);

		auto p = Payload(requestSocket, eventSocket, new Mutex);

		auto eventThread = new Thread(() {
			while (true) {
				auto header = i3ipc.receive!Header(p.eventSocket);
				auto json = parseJSON(i3ipc.fill(p.eventSocket, new ubyte[header.size]));
				if (header.type == ResponseType.Subscribe) continue;
				auto type = cast(EventType) header.type;
				switch (type) {
					case EventType.Workspace:
						auto change = fromJSON!WorkspaceChange(json["change"]);
						auto current = Container(json["current"]);
						Nullable!Container old;
						if (!json["old"].isNull) old = Container(json["old"]);

						synchronized (p.mutex) foreach (cb; cast(Variant[]) p.eventCallbacks[EventType.Workspace]) {
							auto callback = cb.get!(EventCallback!(EventType.Workspace));
							callback(change, current, old);
						}
						break;
					case EventType.Output:
						auto change = fromJSON!OutputChange(json["change"]);

						synchronized (p.mutex) foreach (cb; cast(Variant[]) p.eventCallbacks[EventType.Output]) {
							auto callback = cb.get!(EventCallback!(EventType.Output));
							callback(change);
						}
						break;
					case EventType.Mode:
						auto change = json["change"].str;
						auto pango_markup = JSON_TYPE.TRUE == json["pango_markup"].type;

						synchronized (p.mutex) foreach (cb; cast(Variant[]) p.eventCallbacks[EventType.Mode]) {
							auto callback = cb.get!(EventCallback!(EventType.Mode));
							callback(change, pango_markup);
						}
						break;
					case EventType.Window:
						auto change = fromJSON!WindowChange(json["change"]);
						auto container = Container(json["container"]);

						synchronized (p.mutex) foreach (cb; cast(Variant[]) p.eventCallbacks[EventType.Window]) {
							auto callback = cb.get!(EventCallback!(EventType.Window));
							callback(change, container);
						}
						break;
					case EventType.BarConfigUpdate:
						auto barConfig = BarConfig(json);

						synchronized (p.mutex) foreach (cb; cast(Variant[]) p.eventCallbacks[EventType.BarConfigUpdate]) {
							auto callback = cb.get!(EventCallback!(EventType.BarConfigUpdate));
							callback(barConfig);
						}
						break;
					case EventType.Binding:
						auto change = fromJSON!BindingChange(json["change"]);
						auto binding = Binding(json["binding"]);

						synchronized (p.mutex) foreach (cb; cast(Variant[]) p.eventCallbacks[EventType.Binding]) {
							auto callback = cb.get!(EventCallback!(EventType.Binding));
							callback(change, binding);
						}
						break;
					default: assert(0);
				}
			}
		});
		eventThread.isDaemon = true;

		p.eventThread = eventThread;
		this.p = p;

		eventThread.start();
	}

	JSONValue request(RequestType type, immutable(void)[] message = [])
	{
		i3ipc.send(p.requestSocket, type, message);

		auto responseHeader = i3ipc.receive!Header(p.requestSocket);
		auto response = i3ipc.fill(p.requestSocket, new ubyte[responseHeader.size]);
		
		enforce(reponseTypes[type] == responseHeader.type);
		return parseJSON(response);
	}

public:

	auto execute(string command)
	{
		return map!(json => CommandStatus(json))(request(RequestType.Command, command).array);
	}

	auto workspaces() @property
	{
		return map!(json => Workspace(json))(request(RequestType.GetWorkspaces).array);
	}

	void subscribe(alias T) (EventCallback!T callback)
		if (is(typeof(T) == EventType))
	{
		synchronized (p.mutex) {
			if (T !in p.eventCallbacks) i3ipc.send(p.eventSocket, RequestType.Subscribe, JSONValue([T.toString]).toString);
			p.eventCallbacks[T] ~= cast(shared(Variant[])) [Variant(callback)];
		}
	}

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

private:
	
	T receive(T)(Socket socket)
	{
		ptrdiff_t position = 0;
		ptrdiff_t amountRead = 0;
		ubyte[T.sizeof] buffer;

		while (position < buffer.length) {
			amountRead = socket.receive(buffer[position .. $]);
			enforce!SocketException(0 != amountRead, "Socket closed");
			position += amountRead;
		}

		return *(cast (T*) buffer);
	}

	ubyte[] fill(Socket socket, ubyte[] buffer)
	{
		ptrdiff_t position = 0;
		ptrdiff_t amountRead = 0;

		while (position < buffer.length) {
			amountRead = socket.receive(buffer[position .. $]);
			enforce!SocketException(0 != amountRead, "Socket closed");
			position += amountRead;
		}

		return buffer;
	}

	void send(Socket socket, RequestType type, immutable(void)[] message = [])
	{
		auto header = Header(to!uint(message.length), type);
		socket.send((cast(void*) &header)[0 .. Header.sizeof]);
		if (message.length) socket.send(message);
	}