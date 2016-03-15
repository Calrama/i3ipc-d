
module i3ipc.protocol;

align(1) struct Header
{
	align (1):
	/** Never change this, only on major IPC breakage (don’t do that) */
    char[6] magic = "i3-ipc";
    uint size;
	union
	{
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
		case EventType.Workspace: return "workspace"; break;
		case EventType.Output: return "output"; break;
		case EventType.Mode: return "mode"; break;
		case EventType.Window: return "window"; break;
		case EventType.BarConfigUpdate: return "barconfig_update"; break;
		case EventType.Binding: return "binding"; break;
		default: assert(0);
	}
}
