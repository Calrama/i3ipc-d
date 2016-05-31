
module i3ipc.connection;

struct QueryConnection
{
private:
	struct State
	{
		Socket socket;

		~this()
		{
			socket.close;
		}

		@disable this(this);
		void opAssign(State) { assert(false); }
	}
	alias StateRef = RefCounted!(State, RefCountedAutoInitialize.no);
	StateRef state;

	JSONValue query(RequestType type, immutable(void)[] message = [])
	{
		state.socket.sendMessage(type, message);
		return state.socket.receiveMessage(cast(ResponseType) type);
	}

public:
    this(UnixAddress address)
	{
		auto socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		socket.connect(address);
		state = StateRef(socket);
	}

	auto execute(string command)
	{
		return map!(v => fromJSON!CommandStatus(v))(query(RequestType.Command, command).array);
	}

	auto workspaces()
	{
		return map!(v => fromJSON!Workspace(v))(query(RequestType.GetWorkspaces).array);
	}

	auto outputs()
	{
		return map!(v => fromJSON!Output(v))(query(RequestType.GetOutputs).array);
	}

	auto tree()
	{
		return Container(query(RequestType.GetTree));
	}

	auto marks()
	{
		return map!(v => v.str)(query(RequestType.GetMarks).array);
	}

	auto configuredBars()
	{
		return map!(v => v.str)(query(RequestType.GetBarConfig).array);
	}

	auto getBarConfig(string id)
	{
		return BarConfig(query(RequestType.GetBarConfig, id));
	}

	auto version_()
	{
		return fromJSON!Version(query(RequestType.GetVersion));
	}
}

alias FiberedConnection = EventConnection!Fiber;
alias ThreadedConnection = EventConnection!Thread;
private struct EventConnection(Listener)
	if (is(Listener == Thread) || is(Listener == Fiber))
{
private:
	Listener listener;

	struct State
	{
		Socket socket;
		Mutex mutex;

		UnixAddress address;

		EventCallback!(EventType.Workspace)[] WorkspaceCallbacks;
		EventCallback!(EventType.Output)[] OutputCallbacks;
		EventCallback!(EventType.Mode)[] ModeCallbacks;
		EventCallback!(EventType.Window)[] WindowCallbacks;
		EventCallback!(EventType.BarConfigUpdate)[] BarConfigUpdateCallbacks;
		EventCallback!(EventType.Binding)[] BindingCallbacks;

		~this()
		{ socket.close; }

		@disable this(this);
		void opAssign(State) { assert(false); }
	}
	alias StateRef = RefCounted!(State, RefCountedAutoInitialize.no);
	StateRef state;

	void connect(UnixAddress address)
	{
		if (state.address != address) state.address = address;
		state.socket.connect(address);

		if (state.WorkspaceCallbacks.length > 0) {
			state.socket.sendMessage(RequestType.Subscribe, JSONValue("Workspace").toString);
		}
		if (state.OutputCallbacks.length > 0) {
			state.socket.sendMessage(RequestType.Subscribe, JSONValue("Output").toString);
		}
		if (state.ModeCallbacks.length > 0) {
			state.socket.sendMessage(RequestType.Subscribe, JSONValue("Mode").toString);
		}
		if (state.WindowCallbacks.length > 0) {
			state.socket.sendMessage(RequestType.Subscribe, JSONValue("Window").toString);
		}
		if (state.BarConfigUpdateCallbacks.length > 0) {
			state.socket.sendMessage(RequestType.Subscribe, JSONValue("BarConfigUpdate").toString);
		}
		if (state.BindingCallbacks.length > 0) {
			state.socket.sendMessage(RequestType.Subscribe, JSONValue("Binding").toString);
		}
	}

public:
    this(UnixAddress address)
	{
		auto socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		static if (is(Listener == Fiber)) socket.blocking = false;
		state = StateRef(socket, new Mutex, address);
		connect(state.address);
		listener = new ListenerImpl(this);
		static if (is(Listener == Thread)) listener.start;
	}

	static if (is(Listener == Fiber)) void dispatch()
	{ listener.call; }

	template subscribe(string event)
	{
		enum Event = to!EventType(event);
		void subscribe(EventCallback!Event cb)
		{ subscribe!Event(cb); }
	}

	void subscribe(EventType E)(EventCallback!E cb)
	{
		synchronized (state.mutex) {
			if (0 == mixin("state.%sCallbacks.length".format(E))) {
				state.socket.sendMessage(RequestType.Subscribe, JSONValue([E.toString]).toString);
			}
			mixin("state.%sCallbacks".format(E)) ~= cb;
		}
	}

	static class ListenerImpl : Listener
	{
		alias Connection = EventConnection!Listener;
		private Connection connection;

		this(Connection connection)
		{
			this.connection = connection;
			super(&listen);
		}

		void listen()
		{
			static if (is(Listener == Thread)) isDaemon = true;

			try while (true) {
				try
				{
					auto header = connection.state.socket.receiveExactly!Header;
					auto payload = parseJSON(connection.state.socket.receiveExactly(new ubyte[header.payloadSize]));

					if (EventMask & header.rawType) handle(header, payload);
					else if (header.responseType == ResponseType.Subscribe) {}
					else assert(0);
				}
				catch (SocketException e) {
					info(e);
					warning("Lost connection to i3, trying to reestablish in approximately 10 milliseconds");
					Thread.getThis.sleep(10.msecs);
					connection.connect(connection.state.address);
				}
			}
			catch (Exception e) {
				error(e);
			}
		}

		void handle(Header header, JSONValue payload)
		{
			switch (header.eventType) with(EventType)
			{
				case Workspace:
					auto change = fromJSON!WorkspaceChange(payload["change"]);
					auto current = Container(payload["current"]);
					Nullable!Container old;
					if (!payload["old"].isNull) old = Container(payload["old"]);

					foreach (cb; connection.state.WorkspaceCallbacks) cb(change, current, old);
					break;
				case Output:
					auto change = fromJSON!OutputChange(payload["change"]);

					foreach (cb; connection.state.OutputCallbacks) cb(change);
					break;
				case Mode:
					auto change = payload["change"].str;
					auto pango_markup = JSON_TYPE.TRUE == payload["pango_markup"].type;

					foreach (cb; connection.state.ModeCallbacks) cb(change, pango_markup);
					break;
				case Window:
					auto change = fromJSON!WindowChange(payload["change"]);
					auto container = Container(payload["container"]);

					foreach (cb; connection.state.WindowCallbacks) cb(change, container);
					break;
				case BarConfigUpdate:
					auto barConfig = BarConfig(payload);

					foreach (cb; connection.state.BarConfigUpdateCallbacks) cb(barConfig);
					break;
				case Binding:
					auto change = fromJSON!BindingChange(payload["change"]);
					auto binding = fromJSON!(i3ipc.data.Binding)(payload["binding"]);

					foreach (cb; connection.state.BindingCallbacks) cb(change, binding);
					break;
				default: assert(0);
			}
		}
	}
}

UnixAddress getSessionIPCAddress()
{
	auto result = execute(["i3", "--get-socketpath"]);
	enforce(0 == result.status);
	return new UnixAddress(result.output[0 .. $-1]);
}

template EventCallback(EventType T) if (T == EventType.Workspace)
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


import core.sync.mutex;
import core.thread;

import std.traits;
import std.exception;

import std.variant;
import std.typecons;
import std.range;
import std.algorithm;
import std.array;

import std.conv;
import std.format;
import std.json;
import std.experimental.logger;

import std.process;
import std.socket;
import std.stdio;

import i3ipc.protocol;
import i3ipc.socket;
import i3ipc.data;
