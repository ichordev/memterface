/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.

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
*/
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
	
	`allocate(0)` must always return `null`.
	
	The values in the memory pointed to by the returned slice are undefined. (i.e. do not have to be cleared in any way)
	
	Calling this function must always either succeed, or terminate the program (e.g. with `OutOfMemoryError`).
	For allocators with a fixed amount of pre-allocated space, a fallback to another allocator is recommended.
	Otherwise, the optional `canAllocate` function can be implemented. If `canAllocate(size)` would've returned
	`false` but this function is called anyway, then it must throw an `OutOfMemoryError`.
	*/
	void[] allocate(size_t size) nothrow
	out(memory; memory.length == size)
	out(memory; size > 0 ? isOwnerOf(memory) : memory is null);
	
	/**
	Deallocates `memory`, after which it should be invalid for the caller to use it.
	*/
	void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory));
	
	/**
	Determines whether this allocator (including any of its fallbacks) owns the specified slice of memory.
	
	This function must return `true` when `memory`'s pointer and length are identical to a slice returned (or modified) by
	the same allocator's  `allocate`, `reallocate`, `resize`, etc. functions that return/modify allocated slices, unless the
	slice was reallocated/deallocated/resized/etc. thereafter and thereby returned with (or modified to) having a different pointer/length.
	Otherwise, when `memory` points to the interior of a returned slice, or  `memory`'s length is not
	what was returned by the allocator, then this function should return `false`.
	In generic code, care should be taken to avoid passing interior slices to allocator functions in the first place.
	
	`isOwnerOf(null)` must return `false`, since no allocator owns `null`.
	
	Must return `false` when `memory` points to memory owned by the allocator that has not yet allocated by
	the user (e.g. via `allocate`), or has been deallocated.
	
	Calling this function must never fail, except for errors such as assertion failures.
	
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
	
	The allocator may shorten/extend `memory` in-place where possible. Otherwise, the value of `memory` before
	calling this function will become invalid, and must cause `isOwnerOf(oldMemory)` to return `false`.
	
	If `newSize == 0`, then this function must deallocate `memory` and assign it to be `null`.
	
	Calling this function must always either succeed, or terminate the program (e.g. with `OutOfMemoryError`).
	For allocators with a fixed amount of pre-allocated space, a fallback to another allocator is recommended.
	Otherwise, the optional `canAllocate` function can be implemented. If `canAllocate(size)` would've returned
	`false` but this function is was called anyway, then it must throw an `OutOfMemoryError`.
	
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
	out(; memory.length == newSize)
	out(; newSize > 0 ? isOwnerOf(memory) : memory is null);
}

///An optional extension for resizing an allocated memory block in-place.
interface AllocatorInterfaceWithResize: AllocatorInterface{
	/**
	Attempts to shorten/extend `memory` in-place to be `newSize` bytes.
	The function is allowed to shorten/extend `memory` by less than the amount
	requested, but not by more. However, it must only shrink memory to be a
	minimum of 1 byte in size when `newSize == 0`.
	
	Must not modify the pointer in `memory`. If `memory` was valid when calling this
	function, then it must remain valid afterwards.
	
	Returns: The new size of `memory`.
	*/
	size_t resize(ref void[] memory, size_t newSize) nothrow
	in(isOwnerOf(memory))
	out(; isOwnerOf(memory))
	out(retSize; retSize == memory.length);
}

///An optional extension for checking when `allocate` (and `reallocate` if applicable) will fail.
interface AllocatorInterfaceWithCanAllocate: AllocatorInterface{
	/**
	Determines whether `size` bytes can be allocated with the current allocator state.
	`canAllocate(0)` must always return `true`.
	
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
	
	Returns: `true` if enough space is free (*in the allocator*, not necessarily in the system)
		to call `allocate(size)`, or `reallocate(someMemory, size)` (if implemented),
		otherwise `false`.
	*/
	bool canAllocate(size_t size) const nothrow
	/+out(ret; size > 0 || ret)+/;
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
///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithResize` API extension.
template hasResize(A)
if(isAllocator!A){
	enum hasResize =
		(){ void[] memoryRef; return is(typeof(A.resize(memory: memoryRef, newSize: size_t())) == size_t); }() && is(typeof(A.resize)) &&
		hasFunctionAttributes!(A.resize, "nothrow");
}
///Returns: `true` if `A` implements the optional `AllocatorInterfaceWithCanAllocate` API extension.
template hasCanAllocate(A)
if(isAllocator!A){
	enum hasCanAllocate =
		is(typeof(A.canAllocate(size: size_t())) == bool) &&
		hasFunctionAttributes!(A.canAllocate, "nothrow") &&
		(hasFunctionAttributes!(A.canAllocate, "const") || __traits(isStaticFunction, A.canAllocate));
}

///Returns: a sequence of the class interfaces that `A` is compatible with.
template AllocatorInterfacesFor(A)
if(isAllocator!A){
	import std.meta: AliasSeq;
	alias AllocatorInterfacesFor = AliasSeq!(AllocatorInterface);
	static if(hasReallocate!A)  AllocatorInterfacesFor = AliasSeq!(AllocatorInterfacesFor, AllocatorInterfaceWithReallocate);
	static if(hasResize!A)      AllocatorInterfacesFor = AliasSeq!(AllocatorInterfacesFor, AllocatorInterfaceWithResize);
	static if(hasCanAllocate!A) AllocatorInterfacesFor = AliasSeq!(AllocatorInterfacesFor, AllocatorInterfaceWithCanAllocate);
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
		(hasResize!A ? is(typeof(A.resize)) && __traits(isStaticFunction, A.resize) : true) &&
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
		(hasResize!A ? is(typeof(A.resize)) && hasFunctionAttributes!(A.resize, "pure") : true) &&
		(hasCanAllocate!A ? is(typeof(A.canAllocate)) && hasFunctionAttributes!(A.canAllocate, "pure") : true);
}
