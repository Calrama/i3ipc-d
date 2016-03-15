
module i3ipc.socket;

import core.time : Duration, dur;
import core.thread : Fiber, Thread;

import std.socket : Socket, SocketException, wouldHaveBlocked;
import std.exception : enforce;

ubyte[] receiveExactly(Socket socket, ubyte[] buffer, Duration spinDelay = dur!"msecs"(100))
{
	ptrdiff_t position = 0;
	ptrdiff_t amountRead = 0;

	while (position < buffer.length) {
		amountRead = socket.receive(buffer[position .. $]);
		enforce!SocketException(0 != amountRead, "Remote closed socket prematurely");
		if (Socket.ERROR == amountRead) {
			enforce!SocketException(wouldHaveBlocked, socket.getErrorText);
			if (Fiber.getThis !is null) {
				Fiber.yield;
			} else {
				Thread.sleep(spinDelay);
			}
		} else {
			position += amountRead;
		}
	}

	return buffer;
}

T receiveExactly(T)(Socket socket)
	if (is(T == struct))
{
	ubyte[T.sizeof] buffer;
	return *(cast (T*) socket.receiveExactly(buffer));
}
