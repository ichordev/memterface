/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.
*/
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
	out(memory; size > 0 ? isOwnerOf(memory) : memory is null) =>
		size > 0 ? GC.malloc(size)[0..size] : null;
	
	static void deallocate(void[] memory) nothrow @nogc pure @system
	in(isOwnerOf(memory)) =>
		GC.free(memory.ptr);
	
	static bool isOwnerOf(const(void)[] memory) nothrow @nogc pure @trusted =>
		memory.length && GC.sizeOf(cast(void*)memory.ptr) != 0;
	
	static void reallocate(ref void[] memory, size_t newSize) nothrow pure @system
	in(isOwnerOf(memory))
	out(; memory.length == newSize)
	out(; newSize > 0 ? isOwnerOf(memory) : memory is null){
		memory = GC.realloc(memory.ptr, newSize)[0..newSize];
	}
	
	/**
	In my experience, the GC never extends memory when asked
	(i.e. this always returns `memory.length` when `newSize > memory.length`),
	but your mileage may vary.
	*/
	static size_t resize(ref void[] memory, size_t newSize) nothrow pure @trusted
	in(isOwnerOf(memory))
	out(; isOwnerOf(memory))
	out(retSize; retSize == memory.length){
		if(newSize > memory.length){
			const sizeDelta = GC.extend(memory.ptr, 1, newSize - memory.length);
			memory = memory.ptr[0..memory.length + sizeDelta];
		}
		return memory.length;
	}
}
static assert(isAllocator!GCAllocator);
static assert(hasReallocate!GCAllocator);
static assert(hasResize!GCAllocator);
