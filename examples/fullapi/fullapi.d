
module fullapi;

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

	/+ Use a thread-backed connection for events
	 + and a query connection for synchronous queries. +/
	auto query_c = i3ipc.connect!QueryConnection;
	auto event_c = i3ipc.connect!ThreadedConnection;

	/+ Subscribe a callback to each possible event +/
	event_c.subscribe!"Workspace"((change, current, old) => writeln(change, " ", current, " ", old));
	event_c.subscribe!"Output"((change) => writeln(change));
	event_c.subscribe!"Mode"((change, pango_markup) => writeln(change, " ", pango_markup));
	event_c.subscribe!"Window"((change, container) => writeln(change, " ", container));
	event_c.subscribe!"BarConfigUpdate"((barConfig) => writeln(barConfig));
	event_c.subscribe!"Binding"((change, binding) => writeln(change, " ", binding));

	/+ The same as the convenience wrappers above, only for an already open connection +/
	{
		writeln(query_c.workspaces);
		writeln(query_c.outputs);
		writeln(query_c.tree);
		writeln(query_c.marks);
		auto configuredBars = query_c.configuredBars;
		writeln(configuredBars);
		configuredBars.each!((configuredBar) => writeln(query_c.getBarConfig(configuredBar)));
		writeln(query_c.version_);
	}

	writeln("Connection open for approximately 3 seconds, please generate some i3 events!");
	/+ A thread-backed connection automatically dispatches events,
	 + this just delays program termination.
	 +/
	Thread.sleep(3.seconds);
}

import core.thread;

import std.algorithm;
import std.stdio;
