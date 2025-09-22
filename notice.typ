= Contribution Notice <contrib-notice>

It needs to be noted that the project of building Vello CPU is part of a bigger collaboration involving some external contributors, where another goal is to build an additional 2D renderer based on the sparse strips paradigm that utilizes the GPU instead to achieve better performance. Therefore, the description of some parts of the pipeline in @architecture of this thesis are included for the sake of understandability, but were at least partly co-implemented by other parties. Because of this, we explicitly list the core contributions that have been made specifically as part of this thesis:

- Implementing the whole rasterization stage (fine rasterization + packing), which includes
  - the `f32`-based and `u8`-based rendering pipeline.
  - support for image fills with the different interpolation modes.
  - support for linear, radial and sweep gradients.
  - support for all blend modes and compositing operators.
- Extending fearless_simd with the necessary operators to support NEON and SSE4.2 in Vello CPU.
- Rewriting the flattening, strip generation, fine rasterization and packing stages to be fully SIMD-compatible.
- Applying performance tweaks in various stages of the pipeline that have been identified as bottlenecks through profiling.
- Designing and then implementing support for multi-threading in the path rendering and rasterization stages.
- Running the performance evaluation using the Blend2D benchmark suite and interpreting the results.