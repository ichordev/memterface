/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
module memterface.allocator.gc;

import core.memory: GC;
import std.algorithm.comparison;
import memterface.iface;

/**
Allocates memory directly from D's built-in garbage collector using `core.memory.GC`.
*/
struct GCAllocator{
	static void[] allocate(size_t size) nothrow pure @trusted
	out(memory; memory.length == size)
	out(memory; memory is null || isOwnerOf(memory)) =>
		GC.malloc(size)[0..size];
	
	static void deallocate(void[] memory) nothrow @nogc pure
	in(isOwnerOf(memory)) =>
		GC.free(memory.ptr);
	
	static bool isOwnerOf(const(void)[] memory) nothrow @nogc pure @trusted =>
		GC.sizeOf(cast(void*)memory.ptr) != 0;
	
	static void reallocate(ref void[] memory, size_t newSize) nothrow pure
	in(isOwnerOf(memory))
	out(; memory.length == newSize){
		memory = GC.realloc(memory.ptr, newSize)[0..newSize];
	}
	
	/**
	In my experience, the GC never extends memory when asked
	(i.e. this always returns 0), but your mileage may vary.
	*/
	static size_t extend(ref void[] memory, size_t sizeDelta) nothrow pure @trusted
	in(isOwnerOf(memory)){
		auto newSize = GC.extend(memory.ptr, min(1, sizeDelta), sizeDelta);
		if(newSize == 0) return 0;
		assert(newSize >= memory.length && newSize <= memory.length + sizeDelta);
		auto newSizeDelta = newSize - memory.length;
		memory = memory.ptr[0..newSize];
		return newSizeDelta;
	}
}
static assert(isAllocator!GCAllocator);
static assert(hasReallocate!GCAllocator);
static assert(hasExtend!GCAllocator);
