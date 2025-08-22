= Implementation <implementation>
In this section, we will first showcase an example code snippet to demonstrate how Vello CPU's API works. Afterwards, the majority of the section will be dedicated to explaining each part of the rendering pipeline in Vello CPU. Finally we will illustrate how the pipeline was accelerated by employing SIMD and multi-threading.

== API
@api_example_Listing provides a small example that demonstrates how to use Vello CPU's Rust API for basic rendering.

#[
  #show figure: set block(breakable: true)

  #figure(
    block(breakable: true)[
      #set align(left)
  
      #raw(lang: "rust", read("assets/api_code.rs"))
    ],
    caption: [Example usage of Vello CPU's API.]
  ) <api_example_Listing>
]

In the beginning, the user can specify settings that should be applied while rendering. The `level` property indicates which SIMD level should be used during rendering. By default, Vello CPU will dynamically detect the highest available level on the host system, but the user can in theory override this to for example force using SSE4.2 instructions, even though the system supports AVX2 in theory. The `num_threads` property allows you to enable multi-threaded execution (see @mult-threading) or force single-threaded execution by setting the value to 0. Finally, the `render_mode` property indicates whether to prioritize speed or quality during rendering (see @fine_rasterization).

The user then creates a new `RenderContext` by specifying a width and height as well as the render settings. An important property of the `RenderContext` is that it is _reusable_. This means that if the user renders a certain scene and then wants to render a second scene, they can just _reset_ the context and then reuse it instead of having to initialize a new one. This is important because during the rendering process, _Vello CPU_ will need to make a number of memory allocations, which can have a some impact on runtime. By reusing the same `RenderContext`, Vello CPU can _reuse_ the existing allocations in subsequent rendering operations, leading to better performance. This property is especially useful in the context of GUI rendering, where it is common to render different scenes dozens of times per second over an extended period of time.

Now, the user can start rendering items to the scene. In this specific example, we first render a centered rectangle of width 50 using a fully opaque blue, followed by a smaller, semi-transparent red rectangle in the bottom right. In the end, we draw a green stroked circle.

By specifying drawing instructions in the render context, we are not doing any actual rendering yet. In order to produce an actual picture, we first need to create a new `Pixmap`. A pixmap is basically a fancy wrapper around a `Vec<u8>` (a vector of bytes in Rust) that can store raw, premultiplied RGBA pixels. Remember that in @colors, we explained that RGBA values can either be stored as 32-bit floating point numbers or as 8-bit unsigned integers. In this case, we are simply storing the value of each pixel in the pixmap as integers in row-major order. For example, if we have a pixmap of size 2x2 where the top-left pixel is green, the top-right pixel red, the bottom-left pixel blue and the bottom-right pixel white, we would store this in one contiguous vector with the bytes #raw(lang: "rust", "[0, 255, 0, 255, 255, 0, 0, 255, 0, 0, 255, 0, 255, 255, 255, 255]").

By calling the `render_to_pixmap` method, we can now instruct Vello CPU to actually render the previous rendering instructions into the pixmap. The pixmap can then be further processed, by for example converting it into a PNG file and saving it to disk. The rendered result of @api_example_Listing can be seen in @api_example_result.

#figure(
  image("assets/api_code_result.png", width: 50%, scaling: "pixelated"),
  caption: [The rendered result of the code in @api_example_Listing.],
  placement: auto
) <api_example_result>


== Architecture Overview <architecture_overview>
In order to convert a vector image into a raster image, there are a lot of intermediate steps that need to be performed to arrive at the final result. While a few steps are virtually universal and done by nearly all renderers in some shape or form, the exact implementation of the whole rendering pipeline varies wildly across different implementations.

One of the interesting aspects of the design of Vello CPU is that it has a very modular architecture, where each step takes a specific kind of input and produces a specific kind of intermediate output, which can then be consumed by the next stage in the pipeline. There are no cross-dependencies between non-consecutive stages. As will be seen in the following subsections, this property makes it very easy to explain the functionality of each module in isolation and visualize the intermediates results that are produced after passing through each stage. The stages of the rendering pipeline and their dependencies are illustrated in @overview_pipeline. A summary of each stage is provided below, but they will be explained more clearly later on.

#figure(
  image("assets/overview_pipeline.pdf"),
  caption: [An overview of the rendering pipeline in Vello CPU.],
  placement: auto,
) <overview_pipeline>

As was shown in @api_example_Listing, the user starts by creating a render context and specifying drawing instructions, such as filling a rectangle or stroking a circle. The only difference between stroking and filling is that stroking requires an additional step called _stroke expansion_ in the beginning, which manipulates the input path in a way such that filling the new path has the same visual effect as stroking the old one. By doing this, we can treat filled and stroked paths the same in subsequent stages.

The next stage is called _flattening_. As was mentioned in @drawing_primitives, the two basic primitives used for drawing are lines and curves. As part of this stage, the path is converted into a different representation such that the whole geometry is solely described by lines. Converting curves to lines is clearly a lossy operation since curves inherently cannot be represented completely accurately by just lines, but by using a large enough number of lines, the error in precision will be so small that it cannot be noticed in the final result. The advantage of this conversion step is that the follow-up stage in the pipeline only needs to process line primitives instead of curves _and_ lines, which greatly reduces the complexity.

After that, _tile generation_ is performed. In this stage, we conceptually segment the whole canvas into areas of size 4x4. For each path, we calculate all of the 4x4 areas that it crosses, generate a tile for it and associate the tile with the given line. In the end, all generated tiles are sorted by their y and x coordinates.

The following _strips generation_ stage is arguably the most crucial step in the pipeline: In this stage, we iterate over all tiles in row-major order (this is why tile generation has a sorting step in the end) and _merge_ horizontally adjacent tiles into strips. For each pixel covered by a strip, we calculate the alpha value that is necessary to perform correct anti-aliasing. The output of this stage is a vector of strips that sparsely encodes the rendered representation of the shape by only _explicitly_ storing anti-aliased pixels and storing filled areas  _implicitly_.

Once the path has been converted into sparse strips representation, they are passed to the _coarse rasterizer_. The coarse rasterizer segments the canvas into so-called _wide tiles_ (not to be confused with tiles from the tile generation stage) which all have a dimension of 256x4 pixels. We then iterate over all strips and generate the actual rendering commands that should be applied to each wide tile.

Once this is done, control is passed back to the user, in which case they have two choices: Either, they keep rendering more paths, in which case the above-mentioned stages are re-run for the new path, or the user calls the `render_to_pixmap` method, in which case the _fine rasterization_ kicks off.

Fine rasterization is where the actual "coloring" and compositing of pixels happens. This works by iterating over all commands in each wide tile and performing operations like "fill this area using a blue color" or "fill that area using a gradient color". For reason that will be explained area, all of this happen in an intermediate buffer. Only once fine rasterization is complete do we start the process of _packing_ where the contents of the intermediate buffer of each wide tile are copied into the pixmap that the user provided. In the end, the fully rendered result is stored in the pixmap and can be processed further.

== Stroke expansion <stroke_expansion>

== Flattening <flattening>

== Tile generation <tile-generation>

== Strips generation <strips-generation>

== Coarse rasterization <coarse-rasterization>

== Fine rasterization <fine_rasterization>

== Packing <packing>

== SIMD <simd>

== Multi-threading <mult-threading>

