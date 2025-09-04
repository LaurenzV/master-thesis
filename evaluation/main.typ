= Evaluation <evaluation>

Even when doing 2D rendering on the CPU instead of the GPU, having good performance is still very crucial. In this section, we will analyze how Vello CPU fares in comparison to other prominent 2D renderers by evaluating its performance using the Blend2D benchmark suite @blend2d_perf. 

== Introduction
The main idea behind the benchmark harness is to provide various inputs to the renderer exercising different parts of the rendering pipeline, measure the time and compare the results with other renderers. Doing so allows to easily determine both the strengths and weaknesses of each renderer. To achieve this, the harness defines a number of different "knobs" that can be tweaked to specify what exactly should be rendered. The configuration possibilities are visualized in @bench-types.

#[
 #let entry(title, im) = {
   block(breakable: false)[
     #align(center)[
     #stack(dir: ttb, spacing: 0.2cm, text(1.0em)[#title], if (im != none) {image("assets/" + im + ".svg")} else {})
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
], caption: [The four different configurable knobs of the harness.], placement: auto) <bench-types>
] 

The first knob is the _draw mode_, which should be relatively self-explanatory. Choosing *fill* will help us measure the performance of filling basic shapes, while choosing *stroke* instead will tell us how performant stroke expansion is.

Next, we can configure the actual _shape_ that is drawn, which yet again impacts which part of the pipeline we are exercising:
- *Rect A.*: Rectangles aligned to the pixel boundary. This is the most basic kind of shape you can draw and most renderers usually contain a fast path for them.
- *Rect U.*: Unaligned rectangles. The same as Rect A., but the rectangles are not aligned to the pixel boundary and thus require anti-aliasing. 
- *Rect Rot.*: Rotated rectangles. They are not that easy to special-case and the test case therefore demonstrates how well the renderer can rasterize simple line-based shapes.
- *Rect Round*: Rectangles with rounded corners. The reason these are worth benchmarking specifically is that rounded rectangles are very common in graphical user interfaces and having fast paths for rendering those specifically can therefore be worth it.
- *Triangle*: Triangles. They represent the most basic form of a polygon.
- *Poly N*: N-vertex polygons. These shapes consist of many intersecting lines and are useful to determine how effective the renderer is at calculating anti-aliasing for paths.
- *Butterfly*, *Fish*, *Dragon*: These shapes contain various combinations of lines and mostly curve segments, making them good candidates for evaluating curve flattening performance.
- *World*: This shape consists