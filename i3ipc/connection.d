
module i3ipc.connection;


struct Connection(T)
	if (is(T == Thread) || is(T == Fiber) || is(T == void))
{
private:
	static if (!is(T == void)) T worker;

	struct _Payload
	{
		Socket syncSocket;
		static if (!is(T == void)) {
			Socket asyncSocket;
			static if (is(T == Thread)) Mutex mutex;

			EventCallback!(EventType.Workspace)[] callbacksWorkspace;
			EventCallback!(EventType.Output)[] callbacksOutput;
			EventCallback!(EventType.Mode)[] callbacksMode;
			EventCallback!(EventType.Window)[] callbacksWindow;
			EventCallback!(EventType.BarConfigUpdate)[] callbacksBarConfigUpdate;
			EventCallback!(EventType.Binding)[] callbacksBinding;
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

	void delegate() onClosed;

public:

    this(UnixAddress address, void delegate() onClosed = null)
	{
		this.onClosed = onClosed;
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

	auto workspaces()
	{
		return map!(v => fromJSON!Workspace(v))(get(RequestType.GetWorkspaces).array);
	}

	template subscribe(string event)
	{
		enum Event = to!EventType(event);
		void subscribe(EventCallback!Event dg)
		{
			subscribe!Event(dg);
		}
	}

	void subscribe(EventType E)(EventCallback!E dg)
	{
		mixin(q{%2$s { if (p.callbacks%1$s.length == 0) {
					p.asyncSocket.sendMessage(RequestType.Subscribe, JSONValue([EventType.%1$s.toString]).toString);
				} p.callbacks%1$s ~= dg;
				}
				}.format(E, is(T == Thread) ? q{synchronized(p.mutex)} : ""));
	}

	auto outputs()
	{
		return map!(v => fromJSON!Output(v))(get(RequestType.GetOutputs).array);
	}

	auto tree()
	{
		return Container(get(RequestType.GetTree));
	}

	auto marks()
	{
		return map!(v => v.str)(get(RequestType.GetMarks).array);
	}

	auto configuredBars()
	{
		return map!(v => v.str)(get(RequestType.GetBarConfig).array);
	}

	auto getBarConfig(string id)
	{
		return BarConfig(get(RequestType.GetBarConfig, id));
	}

	auto version_()
	{
		return fromJSON!Version(get(RequestType.GetVersion));
	}

	static if (!is(T == void)) class EventListener : T
	{
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
			try
			{
				while (true) {
					auto header = connection.p.asyncSocket.receiveExactly!Header;
					auto payload = parseJSON(connection.p.asyncSocket.receiveExactly(new ubyte[header.payloadSize]));

					if (EventMask & header.rawType) switch (header.eventType) {
						mixin(zip(eventHandlers.keys, eventHandlers.values).map!q{q{
							case EventType.%1$s:
								%2$s
								%4$s
								connection.p.callbacks%1$s.each!((cb) {
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
			catch (SocketException e) {
				if (connection.onClosed !is null) {
					connection.onClosed();
				}
			}
		}
	}
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

import std.typecons;
import std.range;
import std.algorithm;
import std.array;

import std.format;
import std.json;

import std.socket;

import i3ipc.protocol;
import i3ipc.socket;
import i3ipc.data;
