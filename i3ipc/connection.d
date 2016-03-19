
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

struct Connection(T)
	if (is(T == Thread) || is(T == Fiber) || is(T == void))
{
private:
	import std.variant : Variant;

	import std.typecons : RefCounted, RefCountedAutoInitialize;
	import std.socket : AddressFamily, SocketType;

	import std.container.dlist : DList;
	import core.sync.mutex : Mutex;

	static if (!is(T == void)) T worker;

	struct _Payload
	{
		Socket syncSocket;
		static if (!is(T == void)) {
			Socket asyncSocket;
			static if (is(T == Thread)) Mutex mutex;
			DList!Variant[EventType] eventCallbacks;
		}

		~this()
		{
			syncSocket.close;
			static if (!is(T == void)) asyncSocket.close;
		}

		@disable this(this);
		void opAssign(_Payload) { assert(false); }
	}
	alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
	Payload p;

	JSONValue get(RequestType type, immutable(void)[] message = [])
	{
		p.syncSocket.sendMessage(type, message);
		return p.syncSocket.receiveMessage(cast(ResponseType) type);
	}

public:

    this(UnixAddress address)
	{
		auto syncSocket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		syncSocket.connect(address);

		auto asyncSocket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
		static if (is(T == Fiber)) {
			asyncSocket.blocking = false;
		}
		asyncSocket.connect(address);

		static if (is(T == void)) {
			p = Payload(syncSocket);
		} else static if (is(T == Fiber)) {
			p = Payload(syncSocket, asyncSocket);
		} else static if (is(T == Thread)) {
			p = Payload(syncSocket, asyncSocket, new Mutex);
		}

		static if (!is(T == void)) {
			worker = new EventListener(this);
			static if (is(T == Thread)) {
				worker.start();
			}
		}
	}

	static if (is(T == Fiber)) void dispatch()
	{
		worker.call();
	}

	auto execute(string command)
	{
		return map!(v => fromJSON!CommandStatus(v))(get(RequestType.Command, command).array);
	}

	auto workspaces() @property
	{
		return map!(v => fromJSON!Workspace(v))(get(RequestType.GetWorkspaces).array);
	}

	static if (!is(T == void)) mixin((cast(EventType[]) [ EnumMembers!EventType ])
		.map!((EventType eventType) => q{
			void subscribe(string eventType)(EventCallback!(EventType.%1$s) callback)
				if ("%1$s" == eventType)
			{
				%2$s
				{
					if (EventType.%1$s !in p.eventCallbacks) {
						p.eventCallbacks[EventType.%1$s] = DList!Variant();
						p.asyncSocket.sendMessage(RequestType.Subscribe, JSONValue([EventType.%1$s.toString]).toString);
					}
					p.eventCallbacks[EventType.%1$s] ~= Variant(callback);
				}
			}}.format(eventType, is(T == Thread) ? q{ synchronized (p.mutex) } : "")).joiner.array);

	auto outputs() @property
	{
		return map!(v => fromJSON!Output(v))(get(RequestType.GetOutputs).array);
	}

	auto tree() @property
	{
		return Container(get(RequestType.GetTree));
	}

	auto marks() @property
	{
		return map!(v => v.str)(get(RequestType.GetMarks).array);
	}

	auto configuredBars() @property
	{
		return map!(v => v.str)(get(RequestType.GetBarConfig).array);
	}

	auto getBarConfig(string id)
	{
		return BarConfig(get(RequestType.GetBarConfig, id));
	}

	auto version_() @property
	{
		return fromJSON!Version(get(RequestType.GetVersion));
	}

	static if (!is(T == void)) class EventListener : T
	{
		import std.typecons : tuple;
		import std.range : zip;

		this(Connection!T connection) {
			super(&run);
			this.connection = connection;
			static if (is(T == Thread)) {
				isDaemon = true;
			}
		}

	private:
		Connection!T connection;

		enum eventHandlers = [
			EventType.Workspace : tuple(
				q{
					auto change = fromJSON!WorkspaceChange(payload["change"]);
					auto current = Container(payload["current"]);
					Nullable!Container old;
					if (!payload["old"].isNull) old = Container(payload["old"]);
				},
				q{ cb(change, current, old); }
			),
			EventType.Output : tuple(
				q{ auto change = fromJSON!OutputChange(payload["change"]); },
				q{ cb(change); }
			),
			EventType.Mode : tuple(
				q{
					auto change = payload["change"].str;
					auto pango_markup = JSON_TYPE.TRUE == payload["pango_markup"].type;
				},
				q{ cb(change, pango_markup); }
			),
			EventType.Window : tuple(
				q{
					auto change = fromJSON!WindowChange(payload["change"]);
					auto container = Container(payload["container"]);
				},
				q{ cb(change, container); }
			),
			EventType.BarConfigUpdate : tuple(
				q{ auto barConfig = BarConfig(payload); },
				q{ cb(barConfig); }
			),
			EventType.Binding : tuple(
				q{
					auto change = fromJSON!BindingChange(payload["change"]);
					auto binding = fromJSON!Binding(payload["binding"]);
				},
				q{ cb(change, binding); }
			)
		];

		void run()
		{
			while (true) {
				auto header = connection.p.asyncSocket.receiveExactly!Header;
				auto payload = parseJSON(connection.p.asyncSocket.receiveExactly(new ubyte[header.payloadSize]));

				if (EventMask & header.rawType) switch (header.eventType) {
					mixin(zip(eventHandlers.keys, eventHandlers.values).map!q{q{
						case EventType.%1$s:
							%2$s
							%4$s
							connection.p.eventCallbacks[EventType.%1$s].each!((v) {
								auto cb = v.get!(EventCallback!(EventType.%1$s));
								%3$s
							});
							break;
						}.format(a[0], a[1][0], a[1][1], is(T == Thread) ? q{ synchronized (p.mutex) } : "")}.joiner.array);
					default: assert(0);
				} else switch (header.responseType) {
					case ResponseType.Subscribe:
						continue;
					default: assert(0);
				}
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
