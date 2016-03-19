
module fibered;

import core.time : seconds, msecs, Duration;
import core.thread : Fiber, Thread, dur;

import std.range : repeat;
import std.algorithm : each;
import std.stdio : writeln;

import i3ipc;

void main(string[] args)
{
	auto c = i3ipc.connect!Fiber;

	c.subscribe!"Window"((change, binding) => writeln(change, " ", binding));

	writeln("Connection open for approximately 3 seconds, please generate some i3 window events!");
	100.msecs.repeat(3.seconds / 100.msecs).each!((timeSlice) {
		/+ For a fiber-backed connection one needs to periodically
		 + dispatch events coming in on the (non-blocking) socket.
		 +/
		c.dispatch;
		Thread.sleep(timeSlice);
	});
}
