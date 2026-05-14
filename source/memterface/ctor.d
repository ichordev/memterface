/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.

Functions to automatically allocate memory and construct/initialise a data type into it.
*/
module memterface.ctor;

import core.builtins: unlikely;
import core.lifetime: emplace, forward, moveEmplace;
import std.algorithm.comparison: min;
import memterface.iface;

/**
Return a sub-slice of `memory` which starts on an `alignment`-byte boundary. The length of
the returned sub-slice is `memory.length - alignment` bytes, so you should
allocate `desiredSize + alignment` bytes of mmeory to pass to this function.

Since this function only returns a sub-slice of `memory`, you cannot reliably call the original
allocator's deallocate/reallocate/etc. functions with the returned sub-slice.
Rather, you must call `removeAlignment(subSlice, alignment)` and pass its return value to the
allocator instead.

See_Also: `removeAlignment`
*/
void[] forceAlignment(return scope void[] memory, size_t alignment) nothrow @nogc pure @safe
in(alignment >= 1 && alignment <= 256)
in(memory.length >= alignment){
	const startInd = alignment - (cast(size_t)&memory[0] % alignment);
	const metaInd = cast(ubyte)(startInd - ubyte.sizeof);
	*(() @trusted => cast(ubyte*)memory[metaInd..startInd])() = metaInd; //write the start index as a byte of metadata
	return memory[startInd..$-(alignment - startInd)];
}
///
nothrow pure @safe unittest{
	import memterface.allocator;
	enum alignment = 256;
	foreach(_; 0..100){
		void[] m = GCAllocator().allocate(12 + alignment);
		void[] aligned = forceAlignment(m, alignment);
		assert(aligned.length == 12);
		assert(cast(size_t)aligned.ptr % alignment == 0);
	}
	void[] m = GCAllocator().allocate(12 + alignment + alignment);
	void[] aligned = forceAlignment(m, alignment);
	void[] alignedTwice = forceAlignment(aligned, alignment);
	assert(alignedTwice !is aligned);
	assert(alignedTwice.length == 12);
	assert(cast(size_t)alignedTwice.ptr % alignment == 0);
}

/**
Removes the alignment from a slice of memory returned by `forceAlignment`.

Calls to this function can be marked `@trusted` if the caller is certain that `alignedMemory` matches
a slice returned by `forceAlignment`.

Params:
	alignedMemory = Must be a slice of memory returned by `forceAlignment`.
	alignment = Must be the same as the value that was previously passed to `forceAlignment`.

See_Also: `forceAlignment`
*/
void[] removeAlignment(return scope void[] alignedMemory, size_t alignment) nothrow @nogc @system
in(alignment >= 1 && alignment <= 256)
in(alignedMemory !is null)
out(memory; memory.length == alignedMemory.length + alignment){
	const meta = *cast(ubyte*)(alignedMemory.ptr-1);
	assert(meta < alignment, "`alignment` is less than the alignment that was passed to `forceAlignment`; or `alignedMemory` wasn't returned by `forceAlignment`");
	const start = meta + ubyte.sizeof;
	return (alignedMemory.ptr - start)[0..alignedMemory.length + alignment];
}
///
nothrow @nogc unittest{
	import memterface.allocator;
	enum alignment = 256;
	void[] m = CAllocator().allocate(12 + alignment);
	void[] aligned = forceAlignment(m, alignment);
	assert(removeAlignment(aligned, alignment) is m);
}

private template sizeInMemory(T){
	static if(is(T == class) || is(T == interface))
		enum size_t sizeInMemory = __traits(classInstanceSize, T) + __traits(classInstanceAlignment, T);
	else
		enum size_t sizeInMemory = T.sizeof;
}

private template RefOf(T){
	static if(is(T == class)){
		alias RefOf = T;
	}else{
		alias RefOf = T*;
	}
}

pragma(inline,true)
private auto initNewImpl(T)(return scope void[] memory) nothrow @nogc pure @trusted{
	static if(is(T == class)){
		memory = forceAlignment(memory, __traits(classInstanceAlignment, T));
		import core.stdc.string: memcpy;
		memcpy(memory.ptr, __traits(initSymbol, T).ptr, __traits(classInstanceSize, T));
		return cast(T)memory.ptr;
	}else{
		return initArray!T(memory).ptr;
	}
}

/**
Allocates enough memory to store a heap-allocated instance of `T` using `allocator`, and then
initialises it to `T.init`; or `__traits(initSymbol, T)` if `T` is a class.

This function should always be inferred as `nothrow` unless `opFail` throws.

The optional callback `onFail` may be passed, which will be called if `allocator.canAllocate` is defined and returns `false`.
`onFail` must return a type that converts to an instance of `T`, which will be returned by `initNew`.

Returns: A newly default-initialised heap-allocated instance of `T`; or
	the result of `onFail` (if passed) when allocation fails.

See_Also: `newArray` is a similar function that handles arrays.
*/
auto initNew(T, Allocator, F)(return scope auto ref Allocator allocator, scope F onFail=null)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator && (is(F == typeof(null)) || is(typeof(onFail()): typeof(initNewImpl!T([]))))){
	static if(!is(F == typeof(null)) && hasCanAllocate!Allocator){
		if(unlikely(!allocator.canAllocate(sizeInMemory!T))) return onFail();
	}
	return initNewImpl!T(allocator.allocate(sizeInMemory!T));
}
///ditto
auto initNew(T, F)(return scope AllocatorInterface allocator, scope F onFail=null)
if(is(F == typeof(null)) || is(typeof(onFail()): typeof(initNewImpl!T([])))){
	static if(!is(F == typeof(null))){
		if(auto allocCanAlloc = cast(AllocatorInterfaceWithCanAllocate)allocator){
			if(unlikely(!allocCanAlloc.canAllocate(sizeInMemory!T))) return onFail();
		}
	}
	return initNewImpl!T(allocator.allocate(sizeInMemory!T));
}
///
nothrow pure @safe unittest{
	import memterface.allocator;
	int* i = GCAllocator().initNew!int();
	assert(*i == 0);
	assert(BottomAllocator().initNew!int(() => null) is null);
}

pragma(inline,true)
private auto constructNewImpl(alias doEmplace, T, Allocator)(return scope auto ref Allocator allocator){
	auto memory = allocator.allocate(sizeInMemory!T);
	static if(is(T == class)){
		memory = forceAlignment(memory, __traits(classInstanceAlignment, T));
	}
	scope(failure){
		static if(!is(typeof(() pure{ doEmplace(); }()))) allocator.deallocate(memory);
		else () @trusted{ allocator.deallocate(memory); }();
	}
	return doEmplace(memory);
}

/**
Allocates enough memory to store a heap-allocated instance of `T` using `allocator`, and then
calls its constructor with `args`.

The optional callback `onFail` may be passed, which will be called if `allocator.canAllocate` is defined and returns `false`.
`onFail` must return a type that converts to an instance of `T`, which will be returned by `initNew`.
Note that `onFail` will NOT be called if `T`'s constructor throws.

Returns: A newly constructed heap-allocated instance of `T`; or
	the result of `onFail` (if passed) when allocation fails.

See_Also: `newArray` is a similar function that handles arrays.

Note: This function is roughly equivalent to `make` from `std.experimental.allocator`.
*/
auto constructNew(T, Allocator, F, Args...)(return scope auto ref Allocator allocator, auto ref Args args, scope F onFail=null)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator && (is(F == typeof(null)) || is(typeof(onFail()): typeof(initNewImpl!T([]))))){
	static if(!is(F == typeof(null)) && hasCanAllocate!Allocator){
		if(unlikely(!allocator.canAllocate(sizeInMemory!T))) return onFail();
	}
	return constructNewImpl!((void[] memory) => emplace!T((() @trusted => cast(RefOf!T)memory.ptr)(), forward!args), T, Allocator)(allocator);
}
///ditto
auto constructNew(T, F, Args...)(return scope AllocatorInterface allocator, auto ref Args args, scope F onFail=null)
if(is(F == typeof(null)) || is(typeof(onFail()): typeof(initNewImpl!T([])))){
	static if(!is(F == typeof(null))){
		if(auto allocCanAlloc = cast(AllocatorInterfaceWithCanAllocate)allocator){
			if(unlikely(!allocCanAlloc.canAllocate(sizeInMemory!T))) return false;
		}
	}
	return constructNewImpl!((void[] memory) => emplace!T((() @trusted => cast(RefOf!T)memory.ptr)(), forward!args), T, AllocatorInterface)(allocator);
}

pragma(inline,true)
private size_t getArraySize(T)(size_t length) nothrow @nogc pure @safe{
	static if(T.sizeof <= 1){
		return length * T.sizeof;
	}else{
		import core.exception: onOutOfMemoryError;
		import core.checkedint: mulu;
		bool overflow;
		const size = mulu(length, T.sizeof, overflow);
		if(!overflow) return size;
		else onOutOfMemoryError();
	}
}

pragma(inline,true)
private T[] initArray(T)(return scope void[] array) nothrow @nogc pure @trusted{
	import std.traits: Unqual;
	alias U = Unqual!T;
	if(array.length){
		static if(__traits(isZeroInit, T)){ //types with only 00 bytes
			import core.stdc.string: memset;
			memset(&array[0], 0x00, array.length);
		}else static if(is(U == char) || is(U == wchar)){ //types with only FF bytes
			import core.stdc.string: memset;
			memset(&array[0], 0xFF, array.length);
		}else static if(T.sizeof == 1){
			import core.stdc.string: memset;
			const initSymbol = T.init;
			memcpy(&array[0], *cast(ubyte*)&initSymbol, array.length);
		}else static if(T.sizeof > 0){
			import core.stdc.string: memcpy;
			static if(is(T == struct) || is(T == union)){
				memcpy(&array[0], &__traits(initSymbol, T)[0], T.sizeof);
			}else{
				const initSymbol = T.init;
				memcpy(&array[0], &initSymbol, T.sizeof);
			}
			size_t alreadyCopied = T.sizeof;
			while(alreadyCopied < array.length){
				const thisCopyLength = min(alreadyCopied, array.length-alreadyCopied);
				memcpy(&array[alreadyCopied], &array[0], thisCopyLength);
				alreadyCopied += thisCopyLength;
			}
		}
	}
	return cast(T[])array;
}

/**
Allocates enough memory to store an array of `T` with `length` elements using `allocator`,
and then default-initialises each element.

This function should always be inferred as `nothrow` unless `opFail` throws.

The optional callback `onFail` may be passed, which will be called if `allocator.canAllocate` is defined and returns `false`.
`onFail` must return a type that converts to `T[]`, which will be returned by `newArray`.

Returns: A newly allocated & default-initialised `T[]`; or
	the result of `onFail` (if passed) when allocation fails.

Similar to `makeArray` from `std.experimental.allocator`.
*/
T[] newArray(T, Allocator, F)(return scope auto ref Allocator allocator, size_t length, scope F onFail=null)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator && (is(F == typeof(null)) || is(typeof(onFail()): T[]))){
	const size = getArraySize!T(length);
	static if(!is(F == typeof(null)) && hasCanAllocate!Allocator){
		if(unlikely(!allocator.canAllocate(size))) return onFail();
	}
	return initArray!T(allocator.allocate(size));
}
///ditto
T[] newArray(T, F)(return scope AllocatorInterface allocator, size_t length, scope F onFail=null)
if(is(F == typeof(null)) || is(typeof(onFail()): T[])){
	const size = getArraySize!T(length);
	static if(!is(F == typeof(null))){
		if(auto allocCanAlloc = cast(AllocatorInterfaceWithCanAllocate)allocator){
			if(unlikely(!allocCanAlloc.canAllocate(size))) return onFail();
		}
	}
	return initArray!T(allocator.allocate(size));
}
///
nothrow pure @safe unittest{
	import memterface.allocator;
	int[] a = GCAllocator().newArray!int(10);
	foreach(ref item; a)
		assert(item == 0);
	assert(BottomAllocator().newArray!int(1, () => null) is null);
}

/**
Resizes `array` to have `newLength` elements using `allocator`. If `array` is `null`, it is newly allocated.
`array` must have been originally allocated with `allocator` unless it is `null`.

The optional callback `onFail` may be passed, which will be called if `allocator.canAllocate` is defined and returns `false`.
`onFail` must return a type that converts to `bool`, which will be returned from `resizeArray`.

New elements are default-initialised. Removed elements get destroyed appropriately.

Returns: `true`; or the result of `onFail` (if passed) when allocation fails.
*/
bool resizeArray(bool runDestructors=true, Allocator, T, F)(
	return scope auto ref Allocator allocator, scope ref T[] array, size_t newLength, scope F onFail=null,
)if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator && (is(F == typeof(null)) || is(typeof(onFail()): bool))){
	const oldLength = array.length;
	if(newLength != oldLength){
		if(array !is null){
			static if(runDestructors && (is(T == struct) || is(T == class) || is(T == interface))){
				if(newLength < oldLength){
					foreach(ref item; array[newLength..$])
						destroy!false(item);
				}
			}
			const arraySize = getArraySize!T(newLength);
			static if(!is(F == typeof(null)) && hasCanAllocate!Allocator){
				if(unlikely(!allocator.canAllocate(arraySize))) return cast(bool)onFail();
			}
			
			static if(hasResize!Allocator){
				void[] voidArray = array;
				bool doRealloc = allocator.resize(voidArray, arraySize) != arraySize;
				array = cast(T[])voidArray;
			}else{
				enum doRealloc = true;
			}
			if(doRealloc){
				auto newArray = ((memory) @trusted => cast(T[])memory)(allocator.allocate(arraySize));
				static if(is(immutable T == immutable void) || __traits(isScalar, T)){
					const len = min(array.length, newArray.length);
					newArray[0..len] = array[0..len];
				}else{
					foreach(i, ref item; array[0..min(newArray.length, $)])
						moveEmplace(item, newArray[i]);
				}
				allocator.deallocate(array);
				array = newArray;
			}
			if(newLength > oldLength)
				cast(void)initArray!T(array[oldLength..$]);
		}else{
			array = newArray!(T, Allocator)(allocator, newLength);
		}
	}
	return true;
}
///ditto
bool resizeArray(bool runDestructors=true, T, F)(
	return scope AllocatorInterface allocator, scope ref T[] array, size_t newLength, scope F onFail=null,
)if(is(F == typeof(null)) || is(typeof(onFail()): bool)){
	const oldLength = array.length;
	if(newLength != oldLength){
		if(array !is null){
			static if(runDestructors && (is(T == struct) || is(T == class) || is(T == interface))){
				if(newLength < oldLength){
					foreach(ref item; array[newLength..$])
						destroy!false(item);
				}
			}
			const arraySize = getArraySize!T(newLength);
			static if(!is(F == typeof(null))){
				if(auto allocCanAlloc = cast(AllocatorInterfaceWithCanAllocate)allocator){
					if(unlikely(!allocCanAlloc.canAllocate(arraySize))) return cast(bool)onFail();
				}
			}
			bool doRealloc = true;
			{
				auto allocResize = cast(AllocatorInterfaceWithResize)allocator;
				if(unlikely(allocResize !is null)){
					void[] voidArray = array;
					doRealloc = allocResize.resize(voidArray, arraySize) != arraySize;
					array = cast(T[])voidArray;
				}
			}
			if(doRealloc){
				auto newArray = ((memory) @trusted => cast(T[])memory)(allocator.allocate(arraySize));
				foreach(i, ref item; array[0..min(newArray.length, $)])
					moveEmplace(item, newArray[i]);
				allocator.deallocate(array);
				array = newArray;
			}
			if(newLength > oldLength)
				cast(void)initArray!T(array[oldLength..$]);
		}else{
			array = newArray!T(allocator, newLength);
		}
	}
	return true;
}
///
pure unittest{
	import std.exception;
	import memterface.allocator;
	static class DestructorException: Exception{ mixin basicExceptionCtors!(); }
	static struct X{
		int i;
		~this() pure{ throw new DestructorException("Destructor called!"); }
	}
	X[] a = GCAllocator().newArray!X(10);
	assert(GCAllocator().resizeArray(a, 20) == true);
	foreach(ref item; a)
		assert(item.i == 0);
	assertThrown!DestructorException(GCAllocator().resizeArray(a, 19));
}

/**
Destroys `ptr` if `runDestructors` is `true`, and then deallocates it with `allocator`.

`ptr` must have been allocated by `allocator`.

Similar to `dispose` from `std.experimental.allocator`.
*/
void dispose(bool runDestructors=true, Allocator, T)(scope auto ref Allocator allocator, scope auto ref T* ptr)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator && (!is(T == class) && !is(T == interface))){
	static if(runDestructors && is(T == struct))
		destroy!false(*ptr);
	allocator.deallocate((() @trusted => ptr[0..1])());
	static if(__traits(isRef, ptr))
		ptr = null;
}
///ditto
void dispose(bool runDestructors=true, T)(scope AllocatorInterface allocator, scope auto ref T* ptr)
if(!is(T == class) && !is(T == interface)){
	static if(runDestructors && is(T == struct))
		destroy!false(*ptr);
	allocator.deallocate((() @trusted => ptr[0..1])());
	static if(__traits(isRef, ptr))
		ptr = null;
}
///
nothrow @nogc pure unittest{
	import memterface.allocator;
	int* i = CAllocator().constructNew!int(5);
	assert(*i == 5);
	CAllocator().dispose(i);
	assert(i is null);
}


/**
Destroys `ptr` if `runDestructors` is `true`, and then deallocates it with `allocator`.
This method is recommended over just passing a class instance directly to `allocator.deallocate`
due to runtime polymorphism; and is required for class instances allocated with `constructNew` or
`initNew` because they need to be passed through `removeAlignment` first.

`ptr` must have been allocated by `allocator`.

Similar to `dispose` from `std.experimental.allocator`.
*/
void dispose(bool runDestructors=true, Allocator, T)(scope auto ref Allocator allocator, scope auto ref T ptr)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator && (is(T == class) || is(T == interface))){
	static if(is(T == interface))
		auto object = cast(Object)ptr;
	else
		alias object = ptr;
	auto typeID = typeid(object);
	void[] memory = (cast(void*)object)[0..typeID.initializer.length];
	memory = removeAlignment(memory, typeID.talign);
	static if(runDestructors)
		destroy!false(ptr);
	allocator.deallocate(memory);
	static if(__traits(isRef, ptr))
		ptr = null;
}
///ditto
void dispose(bool runDestructors=true, T)(scope AllocatorInterface allocator, scope auto ref T ptr)
if(is(T == class) || is(T == interface)){
	static if(is(T == interface))
		auto object = cast(Object)ptr;
	else
		alias object = ptr;
	auto typeID = typeid(object);
	void[] memory = (cast(void*)object)[0..typeID.initializer.length];
	memory = removeAlignment(memory, typeID.talign);
	static if(runDestructors)
		destroy!false(ptr);
	allocator.deallocate(memory);
	static if(__traits(isRef, ptr))
		ptr = null;
}
///
nothrow @nogc pure unittest{
	import memterface.allocator;
	static class C{
		int i;
		this(int i) nothrow @nogc{ this.i = i; }
	}
	C c = CAllocator().constructNew!C(5);
	assert(c.i == 5);
	CAllocator().dispose(c);
	assert(c is null);
}

/**
Destroys `array` if `runDestructors` is `true`, and then deallocates it with `allocator`.

Does not deallocate any pointers contained within the array itself, which may cause a memory leak
if the caller does not deallocate them first.

`array` must have been allocated by `allocator`.

Similar to `dispose` from `std.experimental.allocator`.
*/
void dispose(bool runDestructors=true, Allocator, T)(scope auto ref Allocator allocator, scope auto ref T[] array)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator){
	static if(runDestructors && (is(T == struct) || is(T == class) || is(T == interface))){
		foreach(ref item; array)
			destroy!false(item);
	}
	allocator.deallocate(array);
	static if(__traits(isRef, array))
		array = null;
}
///ditto
void dispose(bool runDestructors=true, T)(scope AllocatorInterface allocator, scope auto ref T[] array){
	static if(runDestructors && (is(T == struct) || is(T == class) || is(T == interface))){
		foreach(ref item; array)
			destroy!false(item);
	}
	allocator.deallocate(array);
	static if(__traits(isRef, array))
		array = null;
}
///
nothrow @nogc pure unittest{
	import memterface.allocator;
	int[] a = CAllocator().newArray!int(10);
	assert(a.length == 10);
	CAllocator().dispose(a);
	assert(a is null);
}
