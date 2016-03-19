
module fullapi;

import core.time : seconds;
import core.thread : Thread, dur;

import std.algorithm : each;
import std.stdio : writeln;

import i3ipc;

void main(string[] args)
{
	/+ All convenience wrappers for synchronous requests.
	 + Warning: Each of these will open and close an eventless connection +/
	//writeln(i3ipc.execute("reload"));
	{
		writeln(i3ipc.workspaces);
		writeln(i3ipc.outputs);
		writeln(i3ipc.tree);
		writeln(i3ipc.marks);
		auto configuredBars = i3ipc.configuredBars;
		writeln(configuredBars);
		configuredBars.each!((configuredBar) => writeln(i3ipc.getBarConfig(configuredBar)));
		writeln(i3ipc.version_);
	}

	/+ Use a thread-backed connection; others would be analogous
	 + (except that an eventless connection has no subscribe method)
	 +/
	auto c = i3ipc.connect!Thread;

	/+ Subscribe a callback to each possible event +/
	c.subscribe!"Workspace"((change, current, old) => writeln(change, " ", current, " ", old));
	c.subscribe!"Output"((change) => writeln(change));
	c.subscribe!"Mode"((change, pango_markup) => writeln(change, " ", pango_markup));
	c.subscribe!"Window"((change, container) => writeln(change, " ", container));
	c.subscribe!"BarConfigUpdate"((barConfig) => writeln(barConfig));
	c.subscribe!"Binding"((change, binding) => writeln(change, " ", binding));

	/+ The same as the convenience wrappers above, only for an already open connection +/
	{
		writeln(c.workspaces);
		writeln(c.outputs);
		writeln(c.tree);
		writeln(c.marks);
		auto configuredBars = c.configuredBars;
		writeln(configuredBars);
		configuredBars.each!((configuredBar) => writeln(c.getBarConfig(configuredBar)));
		writeln(c.version_);
	}

	writeln("Connection open for approximately 3 seconds, please generate some i3 events!");
	/+ A thread-backed connection automatically dispatches events,
	 + this just delays program termination.
	 +/
	Thread.sleep(3.seconds);
}
