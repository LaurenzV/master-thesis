#import "@preview/subpar:0.2.2"
#import "../utils.typ": todo

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

The pipeline is illustrated in @api_example_Listing. Overall, the steps can be grouped into three categories: _Path rendering_, _coarse rasterization_ and _rasterization_. 

The user starts by creating a render context and specifying drawing instructions, such as filling a rectangle or stroking a circle. The only difference between stroking and filling is that stroking requires an additional step called _stroke expansion_ in the beginning, which manipulates the input path in a way such that filling the new path has the same visual effect as stroking the old one. By doing this, we can treat filled and stroked paths the same in subsequent stages.

The next stage is called _flattening_. As was mentioned in @drawing_primitives, the two basic primitives used for drawing are lines and curves. As part of this stage, the path is converted into a different representation such that the whole geometry is solely described by lines. Converting curves to lines is clearly a lossy operation since curves inherently cannot be represented completely accurately by just lines, but by using a large enough number of lines, the error in precision will be so small that it cannot be noticed in the final result. The advantage of this conversion step is that the follow-up stage in the pipeline only needs to process line primitives instead of curves _and_ lines, which greatly reduces the complexity.

After that, _tile generation_ is performed. In this stage, we conceptually segment the whole canvas into areas of size 4x4. For each path, we calculate all of the 4x4 areas that it crosses, generate a tile for it and associate the tile with the given line. In the end, all generated tiles are sorted by their y and x coordinates.

The following _strips generation_ stage is arguably the most crucial step in the pipeline: In this stage, we iterate over all tiles in row-major order (this is why tile generation has a sorting step in the end) and _merge_ horizontally adjacent tiles into strips. For each pixel covered by a strip, we calculate the alpha value that is necessary to perform correct anti-aliasing. The output of this stage is a vector of strips that sparsely encodes the rendered representation of the shape by only _explicitly_ storing anti-aliased pixels and storing filled areas  _implicitly_.

Once the path has been converted into sparse strips representation, they are passed to the _coarse rasterizer_. The coarse rasterizer segments the canvas into so-called _wide tiles_ (not to be confused with tiles from the tile generation stage) which all have a dimension of 256x4 pixels. We then iterate over all strips and generate the actual rendering commands that should be applied to each wide tile.

Once this is done, control is passed back to the user, in which case they have two choices: Either, they keep rendering more paths, in which case the above-mentioned stages are re-run for the new path, or the user calls the `render_to_pixmap` method, in which case the _fine rasterization_ kicks off.

Fine rasterization is where the actual "coloring" and compositing of pixels happens. This works by iterating over all commands in each wide tile and performing operations like "fill this area using a blue color" or "fill that area using a gradient color". For reason that will be explained area, all of this happen in an intermediate buffer. Only once fine rasterization is complete do we start the process of _packing_ where the contents of the intermediate buffer of each wide tile are copied into the pixmap that the user provided. In the end, the fully rendered result is stored in the pixmap and can be processed further.

== Stroke expansion <stroke_expansion>

In @fills-and-strokes, we mentioned that there are two types of drawing mode that need to be implemented: Filling and stroking. There are different ways in which stroking can be implemented. In our case, we decided to go with the so-called _stroke expansion_ approach. The basic idea is that we transform our original path description in such a way that applying a fill to that new path _visually_ has the same effect as stroking the original path. The idea is illustrated in figure @stroke-expansion-fig. If we want to draw a stroke with width 1, we compute two new _offset curves_ that are each offset by half the stroke width inward/outward. Filling this new shape results in a painted line of width 1 that is centered on the original outline description of the shape.

#subpar.grid(
  figure(image("assets/butterly_path.svg", width: 100%), caption: [
    The butterfly shape. #linebreak() #linebreak()
  ]),
  figure(image("assets/butterfly_expanded.svg", width: 100%), caption: [
    Expansion of stroke with width 1.
  ]),
  figure(image("assets/butterfly_colored.svg", width: 100%), caption: [
    Filling of the expanded path.
  ]),
  columns: (1fr, 1fr, 1fr),
  caption: [Reducing the problem of stroking a shape to the problem of filling it.],
  label: <stroke-expansion-fig>,
  placement: auto,
)

The main advantage of the stroke expansion approach is that it allows us to treat filled and stroked path in the exact same way in the whole rendering pipeline, allowing for a lot of simplification. The only difference is that stroked paths go through an additional step in the very beginning of the pipeline.

Given that our renderer is implemented in Rust, we decided to use the Kurbo @kurbo library for this purpose, as it provides an implementation for stroke expansion. It takes a path description, the settings of the stroke as well as an _tolerance_ parameter as input, and returns expansion of the stroke as the output. The _tolerance_ parameter represents a trade-off that needs to be carefully balanced: Creating a mathematically completely accurate offset curve is not always possible. If we choose a lower tolerance, the expanded stroke will be more accurate, at the cost of containing more path segments, which ultimately means more work for later parts of the rendering pipeline. If we choose a higher tolerance, the expanded stroke will contain less segments, but the chance of visual artifacts being introduced is higher. In our case, we settled on a tolerance of $0.25$, which has so far be proven to be sufficient.

As is outlined in #cite(<stroke_to_filled>, form: "prose"), stroke expansion is an incredibly complex and mathematically challenge problem to get right. One of the main difficulties is handling the various edge cases correctly, some of which even many of the mainstream renderers do not get right.

Since implementing the stroke expansion logic was not explicitly part of this project, we will not dive into the internals of Kurbo's algorithm and leave it at this high-level description to give an intuition.

== Flattening <flattening>
Now that we have an expanded version of our stroke or a simple shape the user wants to fill (in the examples from now on, we will assume that we want to fill the butterfly instead of stroking it), we reach the next step in the pipeline: flattening. The idea of having this step is as follows: We want to convert our input shape, which consists of lines and curves, into a new representation which consists of just lines. By doing so, later steps in the pipeline only need to consider line segments as the basic building blocks, an assumption that will simplify the logic by a lot.

#figure(
  image("assets/butterfly_flattened.pdf"),
  caption: [Parts of the butterfly shape flattened to lines. The red points indicate the start/end points of the line segments.]
) <butterfly-flattened-fig>

However, there is the problem that line segments clearly cannot accurately model curve segments. This can be seen in @butterfly-flattened-fig. While the flattened versions of the shape _overall_ still look curvy, zooming in makes it very apparent that it is really just a number of connected lines. For plain vector graphics, doing such a simplification would clearly be unacceptable. The crucial point here is that the simplification will be barely noticeable once the shape is rendered to pixels, because as part of the discretization process, the information whether a line or curve was used is completely lost; all that's left is an approximation of pixel coverage in the form of color opacity. And assuming that the number of used line segments is sufficiently large, the change in pixel coverage will be so small that it is unnoticeable with the naked eye.

In order to achieve flattening of curves, we once again resort to the implementation that is provided in Kurbo @kurbo, which is based on an algorithm described in a blog post @flattening_quadratic_curves. Similarly to stroke expansion, the method for flattening takes a path with arbitrary curve and line segments as well as a _tolerance_ parameter as input. The tolerance parameter indicates what the maximum allowed error distance between a curve and its line approximation is and represents another set of trade-offs: Smaller tolerance will yield higher accuracy but result in more line segments, higher tolerance will result in less emitted lines but might cause noticeable artifacts when rendering. We once again settled on the value $0.25$ for this parameter, which means that the error distance can never be larger than one fourth of a pixel.

The algorithm works roughly as follows: We iterate over each path segment and perform some operation on it. 

In the case of lines, there is no work to be done and they can just be re-emitted as is.

For quadratic curves, things start to get more interesting. One possible approach to flattening them would be doing a _recursive subdivision_, which means that we try to build a line between start and end point, and in case the maximum error is too large, we _subdivide_ our current curve in the center and perform the same operation recursively on both halves, until the spanned line of all subdivisions is within the given error bound @flattening_quadratic_curves. While this approach works, it has a tendency to generate more lines than necessary, a side effect that emerges from always religiously doing the subdivision in the center of the curve.

The algorithm in the blog post instead presents a different approach that is based on mathematical analysis: We first calculate the number $n$ of line segments that are needed for the subdivision using an integral that is derived from a closed-form analytic expression, and only then determine the actual subdivision points by subdividing the interval into $n$ equal-spaced points and applying the inverse integral on them @flattening_quadratic_curves. The result will be an approximation that usually uses less line segments than the recursive subdivision approach.

For cubic curves, the Kurbo implementation simply first approximates those by quadratic curves and then applies the same algorithm that was outlined above.

== Tile generation <tile-generation>

== Strips generation <strips-generation>

== Coarse rasterization <coarse-rasterization>

== Fine rasterization <fine_rasterization>

== Packing <packing>

== SIMD <simd>

== Multi-threading <mult-threading>

== Comparison
#todo[Do we want a section on this?]

