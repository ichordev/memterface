/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.

Templates to wrap allocators from [std.experimental.allocator](https://dlang.org/phobos/std_experimental_allocator.html),
wrap allocators that do not provide a mechanism that neatly forwards to `isOwnerOf`, and to turn DBI allocators into
classes with `Classify`.
*/
module memterface.wrap;

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
	import core.exception: onOutOfMemoryError;
	import std.traits: hasFunctionAttributes;
	
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
		size_t resizeImpl()(ref void[] memory, size_t newSize) nothrow{
			if(newSize <= memory.length){
				import std.algorithm.comparison: max;
				memory = memory[0..max(1, newSize)];
			}else{
				static if(hasFunctionAttributes!(Allocator.expand, "nothrow")){
					phobosAllocator.expand(memory, newSize);
				}else{
					try phobosAllocator.expand(memory, newSize);
					catch(Exception ex) assert(0, "`expand` threw an exception: "~ex.toString());
				}
			}
			return memory.length;
		};
		static assert(hasResize!Wrapped);
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
		size_t newSize = gc.resize(memory, 210);
		assert(memory.length == newSize);
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
		this parameter to `true` if you are sure that the data of your allocator at the time of its
		construction is enough to distinguish it from other instances of itself (e.g. your allocator
		only contains a slice). Otherwise, `isOwnerOf` may return `true` erroneously.
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
		(!is(typeof(resizeImpl)) || __traits(isStaticFunction, resizeImpl)) &&
		(!is(typeof(canAllocateImpl)) || __traits(isStaticFunction, canAllocateImpl))
	){
		enum size_t magic = object.hashOf(typeof(this).mangleof);
		static bool isOwnerOf(const(void)[] memory) nothrow @nogc =>
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
		bool isOwnerOf(const(void)[] memory) const nothrow @nogc =>
			memory !is null && magic == getMemoryMagicNumber(restoreMemoryMagicNumber(memory));
	}
	
	private{
		static if(__traits(isStaticFunction, allocateImpl)){
			static void[] _allocateTemplate()(size_t size) nothrow
			out(memory; memory.length == size)
			out(memory; size > 0 ? isOwnerOf(memory) : memory is null) =>
				size > 0 ? truncateMemoryAndSetMagicNumber(allocateImpl(size+magic.sizeof), magic) : null;
		}else{
			void[] _allocateTemplate()(size_t size) nothrow
			out(memory; memory.length == size)
			out(memory; size > 0 ? isOwnerOf(memory) : memory is null) =>
				size > 0 ? truncateMemoryAndSetMagicNumber(allocateImpl(size+magic.sizeof), magic) : null;
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
			out(; memory.length == newSize)
			out(; newSize > 0 ? isOwnerOf(memory) : memory is null){
				void[] fullMemory = restoreMemoryAndSetMagicNumber(memory, 0);
				if(newSize > 0){
					reallocateImpl(fullMemory, newSize+magic.sizeof);
					memory = truncateMemoryAndSetMagicNumber(fullMemory, magic);
				}else{
					deallocateImpl(fullMemory);
					memory = null;
				}
			}
		}else{
			private void _reallocateTemplate()(ref void[] memory, size_t newSize) nothrow
			in(isOwnerOf(memory))
			out(; memory.length == newSize)
			out(; newSize > 0 ? isOwnerOf(memory) : memory is null){
				void[] fullMemory = restoreMemoryAndSetMagicNumber(memory, 0);
				reallocateImpl(fullMemory, newSize+magic.sizeof);
				memory = truncateMemoryAndSetMagicNumber(fullMemory, magic);
			}
		}
		alias reallocate = _reallocateTemplate!();
	}
	static if(is(typeof(resizeImpl))){
		static if(__traits(isStaticFunction, resizeImpl)){
			private static size_t _resizeTemplate()(ref void[] memory, size_t newSize) nothrow
			in(isOwnerOf(memory))
			out(; isOwnerOf(memory))
			out(retSize; retSize == memory.length){
				void[] fullMemory = restoreMemoryMagicNumber(memory);
				scope(exit) memory = fullMemory[magic.sizeof..$];
				return resizeImpl(fullMemory, newSize+magic.sizeof) - magic.sizeof;
			}
		}else{
			private size_t _resizeTemplate()(ref void[] memory, size_t newSize) nothrow
			in(isOwnerOf(memory))
			out(; isOwnerOf(memory))
			out(retSize; retSize == memory.length){
				void[] fullMemory = restoreMemoryMagicNumber(memory);
				scope(exit) memory = fullMemory[magic.sizeof..$];
				return resizeImpl(fullMemory, newSize+magic.sizeof) - magic.sizeof;
			}
		}
		alias resize = _resizeTemplate!();
	}
	static if(is(typeof(canAllocateImpl))){
		static if(__traits(isStaticFunction, canAllocateImpl)){
			private static bool _canAllocateTemplate()(size_t size) nothrow
			out(ret; size > 0 || ret) =>
				canAllocateImpl(size+magic.sizeof);
		}else{
			private bool _canAllocateTemplate()(size_t size) const nothrow
			out(ret; size > 0 || ret) =>
				canAllocateImpl(size+magic.sizeof);
		}
		alias canAllocate = _canAllocateTemplate!();
	}
}

pragma(inline,true){
	inout(void)[] restoreMemoryMagicNumber(inout(void)[] memory) nothrow @nogc =>
		(memory.ptr-size_t.sizeof)[0..memory.length+size_t.sizeof];
	
	size_t getMemoryMagicNumber(const(void)[] fullMemory) nothrow @nogc pure @trusted =>
		*cast(const(size_t)*)fullMemory[0..size_t.sizeof]; //TODO: stop this from sometimes segfaulting by accessing unallocated memory when checking isOwnerOf on invalid/deallocated memory :(
	
	void[] restoreMemoryAndSetMagicNumber(void[] memory, size_t magic) nothrow @nogc{
		void[] fullMemory = (memory.ptr-size_t.sizeof)[0..memory.length+size_t.sizeof];
		*cast(size_t*)fullMemory[0..size_t.sizeof] = magic;
		return fullMemory;
	}
	void[] truncateMemoryAndSetMagicNumber(void[] fullMemory, size_t magic) nothrow @nogc pure @trusted{
		*cast(size_t*)fullMemory[0..size_t.sizeof] = magic;
		return fullMemory[size_t.sizeof..$];
	}
}

/**
Creates a class that wraps an instance of `Allocator`.
Can be used to pass DBI allocators to non-template functions that only accept `AllocatorInterface`.
*/
class Classify(Allocator): AllocatorInterfacesFor!Allocator
if(isAllocator!Allocator){
	static if(isGlobal!Allocator){
		static Allocator allocator;
		
		this(){}
		this(Allocator allocator){}
	}else{
		Allocator allocator;
		
		this()(auto ref Allocator allocator){
			this.allocator = allocator;
		}
	}
	
	void[] allocate(size_t size) nothrow =>
		allocator.allocate(size);
	
	void deallocate(void[] memory) nothrow =>
		allocator.deallocate(memory);
	
	bool isOwnerOf(const(void)[] memory) const nothrow =>
		allocator.isOwnerOf(memory);
	
	static if(hasReallocate!Allocator){
		void reallocate(ref void[] memory, size_t newSize) nothrow =>
			allocator.reallocate(memory, newSize);
	}
	static if(hasResize!Allocator){
		size_t resize(ref void[] memory, size_t newSize) nothrow =>
			allocator.resize(memory, newSize);
	}
	static if(hasCanAllocate!Allocator){
		bool canAllocate(size_t size) const nothrow
		out(ret; size > 0 || ret) =>
			allocator.canAllocate(size);
	}
}
unittest{
	void testIAlloc(AllocatorInterface ialloc){
		auto mem = ialloc.allocate(300);
		assert(mem.length == 300);
		assert(ialloc.isOwnerOf(mem));
		ialloc.deallocate(mem);
	}
	
	import memterface.allocator.malloc;
	testIAlloc(new Classify!CAllocator(CAllocator()));
	import memterface.allocator.gc;
	testIAlloc(new Classify!GCAllocator(GCAllocator()));
}
