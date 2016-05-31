
module query;

import i3ipc;

void main(string[] args)
{
	/+ Open a query connection explicitly +/
	{
		auto c = i3ipc.connect!QueryConnection;

		writeln(c.version_);
		writeln(c.outputs);
	}

	/+ Use API-provided wrappers
	 + Warning: These will open and close a query connection for every call
	 +/
	{
		writeln(i3ipc.version_);
		writeln(i3ipc.outputs);
	}
}

import std.stdio;
