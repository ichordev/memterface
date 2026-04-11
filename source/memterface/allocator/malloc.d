/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.
*/
module memterface.allocator.malloc;

import memterface.iface;

/**
Allocates memory using C's `malloc`.

Warning: Does not implement `isOwnerOf` properly (it always returns `true`) due to
	limitations in the C standard library's API.
*/
struct CAllocator{
	import core.exception: onOutOfMemoryError;
	import core.memory: pureFree, pureMalloc, pureRealloc;
	
	///Wraps a call to `core.memory.pureMalloc`
	static void[] allocateImpl(size_t size) nothrow @nogc pure @trusted{
		if(size > 0){
			if(auto ptr = pureMalloc(size))
				return ptr[0..size];
			else
				onOutOfMemoryError();
		}else{
			return null;
		}
	}
	
	///Wraps a call to `core.memory.pureFree`
	static void deallocateImpl(void[] memory) nothrow @nogc pure @system =>
		pureFree(memory.ptr);
	
	///Wraps a call to `core.memory.pureRealloc`
	static void reallocateImpl(ref void[] memory, size_t newSize) nothrow @nogc pure @system{
		if(newSize > 0){
			if(auto newPtr = pureRealloc(memory.ptr, newSize))
				memory = newPtr[0..newSize];
			else
				onOutOfMemoryError();
		}else{
			deallocateImpl(memory);
			memory = null;
		}
	}
	
	import memterface.wrap;
	mixin ImplementIsOwnerOf!();
}
static assert(isAllocator!CAllocator);
static assert(hasReallocate!CAllocator);
