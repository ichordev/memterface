# Memterface

[Official git repository](https://git.sleeping.town/ichordev/memterface)

A generic allocator API for templated code. Intended to supersede [std.experimental.allocator][std.experimental.allocator].

If there are any allocator designs you would like to see in `memterface.allocator.*`, or you need a new API extension to make
your allocator more awesome, then please [open an issue](https://git.sleeping.town/ichordev/memterface/issues)!

## Overview

Memterface provides strong guarantees to the programmer about how its allocators must behave:
- Allocators must always have a `deallocate` function, and an `isOwnerOf` function to
check whether a slice belongs to the allocator and is valid.
- To reduce manual error-handling and ambiguity, `allocate` can only return `null` for
zero-sized allocations. When an allocator cannot allocate enough memory, it must throw an error.

A simple Memterface allocator looks something like this:
```d
struct MyAllocator{
	void[] allocate(size_t size) nothrow
	out(memory; memory.length == size)
	out(memory; (size == 0 && memory is null) || isOwnerOf(memory)){
		//return `size` bytes of allocated memory
	}
	
	void deallocate(void[] memory) nothrow
	in(isOwnerOf(memory)){
		//deallocate `memory`
	}
	
	bool isOwnerOf(void[] memory) nothrow{
		//return `true` if this allocator owns `memory`
	}
}
```
An allocator's functions may be `static` if they do not rely on any instance data, or
an allocator can be implemented using polymorphism via the `AllocatorInterface` interface.

## Extensions
Extensions to the base allocator interface are available for allocators with different needs & features:

| Extension      | Description |
|----------------|-------------|
|`reallocate`    | For allocators with a specially-optimised way of reallocating memory. |
|`extend`        | For allocators that can extend allocations in-place. |
|`canAllocate`   | Lets allocators inform the user know when calling `allocate` (or `reallocate`) will fail. Useful for allocators with fixed pools of memory. |

## Documentation

For more information, inline documentation is available in the library's source code:

| Module                                         | Description |
|------------------------------------------------|-------------|
|[`memterface.iface`][iface]                     | The actual allocator API & how to use it. |
|[`memterface.ctor`][ctor]                       | Create valid type instances with memory from allocators. |
|[`memterface.wrap`][wrap]                       | Wrap allocators from [std.experimental.allocator][std.experimental.allocator] with `Wrapped!T`, and create wrappers over allocators with no equivalent of `isOwnerOf` with `ImplementIsOwnerOf`. |
|[`memterface.allocator.gc`][gc]                 | `GCAllocator`: D's built-in garbage collector. |
|[`memterface.allocator.malloc`][malloc]         | `CAllocator`: The C standard library's `malloc`. |
|[`memterface.allocator.bottom`][bottom]         | `BottomAllocator`: The fallback used at the bottom of a chain of fallbacks. |

[iface]: https://git.sleeping.town/ichordev/memterface/src/source/memterface/iface.d
[ctor]: https://git.sleeping.town/ichordev/memterface/src//source/memterface/ctor.d
[wrap]: https://git.sleeping.town/ichordev/memterface/src//source/memterface/wrap.d
[gc]: https://git.sleeping.town/ichordev/memterface/src//source/memterface/allocator/gc.d
[malloc]: https://git.sleeping.town/ichordev/memterface/src//source/memterface/allocator/malloc.d
[bottom]: https://git.sleeping.town/ichordev/memterface/src//source/memterface/allocator/bottom.d

[std.experimental.allocator]: https://dlang.org/phobos/std_experimental_allocator.html
