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
After we converted the shape into flattened lines, the next step is tile generation. The main purpose of tile generation is to determine the areas on the canvas that could _potentially_ be affected by anti-aliasing. An area _can_ have anti-aliasing if and only if a line crosses through that area, as anti-aliasing is a phenomenon that is only triggered by the edges of shape contours.

In order to do so, we conceptually segment our drawing area into smaller sub-areas of size 4x4 pixels. Note that there is no inherent reason why we _have_ to choose this specific size, and we could also opt to choose a size like 2x2 or 8x8 pixels instead. However, there is a complex trade-off to balance here which will be elaborated further in section @strips-generation.

Then, we iterate over all lines in our input geometry and generate _one_ tile for each area that the line covers, as is illustrated in @generating-tiles. We do this by first calculating the bounding box of the line in tile coordinates, which in this case is 7x3 tiles. Then, we iterate over them in row-major order and calculate whether the line has any intersection point. If so, we generate a new tile, if not we, just ignore the location and proceed to the next location. 

#figure(
  image("assets/tile_line_example.svg", width: 60%),
  caption: [Generating tiles for a line.]
) <generating-tiles>

#figure(
  [
    ```rs
struct Tile {
    x: u16,
    y: u16,
    line: Line,
    has_winding: bool
}
    ```
  ],
  caption: [The information stored inside of a tile.],
) <tile-fields>

The information that is stored for each tile is shown in @tile-fields. One the one hand, we store the x and y coordinates (in tile coordinates instead of pixel coordinates), but on the other hand, we also keep track of the line associated with the tile. We also store a special boolean flag `has_winding` which will be activated for any tile where the line intersects the top of the tile, as indicated by the yellow points in @generating-tiles. This information will be needed later.

Applying this algorithm to our familiar butterfly shape, we end up with the representation in @butterfly-tiles. There are two aspects worth highlighting: First and foremost, it is _not_ the case that one location can only have one tile. We generate one tile for _each_ line at a certain location, meaning that multiple tiles can be generated if multiple lines cover the same tile square. And secondly, note how this representation really achieves our initial goal: Any pixel that could potentially have anti-aliasing is strictly contained within a tiled region. Any area that is not covered by a tile is either strictly within the shape, and thus will always be painted fully, or strictly outside of the shape and should therefore not be painted at all.

#figure(
  image("assets/butterfly_tiles.pdf", width: 60%),
  caption: [The generated tiles for the butterfly shape. Each line segment generates at least a tile, meaning that there can be multiple overlapping tiles at the same location.]
) <butterfly-tiles>

As a final step, we sort our buffer that stores all tiles first by ascending y-coordinate and then by ascending x-coordinate to ensure that they are stored in row-major order. In order to do so, we use the `sort_unstable` method provided by the Rust standard library.

== Strips generation <strips-generation>
We know arrive at the most integral part of the pipeline, namely strip generation. There are a lot of details and subtleties to unpack here, and it is therefore worth re-exploring the original motivation before diving into the implementation.

=== Motivation
When rendering a shape, there are two types of computations that may be performed:
+ For pixels strictly inside of the shape, not a lot of work needs to be done. We just need to set the value of the pixel to the given color. This is computationally speaking relatively cheap.
+ For pixels on the edge, more work needs to be done: We need to check how the line intersects the pixel and then calculate the area coverage in order to determine the correct opacity for anti-aliasing. This is clearly a much more expensive operation, and we therefore want to limit this operation to the pixels where it's really necessary.

One of the core goals of strip generation is to calculate the opacity values for all pixels that could potentially be affected by anti-aliasing. However, in addition to that, we group the pixels in a smart way and store additional "metadata" such that we can store all the information that is needed to reproduce the necessary information for rendering (which includes the opacity values for anti-aliased pixels as well as information about which areas should be completely filled). The key innovation is that this happens in a storage-efficient way. Normally, if you wanted to store an image with 256 in each dimension in RGBA format using 8-bit unsigned integers, you would need $256 * 256 * 4  #sym.approx 262$ kilobytes of storage. If you increase this to 512 pixels, you end up with around one megabyte, so the storage requirement increases quadratically as the base size increases.

In contrast, using our method, the factor of $4$ completely falls away since we are not storing RGBA values but just single opacity values between $0$ and $255$. In addition to that, even when scaling an image in both directions, the number of _anti-aliased pixels_ tends to increase linearly instead of quadratically, resulting in much lighter storage requirements.

=== Merging strips
The first step of the algorithm is relatively straight-forward: We iterate over all tiles (remember that they are already sorted in row-major order!), and merge horizontally-adjacent tiles into single _strips_. These strips have the same height as the tiles, but the width can vary depending on how many adjacent tiles there are, as is visualized in @butterfly-strip-areas. The blue colored strips represent any area where we will explicitly calculate opacity values for anti-aliasing. Any pixel not falling within a strip will _not_ be explicitly stored and is represented implicitly.

#figure(
image("assets/butterfly_strip_areas.svg",width: 40%),
  caption: [The areas of the generated strips.]
) <butterfly-strip-areas>

=== Calculating coarse winding numbers

However, generating the merged strips is only a small part of the equation. The next step is understanding how we can encode the strips so that in later stages of the pipeline, we can easily determine which areas between the strips should be filled and which ones should not. In order to understand how this works, we need to remind ourselves about the concept of winding numbers as they were introduced in @fill_rules: Conceptually, we shoot a ray into any direction and increase or decrease a winding number counter each time we intersect a line of the path depending on the direction of the line. In our case, there are actually two different winding numbers that we need to keep track of. 

The first winding number is the _coarse winding number_ and defined at the strip level. For each strip, we shoot a ray from the very left of the row to the very right at the very top of the strip. Each time we intersect a line (remember that for each tile, we store a boolean flag with that information, allowing us to easily check that), we use add this to the winding number of the _next_ strip. 

#figure(
image("assets/butterfly_coarse_winding_number.svg", width: 100%),
caption: [Calculating the coarse winding number for each strip in a row.]
) <coarse-winding-fig>

@coarse-winding-fig Shows an example of doing this computation. The first strip on the very left has a start winding number of 0, as it's the leftmost part of the shape on this row. Inside of this strip, we have one tile that has a line intersection at the top. The line is defined from bottom to top, meaning that from the perspective of our imaginary ray, the intersection direction is right-to-left, and thus we _decrease_ our winding counter to -1. Since there are no further intersection in this strip, the coarse winding number of the next strip will be set to -1. The strip in the center first has a left-to-right intersection, meaning that our winding counter is temporarily reset to 0. But in the end, we have yet another intersection in the opposite direction, and therefore, the start winding number of that last strip is going to be -1 as well.

We run this computation for all rows containing strips to assign each strip its coarse winding number. To more easily visualize this, we can now color the strips according to the fill rule: If the coarse winding number of a strip is zero, we color it in green, otherwise we color it in red. The result is illustrated in @butterfly-strip-areas-with-winding. Note in particular that just encoding the winding number in each strip is enough information to later on infer which non-covered areas should be fully painted and which ones should not! For every non-covered gap, if the strip on the _right_ side has a non-zero winding number, the whole area is painted, otherwise it is not painted. For example, the gap in the first row in @butterfly-strip-areas-with-winding will not be painted since the strip on the very right has a winding number of 0. However, in the third row, both areas will be painted since the strips on the right of each gap have a non-zero winding number. Mentally applying this idea to each row, it becomes evident that this approach is sufficient to later on determine which areas need to be painted, solely based on the encoded information in the sparse strips!

#figure(
image("assets/butterfly_strip_areas_with_winding.svg",width: 35%),
    caption: [The areas of the generated strips, with the strips painted according to their winding number.],
    placement: auto
  ) <butterfly-strip-areas-with-winding>

== Calculating pixel-level winding number
We know have encoded the information necessary to determine fully-painted areas in later stages of the pipeline, but we have yet to determine the opacity values of the pixels _inside_ of strips to apply anti-aliasing. In principle, we use a very similar approach to determining the strip-level winding number, with the main difference being that we are now considering rays intersecting individual _pixel rows_ and also considering _fractional_ winding numbers. The process is visualized in @strip-winding-numbers on the basis of the first strip in the first row.

#figure(
image("assets/strip_winding_numbers.pdf", width: 85%),
    caption: [Calculating winding numbers of each pixel in a strip.],
    placement: auto
  ) <strip-winding-numbers>

For each strip, we once again look at its constituent tile regions. We initialize a temporary array of 16 floating point numbers to the value 0.0 and store it in *column-major* (the reasoning behind this will be elaborated in @fine_rasterization) order. We then iterate over all tiles in the given tile region and compute the trapezoidal area that is spanned between the line and the right edge of the tile. For each pixel, we then simply calculate the fraction of its area that is covered by the trapezoid. Note that the usual rules apply, where the area can also be _negative_ depending on the direction the line intersects the pixels with. We then sum the fractional windings of all tiles in the same region into our temporary array, until we end up with the final winding number. Next, we convert the winding numbers into opacities between 0.0 and 1.0 by applying the fill rule and scale them by 255 so that we can store them as 8-bit unsigned integers. The array of the 16 opacity values is then pushed out into a buffer and the whole process is restarted for the next tile area in the strip. Doing this for all strips, we end up with the representation that is shown in @butterfly-all-strips.

#figure(
  image("assets/butterfly_all_strips.svg", width: 35%),
  caption: [The opacity values for all strips. Completely black pixels represent 100% opacity, white pixels 0%, shades of grey intermediate values.],
  placement: auto,
) <butterfly-all-strips>

Thinking about this more carefully, it should now be clear that we have all the information needed to fully draw the complete shape. We have calculated the opacity values of all anti-aliased pixels and represent to-be-filled areas in an implicit way, just by storing a `Vec<Strip>` that represents the whole rasterized geometry of a single shape. As can be seen in @strip-fields, a strip only needs to store its start position x and y positions, its _coarse_ winding number as well as an index into the global alpha buffer pointing to the first element, where all opacity values for _all_ strips are stored. Note in particular that there is no need to explicitly store the width of the strip, as it can be inferred by looking at the `alpha_idx` of the next strip. For example, if one strip has an alpha index of 80 and the next strip an index of 160, the width of the strip is $(160 - 80) / 4 = 20$, since a strip always has a height of 4.

#figure(
  [
    ```rs
struct Strip {
    x: u16,
    y: u16,
    alpha_idx: u32,
    winding: i32,
}
    ```
  ],
  caption: [The information stored inside of a strip.],
) <strip-fields>

With the sparse strip representation concluded, the path rendering stage of the pipeline (as shown in @overview_pipeline) concludes. There are many different things that can now be done with that intermediate representation. On the one hand, we can pass it on to the next stage to commence the actual rasterization process. On the other hand, we could for example store the path for caching purposes so that it can be reused in the future without having to redo all of the calculations.

=== Tile size

== Coarse rasterization <coarse-rasterization>

== Fine rasterization <fine_rasterization>

== Packing <packing>

== SIMD <simd>

== Multi-threading <mult-threading>

== Comparison
#todo[Do we want a section on this?]

