/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
/**
Functions to automatically allocate memory and construct/initialise a data type into it.
*/
module memterface.ctor;

import core.lifetime;
import std.algorithm.comparison, std.traits;
import memterface.iface;

/**
Return a sub-slice of `memory` which starts on an `alignment`-byte boundary. The length of
the returned sub-slice is `memory.length - alignment` bytes, so you should
allocate `desiredSize + alignment` bytes of mmeory to pass to this function.

Since this function only returns a sub-slice of `memory`, you cannot reliably call the original
allocator's deallocate/reallocate/etc. functions with the returned sub-slice.
Instead, you can call `removeAlignment(subSlice, alignment)` and pass its return value to the
allocator instead.

See_Also: `removeAlignment`
*/
void[] forceAlignment(return scope void[] memory, size_t alignment) nothrow @nogc pure @safe
in(alignment >= 1 && alignment <= 256)
in(memory.length >= alignment){
	const metaInd = cast(ubyte)((cast(size_t)&memory[0] - ubyte.sizeof) % alignment);
	const startInd = metaInd + ubyte.sizeof;
	*(() @trusted => cast(ubyte*)memory[metaInd..startInd])() = metaInd; //write the start index as a byte of metadata
	return memory[startInd..$-(alignment - startInd)];
}
nothrow @nogc pure @safe unittest{
	import memterface.allocator;
	enum alignment = 256;
	void[] m = CAllocator().allocate(12 + alignment);
	assert(cast(size_t)forceAlignment(m, alignment).ptr % alignment == 0);
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
void[] removeAlignment(return scope void[] alignedMemory, size_t alignment) nothrow @nogc pure
in(alignment >= 1 && alignment <= 256)
in(alignedMemory !is null)
out(memory; memory.length == alignedMemory.length + alignment){
	const meta = *cast(ubyte*)(alignedMemory.ptr-1);
	assert(meta < alignment, "`alignment` is less than the alignment that was passed to `forceAlignment`; or `alignedMemory` wasn't returned by `forceAlignment`");
	const start = meta + ubyte.sizeof;
	return (alignedMemory.ptr - start)[0..alignedMemory.length + alignment];
}
nothrow @nogc pure unittest{
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

private void[] allocDBIImpl(Allocator)(return scope ref Allocator allocator, size_t size) nothrow{
	static if(hasCanAllocate!Allocator){
		if(allocator.canAllocate(size)){
		}else return null;
	}
	return allocator.allocate(size);
}
private void[] allocIFaceImpl(return scope AllocatorInterface allocator, size_t size) nothrow{
	if(auto allocWCanAlloc = cast(AllocatorInterfaceWithCanAllocate)allocator){
		if(allocWCanAlloc.canAllocate(size)){
		}else return null;
	}
	return allocator.allocate(size);
}

private auto initNewImpl(T)(return scope void[] memory) nothrow{
	static if(is(T == class)){
		memory = forceAlignment(memory, __traits(classInstanceAlignment, T));
		return () @trusted{
			memory[] = __traits(initSymbol, T)[];
			return cast(T)memory.ptr;
		}();
	}else{
		T* ret = (() @trusted => cast(T*)memory)();
		*ret = T.init;
		return ret;
	}
}

/**
Allocates enough memory to store an instance of `T` using `allocator`, and then initialises it to
`T.init`; or `__traits(initSymbol, T)` if `T` is a class.

Returns: A newly allocated & constructed instance of `T`; or `null` if `allocator` defines
	`canAllocate` and it returns `false`. May also return `null` if `T.sizeof == 0`.

See_Also: `newArray` is a similar function that handles arrays.

Similar to `make` from `std.experimental.allocator`.
*/
auto initNew(T, Allocator)(return scope auto ref Allocator allocator) nothrow
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator){
	auto memory = allocDBIImpl!Allocator(allocator, sizeInMemory!T);
	static if(sizeInMemory!T == 0 || hasCanAllocate!Allocator){
		if(memory !is null){
		}else return null;
	}
	return initNewImpl!T(memory);
}
///Ditto
auto initNew(T)(return scope AllocatorInterface allocator) nothrow{
	if(auto memory = allocIFaceImpl(allocator, sizeInMemory!T))
		return initNewImpl!T(memory);
	return null;
}
nothrow @nogc pure @safe unittest{
	import memterface.allocator;
	int* i = CAllocator().initNew!int();
	assert(*i == 0);
	assert(BottomAllocator().initNew!int() is null);
}

/**
Allocates enough memory to store an instance of `T` using `allocator`, and then constructs it with `args`.

Returns: A newly allocated & constructed instance of `T`; or `null` if `allocator` defines
	`canAllocate` and it returns `false`. May also return `null` if `T.sizeof == 0`.

See_Also: `newArray` is a similar function that handles arrays.

Similar to `make` from `std.experimental.allocator`.
*/
auto constructNew(T, Allocator, Args...)(return scope auto ref Allocator allocator, auto ref Args args)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator){
	auto memory = allocDBIImpl!Allocator(allocator, sizeInMemory!T);
	static if(sizeInMemory!T == 0 || hasCanAllocate!Allocator){
		if(memory !is null){
		}else return null;
	}
	static if(is(T == class))
		memory = forceAlignment(memory, __traits(classInstanceAlignment, T));
	return emplace!T(memory, forward!args);
}
///Ditto
auto constructNew(T, Args...)(return scope AllocatorInterface allocator, auto ref Args args){
	if(auto memory = allocIFaceImpl(allocator, sizeInMemory!T)){
		static if(is(T == class))
			memory = forceAlignment(memory, __traits(classInstanceAlignment, T));
		return emplace!T(memory, forward!args);
	}
	return null;
}

pragma(inline,true)
private size_t newArraySize(T)(size_t length) nothrow @nogc pure @safe{
	static if(T.sizeof <= 1){
		return size = length * T.sizeof;
	}else{
		import core.exception: onOutOfMemoryError;
		import core.checkedint: mulu;
		bool overflow;
		const size = mulu(length, T.sizeof, overflow);
		if(!overflow)
			return size;
		else
			onOutOfMemoryError();
	}
}

private void newArrayInit(T)(T[] array) nothrow @nogc pure @trusted{
	alias U = Unqual!T;
	static if(__traits(isZeroInit, T)){ //types with only 00 bytes
		import core.stdc.string: memset;
		memset(&array[0], 0x00, T.sizeof * array.length);
	}else static if(is(U == char) || is(U == wchar)){ //types with only FF bytes
		import core.stdc.string: memset;
		memset(&array[0], 0xFF, T.sizeof * array.length);
	}else{
		auto initSymbol = T.init;
		void[] voidArray = array;
		
		import core.stdc.string: memcpy;
		memcpy(&voidArray[0], &initSymbol, T.sizeof);
		size_t alreadyCopied = T.sizeof;
		while(alreadyCopied < voidArray.length){
			const thisCopyLength = min(alreadyCopied, voidArray.length-alreadyCopied);
			memcpy(&voidArray[alreadyCopied], &voidArray[0], thisCopyLength);
			alreadyCopied += thisCopyLength;
		}
	}
}

/**
Allocates enough memory to store an array of `T` with `length` elements using `allocator`,
and then default-initialises each element.

Returns: A newly allocated & default-initialised `T[]`; or `null` if `allocator` defines
	`canAllocate` and it returns `false`. May also return `null` if `T.sizeof == 0`.

Similar to `makeArray` from `std.experimental.allocator`.
*/
T[] newArray(T, Allocator)(return scope auto ref Allocator allocator, size_t length) nothrow
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator){
	if(auto memory = allocDBIImpl!Allocator(allocator, newArraySize!T(length))){
		T[] array = (() @trusted => cast(T[])memory)();
		newArrayInit(array);
		return array;
	}
	return null;
}
///Ditto
T[] newArray(T)(return scope AllocatorInterface allocator, size_t length) nothrow{
	if(auto memory = allocIFaceImpl(allocator, newArraySize!T(length))){
		T[] array = (() @trusted => cast(T[])memory)();
		newArrayInit(array);
		return array;
	}
	return null;
}
nothrow @nogc pure @safe unittest{
	import memterface.allocator;
	int[] a = CAllocator().newArray!int(10);
	foreach(ref item; a)
		assert(item == 0);
	assert(BottomAllocator().newArray!int(1) is null);
}

/**
Resizes `array` to have `newLength` elements using `allocator`.

`array` must have been originally allocated with `allocator`.

New elements are default-initialised. Removed elements get destroyed appropriately.
Copy constructors are not called.

Returns: `true`; unless `allocator` defines `canAllocate` and it returns `false`.
*/
bool resizeArray(Allocator, T)(return scope auto ref Allocator allocator, scope ref T[] array, size_t newLength)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator){
	const oldLength = array.length;
	if(newLength != oldLength){
		const arraySize = newArraySize!T(newLength);
		static if(hasCanAllocate!Allocator){
			if(allocator.canAllocate(arraySize)){
			}else return false;
		}
		static if(is(typeof(doDestroy(array[0])))){
			if(newLength < oldLength){
				foreach(ref item; array[newLength..$])
					doDestroy(item);
			}
		}
		static if(hasReallocate!Allocator){
			void[] memory = array;
			allocator.reallocate(memory, arraySize);
		}else{
			void[] oldMemory = array;
			void[] memory = allocator.allocate(arraySize);
			memory[0..oldMemory.length] = oldMemory[];
			allocator.deallocate(oldMemory);
		}
		array = (() @trusted => cast(T[])memory)();
		if(newLength > oldLength)
			newArrayInit(array[oldLength..$]);
	}
	return true;
}
///Ditto
bool resizeArray(T)(return scope AllocatorInterface allocator, scope ref T[] array, size_t newLength){
	const oldLength = array.length;
	if(newLength != oldLength){
		const arraySize = newArraySize!T(newLength);
		if(auto allocWCanAlloc = cast(AllocatorInterfaceWithCanAllocate)allocator){
			if(allocWCanAlloc.canAllocate(arraySize)){
			}else return false;
		}
		static if(is(typeof(doDestroy(array[0])))){
			if(newLength < oldLength){
				foreach(ref item; array[newLength..$])
					doDestroy(item);
			}
		}
		void[] memory;
		if(auto allocWRealloc = cast(AllocatorInterfaceWithReallocate)allocator){
			memory = array;
			allocator.allocWRealloc(memory, arraySize);
		}else{
			void[] oldMemory = array;
			memory = allocator.allocate(arraySize);
			memory[0..oldMemory.length] = oldMemory[];
			allocator.deallocate(oldMemory);
		}
		array = (() @trusted => cast(T[])memory)();
		if(newLength > oldLength)
			newArrayInit(array[oldLength..$]);
	}
	return true;
}
pure unittest{
	import std.exception;
	import memterface.allocator;
	static class DestructorException: Exception{ mixin basicExceptionCtors!(); }
	static struct X{
		int i;
		~this() pure{ throw new DestructorException("Destructor called!"); }
	}
	X[] a = CAllocator().newArray!X(10);
	assert(CAllocator().resizeArray(a, 20) == true);
	foreach(ref item; a)
		assert(item.i == 0);
	assertThrown!DestructorException(CAllocator().resizeArray(a, 19));
}

private void doDestroy(T)(ref T ptr){
	static if(hasElaborateDestructor!T || is(T == class) || is(T == interface)){
		destroy(ptr);
	}else static assert(0);
}
nothrow @nogc pure @safe unittest{
	static struct X1{}
	static struct X2{ ~this(){} }
	static class X3{}
	X1 x1; X2 x2; X3 x3;
	static assert(!is(typeof(doDestroy(x1))));
	static assert(is(typeof(doDestroy(x2))));
	static assert(is(typeof(doDestroy(x3))));
}

/**
Destroys `ptr` and then deallocates it with `allocator`.

`ptr` must have been allocated by `allocator`.

Similar to `dispose` from `std.experimental.allocator`.
*/
void dispose(Allocator, T)(scope auto ref Allocator allocator, scope auto ref T* ptr)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator){
	static if(is(typeof(doDestroy(*ptr))))
		doDestroy(ptr);
	allocator.deallocate((() @trusted => ptr[0..1])());
	static if(__traits(isRef, ptr))
		ptr = null;
}
///Ditto
void dispose(T)(scope AllocatorInterface allocator, scope auto ref T* ptr){
	static if(is(typeof(doDestroy(*ptr))))
		doDestroy(ptr);
	allocator.deallocate((() @trusted => ptr[0..1])());
	static if(__traits(isRef, ptr))
		ptr = null;
}

///Ditto
void dispose(Allocator, T)(scope auto ref Allocator allocator, scope auto ref T ptr)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator && (is(T == class) || is(T == interface))){
	static if(is(T == interface)){
		auto object = cast(Object)ptr;
	}else{
		alias object = ptr;
	}
	auto typeID = typeid(object);
	void[] memory = (cast(void*)object)[0..typeID.initializer.length];
	memory = removeAlignment(memory, typeID.talign);
	destroy(ptr);
	allocator.deallocate(memory);
	static if(__traits(isRef, ptr))
		ptr = null;
}
///Ditto
void dispose(T)(scope AllocatorInterface allocator, scope auto ref T ptr)
if(is(T == class) || is(T == interface)){
	static if(is(T == interface)){
		auto object = cast(Object)ptr;
	}else{
		alias object = ptr;
	}
	auto typeID = typeid(object);
	void[] memory = (cast(void*)object)[0..typeID.initializer.length];
	memory = removeAlignment(memory, typeID.talign);
	destroy(ptr);
	allocator.deallocate(memory);
	static if(__traits(isRef, ptr))
		ptr = null;
}

/**
Destroys `array` and then deallocates it with `allocator`.

Does not deallocate any pointers contained within the array itself, which may cause a memory leak
if the caller does not deallocate them first.

`array` must have been allocated by `allocator`.

Similar to `dispose` from `std.experimental.allocator`.
*/
void dispose(Allocator, T)(scope auto ref Allocator allocator, scope auto ref T[] array)
if(!is(Allocator: AllocatorInterface) && isAllocator!Allocator){
	static if(is(typeof(doDestroy(array[0])))){
		foreach(ref item; array)
			doDestroy(item);
	}
	allocator.deallocate(array);
	static if(__traits(isRef, array))
		array = null;
}
///Ditto
void dispose(T)(scope AllocatorInterface allocator, scope auto ref T[] array){
	static if(is(typeof(doDestroy(array[0])))){
		foreach(ref item; array)
			doDestroy(item);
	}
	allocator.deallocate(array);
	static if(__traits(isRef, array))
		array = null;
}

nothrow unittest{
	import memterface.allocator;
	static class C{
		int i;
		this(int i) nothrow{ this.i = i; }
	}
	C c = CAllocator().constructNew!C(5);
	assert(c.i == 5);
	CAllocator().dispose(c);
	assert(c is null);
	
	int* i = CAllocator().constructNew!int(5);
	assert(*i == 5);
	CAllocator().dispose(i);
	assert(i is null);
	
	int[] a = CAllocator().newArray!int(10);
	assert(a.length == 10);
	CAllocator().dispose(a);
	assert(a is null);
}
