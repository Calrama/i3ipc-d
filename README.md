i3ipc-d
=======

**i3ipc-d** provides a high-level D API to the window manager [i3](http://i3wm.org/)'s [interprocess communication interface](https://i3wm.org/docs/ipc.html).

See [here](examples/fullapi/fullapi.d) for an example showing all available API methods and [here](examples) for all examples.
A connection in i3ipc-d has always exactly one of the following characteristics:
- [threaded](examples/threaded/threaded.d) (events are automatically dispatched by a dedicated thread),
- [fibered](examples/fibered/fibered.d) (events need to be explicitly dispatched by calling ```connection.dispatch```), or
- [eventless](examples/eventless/eventless.d) (events are not supported at all).

The following shows how to setup a threaded connection:

```d
module threaded;

import core.time : seconds;
import core.thread : Thread, dur;

import std.stdio : writeln;

import i3ipc;

void main(string[] args)
{
	auto connection = i3ipc.connect!Thread;

	connection.subscribe!"Workspace"((change, current, old) => writeln(change, " ", current, " ", old));

	writeln("Connection open for approximately 3 seconds, please generate some i3 workspace events!");
	/+ A thread-backed connection automatically dispatches events,
	 + this just delays program termination.
	 +/
	Thread.sleep(3.seconds);
}
```
