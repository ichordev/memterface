/**
Copyright: Copyright 2025–2026 Aya Partridge
License: Distributed under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See the accompanying `COPYING.LESSER.md` file or go to <https://www.gnu.org/licenses/> for more details.
*/
module memterface.allocator.kernel;

import memterface.iface;

/**
Allocates pages of virtual memory directly from the operating system's kernel.
As such, the allocated memory is not physically contiguous.
*/
struct KernelVirtualAllocator{
	static void[] allocate(size_t size) nothrow @nogc @safe
	out(memory; memory.length == size)
	out(memory; size > 0 ? isOwnerOf(memory) : memory is null){
		import core.exception: onOutOfMemoryError;
		if(size > 0){
			version(Apple){
				mach_vm_address_t address;
				switch((() @trusted => mach_vm_allocate(mach_task_self(), &address, size, VM_FLAGS_ANYWHERE))()){
					case KERN_SUCCESS:
						return (() @trusted => (cast(void*)address)[0..size])();
					default: //all other errors
						onOutOfMemoryError();
					case KERN_INVALID_ARGUMENT: //should only happen if a bad argument is supplied, which would be our mistake
						assert(0, "Implementation error");
				}
			}else version(Supported_POSIX){
				auto ptr = (() @trusted => mmap(null, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0))();
				if(ptr !is MAP_FAILED){
					return (() @trusted => ptr[0..size])();
				}else{
					onOutOfMemoryError();
				}
			}else version(Windows){
				auto ptr = (() @trusted => VirtualAlloc(null, size, MEM_COMMIT, PAGE_READWRITE))();
				if(ptr !is null){
					
				}else{
					version(assert){
						import core.sys.windows.winerror: ERROR_OUTOFMEMORY;
						 import core.sys.windows.winbase: GetLastError;
						assert(GetLastError() == ERROR_OUTOFMEMORY);
					}
					onOutOfMemoryError();
				}
			}else{
				assert(0, "Unimplemented");
			}
		}else{
			return null;
		}
	}
	
	static void deallocate(void[] memory) nothrow @nogc @system
	in(isOwnerOf(memory)){
		version(Apple){
			const kernRet = mach_vm_deallocate(mach_task_self(), cast(mach_vm_address_t)memory.ptr, memory.length);
			assert(kernRet == KERN_SUCCESS);
		}else version(Supported_POSIX){
			const err = munmap(memory.ptr, memory.length);
			assert(err == 0);
		}else version(Windows){
			const success = VirtualFree(memory.ptr, 0, MEM_RELEASE);
			assert(success);
		}else{
			assert(0, "Unimplemented");
		}
	}
	
	static bool isOwnerOf(const(void)[] memory) nothrow @nogc @safe{
		if(memory.length > 0){
			version(Apple){
				const memorySize = mach_vm_size_t(memory.length);
				
				auto inAddress = (() @trusted => cast(mach_vm_address_t)memory.ptr)();
				mach_vm_size_t totalSize = 0, size = void;
				vm_region_basic_info_64 info = void;
				mach_port_t name = void;
				
				do{
					auto inOutAddress = inAddress;
					mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
					if(
						(() @trusted => mach_vm_region(
							mach_task_self(), &inOutAddress, &size,
							VM_REGION_BASIC_INFO_64, cast(vm_region_info_t)&info, &infoCnt, &name,
						))() == KERN_SUCCESS &&
						inOutAddress == inAddress
					){
						totalSize += size;
						inAddress += size;
					}else{
						return false;
					}
				}while(totalSize < memorySize);
				return true;
				
			}else version(Supported_POSIX){
				import core.stdc.errno: errno;
				import core.sys.posix.unistd: _SC_PAGESIZE, sysconf;
				const size_t pageSize = sysconf(_SC_PAGESIZE);
				if((() @trusted => cast(size_t)memory.ptr)() % pageSize == 0){
					version(mincore){
						static ubyte[64] vec;
						do{
							const size = memory.length >= pageSize ? pageSize : memory.length;
							tryAgain:
							if((() @trusted => mincore(cast(void*)memory.ptr, size, cast(ubyte*)&vec) == 0)()){
								memory = memory[size..$];
							}else{
								import core.stdc.errno: EFAULT, EINVAL;
								switch(errno){
									default: //all other errors
										return false;
								version(linux){
									import core.stdc.errno: EAGAIN;
									case EAGAIN:
										goto tryAgain;
								}
									case EFAULT, EINVAL: //our call should always be valid, so if it isn't then we messed up
										assert(0, "Implementation error");
								}
								assert(0); //unreachable
							}
						}while(memory.length);
						
						return true;
					}else version(OpenBSD){
						do{
							const size = memory.length >= pageSize ? pageSize : memory.length;
							const ptr = (() @trusted => mquery(memory.ptr, memory.length, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_PRIVATE | MAP_ANON))();
							if(ptr is MAP_FAILED || ptr !is &memory[0]){
								import core.stdc.errno: EBADF;
								switch(errno){
									default: //all other errors
										break;
									case EBADF: //our call should always be valid, so if it isn't then we messed up
										assert(0, "Implementation error");
								}
								memory = memory[size..$];
							}else{
								return false;
							}
						}while(memory.length);
						
						return true;
					}
				}
			}/+else version(Posix){
				off_t offset;
				size_t contiguousLength;
				int fileDescriptor = -1;
				
				return
					(() @trusted => posix_mem_offset(memory.ptr, memory.length, &offset, &contiguousLength, &fileDescriptor) == 0)() &&
					offset == off_t(0) &&
					contiguousLength == memory.length;
			}+/else version(Windows){
				MEMORY_BASIC_INFORMATION info;
				const infoByteCount = (() @trusted => VirtualQuery(memory.ptr, &info, info.sizeof))();
				assert(infoByteCount);
				
				return
					info.AllocationBase == &memory[0] &&
					info.RegionSize >= memory.length &&
					info.State == MEM_COMMIT;
			}else{
				assert(0, "Unimplemented");
			}
		}
		return false;
	}
}

private{
	version(Apple){
		import core.sys.darwin.mach.kern_return: KERN_SUCCESS, KERN_INVALID_ARGUMENT, kern_return_t;
		import core.sys.darwin.mach.port: mach_port_t;
		import core.sys.darwin.mach.semaphore: mach_task_self;
		import core.sys.darwin.mach.thread_act: mach_msg_type_number_t;
		
		//<mach/ARCH/boolean.h>
		alias boolean_t = int;
		
		//<mach/ARCH/vm_types.h>
		alias vm_map_t = mach_port_t;
		alias vm_map_read_t = mach_port_t;
		
		//from <mach/mach_vm.h>
		extern(C) nothrow @nogc{
			kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t* address, mach_vm_size_t size, int flags);
			kern_return_t mach_vm_deallocate(vm_map_t target, mach_vm_address_t address, mach_vm_size_t size);
			kern_return_t mach_vm_region(vm_map_read_t target_task, mach_vm_address_t* address, mach_vm_size_t* size, vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t* infoCnt, mach_port_t* object_name);
		}
		
		//from <mach/memory_object_types.h>
		alias memory_object_offset_t = ulong;
		
		//from <mach/vm_behavior.h>
		alias vm_behavior_t = int;
		
		//from <mach/vm_inherit.h>
		alias vm_inherit_t = uint;
		
		//from <mach/vm_prot.h>
		alias vm_prot_t = int;
		
		//from <mach/vm_region.h>
		alias vm_region_info_t = int*;
		alias vm_region_flavor_t = int;
		
		enum VM_REGION_BASIC_INFO_64 = 9;
		struct vm_region_basic_info_64{
			vm_prot_t protection;
			vm_prot_t max_protection;
			vm_inherit_t inheritance;
			boolean_t shared_;
			boolean_t reserved;
			memory_object_offset_t offset;
			vm_behavior_t behavior;
			ushort user_wired_count;
		}
		enum VM_REGION_BASIC_INFO_COUNT_64 = cast(mach_msg_type_number_t)(vm_region_basic_info_64.sizeof/int.sizeof);
		
		//<mach/vm_statistics.h>
		enum VM_FLAGS_ANYWHERE = 1;
		
		//from <mach/vm_types.h>
		alias mach_vm_address_t = ulong;
		alias mach_vm_size_t = ulong;
	}else version(Posix){
		version(linux){
			import core.sys.linux.sys.mman: mincore;
			version = mincore;
			version = Supported_POSIX;
		}else version(FreeBSD){
			import core.sys.freebsd.sys.mman: mincore;
			version = mincore;
			version = Supported_POSIX;
		}else version(NetBSD){
			import core.sys.netbsd.sys.mman: mincore;
			version = mincore;
			version = Supported_POSIX;
		}else version(OpenBSD){
			import core.sys.openbsd.sys.mman: mquery;
			import core.sys.posix.sys.mman: MAP_FIXED;
			version = Supported_POSIX;
		}
		
		version(Supported_POSIX){
			import core.sys.posix.sys.mman: MAP_ANON, MAP_FAILED, MAP_PRIVATE, PROT_READ, PROT_WRITE, mmap, munmap;
		}
	}else version(Windows){
		 import core.sys.windows.winnt: MEMORY_BASIC_INFORMATION, MEM_COMMIT, MEM_RELEASE, PAGE_READWRITE;
		 import core.sys.windows.winbase: VirtualAlloc, VirtualFree, VirtualQuery;
	}
}
