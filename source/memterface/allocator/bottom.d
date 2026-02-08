/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.
*/
module memterface.allocator.bottom;

import core.exception;
import memterface.iface;

/**
The allocator that you place at the bottom of a chain of fallback allocators.
It never allocates, and is intended to fail any applicable operations.
*/
struct BottomAllocator{
	/**
	Always asserts, since this allocator can't allocate anything.
	
	Throws: `OutOfMemoryError` unconditionally (when preconditions are disabled).
	*/
	static void[] allocate(size_t size) nothrow @nogc pure @safe
	out(memory; memory.length == size)
	out(memory; (size == 0 && memory is null) || isOwnerOf(memory))
	in(canAllocate(size)){
		onOutOfMemoryError();
	}
	
	/**
	Should never be reached in practice, since programmers should check `isOwnerOf` beforehand.
	
	Throws: `AssertError` unconditionally, since this allocator doesn't own any memory.
	*/
	static void deallocate(void[] memory) nothrow @nogc pure @safe
	in(isOwnerOf(memory)){
		assert(0);
	}
	
	///Returns: `false`
	static bool isOwnerOf(const(void)[] memory) nothrow @nogc pure @safe =>
		false;
	
	/**
	Should never be reached in practice, since programmers should check `isOwnerOf` beforehand.
	
	Throws: `AssertError` unconditionally, since this allocator doesn't own any memory.
	*/
	static void reallocate(ref void[] memory, size_t newSize) nothrow @nogc pure @safe
	in(isOwnerOf(memory))
	out(; (newSize == 0 && memory is null) || isOwnerOf(memory))
	out(; memory.length == newSize)
	in(canAllocate(newSize)){
		assert(0);
	}
	
	/**
	Should never be reached in practice, since programmers should check `isOwnerOf` beforehand.
	
	Throws: `AssertError` unconditionally, since this allocator doesn't own any memory.
	*/
	static size_t extend(ref void[] memory, size_t sizeDelta) nothrow @nogc pure @safe
	in(isOwnerOf(memory))
	out(returnedSizeDelta; returnedSizeDelta <= sizeDelta){
		assert(0);
	}
	
	///Returns: `false`
	static bool canAllocate(size_t size) nothrow @nogc pure @safe =>
		false;
}
static assert(isAllocator!BottomAllocator);
static assert(hasReallocate!BottomAllocator);
static assert(hasExtend!BottomAllocator);
static assert(hasCanAllocate!BottomAllocator);
