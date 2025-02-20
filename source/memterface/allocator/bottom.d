/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
module memterface.allocator.bottom;

import core.exception;
import memterface.iface;

/**
The allocator that you place at the bottom of a chain of fallback allocators.
It never allocates, and is intended to fail any applicable operations.
*/
struct BottomAllocator{
	///Throws: `OutOfMemoryError` unconditionally.
	static void[] allocate(size_t size) nothrow @nogc pure @safe
	out(memory; memory.length == size){
		onOutOfMemoryError();
	}
	
	///Should never be called, since `isOwnerOf` always returns `false`.
	static void deallocate(void[] memory) nothrow @nogc pure @safe
	in(isOwnerOf(memory)){
		assert(0);
	}
	
	///Returns: `false`
	static bool isOwnerOf(void[] memory) nothrow @nogc pure @safe =>
		false;
	
	///Should never be called, since `isOwnerOf` always returns `false`.
	static void reallocate(ref void[] memory, size_t newSize) nothrow @nogc pure @safe
	in(isOwnerOf(memory))
	out(; memory.length == newSize){
		assert(0);
	}
	
	///Should never be called, since `isOwnerOf` always returns `false`.
	static size_t extend(ref void[] memory, size_t sizeDelta) nothrow @nogc pure @safe
	in(isOwnerOf(memory)){
		assert(0);
	}
}
static assert(isAllocator!BottomAllocator && hasReallocate!BottomAllocator && hasExtend!BottomAllocator);
