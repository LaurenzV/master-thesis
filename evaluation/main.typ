= Evaluation <evaluation>

Even when doing 2D rendering on the CPU instead of the GPU, having good performance is still very crucial. In this section, we will analyze how Vello CPU fares in comparison to other prominent 2D renderers by evaluating its performance using the Blend2D benchmark suite @blend2d_perf. 

== Introduction
The main idea behind the benchmark harness is to feed various inputs to the renderer exercising different parts of the rendering pipeline, measure the time and finally compare the results with other renderers. Doing so allows to easily determine both the strengths and weaknesses of each renderer. To achieve this, the harness defines a number of different "knobs" that can be tweaked to specify what exactly should be rendered. The configuration possibilities are visualized in @bench-types.

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
], caption: [The four different configurable knobs of the benchmarking harness.], placement: auto) <bench-types>
] 

The first knob is the _draw mode_, which should be relatively self-explanatory. Choosing *fill* will help us measure the performance of filling shapes, while choosing *stroke* instead will tell us how performant stroking (in particular stroke expansion) is.

Next, we can configure the actual _shape_ that is drawn, which yet again impacts which part of the pipeline we are mainly exercising:
- *Rect A.*: Rectangles aligned to the pixel boundary. This is the most basic kind of shape you can draw and most renderers usually contain a fast path for them.
- *Rect U.*: Unaligned rectangles. The same as Rect A., but the rectangles are not aligned to the pixel boundary and thus require anti-aliasing. 
- *Rect Rot.*: Rotated rectangles. They are not that easy to special-case and the test case therefore demonstrates how well the renderer can rasterize simple line-based shapes.
- *Rect Round*: Rectangles with rounded corners. The reason these are worth benchmarking specifically is that rounded rectangles are very common in graphical user interfaces and having fast paths for rendering those specifically can therefore be worth it.
- *Triangle*: Triangles. They represent the most basic form of a polygon.
- *Poly N*: N-vertex polygons. These shapes consist of many self-intersecting lines and are useful to determine the performance of anti-aliasing calculations.
- *Butterfly*, *Fish*, *Dragon*: These shapes contain many curve segments, making them good candidates for evaluating curve flattening performance.
- *World*: This shape consists just of line segments and aims to measure how effectively the renderer can rasterize a complex shape.

Specifying the paint allows us to see how fast the renderer is at filling areas with the previously-mentioned complex paints. And finally, tweaking the size of the shape shows us how runtime scales as the dimension of the shape increases. As will be shown soon, having all these different configurations is really useful as most renderers indeed have strengths and weaknesses in different areas.

== Setup
In the interest of covering both the x86 and AArch64 architectures, we ran the benchmarks on two different machines. The first machine is a MacBook using the M1 Pro chip with 8 cores (6 performance cores and 2 efficiency cores) and 16GB of RAM. The second machine uses an Intel Core i9-14900K (8 performance cores and 16 efficiency cores) and runs on 64GB of RAM. Since the main focus of this work was optimizing the renderer using NEON SIMD intrinsics, we will only present the results of the M1 machine here. In addition, due to space reasons we will not exhaustively list the measurements for all possible configurations but pick a small representative selection of tests that highlight the strengths but also weaknesses of Vello CPU. The full results for both architectures and all configurations are available online #footnote[https://laurenzv.github.io/vello_chart/].

The original benchmark harness#footnote[https://github.com/blend2d/blend2d-apps] is written in C++ and covers the following selection of renderers:
- Blend2D, a highly performant 2D renderer based on just-time-compilation that also supports multi-threading.
- Skia, the 2D renderer maintained by Google. Only the CPU-based pipeline is used.
- Cairo, a relatively old but still widely used 2D renderer.
- AGG (Anti-Grain Geometry), yet another 2D renderer written in C++.
- JUCE, the renderer that is shipped as part of the C++-based JUCE application framework.
- Qt6, the renderer that is shipped as part of the Qt application framework.
- CoreGraphics, the graphics framework that is shipped as part of MacOS.

We decided to exclude Qt6 and CoreGraphics from our benchmarks since they turned out to be very slow in many cases and made visualizations harder.

Since Vello CPU is a Rust-based renderer, we had to create C bindings#footnote[https://github.com/LaurenzV/vello_cpu_c] to properly integrate it into the harness. We also decided that another intriguing research question was how Vello CPU compares against other Rust-based CPU renderers in particular. To this end, we also created C bindings#footnote[https://github.com/LaurenzV/raqote_c]#footnote[https://github.com/LaurenzV/tiny_skia_c] for `tiny-skia`#footnote[https://github.com/linebender/tiny-skia] and `raqote`#footnote[https://github.com/jrmuizel/raqote], the two currently most commonly used renderers in the Rust ecosystem. To make the comparison fair, all crates have been compiled with the flag `target-feature=+avx2` so that the compiler can make use of AVX2 instructions. On ARM, no additional flags were necessary since the compiler can assume that NEON intrinsics are available by default. 

The operational semantics of the benchmark suite are very simple. Each test will be rendered to a 512x600 pixmap. When starting a test, the harness will enumerate all possible configurations and make repeated calls to render the shape with the given settings. In order to prevent caching, each render call introduces a specific degree of randomness by for example varying the used colors and opacities or by rendering the shape in different locations on the canvas. The harness will perform multiple such render calls and use the measured time to extrapolate how many render calls can be made in 1 millisecond using that specific configuration. To prevent outliers, we repeat this process ten times for each test and renderer and always choose the best result.

In the following, we will show plots that display the benchmark results for a select number of configurations. For each configuration, we show the results of the given test across all shape sizes to make it easy to see the scaling behavior. It is important to note that for easier visualization, the *time axis is always log-scaled* which has the consequence that large differences in rendering times are visually not as pronounced and can only be noticed by looking at the individual time measurements.

== Single-threaded rendering
We begin the analysis by looking at single-threaded rendering and considering the simplest test case, filling a pixel-aligned rectangle with a solid color. The results are visualized in @solid-fill-recta. There are two points worth highlighting in this figure as they represent a trend that, as will be shown soon, apply to nearly all of the test cases. 

#figure(
  image("assets/plot_fill_Solid_RectA.pdf"),
  placement: auto,
  caption: [The running times for the test "Fill - Solid - RectA".]
) <solid-fill-recta>

First, it is apparent that Blend2D is the clear winner in this specific benchmark. Regardless of whether we are considering small or larger shape sizes, Blend2D consistently needs the shortest time, both compared to the C++-based as well as the Rust-based renderers and Vello CPU. As will be visible in other plots, this does not just apply to that specific test configuration but to nearly all other configurations as well, confirming the fact that the JIT-based architecture and painstaking optimizations that have been applied to Blend2D over the course of the years have their merit. Given this, for the remainder of this subsection we will mostly focus on comparing Vello CPU to the other renderers and shift our focus back to Blend2D when analyzing multi-threaded rendering.

Secondly, another trend that will become more apparent soon is that Vello CPU seems to have a general weakness for small shape sizes, but similarly to Blend2D shows excellent scaling behavior as the shape size increases. For 8x8 and 16x16, AGG and JUCE are faster when rendering pixel-aligned rectangles, but that difference is completely reversed when considering 128x128 and 256x256. We believe this behavior can easily be explained by considering how sparse strips work. Since the minimum tile size is 4x4, in case we are drawing small geometries there is a very high chance that the whole geometry is represented by strips instead of sparse fill regions. In addition to that, the fixed tile size has the consequence that many pixels that are actually no covered by the shape are still included and incur costs during anti-aliasing calculations and rasterization, which can represent a significant overhead in the overall small per-shape workload. On the other hand, thanks to the architecture, the larger the geometry the more likely it is that it can be represented by large sparse fill regions, which are relatively cheap to process. Other rendering architectures do not make use of such an implicit representation and therefore exhibit worse scaling behavior.

#figure(
  image("assets/plot_fill_Solid_RectU.pdf"),
  placement: auto,
  caption: [The running times for the test "Fill - Solid - RectU".]
) <solid-fill-rectu>