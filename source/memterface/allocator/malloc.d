/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
module memterface.allocator.malloc;

import core.exception;
import core.memory: pureFree, pureMalloc, pureRealloc;
import memterface.iface;

/**
Allocates memory using C's `malloc`.

Warning: Does not implement `isOwnerOf` properly (it always returns `true`) due to
	limitations in the C standard library's API.
*/
struct CAllocator{
	///Wraps a call to `core.memory.pureMalloc`
	static void[] allocateImpl(size_t size) nothrow @nogc pure @trusted{
		auto ptr = pureMalloc(size);
		if(ptr)
			return ptr[0..size];
		else
			onOutOfMemoryError();
	}
	
	///Wraps a call to `core.memory.pureFree`
	static void deallocateImpl(void[] memory) nothrow @nogc pure @system =>
		pureFree(memory.ptr);
	
	///Wraps a call to `core.memory.pureRealloc`
	static void reallocateImpl(ref void[] memory, size_t newSize) nothrow @nogc pure @system{
		auto newPtr = pureRealloc(memory.ptr, newSize);
		if(newPtr)
			memory = newPtr[0..newSize];
		else
			onOutOfMemoryError();
	}
	
	import memterface.wrap;
	mixin ImplementIsOwnerOf!();
}
static assert(isAllocator!CAllocator);
static assert(hasReallocate!CAllocator);
