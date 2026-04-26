/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.
*/
module memterface.allocator.malloc;

import memterface.iface;

/**
Allocates memory using the C standard library's `malloc`.
*/
struct CAllocator{
	import core.exception: onOutOfMemoryError;
	import core.memory: pureFree, pureMalloc, pureRealloc;
	
	private pragma(inline,true){
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
		
		static void deallocateImpl(void[] memory) nothrow @nogc pure @system =>
			pureFree(memory.ptr);
		
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
	}
	version(NativeIsOwnerOf){
		///Wraps a call to `core.memory.pureMalloc`
		static void[] allocate(size_t size) nothrow @nogc pure @safe
		out(memory; memory.length == size)
		out(memory; size > 0 ? isOwnerOf(memory) : memory is null) =>
			allocateImpl(size);
		
		///Wraps a call to `core.memory.pureFree`
		static void deallocate(void[] memory) nothrow @nogc pure @system
		in(isOwnerOf(memory)) =>
			deallocateImpl(memory);
		
		/**
		On some systems, it is implemented natively; otherwise it is
		implemented with `ImplementIsOwnerOf`.
		
		- Apple platforms use `malloc_size`.
		- Linux and FreeBSD use `malloc_usable_size`.
		- Windows uses `_msize`.
		*/
		static bool isOwnerOf(const(void)[] memory) nothrow @nogc pure @safe{
			if(memory.length > 0){
				version(Apple){
					return (() @trusted => malloc_size(memory.ptr))() >= memory.length;
				}else version(linux){
					return (() @trusted => malloc_usable_size(cast(void*)memory.ptr))() >= memory.length;
				}else version(FreeBSD){
					return (() @trusted => malloc_usable_size(memory.ptr))() >= memory.length;
				}else version(Windows){
					const size = () @trusted{
						const errnosave = fakePureErrno;
						scope(exit) fakePureErrno = errnosave;
						return _msize(memory);
					}();
					return
						size != cast(size_t)-1 &&
						size >= memory.length; //TODO: check whether this function might return exactly the size that was passed to `malloc`
				}
			}
			return false;
		}
		
		///Wraps a call to `core.memory.pureRealloc`
		static void reallocate(ref void[] memory, size_t newSize) nothrow @nogc pure @system
		in(isOwnerOf(memory))
		out(; memory.length == newSize)
		out(; newSize > 0 ? isOwnerOf(memory) : memory is null) =>
			reallocateImpl(memory, newSize);
	}else{
		import memterface.wrap;
		mixin ImplementIsOwnerOf!();
	}
}
static assert(isAllocator!CAllocator);
static assert(hasReallocate!CAllocator);

private{
	version(Apple){
		//from <malloc/malloc.h>
		extern(C) size_t malloc_size(const(void)* ptr) nothrow @nogc pure @system;
		
		version = NativeIsOwnerOf;
	}version(linux){
		//from <malloc.h>
		size_t malloc_usable_size(void* ptr) nothrow @nogc pure @system;
		
		version = NativeIsOwnerOf;
	}else version(FreeBSD){
		//from <malloc_np.h>
		size_t malloc_usable_size(const(void)* ptr) nothrow @nogc pure @system;
		
		version = NativeIsOwnerOf;
	}else version(Windows){
		extern(Windows) size_t _msize(void* memblock) nothrow @nogc pure @system;
		
		static import core.stdc.errno;
		extern(C) pragma(mangle, __traits(identifier, core.stdc.errno.errno))
		ref int fakePureErrno() nothrow @nogc pure @system;
		
		version = NativeIsOwnerOf;
	}else version(D_Ddoc){
		version = NativeIsOwnerOf;
	}
}
