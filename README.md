i3ipc-d
=======

**i3ipc-d** provides a high-level D API to the window manager [i3](http://i3wm.org/)'s [interprocess communication interface](https://i3wm.org/docs/ipc.html).

See [here](examples) for the examples, one of which is this:

```d
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
```
