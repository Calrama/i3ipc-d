
module threaded;

import core.time : seconds;
import core.thread : Thread, dur;

import std.stdio : writeln;

import i3ipc;

void main(string[] args)
{
	auto c = i3ipc.connect!Thread;

	c.subscribe!"Workspace"((change, current, old) => writeln(change, " ", current, " ", old));

	writeln("Connection open for approximately 3 seconds, please generate some i3 workspace events!");
	/+ A thread-backed connection automatically dispatches events,
	 + this just delays program termination.
	 +/
	Thread.sleep(3.seconds);
}
