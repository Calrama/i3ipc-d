
module i3ipc.protocol;

import std.exception : enforce;
import std.socket : Socket;
import std.conv : to;
import std.json : JSONValue, parseJSON;

import i3ipc.socket;

align(1) struct Header
{
	align (1):
	/** Never change this, only on major IPC breakage (don’t do that) */
    char[6] magic = "i3-ipc";
    uint payloadSize;
	union
	{
		uint rawType;
		RequestType requestType;
		ResponseType responseType;
		EventType eventType;
	}
}

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
		case EventType.Workspace: return "workspace";
		case EventType.Output: return "output";
		case EventType.Mode: return "mode";
		case EventType.Window: return "window";
		case EventType.BarConfigUpdate: return "barconfig_update";
		case EventType.Binding: return "binding";
		default: assert(0);
	}
}

void sendMessage(Socket socket, RequestType type, immutable(void)[] message = [])
{
    Header header;
    header.payloadSize = to!uint(message.length);
    header.requestType = type;
    socket.send((cast(void*) &header)[0 .. Header.sizeof]);
    if (message.length) socket.send(message);
}

JSONValue receiveMessage(Socket socket, ResponseType type)
{
	auto header = socket.receiveExactly!Header;
	auto payload = socket.receiveExactly(new ubyte[header.payloadSize]);

	enforce(type == header.responseType);
	return parseJSON(payload);
}
