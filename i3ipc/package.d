
module i3ipc;

import std.socket : UnixAddress;

import i3ipc.protocol;
import i3ipc.socket;
import i3ipc.data;
import i3ipc.connection;

Connection!T connect(T)(UnixAddress address = defaultIPCAddress)
{
	return Connection!T(address);
}

auto execute(string command)
{
	return connect!void.execute(command);
}

auto workspaces() @property
{
	return connect!void.workspaces;
}

auto outputs() @property
{
	return connect!void.outputs;
}

Container tree() @property
{
	return connect!void.tree;
}

auto marks() @property
{
	return connect!void.marks;
}

auto configuredBars() @property
{
	return connect!void.configuredBars;
}

auto getBarConfig(string id)
{
	return connect!void.getBarConfig(id);
}

auto version_()
{
	return connect!void.version_;
}

private UnixAddress defaultIPCAddress()
{
	import std.process : execute;

	auto result = execute(["i3", "--get-socketpath"]);
	enforce(0 == result.status);
	return new UnixAddress(result.output[0 .. $-1]);
}
