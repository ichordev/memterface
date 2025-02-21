/+
+               Copyright 2025 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
module memterface.allocator;

public import
	memterface.allocator.bottom,
	memterface.allocator.gc,
	memterface.allocator.malloc;

unittest{
	import std.meta: AliasSeq;
	import memterface.iface, memterface.wrap;
	
	static foreach(Allocator; AliasSeq!(
		GCAllocator, CAllocator, BottomAllocator,
		(){
			import std.experimental.allocator.building_blocks.kernighan_ritchie;
			import std.experimental.allocator.gc_allocator: GCA = GCAllocator;
			return Wrapped!(KRRegion!GCA)(KRRegion!GCA(128));
		},
	)){{
		static if(is(Allocator)){
			alias A = Allocator;
			alias allocator = A;
		}else{
			alias A = typeof(Allocator());
			A allocator = Allocator();
		}
		void[] memory = void;
		if((){
			static if(hasCanAllocate!A)
				return allocator.canAllocate(0);
			else return true;
		}()){
			memory = allocator.allocate(0);
			assert(memory.length == 0);
			if(allocator.isOwnerOf(memory)){
				allocator.deallocate(memory);
				
				static if(!is(A == CAllocator))
					assert(!allocator.isOwnerOf(memory));
			}else assert(memory is null);
		}
		if((){
			static if(hasCanAllocate!A)
				return allocator.canAllocate(1);
			else return true;
		}()){
			memory = allocator.allocate(1);
			assert(memory.length == 1);
			assert(allocator.isOwnerOf(memory));
			
			static if(hasReallocate!A){
				if((){
					static if(hasCanAllocate!A)
						return allocator.canAllocate(20);
					else return true;
				}()){
					auto oldMemory = memory;
					allocator.reallocate(memory, 20);
					if(memory.ptr != oldMemory.ptr){
						static if(!is(A == CAllocator))
							assert(!allocator.isOwnerOf(oldMemory));
					}
					assert(memory.length == 20);
				}
			}
			static if(hasExtend!A){
				auto oldMemory = memory;
				size_t oldSize = memory.length;
				size_t sizeDelta = allocator.extend(memory, 1);
				assert(memory.length == oldSize + sizeDelta);
				assert(oldMemory.ptr == memory.ptr);
			}
			
			allocator.deallocate(memory);
			static if(!is(A == CAllocator))
				assert(!allocator.isOwnerOf(memory));
		}
	}}
}
