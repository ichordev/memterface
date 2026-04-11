/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.
*/
module memterface.allocator;

public import
	memterface.allocator.bottom,
	memterface.allocator.gc,
	memterface.allocator.kernel,
	memterface.allocator.malloc;

unittest{
	import std.meta: AliasSeq;
	import memterface.iface, memterface.wrap;
	
	static foreach(Allocator; AliasSeq!(
		BottomAllocator,
		GCAllocator,
		KernelVirtualAllocator,
		CAllocator,
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
		static if(hasCanAllocate!A){
			assert(allocator.canAllocate(0));
		}
		memory = allocator.allocate(0);
		assert(memory is null);
		assert(!allocator.isOwnerOf(memory));
		
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
						assert(!allocator.isOwnerOf(oldMemory));
					}
					assert(memory.length == 20);
				}
			}
			static if(hasResize!A){
				void resize(size_t size){
					auto oldMemory = memory;
					size_t oldSize = memory.length;
					size_t newSize = allocator.resize(memory, size);
					assert(newSize == memory.length);
					if(size > oldSize){
						assert(newSize <= size);
						assert(newSize >= oldSize);
					}else{
						assert(newSize <= oldSize);
						assert(newSize >= (size > 0 ? size : 1));
					}
					assert(oldMemory.ptr == memory.ptr);
					assert(allocator.isOwnerOf(memory));
				}
				resize(memory.length+2);
				resize(0);
			}
			
			allocator.deallocate(memory);
			assert(!allocator.isOwnerOf(memory));
		}
	}}
}
