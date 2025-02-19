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
import std.traits;
import memterface.iface;

private template sizeInMemory(T){
	static if(is(T == class) || is(T == interface))
		enum size_t sizeInMemory = __traits(classInstanceSize, T);
	else static if(is(T == struct) || is(T == union))
		enum size_t sizeInMemory = T.tupleof.length ? T.sizeof : 0;
	else static if(is(T == void))
		enum size_t sizeInMemory = 0;
	else
		enum size_t sizeInMemory = T.sizeof;
}

/**
Allocates enough memory to store an instance of `T` using `allocator`,
and then constructs it with `args`.

For a similar function that handles arrays, see `newArray`.

Similar to `make` from `std.experimental.allocator`.
*/
auto constructNew(T, Allocator, Args...)(auto ref Allocator allocator, auto ref Args args)
if(isAllocator!Allocator){
	import core.internal.lifetime: emplaceRef;
	import core.lifetime: emplace;
	
	auto memory = allocator.allocate(sizeInMemory!T);
	if(!memory.length) return null;
	
	auto construct(){
		static if(is(T == class)){
			return emplace!T(memory, forward!args);
		}else{
			//assume cast is safe as allocation succeeded for `sizeInMemoey!T`
			auto ptr = (() @trusted => cast(T*)memory.ptr)();
			emplaceRef!T(*ptr, forward!args);
			return ptr;
		}
	}
	
	scope(failure){
		//`constructNew` can only be `@safe` if `emplace`/`emplaceRef` is `pure`:
		static if(is(typeof(() pure => construct()))){
			//deallocation here is safe because this is the only reference to this memory
			() nothrow @trusted{ allocator.deallocate(memory); }();
		}else{
			allocator.deallocate(memory);
		}
	}
	
	return construct();
}

private T[] newArrayImpl(T, Allocator)(auto ref Allocator allocator, size_t length){
	static if(T.sizeof <= 1){
		const size = length * T.sizeof;
	}else{
		import core.exception: onOutOfMemoryError;
		import core.checkedint: mulu;
		bool overflow;
		const size = mulu(length, T.sizeof, overflow);
		if(overflow) onOutOfMemoryError();
	}
	auto memory = alloc.allocate(size);
	return (() @trusted => cast(T[])memory)();
}

T[] newArray(T, Allocator)(auto ref Allocator allocator, size_t length){
	auto array = newArrayImpl!(T, Allocator)(forward!allocator, length);
	() nothrow @nogc pure @trusted{
		alias U = Unqual!T;
		static if(__traits(isZeroInit, T)){ //types with only 00 bytes
			import core.stdc.string: memset;
			memset(array.ptr, 0x00, T.sizeof * array.length);
		}else static if(is(U == char) || is(U == wchar)){ //types with only FF bytes
			import core.stdc.string: memset;
			memset(array.ptr, 0xFF, T.sizeof * array.length);
		}else{
			import core.stdc.string: memcpy;
			import std.algorithm.comparison: min;
			auto initSymbol = T.init;
			foreach(ref item; array)
				memcpy(&item, &initSymbol, T.sizeof);
		}
	}();
	return array;
}

/**
Destroys `ptr` and then deallocates it with `allocator`.
`ptr` must have been allocated by `allocator`.

Similar to `dispose` from `std.experimental.allocator`.
*/
void dispose(Allocator, T)(auto ref Allocator allocator, auto ref T* ptr){
	static if(hasElaborateDestructor!T)
		destroy(*ptr);
	
	allocator.deallocate((cast(void*)ptr)[0..T.sizeof]);
	static if(__traits(isRef, ptr))
		ptr = null;
}

///Ditto
void dispose(Allocator, T)(auto ref Allocator allocator, auto ref T ptr)
if(is(T == class) || is(T == interface)){
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
void dispose(Allocator, T)(auto ref Allocator allocator, auto ref T[] array){
	static if(hasElaborateDestructor!(typeof(array[0]))){
		foreach(ref item; array)
			destroy(item);
	}
	allocator.deallocate(array);
	static if(__traits(isRef, array))
		array = null;
}
