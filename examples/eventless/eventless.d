
module eventless;

import std.stdio : writeln;

import i3ipc;

void main(string[] args)
{
	/+ Open an eventless connection explicitly +/
	{
		auto c = i3ipc.connect!void;

		writeln(c.version_);
		writeln(c.outputs);
	}

	/+ Use API-provided wrappers
	 + Warning: These will open and close an eventless connection for every call
	 +/
	{
		writeln(i3ipc.version_);
		writeln(i3ipc.outputs);
	}
}
