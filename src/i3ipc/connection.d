
module i3ipc.connection;

import core.thread : Fiber, Thread;

import std.traits : EnumMembers;
import std.exception : enforce;

import std.typecons : Nullable, Tuple;
import std.algorithm : map, joiner, each;
import std.array : array;

import std.format : format;
import std.json : parseJSON;

import std.socket : UnixAddress, Socket;

import i3ipc.protocol;
import i3ipc.socket;
import i3ipc.data;

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

	JSONValue request(RequestType type, immutable(void)[] message = [])
	{
		auto socket = p.requestSocket;

		socket.sendMessage(type, message);

		auto header = socket.receiveExactly!Header;
		auto payload = socket.receiveExactly(new ubyte[header.payloadSize]);

		// This is valid only because corresponding request and response types match uint values
		enforce(type == header.responseType);
		return parseJSON(payload);
	}

public:

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

	void dispatch()
	{
		eventFiber.call();
	}

	auto execute(string command)
	{
		return map!(v => fromJSON!CommandStatus(v))(request(RequestType.Command, command).array);
	}

	auto workspaces() @property
	{
		return map!(v => fromJSON!Workspace(v))(request(RequestType.GetWorkspaces).array);
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
		return map!(v => fromJSON!Output(v))(request(RequestType.GetOutputs).array);
	}

	Container tree() @property
	{
		return Container(request(RequestType.GetTree));
	}

	auto marks() @property
	{
		return map!(v => v.str)(request(RequestType.GetMarks).array);
	}

	auto configuredBars() @property
	{
		return map!(v => v.str)(request(RequestType.GetBarConfig).array);
	}

	auto getBarConfig(string id)
	{
		return BarConfig(request(RequestType.GetBarConfig, id));
	}

	Version version_() @property
	{
		return fromJSON!Version(request(RequestType.GetVersion));
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
			auto payload = parseJSON(connection.p.eventSocket.receiveExactly(new ubyte[header.payloadSize]));

			if (ResponseType.Subscribe == header.responseType) {
				continue;
			}

			switch (header.eventType) {
				case EventType.Workspace:
					auto change = fromJSON!WorkspaceChange(payload["change"]);
					auto current = Container(payload["current"]);
					Nullable!Container old;
					if (!payload["old"].isNull) old = Container(payload["old"]);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Workspace]) {
						auto callback = cb.get!(EventCallback!(EventType.Workspace));
						callback(change, current, old);
					}
					break;
				case EventType.Output:
					auto change = fromJSON!OutputChange(payload["change"]);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Output]) {
						auto callback = cb.get!(EventCallback!(EventType.Output));
						callback(change);
					}
					break;
				case EventType.Mode:
					auto change = payload["change"].str;
					auto pango_markup = JSON_TYPE.TRUE == payload["pango_markup"].type;

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Mode]) {
						auto callback = cb.get!(EventCallback!(EventType.Mode));
						callback(change, pango_markup);
					}
					break;
				case EventType.Window:
					auto change = fromJSON!WindowChange(payload["change"]);
					auto container = Container(payload["container"]);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.Window]) {
						auto callback = cb.get!(EventCallback!(EventType.Window));
						callback(change, container);
					}
					break;
				case EventType.BarConfigUpdate:
					auto barConfig = BarConfig(payload);

					synchronized (connection.mutex) foreach (cb; cast(Variant[]) connection.p.eventCallbacks[EventType.BarConfigUpdate]) {
						auto callback = cb.get!(EventCallback!(EventType.BarConfigUpdate));
						callback(barConfig);
					}
					break;
				case EventType.Binding:
					auto change = fromJSON!BindingChange(payload["change"]);
					auto binding = fromJSON!Binding(payload["binding"]);

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
