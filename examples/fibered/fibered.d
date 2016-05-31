
module fibered;

import i3ipc;

void main(string[] args)
{
	auto c = i3ipc.connect!FiberedConnection;

	c.subscribe!"Window"((change, binding) => writeln(change, " ", binding));

	writeln("Connection open for approximately 3 seconds, please generate some i3 window events!");
	foreach (timeSlice; 100.msecs.repeat(3.seconds / 100.msecs).array) {
		/+ For a fiber-backed connection one needs to periodically
		 + dispatch events coming in on the (non-blocking) socket.
		 +/
		c.dispatch;
		Thread.sleep(timeSlice);
	}
}

import core.thread;
import std.stdio;
import std.range;
import std.algorithm;
