
module threaded;

import i3ipc;

void main(string[] args)
{
	auto c = i3ipc.connect!ThreadedConnection;

	c.subscribe!"Workspace"((change, current, old) => writeln(change, " ", current, " ", old));

	writeln("Connection open for approximately 3 seconds, please generate some i3 workspace events!");
	/+ A thread-backed connection automatically dispatches events,
	 + this just delays program termination.
	 +/
	Thread.sleep(3.seconds);
}

import core.thread;
import std.stdio;
