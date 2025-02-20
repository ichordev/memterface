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
import std.typecons: Ternary;
import memterface.iface;

/**
Wrap an allocator that uses the std.experimental.allocator interface.

Unless `unsafe` is `true`, each function of the wrapped allocator must be `nothrow`, and
`deallocate` and `owns` functions are required. If you need to use an allocator that throws
or does not have `owns`, see `WrapUnsafe` below.

Note that using this wrapper does not guarantee 100% conformance to the Memterface API. The wrapped
allocators might fail when they are never supposed to. For instance, when the wrapped allocator...
- Has no `deallocate` function. (Causes `deallocate` to silently fail!)
- Returns `false` from `deallocate` function returns `false`.
- Returns `Ternary.unknown` from `owns`.
- Throws an `Exception` (not an `Error`). (Causes an `assert(0)`)

Params:
	Allocator = The `std.experimental.allocator`-compliant allocator type to wrap.
*/
struct Wrapped(Allocator, bool unsafe=false){
	alias PhobosAllocator = Allocator;
	
	private enum monostate = is(typeof(Allocator.instance));
	
	static if(monostate){
		private enum staticDef = "static ";
		private alias phobosAllocator = Allocator.instance;
	}else{
		Allocator phobosAllocator;
		private enum staticDef = "";
		
		this()(auto ref Allocator allocator){
			moveEmplace(allocator, this.phobosAllocator);
		}
	}
	
	mixin(
	staticDef~
	q{void[] allocate(size_t size) nothrow
	out(memory; memory.length == size){
		static if(hasFunctionAttributes!(Allocator.allocate, "nothrow")){
			auto memory = phobosAllocator.allocate(size);
		}else static if(unsafe){
			void[] memory;
			try memory = phobosAllocator.allocate(size);
			catch(Exception ex) assert(0, "`allocate` threw an Exception: "~ex.toString());
		}else
			static assert(0, "Cannot wrap non-`nothrow` function `allocate` unless `unsafe` is `true`");
		
		if(memory !is null || size == 0)
			return memory;
		else
			onOutOfMemoryError();
	}
	}~staticDef~
	q{void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory)){
		static if(is(typeof(Allocator.deallocate(void[].init)) == bool)){
			static if(hasFunctionAttributes!(Allocator.deallocate, "nothrow")){
				const success = phobosAllocator.deallocate(memory);
			}else static if(unsafe){
				bool success;
				try success = phobosAllocator.deallocate(memory);
				catch(Exception ex) assert(0, "`deallocate` threw an Exception: "~ex.toString());
			}else
				static assert(0, "Cannot wrap non-`nothrow` function `deallocate` unless `unsafe` is `true`");
			
			assert(success, "`deallocate` returned `false`");
		}else static if(!unsafe)
			static assert(0, "Cannot wrap allocator without `deallocate` unless `unsafe` is `true`");
	}
	}~staticDef~
	q{bool isOwnerOf(void[] memory) nothrow{
		static if(is(typeof(Allocator.owns(void[].init)) == Ternary)){
			static if(hasFunctionAttributes!(Allocator.owns, "nothrow")){
				const isOwner = phobosAllocator.owns(memory);
			}else static if(unsafe){
				bool isOwner;
				try isOwner = phobosAllocator.owns(memory);
				catch(Exception ex) assert(0, "`owns` threw an Exception: "~ex.toString());
			}else
				static assert(0, "Cannot wrap non-`nothrow` function `owns` unless `unsafe` is `true`");
			assert(isOwner != Ternary.unknown, "`owns` returned `Ternary.unknown`");
			return isOwner != Ternary.no;
		}else static if(unsafe)
			return memory !is null;
		else
			static assert(0, "Cannot wrap allocator without `owns` unless `unsafe` is `true`");
	}
	});
	static assert(isAllocator!Wrapped);
	
	static if(
		(){ void[] b; return is(typeof(Allocator.reallocate(b, size_t.init)) == bool); }() &&
		(unsafe || hasFunctionAttributes!(Allocator.reallocate, "nothrow"))
	){
		mixin(staticDef~q{
		void reallocate(ref void[] memory, size_t newSize) nothrow
		in(isOwnerOf(memory))
		out(; memory.length == newSize){
			if(phobosAllocator.reallocate(memory, newSize))
				return;
			else
				onOutOfMemoryError();
		}});
		static assert(hasReallocate!Wrapped);
	}
	static if(
		(){ void[] b; return is(typeof(Allocator.expand(b, size_t.init)) == bool); }() &&
		(unsafe || hasFunctionAttributes!(Allocator.expand, "nothrow"))
	){
		mixin(staticDef~q{
		size_t extend(ref void[] memory, size_t sizeDelta) nothrow
		in(isOwnerOf(memory)){
			size_t oldSize = memory.length;
			phobosAllocator.expand(memory, sizeDelta);
			return memory.length - oldSize;
		}});
		static assert(hasExtend!Wrapped);
	}
}

unittest{
	void[] memory;
	import std.experimental.allocator.gc_allocator;
	Wrapped!(GCAllocator, true) gc;
	memory = gc.allocate(100);
	gc.reallocate(memory, 200);
	{
		size_t oldSize = memory.length;
		size_t sizeDelta = gc.extend(memory, 10);
		assert(memory.length == oldSize + sizeDelta);
	}
	gc.deallocate(memory);
	
	import std.experimental.allocator.building_blocks.kernighan_ritchie;
	Wrapped!(KRRegion!GCAllocator) krr = KRRegion!GCAllocator(128);
	memory = krr.allocate(100);
	krr.deallocate(memory);
}
