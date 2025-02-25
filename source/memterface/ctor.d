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

private template sizeInMemory(T){
	static if(is(T == class) || is(T == interface))
		enum size_t sizeInMemory = __traits(classInstanceSize, T);
	else
		enum size_t sizeInMemory = T.sizeof;
}

/**
Allocates enough memory to store an instance of `T` using `allocator`, and then constructs it with `args`.

Returns: A newly allocated & constructed instance of `T`; or `null` if `allocator` defines
	`canAllocate` and it returns `false`. May also return `null` if `T.sizeof == 0`.

For a similar function that handles arrays, see `newArray`.

Similar to `make` from `std.experimental.allocator`.
*/
T* constructNew(T, Allocator, Args...)(auto ref Allocator allocator, auto ref Args args)
if(isAllocator!Allocator){
	static if(hasCanAllocate!Allocator){
		if(!allocator.canAllocate(sizeInMemory!T))
			return null;
	}
	auto memory = allocator.allocate(sizeInMemory!T);
	return emplace!T(memory, forward!args);
}
unittest{
	import memterface.allocator;
	int* i = GCAllocator().constructNew!int(5);
	assert(*i == 5);
	assert(BottomAllocator().constructNew!int() is null);
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
T[] newArray(T, Allocator)(auto ref Allocator allocator, size_t length) nothrow
if(isAllocator!Allocator){
	const arraySize = newArraySize!T(length);
	
	static if(hasCanAllocate!Allocator){
		if(!allocator.canAllocate(arraySize))
			return null;
	}
	auto memory = allocator.allocate(arraySize);
	auto array = (() @trusted => cast(T[])memory)();
	newArrayInit(array);
	return array;
}
unittest{
	import memterface.allocator;
	int[] a = GCAllocator().newArray!int(10);
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
bool resizeArray(Allocator, T)(auto ref Allocator allocator, ref T[] array, size_t newLength)
if(isAllocator!Allocator){
	const oldLength = array.length;
	if(newLength != oldLength){
		const arraySize = newArraySize!T(newLength);
		static if(hasCanAllocate!Allocator){
			if(!allocator.canAllocate(arraySize))
				return false;
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
			auto memory = allocator.allocate(arraySize);
			memory[0..oldMemory.length] = oldMemory[];
			allocator.deallocate(oldMemory);
		}
		array = (() @trusted => cast(T[])memory)();
		if(newLength > oldLength){
			newArrayInit(array[oldLength..$]);
		}
	}
	return true;
}

unittest{
	import std.exception;
	import memterface.allocator;
	static class DestructorException: Exception{ mixin basicExceptionCtors!(); }
	static struct X{
		int i;
		~this(){ throw new DestructorException("Destructor called!"); }
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
unittest{
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
void dispose(Allocator, T)(auto ref Allocator allocator, auto ref T* ptr){
	static if(is(typeof(doDestroy(*ptr))))
		doDestroy(ptr);
	allocator.deallocate((cast(void*)ptr)[0..T.sizeof]);
	static if(__traits(isRef, ptr))
		ptr = null;
}

///Ditto
void dispose(Allocator, T)(auto ref Allocator allocator, auto ref T ptr)
if(isAllocator!Allocator && (is(T == class) || is(T == interface))){
	static if(is(T == interface)){
		auto object = cast(Object)ptr;
	}else{
		alias object = ptr;
	}
	auto memory = (cast(void*)object)[0..typeid(object).initializer.length];
	destroy(ptr);
	allocator.deallocate(memory);
	static if(__traits(isRef, ptr))
		ptr = null;
}

/**
Destroys `array` and then deallocates it with `allocator`.

`array` must have been allocated by `allocator`.

Similar to `dispose` from `std.experimental.allocator`.
*/
void dispose(Allocator, T)(auto ref Allocator allocator, auto ref T[] array)
if(isAllocator!Allocator){
	static if(is(typeof(doDestroy(array[0])))){
		foreach(ref item; array)
			doDestroy(item);
	}
	allocator.deallocate(array);
	static if(__traits(isRef, array))
		array = null;
}
