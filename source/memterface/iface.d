/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
/++
Interfaces for generic allocators.

Allocators must follow the *interface* of `AllocatorInterface` (see below). However, making allocators
using class inheritance is **not recommended**. Instead, it is best to use `struct`s and use them with
template parameters and the constraint `isAllocator`:
```
//A custom allocator:
struct MyAllocator{
	void[] allocate(size_t size) nothrow{
		//return allocated memory
	}
	
	void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory)){
		//deallocate passed memory
	}
	
	bool isOwnerOf(void[] memory) nothrow{
		//return whether this allocator owns the passed memory
	}
}

//A struct using an allocator for memory allocation:
struct Array(T, Allocator)
if(isAllocator!Allocator){
	
	Allocator allocator;
	T[] slice;
	
	this(Allocator allocator){
		this.allocator = allocator;
	}
	
	//et cetera
}
```

Allocators from `std.experimental.allocator` may be used via `Wrapped` from `memterface.wrap`.
+/
module memterface.iface;

import std.traits;

/**
Describes the basic API that must be implemented by all allocators.

Note that using DBI with structs is recommended over inheriting directly from this `interface`.

Structs implementing this API may slightly differ from the `AllocatorInterface`s in a few ways:
- Allocator functions  may be `static`. This is useful if the allocator has no instance-specific state (i.e. only global state).
- Functions may provide `shared` overloads.
- Adding extra attributes where appropriate is encouraged. (e.g. `@nogc`, `pure`, `@safe`)
*/
interface AllocatorInterface{
	/**
	Allocates at least the specified amount of memory (in bytes), and returns it as a slice.
	The size of the returned slice must match the requested size, even if more memory was allocated internally.
	
	The values in the memory pointed to by the returned slice are undefined. (i.e. do not have to be cleared in any way)
	
	Calling this function must never fail unless the system is out of memory. For allocators with
	a fixed amount of pre-allocated space, a fallback to another allocator is recommended.
	Otherwise, the optional `canAllocate` function can be implemented. If `canAllocate(size)` would've returned
	`false` but this function is was called anyway, then it may throw an `OutOfMemoryError` or `assert(0)`.
	
	Zero-sized allocations must return zero-sized slices, which may or may not point to `null`.
	
	Throws: `OutOfMemoryError` via `onOutOfMemoryError` when the system is out of memory.
	*/
	void[] allocate(size_t size) nothrow
	out(memory; memory.length == size);
	
	/**
	Deallocates `memory`, after which it is invalid.
	*/
	void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory));
	
	/**
	Determines whether this allocator (including any of its fallbacks) owns the specified slice of memory.
	
	Calling this function should never fail. When creating a wrapper over a pre-existing allocator that makes
	it absolutely impossible to determine if the allocator allocated a pointer (e.g. malloc) then this function
	may always return `true` as long as:
	- It is well-documented that it always returns `true`, and the documentation explains why.
	- The function is marked `@system` if the allocator will produce undefined behaviour when memory that it
		does not own is passed to `deallocate`, `reallocate`, or `extend`.
	
	Returns: `true` if the slice was allocated by this allocator, otherwise `false`.
	*/
	bool isOwnerOf(const(void)[] memory) const nothrow;
}

interface AllocatorInterfaceWithReallocate: AllocatorInterface{
	/**
	Reallocate `memory`, making it `newSize` bytes large.
	
	The allocator may optionally choose to extend `memory` in-place if it is possible.
	
	Calling this function must never fail unless the system is out of memory. For allocators with
	a fixed amount of pre-allocated space, a fallback to another allocator is recommended.
	Otherwise, the optional `canAllocate` function can be implemented. If `canAllocate(size)` would've returned
	`false` but this function is was called anyway, then it may throw an `OutOfMemoryError` or `assert(0)`.
	
	Throws: `OutOfMemoryError` via `onOutOfMemoryError` when the system is out of memory.
	*/
	void reallocate(ref void[] memory, size_t newSize) nothrow
	in(isOwnerOf(memory))
	out(; memory.length == newSize);
}

///An optional extension for extending allocated memory in-place.
interface AllocatorInterfaceWithExtend: AllocatorInterface{
	/**
	Attempt to extend the `memory` in-place by up to the number of bytes in `sizeDelta`.
	
	Must not modify the pointer in `memory`. If `memory` was valid when calling this
	function, then it must remain valid afterwards.
	
	Returns: The number of bytes added to `memory`. `0` indicates that no space could be
		added, i.e. the function failed.
	*/
	size_t extend(ref void[] memory, size_t sizeDelta) nothrow
	in(isOwnerOf(memory))
	out(returnedSizeDelta; returnedSizeDelta <= sizeDelta);
}

///An optional extension for checking when `allocate` will fail.
interface AllocatorInterfaceWithCanAllocate: AllocatorInterface{
	/**
	Determine whether `size` bytes can be allocated with the current allocator state.
	
	If the allocator's state changes in any way, then any value previously returned by
	`canAllocate` no longer applies:
	```
	if(allocator.canAllocate(100)){
		auto memA = allocator.allocate(1); //allocator state is modified, so `canAllocate(100)` has fulfilled its purpose.
		auto memB = allocator.allocate(99); //may throw `OutOfMemoryError`, since we didn't check `canAllocate(99)` since last allocating!
	}
	```
	
	Returns: `true` if enough space is free (*in the allocator*, not necessarily in the system)
		to call `allocate(size)`, or `reallocate(someMemory, size)` (if implemented),
		otherwise `false`.
	*/
	bool canAllocate(size_t size) const nothrow;
}

///Returns: `true` if `T` is an allocator with at least an allocate & deallocate function.
enum isAllocator(T) =
	is(typeof(T.allocate(size: size_t.init)) == void[]) && hasFunctionAttributes!(T.allocate, "nothrow") &&
	is(typeof(T.deallocate(memory: void[].init)) == void) && hasFunctionAttributes!(T.deallocate, "nothrow") &&
	is(typeof(T.isOwnerOf(memory: void[].init)) == bool) && hasFunctionAttributes!(T.isOwnerOf, "nothrow");

///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithReallocate` API extension.
template hasReallocate(A)
if(isAllocator!A){
	enum hasReallocate =
		(){ void[] memory; return is(typeof(A.reallocate(memory: memory, newSize: size_t.init)) == void); }() &&
		hasFunctionAttributes!(A.reallocate, "nothrow");
}
///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithExtend` API extension.
template hasExtend(A)
if(isAllocator!A){
	enum hasExtend =
		(){ void[] memory; return is(typeof(A.extend(memory: memory, sizeDelta: size_t.init)) == size_t); }() &&
		hasFunctionAttributes!(A.extend, "nothrow");
}
///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithCanAllocate` API extension.
template hasCanAllocate(A)
if(isAllocator!A){
	enum hasCanAllocate =
		is(typeof(Allocator.canAllocate(size: size_t.init)) == bool) &&
		hasFunctionAttributes!(A.canAllocate, "nothrow") &&
		(hasFunctionAttributes!(A.canAllocate, "const") || __traits(isStaticFunction, A.canAllocate));
}
/**
Returns: `true` if `Allocator`'s API functions are all `pure`.

Useful for discriminating between allocators that rely on no global state versus ones that do.
*/
template isPure(A)
if(isAllocator!A){
	enum isPure =
		hasFunctionAttributes!(A.allocate, "pure") &&
		hasFunctionAttributes!(A.deallocate, "pure") &&
		hasFunctionAttributes!(A.isOwnerOf, "pure") &&
		(hasReallocate!A ? hasFunctionAttributes!(A.reallocate, "pure") : true) &&
		(hasExtend!A ? hasFunctionAttributes!(A.extend, "pure") : true) &&
		(hasCanAllocate!A ? hasFunctionAttributes!(A.canAllocate, "pure") : true);
}
