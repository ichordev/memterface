# Memterface

[Official git repository](https://git.sleeping.town/ichordev/memterface)

A generic allocator API for templated code. Intended to supersede [std.experimental.allocator][std.experimental.allocator].

If there are any allocator designs you would like to see in `memterface.allocator.*`, or you need a new API extension to make
your allocator more awesome, then please [open an issue](https://git.sleeping.town/ichordev/memterface/issues)!

## Documentation

Inline documentation is available in the library's source code:

| Module                                         | Description |
|------------------------------------------------|-------------|
|[`memterface.iface`][iface]                     | The actual allocator API & how to use it. |
|[`memterface.ctor`][ctor]                       | Create valid type instances with memory from allocators. |
|[`memterface.wrap`][wrap]                       | Wrap allocators from [std.experimental.allocator][std.experimental.allocator]. |
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
