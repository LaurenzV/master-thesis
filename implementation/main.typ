#import "@preview/subpar:0.2.2"
#import "../utils.typ": todo

= Implementation <implementation>
In this section, we will first showcase an example code snippet to demonstrate how Vello CPU's API works. Afterwards, the majority of the section will be dedicated to explaining each part of the rendering pipeline. Finally, we will illustrate how the pipeline was accelerated by employing SIMD and multi-threading.

== API <api>
@api_example_Listing provides a small example that demonstrates how to use Vello CPU's Rust API for basic rendering.

  #figure(
    block(breakable: true, width: 100%)[
      #set align(left)
      #raw(lang: "rust", read("assets/api_code.rs"))
    ],
    caption: [Example usage of Vello CPU's API.],
  ) <api_example_Listing>

In the beginning, the user can specify settings that should be applied while rendering. The `level` property indicates which SIMD level should be used during rendering. By default, Vello CPU will dynamically detect the highest available level on the host system, but the user can override this to, for example, force using SSE4.2 instructions, even though the system supports AVX2. The `num_threads` property allows to enable multi-threaded execution (see @multi-threading) or enforce single-threaded execution by setting the value to 0. Finally, the `render_mode` property indicates whether to prioritize speed or quality during rasterization by using `u8` or `f32` numbers, respectively (see @fine_rasterization).

The user then creates a new `RenderContext` by specifying a width and height as well as the render settings. An important property of the `RenderContext` is that it is _reusable_. This means that if the user renders a certain scene and then wants to render a second scene, they can just _reset_ the context and then reuse it instead of having to initialize a new one. This is important because during the rendering process, _Vello CPU_ needs to make a number of memory allocations which can have an impact on runtime. By reusing the same `RenderContext`, Vello CPU can reuse the existing memory allocations in subsequent rendering operations, leading to better performance. This property is especially useful in the context of GUI rendering, where it is common to render the same scene dozens of times per second over an extended period of time.

Now, the user can start rendering items to the scene. In this specific example, we first render a centered rectangle of width 50 using a fully opaque blue, followed by a smaller, semi-transparent red rectangle in the bottom right. In the end, we draw a green stroked circle. For multi-threaded rendering, we also need to make a call to the `flush` method in the end, whose purpose will be explained in @multi-threading.

By specifying drawing instructions in the render context, we are not doing the full rendering yet. In order to produce an actual picture we first need to create a new `Pixmap`. A pixmap is basically a "fancy" wrapper around a `Vec<u8>` (a vector of bytes in Rust) that can store raw, premultiplied RGBA pixels. Remember that in @colors, we explained that RGBA values can either be stored as `f32` or `u8`. In this case, we are simply storing the value of each pixel in the pixmap as integers in row-major order. For example, if we have a pixmap of size 2x2 where the top-left pixel is green, the top-right pixel red, the bottom-left pixel blue and the bottom-right pixel white, we would store this in one contiguous vector containing the bytes #raw(lang: "rust", "[0, 255, 0, 255, 255, 0, 0, 255, 0, 0, 255, 0, 255, 255, 255, 255]").

By calling the `render_to_pixmap` method, we now instruct Vello CPU to render the previously recorded rendering instructions into the pixmap. The pixmap can then be further processed by, for example, converting it into a PNG file and saving it to disk. The rendered result of @api_example_Listing can be seen in @api_example_result.

#figure(
  image("assets/api_code_result.png", width: 50%, scaling: "pixelated"),
  caption: [The rendered result of the code in @api_example_Listing.],
) <api_example_result>


== Architecture overview <architecture_overview>
In order to convert a vector image into a raster image, there are various intermediate steps to arrive at the final result. While a few steps are virtually universal and done by most renderers in a similar form, the exact implementation of the whole rendering pipeline varies a lot across different implementations.

An interesting aspect of the design of Vello CPU is that it has a highly modular architecture where each step takes a specific kind of data structure as input and produces some intermediate output which can then be consumed by the next stage in the pipeline. There are no cross-dependencies between non-consecutive stages. As will be seen in the following subsections, this property makes it easy to explain the functionality of each module in isolation and visualize the intermediate results that are produced after passing through each stage. The stages of the rendering pipeline and their dependencies are illustrated in @overview_pipeline. A summary of each stage is provided below, and more details on them will be given later on.

#figure(
  image("assets/overview_pipeline.pdf"),
  caption: [An overview of the rendering pipeline in Vello CPU.],
) <overview_pipeline>

The pipeline is illustrated in @overview_pipeline. Overall, the steps can be grouped into three categories: _Path rendering_, _coarse rasterization_ and _rasterization_. 

The user starts by creating a render context and specifying drawing instructions, such as filling a rectangle or stroking a circle. The only difference between stroking and filling is that stroking requires an additional step called _stroke expansion_ in the beginning, which manipulates the input path in such a way that filling the area of the new path has the same visual effect as stroking the old one. By doing this, we can treat filled and stroked paths the same in subsequent stages.

The next stage is called _flattening_. As was mentioned in @drawing_primitives, the two basic primitives used for drawing are lines and curves. As part of this stage, the path is converted into a different representation such that the whole geometry is solely described by lines. Converting curves to lines is naturally a lossy operation since curves inherently cannot be represented by just lines, but by using a sufficiently large number of lines, the error in precision will be so small that it cannot be noticed in the final result. The advantage of this conversion step is that the follow-up stage in the pipeline only needs to process line primitives instead of curves _and_ lines, which greatly reduces the complexity.

After that, _tile generation_ is performed. In this stage, we conceptually segment the whole canvas into areas of size 4x4. For each path, we calculate all of the areas that it crosses, generate a 4x4 tile for it and associate it with the given line. In the end, all generated tiles are sorted by their y and x coordinates.

The following _strips generation_ stage is arguably the most crucial step in the pipeline: In this stage, we iterate over all tiles in row-major order (this is why tile generation has a sorting step in the end) and merge horizontally adjacent tiles into strips. For each pixel covered by a strip, we calculate the alpha value that is necessary to perform anti-aliasing. The output of this stage is a vector of strips that sparsely encodes the rendered representation of the shape by only explicitly storing anti-aliased pixels and representing filled areas implicitly.

Once the path has been converted into sparse strips representation, they are passed to the _coarse rasterizer_. The coarse rasterizer segments the canvas into so-called _wide tiles_ (not to be confused with plain tiles from the tile generation stage) which all have a dimension of 256x4 pixels. We then iterate over all strips and generate the actual rendering commands that should be applied to each wide tile.

Once this is done, control is passed back to the user, in which case they have two choices: Either, they keep rendering more paths, in which case the above-mentioned stages are re-run for the new path, or the user calls the `render_to_pixmap` method, in which case _fine rasterization_ kicks off.

Fine rasterization is where the actual coloring and compositing of pixels happens. This works by iterating over all commands in each wide tile and performing operations like "fill this area using a blue color" or "fill this area using a gradient color". For reasons that will be explained later, all of this happens in an intermediate buffer instead of the user-supplied pixmap. Once fine rasterization is complete, we start the process of _packing_, where the contents of the intermediate buffer are copied into the pixmap that the user provided. In the end, the fully rendered result is stored in the pixmap and can be processed further by the user.

== Stroke expansion <stroke_expansion>

In @fills-and-strokes, it was mentioned that there are two types of drawing mode that need to be implemented: Stroking and filling. There are different ways in which stroking can be implemented. In our case, we decided to use the so-called _stroke expansion_ approach. When doing stroke expansion, the original path description in transformed in such a way that filling the areas of the newly extended path has the same visual effect as stroking the outline of the original path. The idea is illustrated in figure @stroke-expansion-fig. If we want to draw a stroke with width 1 pixel, we compute two new _offset curves_ that are each offset by half the stroke width inward and outward. Filling this area of the new path results in a painted line that is centered on the original outline description of the shape.

#subpar.grid(
  figure(image("assets/butterly_path.svg", width: 100%), caption: [
    The outline of the butterfly shape. 
  ]),
  figure(image("assets/butterfly_expanded.svg", width: 100%), caption: [
    Expansion of stroke with width 1.
  ]),
  figure(image("assets/butterfly_colored.svg", width: 100%), caption: [
    Filling of the expanded path.
  ]),
  columns: (1fr, 1fr, 1fr),
  caption: [Reducing the problem of stroking a shape to the problem of filling its expanded version.],
  label: <stroke-expansion-fig>,
)

The main advantage of the stroke expansion approach is that it allows us to treat filled and stroked paths in the exact same way throughout the whole rendering pipeline, allowing for further simplification. The only difference is that stroked paths go through an additional step in the beginning of the pipeline.

Given that our renderer is implemented in Rust, we decided to use the Kurbo#footnote[https://crates.io/crates/kurbo (accessed on 15.09.2025)] library for this purpose as it provides an implementation for stroke expansion. It takes a path description, the settings of the stroke as well as a _tolerance_ parameter as input and returns the expanded version of the stroke as the output. The _tolerance_ parameter represents a trade-off that needs to be carefully balanced: Creating a mathematically completely accurate offset curve is not always possible. If we choose a lower tolerance, the expanded stroke will be more accurate at the cost of containing more path segments, which ultimately means more work for later parts of the rendering pipeline. If we choose a higher tolerance, the expanded stroke will contain fewer path segments, but the chance of visual artifacts being introduced is higher. In our case, we settled on a tolerance of $0.25$, which has so far shown to be sufficient.

As outlined in #cite(<stroke_to_filled>, form: "prose"), stroke expansion is a complex and mathematically challenging problem. One of the main difficulties is handling the various edge cases correctly, some of which even many of the mainstream renderers do not. Since implementing the stroke expansion logic was not part of this project, we will not dive into the internals of Kurbo's algorithm and leave it at this high-level description to give an intuition.

== Flattening <flattening>
Now that we have an expanded version of our stroke or a shape the user wants to fill, we reach the next step in the pipeline: flattening. The idea of having this step is as follows: We want to convert our input shape, which consists of lines and curves, into a new representation which consists of just lines. By doing so, later steps in the pipeline only need to consider line segments as the basic building blocks, an assumption that will largely simplify the logic.

#figure(
  image("assets/butterfly_flattened.pdf"),
  caption: [Parts of the butterfly shape flattened to lines. The first and third figures represent the original path segments, the second and fourth figures their respective flattened version. The red points indicate the start/end points of the line segments.]
) <butterfly-flattened-fig>

However, line segments usually cannot accurately model curve segments. This can also be seen in @butterfly-flattened-fig. While the flattened versions of the shape _overall_ still look curvy, zooming in makes it apparent that it is approximated by a number of connected lines. For plain vector graphics, doing such a simplification would clearly be unacceptable. The crucial point here is that the simplification will be barely noticeable once the shape is rendered to pixels, because as part of the discretization process, the information whether a line or curve was used is lost; all that is left is an approximation of pixel coverage in the form of color opacity. And assuming that the number of used line segments is sufficiently large, the change in pixel coverage will be so small that it is unnoticeable to the naked eye.

In order to achieve flattening of curves, we once again resort to the implementation that is provided in the Kurbo library (though as mentioned in @simd, the implementation was adapted to be SIMD-optimized), which is based on an algorithm described in a blog post @flattening_quadratic_curves. Similarly to stroke expansion, the method for flattening takes a path with arbitrary curve and line segments as well as a _tolerance_ parameter as input. The tolerance parameter indicates what the maximum allowed error distance between a curve and its line approximation is and represents another trade-off: A smaller tolerance will yield higher accuracy but result in more line segments, higher tolerance will result in less emitted lines but might cause noticeable artifacts when rendering. We once again settled on the value $0.25$ for this parameter, which means that the error distance can never be larger than one fourth of a pixel.

The algorithm works roughly as follows: We iterate over each path segment in the input geometry and perform one of the following operations on it. 

In the case of lines, there is no additional work to be done and they can just be re-emitted.

For quadratic curves, things start to get more interesting. One possible approach to flattening them would be doing a _recursive subdivision_, which means that we try to build a line between start and end point, and in case the maximum error is too large, we _subdivide_ our current curve in the center and perform the same operation recursively on both halves, until the spanned line of all subdivisions is within the given error bound @flattening_quadratic_curves. While this approach works, it has a tendency to generate more lines than necessary, a side effect that emerges from always doing the subdivision at the center of the curve.

The algorithm in the blog post instead presents a different approach that is based on mathematical analysis: We first calculate the number $n$ of line segments that are needed for the subdivision using an integral that is derived from a closed-form analytic expression, and only then determine the actual subdivision points by subdividing the interval into $n$ equal-spaced points and applying the inverse integral on them @flattening_quadratic_curves. The result will be an approximation that usually uses fewer line segments than the recursive subdivision approach.

For cubic curves, the Kurbo implementation simply first approximates the original cubic curves by quadratic curves and then applies the same algorithm that was outlined above.

=== Optimizations <flatten_opt>
As part of doing the profiling, it became apparent that the initial implementation of flattening was often somewhat slow, especially for small shapes with lots of curves. Two optimizations were implemented that, as will be shown in @evaluation, lead to a significant decrease in runtime for curve-heavy geometries.

To understand the first optimization, it is important to realize that curve flattening is time-consuming, even if the curve we are processing is actually small, as some of the computations such as estimating the number of subdivisions and actually doing the subdivision need to be performed regardless of the size. The core insight leading to the first optimization is that in the case of small curves, there is a good chance that all of that work is unnecessary as we will simply end up approximating the whole curve by a single line segment, as the maximum distance between the straight line and the curve does not exceed our threshold. Therefore, before starting the flattening process, we first use the position of the start and end points as well as the control points to determine whether it is even possible that the curve exceeds the tolerance threshold. If this is not possible, we just emit one single line segment instead of doing curve flattening in the first place. As will be shown in @evaluation, this gives us a considerable edge over the other renderers when drawing shapes with small curves.

The second optimization relates to the method used to estimate the number of quad curves needed to subdivide a cubic curve. The original implementation looked like shown in @estimate_quads_old.

#figure(
  block(width: 80%)[
    ```rs
fn estimate_num_quads(c: CubicBez, accuracy: f32) -> usize {
    const TO_QUAD_TOL: f32 = 0.1;
    const MAX_QUADS: usize = 16;
    
    let q_accuracy = (accuracy * TO_QUAD_TOL) as f64;
    let max_hypot2 = 432.0 * q_accuracy * q_accuracy;
    let p1x2 = c.p1.to_vec2() * 3.0 - c.p0.to_vec2();
    let p2x2 = c.p2.to_vec2() * 3.0 - c.p3.to_vec2();
    let err = (p2x2 - p1x2).hypot2();
    let n_quads = ((err / max_hypot2).powf(1. / 6.0).ceil() as usize).max(1);

    n_quads.min(MAX_QUADS)
}
```
  ],
caption: [The original function for estimating the number of quad curves for subdividing a cubic curve.]
) <estimate_quads_old>

Without diving into the exact semantics of this function, note that the function contains a call to `powf`, which is necessary for correctness but also showed up as a significant bottleneck in performance profiles. The core insight for the second optimization is that while the call is necessary for correctness, we do not actually care about the precise fractional result of the call, as the resulting value is always rounded up to the next integer and clamped between 1 and 16. Because of this, a much faster approach is possible where we precompute a lookup table containing the sixth power of all integer numbers between 1 and 16 and determining the right one by simply doing a linear search to find the first value that is less than or equal to `err / max_hypot2`. Implementing this optimization completely eliminated the `powf` bottleneck and lead to a significant speedup in nearly all benchmarks that involve curves.

== Tile generation <tile-generation>
After converting the shape into flattened lines, the next step is tile generation. The main purpose of tile generation is to determine the pixels on the canvas that could _potentially_ be affected by anti-aliasing. A pixel _can_ have anti-aliasing if and only if a line crosses that pixel, as anti-aliasing is a correction procedure that is only triggered by the edges of shape contours.

In order to do so, we conceptually segment our drawing area into smaller sub-areas of size 4x4 pixels. Note that there is no inherent reason why we have to choose this specific size and we could also opt to choose a size like 2x2 or 8x8 pixels instead. However, there is a trade-off to balance here which will be elaborated further in @strips-generation.

Then, we iterate over all lines in our input geometry and generate _one_ tile for each area (indicated by a blue square in @generating-tiles) that the line covers. We do this by first calculating the bounding box of the line in tile coordinates, which in this case encompasses 7x3 tiles. Then, we iterate over them in row-major order and calculate whether the line has any intersection point with the tile area. If so, we generate a new tile at that location. If not we, just ignore the location and proceed to the next location.

#figure(
  image("assets/tile_line_example.svg", width: 60%),
  caption: [Generating tiles for a line. Yellow points represent the locations where the line intersects the top of a tile.]
) <generating-tiles>

As can be seen, tiling is very similar to the concept of conservative rasterization @conservative_rasterization, where the goal is to conservatively determine which pixels are covered by the shape. The main difference lies in the fact that we are dealing with line primitives instead of triangles, and the calculation is based on 4x4 tile areas instead of individual pixels.

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
  caption: [The generated tiles for the butterfly shape. Each line segment generates at least one tile, and there can be multiple overlapping tiles at the same location.]
) <butterfly-tiles>

As a final step, we sort our buffer that stores all tiles first by ascending y-coordinate and then by ascending x-coordinate to ensure that the tiles are stored in row-major order from top to bottom. In order to do so, we use the `sort_unstable` method provided by the Rust standard library.

== Strips generation <strips-generation>
We now arrive at the most integral part of the pipeline, namely strip generation. There are a lot of details and subtleties to unpack here, and it is therefore worth re-exploring the original motivation before diving into the implementation.

=== Motivation
When rendering a shape, there are three types of computations that may be performed:
+ For pixels strictly inside of the shape, not a lot of work needs to be done. We just need to set the value of the pixel to the given color. This is computationally speaking relatively cheap.
+ For pixels strictly outside of the shape, nothing should be done at all.
+ For pixels on the edge, more work needs to be done: We need to check how the line intersects the pixel and calculate the area coverage in order to determine the correct opacity for anti-aliasing. This is a much more expensive operation and we therefore want to perform it only for pixels where it is really necessary.

One of the core goals of strip generation is to calculate the opacity values for all pixels that could potentially be affected by anti-aliasing. However, in addition to that, we also group the pixels in a smart way and store additional "metadata" such that all the information that is needed to reproduce the original shape for rendering (which includes the opacity values for anti-aliased pixels as well as information about which areas should be completely filled and which ones should not) can be easily inferred later on. The key innovation of sparse strips is to do that in a very storage-efficient way by only storing anti-aliased pixels explicitly while representing filled and blank areas implicitly. 

=== Merging tiles into strips
The first step of the strip generation algorithm is relatively straight-forward: We iterate over all tiles (remember that they are already sorted in row-major order), and merge horizontally-adjacent tiles into single _strips_. These strips have the same height as the tiles, but the width can vary depending on how many adjacent tiles there are, as is visualized in @butterfly-strip-areas. The blue colored strips represent any area where we will explicitly calculate opacity values for anti-aliasing. Any pixel not falling within a strip will _not_ be explicitly stored.

#figure(
image("assets/butterfly_strip_areas.svg",width: 40%),
  caption: [The areas of the generated strips, marked in blue.]
) <butterfly-strip-areas>

=== Calculating strip-level winding numbers
Generating the merged strips is only a small part of the overall process. The next step is understanding how we can encode necessary information so that in later stages of the pipeline, we can easily determine which areas between two strips on the same row should be filled and which ones should not. In order to understand how this works, we need to remind ourselves about the concept of winding numbers as they were introduced in @fill_rules: Conceptually, we shoot a ray into any direction and increase or decrease a winding number counter each time we intersect a line of the path depending on the direction of the line. In our case, there are actually two different winding numbers that we need to keep track of. 

The first winding number is the _strip-level winding number_. At the top of each strip row, we conceptually "shoot a ray" from the very left to the very right. Each time we encounter a tile that intersect a line (remember that for each tile, we store a boolean flag with that information, allowing us to easily check that), we account for this while calculating the winding number of the _next_ strip. 

#figure(
image("assets/butterfly_coarse_winding_number.pdf", width: 100%),
caption: [Calculating the strip-level winding number for each strip on the third row of the butterfly in @butterfly-strip-areas. The yellow points indicate the intersection points of the lines with a tile area.]
) <coarse-winding-fig>

@coarse-winding-fig shows an example of doing this computation. The first strip on the very left has a start winding number of 0, as it is the leftmost part of the shape on this row. Inside of this strip, we have one tile that has a line intersection at the top. The line is defined from bottom to top, meaning that from the perspective of our imaginary ray, the intersection direction is right-to-left, and thus we _decrease_ our winding counter to -1. Since there are no further intersections in this strip, the strip-level winding number of the _next_ strip will be set to -1. That strip has a left-to-right intersection in its first tile area, meaning that our winding counter is temporarily reset to 0. But in the end, we have yet another intersection in the opposite direction, so we set our counter back to -1. As those are all intersections in that strip, the start winding number of the last strip in the row is going to be -1 as well.

We run this computation for all rows containing strips to assign each strip its winding number. To more easily visualize this, we can now color the strips according to the fill rule (in our case the non-zero fill rule): If the winding number of a strip is zero, we color it in green, otherwise we color it in red. The result is illustrated in @butterfly-strip-areas-with-winding. Note in particular that just storing a simple boolean flag in each strip indicating whether the area to its left should be filled or not according to the fill rule is enough to later on reproduce that information. For every non-covered gap, if the strip on the _right_ side has a non-zero winding number (i.e. is red in the figure), the whole area is painted, otherwise it is not painted. For example, the gap in the first row in @butterfly-strip-areas-with-winding will not be painted since the strip on the very right has a winding number of zero. However, in the third row, both areas will be painted since the strips on the right of each gap have a non-zero winding number. Mentally applying this idea to each row, it becomes evident that this approach is sufficient to later on determine which areas need to be painted, solely based on the encoded information in the strips.

#figure(
image("assets/butterfly_strip_areas_with_winding.svg",width: 50%),
    caption: [The areas of the generated strips, with the strips painted according to their winding number. Green areas indicate that gaps on the left should not be painted according to the fill rule, while red areas indicate that gaps on the left should be filled.],
  ) <butterfly-strip-areas-with-winding>

=== Calculating pixel-level winding numbers <pixel-level-winding>
We now have encoded the information necessary to determine fully-painted areas in later stages of the pipeline, but we have yet to determine the opacity values of the pixels _inside_ of strips to apply anti-aliasing. In principle, we use a very similar "ray-shooting" approach that we used to determine the strip-level winding number, with the main difference being that we are now considering rays intersecting individual _pixel rows_ (instead of strip rows) and also considering _fractional_ winding numbers. The process is visualized in @strip-winding-numbers on the basis of the first strip in the first row.

#figure(
image("assets/strip_winding_numbers.pdf", width: 85%),
    caption: [Calculating winding numbers of each pixel in a strip. We first calculate the winding numbers for each tile, and then sum the result to calculate the total winding number of each pixel in the whole tile area. Red areas represent the trapezoid spanned by the line.],
  ) <strip-winding-numbers>

For each strip, we once again look at its constituent tile areas. We initialize a temporary array of 16 floating point numbers (one for each pixel in a 4x4 tile area) to the winding number of the strip and store them in *column-major* order (the reasoning behind this will be elaborated in @fine_rasterization). We then iterate over all tiles inside the given 4x4 tile area and compute the trapezoidal area that is spanned between the line and the right edge of the tile (marked in red in the figure). For each pixel, we then calculate the fraction of its area that is covered by the trapezoid. Note that the resulting winding number can also be _negative_ depending on the direction the line intersects the pixels with. We then sum the fractional windings of all tiles in the same area into our temporary array, until we end up with the final winding number for each pixel. Next, we convert the winding numbers into opacities between 0.0 and 1.0 by applying the fill rule and scale them by 255 so that we can store them as `u8`. The array of the 16 opacity values is then pushed out into a buffer and the whole process is restarted for the next tile area in the strip, using the winding numbers for the right-most column as the basis. Doing this for all strips and visualizing the calculated opacities, we end up with the representation that is shown in @butterfly-all-strips.

#figure(
  image("assets/butterfly_all_strips.svg", width: 35%),
  caption: [The opacity values for all strips. Completely black pixels represent 100% opacity, white pixels 0%, shades of grey intermediate values.],
) <butterfly-all-strips>

By now, we have all the information needed to fully draw the complete shape. We have calculated the opacity values of all anti-aliased pixels and represent to-be-filled areas in an implicit way, just by storing a `Vec<Strip>` that represents the whole rasterized geometry of a single shape. As can be seen in @strip-fields, a strip only needs to store its start x and y positions, whether the area to its left should be filled depending on the winding number and active fill rule as well as an index into the global alpha buffer containing the opacities of each pixel in the strip. Note in particular that there is no need to explicitly store the width of the strip, as it can be inferred by looking at the `alpha_idx` of the next strip. For example, if one strip has an alpha index of 80 and the next strip an index of 160, the width of the strip is $(160 - 80) / 4 = 20$ pixels, since a strip always has a height of 4.

#figure(
  [
    ```rs
struct Strip {
    x: u16,
    y: u16,
    alpha_idx_fill_gap: u32,
}
    ```
  ],
  caption: [The information stored inside of a strip. The `alpha_idx_fill_gap` represents a bit-packed field where the first 31 bits are used to store the index into the alpha buffer that contains the opacity values for each pixel in the strip, and the last bit represents a boolean indicating whether the sparse area to the right of the strip should be filled. ],
) <strip-fields>

With the sparse strip representation of the path generated, the path rendering stage of the pipeline (as shown in @overview_pipeline) concludes. The unique aspect of sparse strips is that the representation is very versatile and can be processed in multiple ways. On the one hand, we can pass it on to the next stage to commence the actual rasterization process and render it onto the screen. 

On the other hand, we could for example use it for caching purposes: Imagine that we want to draw a GUI at 60 frames per second. Over the course of time, it is likely that the vast majority of the GUI remains static and only small parts change each frame. Because of this, we can opt to compute the sparse strips representation of elements like buttons and text fields during the first run and cache them, so that in subsequent runs we do not have to rerun the whole path rendering stage for those elements, saving a lot of time. The usual approach for caching would be to render the elements to a bitmap image with a given size, but by virtue of having this intermediate representation, we can achieve the same goal in a much more memory-efficient way.

=== Tile size
Initially, it was claimed that the point of strip rendering is to only calculate the opacities of _anti-aliased pixels_. However, looking at @butterfly-all-strips, it becomes apparent that this is not entirely true: There are many pixels that either have full opacity or no opacity at all and therefore do not require any anti-aliasing at all. They were only included by virtue of being in the _vicinity_ of anti-aliased pixels and being part of the same tile.

#figure(
  block(width: 70%)[
    #grid(
    row-gutter: 3mm,
    column-gutter: 3mm,
    columns: (1fr, 1fr),
    image("assets/butterfly_tile_size_1.svg", width: 100%),
    image("assets/butterfly_tile_size_2.svg", width: 100%),
    image("assets/butterfly_tile_size_4.svg", width: 100%),
    image("assets/butterfly_tile_size_8.svg", width: 100%),
  )
  ],
  caption: [The butterfly processed with tile sizes 1, 2, 4 and 8 from top-left to bottom-right.],
) <butterfly-tile-sizes>

In principle, it is very much possible to use different tile sizes, as is shown in @butterfly-tile-sizes. However, both increasing and decreasing the tile size come with their own caveats. In the case of 8x8 pixels, we have fewer tiles which means lower overhead when generating and sorting them. However, the disadvantage is that our tiles cover _many more_ non-anti-aliased pixels, implying higher memory requirements and also many more pixel-level anti-aliasing computations that need to be performed, which are expensive. Using tile sizes of 1 and 2 on the other hand _reduce_ the number of performed anti-aliasing computations, but the downside is that the bottleneck will instead shift toward tile generation and sorting, as we will need to generate many more tiles. A tile size of 4 is a good balance; the tiles are not too large and we therefore do not need to perform too many unnecessary anti-aliasing computations and reduce the sparseness of the representation, but also not too small, resulting in reasonable performance during tile generation and sorting. In addition to that, as will be demonstrated in @simd, a tile size of 4 hits the sweet spot for efficient SIMD optimizations.

=== Sparseness
With a good understanding of how sparse strips work, it is worth analyzing the sparseness property in more detail. One area the intermediate representation is particularly useful for is path caching. In traditional renderers, the usual way to implement patch caching is to render a path into an intermediate bitmap image and then just paint the whole image when reusing it in the future. In particular, this requires us to explicitly store the value of each pixel covered by the shape. If we were to cache the butterfly shape rendered to a 256x256 resolution, we would therefore need $256 dot.c 256 #sym.approx 65$KB of storage. For 512x512, we would need around 262KB and for 1024x1024 around 1MB. As can be seen, the storage requirements increase linearly with the overall number of pixels.

This is not the case for sparse strips, because we are only explicitly storing information about pixels at the path boundary, while large filled areas are represented implicitly. According to our calculaions, rendering the butterfly to 256x256 results in the generation of 259 strips and 7296 alpha values. Since a single strip has a memory footprint of 64 bytes, the necessary storage amounts to $259 * 64 + 7296 #sym.approx 24$KB. For 512x512, we get 544 strips and 15024 alpha values, resulting in $544 dot.c 64 + 15024 #sym.approx 50$KB. For 1024, we get 1159 strips and 30848 alpha values, resulting in around 105KB of storage, representing a nearly tenfold decrease compared to the traditional caching approach.

== Coarse rasterization <coarse-rasterization>
Coarse rasterization serves as a preparatory step before actually rendering the shape into a pixmap. We start by conceptually splitting the complete drawing area into into so-called _wide tiles_ (to be distinguished from the 4x4 tiles introduced earlier) which always have a dimension of 256x4 pixels. For example, in case we are rendering to a 50x50 screen, we would have $ceil(50 / 256) dot ceil(50 / 4) = 13$ wide tiles in total. If we increase the width to 312, we instead end up with $ceil(312 / 256) dot ceil(50 / 4) = 26$ wide tiles.

Each wide tile contains an (initially empty) vector of commands that represent rendering instructions. As can be seen in @wide-commands, we distinguish between two main commands: _Fill_ and _AlphaFill_ commands.

#figure(
  grid(
    columns: (1fr, 1fr),
    ```rs
struct CmdFill {
    x: u16,
    width: u16,
    paint: Paint,
    blend_mode: BlendMode,
    compose: Compose
}
    ```,
    ```rs
struct CmdAlphaFill {
    x: u16,
    width: u16,
    alpha_idx: usize,
    paint: Paint,
    blend_mode: BlendMode
    compose: Compose
}
    ```
  ),
  caption: [The structure of of fill and alpha fill commands.]
) <wide-commands>

They are very similar and mostly contain the same fields: The `x` field indicates the horizontal starting position of the command and the width how many pixels it spans horizontally. Note that there is no need to store a `y` or `height` coordinate, as a command always applies to the full height of the wide tile it is stored in. The `paint` indicates how the pixels should be painted with. It can either be a solid color, or a complex paint like a gradient or a bitmap image. Alongside, we also store which blend mode and composition operator should be used for the pixels. 

The only difference between fill and alpha fill commands lies in the fact that alpha fills have an additional `alpha_idx` property, which serves the following purpose: Normal fill commands are used for filling the areas _in-between_ strips where there is no anti-aliasing, while alpha fill commands are used for the regions inside of strips which require an additional opacity factor to be applied to the pixels.

We now iterate over the sparse strips representation of our path to generate the appropriate commands for each wide tile. Conceptually, this is not difficult as each row of strips has a 1:1 correspondence to a row of wide tiles. @wide-tile-gen demonstrates this for the second row of strips of our butterfly.

#figure(
  image("assets/wide_tile_commands.pdf"),
  caption: [Generating wide tile commands for a row of strips. Green rectangles represent the strips, red ones the implicitly to-be-filled areas. The `paint`, `blend_mode` and `compose` fields have been omitted for brevity.],
) <wide-tile-gen>

For strips, we more or less just need to copy the `x` and `alpha_idx` properties of the corresponding strip and calculate the implicitly represented width to generate a new alpha fill command. For the gaps between strips, we proceed as previously outlined: In case the right strip has `fill_gap` set to `true`, we generate a corresponding fill command, as is the case for the gap between strip 1 and 2 as well as strip 3 and 4 in @wide-tile-gen. Otherwise, we simply leave the area untouched, like for example the gap between strip 2 and 3. 

The whole procedure is performed for all wide tile rows, until all commands have been generated. Once this is done, the first phase of rendering is completed and control is handed back to the user. Either, the user decides to render additional paths, in which case the whole cycle of path rendering is repeated and more drawing commands will be pushed to the wide tiles, or the user decides to finalize the process by kicking off the rasterization process via a call to `render_to_pixmap`.

== Fine rasterization <fine_rasterization>
Given a set of wide tiles that contain draw commands, the actual rasterization process will now be started. As part of this stage, we calculate the RGBA values of each pixel by iterating over each wide tile and processing them in isolation. Every time we go to a new wide tile, an empty scratch buffer with the dimension 256x4 pixels (i.e. the same area dimensions of a wide tile) is created and each pixel is set to the RGBA value (0.0, 0.0, 0.0, 0.0), so a fully transparent color. Note that pixel values are stored in _column-major_ order. The rationale for doing so is that it improves cache efficiency, since the pixels that are processed as part of processing the commands will be stored contiguously in memory.

When processing the commands, we first need to determine the range of pixels that we want to fill, which is straightforward because each command stores that information. For example, if we are processing the third row of wide tiles and encounter a `Fill` command with `x` set to 24 and `width` set to 24, we can infer that all pixels that fall within the rectangle spanned by the points (24, 12) to (48, 16) should be painted with the paint stored in the command. Note that since the height of a strip is always 4, the height of a command is also always 4. The steps that are outlined below then have to be done for each pixel in the area.

=== Computing pixel color
The first step in fine rasterization is to calculate the _raw_ color value of the pixel, which is determined by the paint that we are using. In the case of a solid color, this is trivial as the pixel just assumes that very color. However, the story is different for image and gradient paints, where the color value depends on the exact location of the pixel.

==== Image paints
In @patterns_rect, we illustrated the concept of image paints based on a 10x10 input texture which is scaled up by the factor of 50 to fill a rectangle with the dimensions 500x500. Assume for example that we are currently processing the pixel at the location (385, 110). If we want to determine the color of that pixel using the nearest-neighbor method, we simply need to _reverse_ the scaling process and then sample the color value of the closest pixel value in the input texture. Since our scaling factor is 50, we simply divide by that factor, which results in the position $(385 / 50, 110 / 50) =$ (7.7, 2.2). As can be seen in @sampling-nn-fig, the nearest neighbor of this fractional location is the pixel at the location (7, 2) which is orange. Therefore, the pixel at the location (385, 110) in the new image will also assume the color orange.

#subpar.grid(
  figure(image("assets/sample_nn.svg", width: 100%), caption: [
    Nearest neighbor.
  ]), <sampling-nn-fig>,
  figure(image("assets/sample_bilinear.svg", width: 100%), caption: [
    Bilinear filtering.
  ]), <sampling-bil-fig>,
  figure(image("assets/sample_bicubic.svg", width: 100%), caption: [
    Bicubic filtering.
  ]), <sampling-bic-fig>,
  columns: (1fr, 1fr, 1fr),
  caption: [The different image sample strategies. The black dot (in @sampling-nn-fig at the same location as the red dot) represents the original location, the red dots the sampled locations.],
  label: <sampling-fig>,
)

The story is a bit different when using bilinear filtering instead. In this case, we instead sample the color values of the four _surrounding_ locations (like in @sampling-bil-fig) and perform a linear interpolation of those samples by weighting them based on their exact fractional location within the pixel. The resulting color will then neither be a clean orange or yellow, but instead some intermediate color. Doing this for all pixels achieves the effect of smoothing the edges between pixels with varying colors, as was previously shown in @rect_bilinear. Bicubic filtering operates on a similar basis, but instead samples the surrounding 16 pixels and then uses a cubic filter for weighting the contributions of each sample based on proximity. The result will be an even smoother blending between pixel edges, as was visible in @rect_bicubic, at the cost of a higher computational cost.

==== Gradient paints
As was mentioned in @background-gradients, gradients allow us to represent smooth transitions between different colors along a certain trajectory. When doing fine rasterization, we need to calculate the exact position of the pixel along the gradient line so that the color that the pixel should be painted with can be determined. How exactly this is achieved depends on the gradient type.

#figure(
  image("assets/gradient_t_vals.pdf", width: 80%),
  caption: [Determining the $t$-value of a pixel for each gradient type.],
) <gradient-t-vals>

Linear gradients are defined by a start and end point that define the line used as the basis for the color gradient, as was previously shown in @rect_linear. In order to calculate the parametric `t` value for any arbitrary pixel position, we just need to calculate the intersection of the _perpendicular_ line that passes through the pixel position. If the intersection point lies exactly at the start point, the value of $t$ will be zero. If it instead lies at the end point, the value will be one. Otherwise, for any position in-between the value will be some fractional value between zero and one, as seen in @gradient-t-vals.

Radial gradients instead are defined by a start and end circle which each have their respective center points and an associated radius. In @gradient-t-vals, both circles are centered in the middle and the radius of the start circle is zero. The visual result is a circle that keeps expanding its radius while constantly changing the color depending on the $t$ value. In order to calculate the $t$ value at any arbitrary pixel position, we simply need to calculate the distance of the pixel to the gradient center and then divide it by the radius of the outer circle, giving us the $t$ value in the range 0.0 to 1.0. Note that the above calculation assumes that the start and end circles are concentric and the start radius is 0, which represents the simplest case. However, there are many other possible variations, in which case the above method is not sufficient anymore. For example, the start radius could be larger than 0 or the center points of the circles could be at different locations. To account for these, we decided to adopt the same approach as Skia#footnote[https://github.com/google/skia/blob/a38a531dec1de335b5ffdf174e2a97b2d450c8d6/src/shaders/gradients/SkConicalGradient.cpp (accessed on 21.09.2025)], where the radial gradient is assigned to a specific category based on its properties and an appropriate formula is then used to compute the value of $t$ for a specific location. However, since the details of this approach are relatively intricate, we will not elaborate them here and leave it at this high-level description.

For sweep gradients, we only need to determine the angle of the pixel in relation to the center point, which can be easily done using the `atan2` function. In our case, similarly to Skia we do not actually use the `atan2` function but instead compute the angle with the help of a polynomial approximation, as this makes it easier to compute the angle for multiple pixels at a time using SIMD (see @simd).

After having determined the $t$ value, we need to calculate the corresponding color value. This is achieved by looking at the two surrounding color stops and doing a linear interpolation based on the position between the two stops. For example, let us assume that we have a blue color stop at the position $t = 0.15$ and a red color stop at the position $t = 0.40$. We now want to determine the color that should be used for the value of $t = 0.33$. We first scale the $t$ value to the range [0.0, 1.0] so that 0.0 stands stands for fully blue and 1.0 for fully red: $(0.33 - 0.15) / (0.40 - 0.15) = 0.72$. Doing a simple linear interpolation will yield the final color: $0.28 dot (0.0, 1.0, 0.0, 1.0) + 0.72 dot (1.0, 0.0, 0.0, 1.0) = (0.72, 0.28, 0.0, 1.0)$. A feasible approach would be to run this calculation for every pixel after we have determined the $t$ value, but doing so would be very costly. 

Instead, what we do is that we _precompute_ a LUT (look-up table) that contains pre-calculated color values for specific $t$ values between 0.0 and 1.0. Depending of the number of color stops, the number of entries is either 256, 512 or 1024. After calculating the $t$ value of a pixel, we then look up the color value of the entry that is the closest to our $t$ value and use that. By doing so, the necessary work for each pixel is reduced from computing the linear interpolation to a simple memory access, which is significantly faster. The downside is that the color values will not always be a 100% accurate, but thanks to the high resolution of the LUT, the differences will be so small that they are not noticeable. Another downside is that we need to do a lot of computations ahead of time, even though not all of them might be needed in the end, but especially for larger-sized geometries this initial overhead is fully eclipsed by the performance improvement that arises from reducing the per-pixel workload.

=== `Fill` vs. `AlphaFill` commands
Previously, we introduced the distinction between the `Fill` and `AlphaFill` commands, the only difference being that alpha fill commands apply an additional opacity to account for anti-aliasing. To account for that, in case we are processing an alpha fill command we multiply the calculated raw pixel value by the opacity for anti-aliasing before processing it further. Apart from that small additional step, the two commands can be treated the same.

=== Compositing and blending
After having determined the raw pixel value, we arrive at the core part of fine rasterization that does blending and compositing. If we are only drawing a single shape, we could simply copy the raw pixel values into the scratch buffer and we would be done. However, the key is that a rendering engine needs to account for the fact that multiple shapes with different paints can be overlapping each other. In particular, the scratch buffer might contain colored pixels from previous drawing instructions which we now need to combine with the generated pixels from our current drawing command according to the rules that were outlined in @compositing and @blending-sect.

==== Alpha-compositing
The simplest and by far the most common operation is simple alpha compositing, which involves no blending and uses the source-over compositing operator. Due to its prevalence, Vello CPU contains a specialized and highly-optimized code path that handles this specific case. The following formula is used to perform alpha-compositing @w3c2015compositing:

#[
  #set math.equation(numbering: "(1)")
  $ alpha_s dot C_s + alpha_b dot C_b dot (1 - alpha_s) $ <alpha-compositing-formula>
]

 $alpha_s$ stands for the opacity of the source color, $C_s$ for the source color, $C_b$ for the background color $alpha_b$ for the opacity of the background color. Note in particular that there are two expressions that require us to multiply the source/background color with their alpha value. This ties to the previous discussion in @premul-alpha, where it was mentioned that storing color values using premultiplied alpha can save lots of computations, and this formula should make this point more clear. If both the source color $C_s$ (which we just computed) and background color $C_b$ (which is stored in the scratch buffer) are _already_ stored using premultiplied alpha, the formula reduces itself to $C_s + C_b dot (1 - alpha_s)$. The original five arithmetic operators were reduced to just three, which leads to a substantial performance improvement given that this calculation is performed for every pixel. Applying this formula results in a new color value which will override the existing value in the scratch buffer to eventually be reused as the new background color in future computations.

It is worth analyzing @alpha-compositing-formula more closely, as it makes it clear that it is essentially yet another linear interpolation based on the opacity of the source pixel. Assume for example that the background pixel is a fully opaque red, denoted by the tuple (1.0, 0.0, 0.0, 1.0).

First, let us try to compose the background with a fully opaque blue pixel, given by (0.0, 0.0, 1.0, 1.0). Since the $alpha_s$  is 1.0, the compositing formula reduces itself to just $C_s$, which matches our intuition that a fully opaque blue should completely override the previously existing red. On the other hand, if we consider a fully transparent blue with (0.0, 0.0, 1.0, 0.0), pre-multiplying this yields just (0.0, 0.0, 0.0, 0.0). Since $alpha_s$ is 0, the formula changes to just $C_b$, which also matches the intuition that if we compose a fully transparent pixel on top of another one, it should have no effect at all and the background should still be visible like before. Finally, assuming an alpha value of 0.15, we end up with the calculation $(0.0, 0.0, 0.15, 0.15) + (1.0, 0.0, 0.0, 1.0) dot 0.85 = (0.85, 0.0, 0.15, 1.0)$, also confirming the intuition that the result should have a touch of blue, but overall still mostly be red.

==== Normal blending and compositing
In case the user specified a different composition operator or blend mode, we cannot use the above shortcut path and instead use a less-optimized code path which can handle all the different modes. The same basic principles that apply to  alpha-compositing also apply here, the only difference being that the pixel-level calculations become much more extensive and complex, as many of the assumptions that make simple alpha compositing so efficient to implement do not apply anymore. Since this code path mostly consists of applying the well-documented formulas for the given blend mode and compositing operator @w3c2015compositing, the details will not be elaborated here. The final result is the same: A new color value for the given pixel that will be stored in the scratch buffer so that it can be used as the new background color in future compositing operations.

=== `u8`/`u16` vs. `f32` <u8-vs-f32>
As was just shown, the vast majority of the fine rasterization pipeline consists of additions and multiplications of color values. We can choose to run the calculations using either 32-bit floating point numbers that are normalized between 0.0 and 1.0, or 8-bit unsigned integers ranging from 0 to 255. 

For example, assume that we have two colors given by their RGBA values: $ & c_1 = (255, 0, 0, 255) \ & c_2 = (0, 128, 0, 255) $ We now want to determine the color that results from linearly interpolating between the two with a $t$ value of $0.3$ using the formula $t dot c_1 + (1.0 - t) dot c_2$.

For `f32`, we first normalize the numbers by dividing by 255, resulting in $c_1 = (1.0, 0.0, 0.0, 1.0)$ and $c_2 = (0.0, 0.5, 0.0, 1.0)$. Next, we do the interpolation: $0.3 dot (1.0, 0.0, 0.0, 1.0) + 0.7 dot (0.0, 0.5, 0.0, 1.0) = (0.3, 0.35, 0.0, 1.0)$. If desired, we can then scale and round the result back to `u8`, resulting in the value (77, 89, 0, 255).

For `u8`, we instead scale up the fraction and change the formula to $t dot c_1 + (255 - t) dot c_2$ to perform the calculations using only integers, in the end dividing the result by 255 to normalize the result back to the range of a `u8` number: $(77 * (255, 0, 0, 255) + 178 * (0, 128, 0, 255)) / 255 = ((19635, 0, 0, 19635) + (0, 22784, 0, 45390)) / 255 = (77, 89, 0, 255)$. It should be noted that we need to use `u16` numbers for intermediate results to prevent overflows.

As can be seen, at least in this particular case both calculations lead to the same result. However, there is a delicate trade-off between the two methods that becomes especially relevant as the number of calculations for the same pixel increases (which will happen if multiple shapes overlap the same pixel). The integer-based pipeline is usually faster as it allows processing more pixels at the same time due to only requiring 8/16 bits instead of 32 bits per channel. We also use an efficient approximation of a division by 255 instead of actually dividing, as it would otherwise be much slower. However, the clear disadvantage is that in contrast to `f32`, in the case of `u8` are losing much more precision due to quantization. These rounding errors can become bigger as the number of pixel-level calculations increases.

As these rounding errors are usually not noticeable to the naked eye, using the `u8`-pipeline is often preferable, but there are use cases where the higher precision can play an important role. Therefore, Vello CPU gives the user the freedom to decide themselves which pipeline to use.

== Packing <packing>
After completing fine rasterization, the scratch buffer of each wide tile stores the final RGBA values for each pixel that is covered by the wide tile. However, there are four problems that need to be addressed:
- The wide tiles (and in particular their buffers) are not stored contiguously in memory. However, users usually expect one continuous buffer containing pixel data for the _whole_ drawing area.
- Wide tiles have a fixed size of 256x4 pixels, but a pixmap could have a size that is not a multiple of that, for example 53x71 pixels.
- The wide tiles themselves store pixel data in column-major order, while the user expects pixels in row-major order (see @packing-fig).
- In case we are running the high-precision rasterization pipeline, the RGBA values will be stored as normalized `f32` values, but the user usually expects `u8` values for the final pixel values, meaning that we must convert them first.

#figure(
  image("assets/packing.pdf"),
  caption: [The packing process visualized based on a 16x16 pixmap and wide tiles of size 8x4 (for easier illustration). As indicated by the arrows, when copying the pixels into the pixmap, we need to transpose from column-major to row-major order.],
) <packing-fig>

To address these points, there is a final stage called _packing_. As part of this, we iterate over all wide tiles and copy each pixel in the wide tile buffer to the appropriate location in the user-supplied `Pixmap`. Pixels whose position lie outside of the pixmap are simply ignored and not copied. In case the values are stored as f32, we multiply the values by 255 and then round them to the appropriate `u8` values. Once this done, all pixels are stored in the pixmap as premultiplied RGBA values and the user can process them further, for example by encoding the image into a PNG file and storing it on disk. The final rasterized version of our butterfly can be seen in @rasterized-butterfly.

#figure(
  image("assets/butterfly_rasterized.svg", width: 30%),
  caption: [The final rasterized version of the butterfly.],
) <rasterized-butterfly>

== SIMD <simd>
In order to achieve the best performance, implementing SIMD optimizations is indispensable. In many cases, it can be sufficient to rely on auto-vectorization for that purpose, but in our case, this is unsatisfactory for two reasons: Firstly, while the compiler often does a good job at detecting auto-vectorization opportunities, it does not do so 100% reliably and making the intended vectorizations explicit by using SIMD intrinsics is therefore more desirable. Secondly, since the Rust compiler by default needs to produce portable code, it can often only rely on a very reduced set of SIMD intrinsics. For example, in order to instruct the compiler to make use of AVX2 feature, it is necessary to explicitly enable the `avx2` target feature, as a result of which the compiled code cannot be run on x86 devices that do not support these instructions.

=== Library

For Vello CPU, our two main goals for the SIMD implementation were:
+ The SIMD code should be written in a target-agnostic way. We wanted to write our code *once* using an abstraction over SIMD vector types and then have the ability to generate target-specific SIMD code on-demand.
+ The implementation should support runtime dispatching, so that we can for example leverage AVX2 instructions on targets that support it, while falling back to SSE4 or even scalar instructions on targets that do not.

There already exist Rust libraries that attempt implementing such an abstraction, like for example pulp #footnote[https://github.com/sarah-quinones/pulp (accessed on 11.09.2025)]. However, after evaluating available options, we came to the conclusion that it would be most advantageous to build our own abstraction, such that we have full control over the overall architecture and the set of implemented instructions. To this purpose, we#footnote[Other collaborators have contributed to the creation of this library and it was not exclusively built as part of this thesis. As was mentioned in @contrib-notice, the main contribution of this thesis was adding the necessary operator to support all usages in Vello CPU.] built fearless_simd #footnote[https://github.com/linebender/fearless_simd (accessed on 11.090.2025)], a SIMD abstraction library that exposes abstract vector types such as `f32x4` or `u8x32` as well as functions for arithmetic operations and calls the appropriate SIMD intrinsics behind the scenes. At the time of writing, support is limited to NEON, WASM SIMD and SSE4.2, all of which operate on 128-bit vector types. A fallback level also exists for platforms without SIMD support. Larger vector types (like `u8x32` or `u8x64`) are also supported but will simply be poly-filled using 128-bit intrinsics.

One of the main features of fearless_simd is that it is based on code generation. Writing manual code for all different combinations of arithmetic operators (which often are only distinguished by the different name of the called intrinsic) and vector sizes would be hard to maintain. Because of this, the core logic for generating the intrinsic calls happens in a separate Rust crate using the proc-macro2 #footnote[https://github.com/dtolnay/proc-macro2 (accessed on 11.09.2025)] and quote #footnote[https://github.com/dtolnay/quote (accessed on 11.09.2025)] crates, and the fearless_simd crate then simply contains the output of the auto-generated code.

At the core of fearless_simd is the `Simd` trait which defines the methods for all possible combinations of vector types and arithmetic (or boolean) operators. A very small selection of these is displayed in @simd-trait. Note in particular how the actual vector types such as `f32x4` are also generic over `Simd`.

#figure(
  ```rs
trait Simd {
  fn add_f32x4(self, a: f32x4<Self>, b: f32x4<Self>) -> f32x4<Self>;
  fn add_f32x8(self, a: f32x8<Self>, b: f32x8<Self>) -> f32x8<Self>;
  fn add_u8x16(self, a: u8x16<Self>, b: u8x16<Self>) -> u8x16<Self>;
  fn sqrt_f32x4(self, a: f32x4<Self>) -> f32x4<Self>;
  fn sub_u16x8(self, a: u16x8<Self>, b: u16x8<Self>) -> u16x8<Self>;
}
  ```,
  caption: [A selection of functions defined by the `Simd` trait.],
) <simd-trait>

The different available SIMD levels are then represented as zero-sized types that implement the functions for the given architecture. In order to prevent the user from arbitrarily creating levels on platforms that do not support it, the types contain an empty private field so that they can only be constructed from within the crate, where an instance of the struct will only be returned at runtime if the current system supports the given capabilities.

An example of the implementation of the `Simd` trait can be seen in @simd-trait-impl. For `Fallback`, we use normal scalar arithmetic to implement the addition of two floating point numbers, while for `Neon` we make a call to the `vaddq_f32` intrinsic.

#figure(
  ```rs
pub struct Fallback {
    _private: (),
}

impl Simd for Fallback {
    #[inline(always)]
    fn add_f32x4(self, a: f32x4<Self>, b: f32x4<Self>) -> f32x4<Self> {
        [
            f32::add(a[0usize], &b[0usize]),
            f32::add(a[1usize], &b[1usize]),
            f32::add(a[2usize], &b[2usize]),
            f32::add(a[3usize], &b[3usize]),
        ]
            .simd_into(self)
    }
}

pub struct Neon {
    _private: (),
}

impl Simd for Neon {
    #[inline(always)]
    fn add_f32x4(self, a: f32x4<Self>, b: f32x4<Self>) -> f32x4<Self> {
        unsafe { vaddq_f32(a.into(), b.into()).simd_into(self) }
    }
}
  ```,
  caption: [Example implementations of the SIMD trait for `Fallback` and `Neon`.],
) <simd-trait-impl>

Using these capabilities, we can define the main functions in Vello CPU to be generic over the `Simd` trait, which allows us to implement them in a platform-agnostic way while still leveraging SIMD capabilities.

=== Implementation
Certain parts of the pipeline (such as coarse rasterization) are not obviously SIMD-optimizable and would only benefit very little from it, if at all. However, the main stages are fortunately very much amenable to such optimizations and profit vastly from it. A major focus of this work was therefore rewriting the existing parts of the pipeline to make use of SIMD capabilities. At the time of writing, the flattening, strips generation, fine rasterization as well as packing stages are SIMD-optimized. The last remaining candidate that could _potentially_ profit from such optimizations would be stroke expansion, but this has not been implemented yet.

For the flattening stage, the SIMD optimization only applies to cubic curves. As was explained in @flattening, cubic curves are flattened by first approximating them by multiple quadratic curves and then flattening each quadratic curve. What we therefore do is first compute the number of necessary quadratic curves and then flatten multiple quadratic curves _in parallel_ by using vectors to store the intermediate results of each curve at the same time. Our benchmarks confirmed that this has a noticeably positive impact on performance, as the original implementation of flattening on Kurbo was written in a way that makes it hard to auto-vectorize for the compiler, and also operated on `f64` instead of `f32` values.

For strips generation, the vectorization is conceptually also relatively simple. Remember that the bulk of the work in this stage comes from iterating over all 4x4 tiles in a strip, calculating the winding number of each pixel, adding them and then converting them into `u8` opacities. In principle, it would be possible to do this calculation independently for each pixel, but the current implementation uses the winding number of the _left_ pixel as the basis for the area calculation, meaning that horizontally consecutive pixels cannot be processed in parallel. However, there are no dependencies whatsoever in the vertical direction. Since strips always have a fixed height of 4, we can therefore always process a whole column of pixels in parallel. As we are using `f32` to store winding numbers, we can conveniently use 128-bit vector types for this. This does however mean that the current approach cannot currently fully utilize 256-bit or 512-bit vectors. Adding support for bigger vector types is possible in principle, but would require changes to make the calculation of the winding number of a pixel completely independent of its neighbors.

The fine rasterization stage makes it even easier to add such optimizations, as the calculations for compositing and blending pixels are completely independent and have no dependencies to neighboring pixels. Because of this, it would theoretically be possible to use 512-bit vectors for most calculations. For the f32-pipeline, a whole column of pixels could be processed at the same time since a column consists of 4 pixels and each pixel stores four `f32` values for the red, green, blue and alpha channels. Since storing `u8`s only needs one fourth of the space, the u8-pipeline could therefore even process chunks of 4x4 pixels at the same time. However, performing computations with such large vectors has the risk of causing high register pressure on targets that do not support such a large width natively. Therefore, in practice, the current implementation uses 256-bit vector types by default, and switches to 128-bit or 512-bit in certain places if appropriate.

 Finally, the last part that makes use of SIMD optimizations is the packing stage of the u8 pipeline. In @packing, it was explained that one of the main challenges of packing is that we need to "transpose" the pixels from column-major order in the wide tiles to row-major order in the pixmap. The main bottleneck here is first loading and then storing each pixel one at a time. Fortunately, at least some instruction sets have dedicated intrinsics that makes this a lot easier. For example, NEON has the `vld4q_u32` instruction which allows loading 16 `u32` values (in this case, the RGBA values of a single pixel are interpreted as a single `u32` value instead of 4 `u8` values) and interleaving them all in one step. By doing so, we can directly store each vector in the corresponding row in the pixmap. Our benchmarks showed that handling these pixels in bulk using SIMD leads to a more than 3x speedup, so this is a very important optimization.

== Multi-threading <multi-threading>
One core motivation for exploring the sparse strips approach was that we believed it to be compatible with multi-threading, something that is currently only supported by one other mainstream renderer, namely Blend2D. @multi-threading-architecture provides a rough overview of the architecture that enables this rendering mode. In general, path rendering and rasterization run completely in parallel on different threads, while coarse rasterization is still exclusively performed on the main thread, therefore forming the only serial bottleneck in the pipeline.

#figure(
  image("assets/multi_threading_architecture.pdf", width: 90%),
  caption: [An overview of the architecture for multi-threaded rendering.],
) <multi-threading-architecture>

Everything starts with the creation of the `RenderContext` (see @api), where the user can set the number of threads that should be used for rendering. In case it is set to 0, no multi-threading will be activated and the code path for single-threaded rendering will be used. Otherwise, the `RenderContext` will spawn a thread pool containing `num_threads` threads, meaning that including the main thread, there will be `num_threads + 1` active threads. In order to manage the thread pool we use rayon#footnote[https://github.com/rayon-rs/rayon (accessed on 11.09.2025)], a Rust library for data parallelism. 

=== Path rendering
The core insight necessary to understand the first part of multi-threading is that path rendering (ranging from stroke expansion or flattening to strips generation) is essentially a pure function that takes a single path as input and returns a vector of strips as the output. Since there are no other dependencies, the rendering of a single path can be completely outsourced without requiring any additional communication between the main thread and the child thread until the strips have been generated. These stages of the pipeline often take up the largest chunk of time. Being able to run these stages in parallel can therefore lead to considerable speedups.

In practice, the process starts by the user emitting a command like `fill_path` or `stroke_path`, upon which the main thread first stores the command inside of a local queue. The reason for doing this instead of directly sending the command to a thread is that we make use of a batching mechanism to increase the efficiency of the whole process. While multi-threading itself is powerful, a considerable problem is that if the amount of work we farm out to the threads is too small, the overhead that arises from context switches and the bookkeeping done by rayon will be so large that any benefit of parallelism is essentially rendered useless. 

Therefore, the main thread collects multiple drawing commands and keeps track of a counter that tries to estimate the cost of rendering all currently stored paths. Only once a certain threshold is reached does the main thread dispatch the whole batch of render tasks to a thread in the thread pool.

The cost estimation function works in a very simplistic way by considering relevant information about the path, including the number of line and curve segments, the overall length of the path and whether we are performing filling or stroking. While naive, this approach has been empirically validated to work pretty well. With this batching mechanism, if the user for example decides to draw many small rectangles, the main thread will collect dozens of these commands before dispatching them. In contrast, if larger geometries with many curves are drawn, only few of them will be batched before being processed. To enable the communication between the main thread and the worker threads, we use the crossbeam-channel crate #footnote[https://github.com/crossbeam-rs/crossbeam (accessed on 11.09.2025)] that provides primitives for implementing the single-producer multi-consumer paradigm easily.

While path rendering itself can be parallelized in a very straight-forward way, there is a very central issue that needs to be addressed: How do we ensure that the generated strips arrive in the correct order back in the main thread? After all, if the user first draws a red rectangle and then a green one, we need to ensure that they are processed in that very same order during coarse rasterization, otherwise it could appear as if the green rectangle was drawn before the red one.

Two key implementation details make sure that this property is always upheld. Firstly, before dispatching a path rendering task, the main thread assigns a unique ID to the task that is based on an incrementing counter. By doing so, just comparing the IDs of two render tasks is enough to determine which one should be processed first during coarse rasterization. Secondly, in order to send the rendered strips back to the main thread, we use the ordered-channel#footnote[https://gitlab.com/kornelski/ordered-channel (accessed on 11.09.2025)] crate which provides a MPSC (multi-producer single-consumer) _channel_ primitive with the useful property that the receiver will always receive messages with incrementally ascending IDs. 

Assume for example that thread 1 sends the generated strips of path 1 via the channel, and subsequently thread 2 sends the strips for path 2. In this case, the main thread can just receive the results normally and use them during coarse rasterization. However, assume that now thread 3 sends the data for path 5 and thread 2 sends the data for path 4, while path 3 is still being processed in thread 1. In this case, the main thread will not receive any messages until thread 1 is done, after which the main thread will receive the messages with ID 3, 4 and 5, in that order. This makes it possible to prevent bugs caused by the indeterministic nature of multi-threading.

=== Coarse rasterization
As was mentioned previously, coarse rasterization is currently the only part of the pipeline that runs strictly sequentially, the reason being that it is not trivially parallelizable. In the multi-threaded setup, each time after processing a `fill_path` or `stroke_path` command, the main thread first sends the batched render tasks and then checks the queue for any already-existing strips that can be processed for coarse rasterization.

An important detail to mention is that due to the fact that we are processing strips asynchronously, it could happen that the user makes a call to `render_to_pixmap` before all strips have been generated, which would be fatal because unprocessed rendering tasks would then simply not be drawn at all. Because of this, as was demonstrated in @api_example_Listing, before starting fine rasterization, the user first has to call `flush`, which will block the main thread until coarse rasterization has completed for all paths.

=== Rasterization
The final part of the pipeline consists of fine rasterization and packing, which is trivial to parallelize. Remember that after coarse rasterization, our drawing commands are distributed over many wide tiles with the dimension of 256x4 pixels which can all be processed independently from each other. Therefore, each wide tile can easily be processed at the same time by different threads without worrying about any data dependencies. In our implementation, this is achieved with a call to the rayon-provided method `par_iter_mut` while iterating over the wide tiles. The main difficulty arises once we reach the packing stage, as every thread will need mutable access to the user-provided `Pixmap`, which cannot easily be shared across the thread boundary due to the constraints imposed by the Rust compiler, even though doing so would be safe because wide tiles are guaranteed to not overlap each other, ensuring that no memory location is updated simultaneously from two threads. One way of solving this would be to simply use `unsafe` code to work around that restriction. However, we decided to circumvent this issue by instead building a custom _Regions_ abstraction that chops up the whole pixmap into many small mutable slices using the `split_at_mut` method, making it possible to write to distinct parts of the pixmap at the same time.
