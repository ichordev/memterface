/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
/++
Interfaces for generic allocators.

Allocators must follow the *interface* of `AllocatorInterface` (see below). However, making allocators
using class inheritance is **not recommended**. Instead, it is generally best to use `struct`s, which
are passed to template type parameters with the `isAllocator!T` constraint:
```
//A custom allocator:
struct MyAllocator{
	void[] allocate(size_t size) nothrow
	out(memory; memory.length == size)
	out(memory; (size == 0 && memory is null) || isOwnerOf(memory)){
		//return `size` bytes of allocated memory
	}
	
	void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory)){
		//deallocate `memory`
	}
	
	bool isOwnerOf(void[] memory) nothrow{
		//return `true` if this allocator owns `memory`
	}
}

//A struct using an allocator for memory allocation:
struct Array(T, Allocator)
if(isAllocator!Allocator){ //This constraint also accepts classes that implement `AllocatorInterface`
	
	Allocator allocator;
	T[] slice;
	
	this(Allocator allocator){
		this.allocator = allocator;
	}
	
	//et cetera
}
```

See_Also: `memterface.wrap` makes it possible to use `std.experimental.allocator` allocators
via `Wrapped!T`; and wrappers over pre-existing allocators with no equivalent of
`isOwnerOf` can be created with the assistance of `ImplementIsOwnerOf`.
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

Definition of terms:
- **must** / **will** means '*required in order to conform to the API*'.
- **may** means '*allowed, but up to the discretion of the programmer*'.
- **should** means '*strongly encouraged, but up to the discretion of the programmer*'.
*/
interface AllocatorInterface{
	/**
	Allocates at least the specified amount of memory (in bytes), and returns it as a slice.
	The size of the returned slice must match the requested size, even if more memory was allocated internally.
	
	The values in the memory pointed to by the returned slice are undefined. (i.e. do not have to be cleared in any way)
	
	Calling this function must always either succeed, or terminate the program (e.g. with `OutOfMemoryError`).
	For allocators with a fixed amount of pre-allocated space, a fallback to another allocator is recommended.
	Otherwise, the optional `canAllocate` function can be implemented. If `canAllocate(size)` would've returned
	`false` but this function is was called anyway, then it must throw an `OutOfMemoryError`. When `canAllocate`
	is implemented, `allocate` (and `reallocate` where applicable) should also have the precondition `in(canAllocate(size))`
	in order to assist in diagnosing the root cause of the error.
	
	Zero-sized allocations must return zero-sized slices, which may or may not point to `null`.
	`null` zero-sized slices are not owned by the allocator, and therefore cannot be `deallocate`d.
	However, non-`null` zero-sized slices must point to valid readable/writeable memory, be unique
	(i.e. `allocator.allocate(0).ptr != allocator.allocate(1).ptr`), and may cause memory leaks if not subsequently
	`deallocate`d.
	If an allocator allocates non-`null` zero-sized slices, it is best practice for it to fall back to return
	`null` zero-sized slices if and when its state runs out of space for non-`null` zero-sized slices.
	*/
	void[] allocate(size_t size) nothrow
	out(memory; memory.length == size)
	out(memory; (size == 0 && memory is null) || isOwnerOf(memory));
	
	/**
	Deallocates `memory`, after which it should be invalid for the caller to use it.
	*/
	void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory));
	
	/**
	Determines whether this allocator (including any of its fallbacks) owns the specified slice of memory.
	
	The allocator must return `true` when `memory`'s pointer and length are identical to a slice returned (or modified) by
	`allocate`, `reallocate`, `extend`, and other functions that return/modify allocated slices, unless the slice was
	reallocated, deallocated, or extended thereafter and thereby returned with (or modified to) a different pointer/length.
	In other cases—for instance when `memory`'s length does not match what was returned, or if its pointer points to the
	interior of a returned slice—this function **must** return `false`!
	
	Must return `false` when `memory` points to memory owned by the allocator that has not yet allocated by
	the user (e.g. via `allocate`), or has been deallocated.
	
	Calling this function must never fail except for assertion failures and breach of contracts.
	
	When creating a wrapper over a pre-existing allocator that makes it absolutely impossible to determine if the
	allocator allocated a pointer (e.g. malloc) then this function may be implemented using
	`memterface.wrap.ImplementIsOwnerOf`.
	
	Returns: `true` if the allocator recognises that `memory` was allocated by it, otherwise `false`.
	*/
	bool isOwnerOf(const(void)[] memory) const nothrow;
}

interface AllocatorInterfaceWithReallocate: AllocatorInterface{
	/**
	Reallocates `memory`, making it `newSize` bytes large.
	
	The allocator may extend `memory` in-place where possible. Otherwise, the value of `memory` before calling this
	function will become invalid, and must cause `isOwnerOf(oldMemory)` to return `false`.
	
	Calling this function must always either succeed, or terminate the program (e.g. with `OutOfMemoryError`).
	For allocators with a fixed amount of pre-allocated space, a fallback to another allocator is recommended.
	Otherwise, the optional `canAllocate` function can be implemented. If `canAllocate(size)` would've returned
	`false` but this function is was called anyway, then it must throw an `OutOfMemoryError`. When `canAllocate`
	is implemented, `allocate` (and `reallocate` where applicable) should also have the precondition
	`in(canAllocate(size))` in order to assist in diagnosing the root cause of the error.
	
	This extension should only be implemented if it provides some benefit over simply
	allocating `newSize` and copying the contents of `memory` into it like so:
	```d
	auto memory2 = allocator.allocate(newSize);
	() @trusted{ memory2[] = memory[]; }();
	allocator.deallocate(memory);
	```
	*/
	void reallocate(ref void[] memory, size_t newSize) nothrow
	in(isOwnerOf(memory))
	out(; (newSize == 0 && memory is null) || isOwnerOf(memory))
	out(; memory.length == newSize);
}

///An optional extension for extending allocated memory in-place.
interface AllocatorInterfaceWithExtend: AllocatorInterface{
	/**
	Attempts to extend `memory` in-place by up to `sizeDelta` bytes.
	
	Must not modify the pointer in `memory`. If `memory` was valid when calling this
	function, then it must remain valid afterwards.
	
	Returns: The number of bytes added to `memory`. `0` indicates that no space could be
		added, i.e. the function call failed.
	*/
	size_t extend(ref void[] memory, size_t sizeDelta) nothrow
	in(isOwnerOf(memory))
	out(returnedSizeDelta; returnedSizeDelta <= sizeDelta);
}

///An optional extension for checking when `allocate` (and `reallocate` if applicable) will fail.
interface AllocatorInterfaceWithCanAllocate: AllocatorInterface{
	/**
	Determines whether `size` bytes can be allocated with the current allocator state.
	
	If the allocator's state changes in any way, then any value previously returned by `canAllocate` no longer applies:
	```
	if(allocator.canAllocate(100)){
		auto memA = allocator.allocate(100); //allocator state is modified, so `canAllocate(100)` has fulfilled its purpose.
		allocator.deallocate(memA);
		auto memB = allocator.allocate(1); //may throw an error, since we didn't check `canAllocate(1)` beforehand!
	}
	if(allocator.canAllocate(100)){
		auto memC = allocator.allocate(1); //may also throw an error, since we checked `canAllocate(100)` beforehand not `canAllocate(1)`!
	}
	```
	
	When this function is implemented, `allocate` (and `reallocate` where applicable) should also have
	the precondition `in(canAllocate(size))` in order to assist in diagnosing the root cause of the error.
	
	Returns: `true` if enough space is free (*in the allocator*, not necessarily in the system)
		to call `allocate(size)`, or `reallocate(someMemory, size)` (if implemented),
		otherwise `false`.
	*/
	bool canAllocate(size_t size) const nothrow;
}

///Returns: `true` if `T` is an allocator with at least an allocate & deallocate function.
enum isAllocator(T) =
	is(typeof(T.allocate(size: size_t())) == void[]) && hasFunctionAttributes!(T.allocate, "nothrow") &&
	is(typeof(T.deallocate(memory: void[].init)) == void) && hasFunctionAttributes!(T.deallocate, "nothrow") &&
	is(typeof(T.isOwnerOf(memory: cast(const(void)[])[])) == bool) && hasFunctionAttributes!(T.isOwnerOf, "nothrow") &&
	(hasFunctionAttributes!(T.isOwnerOf, "const") || __traits(isStaticFunction, T.isOwnerOf));

///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithReallocate` API extension.
template hasReallocate(A)
if(isAllocator!A){
	enum hasReallocate =
		(){ void[] memoryRef; return is(typeof(A.reallocate(memory: memoryRef, newSize: size_t())) == void); }() && is(typeof(A.reallocate)) &&
		hasFunctionAttributes!(A.reallocate, "nothrow");
}
///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithExtend` API extension.
template hasExtend(A)
if(isAllocator!A){
	enum hasExtend =
		(){ void[] memoryRef; return is(typeof(A.extend(memory: memoryRef, sizeDelta: size_t())) == size_t); }() && is(typeof(A.extend)) &&
		hasFunctionAttributes!(A.extend, "nothrow");
}
///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithCanAllocate` API extension.
template hasCanAllocate(A)
if(isAllocator!A){
	enum hasCanAllocate =
		is(typeof(A.canAllocate(size: size_t())) == bool) &&
		hasFunctionAttributes!(A.canAllocate, "nothrow") &&
		(hasFunctionAttributes!(A.canAllocate, "const") || __traits(isStaticFunction, A.canAllocate));
}
/**
Returns: `true` if `Allocator`'s API functions are all `static`.

Useful for discriminating between allocators that don't rely on instance data versus ones that do.
*/
template isGlobal(A)
if(isAllocator!A){
	enum isGlobal =
		__traits(isStaticFunction, A.allocate) &&
		__traits(isStaticFunction, A.deallocate) &&
		__traits(isStaticFunction, A.isOwnerOf) &&
		(hasReallocate!A ? is(typeof(A.reallocate)) && __traits(isStaticFunction, A.reallocate) : true) &&
		(hasExtend!A ? is(typeof(A.extend)) && __traits(isStaticFunction, A.extend) : true) &&
		(hasCanAllocate!A ? is(typeof(A.canAllocate)) && __traits(isStaticFunction, A.canAllocate) : true);
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
		(hasReallocate!A ? is(typeof(A.reallocate)) && hasFunctionAttributes!(A.reallocate, "pure") : true) &&
		(hasExtend!A ? is(typeof(A.extend)) && hasFunctionAttributes!(A.extend, "pure") : true) &&
		(hasCanAllocate!A ? is(typeof(A.canAllocate)) && hasFunctionAttributes!(A.canAllocate, "pure") : true);
}
