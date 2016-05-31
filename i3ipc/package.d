
module i3ipc;

Connection connect(Connection)(UnixAddress address = getSessionIPCAddress)
{
	return Connection(address);
}

auto execute(string command)
{
	return connect!QueryConnection.execute(command);
}

auto workspaces()
{
	return connect!QueryConnection.workspaces;
}

auto outputs()
{
	return connect!QueryConnection.outputs;
}

Container tree()
{
	return connect!QueryConnection.tree;
}

auto marks()
{
	return connect!QueryConnection.marks;
}

auto configuredBars()
{
	return connect!QueryConnection.configuredBars;
}

auto getBarConfig(string id)
{
	return connect!QueryConnection.getBarConfig(id);
}

auto version_()
{
	return connect!QueryConnection.version_;
}

import std.socket : UnixAddress;
import std.exception : enforce;

import i3ipc.protocol;
import i3ipc.socket;
import i3ipc.data;
import i3ipc.connection;
public import i3ipc.connection : QueryConnection,
                                 FiberedConnection,
								 ThreadedConnection;
