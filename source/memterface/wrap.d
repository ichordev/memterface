/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
/**
Templates to wrap allocators from [std.experimental.allocator](https://dlang.org/phobos/std_experimental_allocator.html),
and to wrap allocators that do not provide a mechanism that neatly forwards to `isOwnerOf`.
*/
module memterface.wrap;

import core.exception;
import std.traits;
import memterface.iface;

/**
Wrap an allocator that uses the `std.experimental.allocator` interface.

When using this wrapper for non-global allocators, you must always call the `Wrapped`'s constructor.
Additionally, beware that when copying a non-global `Wrapped` instance, the copied and original instance
will be considered the same by `isOwnerOf`. Therefore, it is strongly advised that you never re-use a
non-global `Wrapped` instance after a copy of it has been made.

Unless `unsafe` is `true`, each function of the wrapped allocator must be `nothrow`, and the
`deallocate` function is required.

When using this wrapper, `size_t.sizeof` bytes more than requested are always allocated. These bytes are
used to make the `isOwnerOf` function work properly, since `owns` in the `std.experimental.allocator`
may still return `true` even when the passed memory has been deallocated.

Note that using this wrapper does not guarantee 100% conformance to the Memterface API. The wrapped
allocators might fail when they are never supposed to. For instance, when the wrapped allocator...
- Has no `deallocate` function. (Causes `deallocate` to silently do nothing!)
- Returns `false` from `deallocate`.

Params:
	Allocator = The `std.experimental.allocator`-compliant allocator type to wrap.
*/
struct Wrapped(Allocator, bool unsafe=false){
	alias PhobosAllocator = Allocator;
	
	enum monostate = is(typeof(Allocator.instance));
	
	static if(monostate){
		alias phobosAllocator = Allocator.instance;
		mixin WrappedImpl!true;
	}else{
		Allocator phobosAllocator;
		this()(auto ref Allocator allocator){
			static if(__traits(isCopyable, Allocator)){
				this.phobosAllocator = allocator;
			}else{
				import core.lifetime: moveEmplace;
				() @trusted{ moveEmplace(allocator, this.phobosAllocator); }();
			}
			generateMagicNumber();
		}
		mixin WrappedImpl!false;
	}
	mixin ImplementIsOwnerOf!();
	static assert(isAllocator!Wrapped);
}

private mixin template WrappedImpl(bool monostate){
	mixin((monostate ? "\tstatic:\n" : "") ~ q{
	void[] allocateImpl()(size_t size) nothrow{
		void[] memory;
		static if(hasFunctionAttributes!(Allocator.allocate, "nothrow")){
			memory = phobosAllocator.allocate(size);
		}else static if(unsafe){
			try memory = phobosAllocator.allocate(size);
			catch(Exception ex) assert(0, "`allocate` threw an Exception: "~ex.toString());
		}else
			static assert(0, "Cannot wrap non-`nothrow` function `allocate` unless `unsafe` is `true`");
		
		if(memory !is null || size == 0) return memory;
		else onOutOfMemoryError();
	}
	void deallocateImpl()(void[] memory) nothrow{
		static if(is(typeof(Allocator.deallocate(void[].init)) == bool)){
			bool success;
			static if(hasFunctionAttributes!(Allocator.deallocate, "nothrow")){
				success = phobosAllocator.deallocate(memory);
			}else static if(unsafe){
				try success = phobosAllocator.deallocate(memory);
				catch(Exception ex) assert(0, "`deallocate` threw an exception: "~ex.toString());
			}else
				static assert(0, "Cannot wrap non-`nothrow` function `deallocate` unless `unsafe` is `true`");
			
			assert(success, "`deallocate` returned `false`");
		}else static if(!unsafe)
			static assert(0, "Cannot wrap allocator without `deallocate` unless `unsafe` is `true`");
	}
	static if(
		(){ void[] bRef; return is(typeof(Allocator.reallocate(bRef, size_t.init)) == bool); }() &&
		is(typeof(Allocator.reallocate)) && (unsafe || hasFunctionAttributes!(Allocator.reallocate, "nothrow"))
	){
		void reallocateImpl()(ref void[] memory, size_t newSize) nothrow{
			bool success;
			static if(hasFunctionAttributes!(Allocator.reallocate, "nothrow")){
				success = phobosAllocator.reallocate(memory, newSize);
			}else{
				try success = phobosAllocator.reallocate(memory, newSize);
				catch(Exception ex) assert(0, "`reallocate` threw an exception: "~ex.toString());
			}
			if(success) return;
			else onOutOfMemoryError();
		}
		static assert(hasReallocate!Wrapped);
	}
	static if(
		(){ void[] bRef; return is(typeof(Allocator.expand(bRef, size_t.init)) == bool); }() &&
		is(typeof(Allocator.expand)) && (unsafe || hasFunctionAttributes!(Allocator.expand, "nothrow"))
	){
		size_t extendImpl()(ref void[] memory, size_t sizeDelta) nothrow{
			void[] fullMemory = restoreMemoryMagicNumber(memory);
			size_t oldSize = fullMemory.length;
			static if(hasFunctionAttributes!(Allocator.expand, "nothrow")){
				phobosAllocator.expand(fullMemory, sizeDelta);
			}else{
				try phobosAllocator.expand(fullMemory, sizeDelta);
				catch(Exception ex) assert(0, "`expand` threw an exception: "~ex.toString());
			}
			memory = fullMemory[magic.sizeof..$];
			return fullMemory.length - oldSize;
		};
		static assert(hasExtend!Wrapped);
	}});
}

unittest{
	void[] memory;
	import std.experimental.allocator.gc_allocator: GCA = GCAllocator;
	Wrapped!(GCA, true) gc;
	memory = gc.allocate(100);
	gc.reallocate(memory, 200);
	{
		size_t oldSize = memory.length;
		size_t sizeDelta = gc.extend(memory, 10);
		assert(memory.length == oldSize + sizeDelta);
	}
	gc.deallocate(memory);
	
	import std.experimental.allocator.building_blocks.kernighan_ritchie;
	Wrapped!(KRRegion!GCA) krr = KRRegion!GCA(128);
	memory = krr.allocate(100);
	krr.deallocate(memory);
}

/**
Implements an `isOwnerOf` function for a struct or class.

Intended to be used when manually writing a wrapper over an allocator that does not provide a
mechanism that can be forwarded to `isOwnerOf`.

This mixin must be used inside a struct or class with `Impl`-suffixed allocator interface methods,
except for `isOwnerOf`.  For example:
```
struct MyAllocator{
	void[] allocateImpl(size_t size) nothrow{
		//...
	}
	void deallocateImpl(void[] memory){
		//...
	}
	mixin ImplementIsOwnerOf!();
	
	this(...){
		generateMagicNumber();
	}
}
```

The mixin will implement the user-facing allocator interface methods and also an
`isOwnerOf` function. When using this `size_t.sizeof` bytes more than requested are always
allocated. These bytes are used to make the `isOwnerOf` function work

For non-global allocators:
- `this.generateMagicNumber()` must be called in the allocator's constructor in order for
`isOwnerOf` to function correctly.
- When copying an instance of the allocator, the `isOwnerOf` function will not recognise the copy as
a separate instance. This means users of your allocator should be made aware that copying your
allocator will essentially cause the original to become invalid. You may enforce this to improve
safety by invalidating the original after it is copied.

Params:
	hashWithSelf = Makes `generateMagicNumber` use `this` as a hash compliment instead of
		using a static variable. Doing this allows `generateMagicNumber` to be `pure`. Only set
		this parameter to `true` if you are sure that the data of your allocator is enough to
		distinguish it from other instances of itself (e.g. your allocator only contains a slice).
		Otherwise, `isOwnerOf` may return `true` erroneously.
*/
mixin template ImplementIsOwnerOf(bool hashWithSelf=false){
	static assert(is(typeof(this) == struct) || is(typeof(this) == class), "`ImplementIsOwnerOf` must be used in a struct or a class");
	static assert(is(typeof(allocateImpl(size_t()))), "No valid `allocateImpl` function found");
	static assert(is(typeof(deallocateImpl(void[].init))), "No valid `deallocateImpl` function found");
	
	import memterface.wrap;
	static if(
		__traits(isStaticFunction, allocateImpl) &&
		__traits(isStaticFunction, deallocateImpl) &&
		(!is(typeof(reallocateImpl)) || __traits(isStaticFunction, reallocateImpl)) &&
		(!is(typeof(extendImpl)) || __traits(isStaticFunction, extendImpl)) &&
		(!is(typeof(canAllocateImpl)) || __traits(isStaticFunction, canAllocateImpl))
	){
		enum size_t magic = object.hashOf(typeof(this).mangleof);
		static bool isOwnerOf(const(void)[] memory) nothrow @nogc pure @safe =>
			memory !is null && magic == getMemoryMagicNumber(restoreMemoryMagicNumber(memory));
	}else{
		size_t magic;
		enum size_t baseHash = object.hashOf(typeof(this).mangleof);
		static if(hashWithSelf){
			void generateMagicNumber() nothrow @nogc pure @safe{
				magic = object.hashOf(this, baseHash);
			}
		}else{
			void generateMagicNumber() nothrow @nogc @safe{
				static size_t n;
				magic = object.hashOf(n++, baseHash);
			}
		}
		bool isOwnerOf(const(void)[] memory) const nothrow @nogc pure @safe =>
			memory !is null && magic == getMemoryMagicNumber(restoreMemoryMagicNumber(memory));
	}
	
	private{
		static if(__traits(isStaticFunction, allocateImpl)){
			static void[] _allocateTemplate()(size_t size) nothrow
			out(memory; memory.length == size)
			out(memory; (size == 0 && memory is null) || isOwnerOf(memory)) =>
				truncateMemoryAndSetMagicNumber(allocateImpl(size+magic.sizeof), magic);
		}else{
			void[] _allocateTemplate()(size_t size) nothrow
			out(memory; memory.length == size)
			out(memory; (size == 0 && memory is null) || isOwnerOf(memory)) =>
				truncateMemoryAndSetMagicNumber(allocateImpl(size+magic.sizeof), magic);
		}
		static if(__traits(isStaticFunction, deallocateImpl)){
			static void _deallocateTemplate()(void[] memory) nothrow
			in(isOwnerOf(memory)){
				deallocateImpl(restoreMemoryAndSetMagicNumber(memory, 0));
			}
		}else{
			void _deallocateTemplate()(void[] memory) nothrow
			in(isOwnerOf(memory)){
				deallocateImpl(restoreMemoryAndSetMagicNumber(memory, 0));
			}
		}
	}
	alias allocate = _allocateTemplate!();
	alias deallocate = _deallocateTemplate!();
	
	static if(is(typeof(reallocateImpl))){
		static if(__traits(isStaticFunction, reallocateImpl)){
			private static void _reallocateTemplate()(ref void[] memory, size_t newSize) nothrow
			in(isOwnerOf(memory))
			out(; (newSize == 0 && memory is null) || isOwnerOf(memory))
			out(; memory.length == newSize){
				void[] fullMemory = restoreMemoryAndSetMagicNumber(memory, 0);
				reallocateImpl(fullMemory, newSize+magic.sizeof);
				memory = truncateMemoryAndSetMagicNumber(fullMemory, magic);
			}
		}else{
			private void _reallocateTemplate()(ref void[] memory, size_t newSize) nothrow
			in(isOwnerOf(memory))
			out(; (newSize == 0 && memory is null) || isOwnerOf(memory))
			out(; memory.length == newSize){
				void[] fullMemory = restoreMemoryAndSetMagicNumber(memory, 0);
				reallocateImpl(fullMemory, newSize+magic.sizeof);
				memory = truncateMemoryAndSetMagicNumber(fullMemory, magic);
			}
		}
		alias reallocate = _reallocateTemplate!();
	}
	static if(is(typeof(extendImpl))){
		static if(__traits(isStaticFunction, extendImpl)){
			private static size_t _extendTemplate()(ref void[] memory, size_t sizeDelta) nothrow
			in(isOwnerOf(memory))
			out(returnedSizeDelta; returnedSizeDelta <= sizeDelta){
				void[] fullMemory = restoreMemoryMagicNumber(memory);
				scope(exit) memory = fullMemory[magic.sizeof..$];
				return extendImpl(fullMemory, sizeDelta);
			}
		}else{
			private size_t _extendTemplate()(ref void[] memory, size_t sizeDelta) nothrow
			in(isOwnerOf(memory))
			out(returnedSizeDelta; returnedSizeDelta <= sizeDelta){
				void[] fullMemory = restoreMemoryMagicNumber(memory);
				scope(exit) memory = fullMemory[magic.sizeof..$];
				return extendImpl(fullMemory, sizeDelta);
			}
		}
		alias extend = _extendTemplate!();
	}
	static if(is(typeof(canAllocateImpl))){
		static if(__traits(isStaticFunction, canAllocateImpl)){
			private static bool _canAllocateTemplate()(size_t size) nothrow =>
				canAllocateImpl(size+magic.sizeof);
		}else{
			private bool _canAllocateTemplate()(size_t size) const nothrow =>
				canAllocateImpl(size+magic.sizeof);
		}
		alias canAllocate = _canAllocateTemplate!();
	}
}

pragma(inline,true){
	inout(void)[] restoreMemoryMagicNumber(inout(void)[] memory) nothrow @nogc pure @trusted =>
		(memory.ptr-size_t.sizeof)[0..memory.length+size_t.sizeof];
	size_t getMemoryMagicNumber(const(void)[] fullMemory) nothrow @nogc pure @trusted =>
		*cast(const(size_t)*)fullMemory[0..size_t.sizeof];
	void[] restoreMemoryAndSetMagicNumber(void[] memory, size_t magic) nothrow @nogc pure @trusted{
		void[] fullMemory = (memory.ptr-size_t.sizeof)[0..memory.length+size_t.sizeof];
		*cast(size_t*)fullMemory[0..size_t.sizeof] = magic;
		return fullMemory;
	}
	void[] truncateMemoryAndSetMagicNumber(void[] fullMemory, size_t magic) nothrow @nogc pure @trusted{
		*cast(size_t*)fullMemory[0..size_t.sizeof] = magic;
		return fullMemory[size_t.sizeof..$];
	}
}

//returns a number that's different each time the function is called
/*private size_t getHashCompliment() nothrow @nogc @safe{
	version(GNU_InlineAsm){
		version(X86){
			version = GNU_InlineAsm_X86;
		}else version(X86_64){
			version = GNU_InlineAsm_X86_64;
		}
	}
	ulong ret = void;
	version(D_InlineAsm_X86){
		asm nothrow @nogc{
			rdtsc;
			mov ret,EAX;
		}
	}else version(D_InlineAsm_X86_64){
		asm nothrow @nogc{
			rdtsc;
			shl RDX,32;
			or RAX,RDX;
			mov ret,RAX;
		}
	}else version(GNU_InlineAsm_X86){
		asm nothrow @nogc{
			"rdtsc" : "=a"(ret);
		}
	}else version(GNU_InlineAsm_X86_64){
		asm nothrow @nogc{
			"rdtsc";
			"shl $32,%%rdx";
			"or %%rdx,%%rax": "=a"(ret);
		}
	}else{
		ret = (ret << 1) | (((ret>>>30) ^ (~ret>>>34)) & 1);
	}
	return cast(size_t)ret;
}*/
