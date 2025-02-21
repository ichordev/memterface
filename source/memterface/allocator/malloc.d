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
	static void[] allocate(size_t size) nothrow @nogc pure @trusted
	out(memory; memory.length == size)
	out(memory; memory is null || isOwnerOf(memory)){
		auto ptr = pureMalloc(size);
		if(ptr)
			return ptr[0..size];
		else
			onOutOfMemoryError();
	}
	
	///Wraps a call to `core.memory.pureFree`
	static void deallocate(void[] memory) nothrow @nogc pure @system
	in(isOwnerOf(memory)) =>
		pureFree(memory.ptr);
	
	/**
	Warning: This function lies by always returning `true` if `memory` is not `null`!
	
	Unfortunately there is no way to check if `malloc` allocated a pointer, so we must
	implement this method incorrectly. This means that calling `deallocate` or `reallocate`
	with `memory` may result in undefined behaviour!
	*/
	static bool isOwnerOf(const(void)[] memory) nothrow @nogc pure @system =>
		memory.ptr !is null;
	
	///Wraps a call to `core.memory.pureRealloc`
	static void reallocate(ref void[] memory, size_t newSize) nothrow @nogc pure @system
	in(isOwnerOf(memory))
	out(; memory.length == newSize){
		auto newPtr = pureRealloc(memory.ptr, newSize);
		if(newPtr)
			memory = newPtr[0..newSize];
		else
			onOutOfMemoryError();
	}
}
static assert(isAllocator!CAllocator);
static assert(hasReallocate!CAllocator);
