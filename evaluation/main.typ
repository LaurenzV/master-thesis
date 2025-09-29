= Evaluation <evaluation>

Even when doing 2D rendering on the CPU instead of the GPU, having good performance is still crucial. In this section, we will analyze how Vello CPU fares in comparison to other prominent 2D renderers by evaluating its performance using the Blend2D benchmark suite @blend2d_perf. 

== Introduction
The main idea behind the benchmark harness is to run various rendering operations that exercise different parts of the rendering pipeline to varying degrees, measure the time and compare the results. Doing so allows us to easily determine both the strengths and weaknesses of each renderer. To achieve this, the harness defines a number of different parameters that can be tweaked to specify what exactly should be rendered. The configuration possibilities are visualized in @bench-types.

#[
 #let entry(title, im) = {
   block(breakable: false)[
     #align(center)[
     #stack(dir: ttb, spacing: 0.2cm, text(1.0em)[#title], if (im != none) {image("assets/" + im + ".svg", width: 90%)} else {})
   ]
   ]
 }

 #let section(title, entries) = {
   block(width: 100%, stroke: (paint: blue, thickness: 1pt, dash: "dashed"), inset: 0.2cm)[
     #align(center)[
     #text(1.6em)[#title]
     #v(-0.4cm)
     #grid(
      columns: (1fr,) * 6,
      row-gutter: 0.5cm,
      column-gutter: 0.3cm,
      ..entries
    )
   ]]
 }


#figure([
 #section("Draw mode", (
   entry("", none),
   entry("", none),
   entry("Fill", "rect_filled"),
   entry("Stroke", "rect_stroked"),
 ))
  
  #section("Shape", (
    entry("Rect A.", "rect_aligned"),
    entry("Rect U.", "rect_unaligned"),
    entry("Rect Rot.", "rect_rotated"),
    entry("Rect Round", "rect_round_unaligned"),
    entry("Triangle", "triangle"),
    entry("Poly 10", "poly_10_nz"),
    entry("Poly 20", "poly_20_nz"),
    entry("Poly 40", "poly_40_nz"),
    entry("Butterfly", "butterfly"),
    entry("World", "world"),
    entry("Fish", "fish"),
    entry("Dragon", "dragon"),
))

#section("Paint", (
    entry("Solid", "rect_solid"),
    entry("Linear G.", "rect_linear"),
    entry("Radial G.", "rect_radial"),
    entry("Sweep G.", "rect_sweep"),
    entry("Image NN", "rect_low"),
    entry("Image BI", "rect_medium"),
 ))

 #section("Size", (
    entry("8x8", "rect_8"),
    entry("16x6", "rect_16"),
    entry("32x32", "rect_32"),
    entry("64x64", "rect_64"),
    entry("128x128", "rect_128"),
    entry("256x256", "rect_256"),
 ))
], caption: [The four different configurable parameters of the benchmarking harness.]) <bench-types>
] 

The first configurable knob is the _draw mode_, which should be relatively self-explanatory. Choosing _fill_ will help us measure the performance of filling shapes, while choosing _stroke_ instead will tell us how performant stroking (in particular stroke expansion) is.

Next, we can configure the actual _shape_ that is drawn, which yet again impacts which part of the pipeline will be mainly exercised:
- *Rect A.*: Rectangles aligned to the pixel boundary. This is the most basic kind of shape you can draw and most renderers usually have a fast path for them.
- *Rect U.*: Unaligned rectangles. The same as Rect A., but the rectangles are not aligned to the pixel boundary and thus require anti-aliasing. 
- *Rect Rot.*: Rotated rectangles. They are harder to special-case and the test case therefore demonstrates how well the renderer can rasterize simple line-based shapes.
- *Rect Round*: Rectangles with rounded corners. The reason these are worth benchmarking is that rounded rectangles are very common in graphical user interfaces and should therefore be fast to render.
- *Triangle*: Triangles. They represent the most basic form of a polygon.
- *Poly N*: N-vertex polygons. These shapes consist of many self-intersecting lines and are useful to determine the performance of anti-aliasing calculations.
- *Butterfly*, *Fish*, *Dragon*: These shapes contain many curve segments, making them good candidates for evaluating curve flattening performance.
- *World*: This shape consists of just small line segments and aims to measure how effectively the renderer can rasterize a complex shape.

Specifying the paint allows us to see how fast the renderer can process gradients and image fills. And finally, tweaking the size of the shape shows us how runtime scales as the dimension of the shape increases. As will be shown below, having all these different configurations is really useful as most renderers do have strengths and weaknesses in different areas.

== Setup
In the interest of covering both the x86 and AArch64 architectures, we ran the benchmarks on two different machines. The first machine is a MacBook using the M1 Pro chip with 8 cores (6 performance cores and 2 efficiency cores) and 16GB of RAM. The second machine uses an Intel Core i9-14900K (8 performance cores and 16 efficiency cores) and runs on 64GB of RAM. Since the main focus of this work was optimizing the renderer using NEON SIMD intrinsics, we will only present the results of the M1 machine here. In addition, due to space reasons, we will not exhaustively list the measurements for all possible configurations but pick a small representative selection of tests that highlight the strengths but also weaknesses of Vello CPU. The full results for both architectures and all configurations are made available online #footnote[https://laurenzv.github.io/vello_chart/ (accessed on 11.09.2025)].

The original benchmark harness is written in C++ and covers the following selection of renderers:
- Blend2D#footnote[https://blend2d.com (accessed on 22.09.2025)], a highly performant 2D renderer based on just-time-compilation that also supports multi-threading.
- Skia#footnote[https://skia.org (accessed on 22.09.2025)], the 2D renderer maintained by Google. Only the CPU-based pipeline is tested here.
- Cairo#footnote[https://www.cairographics.org (accessed on 22.09.2025)], a relatively old but still widely used 2D renderer.
- AGG (Anti-Grain Geometry)#footnote[https://agg.sourceforge.net/antigrain.com/index.html (accessed on 22.09.2025)], yet another prominent 2D renderer written in C++.
- JUCE#footnote[https://juce.com (accessed on 22.09.2025)], the renderer that is shipped as part of the C++-based JUCE application framework.
- Qt6#footnote[https://www.qt.io/product/qt6 (accessed on 22.09.2025)], the renderer that is shipped as part of the Qt application framework.
- CoreGraphics#footnote[https://developer.apple.com/documentation/coregraphics (accessed on 22.09.2025)], the graphics framework that is shipped as part of Mac OS.

We decided to exclude Qt6 and CoreGraphics from our benchmarks since they turned out to be very slow in many cases and made visualizations harder.

Since Vello CPU is a Rust-based renderer, we had to create C bindings#footnote[https://github.com/LaurenzV/vello_cpu_c (accessed on 22.09.2025)] to properly integrate it into the harness. We also decided that another intriguing research question was how Vello CPU compares against other Rust-based CPU renderers in particular, as none were included in the original benchmarking harness. To this end, we also created C bindings#footnote[https://github.com/LaurenzV/tiny_skia_c (accessed on 22.09.2025)]#footnote[https://github.com/LaurenzV/raqote_c (accessed on 22.09.2025)] for tiny-skia#footnote[https://github.com/linebender/tiny-skia (accessed on 22.09.2025)] and raqote#footnote[https://github.com/jrmuizel/raqote (accessed on 22.09.2025)], the two currently most commonly used CPU renderers in the Rust ecosystem. tiny-skia is more or less a direct port of a small subset of Skia to Rust, while raqote is a from-scratch implementation that still borrows many ideas from Skia. To make the comparison fair, all crates have been compiled with the flag `target-feature=+avx2` on x86 so that the compiler can make use of AVX2 instructions. On ARM, no additional flags were necessary since the compiler can assume that NEON intrinsics are available by default. 

The operational semantics of the benchmark suite are very simple. Each test will be rendered to a 512x600 pixmap. When starting a test, the harness will enumerate all possible configurations and make repeated calls to render the shape with the given settings. In order to prevent caching, each render call introduces some randomness by for example varying the used colors and opacities or by rendering the shape in different locations on the canvas. The harness will perform multiple such render calls and use the measured time to extrapolate how many render calls can be made in 1 millisecond using that specific configuration. To reduce the impact of outliers, we repeat this process ten times for each test and always choose the best result.

In the following, we will show plots that display the benchmark results for a select number of configurations. For each configuration, we show the results of the given test across all shape sizes to make it easy to see the scaling behavior. It is important to note that for easier visualization, the *time axis is always log-scaled*, which has the side effect that large differences in rendering times are visually not as pronounced and can only be noticed by looking at the individual time measurements. For multi-threaded rendering, we also show the speedup factor in comparison to single-threaded rendering.

== Single-threaded rendering
=== Filling
We begin the analysis by looking at single-threaded rendering and considering the simplest test case, filling a pixel-aligned rectangle with a solid color. The results are visualized in @solid-fill-recta. There are two points worth highlighting in this figure as they represent a trend that, as will be shown soon, applies to most test cases. 

#figure(
  image("assets/st_fill_Solid_RectA.pdf"),
  caption: [The running times for the test "Fill - Solid - RectA".]
) <solid-fill-recta>

First, it is apparent that Blend2D is the clear winner in this specific benchmark. Regardless of whether we are considering small or larger shape sizes, Blend2D consistently needs the shortest time, both compared to the C++-based as well as the Rust-based renderers and Vello CPU. As will be visible in other plots, this does not just apply to that specific test configuration but to nearly all other configurations as well, confirming the fact that the JIT-based architecture and painstaking optimizations that have been applied to Blend2D over the course of the years have their merit. Given this, for the remainder of this subsection we will mostly focus on comparing Vello CPU to the other renderers and shift our focus back to Blend2D when analyzing multi-threaded rendering.

Secondly, another trend that will become more apparent soon is that Vello CPU seems to have a general weakness for small shape sizes, but apart from Blend2D it is the only other renderer that shows excellent scaling behavior as the shape size increases. For 8x8 and 16x16, AGG and JUCE are faster in this specific benchmark, but that difference is reversed when considering 128x128 and 256x256. 

We believe this behavior can easily be explained by considering how sparse strips work. Since the minimum tile size is 4x4, in case we are drawing small geometries there is a high chance that the whole geometry will be represented exclusively by strips instead of sparse fill regions, which are more expensive to process. In addition to that, the fixed tile size has the consequence that many pixels that are actually not covered by the shape are still included and incur costs during anti-aliasing calculations and rasterization, which can represent a significant overhead given the small size of the shape. On the other hand, thanks to sparse strips, the larger the geometry, the more likely it is that it can be represented by large sparse fill regions, which are comparatively cheap to process. Other renderers do not necessarily make use of such an implicit representation and therefore exhibit worse scaling behavior.

Another reason that Vello CPU performs slightly worse in this particular case is that we decided to not include a special-case path for pixel-aligned rectangles, which becomes apparent when contrasting the results to @solid-fill-rectu, where unaligned rectangles are drawn. In that figure, the results for Vello CPU more or less stay the same, while for example JUCE and AGG show worse performance. Overall, it still seems safe to draw the conclusion that Vello CPU lands a second place for those two configurations.

#figure(
  image("assets/st_fill_Solid_RectU.pdf"),
  caption: [The running times for the test "Fill - Solid - RectU".]
) <solid-fill-rectu>

Next, we want to analyze the performance of general edge rasterization by considering the "PolyNZi40" test case in @solid-fill-polynz40. As can be seen, this is another area where Vello CPU shines: While the gap to Blend2D is larger for small sizes, it becomes much closer for larger sizes. In particular, note how Vello CPU is significantly faster than any of the other renderers, both for smaller sizes and especially for larger sizes. It is difficult to grasp why exactly the other renderers are performing worse here, but it is possible to hypothesize. For example, remember that Raqote uses an "active" edge list to keep track of the active edges per scan-line. This means that each time the renderer moves to a new scan-line, it needs to do much more work to discard, add and sort the edges, resulting in additional overhead for every pixel row that is analyzed. On the other hand, in Vello CPU adding more lines simply means adding another set of tiles that we need to perform anti-aliasing for, but it has no impact on the processing times of the other tiles.

#figure(
  image("assets/st_fill_Solid_PolyNZi40.pdf"),
  caption: [The running times for the test "Fill - Solid - PolyNZi40".]
) <solid-fill-polynz40>

Let us shift our focus to @solid-fill-fish next, which forms the main exception to our previous statement that Vello CPU has a weakness for small shapes and actually ends up beating Blend2D for certain sizes. The reason that Vello CPU performs so well here is that we implemented a clever optimization during curve flattening which seemingly has not been embraced by other renderers: Before performing curve flattening, we first consider the start and end points as well as control points of the curve. In case the points are so close together that the curve cannot possibly exceed the flattening threshold (in our case 0.25), we simply approximate it by a single line segment instead of running the much more computationally intensive flattening algorithm (which will most likely only yield a single line segment, anyway). As can be seen in the figure, having this shortcut path leads to impressive gains if the shape consists of many small curve segments.

#figure(
  image("assets/st_fill_Solid_Fish.pdf"),
  caption: [The running times for the test "Fill - Solid - Fish".]
) <solid-fill-fish>

Let us consider @solid-fill-world, where the weakness for smaller geometry sizes becomes more apparent: At the smallest size, Vello CPU is more than twice as slow as Skia and raqote, with the inflection point only arriving at the size 64x64, at which point Vello CPU once again exhibits much better scaling behavior. When looking at the performance profile for the 8x8 case in @solid-fill-world-profile, over 85% of the time is spent in the path rasterization stage during tile generation, sorting as well as strip generation. Thinking about this in more detail, the possible problem becomes apparent. The "World" test case consists of a shape with a very large amount of lines. Even when the shape is scaled down to 8x8, we still end up generating a 4x4 tile for each single line and computing the winding numbers for all 16 pixels, even though only a small part is really covered. The problem could be slightly ameliorated by relaxing the restriction on the width of strips (see @conclusion), but this will still not reduce the number of generated tiles that need to be sorted, which takes up a significant chunk of the time. 

#figure(
  image("assets/st_fill_Solid_World.pdf"),
  caption: [The running times for the test "Fill - Solid - World". ]
) <solid-fill-world>

#figure(
  image("assets/profile_fill_world_8x8.pdf", width: 60%),
  caption: [The percentage of the total runtime each step in the pipeline takes for the test case "Fill - Solid - World" with shape size 8x8. Note that the shape does not contain any curve segments. Therefore the "flattening" part mostly represents the overhead from iterating over all lines and re-emitting them.]
) <solid-fill-world-profile>

There does not seem to be a straightforward solution to the problem. One approach could be introducing a kind of "line-merging" stage where multiple small lines are merged into larger ones at the cost of some precision, but this seems to be a rather complicated optimization. Otherwise, it might also be worth investigating faster sorting algorithms specialized for a large number of tiles, but the potential for gains here does not seem that significant either.

=== Stroking
Let us devote our attention to stroking next. There are two cases that are worth exploring: Stroking of straight lines and stroking of curves. For lines, we can consider the "World" shape again as it is depicted in @solid-stroke-world. As can be seen, Blend2D once again by far leads the score, but is followed second by Vello CPU, which (together with JUCE) leads with another significant gap compared to the remaining renderers. There is also an interesting behavior where different renderers react differently to different sizes: Raqote seems to deal worse with small shapes but better with larger ones, while for other renderers the sweet spot is somewhere in the middle. Determining the exact reason for these discrepancies appears difficult, but the observation highlights the fact that different renderers use different algorithms for stroking.

#figure(
  image("assets/st_stroke_Solid_World.pdf"),
  caption: [The running times for the test "Stroke - Solid - World".]
) <solid-stroke-world>

In @solid-stroke-butterfly, we can see the running times when stroking a curved shape instead. We once again observe that in this particular case, Vello CPU does not perform as well as other renderers for small shape sizes, but makes up for the differences as the dimensions of the shape increase. In this case, we do not attribute the sluggish performance for small shape sizes to the fixed size of 4x4 for a tile. A look at the profile in @solid-stroke-butterfly-profile reveals that more than 70% of the time is spent in stroke expansion, leading us to the conclusion that there seems to be some inefficiency in the current algorithm. The exact reason for this issue remains to be determined, however.

#figure(
image("assets/st_stroke_Solid_Butterfly.pdf"),
  caption: [The running times for the test "Stroke - Solid - Butterfly".]
) <solid-stroke-butterfly>

#figure(
  image("assets/profile_stroke_butterfly_8x8.pdf", width: 60%),
  caption: [The percentage of the total runtime each step in the pipeline takes for the test case "Stroke - Solid - Butterfly" with shape size 8x8. Stroke expansion represents the main bottleneck.]
) <solid-stroke-butterfly-profile>

Overall, we draw the conclusion that while there is more work left to be done on the stroking side of things, performance is at least comparable to other renderers and stands out when considering larger shape sizes.

=== Paints
Finally, let us analyze the performance of Vello CPU when complex paints such as linear gradients (in @linear-fill-recta) and images (in @pattern-fill-recta) are used.

#figure(
image("assets/st_fill_Linear_RectA.pdf"),
  caption: [The running times for the test "Fill - Linear - RectA".]
) <linear-fill-recta>

#figure(
image("assets/st_fill_Pattern_NN_RectA.pdf"),
  caption: [The running times for the test "Fill - Pattern_NN - RectA".]
) <pattern-fill-recta>

As is visible in @linear-fill-recta figure, Vello CPU has a significant overhead when rendering a gradient with a small shape but has outstanding performance for larger ones. The reason for this can be explained as follows. There are two general approaches for how to deal with gradients: The first method is to precompute a lookup table with a fixed resolution and then sample from that table, as is done in Vello CPU. The second method (for example used by tiny-skia and therefore most likely also Skia) is to do no pre-computation at all but instead do the color interpolation on the pixel-level. The disadvantage of the former method is that computing a LUT of this size is more time-consuming if the shape we will draw only covers very few pixels, but the advantage is that it exhibits much better scaling behavior as the size of the shape grows, as can be seen in the benchmark. It should be noted though that Blend2D also uses the LUT approach and still has the best runtime for 8x8, suggesting that there are probably ways of improving the computation in Vello CPU as well.

For image fills, we see that Vello CPU is not doing particularly well, but performance is not bad either and matches most of the other renderers. A particular problem that we are facing is that for nearest-neighbor rendering of images, the performance is largely determined by how fast a pixel can be sampled from the original image. Since memory safety is at the core of Rust, each access to a memory location is preceded by a bounds-check, which has been shown to lead to a significant slowdown. We could have resorted to using unsafe code to circumvent this, but in the end decided that it was not worth it to potentially introduce memory-safety issues by doing so.

== Multi-threaded rendering
Next, we want to more closely analyze Vello CPU's multi-threaded rendering performance. Since Blend2D is the only other renderer that supports such a mode, we will use this as the main reference point for comparison, putting a particular emphasis on analyzing the speedup that is achieved with different thread counts. Before diving into the analysis, it is important to make a remark about the difference between how threads are counted in both renderers that makes it hard to do a completely fair comparison. In Blend2D, the main thread will also be used as a worker thread. This means that if a test case is indicated to run with eight threads, Blend2D will use the main thread as well as seven additional worker threads for rendering. In Vello CPU, it is not possible to use that same principle as the main thread is always only responsible for distributing work and doing coarse rasterization and cannot be used for path rendering and fine rasterization. Therefore, if a test case is indicated to run with two threads, there will actually be three threads in total: One main thread and two worker threads. Because of this, a direct comparison of the results of the two renderers with a low thread count should be done with care, as the results might be slightly biased towards Vello CPU. With that said, the main purpose of this section is to analyze the scaling behavior as the core count increases, where this difference in behavior becomes irrelevant with higher thread count, especially since our machine only has 8 cores in total.

As will be seen shortly, both renderers can give remarkable performance boosts depending on the exact configuration but are far away from achieving completely linear speedup relative to the thread count (at least a partial explanation for this is that the machine has two efficiency cores). Blend2D seems to overall have the more "well-rounded" multi-threading mode, achieving decent speedup even for simple paths where Vello CPU has some shortcomings. On the other hand, Vello CPU's approach to multi-threading seems to lead to higher speedups as the processing time per path increases.

#figure(
image("assets/mt_fill_Solid_RectA.pdf"),
  caption: [The running times for the test "Fill - Solid - RectA".]
) <mt-solid-fill-recta>

We begin our analysis by once again considering the simplest case of drawing simple rectangles in @mt-solid-fill-recta. A pattern that will also become evident in other benchmarks is that the speedup for smaller shapes is usually smaller than for larger ones. The reason for this is that the needed processing time for handling small paths is so small that any speedup is eclipsed by the overhead that comes from using multi-threading. As the size of the rectangle increases, more rasterization work needs to be performed, which implies a longer processing time and therefore better utilization of different threads. A performance analysis of Vello CPU using a profiler confirms the fact that for 8x8, the majority of the time in each thread is spent on yielding and overhead that arises from the communication. For 256x256, the speedup reaches 3.4 but is still below Blend2D's speedup of 4.7x. Profiling revealed that the main bottleneck seems to be coarse rasterization. In general, coarse rasterization consumes very little time, but since this is the only part of the pipeline that is currently not parallelized, it does become more significant as the number of threads increases. We therefore consider researching ways to lift this limitation important future work (see @conclusion).

#figure(
image("assets/mt_fill_Solid_PolyNZi40.pdf"),
  caption: [The running times for the test "Fill - Solid - PoltNZi40".]
) <mt-solid-fill-polynz40>

As can be seen in @mt-solid-fill-polynz40, things improve as the complexity of the path increases. In the given figure, we only consider line-based shapes, meaning that the most time-consuming step is strip generation, but as can be seen we already achieve much higher speedups in this test case. For small shapes, we are still restricted to a speedup of less than two to three (note in particular how the speedup actually gets worse when using eight threads), but for larger versions of the shape, the speedup gets increasingly better.

Similarly high speedups are achieved once curve segments or strokes are thrown into the mix, as can be observed in @mt-solid-fill-fish. Blend2D and Vello CPU achieve similar speedups when only using two threads, but when increasing that number two four or eight threads, Vello CPU seems to be at an advantage.

#figure(
image("assets/mt_fill_Solid_Fish.pdf"),
  caption: [The running times for the test "Fill - Solid - Fish".]
) <mt-solid-fill-fish>

Finally, it is important to remember that the second component that can be parallelized in the pipeline concerns fine rasterization, which can become a bottleneck when drawing shapes with complex paints. As can be seen in @mt-linear-fill-recta, there does not seem to be a clear winner when comparing Blend2D and Vello CPU. Blend2D seems to achieve higher speedups for the 256x256 case, while Vello CPU scales better for smaller sizes (for unknown reasons, Blend2D actually experiences a slowdown for very small sizes). It is surprising to us that the speedup for Vello CPU is only limited to 4.1, as the bottleneck for this test case is fine rasterization, which conceptually is much easier to parallelize since each wide tile can be processed completely independently.

#figure(
image("assets/mt_fill_Linear_RectA.pdf"),
  caption: [The running times for the test "Fill - Linear - RectA".]
) <mt-linear-fill-recta>

We conclude that both renderers have powerful multi-threading capabilities but with different strengths and weaknesses. As was shown, there is no clear "winner" in most benchmarks. Sometimes, Blend2D achieves better scaling with smaller shapes but not with larger ones, but sometimes, it is the other way around. We believe that Vello CPU could achieve even higher speedups if a way is found to eliminate the coarse rasterization bottleneck, although that remains to be empirically validated as part of the future work.
