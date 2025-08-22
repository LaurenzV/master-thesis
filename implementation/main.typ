= Implementation <implementation>
In this section, we will first showcase an example code snippet to demonstrate how Vello CPU's API works. Afterwards, the majority of the section will be dedicated to explaining each part of the rendering pipeline in Vello CPU. Finally we will illustrate how the pipeline was accelerated by employing SIMD and multi-threading.

== API
@api_example_Listing provides a small example that demonstrates how to use Vello CPU's Rust API for basic rendering. @api_example_result displays the final result of the code snippet.

#[
  #show figure: set block(breakable: true)

  #figure(
    block(breakable: true)[
      #set align(left)
  
      #raw(lang: "rust", read("assets/api_code.rs"))
    ],
    caption: [Example usage of Vello CPU's API.]
  ) <api_example_Listing>

  #figure(
    image("assets/api_code_result.png", width: 50%),
    caption: [The rendered result of the code in @api_example_Listing.]
  ) <api_example_result>
]


== Architecture Overview
In order to convert a vector image into a raster image, there are a lot of intermediate steps that need to be performed to arrive at the final result. While a few steps are universal and performed by nearly all renderers in some shape or form, the exact implementation of the whole rendering pipeline varies wildly across different implementations.

One of the interesting aspects of the design of Vello CPU is that it has a very modular architecture, where each step takes a specific kind of input and produces some intermediate output, which can then be consumed by the next stage in the pipeline. There are no cross-dependencies between non-consecutive stages. As will be seen in the following subsections, this property makes it very easy to explain the functionality of each module in isolation and visualize the intermediates results that are produced after passing through each stage. The stages of the rendering pipeline and their dependencies are visualized in @overview_pipeline. 

A very brief example of Vello CPU's API as well as a summary of each stage is provided below, but they will be more clearly explained in the following subsections.

#figure(
  image("assets/overview_pipeline.pdf"),
  caption: [An overview of the rendering pipeline in Vello CPU.],
  placement: auto,
) <overview_pipeline>


In the beginning, the user needs to specify the size of the drawing area in pixels.  the user has to specify a path consisting of curves and lines that they want to render. They also need to specify whether it should be filled or stroked. The only difference between the two is that stroking requires an additional step called _stroke expansion_ in the beginning, which manipulates the input path in a way such that filling the new path has the same visual effect as stroking the old one. By doing this, we can treat filled and stroked paths the same in subsequent stages.

The next stage is called _flattening_. As was mentioned in @drawing_primitives, the two basic primitives used for drawing are lines and curves. As part of this stage, the path is converted into a new representation such that all curves are replaced by a number of line segments. This is clearly a lossy operation since curves inherently cannot be represented completely accurately by just lines, but the conversion can be done in such a way that the loss of information will not be noticed in the end. The advantage of this step is that the next stage in the pipeline only will need to deal with line primitives instead of curve _and_ line primitives which greatly reduces the complexity.

After that, _tile generation_ is performed. In this stage, we conceptually segment the whole canvas into areas of size 4x4. For each path, we calculate all of the 4x4 areas that it crosses, generate a _tile_ for it and associate that tile with the given line. In the end, we sort all the generated tiles by their y and x coordinate.

The _strip generation_ stage is arguably the most crucial step in the pipeline: In this stage, we process all tiles in row-major order (this is why tile generation has a sorting step in the end) and _merge_ horizontally adjacent tiles into strips. For each pixel covered by a strip, we calculate the alpha value that is necessary to perform correct anti-aliasing. The final result is a vector of strips that sparsely encodes the rendered representation of the shape by only explicitly storing anti-aliased pixels and only storing filled areas implicitly.

In the _coarse rasterization_ stage, we split the 

== Stroke expansion

== Fine rasterization

== Packing

