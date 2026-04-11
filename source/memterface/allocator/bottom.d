/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.
*/
module memterface.allocator.bottom;
import memterface.iface;

/**
The allocator that you place at the bottom of a chain of fallback allocators.
It never allocates, and is intended to fail any applicable operations.
*/
struct BottomAllocator{
	/**
	Always throws an error, since this allocator can't allocate anything.
	
	Throws: `OutOfMemoryError` unconditionally (when preconditions are disabled).
	*/
	static void[] allocate(size_t size) nothrow @nogc pure @safe
	out(memory; memory.length == size)
	out(memory; size > 0 ? isOwnerOf(memory) : memory is null){
		import core.exception: onOutOfMemoryError;
		if(size > 0) onOutOfMemoryError();
		return null;
	}
	
	/**
	Should never be reached in practice, since programmers should check `isOwnerOf` beforehand.
	*/
	static void deallocate(void[] memory) nothrow @nogc pure @safe
	in(isOwnerOf(memory)) =>
		assert(0);
	
	///Returns: `false`
	static bool isOwnerOf(const(void)[] memory) nothrow @nogc pure @safe =>
		false;
	
	/**
	Should never be reached in practice, since programmers should check `isOwnerOf` beforehand.
	*/
	static void reallocate(ref void[] memory, size_t newSize) nothrow @nogc pure @safe
	in(isOwnerOf(memory))
	out(; memory.length == newSize)
	out(; newSize > 0 ? isOwnerOf(memory) : memory is null) =>
		assert(0);
	
	/**
	Should never be reached in practice, since programmers should check `isOwnerOf` beforehand.
	*/
	static size_t resize(ref void[] memory, size_t newSize) nothrow @nogc pure @safe
	in(isOwnerOf(memory))
	out(; isOwnerOf(memory)) =>
		assert(0);
	
	///Returns: `false`
	static bool canAllocate(size_t size) nothrow @nogc pure @safe
	out(ret; size > 0 || ret) =>
		size == 0;
}
static assert(isAllocator!BottomAllocator);
static assert(hasReallocate!BottomAllocator);
static assert(hasResize!BottomAllocator);
static assert(hasCanAllocate!BottomAllocator);
