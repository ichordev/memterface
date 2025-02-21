/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
/**
Templates to wrap allocators from [std.experimental.allocator](https://dlang.org/phobos/std_experimental_allocator.html).
*/
module memterface.wrap;

import core.exception, core.lifetime;
import std.traits;
import memterface.iface;

/**
Wrap an allocator that uses the std.experimental.allocator interface.

Unless `unsafe` is `true`, each function of the wrapped allocator must be `nothrow`, and the
`deallocate` and `owns` functions are required.

When using this wrapper, `size_t.sizeof` bytes more than requested are always allocated. These are
used to make the `isOwnerOf` function work properly, since `owns` in the std.experimental.allocator
may still return `true` even when the passed memory has been deallocated.

Note that using this wrapper does not guarantee 100% conformance to the Memterface API. The wrapped
allocators might fail when they are never supposed to. For instance, when the wrapped allocator...
- Has no `deallocate` function. (Causes `deallocate` to silently do nothing!)
- Returns `false` from `deallocate`.
- Returns `Ternary.unknown` from `owns`.
- Throws an `Exception` (not an `Error`). (Causes an `assert(0)`)

Params:
	Allocator = The `std.experimental.allocator`-compliant allocator type to wrap.
*/
struct Wrapped(Allocator, bool unsafe=false){
	alias PhobosAllocator = Allocator;
	
	enum monostate = is(typeof(Allocator.instance));
	
	static if(monostate){
		private enum staticDef = "static ";
		alias phobosAllocator = Allocator.instance;
		private enum size_t magic = Allocator.mangleof.hashOf;
	}else{
		private enum staticDef = "";
		Allocator phobosAllocator;
		private size_t magic = size_t.max;
		this()(auto ref Allocator allocator){
			moveEmplace(allocator, this.phobosAllocator);
			enum size_t baseHash = Allocator.mangleof.hashOf;
			magic = cast(uint)this.phobosAllocator.hashOf(baseHash);
		}
	}
	
	mixin(
	staticDef~
	q{void[] allocate(size_t size) nothrow
	out(memory; memory.length == size){
		static if(hasFunctionAttributes!(Allocator.allocate, "nothrow")){
			auto memory = phobosAllocator.allocate(size+magic.sizeof);
		}else static if(unsafe){
			void[] memory;
			try memory = phobosAllocator.allocate(size+magic.sizeof);
			catch(Exception ex) assert(0, "`allocate` threw an Exception: "~ex.toString());
		}else
			static assert(0, "Cannot wrap non-`nothrow` function `allocate` unless `unsafe` is `true`");
		
		if(memory !is null || size == 0){
			*(() @trusted => cast(typeof(magic)*)memory[0..magic.sizeof])() = magic;
			return memory[magic.sizeof..$];
		}else onOutOfMemoryError();
	}
	}~staticDef~
	q{void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory)){
		static if(is(typeof(Allocator.deallocate(void[].init)) == bool)){
			ubyte[] fullMemory = (() @trusted => (cast(ubyte*)memory.ptr-magic.sizeof)[0..memory.length+magic.sizeof])();
			fullMemory[0..magic.sizeof] = 0;
			
			bool success;
			static if(hasFunctionAttributes!(Allocator.deallocate, "nothrow")){
				success = phobosAllocator.deallocate(fullMemory);
			}else static if(unsafe){
				try success = phobosAllocator.deallocate(fullMemory);
				catch(Exception ex) assert(0, "`deallocate` threw an exception: "~ex.toString());
			}else
				static assert(0, "Cannot wrap non-`nothrow` function `deallocate` unless `unsafe` is `true`");
			
			assert(success, "`deallocate` returned `false`");
		}else static if(!unsafe)
			static assert(0, "Cannot wrap allocator without `deallocate` unless `unsafe` is `true`");
	}
	}~staticDef~
	q{bool isOwnerOf(const(void)[] memory) nothrow{
		if(memory !is null){
			void[] fullMemory = (() @trusted => (cast(void*)memory.ptr-magic.sizeof)[0..memory.length+magic.sizeof])();
			
			import std.typecons: Ternary;
			static if(is(typeof(Allocator.owns(void[].init)) == Ternary)){
				Ternary ownsResult;
				static if(hasFunctionAttributes!(Allocator.owns, "nothrow")){
					ownsResult = phobosAllocator.owns(fullMemory);
				}else static if(unsafe){
					try ownsResult = phobosAllocator.owns(fullMemory);
					catch(Exception ex) assert(0, "`owns` threw an exception: "~ex.toString());
				}else
					static assert(0, "Cannot wrap non-`nothrow` function `owns` unless `unsafe` is `true`");
				assert(ownsResult != Ternary.unknown, "`owns` returned `Ternary.unknown`");
				
				const isOwner = ownsResult != Ternary.no;
			}else static if(unsafe)
				const isOwner = true;
			else
				static assert(0, "Cannot wrap allocator without `owns` unless `unsafe` is `true`");
			
			if(isOwner)
				return magic == (() @trusted => *cast(typeof(magic)*)fullMemory[0..magic.sizeof])();
		}
		return false;
	}
	});
	static assert(isAllocator!Wrapped);
	
	static if(
		(){ void[] bRef; return is(typeof(Allocator.reallocate(bRef, size_t.init)) == bool); }() && is(typeof(Allocator.reallocate)) &&
		(unsafe || hasFunctionAttributes!(Allocator.reallocate, "nothrow"))
	){
		mixin(staticDef~q{
		void reallocate(ref void[] memory, size_t newSize) nothrow
		in(isOwnerOf(memory))
		out(; memory.length == newSize){
			ubyte[] fullMemoryUBytes = (() @trusted => (cast(ubyte*)memory.ptr-magic.sizeof)[0..memory.length+magic.sizeof])();
			fullMemoryUBytes[0..magic.sizeof] = 0;
			void[] fullMemory = fullMemoryUBytes;
			
			bool success;
			static if(hasFunctionAttributes!(Allocator.reallocate, "nothrow")){
				success = phobosAllocator.reallocate(fullMemory, newSize+magic.sizeof);
			}else{
				try success = phobosAllocator.reallocate(fullMemory, newSize+magic.sizeof);
				catch(Exception ex) assert(0, "`reallocate` threw an exception: "~ex.toString());
			}
			if(success){
				*(() @trusted => cast(typeof(magic)*)fullMemory[0..magic.sizeof])() = magic;
				memory = fullMemory[magic.sizeof..$];
			}else onOutOfMemoryError();
		}});
		static assert(hasReallocate!Wrapped);
	}
	static if(
		(){ void[] bRef; return is(typeof(Allocator.expand(bRef, size_t.init)) == bool); }() && is(typeof(Allocator.expand)) &&
		(unsafe || hasFunctionAttributes!(Allocator.expand, "nothrow"))
	){
		mixin(staticDef~q{
		size_t extend(ref void[] memory, size_t sizeDelta) nothrow
		in(isOwnerOf(memory)){
			void[] fullMemory = (() @trusted => (memory.ptr-magic.sizeof)[0..memory.length+magic.sizeof])();
			size_t oldSize = fullMemory.length;
			static if(hasFunctionAttributes!(Allocator.expand, "nothrow")){
				phobosAllocator.expand(fullMemory, sizeDelta);
			}else{
				try phobosAllocator.expand(fullMemory, sizeDelta);
				catch(Exception ex) assert(0, "`expand` threw an exception: "~ex.toString());
			}
			memory = fullMemory[magic.sizeof..$];
			return fullMemory.length - oldSize;
		}});
		static assert(hasExtend!Wrapped);
	}
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
