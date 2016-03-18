
module i3ipc;

import std.socket : UnixAddress;

import i3ipc.protocol;
import i3ipc.socket;
import i3ipc.data;
import i3ipc.connection;

Connection!T connect(T)()
{
	import std.process : execute;

	auto result = execute(["i3", "--get-socketpath"]);
	enforce(0 == result.status);
	return Connection!T(new UnixAddress(result.output[0 .. $-1]));
}

Connection!T connect(T)(UnixAddress address)
{
	return Connection!T(address);
}
